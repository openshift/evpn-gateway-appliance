#!/usr/bin/env bash
# multi-vni: one primary L2 EVPN CUDN per stretched VLAN (CORENET-7513).
#
# Per VLAN 100/200/300 (plus the day-2 VLAN 400 overlay) this proves:
#   1. three primary L2 EVPN CUDNs, one Ready workload pod per CUDN per kind
#      node, and one simulated on-prem host (vm-<name>) per stretch at .10
#   2. per-VNI route targets: frr-k8s imports/exports only <workload_asn>:<vni>
#      (FRR auto-derives it from the frr-k8s router ASN, since the CUDNs set no
#      routeTarget); the appliance imports <onprem_asn>:<vni> and
#      <workload_asn>:<vni> and exports <onprem_asn>:<vni>. Both ASNs are read
#      from the deployed configuration, never hardcoded, and the three targets
#      differ.
#   3. per-VNI remote VTEPs: every kind node is a remote VTEP for every VNI on
#      the appliance (deploy's health check skips this on the kind lane, so the
#      scenario owns the proof)
#   4. same-VLAN reachability: each vm-<name> pings and HTTP-gets every pod of
#      its own UDN on every node
#   5. no cross-VLAN data plane: from every VM, ping and HTTP to every pod on a
#      foreign VNI must fail; a pod MAC learned on the wrong VNI or a foreign
#      route target inside a VNI fails too. The appliance holds every stretch
#      SVI and forwards IP, so it would happily route between stretch subnets;
#      that path is refused here (a drop between the stretch subnets), which
#      makes a positive result a genuine leak rather than ordinary routing.
#   6. day-2: VLAN 400 added as a NEW EVPN CUDN (EVPN cannot be enabled on an
#      existing CUDN), reachable from vm-database and isolated from the
#      original three both ways
#   7. delete/recreate of the day-2 CUDN: the pod Type-2s withdraw, the
#      original three stretches keep answering, and VLAN 400 reachability
#      returns after the recreate
set -euo pipefail

: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_LAB:?}"
: "${EGA_LAB_DIR:?}"
: "${EGA_EE_IMAGE:?}"

EGA_RELAY_CTR="${EGA_RELAY_CTR:-clab-${EGA_LAB}-relay}"
appliance_ctr="clab-${EGA_LAB}-appliance"
self_dir="$(cd "$(dirname "$0")" && pwd)"

stretch_names=(production staging management database)
stretch_vlans=(100 200 300 400)
stretch_nets=(10.42.1 10.42.2 10.42.3 10.42.4)

# The day-2 objects are applied from here, not from the runner's generic
# manifest handling, so this scenario cleans them up itself.
cleanup() {
	kubectl delete --ignore-not-found=true --wait=false \
		-f "${self_dir}/day2/manifests.yml" >/dev/null 2>&1 || true
	rm -f "${frrjson:-}"
}
trap cleanup EXIT

runtime() {
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" "$@"
}

appliance_frr() { # vtysh command on the appliance's FRR container
	runtime exec "$appliance_ctr" podman exec frr vtysh -c "$1"
}

vm_exec() { # vm_exec <stretch-name> <command...> runs inside vm-<name>
	runtime exec "$appliance_ctr" ip netns exec "vm-$1" "${@:2}"
}

vm_mac() { # MAC of the simulated host's eth0
	vm_exec "$1" cat /sys/class/net/eth0/address
}

mapfile -t frr_pods < <(kubectl -n frr-k8s-system get pods -l app=frr-k8s -o name)
[ "${#frr_pods[@]}" -gt 0 ] || {
	echo "error: no frr-k8s pods" >&2
	exit 1
}

frr_k8s_exec() { # frr_k8s_exec <pod/name> <vtysh command> (the frr-k8s pod is
	# multi-container; vtysh lives in the "frr" container)
	kubectl -n frr-k8s-system exec "$1" -c frr -- vtysh -c "$2"
}

