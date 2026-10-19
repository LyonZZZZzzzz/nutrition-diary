#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { printf 'release audit failed: %s\n' "$*" >&2; exit 1; }
read_yaml_value() {
  local key="$1"
  awk -v key="$key" '$0 ~ "^[[:space:]]*" key ":" { sub("^[[:space:]]*" key ":[[:space:]]*", ""); gsub(/["'"'"']/, ""); print; exit }' project.yml
}

VERSION="$(read_yaml_value MARKETING_VERSION)"
BUILD="$(read_yaml_value CURRENT_PROJECT_VERSION)"
[ -n "$VERSION" ] || fail "missing MARKETING_VERSION"
[ -n "$BUILD" ] || fail "missing CURRENT_PROJECT_VERSION"
[ -f Apps/iOS/NutritionDiary-Development.entitlements ] || fail "missing iOS Development entitlements"
[ -f Apps/iOS/NutritionDiary-Production.entitlements ] || fail "missing iOS Production entitlements"
[ -f Apps/iOS/NutritionDiary-DeviceTest.entitlements ] || fail "missing iOS DeviceTest entitlements"
[ -f Apps/macOS/NutritionDiary-Development.entitlements ] || fail "missing macOS Development entitlements"
[ -f Apps/macOS/NutritionDiary-Production.entitlements ] || fail "missing macOS Production entitlements"
[ -f LegalSite/support.md ] || fail "missing support source"
[ -f AppStore/metadata.json ] || fail "missing App Store metadata"
[ -f CloudKit/README.md ] || fail "missing CloudKit schema documentation"
[ -f CloudKit/NutritionDiary-development.ckdb ] || fail "missing Development CloudKit schema"
[ -f CloudKit/NutritionDiary-production.ckdb ] || fail "missing Production CloudKit schema"
[ -f Scripts/cloudkit-schema.sh ] || fail "missing CloudKit schema tool"
for removed in \
  Apps/Shared/PrivacyInfo.xcprivacy \
  AppStore/privacy-questionnaire.md \
  LegalSite/privacy.md \
  LegalSite/data-deletion.md; do
  [ ! -e "$removed" ] || fail "privacy file must not be present: $removed"
done

plutil -lint Apps/iOS/NutritionDiary-Development.entitlements >/dev/null || fail "invalid iOS Development entitlements"
plutil -lint Apps/iOS/NutritionDiary-Production.entitlements >/dev/null || fail "invalid iOS Production entitlements"
plutil -lint Apps/iOS/NutritionDiary-DeviceTest.entitlements >/dev/null || fail "invalid iOS DeviceTest entitlements"
plutil -lint Apps/macOS/NutritionDiary-Development.entitlements >/dev/null || fail "invalid macOS Development entitlements"
plutil -lint Apps/macOS/NutritionDiary-Production.entitlements >/dev/null || fail "invalid macOS Production entitlements"

python3 - <<'PY'
import plistlib, pathlib, sys
root=pathlib.Path('.')
ios_dev=plistlib.loads((root/'Apps/iOS/NutritionDiary-Development.entitlements').read_bytes())
ios_prod=plistlib.loads((root/'Apps/iOS/NutritionDiary-Production.entitlements').read_bytes())
ios_test=plistlib.loads((root/'Apps/iOS/NutritionDiary-DeviceTest.entitlements').read_bytes())
mac_dev=plistlib.loads((root/'Apps/macOS/NutritionDiary-Development.entitlements').read_bytes())
mac_prod=plistlib.loads((root/'Apps/macOS/NutritionDiary-Production.entitlements').read_bytes())
for name, data in [('iOS Development',ios_dev),('iOS Production',ios_prod),('macOS Development',mac_dev),('macOS Production',mac_prod)]:
    if 'iCloud.com.lyonzhu.NutritionDiary' not in data.get('com.apple.developer.icloud-container-identifiers',[]):
        raise SystemExit(f'{name} CloudKit container missing')
    if 'CloudKit' not in data.get('com.apple.developer.icloud-services',[]):
        raise SystemExit(f'{name} CloudKit service missing')
if ios_dev.get('com.apple.developer.icloud-container-environment') != 'Development':
    raise SystemExit('iOS Development environment entitlement missing')
if ios_prod.get('com.apple.developer.icloud-container-environment') != 'Production':
    raise SystemExit('iOS Production environment entitlement missing')
if mac_dev.get('com.apple.developer.icloud-container-environment') != 'Development':
    raise SystemExit('macOS Development environment entitlement missing')
