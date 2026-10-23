#!/usr/bin/env bash
# Run the emulated EVPN e2e lane on a target host. Primarily for CI: it runs in the CI image and
# drives a remote VM over SSH (SSH_REMOTE set). It can also run directly on a privileged local
# host (SSH_REMOTE unset) to exercise the same procedure without a VM. It exports the base images
# to tarballs and, on the target, loads a local registry, builds the EE and appliance images, and
# runs test/e2e/run.sh.
#
# Env:
#   SSH_REMOTE   user@host of the target VM; UNSET -> run on this host (needs root + podman/systemd)
#   SSH_OPTS     ssh/scp options, word-split (remote only), e.g.
#                "-i /path/key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
#   FRR_IMAGE, NODE_EXPORTER_IMAGE   
#       REQUIRED: the appliance's embedded FRR / node-exporter
#       (CI injects the metallb-frr / prometheus-node-exporter deps; pass them explicitly locally).
#   CI_IMAGE
#   EE_BASE_IMAGE
#   APPLIANCE_BASE_IMAGE
#       exported base images; the OS bases default to public images (CI injects in-cluster
#       registry pullspecs). A bare ref is a docker:// pullspec; an explicit skopeo transport is
#       honored (CI_IMAGE has no public image, so it defaults to
#       containers-storage:localhost/evpn-gateway-appliance-ci:local).
#   REGISTRY_AUTH_FILE   pull secret for the export (default: local docker config; used only if present)
#   ARTIFACTS    local dir the lane's artifacts are collected into (default /tmp/ega/artifact; Prow
#                sets it). For a remote target they are copied back here off the target.
set -euo pipefail

# This script installs nothing -- provisioning handles tools. skopeo does the base-image export
# here, so require it; the target's tools are checked in each step script below.
command -v skopeo >/dev/null || { echo "run_remote: required tool not found: skopeo" >&2; exit 1; }

# Progress banner, so the phases stand out in CI logs.
banner() { printf '\n========== run_remote: %s ==========\n' "$*"; }

# Base images. FRR and node-exporter are required inputs (no public default that runs as the
# appliance's embedded payload); CI injects them, pass them explicitly locally. The OS bases
# default to public images.
readonly FRR_IMAGE="${FRR_IMAGE:?set FRR_IMAGE (CI: the metallb-frr dependency)}"
readonly NODE_EXPORTER_IMAGE="${NODE_EXPORTER_IMAGE:?set NODE_EXPORTER_IMAGE (CI: the prometheus-node-exporter dependency)}"
readonly EE_BASE_IMAGE="${EE_BASE_IMAGE:-quay.io/centos/centos:stream10}"
readonly APPLIANCE_BASE_IMAGE="${APPLIANCE_BASE_IMAGE:-quay.io/centos-bootc/centos-bootc:stream10}"
readonly CI_IMAGE="${CI_IMAGE:-containers-storage:localhost/evpn-gateway-appliance-ci:local}"

# Pull secret for the skopeo export, used only if the file exists (public base images need
# none). Pass REGISTRY_AUTH_FILE to point at a specific secret (CI); defaults to the local
# docker config.
REGISTRY_AUTH_FILE="${REGISTRY_AUTH_FILE:-${HOME:-}/.docker/config.json}"
auth=()
[[ -f "${REGISTRY_AUTH_FILE}" ]] && auth=(--authfile "${REGISTRY_AUTH_FILE}")

# Local dir the e2e artifacts are collected into; Prow sets ARTIFACTS. For a remote target the
# lane writes to a fixed path on the target and we copy it back here; for a local run the lane
# writes straight here.
readonly ARTIFACTS="${ARTIFACTS:-/tmp/ega/artifact}"

# Target transport: remote (ssh/scp with SSH_OPTS) or local (run directly). lane_artifacts is
# where run.sh writes on the target (copied back for remote; already local otherwise).
if [[ -n "${SSH_REMOTE:-}" ]]; then
    read -r -a ssh_opts <<< "${SSH_OPTS:-}"
    echo "run_remote: target is remote -> ${SSH_REMOTE}"
    lane_artifacts=/tmp/ega/artifact
else
    echo "run_remote: target is local"
    lane_artifacts="${ARTIFACTS}"
fi

