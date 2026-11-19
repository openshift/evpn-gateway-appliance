#!/usr/bin/env bash
# The kind nodes are the workload VTEP. Unmanaged mode discovers an address
# already configured on the node and inside the VTEP CIDR, then records it on
# k8s.ovn.org/vteps. That address is the node's kind-network IP.
set -euo pipefail

: "${KUBECONFIG:?}"
: "${EGA_WORK_DIR:?}"

self_dir="$(cd "$(dirname "$0")" && pwd)"

kind_cidr="$(podman network inspect kind | python3 -c '
import json, sys
nets = json.load(sys.stdin)
if isinstance(nets, dict):
    nets = [nets]
for net in nets:
    for subnet in net.get("subnets") or []:
        cidr = subnet.get("subnet", "")
        if "." in cidr:
            print(cidr)
            raise SystemExit
raise SystemExit("prepare-evpn: kind network has no ipv4 subnet")
')"
echo ">> VTEP CIDR ${kind_cidr}"
printf '%s\n' "$kind_cidr" > "${EGA_WORK_DIR}/kind-cidr"

dump() {
	{
		echo "===== vtep / cudn / routeadvertisements ====="
		kubectl get vtep,clusteruserdefinednetwork,routeadvertisements -o yaml
		echo "===== node annotations ====="
		kubectl get nodes -o json | python3 -c '
import json, sys
for node in json.load(sys.stdin).get("items", []):
    ann = node["metadata"].get("annotations", {}).get("k8s.ovn.org/vteps", "")
    print(node["metadata"]["name"], ann)
'
	} > "${EGA_WORK_DIR}/evpn-status.txt" 2>&1 || true
}

kubectl apply -f "${self_dir}/manifests/ega-evpn-namespace.yml"
cat > "${EGA_WORK_DIR}/ega-vtep.yml" <<EOF
apiVersion: k8s.ovn.org/v1
kind: VTEP
metadata:
  name: ega-vtep
spec:
  mode: Unmanaged
  cidrs:
    - ${kind_cidr}
EOF
kubectl apply -f "${EGA_WORK_DIR}/ega-vtep.yml"

if ! kubectl wait --for=condition=Accepted vtep/ega-vtep --timeout=180s; then
	dump
	echo "prepare-evpn: VTEP was not accepted; see ${EGA_WORK_DIR}/evpn-status.txt" >&2
	exit 1
fi

kubectl apply \
	-f "${self_dir}/manifests/ega-evpn-cudn.yml" \
	-f "${self_dir}/manifests/ega-evpn-ra.yml"

if ! kubectl wait --for=condition=NetworkCreated clusteruserdefinednetwork/ega-evpn-production --timeout=180s; then
	dump
	echo "prepare-evpn: CUDN was not created; see ${EGA_WORK_DIR}/evpn-status.txt" >&2
	exit 1
fi
if ! kubectl wait --for=condition=Accepted routeadvertisements/ega-evpn-ra --timeout=180s; then
	dump
	echo "prepare-evpn: route advertisements were not accepted; see ${EGA_WORK_DIR}/evpn-status.txt" >&2
	exit 1
fi
dump
echo ">> VTEP accepted, CUDN created, route advertisements accepted"
