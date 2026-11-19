"""Prueba de la acción de indexación sobre PA #4 en la copia de ADMIN_UI_INDEXACION.md."""
import argparse
import getpass
import json
import os
import sqlite3
import time
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from urllib.request import urlopen

from playwright.sync_api import sync_playwright


def verify(page, args):
    origin = args.origen.rstrip("/")
    solr = args.solr.rstrip("/")
    assert all(urlsplit(url).hostname in {"127.0.0.1", "localhost"} for url in (origin, solr))
    action = "FRONTEND_INDEXING_ACTION"
    snapshots = "/networks/1/snapshots/latest?status=valid"

    def search(q, **params):
        query = urlencode(dict(q=q, fq="network_acronym_str:PA", wt="json", **params))
        with urlopen(solr + "/select?" + query, timeout=15) as response:
            return json.load(response)["response"]

    def get(path):
        response = page.request.get(origin + "/api/v5" + path)
        assert response.ok, (path, response.status)
        return response.json()

    dbpath = args.almacen.resolve() / "PA/snapshots/snapshot_4/validation/validation.db"
    with sqlite3.connect(dbpath.as_uri() + "?mode=ro", uri=True) as db:
        assert db.execute("pragma integrity_check").fetchone() == ("ok",)
        expected = {row[0] for row in db.execute(
            "select identifier from record_validation where is_valid=1 and deleted=0")}
    assert expected
    assert search("*:*", rows=0)["numFound"] == 0, "Esta prueba requiere un índice PA vacío"

    page.goto(origin + "/admin/login")
    page.locator('[autocomplete="username"]').fill(args.usuario)
    page.locator('[autocomplete="current-password"]').fill(os.getenv("ADMIN_TEST_PASSWORD") or getpass.getpass())
    page.locator('button[type="submit"]').click()
    page.wait_for_url("**/networks")
    before = get(snapshots)
    assert before["id"] == 4 and before["validSize"] == len(expected), before
    assert get("/worker-configurations/frontendIndexer")["configuration"]["solrUrl"] == solr

    page.goto(origin + "/admin/networks?acronym=PA")
    row = page.get_by_role("row").filter(has=page.get_by_role("cell", name="PA", exact=True))
    row.get_by_role("button", name="Ejecutar acción").click()
    page.get_by_text("Indexar en el buscador", exact=True).click()
    with page.expect_response(lambda r: r.request.method == "POST" and
                              urlsplit(r.url).path == "/api/v5/networks/1/commands") as sent:
        page.get_by_role("dialog").get_by_role("button", name="Confirmar").click()
    response = sent.value
    assert response.status == 202 and response.request.post_data_json["actionName"] == action
    receipt = response.json()
    assert receipt["result"] == "ACCEPTED", receipt
    print("Solicitud", receipt["requestId"], "elegibles", len(expected), flush=True)
    deadline = time.monotonic() + 600
    while True:
        jobs = [e for e in get("/runtime/executions") if e["groupId"] == receipt["requestId"]]
        if jobs and all(e["finishedAt"] for e in jobs):
            break
        if time.monotonic() >= deadline:
            raise TimeoutError(jobs)
        time.sleep(1)
    assert len(jobs) == 1 and jobs[0]["networkId"] == 1 and jobs[0]["state"] == "COMPLETED", jobs
    after = get(snapshots)
    result = after["indexingResults"]["frontendIndexerWorker"]
    assert after["id"] == 4 and after["indexStatus"] == result["status"] == "INDEXED", after
    assert result["actionName"] == action and result["finishedAt"] and not result["error"], result
    assert result != before["indexingResults"].get("frontendIndexerWorker"), result
    page.reload()
    row.get_by_role("button", name="Indexación del snapshot #4: OK. Ver resultados").click()
    dialog = page.get_by_role("dialog")
    worker = dialog.get_by_role("row").filter(has_text="Indexación del buscador")
    worker.get_by_text("OK", exact=True).wait_for()

    found = search("*:*", fl="id,oai_identifier_str,title", sort="id asc", rows=len(expected))
    docs = found["docs"]
    observed = {doc["oai_identifier_str"] for doc in docs}
    assert found["numFound"] == len(docs) == len(expected) and observed == expected, (
        found["numFound"], len(expected), sorted(expected - observed)[:5], sorted(observed - expected)[:5])
    sample = next(doc for doc in docs if doc.get("title"))
    match = search("{!term f=oai_identifier_str}" + sample["oai_identifier_str"], fl="id", rows=2)
    assert match["numFound"] == 1 and match["docs"][0]["id"] == sample["id"]
    title = search("{!field f=title}" + sample["title"], fl="id", rows=len(expected))
    assert sample["id"] in {d["id"] for d in title["docs"]}
    assert search("{!term f=oai_identifier_str}oai:prueba:inexistente", rows=0)["numFound"] == 0
    print(json.dumps(dict(job=jobs[0]["state"], started=jobs[0]["startedAt"], finished=jobs[0]["finishedAt"],
                          result=result, found=len(docs), sample=sample, titleHits=title["numFound"]),
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origen", required=True)
    parser.add_argument("--solr", required=True, help="URL del core biblio desechable")
    parser.add_argument("--almacen", type=Path, required=True)
    parser.add_argument("--usuario", required=True)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        try:
            verify(browser.new_page(locale="es-ES"), parser.parse_args())
        finally:
            browser.close()
