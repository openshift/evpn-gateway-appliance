#!/usr/bin/env bash
# kind + OVN-Kubernetes via upstream kind.sh, then pinned frr-k8s and the relay neighbor.
# No EVPN or route-advertisement flags: those also install frr-k8s and a demo FRR.
set -euo pipefail

: "${KUBECONFIG:?}"
: "${EGA_KIND_CLUSTER:?}"
: "${RELAY_PRIVATE_IP:?}"
: "${EGA_WORK_DIR:?}"

workers="${EGA_KIND_WORKERS:-2}"
ovn_image="${OVN_K_IMAGE:-ghcr.io/ovn-kubernetes/ovn-kubernetes:master}"
[ -n "$ovn_image" ] || ovn_image="ghcr.io/ovn-kubernetes/ovn-kubernetes:master"
ovn_ref="${OVN_K_REF:-v1.4.0}"
frr_ref="${FRR_K8S_REF:-b43efcb206be}"
self_dir="$(cd "$(dirname "$0")" && pwd)"

ovn_src="${EGA_WORK_DIR}/ovn-kubernetes"
if [ ! -e "${ovn_src}/contrib/kind.sh" ]; then
	rm -rf "$ovn_src"
	git clone --depth 1 --branch "$ovn_ref" https://github.com/ovn-org/ovn-kubernetes.git "$ovn_src"
fi

echo ">> kind.sh ${ovn_ref} cluster ${EGA_KIND_CLUSTER}"
bash "${ovn_src}/contrib/kind.sh" \
	--cluster-name "$EGA_KIND_CLUSTER" \
	--num-workers "$workers" \
	--kubeconfig "$KUBECONFIG" \
	--ovn-image "$ovn_image" \
	--experimental-provider podman

manifest="${EGA_WORK_DIR}/frr-k8s.yaml"
curl -fsSL -o "$manifest" \
	"https://raw.githubusercontent.com/metallb/frr-k8s/${frr_ref}/config/all-in-one/frr-k8s.yaml"
sed -i 's|gcr.io/kubebuilder/kube-rbac-proxy|registry.k8s.io/kubebuilder/kube-rbac-proxy|g' "$manifest"
kubectl apply -f "$manifest"
kubectl -n frr-k8s-system rollout status deployment/frr-k8s-statuscleaner --timeout=180s
kubectl -n frr-k8s-system rollout status daemonset/frr-k8s-daemon --timeout=180s

sed "s/RELAY_PRIVATE_IP/${RELAY_PRIVATE_IP}/g" \
	"${self_dir}/manifests/frrconfiguration.yml" > "${EGA_WORK_DIR}/frrconfiguration.yml"
kubectl apply -f "${EGA_WORK_DIR}/frrconfiguration.yml"
kubectl -n frr-k8s-system wait --for=condition=Ready pod -l app=frr-k8s --timeout=180s
