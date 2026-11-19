#!/usr/bin/env bash
# Run a CI lane on a target host. Primarily for CI: it runs in the CI image and drives a remote VM
# over SSH (SSH_REMOTE set). It can also run directly on a privileged local host (SSH_REMOTE unset)
# to exercise the same procedure without a VM. It exports the base images to tarballs and, on the
# target, loads a local registry, builds the appliance images (and the EE for the e2e lane), and
# runs test/e2e/run.sh.
#
# Shared core for the lanes: the e2e lane (default), the simulate lane, and the molecule lane
# select the in-container script via EGA_ENTRYPOINT. Call this directly for e2e (backward
# compatible), or go through the named wrappers run_e2e.sh / run_simulate.sh / run_molecule.sh,
# which only set EGA_ENTRYPOINT.
#
# Env:
#   EGA_ENTRYPOINT  in-container lane script run.sh executes; entrypoint_e2e.sh (default),
#                   entrypoint_simulate.sh, or entrypoint_molecule.sh. Also gates the EE
#                   build (built unless molecule).
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
#   RELEASE_IMAGE_LATEST  e2e lane only. Release payload whose ovn-kubernetes image is shipped
#                         to the VM. Ignored when OVN_K_IMAGE is already set.
#   OVN_K_IMAGE  e2e lane only. Pullspec to ship instead of the release lookup. The lane always
#                receives localhost/ovn-kubernetes:ci, the name loaded into the VM store.
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

# Lane selection. The in-container script run.sh launches; defaults to the e2e entrypoint so a
# direct call (and the live Prow wiring) is unchanged. run_simulate.sh sets
# entrypoint_simulate.sh and run_molecule.sh sets entrypoint_molecule.sh.
# The execution environment is consumed by the e2e and simulate entrypoints (they run deploy.yml
# through it), so build it unless this is the molecule lane -- derived from the entrypoint, no extra flag.
readonly EGA_ENTRYPOINT="${EGA_ENTRYPOINT:-entrypoint_e2e.sh}"
if [[ "${EGA_ENTRYPOINT}" == entrypoint_molecule.sh ]]; then build_ee=0; else build_ee=1; fi
readonly build_ee

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

run_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null; then
        sudo "$@"
    else
        echo "run_remote: local target requires root" >&2
        return 1
    fi
}

# Scratch staging dir (the same path is created on the target). On exit, tear down the target:
# the scratch dir, the registry container, and the host state the steps wrote (run.sh tears down
# its own clab topology). Runs on the VM too when remote -- best-effort, harmless if already gone.
WORK="$(mktemp -d)"
readonly WORK
cleanup() {
    rm -rf "${WORK}"
    # Leave the artifact dir (/tmp/ega/artifact): it is the collected output locally, and already
    # copied back from a remote target. The rest under /tmp/ega is scratch (the extracted source
    # and the work dir, which holds the throwaway key).
    local teardown='podman rm -f mirror >/dev/null 2>&1 || true; rm -rf /tmp/ega/build /tmp/ega/work /tmp/ega/empty-auth.json /etc/containers/registries.conf.d/99-local.conf'
    if [[ -n "${SSH_REMOTE:-}" ]]; then
        # shellcheck disable=SC2029 # client-side expansion is intended; the remote shell gets the final path
        ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "rm -rf '${WORK}'; sudo sh -c '${teardown}'" >/dev/null 2>&1 || true
    else
        run_as_root sh -c "${teardown}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# Run one shipped step on the target, as root.
run_step() {
    local script="$1"
    if [[ -n "${SSH_REMOTE:-}" ]]; then
        # shellcheck disable=SC2029 # client-side expansion is intended; the remote shell gets the final path
        ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "sudo bash ${WORK}/${script}"
    else
        run_as_root bash "${WORK}/${script}"
    fi
}

# --- Build the ship directory: base-image tarballs + the three step scripts ------------
save_image() {
    local src="$1" dest="$2"
    shift 2
    echo "run_remote: exporting ${src} -> ${dest}"
    # A bare reference is a docker:// registry pullspec; an explicit skopeo transport (e.g.
    # containers-storage:... for a local-canary CI image) is passed through as given.
    # --remove-signatures: a docker-archive tarball can't store signatures (signed registries
    # like registry.redhat.io otherwise fail), and they aren't needed for this flow.
    # Extra skopeo flags (the ovn export passes --override-os/--override-arch) come from "$@".
    case "$src" in
        *://* | containers-storage:*)
            skopeo copy "$@" --remove-signatures "$src" "docker-archive:${WORK}/${dest}" ;;
        *)
            # --src-tls-verify=false tolerates an untrusted source cert (e.g. the in-cluster CI
            # registry); CI images are pulled by digest, so content is verified regardless.
            skopeo copy "$@" --remove-signatures --src-tls-verify=false "${auth[@]}" "docker://${src}" "docker-archive:${WORK}/${dest}" ;;
    esac
}

