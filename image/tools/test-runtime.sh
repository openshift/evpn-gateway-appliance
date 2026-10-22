#!/usr/bin/env bash
# Build the appliance and its nested-CI derivative, then exercise their offline services.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)
: "${SOURCE_REVISION:?set SOURCE_REVISION to the tested Git commit}"
: "${REGISTRY_AUTH_FILE:?set REGISTRY_AUTH_FILE to a registry auth file outside image/}"
: "${ARTIFACT_DIR:?set ARTIFACT_DIR to an absolute output directory}"
if [[ ! $SOURCE_REVISION =~ ^[[:xdigit:]]{40}$ || $ARTIFACT_DIR != /* ]]; then
  echo "expected a full source revision and an absolute artifact directory" >&2
  exit 2
fi
auth=$(realpath -e -- "$REGISTRY_AUTH_FILE")
if [[ ! -f $auth || ! -r $auth || $auth == "$root/image/"* ]]; then
  echo "registry auth must be a readable file outside the image build context" >&2
  exit 2
fi
mkdir -p -- "$ARTIFACT_DIR"
ARTIFACT_DIR=$(realpath -e -- "$ARTIFACT_DIR")
# Never associate a new revision with outputs left by an earlier run.
if [[ ! -r $ARTIFACT_DIR || ! -x $ARTIFACT_DIR ]] || (
  shopt -s nullglob dotglob
  entries=("$ARTIFACT_DIR"/*)
  ((${#entries[@]} != 0))
); then
  echo "artifact directory must be readable, searchable, and empty" >&2
  exit 2
fi
printf '%s\n' "$SOURCE_REVISION" >"$ARTIFACT_DIR/source-revision.txt"

# Reject an unsuitable runner before downloading images or building anything.
podman info --format '{{.Host.CgroupsVersion}} {{.Host.Security.Rootless}} {{.Version.Version}}' \
  >"$ARTIFACT_DIR/host-podman.txt"
read -r cgroups rootless _ <"$ARTIFACT_DIR/host-podman.txt"
if [[ $cgroups != v2 || $rootless != false ]]; then
  echo "appliance runtime requires rootful Podman with cgroup v2" >&2
  exit 2
fi

printf -v tag 'localhost/ega-runtime-%08x' "$SRANDOM"
appliance_image="$tag:appliance"
ci_image="$tag:nested-ci"
cleanup() {
  local status=$?
  # Guard before dropping the EXIT trap: a second signal must not cut cleanup short.
  trap : INT TERM
  trap - EXIT
  set +e
  if ! timeout --kill-after=1s 30s podman image rm --ignore "$ci_image" "$appliance_image" 2>&1 \
      | (trap '' INT TERM; exec tee "$ARTIFACT_DIR/image-cleanup.log") >/dev/null; then
    echo "failed to remove runtime test images; see image-cleanup.log" >&2
    if [[ $status == 0 ]]; then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Cancellation can close the output reader before cleanup reports an error.
trap '' PIPE

# Disable layer caching so completed builds leave no intermediate images.
# VM teardown also handles working containers left by an interrupted build.
build_args=(--layers=false --authfile "$auth" --label "org.opencontainers.image.revision=$SOURCE_REVISION")
if [[ -n ${BOOTC_BASE:-} ]]; then
  build_args+=(--build-arg "BOOTC_BASE=$BOOTC_BASE")
fi
for name in EGA_PAYLOAD_RHEL10_FRR_REPOSITORY EGA_PAYLOAD_RHEL10_FRR_TAG EGA_PAYLOAD_RHEL10_FRR_DIGEST \
  EGA_PAYLOAD_RHEL10_NODE_EXPORTER_REPOSITORY EGA_PAYLOAD_RHEL10_NODE_EXPORTER_TAG EGA_PAYLOAD_RHEL10_NODE_EXPORTER_DIGEST; do
  if [[ -n ${!name:-} ]]; then build_args+=(--build-arg "$name=${!name}"); fi
done

echo "Building appliance from source $SOURCE_REVISION"
podman build "${build_args[@]}" \
  --iidfile "$ARTIFACT_DIR/appliance-image.id" -t "$appliance_image" \
  -f "$root/image/rhel10/Containerfile" "$root/image" 2>&1 | tee "$ARTIFACT_DIR/appliance-build.log"

echo "Building the offline runtime derivative"
podman build --layers=false --pull=never \
  --label "org.opencontainers.image.revision=$SOURCE_REVISION" \
  --secret "id=registry-auth,src=$auth" --build-arg "APPLIANCE_IMAGE=$appliance_image" \
  --iidfile "$ARTIFACT_DIR/runtime-image.id" -t "$ci_image" \
  -f "$root/image/Containerfile.nested-ci" "$root/image" 2>&1 | tee "$ARTIFACT_DIR/runtime-build.log"

echo "Checking services and restart with the container network disabled"
ARTIFACT_DIR="$ARTIFACT_DIR/smoke" \
  bash "$root/image/tools/smoke-nested.sh" "$ci_image" 2>&1 | tee "$ARTIFACT_DIR/smoke.log"