# Scratch staging dir (the same path is created on the target). On exit, tear down the target:
# the scratch dir, the registry container, and the host state the steps wrote (run.sh tears down
# its own clab topology). Runs on the VM too when remote -- best-effort, harmless if already gone.
readonly WORK="$(mktemp -d)"
cleanup() {
    rm -rf "${WORK}"
    # Leave the artifact dir (/tmp/ega/artifact): it is the collected output locally, and already
    # copied back from a remote target. The rest under /tmp/ega is scratch (the extracted source
    # and the work dir, which holds the throwaway key).
    local teardown='podman rm -f mirror >/dev/null 2>&1 || true; rm -rf /tmp/ega/build /tmp/ega/work /tmp/ega/empty-auth.json /etc/containers/registries.conf.d/99-local.conf'
    if [[ -n "${SSH_REMOTE:-}" ]]; then
        ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "rm -rf '${WORK}'; sudo sh -c '${teardown}'" >/dev/null 2>&1 || true
    else
        sudo sh -c "${teardown}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# Run one shipped step on the target, as root.
run_step() {
    local script="$1"
    if [[ -n "${SSH_REMOTE:-}" ]]; then
        ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "sudo bash ${WORK}/${script}"
    else
        sudo bash "${WORK}/${script}"
    fi
}

# --- Build the ship directory: base-image tarballs + the three step scripts ------------
save_image() {
    echo "run_remote: exporting $1 -> $2"
    # A bare reference is a docker:// registry pullspec; an explicit skopeo transport (e.g.
    # containers-storage:... for a local-canary CI image) is passed through as given.
    # --remove-signatures: a docker-archive tarball can't store signatures (signed registries
    # like registry.redhat.io otherwise fail), and they aren't needed for this flow.
    case "$1" in
        *://* | containers-storage:*)
            skopeo copy --remove-signatures "$1" "docker-archive:${WORK}/$2" ;;
        *)
            # --src-tls-verify=false tolerates an untrusted source cert (e.g. the in-cluster CI
            # registry); CI images are pulled by digest, so content is verified regardless.
            skopeo copy --remove-signatures --src-tls-verify=false "${auth[@]}" "docker://$1" "docker-archive:${WORK}/$2" ;;
    esac
}
# The exports are independent, so run them concurrently and wait for all (overlaps each
# image's download/decompress/digest work).
banner "export base images"
pids=()
save_image "${FRR_IMAGE}"            metallb-frr.tar &                pids+=($!)
save_image "${NODE_EXPORTER_IMAGE}"  prometheus-node-exporter.tar &  pids+=($!)
save_image "${EE_BASE_IMAGE}"        ee-base.tar &                   pids+=($!)
save_image "${CI_IMAGE}"             ci.tar &                        pids+=($!)
save_image "${APPLIANCE_BASE_IMAGE}" appliance-base.tar &            pids+=($!)
export_rc=0
for p in "${pids[@]}"; do wait "${p}" || export_rc=1; done
[ "${export_rc}" -eq 0 ] || { echo "run_remote: a base-image export failed" >&2; exit 1; }

# load.sh: start a local insecure registry on the target and load the base images into it.
cat > "${WORK}/load.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
for c in podman skopeo; do command -v "$c" >/dev/null || { echo "load: required tool not found: $c" >&2; exit 1; }; done
[ -S /run/podman/podman.sock ] || { echo "load: /run/podman/podman.sock not found (provisioning must enable podman.socket)" >&2; exit 1; }
mkdir -p /etc/containers/registries.conf.d
printf '[[registry]]\nlocation = "localhost:5000"\ninsecure = true\n' > /etc/containers/registries.conf.d/99-local.conf
podman rm -f mirror >/dev/null 2>&1 || true
podman run -d --name mirror -p 5000:5000 quay.io/libpod/registry:2.8.2 >/dev/null
until curl -sf http://localhost:5000/v2/ >/dev/null; do sleep 2; done
skopeo copy --dest-tls-verify=false docker-archive:./metallb-frr.tar              docker://localhost:5000/ocp/metallb-frr:latest
skopeo copy --dest-tls-verify=false docker-archive:./prometheus-node-exporter.tar docker://localhost:5000/ocp/prometheus-node-exporter:latest
skopeo copy --dest-tls-verify=false docker-archive:./ee-base.tar                  docker://localhost:5000/openshift/centos:stream10
skopeo copy --dest-tls-verify=false docker-archive:./appliance-base.tar           docker://localhost:5000/centos-bootc/centos-bootc:stream10
# The CI image is used by podman directly (not from the registry): load it into local storage
# under the tag the Makefile and run.sh expect.
skopeo copy docker-archive:./ci.tar containers-storage:localhost/evpn-gateway-appliance-ci:local
EOF

