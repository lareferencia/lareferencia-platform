"""Check the mixed OAI fixture through the dashboard gateway with a DASHBOARD session."""
import argparse
import getpass
import os
from pathlib import Path

from playwright.sync_api import expect, sync_playwright


# Expected outcomes are independent of the rule IDs assigned on import.
CASES = {
    "clean": (True, set()),
    "optional-only": (True, {"QA Type"}),
    "missing-title": (False, {"QA Title"}),
    "wrong-language": (False, {"QA Language"}),
    "missing-fields": (False, {"QA Title", "QA Language", "QA Type"}),
    "mixed-values": (True, set()),
}


def read(page, path):
    response = page.request.get(path)
    assert response.ok, (response.status, path)
    return response.json()


def check_records(page, report, rules):
    records = read(page, report + "/records?pageSize=25")
    actual = {row["identifier"]: (row["isValid"], {rules[key]["name"] for key in row["invalidRulesID"]})
              for row in records["content"]}
    assert records["totalElements"] == len(CASES)
    assert actual == {"oai:qa-mixed:" + slug: outcome for slug, outcome in CASES.items()}
    for validity in (True, False):
        query = "?is_valid=" + str(validity).lower()
        filtered = read(page, report + query)
        rows = read(page, report + "/records" + query)
        wanted = {"oai:qa-mixed:" + slug for slug, (valid, _) in CASES.items() if valid == validity}
        assert filtered["size"] == rows["totalElements"] == len(wanted)
        assert {row["identifier"] for row in rows["content"]} == wanted


def screenshot(page, output, name):
    if output:
        output.mkdir(parents=True, exist_ok=True)
        page.screenshot(path=output / (name + ".png"), full_page=True, animations="disabled")


def check_snapshot(page, origin, snapshot, detailed, output):
    report = f"{origin}/api/v5/dashboard/validation/source/QAMIX/{snapshot}"
    summary = read(page, report)
    assert (summary["size"], summary["validSize"], summary["transformedSize"]) == (6, 3, 0)
    rules = summary["rulesByID"]
    assert {rule["name"] for rule in rules.values()} == {"QA Title", "QA Language", "QA Type"}
    for rule in rules.values():
        assert (rule["validCount"], rule["invalidCount"]) == (4, 2)
        assert rule["occurrenceCaptureEnabled"] == (detailed and rule["name"] != "QA Title")
    check_records(page, report, rules)
    language = next(key for key, rule in rules.items() if rule["name"] == "QA Language")
    for group, expected in [("valid", {"en": 2, "es": 2}),
                            ("invalid", {"xx": 1, "zz": 1, "no_occurrences_found": 1})]:
        values = read(page, f"{report}/frequencies/{language}/{group}")
        assert {v["value"]: v["count"] for v in values["content"]} == (expected if detailed else {})
        assert values["totalOccurrences"] == (sum(expected.values()) if detailed else 0)
    # The mixed record passes the language rule while contributing a rejected value.
    passed = read(page, f"{report}/frequencies/{language}/invalid?valid_rules={language}")
    assert passed["content"] == ([{"value": "zz", "count": 1}] if detailed else [])

    page.goto(f"{origin}/dashboard/es/QAMIX/validation/{snapshot}")
    table = page.get_by_role("table", name="Reglas", exact=True)
    expect(table.get_by_text("Sin recuento", exact=True)).to_have_count(1 if detailed else 3)
    expect(table.get_by_role("link", name="Ver ocurrencias", exact=True)).to_have_count(2 if detailed else 0)
    records = page.get_by_role("table", name="Registros seleccionados")
    for slug, (valid, _) in CASES.items():
        row = records.get_by_role("row").filter(has=page.get_by_role("button", name="oai:qa-mixed:" + slug, exact=True))
        expect(row.get_by_text("Válido" if valid else "Inválido", exact=True)).to_be_visible()
    screenshot(page, output, "mixed-detailed" if detailed else "mixed-summary")
    if detailed:
        table.get_by_role("row").filter(has_text="QA Language").get_by_text("Ver ocurrencias").click()
        dialog = page.get_by_role("dialog")
        expect(dialog.get_by_text("Campo ausente", exact=True)).to_be_visible()
        expect(dialog.get_by_text("zz", exact=True)).to_be_visible()
        if output:
            dialog.screenshot(path=output / "mixed-language.png")
        dialog.get_by_role("button", name="Cerrar").click()
    print(f"QAMIX #{snapshot}: six records, all rule outcomes, filters, frequencies and actions verified (detailed={detailed}).")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("origin", help="Dashboard gateway origin")
    parser.add_argument("detailed_snapshot", type=int)
    parser.add_argument("--summary-snapshot", type=int)
    parser.add_argument("--user", default="dashboard")
    parser.add_argument("--screenshots", type=Path)
    args = parser.parse_args()
    origin = args.origin.rstrip("/")
    password = os.environ.get("DASHBOARD_TEST_PASSWORD") or getpass.getpass()
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        page = browser.new_page(locale="es-ES", timezone_id="Europe/Madrid", viewport={"width": 1440, "height": 1000})
        page.goto(origin + "/dashboard/es/")
        page.get_by_label("Usuario").fill(args.user)
        page.get_by_label("Contraseña").fill(password)
        page.locator('button[type="submit"]').click()
        expect(page.get_by_role("combobox", name="Repositorio")).to_be_visible()
        check_snapshot(page, origin, args.detailed_snapshot, True, args.screenshots)
        if args.summary_snapshot is not None:
            check_snapshot(page, origin, args.summary_snapshot, False, args.screenshots)
        browser.close()


if __name__ == "__main__":
    main()
