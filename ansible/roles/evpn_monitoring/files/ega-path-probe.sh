#!/bin/sh
set -eu
export LC_ALL=C

target=${1:?target address required}
success=0
rtt=
# -c 3 -w 5: ping sends up to 5 requests and exits 1 unless 3 replies arrive within 5s, so
# success means at most 2 of 5 lost. Any other failure is local (bad target, no socket), so exit
# without writing and let the stale textfile report the probe as unavailable.
if reply=$(ping -n -q -c 3 -w 5 "$target"); then
	success=1
	rtt=$(printf '%s\n' "$reply" | awk -F/ '/^rtt / {printf "%.9f", $5 / 1000}')
else
	rc=$?
	[ "$rc" -eq 1 ] || exit "$rc"
fi
output=${EGA_PATH_PROBE_OUTPUT:-/var/lib/node_exporter/textfile/ega-path-probe.prom}
tmp=$(mktemp "${output}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
{
	printf '%s\n' '# HELP ega_path_probe_success 1 if 3 echo replies arrived within 5s (up to 5 requests), else 0.'
	printf '%s\n' '# TYPE ega_path_probe_success gauge'
	printf 'ega_path_probe_success{target="%s"} %s\n' "$target" "$success"
	printf '%s\n' '# HELP ega_path_probe_rtt_seconds Average round-trip time of the 3 echo replies in seconds, only on success.'
	printf '%s\n' '# TYPE ega_path_probe_rtt_seconds gauge'
	if [ -n "$rtt" ]; then
		printf 'ega_path_probe_rtt_seconds{target="%s"} %s\n' "$target" "$rtt"
	fi
} > "$tmp"
chmod 0644 "$tmp"
mv -f "$tmp" "$output"
