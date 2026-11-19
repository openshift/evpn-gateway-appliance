#!/usr/bin/env bash
# In-container steps for the e2e lane. Runs INSIDE the pinned CI image (Dockerfile.ci),
# launched by run.sh with the host runtime socket mounted, so containerlab's node
# containers are siblings on the host runtime with the host kernel.
#
# Kind cluster, the ovn-kubernetes chart, frr-k8s, containerlab appliance/relay/TGW,
# deploy.yml, which discovers the frr-k8s pods.
# Fails unless each kind node is BGP Established.
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
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
export EGA_WORK_DIR
cluster="${EGA_KIND_CLUSTER:-ega-evpn-kind}"
self_dir="$(cd "$(dirname "$0")" && pwd)"
kind_dir="${self_dir}/kind"
topo_file="evpn-kind.clab.yml"

# containerlab talks to the mounted host socket; podman is its runtime.
export DOCKER_HOST="unix://${EGA_RUNTIME_SOCK}"
export CONTAINERLAB_RUNTIME="podman"
export KIND_EXPERIMENTAL_PROVIDER="podman"

lab_dir="${EGA_WORK_DIR}/lab-kind"
mkdir -p "$lab_dir"
kubeconfig="${lab_dir}/kubeconfig"
export KUBECONFIG="$kubeconfig"

runtime() {
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" "$@"
}

destroy_lab() {
	if [ -f "${lab_dir}/${topo_file}" ]; then
		containerlab destroy -t "${lab_dir}/${topo_file}" --cleanup || true
	fi
	kind delete cluster --name "$cluster" || true
}

if [ "$stage" = "destroy" ]; then
	destroy_lab
	exit 0
fi

# Tear the topology down on exit for `full`; leave it up for `deploy`. Do NOT `exec` past
# this point, or the trap is lost and the lab leaks.
# shellcheck disable=SC2329 # invoked through the EXIT trap below
cleanup() {
	if [ "$stage" = deploy ]; then
		echo ">> stage=deploy; leaving kind and containerlab up" >&2
		return
	fi
	destroy_lab
}
trap cleanup EXIT

# ansible reaches the nodes over SSH, so generate an ephemeral keypair; the topology binds
# its public key into each node's root authorized_keys (the image has no cloud-init).
ssh_key="${lab_dir}/ssh/id_ega"
mkdir -p "${lab_dir}/ssh"
[ -f "$ssh_key" ] || ssh-keygen -t ed25519 -N '' -C ega-e2e -f "$ssh_key" >/dev/null
chmod 644 "${ssh_key}.pub"
export EGA_SSH_PUBKEY="${ssh_key}.pub"

RELAY_PRIVATE_IP=10.100.0.1
export RELAY_PRIVATE_IP
export EGA_KIND_CLUSTER="$cluster"
"${kind_dir}/setup-cluster.sh"

kind_nodes=()
while IFS= read -r node; do
	[ -n "$node" ] && kind_nodes+=("$node")
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
kind_node_ips=()
while IFS= read -r ip; do
	[ -n "$ip" ] && kind_node_ips+=("$ip")
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
if [ "${#kind_node_ips[@]}" -eq 0 ]; then
	echo "error: no kind node IPs" >&2
	exit 1
fi
echo ">> kind nodes: ${kind_node_ips[*]}"

# containerlab writes its lab dir (clab-<name>/) NEXT TO the topology file, and the repo
# is mounted read-only. Stage the topology into the writable work dir and deploy from
# there so clab has somewhere to write.
cp "${kind_dir}/topology/${topo_file}" "$lab_dir/"
topo="${lab_dir}/${topo_file}"
lab=$(awk '$1 == "name:" { print $2; exit }' "$topo")
echo ">> containerlab deploy"
EGA_NODE_IMAGE="$EGA_NODE_IMAGE" containerlab deploy -t "$topo" --reconfigure

# The nodes are still booting right after deploy (sshd starts only after host-key
# generation), so wait for it instead of racing the boot.
export ANSIBLE_HOST_KEY_CHECKING=False
inv="${lab_dir}/clab-${lab}/ansible-inventory.yml"
echo ">> waiting for SSH"
ansible -i "$inv" all -u root --private-key "$ssh_key" \
	-m ansible.builtin.wait_for_connection -a 'timeout=120'

tgw_ctr="clab-${lab}-tgw"
relay_ctr="clab-${lab}-relay"
runtime network connect kind "$tgw_ctr"
tgw_kind_ip=$(runtime inspect -f '{{with index .NetworkSettings.Networks "kind"}}{{.IPAddress}}{{end}}' "$tgw_ctr")
if [ -z "$tgw_kind_ip" ]; then
	echo "error: TGW has no address on the kind network" >&2
	exit 1
fi
echo ">> TGW kind IP: ${tgw_kind_ip}"
for node in "${kind_nodes[@]}"; do
	runtime exec "$node" ip route replace 10.100.0.0/16 via "$tgw_kind_ip"
	runtime exec "$node" ip route replace 10.44.44.0/24 via "$tgw_kind_ip"
done
for ip in "${kind_node_ips[@]}"; do
	runtime exec "$relay_ctr" ip route replace "${ip}/32" via 10.100.0.2
done

# The kind nodes are the workload VTEP. This has to exist before deploy.yml's
# health check, which requires a remote VTEP learned from these peers.
"${kind_dir}/prepare-evpn.sh"

# Stage the e2e inventory into the work dir so the EE (launched below as a sibling via
# the host socket) can bind it: podman-remote resolves bind sources on the host, and run.sh
# mounts the work dir at the same path on the host and here. Remove any previous copy first:
# the work dir persists across runs, and `cp -r` into an existing dir would nest
# (inventory/inventory/) and silently reuse the stale inventory from an earlier run.
rm -rf "${lab_dir}/inventory"
cp -r "${kind_dir}/inventory" "${lab_dir}/inventory"

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
	shift
	echo ">> ansible-playbook ${pb} (via execution environment: $EGA_EE_IMAGE)"
	runtime run --rm --net=host --user 0 \
		-v "${lab_dir}:${lab_dir}:Z" \
		-e ANSIBLE_HOST_KEY_CHECKING=False \
		-e "KUBECONFIG=${kubeconfig}" \
		-w "${lab_dir}" \
		"$EGA_EE_IMAGE" \
		ansible-playbook -i "${lab_dir}/inventory/hosts.yml" \
			"$pb" \
			"$@" \
			-u root --private-key "$ssh_key"
}

# The kind network is the workload VPC for this lane. wg-quick installs it
# from AllowedIPs once deploy brings the tunnel up, which is what covers the
# node VTEP addresses. 10.44.44.2 is not on-link until then.
kind_cidr="$(tr -d '[:space:]' < "${EGA_WORK_DIR}/kind-cidr")"
if [ -z "$kind_cidr" ]; then
	echo "error: kind network CIDR was not recorded" >&2
	exit 1
fi
echo ">> workload VPC CIDR ${kind_cidr}"
ee_playbook network.evpn_gateway_test.simulate
ee_playbook network.evpn_gateway.deploy \
	-e frr_k8s_ns=frr-k8s-system \
	-e frr_k8s_lbl=app=frr-k8s \
	-e "workload_vpc_cidr=${kind_cidr}"

echo ">> frr-k8s discovery and relay BGP peering ok"
exit 0
