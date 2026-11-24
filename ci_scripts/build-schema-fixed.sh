#!/usr/bin/env bash
# Build the offline Rime schema resources from immutable source revisions.
#
# This file is intentionally separate from InputSchemaBuild.sh: it does not
# modify the existing builder or Xcode project. Without --deployer it produces
# a SOURCE-ONLY fallback; source YAML/dictionaries are not precompiled binaries.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="${ROOT}/Resources/SharedSupport"
WORK=""
KEEP_WORK=0
DEPLOYER=""
THIRD_PARTY_NOTICES=""

ICE_REPO="iDvel/rime-ice"
ICE_REF="927e1cf1d3eeb9bf4be85e3f684dba4dd485b6f6"
ICE_SHA256="3c78386c45eba9bada065300e3e2ffcbc267d50e839892a34fa3116eae9e1817"
PRELUDE_REPO="rime/rime-prelude"
PRELUDE_REF="082425ea0684bca36474415d4a0e8db9b016487e"
PRELUDE_SHA256="66239ba4745d54471e5ce5540b45e86ec663ff5dba004cb23c95531a3bdec00f"
ESSAY_REPO="rime/rime-essay"
ESSAY_REF="d95eeae056df429ecf993038c325a216f0b28c5b"
ESSAY_SHA256="19a0f5ec89cf751daecf06d703a9019769382d53706b987f1fd9fed9abfe3575"

usage() {
  cat <<'USAGE'
Usage: build-schema-fixed.sh [options]

Creates Resources/SharedSupport/SharedSupport.zip and rime-ice.zip.
Default mode is a reproducible SOURCE-ONLY fallback: deployment happens on
first app launch and no .bin file is claimed to be precompiled.

Options:
  --deployer FILE              macOS rime_deployer compatible with librime 1.17
  --third-party-notices FILE   copy release third-party-notices.zip into archive
  --keep-work                  retain the temporary source/deploy tree
  -h, --help                   show this help

The deployer is never downloaded or guessed. It must be supplied by CI and
must be built from the same librime 1.17 ABI as the app's framework. A 1.17
XCFramework alone is not a deployer and cannot be used for this option.
USAGE
}
die() { echo "build-schema-fixed: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
sha256() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}' || sha256sum "$1" | awk '{print $1}'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --deployer) [ "$#" -ge 2 ] || die "--deployer needs a path"; DEPLOYER=$2; shift 2 ;;
    --third-party-notices) [ "$#" -ge 2 ] || die "--third-party-notices needs a path"; THIRD_PARTY_NOTICES=$2; shift 2 ;;
    --keep-work) KEEP_WORK=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