# Stage a file into the lab work dir: the EE only bind-mounts EGA_LAB_DIR, so
# extra-var files must live there for ansible-playbook to read them.
stage_e2e_inputs() { # stage_e2e_inputs <file...>
	local f
	for f in "$@"; do
		cp "${self_dir}/${f}" "${EGA_LAB_DIR}/${f}"
	done
}
stage_e2e_inputs stretches.yml stretches-day2.yml

# ── Tolerant parsers for FRR vtysh JSON (key names vary across versions) ──
frrjson="$(mktemp /tmp/multi-vni-frr.XXXXXX.py)"
cat >"$frrjson" <<'PY'
"""Parse FRR EVPN vtysh JSON (formats verified against FRR 10.5.3). Usage:
<mode> [args...] with JSON on stdin.

vni <where> <vni> <workload_rt> <onprem_rt>
    show bgp l2vpn evpn vni <vni> json: the VNI's effective import/export policy.
    where=frr:       importRts == exportRts == {workload_rt} (FRR auto-derives
                     <router-ASN>:<VNI> when the CUDN sets no routeTarget)
    where=appliance: importRts == {workload_rt, onprem_rt}, exportRts == {onprem_rt}
vteps  show evpn vni <vni> json: print one remote VTEP IP per line
macs   show evpn mac vni <vni> json: print one MAC per line
"""
import json
import re
import sys

MAC_RE = re.compile(r"^[0-9a-f]{2}(:[0-9a-f]{2}){5}$", re.IGNORECASE)


def load():
    data = json.load(sys.stdin)
    if isinstance(data, list) and len(data) == 1 and isinstance(data[0], dict):
        return data[0]
    return data


def field(doc, *keys):
    for key in keys:
        if isinstance(doc, dict) and key in doc:
            return doc[key]
    return None


def as_list(value):
    if value is None:
        return []
    if isinstance(value, dict):
        return [str(k) for k in value]
    if isinstance(value, list):
        return [str(v) for v in value]
    return [str(value)]


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


mode = sys.argv[1]
doc = load()
if mode == "vni":
    where, vni, workload_rt, onprem_rt = sys.argv[2:6]
    rti = set(as_list(field(doc, "importRts", "rtImport", "importRT")))
    rte = set(as_list(field(doc, "exportRts", "rtExport", "exportRT")))
    if not rti or not rte:
        fail(f"vni {vni}: no route-target fields in show bgp l2vpn evpn vni output")
    if where == "frr":
        if rti != {workload_rt} or rte != {workload_rt}:
            fail(f"vni {vni} on frr-k8s: import {sorted(rti)} export {sorted(rte)}"
                 f", want only {workload_rt}")
    else:
        if rti != {workload_rt, onprem_rt}:
            fail(f"vni {vni} on appliance: import {sorted(rti)}"
                 f", want {{{onprem_rt}, {workload_rt}}}")
        if rte != {onprem_rt}:
            fail(f"vni {vni} on appliance: export {sorted(rte)}, want only {onprem_rt}")
    print(f"vni {vni} on {where}: ok (import {sorted(rti)}, export {sorted(rte)})")
elif mode == "vteps":
    remote = field(doc, "remoteVteps", "remoteVtepList") or []
    ips = []
    for entry in remote:
        if isinstance(entry, dict) and "ip" in entry:
            ips.append(str(entry["ip"]))
        else:
            ips.append(str(entry))
    for ip in sorted(set(ips)):
        print(ip)
elif mode == "macs":
    # FRR 10.5.3: {"numMacs": N, "macs": {"<mac>": {...}}}
    macs = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(key, str) and MAC_RE.match(key):
                    macs.add(key.lower())
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(field(doc, "macs") or doc)
    for mac in sorted(macs):
        print(mac)
else:
    fail(f"unknown mode {mode}")
PY