# Pullspec of one image inside a release payload. The payload is a small image
# whose layers hold release-manifests/image-references.
release_image_for() {
    local release="$1" component="$2" tmp src
    tmp="$(mktemp -d)"
    # shellcheck disable=SC2064 # tmp is expanded now; the trap must remove this directory
    trap 'rm -rf "'"${tmp}"'"' RETURN
    case "$release" in
        *://* | containers-storage:*) src="$release" ;;
        *) src="docker://${release}" ;;
    esac
    skopeo copy --remove-signatures --src-tls-verify=false \
        --override-os=linux --override-arch="${host_arch}" \
        "${auth[@]}" "$src" "dir:${tmp}" >&2 || return 1
    python3 - "$tmp" "$component" <<'PY' || return 1
import gzip, io, json, os, sys, tarfile

root, name = sys.argv[1], sys.argv[2]
with open(os.path.join(root, "manifest.json"), "rb") as fh:
    manifest = json.loads(fh.read())

def layer_paths():
    if isinstance(manifest, list):
        for layer in manifest[0].get("Layers", []):
            yield os.path.join(root, layer)
        return
    for layer in manifest.get("layers") or []:
        digest = layer["digest"].split(":", 1)[1]
        yield os.path.join(root, digest)
        yield os.path.join(root, "sha256", digest)

found = None
for path in layer_paths():
    if not os.path.isfile(path):
        continue
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] == b"\x1f\x8b":
        data = gzip.decompress(data)
    try:
        tf = tarfile.open(fileobj=io.BytesIO(data), mode="r:")
    except tarfile.TarError:
        continue
    member = None
    for info in tf.getmembers():
        if info.name.endswith("release-manifests/image-references"):
            member = tf.extractfile(info)
            break
    if member is None:
        continue
    found = json.load(member)

if found is None:
    sys.exit("run_remote: release image has no image-references")
for tag in found.get("spec", {}).get("tags", []):
    pullspec = (tag.get("from") or {}).get("name")
    if tag.get("name") == name and pullspec:
        print(pullspec)
        raise SystemExit(0)
sys.exit(f"run_remote: release has no {name} image")
PY
}

# e2e lane: ovn-kubernetes chart at v1.4.0, the NetworkAttachmentDefinition,
# MultiNetworkPolicy, and IPAMClaim CRDs, and the frr-k8s manifest at b43efcb206be.
# The lane bind-mounts the tree this tarball is unpacked into.
fetch_kind_overlay() {
    local dest src chart
    dest="$(mktemp -d)"
    src="$(mktemp -d)"
    # shellcheck disable=SC2064 # dest and src are expanded now; the trap must remove these directories
    trap 'rm -rf "'"${dest}"'" "'"${src}"'"' RETURN
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --filter=blob:none --sparse --branch v1.4.0 \
        https://github.com/ovn-org/ovn-kubernetes.git "${src}/ovn-kubernetes"
    git -C "${src}/ovn-kubernetes" sparse-checkout set helm/ovn-kubernetes
    chart="${src}/ovn-kubernetes/helm/ovn-kubernetes"
    mkdir -p "${dest}/test/e2e/kind/ovnk-helm" "${dest}/test/e2e/kind/manifests"
    find "${chart}" -type f \
        ! -name README.md \
        ! -name README.md.gotmpl \
        ! -name .helmignore \
        ! -name values-single-node-zone-dpu.yaml \
        -printf '%P\0' \
        | tar --null -C "${chart}" -T - -cf - \
        | tar -C "${dest}/test/e2e/kind/ovnk-helm" -xf -
    [ -f "${dest}/test/e2e/kind/ovnk-helm/Chart.yaml" ] || {
        echo "run_remote: ovn-kubernetes chart checkout is empty" >&2
        return 1
    }
    # NetworkAttachmentDefinition from multus-cni v4.1.3, MultiNetworkPolicy v1.0.1,
    # IPAMClaim v0.5.1-alpha.
    curl -fsSL \
        "https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.1.3/deployments/multus-daemonset.yml" \
        | python3 -c 'import sys; docs = sys.stdin.read().split("\n---\n"); sys.stdout.write(docs[1].strip() + "\n")' \
        > "${dest}/test/e2e/kind/manifests/network-attachment-definition.yaml"
    grep -q '^kind: CustomResourceDefinition$' \
        "${dest}/test/e2e/kind/manifests/network-attachment-definition.yaml" || {
        echo "run_remote: NetworkAttachmentDefinition CRD extract is empty" >&2
        return 1
    }
    curl -fsSL -o "${dest}/test/e2e/kind/manifests/multi-networkpolicy.yaml" \
        https://raw.githubusercontent.com/k8snetworkplumbingwg/multi-networkpolicy/refs/tags/v1.0.1/scheme.yml
    curl -fsSL -o "${dest}/test/e2e/kind/manifests/ipamclaims.yaml" \
        https://raw.githubusercontent.com/k8snetworkplumbingwg/ipamclaims/v0.5.1-alpha/artifacts/k8s.cni.cncf.io_ipamclaims.yaml
    curl -fsSL -o "${dest}/test/e2e/kind/manifests/frr-k8s.yaml" \
        https://raw.githubusercontent.com/metallb/frr-k8s/b43efcb206be/config/all-in-one/frr-k8s.yaml
    tar -C "${dest}" -cf "${WORK}/kind-overlay.tar" .
}
# The exports are independent, so run them concurrently and wait for all (overlaps each
# image's download/decompress/digest work). The e2e lane also ships the release
# payload's ovn-kubernetes image.
host_arch="$(uname -m)"
case "${host_arch}" in
    x86_64) host_arch=amd64 ;;
    aarch64) host_arch=arm64 ;;
