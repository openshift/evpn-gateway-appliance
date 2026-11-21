# EGA monitoring

Prometheus alert rules, their tests, Grafana dashboards and Grafana-managed alerts for EVPN gateway
appliances. EGA ships these files for the deployment's own Prometheus and Grafana; it does not deploy either.
The dashboards were import-tested, and the Grafana alerts provisioning-tested, with Grafana 11.6.0.

## FRR and EVPN

- `rules/frr-alerts.yaml`: ten alerts, tested by `tests/frr-alerts_test.yaml` and, for the BFD
  hold time at 15s evaluation, `tests/frr-alerts-15s_test.yaml`.
- `dashboards/frr-evpn.json`: health, BGP, EVPN and BFD rows.

The data comes from frr-k8s `frr-metrics`, the FRR metrics exporter, with the per-family BGP,
EVPN and per-collector `frrk8s_scrape_success` (`bgp`, `bfd`, `evpn`) series that
metallb/frr-k8s#528 adds. `frrk8s-metrics.txt` lists the series as of #528 at `5a41233`;
`make check-monitoring` fails if a rule or panel names any other `frrk8s_*` series. On appliances,
the image's `frr-metrics.service` runs the embedded FRR image's `frr-metrics`, which serves
`http://127.0.0.1:7573/metrics`, unauthenticated and loopback only until CORENET-7704 provides
remote access; `monitoring.frr_exporter` controls it
(see the [role](../ansible/roles/evpn_monitoring/README.md)). The FRR dashboard's per-family, EVPN
and collector panels and the collector, metrics-down, gather-error, EVPN prefix and remote-VTEP
alerts stay empty or inactive until the pinned FRR image's `frr-metrics` includes metallb/frr-k8s#528.

