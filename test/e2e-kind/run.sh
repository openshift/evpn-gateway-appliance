#!/usr/bin/env bash
# Runner-agnostic entry point for the kind+OVN-K e2e lane. Same contract as test/e2e/run.sh.
# Additional env: EGA_KIND_CLUSTER, OVN_K_IMAGE, OVN_K_DEPLOY_SCRIPT.
set -euo pipefail

EGA_E2E_IMAGE="${EGA_E2E_IMAGE:-localhost/evpn-gateway-appliance-ci:local}"
EGA_NODE_IMAGE="${EGA_NODE_IMAGE:-localhost/evpn-appliance-rhel10:nested-ci}"
EGA_EE_IMAGE="${EGA_EE_IMAGE:-localhost/evpn-gateway-appliance-ee:local}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
EGA_ARTIFACT_DIR="${EGA_ARTIFACT_DIR:-/tmp/ega/artifact}"
EGA_STAGE="${EGA_STAGE:-full}"
EGA_KIND_CLUSTER="${EGA_KIND_CLUSTER:-ega-evpn-kind}"
EGA_RUNTIME_SOCK="${EGA_RUNTIME_SOCK:-/run/podman/podman.sock}"

engine="$(command -v podman || command -v docker)"

src_mount=()
[ -n "${EGA_E2E_SRC:-}" ] && src_mount=(-v "${EGA_E2E_SRC}:/src:ro,Z")

[ "$(id -u)" = 0 ] || { echo "error: requires rootful podman" >&2; exit 1; }
[ -S "$EGA_RUNTIME_SOCK" ] || { echo "error: socket not found: $EGA_RUNTIME_SOCK" >&2; exit 1; }

mkdir -p "$EGA_WORK_DIR" "$EGA_ARTIFACT_DIR" /run/netns

ovnk_mount=() ovnk_env=()
if [ -n "${OVN_K_DEPLOY_SCRIPT:-}" ]; then
	ovnk_dir="$(dirname "$OVN_K_DEPLOY_SCRIPT")"
	ovnk_mount=(-v "${ovnk_dir}:${ovnk_dir}:ro,Z")
	ovnk_env=(-e "OVN_K_DEPLOY_SCRIPT=${OVN_K_DEPLOY_SCRIPT}")
fi

rc=0
"$engine" run --rm --privileged --net=host --pid=host --user 0 \
	-v "$EGA_RUNTIME_SOCK:$EGA_RUNTIME_SOCK" \
	-v /run/netns:/run/netns:rshared \
	"${src_mount[@]}" \
	"${ovnk_mount[@]}" \
	-v "$EGA_WORK_DIR:$EGA_WORK_DIR:Z" \
	-v "$EGA_ARTIFACT_DIR:$EGA_ARTIFACT_DIR:Z" \
	-e "EGA_NODE_IMAGE=$EGA_NODE_IMAGE" \
	-e "EGA_EE_IMAGE=$EGA_EE_IMAGE" \
	-e "EGA_RUNTIME_SOCK=$EGA_RUNTIME_SOCK" \
	-e "EGA_WORK_DIR=$EGA_WORK_DIR" \
	-e "EGA_ARTIFACT_DIR=$EGA_ARTIFACT_DIR" \
	-e "EGA_STAGE=$EGA_STAGE" \
	-e "EGA_KIND_CLUSTER=$EGA_KIND_CLUSTER" \
	-e "OVN_K_IMAGE=${OVN_K_IMAGE:-}" \
	"${ovnk_env[@]}" \
	-w /src/test/e2e-kind \
	"$EGA_E2E_IMAGE" ./entrypoint.sh || rc=$?

chmod -R a+rX "$EGA_ARTIFACT_DIR" 2>/dev/null || true
exit "$rc"
