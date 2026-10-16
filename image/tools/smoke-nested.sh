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
if ! podman info --format '{{.Host.CgroupVersion}} {{.Host.Security.Rootless}}' >"$podman_info" 2>"$podman_error"; then
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

config=$(mktemp -d)
container_id=""
cleanup() {
  status=$?
  if [[ -n $container_id ]]; then
    if [[ $status -ne 0 ]]; then
      podman exec "$container_id" journalctl --no-pager -n 80 \
        -u ega-payload-load.service -u frr.service -u node-exporter.service >&2 || true
    fi
    podman rm -f "$container_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$config"
}
trap cleanup EXIT

printf '%s\n' 'bgpd=yes' 'bfdd=yes' >"$config/daemons"
cat >"$config/frr.conf" <<'EOF'
hostname ega-smoke
frr defaults traditional
service integrated-vtysh-config
log stdout
router bgp 65000
 bgp router-id 192.0.2.1
EOF

container_id=$(podman run -d --pull=never --privileged --network none --cgroupns=host --systemd=always \
  -v "$config:/etc/frr:Z" "$image")

ready() {
  local unit
  for unit in ega-payload-load.service frr.service node-exporter.service; do
    podman exec "$container_id" systemctl is-active --quiet "$unit" || return 1
  done
  podman exec "$container_id" podman exec frr vtysh -c 'show bgp summary' >/dev/null || return 1
  podman exec "$container_id" curl --max-time 5 --fail --silent http://127.0.0.1:9100/metrics \
    | grep '^node_exporter_build_info{' >/dev/null
}

wait_ready() {
  for _ in $(seq 1 60); do
    if ready; then
      return 0
    fi
    sleep 1
  done
  echo "FRR and node-exporter did not become ready" >&2
  return 1
}

wait_ready

podman exec "$container_id" systemctl restart frr.service node-exporter.service
wait_ready

echo "nested offline smoke passed for $image (this does not qualify bootc install, upgrade, rollback, or VM boot)"
