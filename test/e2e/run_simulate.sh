#!/usr/bin/env bash
# Simulate lane: containerlab, the standalone workload VTEP, and deploy.yml with
# skip_frr_discovery. A thin wrapper over run_remote.sh. A direct call of
# run_remote.sh runs entrypoint_e2e.sh instead. All env (SSH_REMOTE, FRR_IMAGE, …)
# passes through to run_remote.sh — see its header and test/e2e/README.md.
set -euo pipefail
export EGA_ENTRYPOINT=entrypoint_simulate.sh
exec "$(dirname "$0")/run_remote.sh" "$@"