# ── Kubernetes helpers ───────────────────────────────────────────────────────
pod_lines() { # pod_lines <namespace>: "name ip mac" per workload pod (primary UDN)
	kubectl -n "$1" get pods -l app=ega-test-workload -o json | python3 -c '
import json
import sys

for pod in json.load(sys.stdin).get("items", []):
    raw = pod.get("metadata", {}).get("annotations", {}).get(
        "k8s.ovn.org/pod-networks", "")
    if not raw:
        continue
    for info in json.loads(raw).values():
        if info.get("role") == "primary":
            ip = info.get("ip_address") or (info.get("ip_addresses") or [""])[0]
            print(pod["metadata"]["name"], ip.split("/", 1)[0],
                  info.get("mac_address", ""))
            break
'
}

declare -A pod_ip pod_mac pods_by_ns

gather_pods() { # gather_pods <namespace> [reset]
	local ns="$1" name ip mac key
	[ "${2:-}" = reset ] && pods_by_ns["$ns"]=""
	while read -r name ip mac; do
		[ -n "$name" ] || continue
		key="${ns}/${name}"
		pod_ip["$key"]="$ip"
		pod_mac["$key"]="$mac"
		pods_by_ns["$ns"]+="${key} "
	done < <(pod_lines "$ns")
	[ -n "${pods_by_ns["$ns"]:-}" ] || {
		echo "error: no workload pods gathered in namespace $ns" >&2
		exit 1
	}
}

pods_of() { # print the pod keys of a namespace, one per line
	local -a keys
	[ -n "${pods_by_ns["$1"]:-}" ] || {
		echo "error: no workload pods in namespace $1" >&2
		return 1
	}
	read -r -a keys <<<"${pods_by_ns["$1"]}"
	printf '%s\n' "${keys[@]}"
}

node_count() {
	kubectl get nodes --no-headers | wc -l
}

wait_gone() { # wait_gone <resource>/<name>: poll until deleted (kubectl wait has
	# no --ignore-not-found, and the object may already be gone)
	local deadline=$((SECONDS + 180))
	while kubectl get "$1" >/dev/null 2>&1; do
		if ((SECONDS >= deadline)); then
			echo "error: $1 still present after 180s" >&2
			return 1
		fi
		sleep 2
	done
}

# ── Dataplane probes ─────────────────────────────────────────────────────────
check_reach() { # vm <pod-ip>: ping and HTTP must succeed
	if ! vm_exec "$1" ping -c 2 -W 3 "$2" >/dev/null 2>&1; then
		echo "error: vm-$1 cannot ping $2" >&2
		exit 1
	fi
	if ! vm_exec "$1" curl -sf --max-time 5 "http://$2:8080/hostname" >/dev/null; then
		echo "error: vm-$1 cannot HTTP http://$2:8080" >&2
		exit 1
	fi
}

check_isolated() { # vm <pod-ip>: ping and HTTP must both fail
	if vm_exec "$1" ping -c 1 -W 3 "$2" >/dev/null 2>&1; then
		echo "error: crosstalk: vm-$1 pinged $2 across VNIs" >&2
		exit 1
	fi
	if vm_exec "$1" curl -sf --max-time 3 "http://$2:8080/hostname" >/dev/null 2>&1; then
		echo "error: crosstalk: vm-$1 reached http://$2:8080 across VNIs" >&2
		exit 1
	fi
}

# ── Control-plane assertions ─────────────────────────────────────────────────
# ASNs from the deployed configuration: the workload ASN from the cluster's
# FRRConfiguration (what frr-k8s actually speaks, and what discover_peers
# propagates to the relay), the on-prem ASN from the lab inventory bgp block.
workload_asn="$(kubectl -n frr-k8s-system get frrconfiguration ega-relay-peer \
	-o jsonpath='{.spec.bgp.routers[0].asn}')"
onprem_asn="$(awk '/^  onprem_asn:/ { print $2 }' \
	"${EGA_LAB_DIR}/inventory/group_vars/all.yml")"
