# FRR metrics and observability plan (CORENET-7504)

[CORENET-7504](https://redhat.atlassian.net/browse/CORENET-7504) covers appliance dashboards
and alerts. Refreshed 2026-11-13; [details](frr-metrics-details.md) hold source evidence and
implementation contracts. “Ask N” refers to the numbered asks below.

## Requirements

| 7504 criterion | Delivered by |
| --- | --- |
| 1. Replace the legacy FRR exporter with the frr-k8s metrics binary | Chunk A |
| 2. Expose required EVPN metrics in the frr-k8s metrics binary | frr-k8s #528; chunk E (ES/DF) |
| 3. Appliance, VLAN and tunnel status views | Chunk B |
| 4. BGP sessions, prefix counts and route churn | EGA #44: UPDATE rates as churn |
| 5. VNI and MAC learning behavior | EGA #44: per-VNI MAC history as learning |
| 6. DX, VPN, BFD, latency and bandwidth health | EGA #44 (BFD); chunks B (bandwidth), C (DX, VPN) and D (latency) |
| 7. Alerts for BGP, VTEP, BFD, transport and DF failures | EGA #44 (BGP, BFD, VTEP membership); chunks C (transport), D (VTEP forwarding) and E (DF) |

## Status and next steps

| Work | State |
| --- | --- |
| frr-k8s [#519](https://github.com/metallb/frr-k8s/pull/519): standalone serving | Merged 2026-11-10 (`088e638`) |
| frr-k8s [#528](https://github.com/metallb/frr-k8s/pull/528): per-family prefixes, VNI inventory, L2 and L3 VNI counts, per-collector `frrk8s_scrape_success` | Open; neither it nor #519 is in openshift/frr yet |
| EGA [#44](https://github.com/openshift/evpn-gateway-appliance/pull/44): alerts and dashboard | Open; see [rules and dashboards](#rules-and-dashboards-buildable-now) |

## Exporter options

[Decision 16](kickoff-decisions.md#decisions-at-a-glance): frr-k8s `frr-metrics`, as Jira requires.

## Where metrics are scraped and shown

The deployment's own Prometheus and Grafana; EGA ships rule files and dashboards, not a stack.
The image's node-exporter binds HTTP `127.0.0.1:9100`; chunk A binds `frr-metrics` to
`127.0.0.1:9141` (HTTPS, self-signed certificate). Remote scraping uses CORENET-7704's access path;
[evidence](frr-metrics-details.md#scrape-path-evidence).

## Rules and dashboards buildable now

EGA #44 adds `monitoring/`: six alerts with promtool tests, one Grafana dashboard over
`frrk8s_*` series and `make check-monitoring`.

## Implementation slices

Closing 7504 needs chunks A–E (S: days; M: one to three weeks).

### A. Run frr-metrics instead of the legacy exporter (M)

- Criteria 1–2.
- Build: rewrite `image/rhel10/frr-metrics.service`, install it into the image with
  `COPY` to `/usr/lib/systemd/system/`, and enable it to run
  `podman exec frr /frr-metrics --disable-metrics-auth --metrics-bind-address=127.0.0.1`
  inside the running router container, with `BindsTo=` and `After=frr-container.service`,
  `Restart=always`, and an `ExecStop=` that kills that process, since Podman does not forward stop
  signals to exec sessions ([units](frr-metrics-details.md#proposed-units-ownership-and-e2e-checks)).
  In `evpn_monitoring`, drive this unit from the `frr_exporter` switch, remove
  `tynany/frr_exporter`, mask the unit when disabled and tear down on every group
  ([integration](frr-metrics-details.md#concrete-ega-integration-work)). On non-bootc hosts,
  where the router roles and handlers start `frr` from `frr_image` with Podman directly, install
  the same unit without the `frr-container.service` dependency and require `frr_image` to be the
  same `frr-rhel9` build, since the upstream FRR default lacks `/frr-metrics`.
- Depends: #528 merged in metallb/frr-k8s; #519 and #528 synced into openshift/frr (ask 3) and built
  by ART from a `release-5.x` branch as `openshift5/frr-rhel9`; EGA's `FRR_IMAGE` moving from the
  current `openshift4/frr-rhel9` build to it (CORENET-7505; ask 2); and openshift/release's
  EGA `base_images.metallb-frr`, which e2e passes as `FRR_IMAGE`, moving from `ocp/4.22` to that
  stream, with rehearsal. EGA #29 edits the router unit and handlers; #41 makes `FRR_IMAGE`
  a required build argument.
- Test: `image/tools/smoke-nested.py` requires the unit and every `frrk8s_scrape_success` at 1.
  A new `test/ansible/playbooks/monitoring.yml` in e2e checks expected peers up, EVPN prefix
  counts and VTEP VNI inventory; that stopping the unit while the router runs frees `:9141`; and
  re-enable and teardown, on bootc and non-bootc hosts.

### B. Appliance, VLAN and tunnel views (S)

- Criteria 3 and 6 (bandwidth).
- Build: `monitoring/dashboards/appliance.json` over node-exporter, already in the image: node-exporter
  scrape status, per VXLAN, bridge, VLAN and WireGuard device its operstate and carrier, and
  traffic for the non-bridge devices. Its job
  variable comes from `node_network_info` for `vxlanN` or `wg0` devices and its instances from `up`, as in #44, so a down
  appliance stays selectable; `monitoring/check_dashboards.py` also scopes `node_*` selectors.
- Depends: EGA #44.
- Test: `make check-monitoring`.

### C. Direct Connect and VPN health (S)

- Criteria 6 and 7 (transport).
- Build: `monitoring/dashboards/aws-transport.json` on Grafana's CloudWatch data source: DX
  `ConnectionState` and `VirtualInterfaceBgpStatus`, and VPN `TunnelState` per VPN connection,
  with resource IDs as variables. `monitoring/grafana/aws-transport-alerts.yaml`
  provisions Grafana alerts on a DX connection, virtual interface or VPN tunnel down.
  `monitoring/README.md` says how to set the CloudWatch data source, region and resource IDs.
  `monitoring/check_dashboards.py` skips
  PromQL checks for CloudWatch files and checks each alert's dashboard panel link.
- Depends: EGA #44.
- Test: `make check-monitoring`; both files import into Grafana with a CloudWatch data source
  without errors.

### D. Overlay path probe (S)

- Criteria 6 (latency) and 7 (VTEP forwarding).
- Build: on on-prem appliances with node-exporter, when a probe address is set, an
  `evpn_monitoring` timer pings that overlay address, routed through a stretch's `br-vni` SVI so
  the probe crosses VXLAN (in e2e, the first stretch's cloud gateway that `evpn_health_check` pings). It uses a deadline and writes RTT and success to a textfile
  under `/var/lib/node_exporter/textfile`. In `image/rhel10/node-exporter.service`, mount that
  directory read-only with `:z` so SELinux allows reads, and set `--collector.textfile.directory`;
  do the same for `evpn_monitoring`'s non-bootc node-exporter container. Add an
  RTT panel to B that hides samples older than two probe intervals, using `node_textfile_mtime_seconds`.
  Add `EGAEvpnPathProbeFailed` under `monitoring/rules/`: probe success 0, the textfile older
  than two probe intervals, or a textfile read error on a host that reported the probe, for 5m. The probe address is a new `evpn_monitoring` input.
- Depends: B.
- Test: promtool cases for the alert, including a stale or unreadable textfile; e2e
  sees a positive RTT, takes the stretch's VXLAN device down with BGP up and sees success 0, then
  recovery.

### E. Ethernet segment and DF (M)

- Criteria 2 and 7 (DF).
- Build: in frr-k8s, add an ES collector reading `show evpn es detail json` with the archived
  prototype's parser (`frrk8s_evpn_es_oper_up` and `frrk8s_evpn_es_df` by `esi`) and its own
  `frrk8s_scrape_success{collector="es"}`, so an ES failure cannot silence VNI alerts. In EGA, alert
  when an ESI seen in `frrk8s_evpn_es_oper_up` has not had exactly one DF for longer than the agreed
  allowance, counting a missing role as zero, gated on the `es` collector. Document both series,
  their omission rules and collector `es` in frr-k8s `cmd/metrics/README.md`.
- Depends: #528; an frr-k8s issue agreeing ES/DF scope and an upstream-testable configuration
  (ask 3); 7502's DF allowance (ask 4). Ships as its own frr-k8s PR and reaches EGA by chunk A's
  path: openshift/frr sync, ART build, then an EGA `FRR_IMAGE` update.
- Test: Go tests on the prototype's captured ES states; registry tests that ES read or parse
  failure sets `es` to 0 while VNI series and `evpn` success survive, and that an empty ES list
  succeeds; e2e through the authenticated endpoint on the agreed configuration; promtool,
  including a quiet DF handover and both members down or election-pending.

## Asks and upstream order

1. **PM (decision 1):** review the churn, learning and VTEP meanings in the requirements table.
2. **Decision 10 owner:** approve the `frr-rhel9` payload that chunk A runs.
3. **frr-k8s and openshift/frr maintainers:** merge #528; agree ES/DF scope and its CI configuration; sync #519,
   #528 and chunk E's collector into openshift/frr and the `release-5.x` branch EGA will embed.
4. **7502 owner:** the DF handover allowance.
