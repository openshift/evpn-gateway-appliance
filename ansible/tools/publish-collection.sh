#!/usr/bin/env bash
# Upload the single built collection in the supplied directory to Automation Hub.
set -euo pipefail

: "${AH_TOKEN:?Set AH_TOKEN to your Automation Hub API token}"
shopt -s nullglob
tarballs=("${1:?usage: $0 TARBALL_DIRECTORY}"/*.tar.gz)
if [[ ${#tarballs[@]} != 1 ]]; then
  echo 'error: expected exactly one collection tarball in the build directory' >&2
  exit 1
fi

umask 077
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/ansible.cfg" <<'EOF'
[galaxy]
server_list = automation_hub

[galaxy_server.automation_hub]
url = https://console.redhat.com/api/automation-hub/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
EOF

ANSIBLE_CONFIG="$tmp/ansible.cfg" \
  ANSIBLE_GALAXY_SERVER_AUTOMATION_HUB_TOKEN="$AH_TOKEN" \
  ansible-galaxy collection publish "${tarballs[0]}"
