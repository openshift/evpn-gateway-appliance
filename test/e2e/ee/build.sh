#!/usr/bin/env bash
# Build the test EE from the collection's EE metadata using the CI image — no host
# ansible-builder. `ansible-builder create` (pure Python, no podman) generates the build
# context inside the CI image; then `podman build` turns it into the EE. Runs rootless. In CI
# this maps to a pre-step that builds the generated Containerfile like any other image
# (ci-operator), so there's no ansible-builder-drives-podman there.
#
#   EGA_EE_IMAGE   EE tag             [default: localhost/evpn-gateway-appliance-ee:local]
#   EGA_E2E_IMAGE  CI image (has ansible-core + ansible-builder)  [default: localhost/evpn-gateway-appliance-ci:local]
#   EGA_EE_BASE    override EE base   [default: the definition's; CI sets a mirrored ref]
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"
tag="${EGA_EE_IMAGE:-localhost/evpn-gateway-appliance-ee:local}"
ci_image="${EGA_E2E_IMAGE:-localhost/evpn-gateway-appliance-ci:local}"

# Stage the inputs in a scratch dir outside the repo (nothing gets written into, or
# SELinux-relabeled in, the checkout); remove it on exit.
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
cp "$here/execution-environment.yml" "$build_dir/"
cp -r "$repo_root/ansible" "$build_dir/collection-src"

# Generate the collection tarball + EE build context with the CI image.
podman run --rm --user 0 -v "$build_dir:/ee:Z" -w /ee "$ci_image" sh -c '
	ansible-galaxy collection build collection-src --force --output-path .
	mv -f network-evpn_gateway-*.tar.gz network-evpn_gateway.tar.gz
	ansible-builder create -f execution-environment.yml -c context
'

# Build the EE from the generated context (plain image build). ansible-builder names the file
# Containerfile or Dockerfile depending on version; let podman auto-detect either.
bargs=()
[ -n "${EGA_EE_BASE:-}" ] && bargs=(--build-arg "EE_BASE_IMAGE=${EGA_EE_BASE}")
podman build -t "$tag" "${bargs[@]}" "$build_dir/context"

# Verify the EE carries the collection + its derived deps.
echo ">> verifying $tag"
podman run --rm "$tag" sh -c '
	set -e
	wg --version
	python3 -c "import netaddr, boto3; print(\"netaddr\", netaddr.__version__)"
	ansible-galaxy collection list 2>/dev/null | grep -E "evpn_gateway|ansible\.utils"'
echo ">> EE canary OK: $tag"
