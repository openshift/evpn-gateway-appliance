#!/usr/bin/env bash
# In-container orchestration for the kind+OVN-K e2e lane.
# 1. kind cluster + OVN-K EVPN + CRs  2. clab topology  3. bridge TGW->kind
# 4. deploy.yml with discovery  5. verify peering + reachability  6. teardown
set -euo pipefail

stage="${EGA_STAGE:-full}"
: "${EGA_NODE_IMAGE:?}"
: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_EE_IMAGE:?}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
cluster="${EGA_KIND_CLUSTER:-ega-evpn-kind}"
self_dir="$(cd "$(dirname "$0")" && pwd)"
topo_file="evpn-kind.clab.yml"

export DOCKER_HOST="unix://${EGA_RUNTIME_SOCK}"
export CONTAINERLAB_RUNTIME="podman"

lab_dir="${EGA_WORK_DIR}/lab-kind"
mkdir -p "$lab_dir"
kubeconfig="${lab_dir}/kubeconfig"
export KUBECONFIG="$kubeconfig"

if [ "$stage" = "destroy" ]; then
	topo="${lab_dir}/${topo_file}"
	containerlab destroy -t "$topo" --cleanup 2>/dev/null || true
	kind delete cluster --name "$cluster" 2>/dev/null || true
	exit 0
fi

cleanup() {
	[ "$stage" = deploy ] && { echo ">> leaving lab up ($cluster)" >&2; return; }
	containerlab destroy -t "${lab_dir}/${topo_file}" --cleanup 2>/dev/null || true
	kind delete cluster --name "$cluster" 2>/dev/null || true
}
trap cleanup EXIT

# SSH key.
ssh_key="${lab_dir}/ssh/id_ega"
mkdir -p "${lab_dir}/ssh"
[ -f "$ssh_key" ] || ssh-keygen -t ed25519 -N '' -C ega-e2e-kind -f "$ssh_key" >/dev/null
chmod 644 "${ssh_key}.pub"
export EGA_SSH_PUBKEY="${ssh_key}.pub"

# 1. Kind cluster + OVN-K + CRs.
RELAY_PRIVATE_IP=10.100.0.1
export RELAY_PRIVATE_IP
EGA_KIND_CLUSTER="$cluster" "${self_dir}/setup-cluster.sh"

kind_node_ips=()
while IFS= read -r ip; do kind_node_ips+=("$ip"); done \
	< <(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}')
echo ">> kind nodes: ${kind_node_ips[*]}"

# 2. Clab topology.
cp "${self_dir}/topology/${topo_file}" "$lab_dir/"
topo="${lab_dir}/${topo_file}"
echo ">> containerlab deploy"
EGA_NODE_IMAGE="$EGA_NODE_IMAGE" containerlab deploy -t "$topo" --reconfigure

export ANSIBLE_HOST_KEY_CHECKING=False
inv="${lab_dir}/clab-${cluster}/ansible-inventory.yml"
echo ">> waiting for SSH"
ansible -i "$inv" all -u root --private-key "$ssh_key" \
	-m ansible.builtin.wait_for_connection -a 'timeout=120'

# 3. Bridge TGW to kind network.
tgw_ctr="clab-${cluster}-tgw"
echo ">> attaching TGW to kind network"
podman-remote --url "unix://${EGA_RUNTIME_SOCK}" network connect kind "$tgw_ctr" 2>/dev/null || true

# Discover TGW's kind-side IP.
tgw_kind_ip=$(podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$tgw_ctr" \
	sh -c "ip -o -4 addr show | grep '172\.18\.' | awk '{print \$4}' | cut -d/ -f1" 2>/dev/null || echo "")
echo ">> TGW kind IP: ${tgw_kind_ip:-unknown}"

if [ -n "$tgw_kind_ip" ]; then
	# Routes on kind nodes -> relay/onprem via TGW.
	for node in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
		podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$node" \
			sh -c "ip route replace 10.44.44.0/24 via ${tgw_kind_ip}; ip route replace 10.100.0.0/16 via ${tgw_kind_ip}" 2>/dev/null || true
	done
	# Per-node /32 routes on relay for precision.
	relay_ctr="clab-${cluster}-relay"
	for ip in "${kind_node_ips[@]}"; do
		podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$relay_ctr" \
			ip route replace "${ip}/32" via 10.100.0.2 2>/dev/null || true
	done
fi

# 4. Deploy via EE (discovery enabled).
cp -r "${self_dir}/inventory" "${lab_dir}/inventory"
echo ">> ansible-playbook deploy.yml (EE: $EGA_EE_IMAGE)"
podman-remote --url "unix://${EGA_RUNTIME_SOCK}" run --rm --net=host --user 0 \
	-v "${lab_dir}:${lab_dir}:Z" \
	-v "${kubeconfig}:${kubeconfig}:ro,Z" \
	-e ANSIBLE_HOST_KEY_CHECKING=False \
	-e "KUBECONFIG=${kubeconfig}" \
	-w "${lab_dir}" \
	"$EGA_EE_IMAGE" \
	ansible-playbook -i "${lab_dir}/inventory/hosts.yml" \
		network.evpn_gateway.deploy \
		-u root --private-key "$ssh_key" \
		-e frr_k8s_namespace=frr-k8s-system \
		-e frr_k8s_label=app=frr-k8s

# 5. Verify.
echo ">> verifying BGP EVPN"
relay_ctr="clab-${cluster}-relay"
podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "$relay_ctr" \
	podman exec frr vtysh -c 'show bgp l2vpn evpn summary' 2>/dev/null || true

test_pod_ip=$(kubectl get pod ega-test-workload -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
if [ -n "$test_pod_ip" ]; then
	echo ">> L2 reachability: on-prem -> pod $test_pod_ip"
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "clab-${cluster}-appliance" \
		ping -c 3 -W 5 "$test_pod_ip" 2>/dev/null && echo ">> PING OK" || echo ">> PING FAILED"
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" exec "clab-${cluster}-appliance" \
		curl -s --max-time 5 "http://${test_pod_ip}:8080/hostname" 2>/dev/null && echo "" && echo ">> HTTP OK" || echo ">> HTTP FAILED"
fi

echo ">> done"
exit 0
