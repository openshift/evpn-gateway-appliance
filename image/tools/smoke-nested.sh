#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 CI-IMAGE" >&2
  exit 2
fi
image=$1

command -v podman >/dev/null || { echo "prerequisite unavailable: podman" >&2; exit 2; }
podman_info=$(mktemp)
podman_error=$(mktemp)
if ! podman info --format '{{.Host.CgroupsVersion}} {{.Host.Security.Rootless}}' >"$podman_info" 2>"$podman_error"; then
  echo "prerequisite unavailable: podman cannot inspect the runtime" >&2
  sed -n '1,12p' "$podman_error" >&2
  rm -f "$podman_info" "$podman_error"
  exit 2
fi
read -r cgroup_version rootless <"$podman_info"
rm -f "$podman_info" "$podman_error"
if [[ $cgroup_version != v2 ]]; then
  echo "prerequisite unavailable: nested smoke requires cgroup v2 (got $cgroup_version)" >&2
  exit 2
fi
if [[ $rootless != false ]]; then
  echo "prerequisite unavailable: nested smoke requires rootful Podman" >&2
  exit 2
fi

if [[ -n ${ARTIFACT_DIR:-} ]]; then
  mkdir -p -- "$ARTIFACT_DIR"
fi
config=$(mktemp -d)
container_name="ega-smoke-${config##*/}"
started=false

diagnostics() {
  # The logging pipeline runs this function in a subshell; keep cleanup's signal guard.
  trap : INT TERM
  # Select fields explicitly: full container inspection can contain credentials.
  timeout --kill-after=1s 4s podman inspect --format \
    '{{.Id}} {{.State.Status}} {{.State.ExitCode}}' "$container_name" || true
  timeout --kill-after=1s 4s podman exec "$container_name" systemctl --no-pager status \
    ega-payload-load.service frr.service node-exporter.service || true
  timeout --kill-after=1s 4s podman exec "$container_name" journalctl --no-pager -n 80 \
    -u ega-payload-load.service -u frr.service -u node-exporter.service || true
  # The nested Podman comes from the base's repositories at build time, so record it.
  timeout --kill-after=1s 4s podman exec "$container_name" podman info \
    --format '{{.Store.GraphDriverName}} {{.Version.Version}}' || true
  timeout --kill-after=1s 4s podman exec "$container_name" podman ps -a \
    --format '{{.Names}} {{.Status}}' || true
  # Systemd's boot output is the only record if exec never works.
  timeout --kill-after=1s 10s podman logs --tail 200 "$container_name" || true
}

cleanup() {
  local status=$?
  local cleanup_log=/dev/null
  # Guard before dropping the EXIT trap: a second signal must not cut cleanup short.
  # Each step is bounded and checks its own status.
  trap : INT TERM
  trap - EXIT
  set +e
  if [[ $started == true ]]; then
    if [[ -n ${ARTIFACT_DIR:-} ]]; then
      cleanup_log=$ARTIFACT_DIR/runtime.txt
      if ! diagnostics 2>&1 | (trap '' INT TERM; exec tee "$ARTIFACT_DIR/runtime.txt") >/dev/null; then
        echo "failed to save smoke diagnostics" >&2
        if [[ $status == 0 ]]; then status=1; fi
      fi
    else
      diagnostics >&2
    fi
    # Bound systemd's stop grace and allow removal of the nested VFS store.
    # Podman can raise SIGPIPE on a stop warning if the caller's reader has gone.
    if ! timeout --kill-after=1s 1m podman rm -f --time 1 --ignore "$container_name" 2>&1 \
        | (trap '' INT TERM; exec tee -a "$cleanup_log") >/dev/null; then
      echo "failed to remove smoke container $container_name" >&2
      if [[ $status == 0 ]]; then status=1; fi
    fi
  fi
  if ! rm -rf -- "$config"; then
    if [[ $status == 0 ]]; then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# The caller's output reader can exit first on cancellation. Without this, bash's
# report of a terminated child raises SIGPIPE, which sets status 141 and can end
# cleanup at its first write to stderr.
trap '' PIPE

printf '%s\n' 'bgpd=yes' 'bfdd=yes' >"$config/daemons"
printf '%s\n' 'service integrated-vtysh-config' >"$config/vtysh.conf"
cat >"$config/frr.conf" <<'EOF'
hostname ega-smoke
frr defaults traditional
log stdout
router bgp 65000
 bgp router-id 192.0.2.1
EOF

started=true
podman run -d --name "$container_name" --pull=never --privileged --network none --cgroupns=host --systemd=always \
  -v "$config:/etc/frr:Z" "$image"

# Bound each probe so a hung command fails its poll instead of the caller's deadline.
# --foreground keeps it in our process group, so the caller's timeout still reaches it.
probe() {
  timeout --foreground --kill-after=5s 30s podman exec "$@"
}

ready() {
  local unit
  for unit in ega-payload-load.service frr.service node-exporter.service; do
    probe "$container_name" systemctl is-active --quiet "$unit" || return 1
  done
  # vtysh can exit zero when the BGP instance is missing. Check the fixture state.
  probe "$container_name" podman exec frr vtysh -c 'show bgp ipv4 unicast json' \
    | probe -i "$container_name" python3 -c '
import json, sys
try:
    bgp = json.load(sys.stdin)
except ValueError:
    sys.exit(1)
sys.exit(not isinstance(bgp, dict) or bgp.get("localAS") != 65000
         or bgp.get("routerId") != "192.0.2.1")
' || return 1
  probe "$container_name" curl --noproxy '*' --max-time 5 --fail --silent http://127.0.0.1:9100/metrics \
    | grep '^node_exporter_build_info{' >/dev/null
}

# Poll against a clock, not a count: one hung probe can take its full timeout every poll.
wait_ready() {
  local deadline
  deadline=$(($(date +%s) + 300))
  while (($(date +%s) < deadline)); do
    if ready; then
      return 0
    fi
    sleep 1
  done
  echo "FRR and node-exporter did not become ready during $1" >&2
  return 1
}

wait_ready startup

# Masking the vendor drop-ins leaves plain VFS. Options would mean an inherited drop-in,
# such as the bootc additional image store, still applies.
store=$(probe "$container_name" podman info --format '{{.Store.GraphDriverName}} {{len .Store.GraphOptions}}')
if [[ $store != "vfs 0" ]]; then
  echo "nested smoke requires VFS storage without store options (got driver and option count: $store)" >&2
  exit 1
fi

timeout --foreground --kill-after=5s 2m \
  podman exec "$container_name" systemctl restart frr.service node-exporter.service
wait_ready restart

echo "nested offline smoke passed for $image (this does not qualify bootc install, upgrade, rollback, or VM boot)"
