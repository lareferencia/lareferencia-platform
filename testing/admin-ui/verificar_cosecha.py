"""Ejecutar únicamente sobre la copia desechable descrita en ADMIN_UI_OPERACIONES.md."""
import argparse
import getpass
import gzip
import json
import os
import secrets
import sqlite3
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

from playwright.sync_api import expect, sync_playwright


FIXTURES = Path(__file__).resolve().parents[1] / "oai-incremental/fixtures/oai-dc/baseline"
ACTION = "HARVESTING_ACTION"


class OAIHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        path = urlsplit(self.path)
        source = path.path.strip("/")
        url = f"http://127.0.0.1:{self.server.server_port}/{source}"
        params = parse_qs(path.query)
        verb = params.get("verb", [""])[0]
        if verb == "Identify":
            payload = (f"<Identify><repositoryName>{source}</repositoryName><baseURL>{url}</baseURL>"
                       "<protocolVersion>2.0</protocolVersion><adminEmail>fixture@example.invalid</adminEmail>"
                       "<earliestDatestamp>2026-01-01T00:00:00Z</earliestDatestamp><deletedRecord>persistent</deletedRecord>"
                       "<granularity>YYYY-MM-DDThh:mm:ssZ</granularity></Identify>")
        elif verb == "ListRecords":
            token = params.get("resumptionToken", [""])[0]
            pages = {"": (1, 2), "two": (3, 4), "three": (5,)}
            if token not in pages:
                self.send_error(400)
                return
            self.server.requests.append((source, token))
            if source.endswith("C") and token == "two":
                self.server.second_page.set()
                if not self.server.resume.wait(60):
                    self.send_error(504)
                    return
            records = []
            for index in pages[token]:
                metadata = self.server.records[index - 1]
                records.append(f"<record><header><identifier>oai:{source}:{index}</identifier>"
                               f"<datestamp>2026-01-01T00:00:0{index}Z</datestamp></header>"
                               f"<metadata><oai_dc:dc>{metadata}</oai_dc:dc></metadata></record>")
            next_token = {"": "two", "two": "three", "three": ""}[token]
            payload = "<ListRecords>" + "".join(records) + f"<resumptionToken>{next_token}</resumptionToken></ListRecords>"
        else:
            self.send_error(400)
            return
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        body = (f'<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
                'xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" '
                'xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">'
                f'<responseDate>{now}</responseDate><request verb="{verb}">{escape(url)}</request>{payload}</OAI-PMH>').encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/xml; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def until(read, matches, timeout=50):
    deadline = time.monotonic() + timeout
    while True:
        value = read()
        if matches(value):
            return value
        if time.monotonic() >= deadline:
            raise AssertionError(f"Tiempo agotado. Última lectura: {value!r}")
        time.sleep(.25)