if [ -z "$workload_asn" ] || [ -z "$onprem_asn" ]; then
	echo "error: could not read ASNs (workload=${workload_asn:-?} onprem=${onprem_asn:-?})" >&2
	exit 1
fi
echo ">> ASNs: workload ${workload_asn}, onprem ${onprem_asn}"

mapfile -t kind_node_ips < <(kubectl get nodes -o json | python3 -c '
import json
import sys

for node in json.load(sys.stdin).get("items", []):
    for addr in node.get("status", {}).get("addresses", []):
        ip = addr.get("address", "")
        if addr.get("type") == "InternalIP" and "." in ip:
            print(ip)
')
[ "${#kind_node_ips[@]}" -gt 0 ] || {
	echo "error: no kind node addresses" >&2
	exit 1
}

# check_vni_isolation <stretch-count> [expect-macs]: per VNI, every remote VTEP
# present, the route targets exactly as deployed, no foreign MAC or route target
# in the VNI. With expect-macs (run after dataplane traffic, when ARP has made
# the pods advertise their MACs), each UDN's own pod MACs must be present too.
check_vni_isolation() {
	local count="$1" expect_macs="${2:-}" i j vni key
	local -a own_pods foreign_macs
	for ((i = 0; i < count; i++)); do
		vni=$((10000 + stretch_vlans[i]))
		local wrt="${workload_asn}:${vni}" ort="${onprem_asn}:${vni}"

		echo ">> vni ${vni} (${stretch_names[i]}): route targets"
		# The VNI's effective import/export policy: frr-k8s auto-derives
		# <router-ASN>:<VNI> (the workload ASN) because the CUDNs set no
		# routeTarget; the appliance imports both ASNs and exports its own.
		appliance_frr "show bgp l2vpn evpn vni ${vni} json" | python3 "$frrjson" vni \
			appliance "$vni" "$wrt" "$ort"
		for pod in "${frr_pods[@]}"; do
			frr_k8s_exec "$pod" "show bgp l2vpn evpn vni ${vni} json" |
				python3 "$frrjson" vni frr "$vni" "$wrt" "$ort"
		done

		echo ">> vni ${vni} (${stretch_names[i]}): every kind node is a remote VTEP"
		local -a vteps
		mapfile -t vteps < <(appliance_frr "show evpn vni ${vni} json" |
			python3 "$frrjson" vteps)
		for ip in "${kind_node_ips[@]}"; do
			printf '%s\n' "${vteps[@]}" | grep -qx "$ip" || {
				echo "error: vni ${vni} on appliance: kind node ${ip} not a remote VTEP (${vteps[*]})" >&2
				exit 1
			}
		done

		mapfile -t own_pods < <(pods_of "${stretch_names[i]}")
		# MACs that must not appear in this VNI: pods and VMs of every other stretch
		local -a foreign_macs=()
		for ((j = 0; j < 4; j++)); do
			[ "$j" -eq "$i" ] && continue
			[ "$j" -lt "$count" ] || continue
			while read -r key; do
				foreign_macs+=("${pod_mac["$key"]}")
			done < <(pods_of "${stretch_names[j]}")
			foreign_macs+=("$(vm_mac "${stretch_names[j]}")")
		done

		echo ">> vni ${vni}: MAC tables contain only ${stretch_names[i]} MACs"
		# The per-VNI MAC tables prove route membership (FRR matches EVPN
		# Type-2/3 to a local VNI by the VNI label, so a foreign MAC here means
		# a real leak, not just a mislabeled route target).
		local table
		table="$(appliance_frr "show evpn mac vni ${vni} json" 2>/dev/null |
			python3 "$frrjson" macs || true)"
		for mac in "${foreign_macs[@]}"; do
			if grep -qx "$mac" <<<"$table"; then
				echo "error: foreign MAC ${mac} in appliance vni ${vni} table" >&2
				exit 1
			fi
		done
		for key in "${own_pods[@]}"; do
			[ -z "$expect_macs" ] && continue
			grep -qx "${pod_mac["$key"]}" <<<"$table" || {
				echo "error: ${key} MAC ${pod_mac["$key"]} missing from appliance vni ${vni}" >&2
				exit 1
			}
		done
		for pod in "${frr_pods[@]}"; do
			table="$(frr_k8s_exec "$pod" "show evpn mac vni ${vni} json" 2>/dev/null |
				python3 "$frrjson" macs || true)"
			for mac in "${foreign_macs[@]}"; do
				if grep -qx "$mac" <<<"$table"; then
					echo "error: foreign MAC ${mac} in ${pod} vni ${vni} table" >&2
					exit 1
				fi
			done
			for key in "${own_pods[@]}"; do
				[ -z "$expect_macs" ] && continue
				grep -qx "${pod_mac["$key"]}" <<<"$table" || {
					echo "error: ${key} MAC ${pod_mac["$key"]} missing from ${pod} vni ${vni}" >&2
					exit 1
				}
			done
		done
	done
}

