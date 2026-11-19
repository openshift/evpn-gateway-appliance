#!/usr/bin/env bash
# l2-pod: the appliance can reach a pod on the primary EVPN CUDN.
set -euo pipefail

: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_LAB:?}"
: "${EGA_LAB_DIR:?}"
: "${EGA_RELAY_CTR:?}"
: "${EGA_KIND_NODE_IPS:?}"

runtime() {
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" "$@"
}

read -r -a kind_node_ips <<< "${EGA_KIND_NODE_IPS}"

kubectl wait --for=condition=NetworkCreated clusteruserdefinednetwork/ega-evpn-production --timeout=180s
kubectl -n ega-evpn wait --for=condition=Ready pod/ega-test-workload --timeout=180s

# A Ready pod only means the CNI finished. Poll until each kind node has
# advertised an EVPN prefix.
evpn="${EGA_LAB_DIR}/evpn-summary.json"
evpn_deadline=$((SECONDS + 180))
while true; do
	if runtime exec "$EGA_RELAY_CTR" podman exec frr vtysh -c 'show bgp l2vpn evpn summary json' > "$evpn" \
		&& python3 - "$evpn" "${kind_node_ips[@]}" <<'PY'
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
    print("waiting for EVPN prefixes: " + ", ".join(bad), file=sys.stderr)
    sys.exit(1)
print("EVPN prefixes received from: " + ", ".join(ips))
PY
	then
		break
	fi
	if (( SECONDS >= evpn_deadline )); then
		echo "timed out waiting for EVPN prefixes" >&2
		[ -s "$evpn" ] && cat "$evpn" >&2
		exit 1
	fi
	sleep 5
done

# status.podIP stays on the cluster network. The stretched address is the
# primary network recorded in k8s.ovn.org/pod-networks.
pod_ip=""
pod_deadline=$((SECONDS + 60))
while true; do
	pod_ip="$(kubectl -n ega-evpn get pod ega-test-workload -o json | python3 -c '
import json, sys
pod = json.load(sys.stdin)
raw = pod.get("metadata", {}).get("annotations", {}).get("k8s.ovn.org/pod-networks", "")
if not raw:
    sys.exit(1)
for info in json.loads(raw).values():
    if info.get("role") == "primary":
        ip = info.get("ip_address") or (info.get("ip_addresses") or [""])[0]
        print(ip.split("/", 1)[0])
        sys.exit(0)
sys.exit(1)
')" || true
	if [ -n "$pod_ip" ]; then
		break
	fi
	if (( SECONDS >= pod_deadline )); then
		echo "error: ega-test-workload has no primary network address" >&2
		exit 1
	fi
	sleep 2
done
echo ">> L2 reachability: appliance -> ${pod_ip}"
runtime exec "clab-${EGA_LAB}-appliance" ping -c 3 -W 5 -I 10.42.1.1 "$pod_ip"
runtime exec "clab-${EGA_LAB}-appliance" curl -sf --max-time 5 "http://${pod_ip}:8080/hostname"
echo
echo ">> l2-pod ok"
