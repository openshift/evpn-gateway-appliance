#!/usr/bin/env bash
# Kind cluster lifecycle for the kind e2e scenario. Runs inside the privileged
# CI image with the host runtime socket, so kind's node containers, the podman
# network, and the host kernel modules are all host-side.
#
# usage: setup-cluster.sh <setup|teardown> <work_dir>
#
# setup creates the podman network (the containerlab bridge node ega-kind-br),
# the kind cluster, and the ovn-kubernetes chart with frr-k8s and the EVPN
# VTEP/CUDN/route advertisements. The kubeconfig lands in <work_dir>/kubeconfig.
# teardown removes the cluster and the network.
set -euo pipefail

# kind's node containers are siblings on the host runtime; without this kind looks for docker.
export KIND_EXPERIMENTAL_PROVIDER=podman

cmd="${1:?usage: setup-cluster.sh <setup|teardown> <work_dir>}"
work_dir="${2:?usage: setup-cluster.sh <setup|teardown> <work_dir>}"
self_dir="$(cd "$(dirname "$0")" && pwd)"

cluster=ega-kind
kubeconfig="${work_dir}/kubeconfig"
# The TGW owns 10.89.0.2 on this bridge; kind nodes draw from the upper half of the prefix.
kind_prefix=10.89.0.0/24
kind_tgw_ip=10.89.0.2
kind_bridge=ega-kind-br
# The relay's infra-VPC address, also in the kind inventory group_vars.
relay_private_ip=10.100.0.1

teardown() {
	# Only remove what this run created: the kind network name is fixed, so a
	# pre-existing one may belong to someone else. A failed cluster listing is
	# an error, not "cluster absent".
	if [ -f "${work_dir}/kind-cluster" ]; then
		clusters="$(kind get clusters)"
		if grep -qx "$cluster" <<< "$clusters"; then
			kind delete cluster --name "$cluster"
		fi
		rm -f "${work_dir}/kind-cluster"
	fi
	owned_network=0
	[ -f "${work_dir}/kind-network" ] && owned_network=1
	if [ "$owned_network" = 1 ] && podman network exists kind; then
		podman network rm kind
	fi
	rm -f "${work_dir}/kind-network"
	# netavark cannot delete the bridge while a containerlab veth is still
	# enslaved to it, so the interface can outlive the network and keep the
	# subnet busy for the next scenario's network create.
	if [ "$owned_network" = 1 ] && ip link show "$kind_bridge" >/dev/null 2>&1; then
		ip link del "$kind_bridge"
	fi
}

case "$cmd" in
	teardown)
		teardown
		exit 0
		;;
	setup) ;;
	*)
		echo "setup-cluster: unknown command: $cmd" >&2
		exit 2
		;;
esac

# Host kernel tuning: inotify limits for ovnkube-node, bridge netfilter off
# for route advertisements. These sysctls are global, so they apply from inside
# the privileged CI image; the modules themselves are loaded on the host by
# run.sh (their packages live in the host's own repos).
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

# Mark the network as this run's, so teardown removes only what it created.
# The bridge must exist before the clab topology's host-side veth is enslaved
# to it after the deploy.
podman network create --driver bridge --interface-name "$kind_bridge" \
	--subnet "$kind_prefix" --gateway 10.89.0.1 \
	--ip-range 10.89.0.128/25 kind
touch "${work_dir}/kind-network"

# ovn-kubernetes v1.4.0 chart: multi-network CRDs first (FRRConfiguration must
# exist before ovnkube-node's informer), then frr-k8s, then the relay FRRConfiguration.
e2e_inputs="${EGA_E2E_INPUTS:-/opt/ega/e2e}"
chart="${e2e_inputs}/ovnk-helm"
crds="${e2e_inputs}/manifests"

# Refuse to reuse a cluster with this name: it may belong to someone else.
# A failed cluster listing is an error, not "no such cluster".
clusters="$(kind get clusters)"
if grep -qx "$cluster" <<< "$clusters"; then
	echo "setup-cluster: cluster ${cluster} already exists; destroy it first" >&2
	exit 1
fi
echo ">> kind cluster ${cluster}"
kind create cluster \
	--name "$cluster" \
	--kubeconfig "$kubeconfig" \
	--image kindest/node:v1.36.1 \
	--config "${self_dir}/kind.yaml"
# Mark the cluster as this run's, so teardown removes only what it created.
touch "${work_dir}/kind-cluster"

# A failed or empty node list would silently skip the route setup.
nodes="$(kind get nodes --name "$cluster")"
[ -n "$nodes" ] || { echo "setup-cluster: no nodes for cluster ${cluster}" >&2; exit 1; }
while IFS= read -r node; do
	[ -n "$node" ] || continue
	podman exec "$node" sysctl --ignore net.ipv6.conf.all.disable_ipv6=0
	podman exec "$node" sysctl --ignore net.ipv4.conf.all.forwarding=1
	podman exec "$node" ip route replace 10.100.0.0/16 via "$kind_tgw_ip"
	podman exec "$node" ip route replace 10.44.44.0/24 via "$kind_tgw_ip"
done <<< "$nodes"