if mac_prod.get('com.apple.developer.icloud-container-environment') != 'Production':
    raise SystemExit('macOS Production environment entitlement missing')
if not ios_dev.get('com.apple.developer.healthkit') or not ios_prod.get('com.apple.developer.healthkit'):
    raise SystemExit('iOS HealthKit entitlement missing')
if ios_test.get('com.apple.developer.icloud-services') or ios_test.get('com.apple.developer.icloud-container-identifiers'):
    raise SystemExit('DeviceTest must not include CloudKit entitlements')
if not mac_dev.get('com.apple.security.app-sandbox') or not mac_prod.get('com.apple.security.app-sandbox'):
    raise SystemExit('macOS app sandbox entitlement missing')
if not mac_dev.get('com.apple.security.network.client') or not mac_prod.get('com.apple.security.network.client'):
    raise SystemExit('macOS network client entitlement missing')
print('entitlements: OK')
PY

project_version="$(read_yaml_value MARKETING_VERSION)"
[ "$project_version" = "$VERSION" ] || fail "version source mismatch"
rg -q 'DEVELOPMENT_TEAM: ZRY7UHFY75' project.yml || fail "development team missing from project.yml"
rg -q 'Apps/iOS/NutritionDiary-Development.entitlements' project.yml || fail "Debug CloudKit entitlement mapping missing"
rg -q 'Apps/iOS/NutritionDiary-Production.entitlements' project.yml || fail "Release CloudKit entitlement mapping missing"
rg -q 'Apps/macOS/NutritionDiary-Development.entitlements' project.yml || fail "macOS Debug CloudKit entitlement mapping missing"
rg -q 'Apps/macOS/NutritionDiary-Production.entitlements' project.yml || fail "macOS Release CloudKit entitlement mapping missing"
if rg -n --hidden -g '!Releases/**' -g '!.git/**' -g '!**/.build/**' -g '!**/DerivedData/**' -g '!**/__pycache__/**' "(sk-[A-Za-z0-9_-]{20,}|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|api[_-]?key[[:space:]]*[:=])" . >/tmp/nutrition-release-secret-scan.txt 2>/dev/null; then
  cat /tmp/nutrition-release-secret-scan.txt >&2
  fail "possible secret found in repository"
fi

CATALOG="Packages/NutritionKit/Sources/NutritionKit/Resources/Catalog.sqlite"
[ -f "$CATALOG" ] || fail "missing Catalog.sqlite"
bytes="$(stat -f%z "$CATALOG")"
rows="$(sqlite3 "$CATALOG" 'SELECT COUNT(*) FROM foods;')"
zh="$(sqlite3 "$CATALOG" "SELECT COUNT(*) FROM foods WHERE name_zh IS NOT NULL AND name_zh != '';")"
fts="$(sqlite3 "$CATALOG" 'SELECT COUNT(*) FROM food_search;')"
manifest_rows=$(python3 -c 'import json; print(json.load(open("Packages/NutritionKit/Sources/NutritionKit/Resources/catalog-manifest.json"))["recordCount"])')
[ "$rows" = "$manifest_rows" ] || fail "catalog row count does not match manifest: $rows/$manifest_rows"
[ "$zh" = "$rows" ] || fail "Chinese name coverage incomplete: $zh/$rows"
[ "$rows" = "$fts" ] || fail "FTS coverage mismatch: $fts/$rows"
[ "$bytes" -le 70000000 ] || fail "Catalog exceeds 70 MB target: $bytes"
printf 'catalog: OK (%s records, %s bytes)\n' "$rows" "$bytes"

[ -f "Docs/release-notes-v${VERSION}-b${BUILD}.md" ] || fail "release notes for current version missing"
if [ -f Releases/index.json ]; then
  latest="$(python3 -c 'import json; print(json.load(open("Releases/index.json")).get("latest",""))')"
  [ -n "$latest" ] || fail "release index has no latest version"
  [ -d "Releases/$latest" ] || fail "latest release directory missing: $latest"
  ./Scripts/archive-version.sh verify "Releases/$latest" >/dev/null || fail "latest release verification failed"
else
  latest="not-present"
fi

if git ls-files --error-unmatch Packages/NutritionKit/.build >/dev/null 2>&1; then
  fail "SwiftPM .build is tracked by Git"
fi

printf 'release audit passed: %s (%s), latest=%s\n' "$VERSION" "$BUILD" "$latest"
