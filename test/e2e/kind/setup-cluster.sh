#!/usr/bin/env bash
# Kind cluster plus the ovn-kubernetes v1.4.0 chart in ovnk-helm.
# NetworkAttachmentDefinition, MultiNetworkPolicy, IPAMClaim, and the
# FRRConfiguration CRD are applied first. The chart install turns on
# multi-network, network segmentation, local gateway, route advertisements,
# and EVPN. frr-k8s comes from manifests/frr-k8s.yaml (b43efcb206be) once
# that network is up, then the relay FRRConfiguration.
set -euo pipefail

: "${KUBECONFIG:?}"
: "${EGA_KIND_CLUSTER:?}"
: "${RELAY_PRIVATE_IP:?}"
: "${EGA_WORK_DIR:?}"
: "${OVN_K_IMAGE:?}"

self_dir="$(cd "$(dirname "$0")" && pwd)"
chart="${self_dir}/ovnk-helm"
ovn_image="$OVN_K_IMAGE"

echo ">> kind cluster ${EGA_KIND_CLUSTER}"
kind create cluster \
	--name "$EGA_KIND_CLUSTER" \
	--kubeconfig "$KUBECONFIG" \
	--image kindest/node:v1.36.1 \
	--config "${self_dir}/kind.yaml"

while IFS= read -r node; do
	[ -n "$node" ] || continue
	podman exec "$node" sysctl --ignore net.ipv6.conf.all.disable_ipv6=0
	podman exec "$node" sysctl --ignore net.ipv6.conf.all.forwarding=1
done < <(kind get nodes --name "$EGA_KIND_CLUSTER")

archive_dir="$(mktemp -d)"
trap 'rm -rf "${archive_dir}"' EXIT
podman save -o "${archive_dir}/image.tar" "$ovn_image"
kind load image-archive "${archive_dir}/image.tar" --name "$EGA_KIND_CLUSTER"

api="$(kind get kubeconfig --internal --name "$EGA_KIND_CLUSTER" | awk '/server:/ { print $2; exit }')"
cp_node="${api#*//}"
cp_node="${cp_node%:*}"
cp_ip="$(podman inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' "$cp_node")"
[ -n "$cp_ip" ] || { echo "setup-cluster: no kind-network IP for ${cp_node}" >&2; exit 1; }
api="${api/${cp_node}/${cp_ip}}"

echo ">> multi-network CRDs"
kubectl apply \
	-f "${self_dir}/manifests/network-attachment-definition.yaml" \
	-f "${self_dir}/manifests/multi-networkpolicy.yaml" \
	-f "${self_dir}/manifests/ipamclaims.yaml"
kubectl wait --for=condition=Established --timeout=60s \
	crd/network-attachment-definitions.k8s.cni.cncf.io \
	crd/multi-networkpolicies.k8s.cni.cncf.io \
	crd/ipamclaims.k8s.cni.cncf.io

echo ">> frr-k8s CRDs"
python3 - "${self_dir}/manifests/frr-k8s.yaml" <<'PY' | kubectl apply -f -
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
crds = []
for doc in text.split("\n---\n"):
    body = doc.strip()
    if "\n  name: frrconfigurations.frrk8s.metallb.io\n" in f"\n{body}\n":
        crds.append(body)
if len(crds) != 1:
    sys.exit("setup-cluster: frr-k8s manifest has no FRRConfiguration CRD")
sys.stdout.write("---\n" + "\n---\n".join(crds) + "\n")
PY
kubectl wait --for=condition=Established --timeout=60s \
	crd/frrconfigurations.frrk8s.metallb.io

echo ">> helm ovn-kubernetes (${api})"
helm upgrade --install ovn-kubernetes "$chart" \
	-f "${chart}/values-single-node-zone.yaml" \
	--set-string "k8sAPIServer=${api}" \
	--set global.gatewayMode=local \
	--set global.enableMultiNetwork=true \
	--set global.enableNetworkSegmentation=true \
	--set global.enableRouteAdvertisements=true \
	--set global.enableEVPN=true \
	--set global.enablePreconfiguredUDNAddresses=true \
	--set-string "global.image.repository=${ovn_image%:*}" \
	--set-string "global.image.tag=${ovn_image##*:}"

rollout() {
	local ns="$1" obj="$2" timeout="$3"
	if kubectl -n "$ns" rollout status "$obj" --timeout="$timeout"; then
		return 0
	fi
	echo "setup-cluster: ${ns}/${obj} did not become ready" >&2
	kubectl -n "$ns" get pods -o wide >&2 || true
	kubectl -n "$ns" describe pods >&2 || true
	if [ "$ns" = "ovn-kubernetes" ]; then
		kubectl -n "$ns" logs -l app=ovs-node --all-containers --tail=50 --prefix >&2 || true
		kubectl -n "$ns" logs -l app=ovnkube-node --all-containers --tail=30 --prefix >&2 || true
	fi
	return 1
}

while IFS= read -r obj; do
	[ -n "$obj" ] || continue
	rollout ovn-kubernetes "$obj" 300s
done < <(kubectl -n ovn-kubernetes get daemonset,deployment -o name)

echo ">> frr-k8s"
# Upstream starts bgpd with -p 0, so the node never accepts the relay's dial.
sed 's/-p 0/-p 179/' "${self_dir}/manifests/frr-k8s.yaml" > "${EGA_WORK_DIR}/frr-k8s.yaml"
kubectl apply -f "${EGA_WORK_DIR}/frr-k8s.yaml"
rollout frr-k8s-system deployment/frr-k8s-statuscleaner 180s
rollout frr-k8s-system daemonset/frr-k8s-daemon 180s

sed "s/RELAY_PRIVATE_IP/${RELAY_PRIVATE_IP}/g" \
	"${self_dir}/manifests/frrconfiguration.yml" > "${EGA_WORK_DIR}/frrconfiguration.yml"
kubectl apply -f "${EGA_WORK_DIR}/frrconfiguration.yml"
kubectl -n frr-k8s-system wait --for=condition=Ready pod -l app=frr-k8s --timeout=180s
