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
: "${EGA_NODE_IMAGE:?}"
: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_EE_IMAGE:?}"
EGA_TOPOLOGY="${EGA_TOPOLOGY:-evpn.clab.yml}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"

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

# The nodes are still booting right after deploy (sshd starts only after host-key
# generation), so wait for it instead of racing the boot.
export ANSIBLE_HOST_KEY_CHECKING=False
inv="${lab_dir}/clab-ega-evpn/ansible-inventory.yml"
echo ">> waiting for SSH on all nodes"
ansible -i "$inv" all -u root --private-key "$ssh_key" \
	-m ansible.builtin.wait_for_connection -a 'timeout=120'

# Stage the e2e inventory into the work dir so the EE (launched below as a sibling via
# the host socket) can bind it: podman-remote resolves bind sources on the host, and run.sh
# mounts the work dir at the same path on the host and here.
cp -r "${self_dir}/inventory" "${lab_dir}/inventory"

# Run the collection's deploy.yml from the execution environment — the same artifact AAP
# runs. The EE carries the collection and its derived deps (wireguard-tools for the
# control-node key generation, netaddr for ansible.utils' ipaddr filters, boto3), so
# nothing is built, installed or pre-seeded here. It joins the host network to reach the
# nodes on the clab management network, and runs as root to read the (root-owned) key and
# inventory and write ansible's temp dirs.
echo ">> ansible-playbook deploy.yml (via execution environment: $EGA_EE_IMAGE)"
# The toolchain ships podman-remote (not a local podman): launch the EE as a sibling on the
# host runtime through the same mounted socket containerlab uses.
podman-remote --url "unix://${EGA_RUNTIME_SOCK}" run --rm --net=host --user 0 \
	-v "${lab_dir}:${lab_dir}:Z" \
	-e ANSIBLE_HOST_KEY_CHECKING=False \
	-w "${lab_dir}" \
	"$EGA_EE_IMAGE" \
	ansible-playbook -i "${lab_dir}/inventory/hosts.yml" \
		network.evpn_gateway.deploy \
		-u root --private-key "$ssh_key"

echo ">> deploy complete (assertions not yet added)"
exit 0
