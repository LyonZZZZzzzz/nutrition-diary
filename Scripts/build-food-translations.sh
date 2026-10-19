#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="${TMPDIR:-/tmp}/nutritiondiary-food-translator"
swiftc -parse-as-library Scripts/translate-food-names.swift -lsqlite3 -o "$BIN"
ARGS=(
  --database Packages/NutritionKit/Sources/NutritionKit/Resources/Catalog.sqlite
  --rules Tools/food-name-translation-rules.json
  --output CatalogData/FoodNameZhTranslations.json
  --batch-size "${BATCH_SIZE:-100}"
)
if [ "${RESUME:-0}" = "1" ]; then ARGS+=(--resume); fi
"$BIN" "${ARGS[@]}"
