#!/usr/bin/env bash
# CI entry for the kind peers lane. Ships and builds the same images as
# test/e2e/run_remote.sh, then runs test/e2e-kind/run.sh on the target.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export EGA_LANE_SCRIPT=test/e2e-kind/run.sh
exec "${here}/../e2e/run_remote.sh"