# ═ 1. three stretches ════════════════════════════════════════════════════════
echo ">> retire the bring-up single-stretch CUDN and RouteAdvertisements"
kubectl delete --ignore-not-found=true clusteruserdefinednetwork ega-evpn-production
kubectl delete --ignore-not-found=true routeadvertisements ega-evpn-ra
wait_gone clusteruserdefinednetwork/ega-evpn-production
wait_gone routeadvertisements/ega-evpn-ra

kubectl apply -f "${self_dir}/manifests"
for name in production staging management; do
	kubectl wait --for=condition=NetworkCreated \
		clusteruserdefinednetwork/"$name" --timeout=180s
done
kubectl wait --for=condition=Accepted routeadvertisements/ega-multi-vni-ra --timeout=180s

# Build the simulated trunk for all three stretches BEFORE deploy so the
# appliance role finds the VLANs to build its VTEPs on; deploy then configures
# the appliance per stretch and discovers the frr-k8s peers.
ee_playbook network.evpn_gateway_test.simulate -e @"${EGA_LAB_DIR}/stretches.yml"
ee_playbook network.evpn_gateway.deploy \
	-e @"${EGA_LAB_DIR}/stretches.yml" \
	-e frr_k8s_ns=frr-k8s-system \
	-e frr_k8s_lbl=app=frr-k8s

for i in 0 1 2; do
	addr="$(vm_exec "${stretch_names[i]}" ip -4 -o addr show dev eth0 |
		awk '{ print $4 }' | cut -d/ -f1)"
	[ "$addr" = "${stretch_nets[i]}.10" ] || {
		echo "error: vm-${stretch_names[i]} has ${addr:-no address}, want ${stretch_nets[i]}.10" >&2
		exit 1
	}
done

nodes="$(node_count)"
for name in production staging management; do
	kubectl -n "$name" rollout status daemonset/ega-test-workload --timeout=180s
	ready="$(kubectl -n "$name" get daemonset ega-test-workload \
		-o jsonpath='{.status.numberReady}')"
	[ "$ready" = "$nodes" ] || {
		echo "error: ${name}: ${ready}/${nodes} workload pods ready" >&2
		exit 1
	}
	gather_pods "$name"
done

# Convergence: every kind node advertises EVPN prefixes to the relay (l2-pod's
# poll; the per-VNI proof below is the scenario's own, since deploy's health
# check skips the remote-VTEP assertions on the kind lane).
evpn="${EGA_LAB_DIR}/evpn-summary.json"
evpn_deadline=$((SECONDS + 180))
while true; do
	if runtime exec "$EGA_RELAY_CTR" podman exec frr vtysh \
		-c 'show bgp l2vpn evpn summary json' >"$evpn" &&
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
    print("waiting for EVPN prefixes: " + ", ".join(bad), file=sys.stderr)
    sys.exit(1)