These are appliance-side FRR signals, meant for the appliances' frr-metrics; the rules carry no
target scoping (see below). They do not replace OVN-Kubernetes control-plane health on the
cluster: `ovnkube_clustermanager_cluster_user_defined_network_condition`,
`ovnkube_clustermanager_route_advertisement_condition` and `ovnkube_clustermanager_vtep_condition`
(labels `name`, `condition`, `status`;
[`cluster_manager.go`](https://github.com/ovn-kubernetes/ovn-kubernetes/blob/c4deeb85a03f955099f745d9fefbf7d74412f9f5/go-controller/pkg/metrics/cluster_manager.go)). The last two need OVN-Kubernetes's
EnableRouteAdvertisements and EnableEVPN; check your OpenShift release.

BGP Cloud Connector ships alerts on the same `frrk8s_*` series for the cluster's frr-k8s
([`rules-frrk8s.yaml`](https://github.com/openshift/bgp-cloud-connector/blob/main/config/prometheus/rules-frrk8s.yaml)).
Each of its six alerts has an EGA counterpart with the same expression, severity and hold time
(the table below), except that the two prefix alerts read the `l2vpn/evpn` family, so IPv4
routes cannot hide missing EVPN routes on a session that negotiated it; a session that does not
activate the family has no series, so they stay silent (see the table), and that EGA's collector, session,
prefix and VTEP alerts read each series' last value within 4m (`last_over_time`). Names start with `EGA` to show where
an alert comes from when both sets are loaded, use `Bgp`/`Bfd` casing and add `Evpn` to the
prefix alerts, whose `NoPrefixesAccepted` reflects FRR's accepted, post-policy count. EGA adds the collector,
gather-error and remote-VTEP alerts. Like BGP Cloud Connector's, every alert carries
`netobserv: "true"` and a `netobserv_io_network_health: '{}'` annotation, so NetObserv's Network
Health shows them under Global. NetObserv reads rules only through its FlowCollector's
`spec.prometheus.querier`, so load them where that querier sees them, in a Prometheus that
scrapes the appliances but not the cluster's frr-k8s (see below).

Both sets match every `frrk8s_*` target their Prometheus scrapes, so with both loaded where the
cluster's frr-k8s and the appliances are scraped together, each problem alerts twice. Evaluate
them in separate Prometheus instances. Only these rules can be scoped with a `job` matcher on
every selector; BGP Cloud Connector's ship in its bundle, and scoping only one set still alerts
twice.

To use them:

1. Scrape `frr-metrics`. Any job name works; keep the scrape-added `job` and `instance` labels
   unique per exporter within the Prometheus that evaluates the rules.
2. Add `rules/frr-alerts.yaml` to Prometheus's `rule_files`. Do not load `tests/`. With the
   Prometheus Operator or OpenShift monitoring, put its `groups` under a `PrometheusRule`'s
   `spec.groups`.
3. Import `dashboards/frr-evpn.json` and select the Prometheus data source, jobs and instances.

| Alert | Severity | Fires when | Silent when |
| --- | --- | --- | --- |
| EGAFrrCollectorFailed | critical | Collector success is 0 for 2m | Success is 1, or status absent for 4m |
| EGAFrrMetricsDown | critical | A target that reported FRR collector status in the last day fails its scrapes for 2m | Scraped, or no status in the last day |
| EGAFrrMetricsGatherErrors | warning | Registry gather errors keep increasing, at least one in each 10m window, for 10m on an FRR target | Counter flat or absent, or collector status absent for 4m |
| EGABgpSessionDown | critical | A BGP session is not Established for 1m | Up, or absent for 4m |
| EGABgpEvpnNoPrefixesAccepted | warning | An Established peer accepts zero l2vpn/evpn prefixes for 5m | Nonzero, absent for 4m, or session not up |
| EGABgpEvpnNoPrefixesAnnounced | warning | An Established peer is sent zero l2vpn/evpn prefixes for 5m | Nonzero, absent for 4m, or session not up |
| EGABgpPeerFlapping | warning | 3 or more OPENs sent to a peer in 15m, for 5m | Fewer, or counter absent |
| EGAEvpnVniNoRemoteVteps | warning | An L2 VNI has zero remote VTEPs for 15m | Nonzero, or absent for 4m |
| EGABfdSessionDown | critical | A BFD session is down for 30s | Up, or absent for 4m |
| EGABfdPeerFlapping | warning | 3 or more BFD down events for a peer in 15m, for 5m | Fewer, or counter absent |

The base appliance configuration has no BFD peers, so there its BFD panels stay empty and the
BFD alerts stay quiet. A failed collector emits none of its series, so its other alerts cannot
fire; EGAFrrCollectorFailed is critical for that reason. Because those alerts read each series'
last value within 4m, a failed scrape or collector neither resets a hold nor clears a firing
alert, and a down session keeps firing until EGAFrrCollectorFailed or EGAFrrMetricsDown does.
BFD reports sessions even when its counter read fails, so `EGABfdSessionDown` still fires for a
down session after 30s. Prefix and MAC or ARP/ND counts are gauges of occupancy. The dashboard
shows route churn as each peer's BGP UPDATE message rate, which counts messages, not individual
route changes, and MAC learning as each VNI's MAC and ARP/ND count over time. Panels that count
events per interval (`x - x offset $__interval`) count each event once only when the Grafana
data source's scrape interval is a whole number of one unit, such as `15s` or `1m`.

These alerts do not detect:

- objects or collectors that vanish, which needs an expected inventory this package does not
  have;
- a single flap shorter than an alert's `for:` time, which may be missed or look continuous
  between scrapes; the flapping alerts and the dashboard's OPEN and BFD down-event panels catch
  repeated ones;
- a target that never reported FRR collector status, or none in the last day;
- Ethernet-segment designated-forwarder state;
- WireGuard peer liveness: node-exporter has no WireGuard collector, and `wg0` carrier does
  not show it; BGP to the relay and the opt-in probe give indirect evidence;
- path latency beyond the opt-in probe's RTT to one overlay target, which no alert reads; AWS
  publishes no DX or VPN latency metric.

## Appliance, VLANs and tunnels

`dashboards/appliance.json` shows node-exporter scrape status; the operstate, carrier and
carrier changes of the `vxlanN`, `br-vniN`, `trunk-br`, `trunk.N` and `wg0` devices; the
traffic, drops and errors of the non-bridge ones; and overlay path probe RTT.

The data comes from node-exporter. The bootc image runs it on `127.0.0.1:9100`, so scraping it
from another host needs the access path from CORENET-7704. On other hosts `evpn_monitoring`
runs it in a container without a listen address, so it listens on every interface (see the
[collection's known limitations](../ansible/README.md#known-limitations-tracked-not-all-fixed-here)).

To use it:

1. Scrape node-exporter with any job name. The dashboard lists the jobs and instances that
   report a `vxlanN` or `wg0` device, so it does not list an appliance with no stretch and no
   tunnel, or a target that was down for the whole time range.
2. Import `dashboards/appliance.json` and select the Prometheus data source, jobs and
   instances.

The carrier-changes panel counts per interval, as described under FRR and EVPN. VXLAN, WireGuard
and `br-vniN` devices report carrier whenever they are administratively up, so
their carrier does not show path loss; trunk loss shows on `trunk-br` and `trunk.N`. Traffic
leaves out the bridges: `br-vniN` counters miss bridged frames, and `trunk.N` already counts
the stretch traffic that `trunk-br` delivers.

## AWS transport

- `dashboards/aws-transport.json`: Direct Connect connection state, virtual-interface BGP
  status, VPN tunnel state, and Direct Connect and per-tunnel VPN throughput in bits/s
  (directions from AWS's perspective), from CloudWatch.
- `grafana/aws-transport-alerts.yaml`: three Grafana-managed alerts, one per state panel.

A Direct Connect connection can end on a customer router and a VPN backup can keep EVPN BGP up,
so FRR metrics cannot see these failures.

To use them:

1. Add a CloudWatch data source whose credentials allow `cloudwatch:GetMetricData`,
   `cloudwatch:ListMetrics` and `ec2:DescribeRegions`.
2. Import `dashboards/aws-transport.json` and select the data source, region and resource IDs.
   Keep its UID: the alerts link to its panels.
3. In `grafana/aws-transport-alerts.yaml`, set each `datasourceUid: cloudwatch` to the data
   source's UID, or provision the data source with `uid: cloudwatch`. Set each rule's
   `region: default` to the region where CloudWatch publishes that metric: Direct Connect
   metrics go to the connection's home region and VPN metrics to the VPN's region, which can
   differ. Each rule covers every connection, virtual interface or VPN in its region; replace a
   `['*']` with a list of IDs to limit it.
4. Copy the file to Grafana's `provisioning/alerting` directory and restart Grafana.

| Alert | Severity | Fires when | Silent when |
| --- | --- | --- | --- |
| EGADxConnectionDown | warning | A connection's minimum state is 0 in each 5-minute period for 10m | Up |
| EGADxVirtualInterfaceBgpDown | warning | A virtual interface's minimum BGP status is 0 in each 5-minute period for 10m | Up |
| EGAVpnTunnelDown | warning | A VPN's minimum tunnel state is below 1 (a tunnel down) in each 5-minute period for 10m | All tunnels up |

The rules read 5-minute periods every 5 minutes and wait `for: 10m`, so an alert fires about
15 to 20 minutes after a failure. A VPN that uses only one of its two tunnels keeps
`EGAVpnTunnelDown` firing; to alert only when every tunnel is down, change that rule's
`statistic: Minimum` to `Maximum` and `$B < 1` to `$B == 0` in the deployed copy; change panel
3's statistic too to show the same condition.

The rules keep their last state when the whole query returns no data, because Grafana 11.6
reports a failed CloudWatch read, such as expired credentials, as no data; watch the data source
separately. So a region without these resources stays quiet. When one resource stops reporting
while others still do, Grafana resolves its alert after two evaluations; when none reports any
more, an alert keeps its last state until the rule is paused or deleted in the provisioning file
and Grafana reloads it.

## Overlay path probe

BGP and EVPN membership can stay up while VXLAN forwarding fails. On an
`onprem_appliances` host with `monitoring.node_exporter` on, setting
`evpn_monitoring_path_probe_target` to a stretch's `cloud_gateway` makes
`evpn_monitoring` install a timer that pings it every 30s and writes the result through
node-exporter's textfile collector. A probe fails unless 3 echo replies arrive within 5s (up to 5 requests). It samples one overlay
path and does not identify the failed component: it tests the path from the appliance to the
cloud VTEP's bridge, not the on-prem trunk, tenant workloads or other stretches. Its pings are
default-size, so a path that drops only large packets (an MTU black hole) passes. Something on the
cloud side must hold the stretch's `cloud_gateway` and answer ICMP echo, as the lab's cloud VTEP
bridge does; a missing or filtering target fails the probe with the path healthy.
The appliance dashboard's RTT panel shows fresh samples.

The probe is opt-in. It complements OVN-Kubernetes's cluster conditions and NetObserv's drop
and latency rules and replaces none of them, so one incident can fire several alerts. Both
alerts carry the FRR alerts' `netobserv: "true"` label.

- `rules/path-probe-alerts.yaml`: two alerts, tested by `tests/path-probe-alerts_test.yaml`. Add
  it to `rule_files` with the FRR rules.

| Alert | Severity | Fires when | Silent when |
| --- | --- | --- | --- |
| EGAEvpnPathProbeFailed | warning | Over a quarter of the probe results that were fresh when scraped in the last 5m failed, for 3m | Three quarters succeed, or no fresh result in the last 5m |
| EGAEvpnPathProbeUnavailable | warning | For 5m: the probe file is older than 60s, or over 60s ahead after a clock step back; or, on a host that reported the probe in the last day and was not disabled by the role, the probe series is gone while node-exporter is scraped | A fresh probe file; node-exporter not scraped; the probe removed by the role; or no probe series in the last day |

The image's node-exporter must read `/var/lib/node_exporter/textfile`
(`--collector.textfile.directory`); the role fails otherwise, or when the probe fails locally.
Missing echo replies record `ega_path_probe_success 0` and do not fail the role.

A deploy without a target (including after clearing it), turning off `monitoring.node_exporter` or
running `teardown.yml` removes any probe and, if the textfile directory exists, writes
`ega_path_probe_disabled 1` there, which keeps `EGAEvpnPathProbeUnavailable` quiet on that host.

## Runbooks

Every alert's `runbook_url` links to its section of [runbooks.md](runbooks.md), which says what the
alert means, what to check on the appliance or in AWS, and what to do.

## Checks

Run `make check-monitoring` from the repository root for promtool rule lint and tests,
dashboard panel and variable PromQL compilation, frr-k8s metric-name checks, Grafana alert-rule
and runbook-link checks, and unit tests for the checker and the overlay probe script. Host runs
(`USE_IMAGE=0`) need `promtool` 3.5.0 on PATH and PyYAML.
