"""Regression tests for the ARB validator; no Flutter SDK required."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("check_moru_ru", Path(__file__).with_name("check_moru_ru.py"))
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class RussianCatalogValidationTest(unittest.TestCase):
    def validate(self, en, ru, allowed=None):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            directory = root / "lib/l10n"
            directory.mkdir(parents=True)
            (directory / "app_en.arb").write_text(json.dumps(en), encoding="utf-8")
            (directory / "app_ru.arb").write_text(json.dumps({"@@locale": "ru", **ru}), encoding="utf-8")
            if allowed is not None:
                (root / "tool").mkdir()
                (root / "tool/moru_ru_technical_allowlist.json").write_text(json.dumps(allowed), encoding="utf-8")
            return validator.validate(root)[0]

    def test_plural_branch_words_are_not_arguments(self):
        self.assertEqual([], self.validate(
            {"copies": "Delete {count, plural, =1{it} other{those}}; keep {count, plural, =1{it} other{them}}."},
            {"copies": "Удалить {count, plural, one{{count} копию} few{{count} копии} many{{count} копий} other{{count} копии}}."},
        ))

    def test_nested_select_arguments_are_preserved(self):
        self.assertEqual([], self.validate(
            {"state": "{status, select, ready{Ready for {name}} other{Waiting for {count, plural, one{one} other{{count}}}}}"},
            {"state": "{status, select, ready{Готово для {name}} other{Ожидание: {count, plural, one{{count} элемент} few{{count} элемента} many{{count} элементов} other{{count} элемента}}}}"},
        ))

    def test_missing_nested_argument_is_rejected(self):
        errors = self.validate(
            {"state": "{status, select, ready{Ready for {name}} other{Waiting}}"},
            {"state": "{status, select, ready{Готово} other{Ожидание}}"},
        )
        self.assertTrue(any("Placeholder mismatch" in error for error in errors), errors)

    def test_missing_and_extra_keys_are_rejected(self):
        self.assertTrue(self.validate({"a": "Name"}, {"b": "Имя"}))

    def test_technical_exception_must_be_explicit_and_used(self):
        self.assertEqual([], self.validate({"api": "MCP"}, {"api": "MCP"}, {"api": "Protocol name"}))
        self.assertTrue(self.validate({"api": "MCP"}, {"api": "MCP"}))
        self.assertTrue(self.validate({"label": "Name"}, {"label": "Имя"}, {"label": "unused"}))

    def test_duplicate_json_keys_are_rejected(self):
        with self.assertRaises(ValueError):
            json.loads('{"a":"one","a":"two"}', object_pairs_hook=validator.unique_object)


if __name__ == "__main__":
    unittest.main()
