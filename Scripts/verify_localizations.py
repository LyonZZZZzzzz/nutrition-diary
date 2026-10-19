#!/usr/bin/env python3
"""Validate that user-facing Chinese literals have English catalog entries."""
from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Apps/Shared/Localizable.xcstrings"
INFO_PLIST = ROOT / "Apps/Shared/InfoPlist.xcstrings"
APPS = ROOT / "Apps"
UI_APIS = (
    "Text", "Button", "Label", "Section", "navigationTitle",
    "ContentUnavailableView", "TextField", "Toggle", "Link", "Picker",
    "DatePicker", "confirmationDialog", "alert",
)
PATTERN = re.compile(r"\b(?:" + "|".join(map(re.escape, UI_APIS)) + r')\("((?:[^"\\]|\\.)*)"')
CHINESE = re.compile(r"[\u3400-\u9fff]")


def localized_keys(path: pathlib.Path) -> set[str]:
    data = json.loads(path.read_text())
    return set(data.get("strings", {}))


def main() -> int:
    keys = localized_keys(CATALOG)
    missing: dict[str, list[str]] = {}
    for path in sorted(APPS.rglob("*.swift")):
        for line_number, line in enumerate(path.read_text().splitlines(), 1):
            for match in PATTERN.finditer(line):
                value = match.group(1)
                if CHINESE.search(value) and "\\(" not in value and value not in keys:
                    missing.setdefault(value, []).append(f"{path.relative_to(ROOT)}:{line_number}")

    info = json.loads(INFO_PLIST.read_text()).get("strings", {})
    required_info = {
        "CFBundleDisplayName", "NSCameraUsageDescription",
        "NSPhotoLibraryUsageDescription", "NSHealthShareUsageDescription",
        "NSHealthUpdateUsageDescription",
    }
    for key in sorted(required_info):
        localizations = info.get(key, {}).get("localizations", {})
        if not localizations.get("en", {}).get("stringUnit", {}).get("value"):
            missing.setdefault(key, []).append(f"{INFO_PLIST.relative_to(ROOT)}: missing English value")
        if not localizations.get("zh-Hans", {}).get("stringUnit", {}).get("value"):
            missing.setdefault(key, []).append(f"{INFO_PLIST.relative_to(ROOT)}: missing Chinese value")

    if missing:
        for value, locations in sorted(missing.items()):
            print(f"missing localization: {value!r}", file=sys.stderr)
            for location in locations:
                print(f"  {location}", file=sys.stderr)
        return 1
    print(f"localization verification passed ({len(keys)} catalog keys)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
