# FRR metrics and observability plan (CORENET-7504)

[CORENET-7504](https://redhat.atlassian.net/browse/CORENET-7504) covers appliance dashboards
and alerts. Refreshed 2026-11-20; [details](frr-metrics-details.md) hold source evidence.

## Requirements

| 7504 criterion | Delivered by |
| --- | --- |
| 1. Replace the legacy FRR exporter with the frr-k8s metrics binary | Chunk A (EGA #53, open) |
| 2. Expose required EVPN metrics in the frr-k8s metrics binary | frr-k8s #528 (open); ES/DF series: CORENET-7502 (chunk E, proposed) |
| 3. Appliance, VLAN and tunnel status views | Chunk B (interfaces); chunk C (AWS VPN tunnel state). Appliance-side per-tunnel IPsec status, proposed to stay in 7504 ([decision 16](kickoff-decisions.md#gate-c-stage--trial-publication)), is unassigned: no chunk delivers it yet, because #44's appliance dashboard filters devices to `vxlan`, `br-vni`, `trunk` and `wg0` names, which miss the `ipsecN` devices CORENET-7500 ([#52](https://github.com/openshift/evpn-gateway-appliance/pull/52), open) adds, and no per-tunnel status source is selected |
| 4. BGP sessions, prefix counts and route churn | #528 (per-family prefixes) and EGA #44 (sessions, prefixes, churn), both open |
| 5. VNI and MAC learning behavior | #528 (VNI series) and EGA #44 (learning), both open |
| 6. DX, VPN, BFD, latency and bandwidth health | EGA #44 (BFD, open); chunks B (interface bandwidth), C (DX and VPN state and throughput) and D (latency) |
| 7. Alerts for BGP, VTEP, BFD and transport failures | EGA #44 (BGP, BFD, VTEP membership, open); chunks C (transport) and D (VTEP forwarding); DF: CORENET-7502 (chunk E, proposed) |

[Decision 1](kickoff-decisions.md#start-now-without-waiting-for-engineering) has a proposal (2026-11-17, approval pending) defining
route churn (row 4) and MAC learning (row 5); #44's FRR dashboard plots both, and neither has an alert.

## Status and next steps

| Work | Where |
| --- | --- |
| Standalone serving (`--disable-metrics-auth`) | frr-k8s [#519](https://github.com/metallb/frr-k8s/pull/519), merged 2026-11-10 (`088e638`) |
| Per-family prefixes, VNI inventory, L2 and L3 VNI counts, per-collector `frrk8s_scrape_success` | frr-k8s [#528](https://github.com/metallb/frr-k8s/pull/528) (open) |
| frr-metrics on the appliance | EGA [#53](https://github.com/openshift/evpn-gateway-appliance/pull/53) (open): the pinned `frr-rhel9` image's own exporter; #528's series need an image that carries it |

## Exporter choice

[Decision 16](kickoff-decisions.md#decisions-at-a-glance): frr-k8s `frr-metrics`, as Jira requires.

## Where metrics are scraped and shown

Proposed, not decided: the deployment's own Prometheus and Grafana, with EGA shipping rule files
and dashboards but no monitoring stack. Packaging and publishing them is CORENET-7522's. OpenShift user-workload monitoring, the Cluster
Observability Operator, ACM or a push path remain open until [ask 3](#asks-and-upstream-order) is answered. The image's
node-exporter binds HTTP `127.0.0.1:9100`; with #53 (open), `frr-metrics` will bind HTTP `127.0.0.1:7573` from the pinned 4.22 image, and an image carrying #519 serves HTTPS instead. Remote scraping needs an access path, which CORENET-7704 owns;
[evidence](frr-metrics-details.md#scrape-path-evidence).

## Rules and dashboards

EGA #44 (open) adds `monitoring/`: FRR alerts with promtool tests, an FRR dashboard over `frrk8s_*`
series, chunks B and C, a runbook for each alert and `make check-monitoring`; #48 (open) adds chunk D
and its runbooks. Alerts on `frrk8s_*` signals shared with BGP Cloud Connector's
[`rules-frrk8s.yaml`](https://github.com/openshift/bgp-cloud-connector/blob/8e0b01bc3b0773970b5717d8b85df047f6002de3/config/prometheus/rules-frrk8s.yaml)
keep its severity and hold time; #44's `monitoring/README.md` covers the differences.

## Implementation chunks

Closing 7504 needs chunks A–D and the unassigned IPsec status part of criterion 3; E is proposed to move to CORENET-7502 (S: days; M: one to three weeks).

### A. Run frr-metrics instead of the legacy exporter (S)

- Build: EGA #53 (open) will run the pinned FRR image's `frr-metrics` as `frr-metrics.service`;
  `evpn_monitoring` drives it from the `frr_exporter` switch and removes `tynany/frr_exporter`.
- Depends: #528's series need a pinned `frr-rhel9` whose `frr-metrics` carries #519 and #528.
  That downstream build belongs to CORENET-7505/7506 under decision 10 (Networking / PM /
  Product Security; accountable owner pending). An exporter carrying #519 always serves HTTPS,
  with a self-signed certificate unless given one, and binds `0.0.0.0` by default;
  `--disable-metrics-auth` only removes the Kubernetes authentication. Moving to that image
  needs the flag in the unit, and the health check and scrape must move to `https://` with a
  decision on a CA or skipping verification.

### B. Appliance, VLAN and tunnel views (S)

`monitoring/dashboards/appliance.json` over node-exporter, already in the image; EGA
[#44](https://github.com/openshift/evpn-gateway-appliance/pull/44) (open).

### C. Direct Connect and VPN health (S)

`monitoring/dashboards/aws-transport.json` and Grafana-managed alerts on CloudWatch DX and VPN
state; EGA #44 (open).

### D. Overlay path probe (S)

An opt-in `evpn_monitoring` probe of one overlay path, its two alerts and an RTT panel; EGA
[#48](https://github.com/openshift/evpn-gateway-appliance/pull/48) (open), stacked on #44.

### E. Ethernet segment and DF (M)

Proposed to move to CORENET-7502 ([decision 16](kickoff-decisions.md#gate-c-stage--trial-publication), 2026-11-17, approval pending), which delivers EVPN multihoming
([networking spec](networking-spec.md) item 6): without Ethernet segments a DF alert has no data.
The hand-off branches [`evpn-es-metrics`](https://github.com/dfarrell07/frr-k8s/tree/fba99aa22caa8d4b8c7d4feb803b110fc09823a1) (frr-k8s) and [`corenet-7504-evpn-df`](https://github.com/dfarrell07/evpn-gateway-appliance/tree/9d88b8f9aee70317f325c630d77965877420fcf6) (EGA) hold the frr-k8s ES collector
(series and omission rules in its `cmd/metrics/README.md`), the DF alert and their tests; 7502
sets the DF handover allowance.

## Asks and upstream order

1. **Decision 10 owner:** approve running the `frr-rhel9` image's `frr-metrics` beside the
   embedded FRR for chunk A ([runtime shape](frr-metrics-details.md#runtime-shape-of-frr-metrics)).
   #53 (open) runs it with `label=disable`, which leaves the container unconfined (`spc_t`) and reverses
   the earlier plan's "never `label=disable`"; CORENET-7704 reviews that.
2. **frr-k8s maintainers:** merge #528.
3. **OpenShift Monitoring:** whether appliance metrics should feed user-workload monitoring, the
   Cluster Observability Operator or ACM rather than the deployment's own Prometheus, and what
   scrape configuration and RBAC that needs ([earlier questions](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-plan.md#where-metrics-are-scraped-and-shown)).
