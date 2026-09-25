#!/usr/bin/env python3
"""Checks that every localization key used in source has an entry in its
target's Localizable.xcstrings catalog, and that every catalog entry is
still used somewhere in source — Repository Quality Standard L04.

Two call sites are scanned:
  - `L.string("key", "value", ...)` in Sources/OpenZonrCore
  - `localized("key", "value", ...)` in Sources/OpenZonrApp

The source's `value` argument is the string's English source text. A small
set of pinned keys are exempt from the "used in source" requirement: they
are read directly by LocalizationTests to prove the resource-bundle
plumbing, not through L.string/localized, and would otherwise always show
up as orphaned.

Usage:
    python3 Scripts/check-localization-keys.py            # check only
    python3 Scripts/check-localization-keys.py --sync      # also add
        missing keys to their catalog, with the English value from source
        as the "en" localization, state "translated". Never removes a key:
        an orphaned key still fails the check after --sync, so a stale key
        is a deliberate deletion, not a silent one.

Exit status is non-zero when a missing or orphaned key remains after any
requested sync, so this doubles as a CI check.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (display name, source directory, catalog path, call prefix regex, pinned keys)
TARGETS = [
    (
        "OpenZonrCore",
        ROOT / "Sources" / "OpenZonrCore",
        ROOT / "Sources" / "OpenZonrCore" / "Resources" / "Localizable.xcstrings",
        r"L\.string\(",
        {"localizationTests.probe"},
    ),
    (
        "OpenZonrApp",
        ROOT / "Sources" / "OpenZonrApp",
        ROOT / "Sources" / "OpenZonrApp" / "Resources" / "Localizable.xcstrings",
        r"\blocalized\(",
        {"localizationTests.probe"},
    ),
]

# Matches `<prefix>"key"` then, across any whitespace/newlines, a value that
# may itself be several string literals joined by `+` — this codebase wraps
# long messages across lines as `"first part "\n    + "second part."`, and
# the whole joined sequence is the second argument. Handles escaped
# characters (\", \\, \u{...}) inside any literal.
ONE_LITERAL = r'"(?:[^"\\]|\\.)*"'
STRING_LITERAL = r'"((?:[^"\\]|\\.)*)"'
CONCATENATED_LITERAL = r"(" + ONE_LITERAL + r"(?:\s*\+\s*" + ONE_LITERAL + r")*)"


def find_calls(prefix: str, text: str) -> list[tuple[str, str]]:
    pattern = re.compile(prefix + r"\s*" + STRING_LITERAL + r"\s*,\s*" + CONCATENATED_LITERAL, re.DOTALL)
    results = []
    for m in pattern.finditer(text):
        parts = re.findall(STRING_LITERAL, m.group(2))
        results.append((m.group(1), "".join(unescape(part) for part in parts)))
    return results


ESCAPE_PATTERN = re.compile(r"\\u\{([0-9a-fA-F]+)\}|\\(.)")
SIMPLE_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\"}


def unescape(value: str) -> str:
    def replace(m: re.Match[str]) -> str:
        if m.group(1) is not None:
            return chr(int(m.group(1), 16))
        return SIMPLE_ESCAPES.get(m.group(2), m.group(2))

    # A single left-to-right pass, so a backslash is consumed with exactly
    # the character after it — chaining separate str.replace() calls (the
    # first version of this function) can misfire when one escape's output
    # happens to contain another escape's input character.
    return ESCAPE_PATTERN.sub(replace, value)


def used_keys(src_dir: Path, prefix: str) -> dict[str, str]:
    found: dict[str, str] = {}
    for path in sorted(src_dir.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for key, value in find_calls(prefix, text):
            found.setdefault(key, value)
    return found


def load_catalog(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save_catalog(path: Path, catalog: dict) -> None:
    text = json.dumps(catalog, indent=2, ensure_ascii=False, sort_keys=True)
    path.write_text(text + "\n", encoding="utf-8")


def check_target(name: str, src_dir: Path, catalog_path: Path, prefix: str, pinned: set[str], fix: bool) -> bool:
    used = used_keys(src_dir, prefix)
    catalog = load_catalog(catalog_path)
    cataloged = set(catalog["strings"].keys())

    missing = sorted(set(used) - cataloged)
    if fix and missing:
        for key in missing:
            catalog["strings"][key] = {
                "extractionState": "extracted_with_value",
                "localizations": {"en": {"stringUnit": {"state": "translated", "value": used[key]}}},
            }
        save_catalog(catalog_path, catalog)
        cataloged = set(catalog["strings"].keys())
        missing = sorted(set(used) - cataloged)

    orphaned = sorted(cataloged - set(used) - pinned)

    ok = True
    if missing:
        ok = False
        print(f"{name}: {len(missing)} key(s) used in source but missing from {catalog_path.relative_to(ROOT)}:")
        for key in missing:
            print(f"  - {key}")
    if orphaned:
        ok = False
        print(f"{name}: {len(orphaned)} key(s) in {catalog_path.relative_to(ROOT)} but not used in source:")
        for key in orphaned:
            print(f"  - {key}")
    if ok:
        print(f"{name}: {len(used)} key(s), catalog complete (no missing or orphaned keys).")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--sync", action="store_true", help="add missing keys to their catalog before reporting"
    )
    args = parser.parse_args()

    all_ok = True
    for name, src_dir, catalog_path, prefix, pinned in TARGETS:
        if not check_target(name, src_dir, catalog_path, prefix, pinned, fix=args.sync):
            all_ok = False

    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
