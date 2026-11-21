import unittest

from normalize_rights import normalize_rights
from rights_catalog import FAMILIES


class RightsContractTests(unittest.TestCase):
    def test_catalog(self):
        self.assertEqual(len(set(FAMILIES)), 22)
        examples = {
            "The MIT License": "MIT", "Apache-2.0": "Apache", "GNU GPL 3.0": "GPL",
            "BSD-3-Clause license": "BSD", "GNU Free Documentation License": "GFDL",
            "https://www.gnu.org/licenses/lgpl-3.0.html": "LGPL",
            "http://opensource.org/licenses/osl-3.0.php": "OSL",
            "Open Data Commons Attribution License (ODC-By) v1.0": "ODC-BY",
            "Open Database License (ODC-ODbL)": "ODbL", "PDDL v1.0": "PDDL",
            "Licencia RepHip": "INSTITUTIONAL", "Publisher's Bespoke License": "OTHER-LICENSE",
            "Creative Commons": "CC-UNSPECIFIED", "CC0": "CC0", "CC-PDM": "CC-PDM",
        }
        for value, family in examples.items():
            with self.subTest(value=value):
                self.assertEqual(normalize_rights(value)["licenses"][0]["family"], family)

    def test_edition(self):
        for value, expected in [
            ("https://creativecommons.org/licenses/by-nc-sa/2.5/ar/", ("2.5", "AR", "AR")),
            ("CC BY-NC 4.0", ("4.0", None, None)),
            ("https://creativecommons.org/licenses/by/3.0/igo/", ("3.0", None, "IGO")),
            ("https://creativecommons.org/licenses/by/4.0/", ("4.0", None, "international")),
        ]:
            lic = normalize_rights(value)["licenses"][0]
            self.assertEqual((lic["version"], lic["country"], lic["jurisdiction"]), expected)

    def test_reviewed_non_cc(self):
        for label in ("Licença Comum", "Domini públic", "codi: Mozilla (c) autor",
                      "http://www.gnu.org/licenses/licenses.es.html#GPL"):
            with self.subTest(label=label):
                self.assertEqual(normalize_rights(label)["licenses"], [])
        row = normalize_rights("codi: AGPL (c) autor")
        self.assertEqual(row["licenses"][0]["scope"], "code")
        self.assertEqual(row["copyright"], "(c) autor")
        self.assertEqual(normalize_rights("GPL 3.0+")["licenses"][0]["modifier"], "or-later")
        self.assertEqual(normalize_rights("Institutional licence")["licenses"][0]["family"],
                         "INSTITUTIONAL")

    def test_elsevier_license_and_notice(self):
        row = normalize_rights("© Elsevier 2016 Inc. Under an Elsevier user license")
        self.assertEqual(row["copyright"], "© Elsevier 2016 Inc.")
        self.assertEqual(row["licenses"][0]["instrument"], "Elsevier User License")
        self.assertIsNone(row["licenses"][0]["version"])
        self.assertEqual(normalize_rights("https://www.elsevier.com/tdm/userlicense/1.0/")["licenses"], [])

    def test_context(self):
        row = normalize_rights("codi: GPL (c) Autor, 2025")
        self.assertEqual(row["licenses"][0]["scope"], "code")
        self.assertEqual(row["copyright"], "(c) Autor, 2025")
        result = normalize_rights("https://rightsstatements.org/vocab/InC/1.0/")
        self.assertEqual(result["licenses"][0], dict(family="RIGHTSSTATEMENTS", kind="rights_statement",
                         subtype="InC", code="InC", version="1.0", country=None, jurisdiction=None))
        for url in ("https://rightsstatements.org/", "https://rightsstatements.org/vocab/Unknown/1.0/",
                    "https://other-rightsstatements.org/vocab/InC/1.0/"):
            self.assertEqual(normalize_rights(url)["licenses"], [])
        self.assertEqual(normalize_rights("GPL-3.0-or-later")["licenses"][0]["modifier"], "or-later")
        self.assertEqual(normalize_rights("unknown")["licenses"], [])
        self.assertIsNone(normalize_rights("open access"))


if __name__ == "__main__":
    unittest.main()
