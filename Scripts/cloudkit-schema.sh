#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${CLOUDKIT_TEAM_ID:-ZRY7UHFY75}"
CONTAINER_ID="${CLOUDKIT_CONTAINER_ID:-iCloud.com.lyonzhu.NutritionDiary}"
SCHEMA_DIR="$ROOT/CloudKit"
DEVELOPMENT_SCHEMA="$SCHEMA_DIR/NutritionDiary-development.ckdb"
PRODUCTION_SCHEMA="$SCHEMA_DIR/NutritionDiary-production.ckdb"

usage() {
  cat <<'USAGE'
Usage: Scripts/cloudkit-schema.sh <command>

Commands:
  doctor               Verify cktool can list the configured developer team.
  auth-management      Save a management token to the login Keychain.
  auth-user            Save a short-lived user token to the login Keychain.
  export-development   Export the Development schema to CloudKit/.
  validate-development Validate the versioned Development schema.
  export-production    Export the Production schema to CloudKit/.
  validate-production  Validate the versioned Production schema.
  compare              Compare Development and Production field definitions.
USAGE
}

require_management_token() {
  security find-generic-password -s com.apple.icloud.cktool -a cktoolmanagement_auth >/dev/null 2>&1 || {
    printf 'error: CloudKit management token is not saved. Run: %s auth-management\n' "$0" >&2
    exit 1
  }
}

command="${1:-}"
case "$command" in
  doctor)
    xcrun cktool get-teams
    ;;
  auth-management)
    xcrun cktool save-token --type management --method keychain
    ;;
  auth-user)
    xcrun cktool save-token --type user --method keychain
    ;;
  export-development)
    require_management_token
    mkdir -p "$SCHEMA_DIR"
    xcrun cktool export-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment development \
      --output-file "$DEVELOPMENT_SCHEMA"
    printf 'exported: %s\n' "$DEVELOPMENT_SCHEMA"
    ;;
  validate-development)
    require_management_token
    xcrun cktool validate-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment development \
      --file "$DEVELOPMENT_SCHEMA"
    ;;
  export-production)
    require_management_token
    mkdir -p "$SCHEMA_DIR"
    xcrun cktool export-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment production \
      --output-file "$PRODUCTION_SCHEMA"
    printf 'exported: %s\n' "$PRODUCTION_SCHEMA"
    ;;
  validate-production)
    require_management_token
    xcrun cktool validate-schema \
      --team-id "$TEAM_ID" \
      --container-id "$CONTAINER_ID" \
      --environment production \
      --file "$PRODUCTION_SCHEMA"
    ;;
  compare)
    require_management_token
    [ -f "$DEVELOPMENT_SCHEMA" ] || { printf 'error: missing %s\n' "$DEVELOPMENT_SCHEMA" >&2; exit 1; }
    [ -f "$PRODUCTION_SCHEMA" ] || { printf 'error: missing %s\n' "$PRODUCTION_SCHEMA" >&2; exit 1; }
    python3 - "$DEVELOPMENT_SCHEMA" "$PRODUCTION_SCHEMA" <<'PY'
import json, pathlib, sys

def fields(path):
    data=json.loads(pathlib.Path(path).read_text())
    result={}
    for record_type in data.get('recordTypes', data.get('record_types', [])):
        name=record_type.get('recordTypeName') or record_type.get('name')
        values={}
        for field in record_type.get('fields', []):
            field_name=field.get('fieldName') or field.get('name')
            field_type=field.get('fieldType') or field.get('type')
            values[field_name]=field_type
        result[name]=values
    return result

development=fields(sys.argv[1])
production=fields(sys.argv[2])
if development != production:
    missing=set(development)-set(production)
    extra=set(production)-set(development)
    print('schema mismatch', {'missingInProduction': sorted(missing), 'extraInProduction': sorted(extra)}, file=sys.stderr)
    for name in sorted(set(development)&set(production)):
        if development[name] != production[name]:
            print(f'field mismatch for {name}: development={development[name]} production={production[name]}', file=sys.stderr)
    raise SystemExit(1)
print('CloudKit Development/Production schemas match')
PY
    ;;
  *)
    usage
    exit 1
    ;;
esac
