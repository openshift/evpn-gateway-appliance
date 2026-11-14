# FRR metrics and observability plan (CORENET-7504)

[CORENET-7504](https://redhat.atlassian.net/browse/CORENET-7504) covers appliance dashboards
and alerts. Review the FRR metrics below, then the exporter and scrape choices.
Refreshed 2026-11-10; [details](frr-metrics-details.md) hold source evidence and implementation contracts.

[Decision 16](kickoff-decisions.md#decisions-at-a-glance) closed 2026-11-10: use frr-k8s's
`frr-metrics`, matching Jira. Decision 10 (payload) and delivery work remain open;
implementation contracts below are proposals.
“Slice N” and “ask N” refer to the tables and numbered asks below.

## Requirements

Are the expected BGP peers and EVPN routes present, and does each stretch have its VNI,
learned entries and remote VTEPs? Dave Tucker's configured collectors and health checks
establish this baseline; his dashboard/HA task list adds churn, BFD and DF views.
The [prototype mapping](frr-metrics-details.md#what-the-prototypes-checks-become) distinguishes
implemented checks, intended collector coverage and planned work.

The reduced [frr-k8s candidate (#528)](https://github.com/metallb/frr-k8s/pull/528) adds
per-family BGP prefix gauges and basic EVPN VNI metrics. Its [metric contract](https://github.com/dfarrell07/frr-k8s/blob/348b6ce29a852c420407a2d0970f8cc2027d381d/cmd/metrics/README.md)
defines names, labels and behavior; this table explains the coverage we care about:

| Metric we care about | Why / prototype basis | Upstream baseline / reduced addition |
| --- | --- | --- |
| BGP session state by peer/VRF | Four checks require expected peers Established | Existing `frrk8s_bgp_session_up`; compare against expected peers |
| FRR-reported accepted and advertised EVPN prefixes by peer/VRF/AFI/SAFI | Relay checks received EVPN prefixes from both sides; advertised counts help diagnose propagation | Existing gauges sum families; add per-family gauges so IPv4 cannot hide missing EVPN routes |
| VNI inventory with type, VRF and interface | Identify each configured stretch; scope the per-VNI checks | New L2/L3 inventory gauge |
| MAC and ARP/ND occupancy per L2 VNI | Preserve the configured L2VPN collector's intended learning view | New L2 gauges; counts, not learn/age event rates |
| Known remote-VTEP count per L2 VNI | Two per-stretch checks require a listed remote endpoint | New L2 count; known endpoints, not reachability |
| BGP UPDATE sent/received counters and session re-establishment evidence | Planned BGP churn row and session-drop alerts | Existing UPDATE/OPEN counters and session state; message activity is a churn proxy; sampled state can miss short flaps |
| Configured BFD session state and down events | Planned BFD/flap alerts; no sessions configured in prototype | Existing series need identity/completeness fixes; require declared expected sessions |
| Local Ethernet-segment operational and DF state | Planned multihoming and DF alerts | Deferred from the reduced candidate; select a source and agree CORENET-7502 HA policy; a DF change can be correct failover |

The candidate adds one default VNI query per scrape; its success gauge covers EVPN only.
Existing BGP/BFD behavior and limitations remain. Zero can be valid for an empty stretch;
compare with declared expectations and check missing series as well as scrape status.
[Source semantics](frr-metrics-details.md#proposed-additive-metrics) explain the limits;
[broader collection health](frr-metrics-details.md#failure-visibility-and-deadlines) is a proposed follow-up.

VNI/MAC/VTEP expectations apply to VTEPs; the relay needs BGP/EVPN prefixes without local VNIs.
Map the prototype's lab workload-VTEP checks to OCP-native EVPN. The [other 7504 areas](pipeline-spec.md#metrics-corenet-74997504) still need
host/interface, AWS and forwarding/latency integration. FRR membership and route counts do not prove forwarding.

Live Jira (2026-11-05) requires legacy-exporter replacement and EVPN metrics **in the frr-k8s
binary**; 7505 names it too. Another source needs amended criteria. Decision 1 still needs
clarification of learning/churn meanings; DF alerts, access and dashboards remain product work.

## Status and next steps

As of 2026-11-10:

| Work | Evidence / state | Next dependency |
| --- | --- | --- |
| Standalone `--disable-metrics-auth` ([#518](https://github.com/metallb/frr-k8s/issues/518), [#519](https://github.com/metallb/frr-k8s/pull/519)) | Open, unmerged; maintainer go-ahead for shared exporter use without divergent behavior/metrics | Upstream review, downstream integration and qualification |
| Reduced frr-k8s candidate, [#528](https://github.com/metallb/frr-k8s/pull/528), [review branch](https://github.com/dfarrell07/frr-k8s/compare/disable-metrics-auth...evpn-metrics-gr-integration) | Per-family prefixes, VNI inventory and L2 counts; full local Go suite, metrics race tests and lint pass at `348b6ce` (same tree as current `92a4bc8`); [CI at `202b2ff`](https://github.com/dfarrell07/frr-k8s/actions/runs/42088338524) finished: 10 jobs passed, IPv4 Helm prefix-count test failed ([details](frr-metrics-details.md#required-evidence-per-slice)) | Upstream review; downstream build and selected FRR/appliance qualification |
| Archived full prototype, [`prototype/evpn-metrics-full`](https://github.com/dfarrell07/frr-k8s/tree/prototype/evpn-metrics-full), `87f63e1` | Broader collectors, BFD identity, ES/DF and serving experiments; [historical validation](frr-metrics-details.md#required-evidence-per-slice) includes `62bead0` | Reference evidence; results do not qualify the reduced candidate |
| Reference exporter prototype, [feature branch](https://github.com/dfarrell07/frr-metrics-exporter/tree/feature/exporter-reference), `f86942d` on fork main | Broader experimental contract; CI passes; [RHEL/runtime evidence and limits](frr-metrics-details.md#required-evidence-per-slice) | Comparison evidence; another shipping source needs amended Jira criteria |
| Image / collection integration | [Proposed units](frr-metrics-details.md#proposed-units-ownership-and-e2e-checks), role migration, teardown and e2e scrape | 7504/7704 boundary; selected payload/access policy; rootful qualification; coordinate with EGA #23 |
| Rules / panels | [`monitoring/`](#rules-and-dashboards-buildable-now): six alerts with promtool tests and a Grafana dashboard over #528, including its per-collector success | Expected inventory (slice 7), interface/host rules, scrape path and dashboard format |

Existing exporter/test defects are being extracted into [focused fixes](frr-metrics-details.md#adjacent-findings-to-handle-separately),
separate from new metrics and access features.

Next: review #519/#528, then qualify the selected Red Hat image and appliance scrape path.
Rules, panels and other product work can proceed separately.

## Exporter options

The [2026-11-03 maintainer reply](https://github.com/metallb/frr-k8s/pull/519#issuecomment-6612226284)
gives the go-ahead for #519 and shared exporter reuse, provided behavior and metrics do not
diverge. The reduced proposal targets basic L2/L3 EVPN configurations that frr-k8s generates;
multihoming/DF and access additions are deferred. Metrics outside those configurations may
belong in a standalone/shared exporter. The [earlier reply](https://github.com/metallb/frr-k8s/pull/519#issuecomment-6578427404)
also suggests `tynany/frr_exporter`. MetalLB metric compatibility motivated frr-k8s's exporter.

**Proposed delivery path:** retain Red Hat-built `frr-metrics`, matching Jira. Keep #519
limited to standalone serving; review the additive collector candidate and seek upstream
agreement. Downstream integration, builds and qualification still
follow; a maintained downstream patch needs a named owner.

The reference exporter and textfile experiments provide comparison evidence. Selecting the Jira
target need not wait for shared-project extraction or implementation/qualification of #519/#528.

| Target / comparison alternative | Benefit | Required work |
| --- | --- | --- |
| Extend frr-k8s | Jira target; shared series and Red Hat build route | Candidate review, collector agreement, downstream delivery and qualification |
| Supplement with EVPN textfiles | Reuses embedded node-exporter and endpoint | Amend 7504; parser/timer ownership, freshness/label contract and endpoint hardening |
| Replace with reference exporter or `tynany/frr_exporter` | Standalone design or existing EVPN collector | Amend 7504/7505; migration/qualification and Red Hat build/update/security ownership |

The [4.22 interim](frr-metrics-details.md#interim-exporter-from-the-embedded-422-image) remains a
development option. [Implementation routes](frr-metrics-details.md#upstream-evidence) stay in details.

### What the 2026-11-02 checks add

Container-lab results (FRR 10.4.3, some 10.6.2; not appliance/FIPS/AWS qualification):
control-plane health survived a VXLAN UDP/4789 forwarding failure; the separate textfile
experiment served metrics over mTLS but needs freshness/job-label checks and protected web
configuration; daemon-specific vtysh reads isolated an unresponsive daemon. Non-root socket
access still needs appliance SELinux qualification. These tests inform the [validation contract](frr-metrics-details.md#required-evidence-per-slice).

## Where metrics are scraped and shown

No path is selected. [Evidence](frr-metrics-details.md#scrape-path-evidence) distinguishes
support precedent from the version/configuration still to qualify. Rule/panel sources can
proceed now; deployment must validate labels, namespace enforcement and query access.

| Option | Fit | Qualification / ownership |
| --- | --- | --- |
| User-workload ServiceMonitor/manual endpoints, Perses, PrometheusRule | Queries with cluster series through Thanos; mTLS API support | Exact EndpointSlice/mTLS recipe and scale under limited external-target guidance; RBAC and transport reachability |
| COO MonitoringStack / ScrapeConfig | Separate customizable stack | Prometheus/Alertmanager ownership; alpha API support; federation/query path for cluster-series joins |
| ACM federation of UWM or COO metrics | Multicluster views, retention, Grafana | ACM/add-on version, metric selection and underlying scrape path |
| Push to COO receiver | Exporter stays on loopback | Appliance agent (decision 10), authenticated receiver and delivery ownership |
| External/customer-run Prometheus and Grafana | Not evaluated | Owned component or sample integration and qualification |

A failed scrape may share the DX/VPN failure being monitored; it is not an independent
“appliance unreachable” measurement.

Questions for OpenShift Monitoring (ask 5):

- (a) Which 4.22+ EndpointSlice/mTLS recipe and scale fit external-target guidance?
- (b) Is user-workload ScrapeConfig/additional-scrape configuration planned?
- (c) Which COO version supports `monitoring.rhobs/v1alpha1` ScrapeConfig?
- (d) Will cluster policy permit rule-namespace exemptions, and what query RBAC is needed?
- (e) Which Perses data source and viewer RBAC should non-admin users use?

## Rules and dashboards buildable now

[`monitoring/`](../../../monitoring/README.md) holds six alert rules, their promtool tests and one
Grafana dashboard over #528's series, including `frrk8s_scrape_success{collector}`. They key on
scrape `job`/`instance` only; collector failure raises its own alert;
tests cover explicit zero versus absent data, missing status and cross-target isolation.
The dashboard renders in Grafana 11.6.0 against collector output from captured FRR JSON.

Not covered yet: vanished peers/VNIs/collectors and source collisions need the
[slice 7 identity/capability contract](frr-metrics-details.md#scraping-expectations-dashboards-and-rules);
target down is left to platform `up` alerting. The
[earlier drafts](https://github.com/dfarrell07/evpn-gateway-appliance/tree/corenet-7504-monitoring-drafts/monitoring)
hold inventory and interface rules to revisit then (fix `errs_total`/`drop_total` names first).
DF/ES, transport and forwarding-probe rules remain work.

## Implementation slices

These proposed work groups separate #528 (slices 3–4), focused collection fixes and product
integration. Jira defines acceptance. [Evidence per slice](frr-metrics-details.md#required-evidence-per-slice).

| Slice | Where | Change |
| --- | --- | --- |
| 1. Standalone serving | frr-k8s | Explicit auth selection, unchanged Kubernetes TLS/auth defaults, documentation |
| 2. Reliable collection | frr-k8s, separate fixes | Known BFD identity, failure visibility and vtysh issues remain; no generic collection/serving framework in #528 |
| 3. EVPN prefixes | frr-k8s | Per-family gauges preserving aggregates |
| 4. L2 VNI/MAC | frr-k8s | Default VNI collector, L2 counts and EVPN-only success |
| 5. Local ES/DF and VTEP membership | Product source open | DF needs a source and HA alert policy with 7502; individual-member observations are optional. Deferred from #528 |
| 6. Red Hat delivery | openshift/frr | Downstream source, selected toolchain, qualified image |
| 7. Appliance and collection | EGA, 7504/7704 | Runtime/role migration, persistent disable/teardown, access/scraping and expected inventory lifecycle |
| 8. Complete 7504 | EGA | Packaged dashboards/rules and chosen AWS/probe integration |

## Asks and upstream order

Responsibilities remain proposed; route these through the 7504 assignee:

1. **7504 owner:** agree remaining metric meanings and DF/ES sourcing for the selected exporter.
   Interim runtime belongs to decision 10.
2. **Epic/7704 owners:** agree 7504 replacement versus 7704 privilege/access work and tests.
   Keep migration/teardown in 7504 unless reassigned; propose separately deliverable BGP/BFD,
   EVPN/DF and AWS/latency work.
3. **PM:** dashboard format; decision 1 clarification; BFD and AWS/latency owners. 7502 covers multihoming BFD only.
4. **Product Security:** loopback/interim payload support, SBOM/FIPS/update ownership, vtysh control, access and label visibility.
5. **OpenShift Monitoring:** the five questions above.
6. **Decision 10 owner:** selected payload and build/update ownership.
7. **openshift/frr owners:** target branches and integration/build path.
8. **frr-k8s maintainers:** keep #519 isolated; agree basic EVPN/CI scope and discuss ES/DF separately.
9. **Network/security:** scrape path, certificates/keys/rotation, AWS access and latency/probe source; reuse 7501 preflight work.
