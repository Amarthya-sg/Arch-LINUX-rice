from __future__ import annotations

import sys
import unittest
from pathlib import Path

CORE_DIR = Path(__file__).resolve().parents[1] / "core"
sys.path.insert(0, str(CORE_DIR))

from parse_css_tokens import parse_css, qml_value  # noqa: E402


class CssTokenParserTests(unittest.TestCase):
    def test_current_stylesheet_exposes_expected_tokens(self) -> None:
        css = (CORE_DIR.parent / "style.css").read_text(encoding="utf-8")
        tokens = parse_css(css)
        self.assertEqual(tokens["background"], "#0b111b")
        self.assertEqual(tokens["surfaceRaised"], "#192638")
        self.assertEqual(tokens["spaceXl"], 24)
        self.assertEqual(tokens["textTitle"], 22)
        self.assertEqual(tokens["islandBg"], "#060b12")
        self.assertEqual(tokens["outline"], "#24ffffff")

    def test_css_alpha_hex_is_reordered_for_qt_argb(self) -> None:
        self.assertEqual(qml_value("#ffffff14"), "#14ffffff")
        self.assertEqual(qml_value("#f008"), "#8f00")

    def test_numeric_px_values_become_json_numbers(self) -> None:
        self.assertEqual(qml_value("22px"), 22)
        self.assertEqual(qml_value("1.5px"), 1.5)
        self.assertEqual(qml_value("-2px"), -2)

    def test_kebab_case_becomes_camel_case(self) -> None:
        tokens = parse_css(":root {\n  --cc-surface-raised: #232327;\n}\n")
        self.assertEqual(tokens, {"surfaceRaised": "#232327"})

    def test_comments_are_ignored(self) -> None:
        tokens = parse_css("/* --cc-ignored: 1px; */\n:root {\n --cc-space-sm: 10px; /* space */\n}\n")
        self.assertEqual(tokens, {"spaceSm": 10})

    def test_duplicate_tokens_are_rejected(self) -> None:
        css = ":root {\n--cc-text: #fff;\n--cc-text: #000;\n}\n"
        with self.assertRaisesRegex(ValueError, "duplicate token"):
            parse_css(css)

    def test_malformed_custom_property_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "malformed"):
            parse_css(":root {\n--cc-text: #fff\n}\n")

    def test_empty_stylesheet_is_rejected(self) -> None:
        with self.assertRaisesRegex(ValueError, "no --cc-"):
            parse_css(":root { color: red; }\n")


if __name__ == "__main__":
    unittest.main()
