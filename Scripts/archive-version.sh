#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

PROJECT_SPEC="$ROOT/project.yml"
RELEASES_DIR="$ROOT/Releases"
INDEX_FILE="$RELEASES_DIR/index.json"
TMP_DIR=""

usage() {
  cat <<'USAGE'
Usage:
  Scripts/archive-version.sh [--dry-run] [--skip-build] [--notes PATH]
  Scripts/archive-version.sh verify [RELEASE_DIRECTORY]

Options:
  --dry-run       Print the version and archive files without writing or building.
  --skip-build    Create the archive without running tests/builds.
  --notes PATH    Use a custom release-notes Markdown file.
  verify [PATH]   Validate a release archive; defaults to index.json latest.
USAGE
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

read_yaml_value() {
  local key="$1"
  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":" {
      sub("^[[:space:]]*" key ":[[:space:]]*", "")
      gsub(/["'"'"']/, "")
      sub(/[[:space:]]*#.*$/, "")
      print
      exit
    }
  ' "$PROJECT_SPEC" | tr -d '\r'
}

first_target_setting() {
  local target="$1"
  local key="$2"
  awk -v target="$target" -v key="$key" '
    $0 ~ "^  " target ":[[:space:]]*$" { in_target=1; next }
    in_target && $0 ~ "^  [^ ]" { exit }
    in_target && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      line=$0
      sub("^[[:space:]]*" key ":[[:space:]]*", "", line)
      gsub(/["'"'"']/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      print line
      exit
    }
  ' "$PROJECT_SPEC"
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

if [ "${1:-}" = "verify" ]; then
  [ -f "$INDEX_FILE" ] || die "missing release index: $INDEX_FILE"
  if [ -n "${2:-}" ]; then
    RELEASE_ARG="$2"
  else
    LATEST_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("latest") or "")' "$INDEX_FILE")"
    [ -n "$LATEST_ID" ] || die "index.json has no latest release"
    RELEASE_ARG="$RELEASES_DIR/$LATEST_ID"
  fi
  RELEASE_DIR="$(cd "$RELEASE_ARG" && pwd)"
  MANIFEST="$RELEASE_DIR/manifest.json"
  [ -f "$MANIFEST" ] || die "missing manifest: $MANIFEST"
  [ -f "$INDEX_FILE" ] || die "missing release index: $INDEX_FILE"

  VERSION="$(read_yaml_value MARKETING_VERSION)"
  BUILD="$(read_yaml_value CURRENT_PROJECT_VERSION)"
  [ -n "$VERSION" ] || die "MARKETING_VERSION is missing from project.yml"
  [ -n "$BUILD" ] || die "CURRENT_PROJECT_VERSION is missing from project.yml"

  python3 - "$RELEASE_DIR" "$MANIFEST" "$INDEX_FILE" "$VERSION" "$BUILD" <<'PY'
import hashlib, json, pathlib, sys
release_dir = pathlib.Path(sys.argv[1]).resolve()
manifest_path = pathlib.Path(sys.argv[2])
index_path = pathlib.Path(sys.argv[3])
expected_version = sys.argv[4]
expected_build = int(sys.argv[5])
manifest = json.loads(manifest_path.read_text())
current_id = f"v{expected_version}-b{expected_build}"
if manifest.get("id") != current_id:
    print(f"historical release: {manifest.get('id')} (current project is {current_id})")
elif manifest.get("version") != expected_version or int(manifest.get("build", -1)) != expected_build:
    raise SystemExit("current release manifest does not match project.yml")
items = []
items.extend(manifest.get("resources", []))
items.extend(manifest.get("screenshots", []))
for key in ("source", "releaseNotes"):
    if key in manifest:
        items.append(manifest[key])
for item in items:
    path = release_dir / item["path"]
    if not path.is_file():
        raise SystemExit(f"missing archived file: {item['path']}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != item["sha256"]:
        raise SystemExit(f"checksum mismatch: {item['path']}")
index = json.loads(index_path.read_text())
ids = [entry.get("id") for entry in index.get("versions", [])]
if manifest.get("id") not in ids:
    raise SystemExit(f"release {manifest.get('id')} is not registered in index.json")
print(f"manifest: OK ({manifest.get('id')})")
PY
  (cd "$RELEASE_DIR" && shasum -a 256 -c checksums.sha256)
  printf 'release verification passed: %s\n' "$RELEASE_DIR"
  exit 0
fi

DRY_RUN=0
SKIP_BUILD=0
NOTES_PATH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --notes)
      shift
      [ $# -gt 0 ] || die "--notes requires a path"
      NOTES_PATH="$1"
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

VERSION="$(read_yaml_value MARKETING_VERSION)"
BUILD="$(read_yaml_value CURRENT_PROJECT_VERSION)"
IOS_TARGET="$(first_target_setting NutritionDiary-iOS deploymentTarget)"
MAC_TARGET="$(first_target_setting NutritionDiary-macOS deploymentTarget)"
IOS_BUNDLE="$(first_target_setting NutritionDiary-iOS PRODUCT_BUNDLE_IDENTIFIER)"
MAC_BUNDLE="$(first_target_setting NutritionDiary-macOS PRODUCT_BUNDLE_IDENTIFIER)"

[ -n "$VERSION" ] || die "MARKETING_VERSION is missing from project.yml"
[ -n "$BUILD" ] || die "CURRENT_PROJECT_VERSION is missing from project.yml"
case "$BUILD" in (*[!0-9]*|'') die "CURRENT_PROJECT_VERSION must be an integer: $BUILD" ;; esac
[ -d Apps/Shared/Assets.xcassets ] || die "missing Apps/Shared/Assets.xcassets"
[ -f Docs/app-home.png ] || die "missing Docs/app-home.png"
if [ -n "$NOTES_PATH" ] && [ ! -f "$NOTES_PATH" ]; then
  die "release notes not found: $NOTES_PATH"
fi

RELEASE_ID="v${VERSION}-b${BUILD}"
DEST="$RELEASES_DIR/$RELEASE_ID"

if [ -e "$DEST" ]; then
  die "release already exists and is immutable: $DEST"
fi

printf 'release id: %s\n' "$RELEASE_ID"
printf 'destination: %s\n' "$DEST"
printf 'source archive: source/NutritionDiary-%s-source.zip\n' "$RELEASE_ID"
printf 'resources: Apps/Shared/Assets.xcassets\n'
printf 'screenshots: Docs/*.png\n'
printf 'validation: %s\n' "$([ "$SKIP_BUILD" -eq 1 ] && echo skipped || echo tests-and-builds)"

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'dry-run: no files were written and no builds were run.\n'
  exit 0
fi

if [ "$SKIP_BUILD" -eq 0 ]; then
  command -v xcodegen >/dev/null 2>&1 || die "xcodegen is required"
  command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required"
  xcodegen generate
  swift test --package-path Packages/NutritionKit
  python3 Scripts/verify_localizations.py
  xcodebuild test -project NutritionDiary.xcodeproj -scheme NutritionDiary-iOS -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' CODE_SIGNING_ALLOWED=NO \
    -only-testing:NutritionDiary-iOS-UITests -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300
  xcodebuild -project NutritionDiary.xcodeproj -scheme NutritionDiary-iOS -configuration Debug \
    -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
  xcodebuild -project NutritionDiary.xcodeproj -scheme NutritionDiary-macOS -configuration Debug \
    -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
fi

mkdir -p "$RELEASES_DIR"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nutrition-release.XXXXXX")"
STAGE="$TMP_DIR/$RELEASE_ID"
mkdir -p "$STAGE/resources" "$STAGE/screenshots" "$STAGE/source"

ditto "$ROOT/Apps/Shared/Assets.xcassets" "$STAGE/resources/Assets.xcassets"
find "$ROOT/Docs" -maxdepth 1 -type f -name '*.png' -exec cp {} "$STAGE/screenshots/" \;
[ -n "$(find "$STAGE/screenshots" -type f -name '*.png' -print -quit)" ] || die "no screenshots were archived"

if [ -n "$NOTES_PATH" ]; then
  cp "$NOTES_PATH" "$STAGE/RELEASE_NOTES.md"
else
  cat > "$STAGE/RELEASE_NOTES.md" <<NOTES
# $RELEASE_ID

- App version: $VERSION
- Build: $BUILD
- Created: $(date -u +'%Y-%m-%dT%H:%M:%SZ')

## Changes

- Describe user-visible and technical changes for this version.
NOTES
fi

SOURCE_ZIP="$STAGE/source/NutritionDiary-${RELEASE_ID}-source.zip"
(
  cd "$ROOT"
  zip -q -r -X "$SOURCE_ZIP" .gitignore .gitattributes AGENTS.md LICENSE THIRD_PARTY_NOTICES.md project.yml Makefile README.md .github AppStore Apps CloudKit Packages CatalogData Docs LegalSite Scripts Tools \
    -x '*/.build/*' '*/.swiftpm/*' '*/DerivedData/*' '*/xcuserdata/*' '*/.DS_Store' '*/__pycache__/*'
)

GIT_COMMIT="$(git rev-parse --verify HEAD 2>/dev/null || true)"
if ! printf '%s' "$GIT_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then GIT_COMMIT=""; fi
GIT_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
GIT_DIRTY=0
if [ -n "$(git status --porcelain 2>/dev/null || true)" ]; then GIT_DIRTY=1; fi
VALIDATION="passed"
[ "$SKIP_BUILD" -eq 1 ] && VALIDATION="skipped"

export RELEASE_ID VERSION BUILD STAGE IOS_TARGET MAC_TARGET IOS_BUNDLE MAC_BUNDLE GIT_COMMIT GIT_BRANCH GIT_DIRTY VALIDATION NOTES_PATH
python3 - <<'PY'
import datetime, hashlib, json, os, pathlib
stage = pathlib.Path(os.environ["STAGE"])
release_id = os.environ["RELEASE_ID"]

def record(path):
    return {"path": str(path.relative_to(stage)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}

resources = [record(p) for p in sorted((stage / "resources").rglob("*")) if p.is_file()]
screenshots = [record(p) for p in sorted((stage / "screenshots").rglob("*")) if p.is_file()]
source = record(stage / "source" / f"NutritionDiary-{release_id}-source.zip")
notes = record(stage / "RELEASE_NOTES.md")
manifest = {
    "schemaVersion": 1,
    "app": "NutritionDiary",
    "displayName": "饮食营养记录",
    "id": release_id,
    "version": os.environ["VERSION"],
    "build": int(os.environ["BUILD"]),
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "deployment": {
        "iOS": os.environ.get("IOS_TARGET", ""),
        "macOS": os.environ.get("MAC_TARGET", "")
    },
    "bundleIdentifiers": {
        "iOS": os.environ.get("IOS_BUNDLE", ""),
        "macOS": os.environ.get("MAC_BUNDLE", "")
    },
    "git": {
        "commit": os.environ.get("GIT_COMMIT") or None,
        "branch": os.environ.get("GIT_BRANCH") or None,
        "dirty": bool(int(os.environ.get("GIT_DIRTY", "0")))
    },
    "validation": os.environ["VALIDATION"],
    "source": source,
    "releaseNotes": notes,
    "resources": resources,
    "screenshots": screenshots
}
(stage / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
PY

(
  cd "$STAGE"
  find . -type f ! -name 'checksums.sha256' -print | sort | while IFS= read -r file; do
    printf '%s  %s\n' "$(shasum -a 256 "$file" | awk '{print $1}')" "${file#./}"
  done > checksums.sha256
)

mv "$STAGE" "$DEST"

python3 - "$RELEASES_DIR" "$INDEX_FILE" <<'PY'
import json, pathlib, sys
releases = pathlib.Path(sys.argv[1])
index_path = pathlib.Path(sys.argv[2])
entries = []
for manifest_path in sorted(releases.glob("v*/manifest.json")):
    m = json.loads(manifest_path.read_text())
    entries.append({
        "id": m["id"],
        "version": m["version"],
        "build": m["build"],
        "createdAt": m["createdAt"],
        "path": m["id"] + "/",
        "validation": m.get("validation", "unknown")
    })
def version_key(value):
    return tuple(int(part) if part.isdigit() else part for part in value.replace("-", ".").split("."))
entries.sort(key=lambda e: (version_key(e["version"]), e["build"]))
latest = entries[-1]["id"] if entries else None
index = {"schemaVersion": 1, "latest": latest, "versions": entries}
index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n")
PY

printf 'created release: %s\n' "$DEST"
"$SCRIPT_DIR/archive-version.sh" verify "$DEST"
