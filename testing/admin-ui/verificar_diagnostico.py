"""Recorrido de lectura sobre la copia de desarrollo descrita en docs/ADMIN_UI_VERIFICACION.md."""
import argparse
import getpass
import os
import re

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("origen", help="Origen del harvester que sirve el admin compilado")
    parser.add_argument("usuario", help="Administrador de la copia de desarrollo")
    args = parser.parse_args()
    password = os.getenv("ADMIN_TEST_PASSWORD") or getpass.getpass()
    base = args.origen.rstrip("/") + "/admin"
    report = base + "/networks/33/diagnostics"
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="chrome")
        page = browser.new_page(locale="es-ES")
        page.goto(base + "/login")
        page.locator('[autocomplete="username"]').fill(args.usuario)
        page.locator('[autocomplete="current-password"]').fill(password)
        page.locator('button[type="submit"]').click()
        page.wait_for_url("**/networks")

        reads = []
        page.on("request", lambda request: reads.append(request.url))
        with page.expect_response(lambda r: "/diagnostics/summary/query" in r.url) as summary:
            page.goto(report)
        assert summary.value.ok and summary.value.json()["size"] == 4000
        expect(page.get_by_role("heading", name="AREANDINA", exact=True)).to_be_visible()

        with page.expect_response(lambda r: "/occurrences/query" in r.url) as frequencies:
            page.get_by_role("button", name="Ocurrencias", exact=True).first.click()
        assert frequencies.value.ok
        page.get_by_role("button", name="Cerrar", exact=True).click()
        page.get_by_role("button", name="Detalle", exact=True).first.click()
        assert not any("/diagnostics/records/metadata?" in url for url in reads)
        with page.expect_response(lambda r: "/diagnostics/records/metadata?" in r.url) as xml:
            page.get_by_role("tab", name="XML publicado").click()
        assert xml.value.ok and b"<" in xml.value.body()
        page.get_by_role("button", name="Cerrar", exact=True).click()

        field = page.get_by_label("Buscar identificador")
        reads.clear()
        field.press_sequentially("oai:")
        assert not any("/diagnostics/" in url for url in reads)
        with page.expect_response(lambda r: "/records/query" in r.url) as records, \
                page.expect_response(lambda r: "/summary/query" in r.url) as filtered:
            field.press("Enter")
        assert records.value.ok and filtered.value.ok
        assert records.value.json()["totalElements"] == filtered.value.json()["size"] == 4000
        page.reload()
        expect(field).to_have_value("oai:")
        page.go_back()
        expect(field).to_have_value("")

        # Fuerza un error de transporte solo en la tabla. El resumen usa el servidor real.
        pattern = "**/snapshots/6/diagnostics/records/query"
        page.route(pattern, lambda route: route.fulfill(status=503, body=""))
        page.goto(report + "?snapshot=6&identifier=oai%3A&page=1")
        expect(page.get_by_text("No se pudieron leer los registros.")).to_be_visible(timeout=15000)
        expect(page.get_by_text("No hay registros para estos filtros.")).to_have_count(0)
        page.unroute(pattern)
        with page.expect_response(lambda r: "/records/query" in r.url) as retry:
            page.get_by_role("button", name="Reintentar").click()
        assert retry.value.ok
        query = retry.value.request.post_data_json
        assert query["page"] == 1 and query["filters"] == [
            {"field": "IDENTIFIER", "operator": "CONTAINS", "value": "oai:"}
        ]
        expect(page.get_by_role("button", name="Detalle", exact=True).first).to_be_visible()

        reads.clear()
        page.goto(report + "?snapshot=1")
        expect(page.get_by_text("Snapshot no disponible para esta fuente.")).to_be_visible()
        assert not any(re.search(r"/snapshots/1/diagnostics/", url) for url in reads)
        browser.close()
    print("Diagnóstico, frecuencias, XML, búsqueda, historial, reintento y pertenencia verificados.")


if __name__ == "__main__":
    main()