# build.sh: build the EE and the appliance images (:ci parent + vfs :nested-ci child) on the
# target, using the passed-in CI image and the base images in the local registry.
cat > "${WORK}/build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
reg=localhost:5000
for c in podman make; do command -v "$c" >/dev/null || { echo "build: required tool not found: $c" >&2; exit 1; }; done
# Source comes from the CI image (it bakes the repo at /src); the CI image is already loaded.
rm -rf /tmp/ega/build && mkdir -p /tmp/ega/build
podman run --rm --user 0 localhost/evpn-gateway-appliance-ci:local tar -C /src -cf - . | tar -C /tmp/ega/build -xf -
cd /tmp/ega/build
# Build the EE with the passed-in CI image (ee-image no longer rebuilds it) and the EE base
# from the local registry.
EGA_EE_BASE="${reg}/openshift/centos:stream10" make ee-image
# Appliance nested-ci image (:ci parent + vfs child) via the make targets. The bases come from
# the on-VM local registry, so override them to its paths and pass APPLIANCE_BUILD_ARGS so the
# Containerfile's build-time skopeo can reach it (--network=host + the insecure drop-in). The
# empty auth file satisfies the target's secret mount; the local registry needs no credentials.
echo '{}' > /tmp/ega/empty-auth.json
make nested-ci-appliance-image \
    BOOTC_BASE="${reg}/centos-bootc/centos-bootc:stream10" \
    FRR_IMAGE="${reg}/ocp/metallb-frr:latest" \
    NODE_EXPORTER_IMAGE="${reg}/ocp/prometheus-node-exporter:latest" \
    CONTAINER_AUTH_FILE=/tmp/ega/empty-auth.json \
    APPLIANCE_CI_BUILD_ARGS="--network=host -v /etc/containers/registries.conf.d/99-local.conf:/etc/containers/registries.conf.d/99-local.conf:ro"
EOF

# e2e.sh: run the lane (repo-default image tags, so no EGA_* image overrides). Pin the artifact
# dir so we know where to collect from; run.sh makes it world-readable on exit.
cat > "${WORK}/e2e.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /tmp/ega/build
EGA_ARTIFACT_DIR="${lane_artifacts}" bash test/e2e/run.sh
EOF

chmod +x "${WORK}"/*.sh

# --- Ship to the target (remote only) -------------------------------------------------
if [[ -n "${SSH_REMOTE:-}" ]]; then
    banner "ship to ${SSH_REMOTE}:${WORK}"
    ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "mkdir -p ${WORK}"
    scp "${ssh_opts[@]}" "${WORK}"/* "${SSH_REMOTE}:${WORK}/"
fi

# --- Run the procedure on the target --------------------------------------------------
banner "load base images into the target registry"; run_step load.sh
banner "build EE + appliance images on the target"; run_step build.sh
banner "run e2e"
e2e_rc=0; run_step e2e.sh || e2e_rc=$?

# Collect artifacts even on failure (that is when they matter most). For a remote target, copy
# the lane's artifact dir back into the local ARTIFACTS dir -- run.sh made it world-readable, so
# the SSH user can tar it without sudo. For a local run the lane already wrote straight there.
if [[ -n "${SSH_REMOTE:-}" ]]; then
    banner "collect artifacts -> ${ARTIFACTS}"
    mkdir -p "${ARTIFACTS}"
    if ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "tar -C '${lane_artifacts}' -cf - . 2>/dev/null" \
        | tar -C "${ARTIFACTS}" -xf - 2>/dev/null; then :; else
        echo "run_remote: artifact copy-back failed or nothing to collect (continuing)" >&2
    fi
fi

banner "done"
[ "${e2e_rc}" -eq 0 ] || { echo "run_remote: e2e failed (rc=${e2e_rc})" >&2; exit "${e2e_rc}"; }
