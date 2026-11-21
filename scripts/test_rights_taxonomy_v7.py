import unittest

from normalize_rights import normalize_rights


class TaxonomyV7Tests(unittest.TestCase):
    def classify(self, value):
        return normalize_rights(value)['licenses']

    def test_domain_instruments_and_generic_statement(self):
        for label, instrument in [('CC0','CC0'), ('PDDL v1.0','PDDL'), ('Domini públic','UNSPECIFIED')]:
            with self.subTest(label=label):
                entry = self.classify(label)[0]
                self.assertEqual((entry['family'], entry['instrument']), ('PUBLIC-DOMAIN', instrument))

    def test_scoped_license_and_copyright(self):
        entries = self.classify('codi: AGPL (c) autor')
        self.assertEqual([(e['family'], e['instrument']) for e in entries],
                         [('SOFTWARE','AGPL'), ('Copyright','NOTICE')])
        self.assertEqual(entries[0]['scope'], 'code')

    def test_rights_statement_edition(self):
        entry = self.classify('https://rightsstatements.org/vocab/InC/1.0/')[0]
        self.assertEqual((entry['family'],entry['instrument'],entry['version']), ('RE','InC','1.0'))

    def test_unspecified_and_unresolved(self):
        self.assertEqual(self.classify('Licencia institucional')[0]['instrument'], 'UNSPECIFIED')
        self.assertEqual(self.classify('Licença Comum'), [])