for c in curl tar unzip zip python3; do need_cmd "$c"; done
[ -z "$DEPLOYER" ] || { [ -x "$DEPLOYER" ] || die "deployer is not executable: $DEPLOYER"; [ "$(uname -s)" = Darwin ] || die "rime_deployer execution requires macOS"; }
[ -z "$THIRD_PARTY_NOTICES" ] || [ -f "$THIRD_PARTY_NOTICES" ] || die "notices archive not found: $THIRD_PARTY_NOTICES"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hamster-schema.XXXXXXXX")"
cleanup() { [ "$KEEP_WORK" -eq 1 ] || rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK/src" "$WORK/shared" "$WORK/user" "$WORK/downloads"

download() {
  local name=$1 repo=$2 ref=$3 expected=$4 archive="$WORK/downloads/$1.tar.gz"
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 30 \
    "https://codeload.github.com/${repo}/tar.gz/${ref}" -o "$archive"
  local actual; actual=$(sha256 "$archive")
  [ "$actual" = "$expected" ] || die "$name source SHA-256 mismatch: $actual"
  mkdir -p "$WORK/src/$name"
  tar -xzf "$archive" -C "$WORK/src/$name" --strip-components=1
}

download ice "$ICE_REPO" "$ICE_REF" "$ICE_SHA256"
download prelude "$PRELUDE_REPO" "$PRELUDE_REF" "$PRELUDE_SHA256"
download essay "$ESSAY_REPO" "$ESSAY_REF" "$ESSAY_SHA256"

# The application expects a flat Rime shared-data directory. Copy the actual
# source inputs, not the repository's docs or CI metadata.
cp -a "$WORK/src/ice"/. "$WORK/shared/"
cp -a "$WORK/src/prelude"/{key_bindings.yaml,punctuation.yaml,symbols.yaml} "$WORK/shared/" 2>/dev/null || true
cp -a "$WORK/src/essay/essay.txt" "$WORK/shared/" 2>/dev/null || true
cp -a "$ROOT/Resources/SharedSupport/hamster.yaml" "$WORK/shared/hamster.yaml"
mkdir -p "$WORK/shared/Licenses"
cp -a "$WORK/src/ice/LICENSE" "$WORK/shared/Licenses/rime-ice-GPL-3.0"
cp -a "$WORK/src/prelude/LICENSE" "$WORK/shared/Licenses/rime-prelude"
cp -a "$WORK/src/essay/LICENSE" "$WORK/shared/Licenses/rime-essay"
cp -a "$WORK/src/ice/others/docs/Credits.md" "$WORK/shared/Licenses/rime-ice-Credits.md"

# Optional binary deployment. This is deliberately an explicit input because
# vtable/module registration and generated table formats must match librime.
MODE="source-only"
if [ -n "$DEPLOYER" ]; then
  MODE="deployed-by-supplied-1.17-deployer"
  "$DEPLOYER" --build "$WORK/user" "$WORK/shared" "$WORK/shared/build"
fi
if [ -n "$THIRD_PARTY_NOTICES" ]; then
  mkdir -p "$WORK/shared/Licenses"
  cp -a "$THIRD_PARTY_NOTICES" "$WORK/shared/Licenses/third-party-notices.zip"
fi

cat > "$WORK/shared/Licenses/BUILD-METADATA.txt" <<META
schema-source-mode=${MODE}
rime-ice-repository=https://github.com/${ICE_REPO}
rime-ice-commit=${ICE_REF}
rime-ice-source-sha256=${ICE_SHA256}
rime-prelude-repository=https://github.com/${PRELUDE_REPO}
rime-prelude-commit=${PRELUDE_REF}
rime-prelude-source-sha256=${PRELUDE_SHA256}
rime-essay-repository=https://github.com/${ESSAY_REPO}
rime-essay-commit=${ESSAY_REF}
rime-essay-source-sha256=${ESSAY_SHA256}
META

mkdir -p "$OUT"
rm -f "$OUT/SharedSupport.zip" "$OUT/rime-ice.zip"
# SharedSupport.zip is what the app expands into its sandbox shared directory.
(cd "$WORK/shared" && zip -qr -X "$OUT/SharedSupport.zip" .)
# Keep the complete fixed rime-ice source/config payload as the user-data zip.
(cd "$WORK/src/ice" && zip -qr -X "$OUT/rime-ice.zip" .)

python3 - "$OUT/SharedSupport.zip" "$OUT/rime-ice.zip" "$MODE" <<'PY'
import sys, zipfile
shared, ice, mode = sys.argv[1:]
for path in (shared, ice):
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad: raise SystemExit(f'corrupt ZIP member: {bad}')
with zipfile.ZipFile(shared) as z:
    names = set(z.namelist())
    required = {'default.yaml', 'hamster.yaml', 'rime_ice.schema.yaml', 'rime_ice.dict.yaml'}
    missing = sorted(required - names)
    if missing: raise SystemExit('SharedSupport missing: ' + ', '.join(missing))
    if not any(n.startswith('Licenses/') for n in names): raise SystemExit('license payload missing')
    has_bin = any(n.endswith(('.bin', '.prism.bin', '.table.bin')) for n in names)
    if mode == 'source-only' and has_bin: raise SystemExit('source-only archive unexpectedly contains generated binaries')
print(f'validated {mode}: {shared} and {ice}')
PY
printf '%s\n' "Wrote $OUT/SharedSupport.zip" "Wrote $OUT/rime-ice.zip" "Mode: $MODE"
[ "$KEEP_WORK" -eq 0 ] || printf '%s\n' "Work tree retained at $WORK"
