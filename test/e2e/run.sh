#!/usr/bin/env bash
# Runner-agnostic entry point for the CORENET-7508 emulated EVPN e2e lane.
#
# Run this on any host that has a container runtime and a real kernel
# (kernel networking: veth, netns, VXLAN, netfilter). It launches the pinned toolchain
# image and runs EGA_ENTRYPOINT (default entrypoint_e2e.sh), using EGA_WORK_DIR for its
# working files. No runner-specific
# logic lives here: Prow and a GitHub Actions VM both just set the env below, call this,
# and collect artifacts. See test/e2e/README.md.
#
#   EGA_E2E_IMAGE     pinned toolchain image (the CI image, Dockerfile.ci)  [default: localhost/evpn-gateway-appliance-ci:local]
#   EGA_NODE_IMAGE    node image clab instantiates (the appliance nested-ci image, vfs baked in;
#                     CI overrides with a digest)  [default: localhost/evpn-appliance-rhel10:nested-ci]
#   EGA_EE_IMAGE      execution environment that runs deploy.yml (make ee-image)  [default: localhost/evpn-gateway-appliance-ee:local]
#   EGA_WORK_DIR      host dir for the lab working files (clab lab dir, keys, inventory);
#                     mounted at the same path on host and in-container  [default: /tmp/ega/work]
#   EGA_ARTIFACT_DIR  host dir for produced artifacts (reserved; nothing is written here yet);
#                     out of the checkout, Prow sets this to $ARTIFACTS  [default: /tmp/ega/artifact]
#   EGA_TOPOLOGY      topology file under test/e2e/topology            [default: evpn.clab.yml]
#   EGA_STAGE         full (deploy+validate+teardown) | deploy (leave up) | destroy  [default: full]
#   EGA_E2E_SRC       bind this repo checkout over the image's baked /src for live dev of the
#                     harness (topology/inventory/entrypoint/tests) — NOT the collection,
#                     which comes from EGA_EE_IMAGE. The e2e lane's run_remote.sh sets it to
#                     the extracted tree, which holds the fetched ovn-kubernetes chart, the
#                     multi-network CRDs, and the frr-k8s manifest. (default: unset -> use the baked /src)
#   OVN_K_IMAGE       e2e lane only. ovn-kubernetes image already in the host podman store.
#                     run_remote.sh sets localhost/ovn-kubernetes:ci.
set -euo pipefail

EGA_E2E_IMAGE="${EGA_E2E_IMAGE:-localhost/evpn-gateway-appliance-ci:local}"
EGA_NODE_IMAGE="${EGA_NODE_IMAGE:-localhost/evpn-appliance-rhel10:nested-ci}"
EGA_EE_IMAGE="${EGA_EE_IMAGE:-localhost/evpn-gateway-appliance-ee:local}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
EGA_ARTIFACT_DIR="${EGA_ARTIFACT_DIR:-/tmp/ega/artifact}"
EGA_TOPOLOGY="${EGA_TOPOLOGY:-evpn.clab.yml}"
EGA_STAGE="${EGA_STAGE:-full}"
# The in-container script this lane runs. Defaults to the e2e entrypoint so a direct call
# (and the live Prow wiring) stays unchanged; run_simulate.sh sets entrypoint_simulate.sh
# and run_molecule.sh sets entrypoint_molecule.sh.
EGA_ENTRYPOINT="${EGA_ENTRYPOINT:-entrypoint_e2e.sh}"

engine="$(command -v podman || command -v docker)"

# The toolchain image bakes the repo at /src (COPY . /src). For local dev, set EGA_E2E_SRC to
# the checkout to bind-mount it over the baked /src and iterate without rebuilding the image.
src_mount=()
if [ -n "${EGA_E2E_SRC:-}" ]; then
	src_mount=(-v "${EGA_E2E_SRC}:/src:ro,Z")
fi

# This lane needs ROOTFUL podman: it loads kernel modules (vxlan, wireguard), creates
# netns/VXLAN/netfilter state, and runs privileged systemd nodes. Run it under sudo.
# The container runtime's API socket is mounted into the toolchain image so containerlab
# creates the node containers as SIBLINGS on this host's runtime (not nested), giving
# them the host kernel.
EGA_RUNTIME_SOCK="${EGA_RUNTIME_SOCK:-/run/podman/podman.sock}"
if [ "$(id -u)" != 0 ]; then
	echo "error: this lane requires rootful podman; re-run under sudo" >&2
	exit 1
