#!/usr/bin/env python3
"""Add target capabilities that XcodeGen cannot currently serialize as PBX dictionaries."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "NutritionDiary.xcodeproj/project.pbxproj"
TARGETS = {
    "NutritionDiary-iOS": ("com.apple.HealthKit", "com.apple.iCloud"),
    "NutritionDiary-macOS": ("com.apple.iCloud",),
}

text = PROJECT.read_text()
target_ids: dict[str, str] = {}
for target_id, target_name in re.findall(
    r"^\s*([A-F0-9]{24}) /\* (NutritionDiary-(?:iOS|macOS)) \*/ = \{",
    text,
    flags=re.MULTILINE,
):
    target_ids[target_name] = target_id

missing = sorted(set(TARGETS) - set(target_ids))
if missing:
    raise SystemExit(f"targets not found in generated project: {missing}")

lines = text.splitlines()
start = next((i for i, line in enumerate(lines) if "TargetAttributes = {" in line), None)
if start is None:
    raise SystemExit("TargetAttributes section not found")

for target_name, capabilities in TARGETS.items():
    target_id = target_ids[target_name]
    block_start = next(
        (i for i in range(start, len(lines)) if re.match(rf"^\s*{re.escape(target_id)} = \{{", lines[i])),
        None,
    )
    if block_start is None:
        raise SystemExit(f"TargetAttributes block not found for {target_name}")
    block_end = next(
        (i for i in range(block_start + 1, len(lines)) if re.match(r"^\s*\};", lines[i])),
        None,
    )
    if block_end is None:
        raise SystemExit(f"TargetAttributes block end not found for {target_name}")

    if any("SystemCapabilities = {" in line for line in lines[block_start:block_end]):
        continue

    insertion = ["\t\t\t\t\tSystemCapabilities = {"]
    for capability in capabilities:
        insertion.extend([
            f"\t\t\t\t\t\t{capability} = {{",
            "\t\t\t\t\t\t\tenabled = 1;",
            "\t\t\t\t\t\t};",
        ])
    insertion.append("\t\t\t\t\t};")
    lines[block_end:block_end] = insertion

PROJECT.write_text("\n".join(lines) + "\n")
print(f"patched capabilities: {', '.join(sorted(TARGETS))}")
