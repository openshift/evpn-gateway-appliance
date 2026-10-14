# EVPN Appliance Bootc Image

Part of [openshift/evpn-gateway-appliance](https://github.com/openshift/evpn-gateway-appliance).

RHEL 10 FRR is the host `frr` package (`frr.service`). It is not a container. node-exporter is the remaining payload image. The FRR version is the Konflux `rpms.lock.yaml` entry, which is not in this tree yet.


## Inventory checks

```bash
python3 image/tools/check-image-inventory.py
# After registry.redhat.io login:
python3 image/tools/resolve-payload-digests.py --write
```

## Local smoke build (optional)

One `Containerfile`. `ARG BOOTC_BASE` defaults to `registry.redhat.io/rhel10/rhel-bootc`.

Release build:

```bash
cd image/rhel10
podman build -t "localhost/evpn-appliance-rhel10:dev" -f Containerfile .
```

CI build. The base is `bootcImageCi` in `streams.yaml`.

```bash
cd image/rhel10
podman build \
  --build-arg BOOTC_BASE=quay.io/centos-bootc/centos-bootc:stream10 \
  -t "localhost/evpn-appliance-rhel10:ci" \
  -f Containerfile .
```

The release build needs pull access to `registry.redhat.io` for the bootc base and for payload digests in `payload-images.env`. The CI build does not, for the base.