api="$(kind get kubeconfig --internal --name "$cluster" | awk '/server:/ { print $2; exit }')"
cp_node="${api#*//}"
cp_node="${cp_node%:*}"
cp_ip="$(podman inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' "$cp_node")"
[ -n "$cp_ip" ] || { echo "setup-cluster: no kind-network IP for ${cp_node}" >&2; exit 1; }
api="${api/${cp_node}/${cp_ip}}"

# The chart's pods pull their image into every fresh kind node; ghcr.io
# rate-limits repeated anonymous pulls, so load it from the host instead.
# kind load docker-image shells out to docker even under the podman provider;
# the image-archive path has no such dependency.
chart_image="ghcr.io/ovn-kubernetes/ovn-kubernetes/ovn-kube-ubuntu:master"
podman image exists "$chart_image" || podman pull "$chart_image"
image_tar="${work_dir}/ovn-kube-ubuntu.tar"
podman save -o "$image_tar" "$chart_image"
kind load image-archive --name "$cluster" "$image_tar"

echo ">> multi-network CRDs"
kubectl --kubeconfig "$kubeconfig" apply \
	-f "${crds}/network-attachment-definition.yaml" \
	-f "${crds}/multi-networkpolicy.yaml" \
	-f "${crds}/ipamclaims.yaml"
kubectl --kubeconfig "$kubeconfig" wait --for=condition=Established --timeout=60s \
	crd/network-attachment-definitions.k8s.cni.cncf.io \
	crd/multi-networkpolicies.k8s.cni.cncf.io \
	crd/ipamclaims.k8s.cni.cncf.io

echo ">> frr-k8s"
# bgpd must listen on 179 for the relay's dial; the node RBAC rule is in the baked chart.
sed 's/-p 0/-p 179/' "${crds}/frr-k8s.yaml" > "${work_dir}/frr-k8s.yaml"
kubectl --kubeconfig "$kubeconfig" apply -f "${work_dir}/frr-k8s.yaml"
kubectl --kubeconfig "$kubeconfig" wait --for=condition=Established --timeout=60s \
	crd/frrconfigurations.frrk8s.metallb.io

echo ">> helm ovn-kubernetes (${api})"
helm upgrade --install ovn-kubernetes "$chart" \
	--kubeconfig "$kubeconfig" \
	-f "${chart}/values-single-node-zone.yaml" \
	--set-string "k8sAPIServer=${api}" \
	--set global.gatewayMode=local \
	--set global.enableMultiNetwork=true \
	--set global.enableNetworkSegmentation=true \
	--set global.enableRouteAdvertisements=true \
	--set global.enableEVPN=true \
	--set global.enablePreconfiguredUDNAddresses=true

rollout() {
	local ns="$1" obj="$2" timeout="$3"
	if kubectl --kubeconfig "$kubeconfig" -n "$ns" rollout status "$obj" --timeout="$timeout"; then
		return 0
	fi
	echo "setup-cluster: ${ns}/${obj} did not become ready" >&2
	kubectl --kubeconfig "$kubeconfig" -n "$ns" get pods -o wide >&2 || true
	return 1
}

# A failed or empty workload list would silently skip the rollout checks.
ovn_objects="$(kubectl --kubeconfig "$kubeconfig" -n ovn-kubernetes get daemonset,deployment -o name)"
[ -n "$ovn_objects" ] || { echo "setup-cluster: no ovn-kubernetes workloads found" >&2; exit 1; }
while IFS= read -r obj; do
	[ -n "$obj" ] || continue
	rollout ovn-kubernetes "$obj" 600s
done <<< "$ovn_objects"

echo ">> frr-k8s ready"
rollout frr-k8s-system deployment/frr-k8s-statuscleaner 180s
rollout frr-k8s-system daemonset/frr-k8s-daemon 180s

sed "s/RELAY_PRIVATE_IP/${relay_private_ip}/g" \
	"${self_dir}/manifests/frrconfiguration.yml" > "${work_dir}/frrconfiguration.yml"
kubectl --kubeconfig "$kubeconfig" apply -f "${work_dir}/frrconfiguration.yml"
kubectl --kubeconfig "$kubeconfig" -n frr-k8s-system wait --for=condition=Ready pod -l app=frr-k8s --timeout=180s

echo ">> evpn VTEP, network, and route advertisements"
kubectl --kubeconfig "$kubeconfig" apply \
	-f "${self_dir}/manifests/ega-evpn-namespace.yml" \
	-f "${self_dir}/manifests/ega-evpn-vtep.yml"
kubectl --kubeconfig "$kubeconfig" wait --for=condition=Accepted vtep/ega-vtep --timeout=180s
kubectl --kubeconfig "$kubeconfig" apply \
	-f "${self_dir}/manifests/ega-evpn-cudn.yml" \
	-f "${self_dir}/manifests/ega-evpn-ra.yml"
kubectl --kubeconfig "$kubeconfig" wait --for=condition=NetworkCreated clusteruserdefinednetwork/ega-evpn-production --timeout=180s
kubectl --kubeconfig "$kubeconfig" wait --for=condition=Accepted routeadvertisements/ega-evpn-ra --timeout=180s
echo ">> VTEP accepted, CUDN created, route advertisements accepted"
