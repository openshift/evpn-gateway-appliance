# FRR and EVPN monitoring

`rules/frr-alerts.yaml` contains six Prometheus alerts; `rules/frr-alerts_test.yaml`
tests them. Import `dashboards/frr-evpn.json` into Grafana (rendered with 11.6.0) and
select a Prometheus data source, jobs and instances.

Any Prometheus scraping frr-k8s `frr-metrics` can supply the data. This package
requires the per-family BGP, EVPN and per-collector `frrk8s_scrape_success`
(`bgp`, `bfd`, `evpn`) metrics from frr-k8s #528. Older exporters
do not supply the full contract. Configure scraping separately; preserve the
scrape-added `job` and `instance` labels as target identity, unique within the
query domain. There is no required job name. Load the rules through Prometheus's
`rule_files` configuration.

| Alert | Reads | Silent when |
| --- | --- | --- |
| EGAFrrCollectorFailed | Collector success = 0 for 10m | Success = 1 or status absent |
| EGAFrrMetricsGatherErrors | Registry gather/encode errors increasing over 10m for 10m on an FRR target | Flat counter, counter absent, or collector status absent |
| EGABgpSessionDown | BGP session = 0 for 5m | Up or absent |
| EGABgpEvpnNoPrefixesAccepted | EVPN-family accepted count = 0 with session up for 15m | Nonzero, absent, or session not up |
| EGAEvpnVniNoRemoteVteps | L2 remote-VTEP count = 0 for 15m | Nonzero or absent |
| EGABfdSessionDown | BFD session = 0 for 2m | Up or absent |

Absent collector status does not establish collection health. BFD can report sessions
while counter reads fail, so `EGABfdSessionDown` still fires for a down session after 2m.
BGP administrative shutdown also reads 0; zero prefixes or VTEPs can be intentional.
BFD peer/VRF identities can collide.
Prefix and MAC/ARP-ND counts are gauges of occupancy; known VTEPs do not prove
reachability. UPDATE rates measure messages, not individual route changes.
The VNI table shows L2 and L3 counts in separate columns, keeping missing counts blank.

Absent or vanished objects and collectors go undetected: that needs an expected
inventory, which this package does not have. Target down is left
to the platform's TargetDown/`up` alerting. DF/ES, transport and latency have no
source in this package. These signals do not establish forwarding health.

Run `make check-monitoring` from the repository root.
Host runs (`USE_IMAGE=0`) need promtool (tested with 3.5.0) on PATH.
