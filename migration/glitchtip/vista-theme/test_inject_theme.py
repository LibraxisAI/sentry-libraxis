import unittest

from inject_theme import THEME_LINK, inject


class InjectThemeTests(unittest.TestCase):
    def test_inserts_once_after_generated_stylesheet(self):
        html = '<head><link rel="stylesheet" href="static/styles-ABC123.css"></head>'
        themed = inject(html)
        self.assertIn('styles-ABC123.css">\n    ' + THEME_LINK, themed)
        self.assertEqual(themed.count(THEME_LINK), 1)
        self.assertEqual(inject(themed), themed)

    def test_rejects_changed_or_ambiguous_upstream_html(self):
        for html in (
            '<head><link rel="stylesheet" href="static/other.css"></head>',
            '<link rel="stylesheet" href="static/styles-A.css">'
            '<link rel="stylesheet" href="static/styles-B.css">',
            THEME_LINK + THEME_LINK,
        ):
            with self.subTest(html=html), self.assertRaises(ValueError):
                inject(html)


if __name__ == "__main__":
    unittest.main()
