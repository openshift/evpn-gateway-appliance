#!/usr/bin/env bash
# Run every checker in this directory. Usage: tools/check-all.sh [--offline]
# --offline skips the checks that need the network (external URLs and GitHub pins).
set -uo pipefail
cd "$(dirname "$0")" || exit 1
status=0
run() { echo "== $*"; "$@" || status=1; }
run python3 check-public-safe.py
if [[ "${1:-}" == "--offline" ]]; then
  run python3 check-links.py --offline
else
  run python3 check-links.py
  run python3 check-pins.py
fi
exit $status