print("EVPN prefixes received from: " + ", ".join(ips))
PY
	then
		break
	fi
	if ((SECONDS >= evpn_deadline)); then
		echo "timed out waiting for EVPN prefixes" >&2
		[ -s "$evpn" ] && cat "$evpn" >&2
		exit 1
	fi
	sleep 5
done

# ═ 2. route targets and remote VTEPs ═════════════════════════════════════════
check_vni_isolation 3

# The three workload route targets differ (distinct VNIs, same ASN).
rts="$(for i in 0 1 2; do echo "${workload_asn}:$((10000 + stretch_vlans[i]))"; done |
	sort -u)"
[ "$(wc -l <<<"$rts")" -eq 3 ] || {
	echo "error: workload route targets are not distinct: ${rts//$'\n'/ }" >&2
	exit 1
}

# ═ 3. same-VLAN reachability ═════════════════════════════════════════════════
for i in 0 1 2; do
	while read -r key; do
		check_reach "${stretch_names[i]}" "${pod_ip["$key"]}"
	done < <(pods_of "${stretch_names[i]}")
done
echo ">> same-VLAN reachability ok (ping + HTTP, every pod, every node)"

# ═ 4. no cross-VLAN data plane ═══════════════════════════════════════════════
# The appliance is the gateway of every stretch SVI and forwards IP, so
# VM-to-foreign-subnet traffic would be routed, not leaked. Refuse that path:
# drop forwarding between the stretch subnets (same-subnet traffic is bridged
# and never matches). Installed for all four subnets up front so the day-2
# stretch is covered too.
# runtime exec runs this remotely; single quotes keep the loop on the appliance.
# shellcheck disable=SC2016
runtime exec "$appliance_ctr" sh -c '
for a in 10.42.1.0/24 10.42.2.0/24 10.42.3.0/24 10.42.4.0/24; do
	for b in 10.42.1.0/24 10.42.2.0/24 10.42.3.0/24 10.42.4.0/24; do
		[ "$a" = "$b" ] && continue
		iptables -w -C FORWARD -s "$a" -d "$b" -j DROP 2>/dev/null ||
			iptables -w -I FORWARD -s "$a" -d "$b" -j DROP
	done
done
'

for i in 0 1 2; do
	for ((j = 0; j < 3; j++)); do
		[ "$j" -eq "$i" ] && continue
		while read -r key; do
			check_isolated "${stretch_names[i]}" "${pod_ip["$key"]}"
		done < <(pods_of "${stretch_names[j]}")
	done
done
echo ">> no cross-VLAN data plane (ping and HTTP fail on every foreign VNI)"

# Re-run the control-plane isolation after the dataplane traffic: MAC tables
# (now populated by the ARP the probes generated) and Type-2 route targets per
# VNI, on the appliance and on every frr-k8s pod.
check_vni_isolation 3 expect-macs

# ═ 5. day-2: VLAN 400 as a new EVPN CUDN ═════════════════════════════════════
echo ">> day-2: apply VLAN 400 (database) as a new EVPN CUDN"
kubectl apply -f "${self_dir}/day2/manifests.yml"
kubectl wait --for=condition=NetworkCreated clusteruserdefinednetwork/database \
	--timeout=180s

ee_playbook network.evpn_gateway_test.simulate -e @"${EGA_LAB_DIR}/stretches-day2.yml"
ee_playbook network.evpn_gateway.deploy \
	-e @"${EGA_LAB_DIR}/stretches-day2.yml" \
	-e frr_k8s_ns=frr-k8s-system \
	-e frr_k8s_lbl=app=frr-k8s

kubectl -n database rollout status daemonset/ega-test-workload --timeout=180s
ready="$(kubectl -n database get daemonset ega-test-workload \
	-o jsonpath='{.status.numberReady}')"
[ "$ready" = "$nodes" ] || {
	echo "error: database: ${ready}/${nodes} workload pods ready" >&2
	exit 1
}
gather_pods database

