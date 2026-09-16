#!/usr/bin/env python3
"""Validate Moru's Russian source catalog before Flutter generation."""
import argparse
import json
import re
import sys
from pathlib import Path


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def validate(root):
    directory = root / "lib/l10n"
    english = read_json(directory / "app_en.arb")
    russian_path = directory / "app_ru.arb"
    if not russian_path.is_file():
        return ["Russian ARB is missing: lib/l10n/app_ru.arb"], 0
    russian = read_json(russian_path)
    en = {k: v for k, v in english.items() if not k.startswith("@")}
    ru = {k: v for k, v in russian.items() if not k.startswith("@")}
    errors = []
    if russian.get("@@locale") != "ru":
        errors.append("Russian ARB must declare @@locale=ru")
    if en.keys() != ru.keys():
        errors.append(f"Missing RU keys: {sorted(en.keys() - ru.keys())}")
        errors.append(f"Unknown RU keys: {sorted(ru.keys() - en.keys())}")
    allow_path = root / "tool/moru_ru_technical_allowlist.json"
    allowed = read_json(allow_path) if allow_path.is_file() else {}
    for key in allowed:
        if key not in en or not isinstance(allowed[key], str) or not allowed[key].strip():
            errors.append(f"Invalid technical-English exception: {key}")
    # ICU syntax itself is validated by flutter gen-l10n; here ensure that
    # named interpolation/plural/select inputs survive translation.
    variables = re.compile(r"\{\s*([a-zA-Z][a-zA-Z0-9_]*)\s*(?:[,}])")
    for key in sorted(en.keys() & ru.keys()):
        value = ru[key]
        if not isinstance(value, str) or not value.strip():
            errors.append(f"Empty or non-text RU value: {key}")
            continue
        en_vars, ru_vars = set(variables.findall(en[key])), set(variables.findall(value))
        if en_vars != ru_vars:
            errors.append(f"Placeholder mismatch: {key}: EN={sorted(en_vars)}, RU={sorted(ru_vars)}")
        metadata = english.get("@" + key, {})
        ru_metadata = russian.get("@" + key, {})
        if "placeholders" in ru_metadata and metadata.get("placeholders", {}) != ru_metadata["placeholders"]:
            errors.append(f"Placeholder metadata changed: {key}")
        if value == en[key] and re.search(r"[A-Za-z]", value) and key not in allowed:
            errors.append(f"Untranslated value needs translation or a justified technical exception: {key}")
        if key in allowed and value != en[key]:
            errors.append(f"Unused technical exception: {key}")
        if "\ufffd" in value:
            errors.append(f"Broken Unicode replacement character: {key}")
    return errors, len(en)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        errors, count = validate(args.root)
    except (ValueError, OSError) as error:
        errors, count = [str(error)], 0
    if errors:
        print("Moru RU validation FAILED", file=sys.stderr)
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"Moru RU validation PASS: {count} EN = {count} RU; placeholders and exceptions checked")
    return 0


if __name__ == "__main__":
    sys.exit(main())
