# FRR metrics details (CORENET-7504)

Evidence behind the [plan](frr-metrics-plan.md)'s claims, with pointers to the PRs that implement
it. The [2026-11-10 version of this file](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md) keeps the full source
evidence that the sections below link to.

## Source baseline and repository boundaries

Merged EGA #6 (2026-10-23) embeds FRR and node-exporter but not
`frr-metrics.service` ([revisions checked](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#source-baseline-and-repository-boundaries)).

The prototype's relay check on EVPN `pfxRcd` maps to #528's per-family accepted-prefix gauge:
FRR uses the same count for summary `pfxRcd` and neighbor `acceptedPrefixCounter`
([FRR source](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#what-the-prototypes-checks-become)).

## Runtime shape of `frr-metrics`

`frr-metrics.service` ([#53](https://github.com/openshift/evpn-gateway-appliance/pull/53)) runs the
pinned `frr-rhel9` image's own `/frr-metrics` as a second container from the embedded FRR image,
serving HTTP on `127.0.0.1:7573` ([4.22 exporter](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#interim-exporter-from-the-embedded-422-image)).
It shares `/var/run/frr` with the FRR container and runs as `frr` with no capabilities, confined
as `container_t`. Both containers run at the fixed MCS level `s0:c700,c701,c702`, and FRR's `:Z`
mounts relabel `/etc/frr` and `/var/run/frr` to it on every start, so the exporter can reach FRR's
configuration and vtysh sockets. Ordinary confined containers get podman's default random
two-category levels, which can never cover these three, so they cannot; a container explicitly given
a covering level, or run unconfined, can. FRR's level in turn covers three of podman's random
pairs, so a container that draws one of them (about 3 in 523,776) is exposed to what FRR's mounts
and host network namespace reach.
It reads FRR through the vtysh sockets, so it can change daemon configuration; CORENET-7704
reviews its privileges and access path.

## Proposed units, ownership and e2e checks

[#53](https://github.com/openshift/evpn-gateway-appliance/pull/53) installs `frr-metrics.service`, and its e2e
covers the switch and an FRR crash, and the unit restarts with FRR. With SELinux enforcing, RHEL
10.3 and CentOS Stream 10 bootc builds with the pinned `frr-rhel9` kept both containers confined
with no AVCs through boots, reboots and an FRR kill, and the CentOS Stream build also through
upgrades from and rollbacks to the previous units.

## Scrape-path evidence

Cluster frr-k8s ServiceMonitors do not discover appliances, so any scrape path needs an explicit
target ([earlier analysis](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#scraping-expectations-dashboards-and-rules);
[options checked](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#scrape-path-evidence)).
