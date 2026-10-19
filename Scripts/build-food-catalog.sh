#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CACHE="$ROOT/.catalog-cache"
mkdir -p "$CACHE"
TAIWAN_FILE="${TAIWAN_FILE:-}"
FOUNDATION="$CACHE/foundation.zip"
SR="$CACHE/sr-legacy.zip"
FNDDS="$CACHE/fndds.zip"
curl -L --fail --retry 3 --max-time 300 -o "$FOUNDATION" 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_foundation_food_json_2026-04-30.zip'
curl -L --fail --retry 3 --max-time 600 -o "$SR" 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_json_2018-04.zip'
curl -L --fail --retry 3 --max-time 300 -o "$FNDDS" 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_survey_food_json_2024-10-31.zip'
TAIWAN_ARG=()
if [ -n "$TAIWAN_FILE" ]; then TAIWAN_ARG=(--taiwan-reference "$TAIWAN_FILE"); fi
python3 Tools/build_food_catalog.py \
  --foundation "$FOUNDATION" --sr-legacy "$SR" --fndds "$FNDDS" \
  --translation-cache CatalogData/FoodNameZhTranslations.json \
  "${TAIWAN_ARG[@]}"
