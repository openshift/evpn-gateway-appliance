#!/usr/bin/env bash
# Create a kind cluster with OVN-K EVPN, deploy frr-k8s, and apply EGA manifests.
#
# Required env: RELAY_PRIVATE_IP, KUBECONFIG.
# Optional: EGA_KIND_CLUSTER (default: ega-evpn-kind), EGA_KIND_WORKERS (default: 2),
#           OVN_K_IMAGE, OVN_K_DEPLOY_SCRIPT (path to ovn-kubernetes/contrib/kind.sh).
set -euo pipefail

cluster="${EGA_KIND_CLUSTER:-ega-evpn-kind}"
workers="${EGA_KIND_WORKERS:-2}"
: "${RELAY_PRIVATE_IP:?must be set}"
: "${KUBECONFIG:?must be set}"
ovnk_image="${OVN_K_IMAGE:-ghcr.io/ovn-kubernetes/ovn-kubernetes:master}"
self_dir="$(cd "$(dirname "$0")" && pwd)"

echo ">> creating kind cluster: $cluster (${workers} workers)"
kind_config="$(mktemp)"
cat > "$kind_config" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/16
nodes:
  - role: control-plane
$(for i in $(seq 1 "$workers"); do echo "  - role: worker"; done)
EOF
kind create cluster --name "$cluster" --config "$kind_config" --kubeconfig "$KUBECONFIG"
rm -f "$kind_config"
export KUBECONFIG

kubectl wait --for=condition=Ready node --all --timeout=120s 2>/dev/null || true

# Deploy OVN-K (via contrib/kind.sh if provided, otherwise assume pre-deployed).
echo ">> deploying OVN-K (image: $ovnk_image)"
kind load docker-image "$ovnk_image" --name "$cluster" 2>/dev/null || true

if [ -n "${OVN_K_DEPLOY_SCRIPT:-}" ] && [ -x "$OVN_K_DEPLOY_SCRIPT" ]; then
	echo ">> running OVN-K deploy: $OVN_K_DEPLOY_SCRIPT"
	OVN_GATEWAY_MODE=local \
	OVN_ENABLE_INTERCONNECT=true \
	ENABLE_MULTI_NET=true \
	ENABLE_NETWORK_SEGMENTATION=true \
	ENABLE_ROUTE_ADVERTISEMENTS=true \
	ENABLE_EVPN=true \
	KIND_CLUSTER_NAME="$cluster" \
	OVN_IMAGE="$ovnk_image" \
		"$OVN_K_DEPLOY_SCRIPT"
else
	echo ">> OVN_K_DEPLOY_SCRIPT not set; assuming OVN-K is pre-deployed"
fi

kubectl -n ovn-kubernetes wait --for=condition=Ready pod --all --timeout=300s 2>/dev/null || {
	echo "warning: OVN-K pods not fully ready" >&2
}

# Deploy frr-k8s if not present.
if ! kubectl get namespace frr-k8s-system &>/dev/null; then
	echo ">> deploying upstream frr-k8s"
	kubectl apply -f https://raw.githubusercontent.com/metallb/frr-k8s/main/config/default/frr-k8s.yaml 2>/dev/null || true
fi
kubectl -n frr-k8s-system wait --for=condition=Ready pod --all --timeout=120s 2>/dev/null || true

# Apply EGA manifests (template relay IP into FRRConfiguration).
echo ">> applying EGA manifests"
kubectl apply -f "${self_dir}/manifests/vtep.yml"
kubectl apply -f "${self_dir}/manifests/cudn.yml"
kubectl apply -f "${self_dir}/manifests/routeadvertisements.yml"
sed "s/RELAY_PRIVATE_IP/${RELAY_PRIVATE_IP}/g" "${self_dir}/manifests/frrconfiguration.yml" \
	| kubectl apply -f -

kubectl wait --for=condition=NetworkCreated cudn/ega-evpn-production --timeout=120s 2>/dev/null || {
	echo "warning: CUDN not ready" >&2
}

echo ">> deploying test workload"
kubectl apply -f "${self_dir}/manifests/test-workload.yml"
kubectl wait --for=condition=Ready pod/ega-test-workload --timeout=120s 2>/dev/null || true

echo ">> cluster ready: $cluster ($KUBECONFIG)"
kubectl get nodes -o custom-columns='NAME:.metadata.name,IP:.status.addresses[?(@.type=="InternalIP")].address' --no-headers