fi
if [ ! -S "$EGA_RUNTIME_SOCK" ]; then
	echo "error: podman API socket not found at $EGA_RUNTIME_SOCK" >&2
	echo "  enable it: systemctl enable --now podman.socket" >&2
	echo "  or set EGA_RUNTIME_SOCK to its path" >&2
	exit 1
fi

# ovs-vswitchd uses the host openvswitch module (kernel-modules-core on this
# kernel). ovnkube-node watches past the default inotify limits. Route
# advertisements need bridge netfilter loaded so its call-iptables sysctls
# can be turned off.
if [ "$EGA_ENTRYPOINT" = "entrypoint_e2e.sh" ]; then
	if [ ! -d /sys/module/openvswitch ]; then
		modprobe openvswitch 2>/dev/null || dnf install -y "kernel-modules-core-$(uname -r)"
		modprobe openvswitch
	fi
	modprobe br_netfilter 2>/dev/null || true
	current="$(sysctl -n fs.inotify.max_user_watches)"
	if [ "$current" -lt 524288 ]; then
		sysctl -w fs.inotify.max_user_watches=524288
	fi
	current="$(sysctl -n fs.inotify.max_user_instances)"
	if [ "$current" -lt 512 ]; then
		sysctl -w fs.inotify.max_user_instances=512
	fi
	if sysctl -n net.bridge.bridge-nf-call-iptables >/dev/null 2>&1; then
		sysctl -w net.bridge.bridge-nf-call-iptables=0
		sysctl -w net.bridge.bridge-nf-call-ip6tables=0
	fi
fi

mkdir -p "$EGA_WORK_DIR" "$EGA_ARTIFACT_DIR"
# containerlab runs in this container but creates the node containers as siblings on the
# host. To wire their veths it needs to see the nodes' host PIDs (--pid=host) and share
# the netns directory (the "containerlab in a container" requirement). The work dir is
# also mounted at the SAME path inside and on the host, because topology bind sources (e.g.
# the SSH key) are resolved by the host runtime, not inside this container.
mkdir -p /run/netns

ovn_env=()
if [ -n "${OVN_K_IMAGE:-}" ]; then
	ovn_env=(-e "OVN_K_IMAGE=${OVN_K_IMAGE}")
fi

rc=0
"$engine" run --rm --privileged --net=host --pid=host --user 0 \
	-v "$EGA_RUNTIME_SOCK:$EGA_RUNTIME_SOCK" \
	-v /run/netns:/run/netns:rshared \
	"${src_mount[@]}" \
	-v "$EGA_WORK_DIR:$EGA_WORK_DIR:Z" \
	-v "$EGA_ARTIFACT_DIR:$EGA_ARTIFACT_DIR:Z" \
	-e "EGA_NODE_IMAGE=$EGA_NODE_IMAGE" \
	-e "EGA_EE_IMAGE=$EGA_EE_IMAGE" \
	-e "EGA_TOPOLOGY=$EGA_TOPOLOGY" \
	-e "EGA_RUNTIME_SOCK=$EGA_RUNTIME_SOCK" \
	-e "EGA_WORK_DIR=$EGA_WORK_DIR" \
	-e "EGA_ARTIFACT_DIR=$EGA_ARTIFACT_DIR" \
	-e "EGA_STAGE=$EGA_STAGE" \
	"${ovn_env[@]}" \
	-w /src/test/e2e \
	"$EGA_E2E_IMAGE" ./"$EGA_ENTRYPOINT" || rc=$?

# The lane runs as root, so anything written to the artifact dir is root-owned. Make it
# world-readable (and dirs traversable) so an unprivileged caller -- e.g. run_remote.sh's SSH
# user copying artifacts back off the target -- can collect it. Run regardless of the lane's
# exit so failure artifacts are collectable too.
chmod -R a+rX "$EGA_ARTIFACT_DIR" 2>/dev/null || true
exit "$rc"
