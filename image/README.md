# EVPN Appliance Bootc Image

Part of [openshift/evpn-gateway-appliance](https://github.com/openshift/evpn-gateway-appliance).

The image embeds FRR and node-exporter. It does not install the frr RPM.

## Local smoke build (optional)

One `Containerfile`. `ARG BOOTC_BASE` defaults to `registry.redhat.io/rhel10/rhel-bootc`.
`FRR_IMAGE` and `NODE_EXPORTER_IMAGE` have no default. Pass pinned payload pullspecs, or let
the Konflux Component replace them with downstream digests through
`content.source.modifications`. A build with neither fails before pulling anything.

Release build, from the repository root. Auth defaults to `$HOME/.docker/config.json`.

```bash
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> make appliance-image
```

CI build. The base is `bootcImageCi` in `streams.yaml`.

```bash
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> make appliance-image \
  APPLIANCE_TAG=localhost/evpn-appliance-rhel10:ci \
  BOOTC_BASE=quay.io/centos-bootc/centos-bootc:stream10
```

The release build pulls the RHEL bootc base and both payload images from `registry.redhat.io`. The CentOS base still pulls both payload images from `registry.redhat.io`.

From the repository root, `make nested-ci-appliance-image` builds `localhost/evpn-appliance-rhel10:ci` with the CentOS base, then layers the vfs drop-in on that tag.

```bash
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> make nested-ci-appliance-image
```

The child image copies `storage.conf` to `/etc/containers/storage.conf.d/99-evpn-vfs.conf` so nested Podman uses vfs. The appliance image does not contain that file. The smoke does not mount it.

These are two programs. They both ask whether the embedded FRR and node-exporter images run. They start those images in different places, so they do not share a runner.

On a machine that can boot systemd inside Podman, build the vfs child and run the boot smoke.

```bash
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> make nested-ci-appliance-image
python3 image/tools/smoke-nested.py localhost/evpn-appliance-rhel10:nested-ci
```

Success is this line.

```text
nested offline smoke passed for localhost/evpn-appliance-rhel10:nested-ci (this does not qualify bootc install, upgrade, rollback, or VM boot)
```

In nested Podman CI, systemd cannot mount sysfs. Build the appliance tag and run the payload smoke. Set `ARTIFACT_DIR` to a writable directory. That script does not use the vfs child.

```bash
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> make ci-appliance-image
ARTIFACT_DIR=/tmp/ega-artifacts python3 image/tools/smoke-payloads.py localhost/evpn-appliance-rhel10:ci
```

Success is this line.

```text
rootless payload smoke passed for localhost/evpn-appliance-rhel10:ci
```