esac
ovn_pullspec=""
kind_overlay_pid=""
if [[ "${EGA_ENTRYPOINT}" == entrypoint_e2e.sh ]]; then
    command -v python3 >/dev/null || { echo "run_remote: required tool not found: python3" >&2; exit 1; }
    command -v git >/dev/null || { echo "run_remote: required tool not found: git" >&2; exit 1; }
    command -v curl >/dev/null || { echo "run_remote: required tool not found: curl" >&2; exit 1; }
    if [[ -n "${OVN_K_IMAGE:-}" ]]; then
        ovn_pullspec="${OVN_K_IMAGE}"
    else
        : "${RELEASE_IMAGE_LATEST:?e2e lane needs RELEASE_IMAGE_LATEST or OVN_K_IMAGE}"
        ovn_pullspec="$(release_image_for "${RELEASE_IMAGE_LATEST}" ovn-kubernetes)"
    fi
    echo "run_remote: ovn-kubernetes image ${ovn_pullspec}"
    fetch_kind_overlay &
    kind_overlay_pid=$!
fi
banner "export base images"
pids=()
save_image "${FRR_IMAGE}"            metallb-frr.tar &                pids+=($!)
save_image "${NODE_EXPORTER_IMAGE}"  prometheus-node-exporter.tar &  pids+=($!)
save_image "${EE_BASE_IMAGE}"        ee-base.tar &                   pids+=($!)
save_image "${CI_IMAGE}"             ci.tar &                        pids+=($!)
save_image "${APPLIANCE_BASE_IMAGE}" appliance-base.tar &            pids+=($!)
if [[ -n "${ovn_pullspec}" ]]; then
    save_image "${ovn_pullspec}" ovn.tar --override-os=linux --override-arch="${host_arch}" &
    pids+=($!)
fi
export_rc=0
for p in "${pids[@]}"; do wait "${p}" || export_rc=1; done
overlay_rc=0
if [[ -n "${kind_overlay_pid}" ]]; then
    wait "${kind_overlay_pid}" || overlay_rc=1
fi
[ "${export_rc}" -eq 0 ] || { echo "run_remote: a base-image export failed" >&2; exit 1; }
[ "${overlay_rc}" -eq 0 ] || { echo "run_remote: kind chart fetch failed" >&2; exit 1; }

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
if [[ -n "${ovn_pullspec}" ]]; then
    cat >> "${WORK}/load.sh" <<'EOF'
skopeo copy docker-archive:./ovn.tar containers-storage:localhost/ovn-kubernetes:ci
EOF
fi

