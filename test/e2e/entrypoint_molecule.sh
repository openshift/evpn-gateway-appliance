#!/usr/bin/env bash
# In-container steps for the molecule lane. Runs INSIDE the pinned CI image (Dockerfile.ci),
# launched by run.sh with the host runtime socket mounted. Molecule's delegated driver creates the
# appliance instance as a SIBLING on that rootful socket (host kernel for vxlan/bridge netlink), so
# molecule cannot create it from a nested, rootless Prow container — which is why this lane rides the
# same rootful VM substrate as the e2e lane.
#
# EGA_STAGE selects scenarios: full / unset -> all; otherwise a single molecule scenario name.
set -euo pipefail

: "${EGA_NODE_IMAGE:?}"    # appliance image the delegated create runs as the instance
: "${EGA_RUNTIME_SOCK:?}"  # rootful podman socket; container create/exec go through it
stage="${EGA_STAGE:-full}"

# The podman CLI — and the connection plugin's `podman exec` — target the mounted rootful socket, so
# the molecule instance is a sibling on the host runtime with the host kernel.
export CONTAINER_HOST="unix://${EGA_RUNTIME_SOCK}"
export EGA_NODE_IMAGE

# /src is read-only in the CI image (chmod a-w), so work from a writable copy of the collection:
# molecule and ansible write ephemeral state relative to the project. Symlink that copy into a
# collections path so converge/verify resolve the role by FQCN (network.evpn_gateway.*) without a
# build; append the image's baked collections dir so containers.podman (the podman connection the
# delegated instance uses) still resolves.
work=/tmp/ega/molecule
rm -rf "${work}"; mkdir -p "${work}"
cp -a /src/ansible "${work}/ansible"
col_root="${work}/collections"
mkdir -p "${col_root}/ansible_collections/network"
ln -sfn "${work}/ansible" "${col_root}/ansible_collections/network/evpn_gateway"
export ANSIBLE_COLLECTIONS_PATH="${col_root}:/usr/share/ansible/collections"

# Scenarios live under ansible/tests/molecule; point molecule at them and run from the collection.
export MOLECULE_GLOB="tests/molecule/*/molecule.yml"
cd "${work}/ansible"

if [ "$stage" = full ] || [ "$stage" = molecule ]; then
	exec molecule test --all
fi
exec molecule test -s "$stage"
