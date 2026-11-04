#!/usr/bin/env bash
# molecule lane entry point: the evpn_onprem_appliance role's Molecule suite (converge, idempotence,
# ownership-reconcile, reboot, teardown). A thin, named wrapper over run_remote.sh — the shared lane
# core — selecting the molecule entrypoint, which also skips the EE build (molecule drives the role
# with the CI image's own ansible, not the shipped EE). All env (SSH_REMOTE, FRR_IMAGE, …) passes
# through to run_remote.sh — see its header and test/e2e/README.md.
set -euo pipefail
export EGA_ENTRYPOINT=entrypoint_molecule.sh
exec "$(dirname "$0")/run_remote.sh" "$@"