def verify(args, server, page):
    origin = args.origen.rstrip("/")
    api = origin + "/api/v5"
    page.goto(origin + "/admin/login")
    page.locator('[autocomplete="username"]').fill(args.usuario)
    page.locator('[autocomplete="current-password"]').fill(os.getenv("ADMIN_TEST_PASSWORD") or getpass.getpass())
    page.locator('button[type="submit"]').click()
    page.wait_for_url("**/networks")
    prefix = "QA" + secrets.token_hex(3).upper()
    first, second, slow = [prefix + suffix for suffix in "ABC"]
    ids = {}

    def get(path):
        response = page.request.get(api + path)
        assert response.ok, (path, response.status)
        return response.json()

    def snapshots(source):
        return get(f"/networks/{ids[source]}/snapshots")["items"]

    def row(source):
        return page.get_by_role("row").filter(has=page.get_by_role("cell", name=source, exact=True))

    def submit(locator, endpoint):
        with page.expect_response(lambda r: r.request.method == "POST" and urlsplit(r.url).path.endswith(endpoint)) as result:
            locator.click()
        response = result.value
        expected = 201 if endpoint == "/networks" else 202
        assert response.status == expected, (endpoint, response.status, response.text())
        return response.json()

    def harvest(source):
        row(source).get_by_role("button", name="Ejecutar acción").click()
        page.get_by_text("Cosechar metadatos", exact=True).click()
        return submit(page.get_by_role("dialog").get_by_role("button", name="Confirmar"), "/commands")

    def batch(sources):
        for source in sources:
            row(source).get_by_role("checkbox").check()
        page.get_by_text(f"{len(sources)} fuentes seleccionadas", exact=True).locator("..").get_by_role(
            "button", name="Ejecutar acción", exact=True).click()
        dialog = page.get_by_role("dialog")
        dialog.get_by_role("combobox").click()
        page.get_by_role("option", name="Cosechar metadatos").click()
        receipt = submit(dialog.get_by_role("button", name="Ejecutar acción"), "/network-command-batches")
        print("Lote", receipt["requestId"], [(c["networkId"], c["result"]) for c in receipt["children"]], flush=True)
        assert sorted(c["networkId"] for c in receipt["children"]) == sorted(ids[s] for s in sources)
        return {c["networkId"]: c for c in receipt["children"]}

    def execution(receipt, allowed):
        assert receipt["result"] == "ACCEPTED", receipt
        group = receipt["requestId"]
        found = until(lambda: [e for e in get("/runtime/executions") if e["groupId"] == group],
                      lambda es: len(es) == 1 and es[0]["state"] in allowed)
        return found[0]

    seen = {source: set() for source in (first, second, slow)}

    def finished(source, receipt, cancelled=False):
        job = execution(receipt, {"COMPLETED", "FAILED", "CANCELLED"})
        assert job["networkId"] == ids[source] and job["finishedAt"] and job["startedAt"], job
        assert job["state"] == ("CANCELLED" if cancelled else "COMPLETED"), job
        new = [s for s in snapshots(source) if s["id"] not in seen[source]]
        assert len(new) == 1, new
        snap = new[0]
        seen[source].add(snap["id"])
        status = "HARVESTING_STOPPED" if cancelled else "HARVESTING_FINISHED_VALID"
        assert snap["networkId"] == ids[source] and snap["status"] == status and snap["endTime"], snap
        path = args.almacen / source / "snapshots" / f"snapshot_{snap['id']}" / "catalog/catalog.db"
        with sqlite3.connect(path.as_uri() + "?mode=rw", uri=True) as db:
            db.execute("pragma query_only=on")
            assert db.execute("pragma integrity_check").fetchone() == ("ok",)
            rows = db.execute("select identifier, original_metadata_hash from oai_record where deleted=0 order by identifier").fetchall()
        expected = [f"oai:{source}:{i}" for i in range(1, 6)]
        assert [identifier for identifier, _ in rows] == expected[:len(rows)] and all(h for _, h in rows), rows
        for _, digest in rows:
            xml = (args.almacen / source / "metadata").joinpath(*digest[:3].upper(), digest + ".xml.gz")
            with gzip.open(xml) as stream:
                ET.parse(stream)
        assert len(rows) == snap["size"] == (2 if cancelled else 5), (rows, snap)
        assert get(f"/networks/{ids[source]}/runtime") == []
        print(json.dumps(dict(source=source, network=ids[source], group=job["groupId"], execution=job["executionId"],
                              state=job["state"], snapshot=snap["id"], status=status, size=snap["size"], rows=len(rows))), flush=True)

    for source in (first, second, slow):
        page.goto(origin + "/admin/networks/new")
        fields = page.locator("form input[required]")
        expect(fields).to_have_count(4)
        for field, value in zip(fields.all(), [source, "Cosecha " + source, "Institución de prueba", f"http://127.0.0.1:{server.server_port}/{source}"]):
            field.fill(value)
        ids[source] = submit(page.locator('form button[type=submit]'), "/networks")["id"]
        page.wait_for_url(f"**/networks/{ids[source]}/edit")
    page.goto(origin + "/admin/networks?q=" + prefix)
    finished(first, harvest(first))
    expect(row(first).get_by_text("Cosecha terminada", exact=True)).to_be_visible(timeout=20000)
    receipt = harvest(slow)
    assert server.second_page.wait(20), "El harvester no solicitó la segunda página"
    execution(receipt, {"RUNNING"})
    assert snapshots(slow)[0]["status"] == "HARVESTING"
    queued = harvest(slow)
    assert execution(queued, {"QUEUED"})["startedAt"] is None
    row(slow).get_by_role("button", name="Cancelar acciones").click(timeout=20000)
    cancelled = submit(page.get_by_role("dialog").get_by_role("button", name="Cancelar operaciones"), "/commands")
    assert cancelled["result"] == "ACCEPTED" and cancelled["command"] == "CANCEL_ALL"
    server.resume.set()
    finished(slow, receipt, cancelled=True)
    unstarted = execution(queued, {"CANCELLED"})
    assert unstarted["startedAt"] is None and unstarted["finishedAt"]
    assert len(snapshots(slow)) == 1
    print("En cola", unstarted["groupId"], unstarted["executionId"], "CANCELLED sin iniciar", flush=True)
    assert [token for source, token in server.requests if source == slow] == ["", "two"]
    expect(row(slow).get_by_text("Detenida", exact=True).first).to_be_visible(timeout=20000)
    batch_receipts = batch([first, second])
    for source in (first, second):
        finished(source, batch_receipts[ids[source]])
    print("Lote de dos cosechas terminado", flush=True)
    # Preparar un rechazo por política de red exclusivamente en la nueva fuente de prueba.
    csrf = get("/auth/csrf")["token"]
    disabled = page.request.put(f"{api}/networks/{ids[second]}/actions/{ACTION}", headers={"X-XSRF-TOKEN": csrf},
                                data={"enabled": False, "scheduleEnabled": False, "configuration": {}})
    assert disabled.ok, disabled.text()
    expect(page.get_by_text("2 aceptadas · 0 rechazadas")).to_be_visible()
    mixed = batch([first, second])
    assert mixed[ids[second]]["result"] == "REJECTED", mixed
    finished(first, mixed[ids[first]])
    assert {s["id"] for s in snapshots(second)} == seen[second]
    print("Lote mixto:", second, mixed[ids[second]]["message"], flush=True)
    expect(page.get_by_role("dialog").get_by_text(second, exact=True)).to_be_visible()
    expect(page.get_by_role("dialog").get_by_text(mixed[ids[second]]["message"], exact=True)).to_be_visible()
    page.get_by_role("dialog").get_by_role("button", name="Cerrar").click()
    page.reload()
    for source in (first, second):
        expect(row(source).get_by_text("Cosecha terminada", exact=True)).to_be_visible()
    expect(row(slow).get_by_text("Detenida", exact=True).first).to_be_visible()
    assert [token for source, token in server.requests if source == first] == ["", "two", "three"] * 3
    assert [token for source, token in server.requests if source == second] == ["", "two", "three"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("origen")
    parser.add_argument("usuario")
    parser.add_argument("almacen", type=Path)
    args = parser.parse_args()
    if urlsplit(args.origen).hostname not in {"127.0.0.1", "localhost"}:
        parser.error("Esta prueba utiliza un harvester local y un proveedor OAI en loopback.")
    args.almacen = args.almacen.resolve(strict=True)
    with ThreadingHTTPServer(("127.0.0.1", 0), OAIHandler) as server, sync_playwright() as pw:
        server.requests = []
        server.second_page = threading.Event()
        server.resume = threading.Event()
        server.records = ["".join(ET.tostring(field, encoding="unicode") for field in ET.parse(file).find("metadata"))
                          for file in sorted(FIXTURES.glob("record-*.xml"))]
        threading.Thread(target=server.serve_forever, daemon=True).start()
        browser = pw.chromium.launch(channel="chrome")
        try:
            verify(args, server, browser.new_page(locale="es-ES"))
        finally:
            server.resume.set()
            server.shutdown()
            browser.close()


if __name__ == "__main__":
    main()
