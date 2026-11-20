#!/usr/bin/env bash
# In-container steps for the e2e lane. Runs INSIDE the pinned CI image (Dockerfile.ci),
# launched by run.sh with the host runtime socket mounted, so containerlab's node
# containers are siblings on the host runtime with the host kernel.
#
# Stages (EGA_STAGE):
#   full     deploy the fabric (containerlab + the collection's deploy.yml), validate, tear down.
#   deploy   same as full but leave the lab up for inspection.
#   destroy  tear down a lab left up by `deploy`.
set -euo pipefail

stage="${EGA_STAGE:-full}"
scenario="${EGA_SCENARIO:-base}"
: "${EGA_NODE_IMAGE:?}"
: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_EE_IMAGE:?}"
EGA_TOPOLOGY="${EGA_TOPOLOGY:-evpn.clab.yml}"
EGA_INVENTORY="${EGA_INVENTORY:-inventory}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"

case "$scenario" in
	base|relay-ha) ;;
	*)
		echo "error: unsupported EGA_SCENARIO=$scenario" >&2
		exit 2
		;;
esac

self_dir="$(cd "$(dirname "$0")" && pwd)"

# containerlab talks to the mounted host socket; podman is its runtime.
export DOCKER_HOST="unix://${EGA_RUNTIME_SOCK}"
export CONTAINERLAB_RUNTIME="podman"

src_topo="${self_dir}/topology/${EGA_TOPOLOGY}"

# containerlab writes its lab dir (clab-<name>/) NEXT TO the topology file, and the repo
# is mounted read-only. Stage the topology into the writable work dir and deploy from
# there so clab has somewhere to write.
lab_dir="${EGA_WORK_DIR}/lab"
mkdir -p "$lab_dir"
cp "$src_topo" "$lab_dir/"
topo="${lab_dir}/$(basename "$src_topo")"
cd "$lab_dir"

if [ "$stage" = "destroy" ]; then
	echo ">> containerlab destroy: $topo"
	exec containerlab destroy -t "$topo" --cleanup
fi

# ansible reaches the nodes over SSH, so generate an ephemeral keypair; the topology binds
# its public key into each node's root authorized_keys (the image has no cloud-init).
ssh_key="${lab_dir}/ssh/id_ega"
mkdir -p "${lab_dir}/ssh"
[ -f "$ssh_key" ] || ssh-keygen -t ed25519 -N '' -C ega-e2e -f "$ssh_key" >/dev/null
chmod 644 "${ssh_key}.pub"
export EGA_SSH_PUBKEY="${ssh_key}.pub"

# Tear the topology down on exit for `full`; leave it up for `deploy`. Do NOT `exec` past
# this point, or the trap is lost and the lab leaks.
# shellcheck disable=SC2329 # invoked through the EXIT trap below
cleanup() {
	if [ "$stage" = deploy ]; then
		echo ">> stage=deploy; leaving lab up for inspection: $topo" >&2
		return
	fi
	containerlab destroy -t "$topo" --cleanup || true
}
trap cleanup EXIT

echo ">> containerlab deploy: $topo"
EGA_NODE_IMAGE="$EGA_NODE_IMAGE" containerlab deploy -t "$topo" --reconfigure

# The 7503 lab has a shared L2 underlay. Containerlab creates all veths only after
# deployment, so configuring its bridge from a topology exec hook races link creation.
# Attach the links after deploy instead, before Ansible starts configuring BGP.
if [ "$EGA_TOPOLOGY" = evpn-7503.clab.yml ]; then
	container_name="clab-ega-7503-underlay-switch"
	# The single-quoted script is evaluated inside the switch container.
	# shellcheck disable=SC2016
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$container_name" \
		bash -c 'for i in 1 2 3; do nmcli dev set "eth${i}" managed no 2>/dev/null || true; done
		systemctl stop NetworkManager 2>/dev/null || true
		ip link add br-underlay type bridge 2>/dev/null || true
		ip link set br-underlay up
		for i in 1 2 3; do
			for attempt in $(seq 1 60); do
				if ip link set "eth${i}" master br-underlay 2>/dev/null; then
					ip link set "eth${i}" up
					break
				fi
				sleep 1
			done
		done'
fi

