# FRR metrics details (CORENET-7504)

Build contracts for [chunks A–E](frr-metrics-plan.md#implementation-slices).

## Source baseline and repository boundaries

Merged EGA #6 embeds FRR and node-exporter; `frr-metrics.service` is not installed.

Delivery path: chunk A's dependencies in the [plan](frr-metrics-plan.md#a-run-frr-metrics-instead-of-the-legacy-exporter-m).

## Existing series

Series names, labels and semantics are defined by #528's [metrics README](https://github.com/metallb/frr-k8s/blob/9a69b6467f0082ffc3ddc0c3d2623f06e11d5b38/cmd/metrics/README.md)
and EGA #44's `monitoring/README.md`.

Chunk E ports the ES parser from the [archived prototype](https://github.com/dfarrell07/frr-k8s/tree/87f63e17f5d234c03f1b9ddd721f0960b50d1f37/cmd/metrics).
It always reports `frrk8s_evpn_es_oper_up` for a local segment, but `frrk8s_evpn_es_df` only for
ready, operational, non-bypassed segments with no election pending.

## Legacy migration contract

See [chunk A](frr-metrics-plan.md#a-run-frr-metrics-instead-of-the-legacy-exporter-m) and [Existing series](#existing-series).

## What the prototype's checks become

The prototype's relay check on EVPN `pfxRcd` maps to #528's per-family accepted-prefix gauge:
FRR uses the same count for summary `pfxRcd` and neighbor `acceptedPrefixCounter`.

## Runtime shape if `frr-metrics` is chosen

`frr:embedded` ships `/frr-metrics`, and the router container already mounts the FRR sockets
and vtysh configuration it needs, so `podman exec` adds no mounts, labels or users. Host
networking lets it bind host loopback. Its privileges follow the router container's, which
CORENET-7704 owns.

## Interim exporter from the embedded 4.22 image

The embedded 4.22 `/frr-metrics` lacks #528's series, so chunk A needs the updated image.

## Concrete EGA integration work

- The current `frr-metrics.service` expects a host binary that does not exist.
  `evpn_monitoring` starts `frr-exporter.service` if present, otherwise the `frr_exporter`
  Podman container; remove both, stopping the owning service before removing the container so
  its restart policy cannot recreate it.
- Baseline teardown removes exporters only on-prem; cover every production group.
- Router handlers fall back to `frr_image`, which may differ from `frr:embedded`; test
  configuration-triggered router restarts.

## Proposed units, ownership and e2e checks

- Link `frr-container.service.wants/frr-metrics.service` in the image.
- Mask the vendor `/usr/lib` unit when disabled; a regular legacy unit in `/etc` can block
  masking and must be removed first.
- Beyond chunk A's e2e checks, test router restart, crash and reboot on RHEL 10 with SELinux
  enforcing.

## Scrape-path evidence

Cluster frr-k8s ServiceMonitors do not discover appliances.
