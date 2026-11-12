#!/usr/bin/env bash
# Runner-agnostic entry point for the kind peers lane. Same contract as test/e2e/run.sh.
# Additional env: EGA_KIND_CLUSTER, EGA_KIND_WORKERS, OVN_K_IMAGE.
set -euo pipefail

EGA_E2E_IMAGE="${EGA_E2E_IMAGE:-localhost/evpn-gateway-appliance-ci:local}"
EGA_NODE_IMAGE="${EGA_NODE_IMAGE:-localhost/evpn-appliance-rhel10:nested-ci}"
EGA_EE_IMAGE="${EGA_EE_IMAGE:-localhost/evpn-gateway-appliance-ee:local}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
EGA_ARTIFACT_DIR="${EGA_ARTIFACT_DIR:-/tmp/ega/artifact}"
EGA_STAGE="${EGA_STAGE:-full}"
EGA_KIND_CLUSTER="${EGA_KIND_CLUSTER:-ega-evpn-kind}"
EGA_KIND_WORKERS="${EGA_KIND_WORKERS:-2}"
EGA_RUNTIME_SOCK="${EGA_RUNTIME_SOCK:-/run/podman/podman.sock}"

engine="$(command -v podman || command -v docker)"

src_mount=()
if [ -n "${EGA_E2E_SRC:-}" ]; then
	src_mount=(-v "${EGA_E2E_SRC}:/src:ro,Z")
fi

if [ "$(id -u)" != 0 ]; then
	echo "error: this lane requires rootful podman; re-run under sudo" >&2
	exit 1
fi
if [ ! -S "$EGA_RUNTIME_SOCK" ]; then
	echo "error: podman API socket not found at $EGA_RUNTIME_SOCK" >&2
	exit 1
fi

mkdir -p "$EGA_WORK_DIR" "$EGA_ARTIFACT_DIR" /run/netns

rc=0
"$engine" run --rm --privileged --net=host --pid=host --user 0 \
	-v "$EGA_RUNTIME_SOCK:$EGA_RUNTIME_SOCK" \
	-v /run/netns:/run/netns:rshared \
	"${src_mount[@]}" \
	-v "$EGA_WORK_DIR:$EGA_WORK_DIR:Z" \
	-v "$EGA_ARTIFACT_DIR:$EGA_ARTIFACT_DIR:Z" \
	-e "EGA_NODE_IMAGE=$EGA_NODE_IMAGE" \
	-e "EGA_EE_IMAGE=$EGA_EE_IMAGE" \
	-e "EGA_RUNTIME_SOCK=$EGA_RUNTIME_SOCK" \
	-e "EGA_WORK_DIR=$EGA_WORK_DIR" \
	-e "EGA_ARTIFACT_DIR=$EGA_ARTIFACT_DIR" \
	-e "EGA_STAGE=$EGA_STAGE" \
	-e "EGA_KIND_CLUSTER=$EGA_KIND_CLUSTER" \
	-e "EGA_KIND_WORKERS=$EGA_KIND_WORKERS" \
	-e "OVN_K_IMAGE=${OVN_K_IMAGE:-}" \
	-w /src/test/e2e-kind \
	"$EGA_E2E_IMAGE" ./entrypoint.sh || rc=$?

chmod -R a+rX "$EGA_ARTIFACT_DIR" 2>/dev/null || true
exit "$rc"
