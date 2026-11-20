#!/bin/sh
# Unit test for ansible/roles/evpn_monitoring/files/ega-path-probe.sh with a fake ping.
# Run from the repository root; PROMTOOL (default promtool) validates the textfile.
set -eu

script=ansible/roles/evpn_monitoring/files/ega-path-probe.sh
promtool=${PROMTOOL:-promtool}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
cat > "$work/bin/ping" <<'PING'
#!/bin/sh
printf '%s\n' "$*" > "$FAKE_PING_ARGS"
if [ "$FAKE_PING_RC" = 0 ]; then
	printf '%s\n' '3 packets transmitted, 3 received, 0% packet loss, time 2003ms'
	[ -n "${FAKE_PING_NO_RTT:-}" ] || printf '%s\n' 'rtt min/avg/max/mdev = 0.100/1.250/2.000/0.300 ms'
fi
exit "$FAKE_PING_RC"
PING
chmod +x "$work/bin/ping"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

probe() {
	PATH="$work/bin:$PATH" FAKE_PING_RC=$1 FAKE_PING_ARGS="$work/args" FAKE_PING_NO_RTT="${FAKE_PING_NO_RTT:-}" \
		EGA_PATH_PROBE_OUTPUT="$work/out.prom" sh "$script" "$2"
}

probe 0 192.0.2.1
grep -qx 'ega_path_probe_success{target="192.0.2.1"} 1' "$work/out.prom" || fail 'success line'
grep -qx 'ega_path_probe_rtt_seconds{target="192.0.2.1"} 0.001250000' "$work/out.prom" || fail 'RTT line'
grep -qx -- '-n -q -c 3 -w 5 192.0.2.1' "$work/args" || fail 'ping arguments'
"$promtool" check metrics < "$work/out.prom" || fail 'promtool check metrics on success'

probe 1 192.0.2.1
grep -qx 'ega_path_probe_success{target="192.0.2.1"} 0' "$work/out.prom" || fail 'failure line'
! grep -q '^ega_path_probe_rtt_seconds' "$work/out.prom" || fail 'RTT written on failure'
"$promtool" check metrics < "$work/out.prom" || fail 'promtool check metrics on failure'

if probe 0 '' 2> /dev/null; then fail 'empty target accepted'; fi

# The stale-file alert reads the textfile's mtime, so a local error must not touch it either.
touch -d '2000-01-01 00:00:00' "$work/out.prom"
cp -p "$work/out.prom" "$work/before.prom"
if probe 2 192.0.2.1; then fail 'local ping error reported as a result'; fi
[ "$(cat "$work/out.prom")" = "$(cat "$work/before.prom")" ] || fail 'textfile rewritten after a local ping error'
[ ! "$work/out.prom" -nt "$work/before.prom" ] || fail 'textfile touched after a local ping error'

FAKE_PING_NO_RTT=1
probe 0 192.0.2.1
FAKE_PING_NO_RTT=
grep -qx 'ega_path_probe_success{target="192.0.2.1"} 1' "$work/out.prom" || fail 'success without RTT'
! grep -q '^ega_path_probe_rtt_seconds' "$work/out.prom" || fail 'empty RTT written'
"$promtool" check metrics < "$work/out.prom" || fail 'promtool check metrics without RTT'
[ -z "$(find "$work" -maxdepth 1 -name 'out.prom.*')" ] || fail 'temporary file left behind'

printf '%s\n' 'ega-path-probe: OK'