# The nodes are still booting right after deploy (sshd starts only after host-key
# generation), so wait for it instead of racing the boot.
export ANSIBLE_HOST_KEY_CHECKING=False
lab_name="$(awk '$1 == "name:" {print $2; exit}' "$topo")"
inv="${lab_dir}/clab-${lab_name}/ansible-inventory.yml"
echo ">> waiting for SSH on all nodes"
ansible -i "$inv" all -u root --private-key "$ssh_key" \
	-m ansible.builtin.wait_for_connection -a 'timeout=120'

# Stage the e2e inventory into the work dir so the EE (launched below as a sibling via
# the host socket) can bind it: podman-remote resolves bind sources on the host, and run.sh
# mounts the work dir at the same path on the host and here. Remove any previous copy first:
# the work dir persists across runs, and `cp -r` into an existing dir would nest
# (inventory/inventory/) and silently reuse the stale inventory from an earlier run.
rm -rf "${lab_dir}/inventory"
cp -r "${self_dir}/${EGA_INVENTORY}" "${lab_dir}/inventory"

# Run the collection's deploy.yml from the execution environment — the same artifact AAP
# runs. The EE carries the collection and its derived deps (wireguard-tools for the
# control-node key generation, netaddr for ansible.utils' ipaddr filters, boto3), so
# nothing is built, installed or pre-seeded here. It joins the host network to reach the
# nodes on the clab management network, and runs as root to read the (root-owned) key and
# inventory and write ansible's temp dirs.
# Run a collection playbook from the execution environment. The toolchain ships
# podman-remote (not a local podman): launch the EE as a sibling on the host runtime
# through the same mounted socket containerlab uses.
ee_playbook() {
	local pb="$1"
	echo ">> ansible-playbook ${pb} (via execution environment: $EGA_EE_IMAGE)"
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" run --rm --net=host --user 0 \
		-v "${lab_dir}:${lab_dir}:Z" \
		-e ANSIBLE_HOST_KEY_CHECKING=False \
		-w "${lab_dir}" \
		"$EGA_EE_IMAGE" \
		ansible-playbook -i "${lab_dir}/inventory/hosts.yml" \
			"$pb" \
			-u root --private-key "$ssh_key"
}

# Build the simulated on-prem side (trunk + fake hosts) BEFORE the product deploy so
# the appliance role finds the trunk to build its VTEP on; deploy the product; then run
# the simulated-host data-plane checks.
ee_playbook network.evpn_gateway_test.simulate
ee_playbook network.evpn_gateway.deploy
ee_playbook network.evpn_gateway_test.healthcheck

# Exercise relay HA independently of the collection's deploy health check.  The 7503
# topology uses two relays with the same EVPN VNIs, so stopping FRR on either relay must
# leave all three stretched networks reachable through the other relay.
if [ "$EGA_TOPOLOGY" = evpn-7503.clab.yml ]; then
	assert_relay_failover() {
		local relay="$1"
		local failed=0
		local node="clab-ega-7503-${relay}"
		local targets=(
			"appliance vm-production 10.42.1.2"
			"appliance vm-staging 10.42.2.2"
			"appliance vm-management 10.42.3.2"
			"workload - 10.42.1.1"
			"workload - 10.42.2.1"
			"workload - 10.42.3.1"
		)

		echo ">> relay failover: stopping FRR on ${relay}"
		podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$node" \
			systemctl stop frr-container.service
		trap 'podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$node" systemctl start frr-container.service >/dev/null 2>&1 || true' RETURN
		sleep 8

		for target in "${targets[@]}"; do
			read -r side namespace address <<<"$target"
			if [ "$side" = appliance ]; then
				command=(ip netns exec "$namespace" ping -c 5 -W 1 "$address")
			else
				command=(ping -c 5 -W 1 "$address")
			fi
			output="$(podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec \
				"clab-ega-7503-${side}" "${command[@]}" 2>&1 || true)"
			if ! grep -qE '[[:space:]]0([.]0+)?% packet loss([[:space:]]|$)' <<<"$output"; then
				echo "ERROR: ${side}/${namespace:-workload} cannot reach ${address} with ${relay} FRR down" >&2
				echo "$output" >&2
				failed=1
			fi
		done

		podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$node" \
			systemctl start frr-container.service
		trap - RETURN
		sleep 15
		[ "$failed" -eq 0 ] || return "$failed"
	}

	assert_relay_failover relay-a
	assert_relay_failover relay-b
fi

echo ">> deploy + simulated-host health checks complete"
exit 0
