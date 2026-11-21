import unittest

from cc_license_fragments import resolve_pending_cc, apply_structural_repairs, apply_url_priority, apply_ordered_name, declaration_fallback, detect, fallback, reference_subtype, review_reference


class LicenseFragmentTests(unittest.TestCase):
    def test_codes_and_translated_names(self):
        for fragment in ("bYnCnD", "BY / NC / ND", "CC BY NC ND", "Creative Commons by-nc-nd",
                         "Reconocimiento–No Comercial–Sin Derivadas",
                         "Atribuição–Não Comercial–Sem Derivações",
                         "Attribution-NonCommercial-NoDerivatives"):
            value = "© Revista (" + fragment + ")"
            with self.subTest(fragment=fragment):
                result = detect(value)
                self.assertEqual(result["creativeCommons"]["family"], "CC-BY-NC-ND")
                self.assertEqual(result["copyright"], "© Revista")
                self.assertEqual(result["ccEvidence"][0]["fragment"], fragment)

    def test_specific(self):
        for value in ("CC BY 4.0 DEED Attribution 4.0 International",
                      "CC BY Atribución Internacional 4.0",
                      "CC BY (https://creativecommons.org/licenses/by/4.0/)"):
            self.assertEqual(detect(value)["creativeCommons"]["specific"], "CC-BY-4.0")
        result = detect("Declaración: Reconocimiento–No Comercial–Compartir Igual 4.0")
        self.assertEqual(result["creativeCommons"]["specific"], "CC-BY-NC-SA")
        self.assertEqual(result["creativeCommons"]["version"], "4.0")
        self.assertEqual(detect("https://creativecommons.org/licenses/by nc nd/4.0")["creativeCommons"]["specific"],
                         "CC-BY-NC-ND-4.0")

    def test_unspecified_and_fallback(self):
        self.assertIsNone(fallback("Creative Commons")["creativeCommons"]["family"])
        for value in ("https://creativecommons.org/", "sense cap llicència Creative Commons",
                      "https://creativecommons.org/choose/zero/", "Creative Commons 4.0",
                      "AtribuiçãoNãoComercial (CC BY-ND)"):
            self.assertIsNone(fallback(value))
        for value, expected in (
            ("Creative Commons Public Domain Mark (PDM)", "CC-PDM"),
            ("https://creativecommons.org.//licenses/by-nc-sa/3.0/ec/", "CC-BY-NC-SA-3.0-EC"),
            ("\u200bhttp://creativecommons.org/licenses/by-nc-nd/4.0\u200b", "CC-BY-NC-ND-4.0"),
            ("© 2020 AtribuiçãoNãoComercial 4.0 Internacional", "CC-BY-NC-4.0"),
        ):
            result = fallback(value)
            self.assertEqual(result["creativeCommons"]["specific"], expected)
            for hit in result["ccEvidence"]:
                self.assertEqual(value[hit["start"]:hit["end"]], hit["fragment"])

    def test_v9_declarations_and_references(self):
        for value in ("Atribución/Reconocimiento-NoComercial-SinDerivados 4.0 Internacional",
                      "http://creativecommons.org/licencias/by-nc-nd/4.0/",
                      "http://creativecommons.org/licenses/bync-nd/4.0/"):
            self.assertEqual(detect(value)["creativeCommons"]["specific"], "CC-BY-NC-ND-4.0")
        self.assertEqual(reference_subtype("httpss://creativecommons.org/choose/zero/?lang=ca"), "cc0_selector")
        self.assertEqual(reference_subtype("https://creativecommons.org"), "cc_homepage")
        self.assertIsNone(reference_subtype("https://creativecommons.org.example.net"))
        generic = fallback("Copyright (c) 2025 Licença Creative Commons")
        self.assertEqual(generic["copyright"], "Copyright (c) 2025")
        self.assertIsNone(generic["creativeCommons"]["family"])
        versioned = fallback("Este trabalho está sob uma Licença Creative Commons 4.0. Fonte: PDF do artigo.")
        self.assertEqual(versioned["creativeCommons"]["version"], "4.0")
        for value in ("Copyright (c) 2019 Creative Commons",
                      "http://creativecommons.or/licencces/by-nc-nd/.25/pe/",
                      "Atribuição-NãoComercial-SemDerivações 4.0 Internacional (CC BY-ND-ND 4.0)"):
            self.assertIsNone(detect(value) or fallback(value))

    def test_v10_fragments(self):
        for label in ("Attibution-NonComercial-NoDerivatives", "Attribuzione-Non commerciale-Non opere derivate",
                      "Aitortu-EzKomertziala-LanEratorririkGabe"):
            self.assertEqual(detect(label)["creativeCommons"]["family"], "CC-BY-NC-ND")
        url = "https://creativecommons.org/licenses/by/4.0/deed.ca"
        self.assertEqual(detect(url + url)["creativeCommons"]["specific"], "CC-BY-4.0")
        cc = detect("https://creativecommons.org/licenses/by-nc-nd/4.241")["creativeCommons"]
        self.assertEqual(cc["specific"], "CC-BY-NC-ND")
        self.assertIsNone(cc["version"])
        scoped = declaration_fallback("All site content, except where otherwise noted, is licensed under a Creative Commons Attribution 3.0 License.")
        self.assertIn("except where otherwise noted", scoped["scope"])
        self.assertEqual(scoped["creativeCommons"]["version"], "3.0")
        generic = declaration_fallback("La nueva colección está bajo una licencia Creative Commons 4.0.")
        self.assertIsNone(generic["creativeCommons"]["family"])
        self.assertEqual(generic["creativeCommons"]["version"], "4.0")
        self.assertIsNone(declaration_fallback("Esta obra no está bajo una licencia Creative Commons."))
        self.assertEqual(reference_subtype("ejemplo: " + url), "cc_example")

    def test_v11_review(self):
        named = "Atribuição-NãoComercial-SemDerivações 4.0 Internacional"
        candidate = review_reference(named + " (CC BY-ND-ND 4.0)")
        self.assertEqual(candidate["subtype"], "cc_name_candidate")
        self.assertEqual(candidate["nameInterpretation"]["specific"], "CC-BY-NC-ND-4.0")
        self.assertIsNone(candidate["creativeCommons"]["family"])
        decision = review_reference(named + " (CC BY-SA 3.0)")
        self.assertEqual(decision["creativeCommons"]["family"], "CC-BY-SA")
        self.assertEqual(decision["creativeCommons"]["version"], "3.0")
        self.assertIsNone(decision["creativeCommons"]["jurisdiction"])
        self.assertIsNone(review_reference("http://creativecommons.org/licenses/by-nc-nc/4.0/"))
        self.assertEqual(review_reference("http://creativecommons.org/li censes/by/4.0/")["creativeCommons"]["specific"], "CC-BY-4.0")
        self.assertEqual(review_reference("https://creativecommons.org/licenses/4.0/")["subtype"], "cc_version_only_url")
        scoped = review_reference("CC-BY-NC-ND [només pel text] ; CC-BY [per les imatges]")
        self.assertEqual([s["family"] for s in scoped["scopedLicenses"]], ["CC-BY-NC-ND", "CC-BY"])

    def test_ordered_names(self):
        for text, family in (
            ("Atrib. Não comercial", "CC-BY-NC"),
            ("Atribución: No comercial y sin obras derivadas", "CC-BY-NC-ND"),
            ("Attribution, non-commercial and share alike", "CC-BY-NC-SA"),
            ("Attribuzione - Non commerciale e Non opere derivate", "CC-BY-NC-ND"),
            ("Attribution – Pas d'utilisation commerciale et Sans modification", "CC-BY-NC-ND"),
            ("Atribuição-NãoComercial-SemDerivações (CC BY-ND-ND)", "CC-BY-NC-ND"),
            ("Atrib. Não comercial (CC BY-SA 3.0)", "CC-BY-SA"),
            ("Uso no comercial", None), ("Atrib.", None),
            ("Atribución a los autores. Esta entidad es no comercial", None),
            ("Atrib. No comercial. Consulte las condiciones adicionales.", None),
        ):
            with self.subTest(text=text):
                row = dict(value=text, creativeCommons=dict(family=None))
                apply_ordered_name(row)
                self.assertEqual(row["creativeCommons"]["family"], family)

    def test_url_priority(self):
        for value, expected in (
            ("CC BY-SA (https://creativecommons.org/licenses/by/4.0/)", "CC-BY-4.0"),
            ("https://creativecommons.org/licenses/by nc nd/4.0", "CC-BY-NC-ND-4.0"),
            ("https:/creativecommons.org/licenses/by/4.0/", "CC-BY-4.0"),
            ("https://creativecommons.org/licenses/by4.0/", "CC-BY-4.0"),
            ("cc by-nc https://creativecommons.org/li censes/by-nc/3.0/", "CC-BY-NC-3.0"),
            ("cc-by-nd-nc (c) Autor", "CC-BY-NC-ND"),
            ("cc-by-nc-nc (c) Autor", None),
            ("CC BY https://creativecommons.org/licenses/", "CC-BY"),
            ("ejemplo: https://creativecommons.org/licenses/by/4.0/", None),
            ("https://creativecommons.org/licenses/by/4.0/ https://creativecommons.org/licenses/by-sa/4.0/", None),
        ):
            with self.subTest(value=value):
                row = dict(value=value, category="NON_CC", subtype="cc_reference_unresolved",
                           creativeCommons=dict.fromkeys(("specific", "family", "version", "jurisdiction")))
                apply_url_priority(row)
                self.assertEqual(row["creativeCommons"]["specific"], expected)

    def test_structural_repairs(self):
        for value, expected in (
            ("ht6tps://creativecommons.org/licenses/by/4.0/", "CC-BY-4.0"),
            ("http://https://creativecommons.org/licenses/by/4.0/", "CC-BY-4.0"),
            ("http://creativecommons.org/licenses/by-nc-nd-2.5/ar/", "CC-BY-NC-ND-2.5-AR"),
            ("https://creativecommons.org/lincenses/by-nd/4.0/", "CC-BY-ND-4.0"),
            ("https://creativecommons.org/licenses/by%2Dnc/4.0/", "CC-BY-NC-4.0"),
            ("http://creativecommons.org/licenses/by/nc-nd/2.5/co/", "CC-BY-NC-ND-2.5-CO"),
            ("Licencia de reconocimiento de Creative Commons", "CC-BY"),
            ("Una Llicència Creative Commons Atribució 4.0 Internacional.", "CC-BY-4.0"),
            ("Licença pública Creative Commons Licença 4.0", None),
        ):
            with self.subTest(value=value):
                row = dict(value=value, category="NON_CC")
                apply_structural_repairs(row)
                self.assertEqual(row["category"], "CC")
                self.assertEqual(row["creativeCommons"]["specific"], expected)
                if expected is None:
                    self.assertEqual(row["creativeCommons"]["version"], "4.0")
        for value in ("by-nc-", "by-nc-ns", "by-n-nd", "by-nd-nd", "by-cc-by"):
            row = dict(value=f"ttp://creativecommons.org/lincenses/{value}/4.0/", category="NON_CC")
            apply_structural_repairs(row)
            self.assertEqual(row["category"], "NON_CC")

    def test_pending_declarations(self):
        def resolve(value):
            row = dict(value=value, category="NON_CC", subtype="cc_reference_unresolved")
            resolve_pending_cc(row)
            return row

        for url, specific in (
            ("http://creativecommons.org/licenses/by-nc-nd/40/es/", "CC-BY-NC-ND"),
            ("https://creativecommons.org/by/4.0/", "CC-BY-4.0"),
            ("http://creativecommons.org/licenses/by-nc-nd/3.0/es/:", "CC-BY-NC-ND-3.0-ES"),
            ("CC BY-NC4.0", "CC-BY-NC"),
            ("Published under the CC BY-SAlicense", "CC-BY-SA"),
        ):
            with self.subTest(value=url):
                self.assertEqual(resolve(url)["creativeCommons"]["specific"], specific)
        broken = resolve("http://creativecommons.org/licenses/by-nc-nd/40/es/")["creativeCommons"]
        self.assertIsNone(broken["version"])
        self.assertIsNone(broken["jurisdiction"])
        self.assertEqual(resolve("CC BY-NC4.0")["creativeCommons"]["version"], "4.0")
        self.assertEqual(resolve("http://www.creativecommons.org.ar/licencias.html")["subtype"], "cc_directory")
        pair = resolve("Presentació publicada sota llicència CC-BY 4.0. Vídeo publicat sota llicència CC-BY-NC-ND 4.0.")
        self.assertEqual([(s["scope"], s["family"]) for s in pair["scopedLicenses"]],
                         [("Presentació", "CC-BY"), ("Vídeo", "CC-BY-NC-ND")])
        for code in ("by-nc-ns", "by-n-nd", "by-nd-nd", "by-nc-"):
            self.assertEqual(resolve(f"http://creativecommons.org/licenses/{code}/40/")["subtype"],
                             "cc_reference_unresolved")

    def test_ambiguous_or_conflicting(self):
        for value in ("published by the authors", "uso no comercial", "Creative Commons",
                      "Open Data Commons Attribution License (ODC-By) v1.0",
                      "Attribution–ShareAlike (CC BY-ND)", "CC BY-NC 4.0 (CC BY-NC 3.0)",
                      "ejemplo: https://creativecommons.org/licenses/by-nc/4.0/",
                      "not licensed under CC BY", "CC BY-ND-ND", "https://example.org/cc-by-nc.pdf"):
            with self.subTest(value=value):
                self.assertIsNone(detect(value))


if __name__ == "__main__":
    unittest.main()
