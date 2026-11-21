# FRR metrics details (CORENET-7504)

Evidence behind the [plan](frr-metrics-plan.md)'s claims, with pointers to the PRs that implement
it. The [2026-11-10 version of this file](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md) keeps the full source
evidence that the sections below link to.

## Source baseline and repository boundaries

Merged EGA #6 (2026-10-23) embeds FRR and node-exporter; `frr-metrics.service` is
not installed ([revisions checked](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#source-baseline-and-repository-boundaries)).

## What the prototype's checks become

The prototype's relay check on EVPN `pfxRcd` maps to #528's per-family accepted-prefix gauge:
FRR uses the same count for summary `pfxRcd` and neighbor `acceptedPrefixCounter`
([FRR source](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#what-the-prototypes-checks-become)).

## Runtime shape of `frr-metrics`

`frr-metrics.service` ([#53](https://github.com/openshift/evpn-gateway-appliance/pull/53), open) runs the
pinned `frr-rhel9` image's own `/frr-metrics` as a second container from the embedded FRR image,
serving HTTP on `127.0.0.1:7573` ([4.22 exporter](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#interim-exporter-from-the-embedded-422-image)).
It shares `/var/run/frr` with the FRR container and runs as `frr` with no capabilities and
SELinux labeling disabled (`label=disable`, so the container runs unconfined as `spc_t`), since FRR's `:Z` mount relabels the socket directory on every start.
It reads FRR through the vtysh sockets, so it can change daemon configuration; CORENET-7704
reviews its privileges and access path. #528's series arrive with a pinned `frr-rhel9` whose
`frr-metrics` carries #519 and #528.

## Proposed units, ownership and e2e checks

[#53](https://github.com/openshift/evpn-gateway-appliance/pull/53) adds `frr-metrics.service` and its e2e
covers the switch and an FRR crash. The unit restarts with FRR; FRR restarts and crashes were tested on
systemd with SELinux enforcing outside the image, and a reboot of the RHEL 10 image is not yet tested.

## Scrape-path evidence

Cluster frr-k8s ServiceMonitors do not discover appliances, so any scrape path needs an explicit
target ([earlier analysis](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#scraping-expectations-dashboards-and-rules);
[options checked](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#scrape-path-evidence)).
