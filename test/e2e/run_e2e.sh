#!/usr/bin/env bash
# e2e lane entry point: the emulated EVPN end-to-end lane (containerlab + deploy.yml + health
# checks). A thin, named wrapper over run_remote.sh — the shared lane core — selecting the e2e
# entrypoint. run_remote.sh also works when called directly (the live Prow wiring does); this is the
# symmetric counterpart to run_molecule.sh. All env (SSH_REMOTE, FRR_IMAGE, …) passes through to
# run_remote.sh — see its header and test/e2e/README.md.
set -euo pipefail
export EGA_ENTRYPOINT=entrypoint_e2e.sh
exec "$(dirname "$0")/run_remote.sh" "$@"
