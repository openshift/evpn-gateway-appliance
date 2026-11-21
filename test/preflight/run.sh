#!/bin/sh
# Each case: expected message (empty = pass), then extra vars for $play (play.yml, then baseline.yml).
cd "$(dirname "$0")" || exit 1
failed=0
check() {
	want=$1; shift
	out=$(ANSIBLE_NOCOLOR=1 ansible-playbook -i hosts.yml "${play:-play.yml}" -e "$1" 2>&1); rc=$?
	pass=0
	if [ -z "$want" ]; then
		[ $rc -eq 0 ] && pass=1
	elif [ $rc -ne 0 ] && printf '%s' "$out" | grep -q "$want"; then
		pass=1
	fi
	if [ $pass -eq 1 ]; then
		echo "ok   $1"
	else
		echo "FAIL $1 (want ${want:-success}, rc=$rc)"; printf '%s\n' "$out" | tail -20; failed=1
	fi
}
check "crosses the internet" '{"ttype": "wireguard"}'
check "crosses the internet" '{"ttype": "ipsec"}'
# -e key=value passes strings.
check "crosses the internet" 'ttype=wireguard evpn_health_check_accept_internet_mode_limits=false'
check "" 'ttype=ipsec evpn_health_check_accept_internet_mode_limits=true evpn_health_check_workload_mtu=1388'
check "" '{"ttype": "wireguard", "evpn_health_check_accept_internet_mode_limits": true, "evpn_health_check_workload_mtu": 1370}'
check "exceeds the" '{"ttype": "wireguard", "evpn_health_check_accept_internet_mode_limits": true, "evpn_health_check_workload_mtu": 1371}'
check "" '{"ttype": "ipsec", "evpn_health_check_accept_internet_mode_limits": true, "evpn_health_check_workload_mtu": 1388}'
check "exceeds the" '{"ttype": "ipsec", "evpn_health_check_accept_internet_mode_limits": true, "evpn_health_check_workload_mtu": 1389}'
check "exceeds the" '{"ttype": "ipsec", "evpn_health_check_accept_internet_mode_limits": true, "second_workload_mtu": 1389}'
check "must be one of" '{"ttype": "dx"}'
# The health check's loss and RTT baseline on canned iputils summaries.
play=baseline.yml
BASELINE_DIR=$(mktemp -d) || exit 1
export BASELINE_DIR
trap 'rm -rf "$BASELINE_DIR"' EXIT
ok='20 packets transmitted, 20 received, 0% packet loss, time 3805ms\nrtt min/avg/max/mdev = 0.512/1.234/2.001/0.300 ms'
part='20 packets transmitted, 15 received, +2 duplicates, +3 errors, 25% packet loss, time 3805ms\nrtt min/avg/max/mdev = 0.512/12.500/30.001/3.300 ms, pipe 2'
check "" "{\"ping_out\": \"$ok\"}"
check "" "{\"ping_out\": \"$ok\", \"evpn_health_check_max_rtt_ms\": 1.234}"
check "average RTT 1.234 ms" "{\"ping_out\": \"$ok\", \"evpn_health_check_max_rtt_ms\": 1.2}"
check "" "{\"ping_out\": \"$part\", \"evpn_health_check_max_loss_percent\": null, \"evpn_health_check_max_rtt_ms\": null}"
check "" "{\"ping_out\": \"$part\", \"evpn_health_check_max_loss_percent\": 25, \"evpn_health_check_max_rtt_ms\": 12.5}"
check "loss 25%" "{\"ping_out\": \"$part\", \"evpn_health_check_max_loss_percent\": 24}"
check "average RTT 12.500 ms" "{\"ping_out\": \"$part\", \"evpn_health_check_max_rtt_ms\": 12}"
check "loss 100%" '{"ping_out": "20 packets transmitted, 0 received, +20 errors, 100% packet loss, time 3805ms"}'
check "loss 100%" '{"ping_out": ""}'
# Received replies without an rtt line: no RTT, which fails only a set limit.
check "" '{"ping_out": "20 packets transmitted, 20 received, 0% packet loss, time 3805ms"}'
check "average RTT inf" '{"ping_out": "20 packets transmitted, 20 received, 0% packet loss", "evpn_health_check_max_rtt_ms": 1000}'
exit $failed
