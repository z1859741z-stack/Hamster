#!/usr/bin/env bash
# Compatibility entry point for the pinned aggregate framework and fixed schema build.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
if [[ "${1:-}" == "--help" ]]; then
  echo "Usage: prepare-ci.sh (no arguments); use prepare-rime-framework.sh and build-schema-fixed.sh"; exit 0
fi
[[ "$#" -eq 0 ]] || { echo "prepare-ci: stale split-framework arguments are not supported" >&2; exit 2; }
bash "$root/ci_scripts/prepare-rime-framework.sh"
bash "$root/ci_scripts/build-schema-fixed.sh"