addr="$(vm_exec database ip -4 -o addr show dev eth0 | awk '{ print $4 }' | cut -d/ -f1)"
[ "$addr" = "10.42.4.10" ] || {
	echo "error: vm-database has ${addr:-no address}, want 10.42.4.10" >&2
	exit 1
}

while read -r key; do
	check_reach database "${pod_ip["$key"]}"
done < <(pods_of database)
for i in 0 1 2; do
	while read -r key; do
		check_reach "${stretch_names[i]}" "${pod_ip["$key"]}"
	done < <(pods_of "${stretch_names[i]}")
done
for i in 0 1 2; do
	while read -r key; do
		check_isolated database "${pod_ip["$key"]}"
	done < <(pods_of "${stretch_names[i]}")
done
while read -r key; do
	for i in 0 1 2; do
		check_isolated "${stretch_names[i]}" "${pod_ip["$key"]}"
	done
done < <(pods_of database)
check_vni_isolation 4 expect-macs
echo ">> day-2 VLAN 400 reachable and isolated"

# ═ 6. delete and recreate the day-2 CUDN ═════════════════════════════════════
echo ">> day-2: delete the VLAN 400 CUDN"
mapfile -t db_pod_macs < <(pods_of database | while read -r key; do
	echo "${pod_mac["$key"]}"
done)
# The DaemonSet (and its pods) must go first: the CUDN's
# k8s.ovn.org/user-defined-network-protection finalizer refuses to release the
# NetworkAttachmentDefinition while pods still reference the network, so
# deleting the CUDN with the DaemonSet up would block forever.
kubectl -n database delete daemonset ega-test-workload
pods_deadline=$((SECONDS + 180))
while [ -n "$(kubectl -n database get pods -l app=ega-test-workload -o name 2>/dev/null)" ]; do
	if ((SECONDS >= pods_deadline)); then
		echo "error: database workload pods did not terminate" >&2
		exit 1
	fi
	sleep 2
done
kubectl delete clusteruserdefinednetwork database
wait_gone clusteruserdefinednetwork/database

# Wait until the database pod Type-2s are withdrawn everywhere: none of the
# pod MACs may remain in any vni 10400 MAC table (a missing VNI counts as gone).
macs_gone() {
	local out mac pod
	out="$(appliance_frr 'show evpn mac vni 10400 json' 2>/dev/null |
		python3 "$frrjson" macs 2>/dev/null || true)"
	for mac in "${db_pod_macs[@]}"; do
		grep -qx "$mac" <<<"$out" && return 1
	done
	for pod in "${frr_pods[@]}"; do
		out="$(frr_k8s_exec "$pod" 'show evpn mac vni 10400 json' 2>/dev/null |
			python3 "$frrjson" macs 2>/dev/null || true)"
		for mac in "${db_pod_macs[@]}"; do
			grep -qx "$mac" <<<"$out" && return 1
		done
	done
	return 0
}
deadline=$((SECONDS + 180))
until macs_gone; do
	if ((SECONDS >= deadline)); then
		echo "timed out waiting for the VLAN 400 Type-2 withdrawal" >&2
		exit 1
	fi
	sleep 5
done
echo ">> VLAN 400 pod Type-2s withdrawn"

# The original three stretches keep answering while VLAN 400 is gone.
for i in 0 1 2; do
	read -r key < <(pods_of "${stretch_names[i]}")
	check_reach "${stretch_names[i]}" "${pod_ip["$key"]}"
done

echo ">> day-2: recreate the VLAN 400 CUDN"
kubectl apply -f "${self_dir}/day2/manifests.yml"
kubectl wait --for=condition=NetworkCreated clusteruserdefinednetwork/database \
	--timeout=180s
kubectl -n database rollout status daemonset/ega-test-workload --timeout=180s
gather_pods database reset
while read -r key; do
	check_reach database "${pod_ip["$key"]}"
done < <(pods_of database)
echo ">> VLAN 400 reachability restored after recreate"

echo ">> multi-vni ok"
