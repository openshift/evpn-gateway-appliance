# EVPN appliance bootc image

The RHEL 10 image contains the host operating system and two Quadlet bindings.
It does not contain the FRR or node-exporter image layers. `payload-images.yaml`
is the one inventory for their repository, tag, and immutable digest. The
Containerfile renders the `.container.in` templates during the build and keeps
the generated units in `/usr/share/containers/systemd/` and
`/usr/lib/bootc/bound-images.d/`.

The product image uses bootc logically bound images. The host running
`bootc install` must already have the exact payload references in its normal
Podman store. bootc copies them into `/usr/lib/bootc/storage` on the target.
`bootc upgrade` and `bootc switch` pull the pinned references again using the
host's configured registry credentials. Anaconda does not support this install
path. The image's Quadlets add the bootc store only to their own Podman
commands; it is not a global storage configuration.

## Verify the inventory and generated units

```bash
make payload-test
python3 image/tools/payload.py render \
  --inventory image/payload-images.yaml \
  --stream rhel10 \
  --templates image/rhel10 \
  --output /tmp/ega-rendered
```

The renderer requires PyYAML. The OS build installs `python3-pyyaml` only in
its temporary rendering stage, so the final product image does not need a YAML
runtime dependency. Resolve a tag in an authenticated registry session before
updating its digest in `payload-images.yaml`. These source checks do not contact
the registry or verify that a tag still matches its recorded digest.

CI controls a build's pin with environment variables. A set variable replaces
the matching field in `payload-images.yaml` for that build. An empty or unset
variable leaves the committed value. For one service, set all three variables
or none of them. The FRR unit's `Exec=` repeats the payload's start command, so
a new FRR pin or override must keep `/usr/lib/frr/docker-start`.

- `EGA_PAYLOAD_RHEL10_FRR_REPOSITORY`
- `EGA_PAYLOAD_RHEL10_FRR_TAG`
- `EGA_PAYLOAD_RHEL10_FRR_DIGEST`
- `EGA_PAYLOAD_RHEL10_NODE_EXPORTER_REPOSITORY`
- `EGA_PAYLOAD_RHEL10_NODE_EXPORTER_TAG`
- `EGA_PAYLOAD_RHEL10_NODE_EXPORTER_DIGEST`

Pass the same names as `--build-arg` to `podman build`. The rendering stage
exports them into the renderer. The committed file remains the default for a
build that sets none of them.

## Build the product image

The build context is `image/`, because rendering reads the inventory and the
templates together.

```bash
podman build -f image/rhel10/Containerfile \
  -t localhost/evpn-appliance-rhel10:dev image
```

For a CI base, pass `--build-arg BOOTC_BASE=...`. A normal `podman build` of
this Containerfile does not populate `/usr/lib/bootc/storage` and cannot prove
an offline boot. Build a bootable disk with bootc or an image builder, preload
the two exact references on the install host, and test the resulting machine
with the registry unavailable.

## Build and run the nested CI derivative

The CI-only derivative starts from a completed appliance image. It uses a
BuildKit or Buildah secret to pull every concrete `Image=` reference with
Skopeo's `dir` transport, `--all`, and `--preserve-digests`. The full OCI index,
all platform manifests, configs, layers, and entrypoints are retained in
`/usr/lib/ega/payload-cache`. At startup the loader validates the cache before
copying the native platform instance into ordinary Podman storage. The CI
drop-ins clear the bootc `additionalimagestore`, set `Pull=never`, and order
both workloads after the loader.
The derivative uses VFS storage to avoid nested overlay mounts. It also caches
all architectures to preserve an index pin without rewriting its manifest.
Both choices increase CI disk usage.

```bash
podman build -f image/rhel10/Containerfile \
  -t localhost/evpn-appliance-rhel10:dev image
podman build -f image/Containerfile.nested-ci \
  --build-arg APPLIANCE_IMAGE=localhost/evpn-appliance-rhel10:dev \
  --secret id=registry-auth,src=/path/outside/repository/auth.json \
  -t localhost/evpn-appliance-rhel10:nested-ci image
bash image/tools/smoke-nested.sh localhost/evpn-appliance-rhel10:nested-ci
```

The smoke requires a rootful Podman runtime with cgroup v2, nested systemd,
and privileged containers. It disables the container network, starts both
services, checks the fixture's local AS and router ID with `vtysh`, checks
node-exporter metrics on localhost, and repeats those checks after a restart.
It also requires the nested store to be plain VFS, with no inherited options.
A prerequisite failure is reported as unavailable. This is an offline
nested-container check and does not qualify
bootc installation, upgrade, rollback, or a virtual machine boot.
Docker and kind runners need their own privileged systemd and cgroup setup.
The supplied smoke runner uses Podman.

## Run the build and runtime check

`image/tools/test-runtime.sh` builds `image/rhel10/Containerfile` and
`image/Containerfile.nested-ci`, then runs the offline service/restart smoke.
Run it from a clean checkout on a disposable rootful Podman host with cgroup v2
and enough disk space for the base and payloads:

```bash
runtime_artifacts=$(mktemp -d /var/tmp/ega-runtime-artifacts.XXXXXXXX)
sudo env SOURCE_REVISION="$(git rev-parse HEAD)" \
  REGISTRY_AUTH_FILE=/path/outside/repository/auth.json \
  ARTIFACT_DIR="$runtime_artifacts" \
  timeout --kill-after=3m 45m bash image/tools/test-runtime.sh
```

Use a new or empty artifact directory for each run. The runner rejects existing
entries before writing output, preserving earlier evidence and preventing old
image IDs or smoke logs from being attributed to a new source revision.

Keep registry auth outside `image/` and `ARTIFACT_DIR`. `BOOTC_BASE` and the six
payload variables above are optional build overrides. The caller supplies one
deadline for the complete run so cancellation reaches the builds and smoke
together. The builds skip layer caching, and the check removes its completed
images, preserving the original failure if cleanup also fails. Cancellation can
leave Buildah working containers; tear down the disposable host after the check.
Pulled base images remain.

`ARTIFACT_DIR` receives `source-revision.txt`, `host-podman.txt` (the host's
cgroup version, rootless mode and Podman version), `appliance-image.id`,
`runtime-image.id`, `appliance-build.log`, `runtime-build.log`, `smoke.log`,
`image-cleanup.log` and `smoke/runtime.txt` (selected container state, unit
status and journal, nested store driver, Podman version and containers, and the
container's boot log). The artifacts contain no registry auth file. The proposed
on-demand `aws-vm-rhel10` Prow job provisions a RHEL VM, transfers a Git archive of
its tested commit and supplies these inputs; the companion configuration lives in
`openshift/release`. The job pins a CentOS Stream 10 `BOOTC_BASE` as an explicit
test substitute.
This check does not qualify a RHEL appliance disk or network e2e topology.