# build.sh: build the appliance images (:ci parent + vfs :nested-ci child) and, for the e2e lane,
# the EE on the target, using the passed-in CI image and the base images in the local registry.
# build_ee (derived from the entrypoint) gates the EE build; the molecule lane skips it. Written
# in two parts so build_ee is injected from here while the body stays a literal (quoted) heredoc.
cat > "${WORK}/build.sh" <<EOF
#!/usr/bin/env bash
build_ee=${build_ee}
EOF
cat >> "${WORK}/build.sh" <<'EOF'
set -euo pipefail
reg=localhost:5000
for c in podman make; do command -v "$c" >/dev/null || { echo "build: required tool not found: $c" >&2; exit 1; }; done
# Source comes from the CI image (it bakes the repo at /src); the CI image is already loaded.
rm -rf /tmp/ega/build && mkdir -p /tmp/ega/build
podman run --rm --user 0 localhost/evpn-gateway-appliance-ci:local tar -C /src -cf - . | tar -C /tmp/ega/build -xf -
overlay="$(cd "$(dirname "$0")" && pwd)/kind-overlay.tar"
if [ -f "${overlay}" ]; then
    tar -C /tmp/ega/build -xf "${overlay}"
fi
cd /tmp/ega/build
# Build the EE with the passed-in CI image (ee-image no longer rebuilds it) and the EE base
# from the local registry. Only the e2e lane consumes the EE.
if [ "$build_ee" = 1 ]; then
    EGA_EE_BASE="${reg}/openshift/centos:stream10" make ee-image
fi
# Appliance nested-ci image (:ci parent + vfs child) via the make targets. The bases come from
# the on-VM local registry, so override them to its paths; the host engine pulls them as FROM
# stages through the insecure drop-in. The empty auth file satisfies the target's auth-file
# check; the local registry needs no credentials.
echo '{}' > /tmp/ega/empty-auth.json
make nested-ci-appliance-image \
    BOOTC_BASE="${reg}/centos-bootc/centos-bootc:stream10" \
    FRR_IMAGE="${reg}/ocp/metallb-frr:latest" \
    NODE_EXPORTER_IMAGE="${reg}/ocp/prometheus-node-exporter:latest" \
    CONTAINER_AUTH_FILE=/tmp/ega/empty-auth.json
EOF

# lane.sh: run the selected lane (repo-default image tags, so no EGA_* image overrides). Pin the
# artifact dir so we know where to collect from; run.sh makes it world-readable on exit. Pass the
# entrypoint through so run.sh runs the e2e or the molecule in-container script.
ovn_lane_env=""
if [[ -n "${ovn_pullspec}" ]]; then
    ovn_lane_env="OVN_K_IMAGE=localhost/ovn-kubernetes:ci EGA_E2E_SRC=/tmp/ega/build"
fi
cat > "${WORK}/lane.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd /tmp/ega/build
${ovn_lane_env} EGA_ARTIFACT_DIR="${lane_artifacts}" EGA_ENTRYPOINT="${EGA_ENTRYPOINT}" bash test/e2e/run.sh
EOF

chmod +x "${WORK}"/*.sh

# --- Ship to the target (remote only) -------------------------------------------------
if [[ -n "${SSH_REMOTE:-}" ]]; then
    banner "ship to ${SSH_REMOTE}:${WORK}"
    # shellcheck disable=SC2029 # client-side expansion is intended; the remote shell gets the final path
    ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "mkdir -p ${WORK}"
    scp "${ssh_opts[@]}" "${WORK}"/* "${SSH_REMOTE}:${WORK}/"
fi

# --- Run the procedure on the target --------------------------------------------------
banner "load base images into the target registry"; run_step load.sh
banner "build images on the target"; run_step build.sh
banner "run lane (${EGA_ENTRYPOINT})"
lane_rc=0; run_step lane.sh || lane_rc=$?

# Collect artifacts even on failure (that is when they matter most). For a remote target, copy
# the lane's artifact dir back into the local ARTIFACTS dir -- run.sh made it world-readable, so
# the SSH user can tar it without sudo. For a local run the lane already wrote straight there.
if [[ -n "${SSH_REMOTE:-}" ]]; then
    banner "collect artifacts -> ${ARTIFACTS}"
    mkdir -p "${ARTIFACTS}"
    # shellcheck disable=SC2029 # client-side expansion is intended; the remote shell gets the final path
    if ssh "${ssh_opts[@]}" "${SSH_REMOTE}" "tar -C '${lane_artifacts}' -cf - . 2>/dev/null" \
        | tar -C "${ARTIFACTS}" -xf - 2>/dev/null; then :; else
        echo "run_remote: artifact copy-back failed or nothing to collect (continuing)" >&2
    fi
fi

banner "done"
[ "${lane_rc}" -eq 0 ] || { echo "run_remote: lane failed (rc=${lane_rc})" >&2; exit "${lane_rc}"; }
