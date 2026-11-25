#!/usr/bin/env bash
# Static checks for build-schema-fixed.sh. Does not download, build, commit, or push.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILDER="$ROOT/ci_scripts/build-schema-fixed.sh"
[ -f "$BUILDER" ] || { echo "missing $BUILDER" >&2; exit 1; }
bash -n "$BUILDER"
grep -Fq 'ICE_REF="927e1cf1d3eeb9bf4be85e3f684dba4dd485b6f6"' "$BUILDER"
grep -Fq 'PRELUDE_REF="082425ea0684bca36474415d4a0e8db9b016487e"' "$BUILDER"
# rime-essay was dropped in the 2026-11-25 slim-down (no schema imports
# essay.txt); its pin is intentionally gone, do not re-add the check.
grep -Fq 'codeload.github.com' "$BUILDER"
grep -Fq 'source-only' "$BUILDER"
grep -Fq 'schema-source-mode=' "$BUILDER"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=error "$BUILDER"
fi
python3 - "$ROOT/Resources/SharedSupport/SharedSupport.zip" "$ROOT/Resources/SharedSupport/rime-ice.zip" <<'PY'
import pathlib, sys, zipfile
for raw in sys.argv[1:]:
    p = pathlib.Path(raw)
    if not p.is_file():
        print(f"skip absent archive: {p}")
        continue
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None, p
        names = set(z.namelist())
        if p.name == "SharedSupport.zip":
            for required in ("default.yaml", "hamster.yaml", "rime_ice.schema.yaml", "rime_ice.dict.yaml"):
                assert required in names, (p, required)
            assert any(n.startswith("Licenses/") for n in names), p
            assert not any(n.endswith((".bin", ".prism.bin", ".table.bin")) for n in names), p
print("schema-self-test: PASS")
PY
