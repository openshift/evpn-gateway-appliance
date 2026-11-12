#!/usr/bin/env bash
# In-container steps for the kind peers lane.
# kind.sh + frr-k8s, containerlab appliance/relay/TGW, deploy.yml with discovery on.
# Fails unless each kind node is BGP Established. Tears down on exit unless stage=deploy.
set -euo pipefail

stage="${EGA_STAGE:-full}"
: "${EGA_NODE_IMAGE:?}"
: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_EE_IMAGE:?}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
export EGA_WORK_DIR
cluster="${EGA_KIND_CLUSTER:-ega-evpn-kind}"
self_dir="$(cd "$(dirname "$0")" && pwd)"
topo_file="evpn-kind.clab.yml"

export DOCKER_HOST="unix://${EGA_RUNTIME_SOCK}"
export CONTAINERLAB_RUNTIME="podman"

lab_dir="${EGA_WORK_DIR}/lab-kind"
mkdir -p "$lab_dir"
kubeconfig="${lab_dir}/kubeconfig"
export KUBECONFIG="$kubeconfig"

runtime() {
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" "$@"
}

destroy_lab() {
	containerlab destroy -t "${lab_dir}/${topo_file}" --cleanup || true
	kind delete cluster --name "$cluster" || true
}

if [ "$stage" = "destroy" ]; then
	destroy_lab
	exit 0
fi

# shellcheck disable=SC2329 # invoked through the EXIT trap below
cleanup() {
	if [ "$stage" = deploy ]; then
		echo ">> stage=deploy; leaving kind and containerlab up" >&2
		return
	fi
	destroy_lab
}
trap cleanup EXIT

ssh_key="${lab_dir}/ssh/id_ega"
mkdir -p "${lab_dir}/ssh"
[ -f "$ssh_key" ] || ssh-keygen -t ed25519 -N '' -C ega-e2e-kind -f "$ssh_key" >/dev/null
chmod 644 "${ssh_key}.pub"
export EGA_SSH_PUBKEY="${ssh_key}.pub"

RELAY_PRIVATE_IP=10.100.0.1
export RELAY_PRIVATE_IP
export EGA_KIND_CLUSTER="$cluster"
"${self_dir}/setup-cluster.sh"

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

cp "${self_dir}/topology/${topo_file}" "$lab_dir/"
topo="${lab_dir}/${topo_file}"
lab=$(awk '$1 == "name:" { print $2; exit }' "$topo")
echo ">> containerlab deploy"
EGA_NODE_IMAGE="$EGA_NODE_IMAGE" containerlab deploy -t "$topo" --reconfigure

export ANSIBLE_HOST_KEY_CHECKING=False
inv="${lab_dir}/clab-${lab}/ansible-inventory.yml"
echo ">> waiting for SSH"
ansible -i "$inv" all -u root --private-key "$ssh_key" \
	-m ansible.builtin.wait_for_connection -a 'timeout=120'

tgw_ctr="clab-${lab}-tgw"
relay_ctr="clab-${lab}-relay"
runtime network connect kind "$tgw_ctr" || true
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

rm -rf "${lab_dir}/inventory"
cp -r "${self_dir}/inventory" "${lab_dir}/inventory"

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

ee_playbook network.evpn_gateway_test.simulate
ee_playbook network.evpn_gateway.deploy \
	-e frr_k8s_ns=frr-k8s-system \
	-e frr_k8s_lbl=app=frr-k8s \
	-e skip_health=true

summary="${lab_dir}/bgp-summary.json"
runtime exec "$relay_ctr" podman exec frr vtysh -c 'show bgp summary json' > "$summary"
python3 - "$summary" "${kind_node_ips[@]}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
ips = sys.argv[2:]
peers = data.get("ipv4Unicast", {}).get("peers", {})
bad = [f"{ip}={peers.get(ip, {}).get('state', 'missing')}" for ip in ips if peers.get(ip, {}).get("state") != "Established"]
if bad:
    print("BGP sessions not established: " + ", ".join(bad), file=sys.stderr)
    sys.exit(1)
print("BGP established: " + ", ".join(ips))
PY

evpn="${lab_dir}/evpn-summary.json"
runtime exec "$relay_ctr" podman exec frr vtysh -c 'show bgp l2vpn evpn summary json' > "$evpn"
python3 - "$evpn" "${kind_node_ips[@]}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
ips = sys.argv[2:]
peers = data.get("peers", {})
bad = []
for ip in ips:
    received = peers.get(ip, {}).get("pfxRcd", 0)
    try:
        received = int(received)
    except (TypeError, ValueError):
        received = 0
    if received <= 0:
        bad.append(f"{ip} pfxRcd={received}")
if bad:
    print("no EVPN prefixes from: " + ", ".join(bad), file=sys.stderr)
    sys.exit(1)
print("EVPN prefixes received from: " + ", ".join(ips))
PY

pod_ip="$(kubectl -n ega-evpn get pod ega-test-workload -o jsonpath='{.status.podIP}')"
if [ -z "$pod_ip" ]; then
	echo "error: ega-test-workload has no pod IP" >&2
	exit 1
fi
echo ">> L2 reachability: appliance -> ${pod_ip}"
runtime exec "clab-${lab}-appliance" ping -c 3 -W 5 -I 10.42.1.1 "$pod_ip"
runtime exec "clab-${lab}-appliance" curl -sf --max-time 5 "http://${pod_ip}:8080/hostname"
echo
echo ">> frr-k8s discovery, EVPN prefixes, and L2 reachability ok"
exit 0
