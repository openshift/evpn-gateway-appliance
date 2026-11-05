# FRR metrics details (CORENET-7504)

Evidence and implementation contracts for the [plan](frr-metrics-plan.md). “Slice N” and
“ask N” refer there; decisions remain proposals until their owners approve.

## Source baseline and repository boundaries

Inspected source revisions; these pins alone establish neither builds nor deployment. Undated observations are
from 2026-10-22. The prototype was read from the pinned local checkout; this is not a
claim about its current remote head.

| Repository / revision | What it contains and why it matters |
| --- | --- |
| [`metallb/frr-k8s`, `0d3197bb`](https://github.com/metallb/frr-k8s/tree/0d3197bbe0090b88b4a106c222cc8c5118168138/cmd/metrics) | Upstream Go controller, metrics exporter, status controller and tests. Candidate location for the standalone and collector changes |
| [Reduced frr-k8s candidate, `348b6ce`](https://github.com/dfarrell07/frr-k8s/tree/348b6ce29a852c420407a2d0970f8cc2027d381d), [#528](https://github.com/metallb/frr-k8s/pull/528), [review branch](https://github.com/dfarrell07/frr-k8s/tree/evpn-metrics-gr-integration) | Inspected 2026-11-05: per-family BGP prefixes, default basic VNI collector and EVPN-only success. Existing BGP/BFD series and serving implementation retained; stacked on #519, unmerged upstream |
| [Archived full prototype, `87f63e1`](https://github.com/dfarrell07/frr-k8s/tree/87f63e17f5d234c03f1b9ddd721f0960b50d1f37), [`prototype/evpn-metrics-full`](https://github.com/dfarrell07/frr-k8s/tree/prototype/evpn-metrics-full) | Shared collectors, optional EVPN, BFD identity changes, ES/DF, standalone mTLS, bounded reviews and shutdown. Historical evidence below includes `62bead0`; it does not qualify the reduced candidate |
| [Reference exporter, `f86942d`](https://github.com/dfarrell07/frr-metrics-exporter/tree/f86942d7a28255aaed436c18cc1614731cf91bc0) | [Feature branch](https://github.com/dfarrell07/frr-metrics-exporter/tree/feature/exporter-reference), published on fork main, inspected 2026-11-02. BGP/BFD/EVPN collectors with bounded standalone mTLS; [demo and sample](https://github.com/dfarrell07/frr-metrics-exporter/pull/3#issuecomment-6594391791); [qualification evidence](#required-evidence-per-slice) |
| [`openshift/frr`, `5f7712b`](https://github.com/openshift/frr/blob/5f7712b486942769dc12a6c8e993537569faa587/Dockerfile.openshift) | Downstream frr-k8s fork; main, release-5.1 and release-5.2 match this revision (2026-11-04). Builds the Go binaries and installs the RHEL FRR package. Historical full-prototype [compiler/runtime checks](#required-evidence-per-slice) pass; reduced-candidate integration and official image build remain |
| [`openshift/frr` release-4.22, `943578e5`](https://github.com/openshift/frr/blob/943578e55487fc99389a36e0b50ee3e02101050e/cmd/metrics/exporter.go) | Earlier HTTP exporter without native Kubernetes authentication; useful history and the interim option, not a 5.x fix |
| [`FRRouting/frr` 10.4.3, `6ddbeb5e`](https://github.com/FRRouting/frr/tree/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra) | C daemons and CLI JSON producers, used to establish candidate EVPN fields; verify fixtures against the chosen image's RHEL package |
| [`tynany/frr_exporter` v1.12.0, `85392e48`](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/bgp.go) | Exporter selected by the merged Ansible role; comparison baseline for coverage lost on replacement |
| [EGA main, `cbc7d43`](https://github.com/openshift/evpn-gateway-appliance/blob/cbc7d436e9836c51ee7f8b51c49bd9b533d93024/image/rhel10/Containerfile) | Inspected public baseline (2026-10-29): embeds FRR and node-exporter; its metrics unit is not installed/enabled and the collection still uses the legacy exporter. Import history is in [source audit](source-audit.md); merged source does not establish runtime qualification or approval of decisions 10/16 |
| Internal prototype `evpn-on-cloud` at `1c8e88873af8` (read in full 2026-11-02) | Runs `tynany/frr_exporter` (`:9342`, BGP, L2VPN and BFD collectors, unpinned `:latest`) and node-exporter, plus 16 conditional health-check task definitions. It has no rule or dashboard artifacts; one plan table marks alert rules done; its task breakdown plans replacing the exporter with `/frr-metrics`. Mapped in [What the prototype's checks become](#what-the-prototypes-checks-become) |

Upstream main `a57f09c` (2026-11-02), the rebased #519's base, has no `cmd/metrics`,
`internal/frr` or `internal/tlsconfig` change since `0d3197bb`. Its integration fixtures
select FRR 10.6.2, which does not qualify the FRR 10.4.3 RHEL package.

The [ART 5.1 input at `7b8eb39d`](https://github.com/openshift-eng/ocp-build-data/blob/7b8eb39dbd3076ac757d0f811b72e7bed9997938/images/ose-frr.yml)
selects the release branch and RHEL 9 build for `openshift5/frr-rhel9`, with a
modification selecting `frr10`. Build and test focused ports against the selected downstream
module/vendor tree and Red Hat toolchain; identical exporter files or passing upstream tests
do not qualify that build. A build-data declaration does not show customer registry
availability; resolve the actual image once the change lands and builds. Repeat the prior
[binary/FIPS evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs) for that candidate.

The reduced candidate changes the metrics collectors and existing neighbor parser/model,
with generated-configuration tests. It retains BFD, TLS, vtysh, liveness and serving code
apart from registering the new collector. Downstream integration still needs its own build
and runtime checks; no archived result transfers automatically.

## Exporter startup and authentication

### Current behavior

The [baseline exporter](https://github.com/metallb/frr-k8s/blob/0d3197bbe0090b88b4a106c222cc8c5118168138/cmd/metrics/exporter.go)
creates BGP/BFD registries, then a Kubernetes RBAC filter, before its TLS listener.
`rest.InClusterConfig()` is unconditional; the inherited kubeconfig flag/environment is unused.
FRR queries themselves need no Kubernetes client. `/livez` bypasses the filter on the same listener.
TokenReview/SAR authenticate and authorize `/metrics`; failures must not trigger unauthenticated fallback.
For regression tests, note cached review decisions and the observed invalid-token 500; test backend
failure with a fresh identity/filter. A custom metrics path also needs matching non-resource RBAC.

[#409](https://github.com/metallb/frr-k8s/pull/409) introduced native TLS/RBAC (merged 2026-03-24,
`a670e00`): HTTPS `0.0.0.0:9141`, TLS 1.3 minimum, and a self-signed certificate if none supplied.
The [4.22 interim](#interim-exporter-from-the-embedded-422-image) instead serves loopback HTTP.
These are different serving contracts.

### First patch as submitted

PR #519 ([feature branch](https://github.com/dfarrell07/frr-k8s/tree/disable-metrics-auth)) adds `--disable-metrics-auth=false`. Opting out bypasses only RBAC; TLS, Kubernetes
defaults and default no-cluster startup failure remain. No automatic fallback or dedicated
unit test is included (the reviewer considered the test excessive).

### Access model beyond the first patch

Remote access remains open under CORENET-7704 and decisions 10/16. #519's auth opt-out keeps
server TLS but supplies no client authentication; keep scraping local until the selected
remote path is qualified, with CA and endpoint-name validation.
The [access alternatives and rotation experiment](https://github.com/dfarrell07/evpn-gateway-appliance/blob/0ebd06027901f984f93bd300ac1b48ed7dbaeb3c/plans/context/evpn-aws/frr-metrics-details.md#access-model-beyond-the-first-patch)
retain the proxy, native mTLS and exporter-toolkit findings. A client CA authorizes every
valid client it issues; reloading trust did not revoke an existing persistent connection.
Agree revocation latency and test fresh, reused and resumed connections.

### Adjacent findings to handle separately

Focused fixes prepared separately from EVPN/access additions (rechecked 2026-11-04):

| Target | Finding | Branch / status |
| --- | --- | --- |
| frr-k8s | Supplied-certificate serving survives SIGTERM, including Helm TLS deployments | Local `fix/metrics-sigterm`, `51263c2`; process regression passes |
| frr-k8s | vtysh can block indefinitely and connect unrelated daemons | Published [`fix/metrics-vtysh-timeout`](https://github.com/dfarrell07/frr-k8s/tree/fix/metrics-vtysh-timeout), `c36be7f`; paused-daemon isolation, deadline and recovery checks pass |
| frr-k8s | Counter test expects a route refresh without requesting one | Published [`fix/metrics-route-refresh-test`](https://github.com/dfarrell07/frr-k8s/tree/fix/metrics-route-refresh-test), `3706337` |
| frr-k8s | Workspace checksum drift on the unmodified base | Published [`fix/e2e-workspace-checksums`](https://github.com/dfarrell07/frr-k8s/tree/fix/e2e-workspace-checksums), `b539dcc`; requirements unchanged |
| frr-k8s | Raw IPv6 bind addresses produce an invalid host/port | Local `fix/metrics-ipv6-bind`, `b8dbd39`; raw/bracketed listener regressions pass |
| frr-k8s | Unnumbered BFD sessions on different interfaces collide at the same peer/VRF | Local `fix/metrics-bfd-interface`, `ba6ac3d`; generated-config reproduction passes; label compatibility needs review |
| FRR | Secondary graceful restart timer survives instance deletion | [`fix/graceful-restart-timer-cleanup`](https://github.com/dfarrell07/frr/tree/fix/graceful-restart-timer-cleanup), `a05d449`; native before/after regression and 442 checks pass; cleanup also present in the replay branch |
| FRR | Restart completion overtakes replacement route replay | [`fix/graceful-restart-completion`](https://github.com/dfarrell07/frr/tree/fix/graceful-restart-completion), `4007568`; [validation below](#ipv6-graceful-restart-ci-investigation) |
| FRR | Configured startup ignores End-of-RIB while selection is pending | [`fix/graceful-restart-startup-eor`](https://github.com/dfarrell07/frr/tree/fix/graceful-restart-startup-eor), `f277609`; three timing regressions and standard native suite pass |

The SIGTERM, IPv6-bind and BFD-interface branches remain local. None of these focused
fixes has a standalone upstream PR.
[#519](https://github.com/metallb/frr-k8s/pull/519) includes both CI repairs and
[#526](https://github.com/metallb/frr-k8s/pull/526)'s graceful restart test setup fix.
[Fork CI](https://github.com/dfarrell07/frr-k8s/actions/runs/41877134240/attempts/2)
passes all 11 jobs after rerunning an IPv4 job that hit an FRR daemon crash. The SIGTERM fix
restores default termination; the archived full prototype coordinates shutdown. The focused
BFD fix adds only the interface label, separately from the archived broader identity proposal.
On the upstream base, partial TLS pairs fall back to self-signed TLS and BFD-only VRFs
are unsupported.

At `62bead0`, [CI](https://github.com/dfarrell07/frr-k8s/actions/runs/41963080026/attempts/1)
hit stock bgpd crashes after cleanup in both IPv4 jobs;
[unchanged retries](https://github.com/dfarrell07/frr-k8s/actions/runs/41963080026/attempts/2) passed.
The signature matches failures without the new collectors on frr-k8s
[#519](https://github.com/metallb/frr-k8s/pull/519) and
[#526](https://github.com/metallb/frr-k8s/pull/526). The stock image has the timer-cleanup
omission addressed by the [prepared fix](https://github.com/dfarrell07/frr/commit/a05d449ef2de6047bb1a2bb95bddd2ecd0f33578).
The crashes followed configuration release by about 120 seconds, consistent with that
timer bug; exact CI attribution remains unproven.

At `6b8efe6`, [dual-stack CI](https://github.com/dfarrell07/frr-k8s/actions/runs/41947671121/attempts/1)
failed an existing L2 forwarding ping: external FRR retained three BGP packets while
worker2 lacked remote EVPN routes. No daemon crash was recorded; the cause and any
collection timing effect remain unproven.

The archived full prototype explored coordinated listener/watcher/CLI shutdown. The reduced
candidate retains the existing lifecycle, certificate handling and known defects above;
these fixes remain separate from basic EVPN metrics.

## Collection semantics and failure behavior

### Existing series

BGP state, aggregate advertised/accepted-prefix gauges and message counters use `peer,vrf`.
Despite `_total`, prefix series are gauges: never `rate()` them. UPDATE counters measure
messages, not route additions/withdrawals. Preserve legacy series; adding labels is breaking.
Prefix gauges report FRR's counts, not an independent routing-table inventory.

The candidate retains summed prefix gauges and adds family counts using the same neighbor
reads ([contract](#proposed-additive-metrics)). Missing counts differ from explicit zero:
FRR can omit `sentPrefixCounter` without an update subgroup, including for a down peer.
VRF comes from the `vrf all` wrapper; message counters stay session-wide.

The upstream baseline's BFD `peer,vrf` identity can collide across local addresses/interfaces/multihop.
A real 10.4.3 test produced duplicate-series errors and HTTP 200 with a down sample while
another session was up. FRR's [`bfd_key`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfd.h)
includes family, mode, peer, local address, interface, VRF and BFD name. Both JSON snapshots
carry session IDs and identity fields; [producer](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfdd_vty.c).
The existing counter parser retains only peer and labels results with the queried VRF.

The reduced candidate retains BFD's existing `peer,vrf` labels and parser. The archived full
prototype and reference exporter explore broader identity checks and extra labels; any
separate label change needs compatibility review. Those experiments do not repair BFD in #528.

BGP-derived VRF discovery misses BFD-only VRFs (observed on 10.4.3). Unfiltered `show bfd
peers json` and `show bfd peers counters json` expose them in two reads, with VRF/session
fields. A nonexistent VRF filter succeeds with `[]`; empty does not prove coverage. No BFD
session is expected merely because bfdd runs. Standalone tests can cover BFD-only VRFs;
upstream frr-k8s integration tests must use configurations its controller supports.

### Failure visibility and deadlines

[Baseline collectors](https://github.com/metallb/frr-k8s/tree/0d3197bbe0090b88b4a106c222cc8c5118168138/cmd/metrics/collector)
log CLI/parse errors but emit no status; HTTP 200 can contain only process metrics or
partial BFD data. [`promhttp_metric_handler_errors_total`](https://github.com/prometheus/client_golang/blob/48dd383f94cc36bb0179724166383effd9f64847/prometheus/promhttp/http.go)
catches registry/encoding errors, not logged collection failures, and can lag one scrape.

The reduced candidate adds unlabeled `frrk8s_evpn_scrape_success` for its one VNI read and
parse. It builds the complete EVPN result before emitting; failure omits VNI measurements
and reports 0, while successful empty inventory reports 1. This says nothing about BGP/BFD
collection success. Missing optional measurements remain absent even when collection succeeds.
Use target status, expected series and EVPN success together.

Existing vtysh execution remains unbounded; the new default query adds scrape cost and can
block a scrape. Global collector status/duration, admission, output bounds and cancellation
belong to the archived experiments or separate fixes, not this candidate. Selected-image
qualification must assess scrape cost and failure behavior.

The upstream baseline discovers VRFs with `show bgp vrf all json`, dumping routes at least
three times per scrape. [#507](https://github.com/metallb/frr-k8s/pull/507) (`6f1effe`, open November 2)
changes command and parser to `show bgp vrfs json`. The reduced candidate retains existing
discovery; only the archived full prototype and reference exporter use bulk BGP/BFD reads.

### Liveness has a narrower meaning

`/livez` runs `show daemons`, requiring zebra/bgpd/watchfrr/staticd/bfdd: CLI failure is 500,
missing daemon 404. It proves neither peering nor forwarding. Preserve cluster probes.
The [10.4.3 daemon script](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/tools/frrcommon.sh.in)
forces zebra/staticd/mgmtd on when available; `bgpd=yes`/`bfdd=yes` does not prove the others
are absent. Qualify the packaged daemon set. If appliances intentionally omit daemons,
separate process liveness from configured readiness instead of weakening cluster semantics.

## EVPN data sources and proposed metric contract

### What FRR 10.4.3 actually exposes

The pinned FRRouting C producers and [real VNI capture](https://github.com/dfarrell07/frr-k8s/blob/87f63e17f5d234c03f1b9ddd721f0960b50d1f37/cmd/metrics/collector/testdata/evpn_vni.json)
establish the summary fields used by this candidate; topotest expected JSON can be partial.

| Command | Shape / meaning | Consequence for the collector |
| --- | --- | --- |
| `show evpn vni json`, L2 entry | Object keyed by VNI; `vni`, `type`, `vxlanIf`, `tenantVrf`, `numMacs`, `numArpNd` and numeric `numRemoteVteps` | Inventory and occupancy; a known zero-MAC VNI still has an entry |
| Same command, L3 entry | `numMacs` counts router MACs, `numArpNd` counts next hops, and `numRemoteVteps` is the string `"n/a"` | Emit inventory only; these counts are not L2 occupancy, and `"n/a"` is not zero or the legacy `-1` sentinel |

Real 10.6.2 output matched these shapes (October 27), adding `vlan`/`bridge`.
Summary MAC counting walks the table and excludes AUTO-only entries; a bulk read still
needs daemon CPU/JSON-size qualification at scale. Full MAC dumps cost more.
The [other command schemas and ES/DF captures](https://github.com/dfarrell07/evpn-gateway-appliance/blob/0ebd06027901f984f93bd300ac1b48ed7dbaeb3c/plans/context/evpn-aws/frr-metrics-details.md#what-frr-1043-actually-exposes)
retain the detailed shape differences and findings for commands outside this candidate.

### Proposed additive metrics

The candidate's [metric names, labels and behavior](https://github.com/dfarrell07/frr-k8s/blob/348b6ce29a852c420407a2d0970f8cc2027d381d/cmd/metrics/README.md)
are documented with the implementation. Its default VNI read also runs on BGP-only deployments; there is
no collector-selection flag. Relays need prefix counts without local VNIs. L3 VNIs supply
inventory only; L2 MAC occupancy excludes AUTO-only entries and is not a learning-event
counter. Known-VTEP counts cannot verify an individual member or forwarding health.

Individual membership, ES/DF and broader collection/access features remain in the
[archived full prototype](https://github.com/dfarrell07/frr-k8s/tree/87f63e17f5d234c03f1b9ddd721f0960b50d1f37/cmd/metrics).
The [earlier contract notes](https://github.com/dfarrell07/evpn-gateway-appliance/blob/0ebd06027901f984f93bd300ac1b48ed7dbaeb3c/plans/context/evpn-aws/frr-metrics-details.md#proposed-additive-metrics)
retain parser/schema findings; they add no features to this candidate. DF alerts remain product work.

### Learning, reachability and DF need honest semantics

Known VTEPs/BGP sessions do not prove forwarding, and relay next hops need not equal peers.
Name alerts for their signal: expected membership, mapped BFD, interface state or explicit
probe. BFD-up also does not prove TCP/179 works; include BFD-up/BGP-transport-blocked faults.
A DF role change can be valid failover; require intended local HA policy, convergence time
and complete participant coverage.

BFD RTT is not generic latency. FRR 10.4.3 reports microsecond recent-window echo samples
only for Linux single-hop IPv4; zero echo output means no samples. [`_display_rtt`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfdd_vty.c)
initializes the minimum to 1000µs, capping larger minima. Do not publish missing samples as
zero latency; select and qualify a supported latency source.

### Legacy migration contract

The prototype's `:latest` image leaves historical binary/metric inventory unknown. Its
configured default IPv4 BGP plus L2VPN/BFD collectors are compared here against inspected
v1.12.0 `85392e48`; IPv6 BGP is not explicitly enabled.

| Legacy source / signal | Migration meaning |
| --- | --- |
| [`collector/bgp.go`](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/bgp.go): peer state, uptime, received/advertised prefixes, message totals by AFI/SAFI | Preserve peer/VRF identity and EVPN-specific prefix visibility. Legacy state 2 is administratively down; frr-k8s emits 1 only for Established. The reduced candidate adds family gauges alongside its existing aggregates |
| Same file, enabled L2VPN collector: `show evpn vni json` | Supplies MAC, ARP/ND and known remote-VTEP occupancy (`frr_bgp_l2vpn_evpn_{mac,arp_nd,remote_vtep}_count_total`, all gauges) with `vni,type,vxlanIf,tenantVrf`. The reduced candidate adds this view, absent from merged frr-k8s |
| [`collector/bfd.go`](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/bfd.go): session state, uptime and peer count | Capability only until sessions are configured. Preserve session identity; frr-k8s adds packet and event counters but its current peer/VRF labels can collide |
| [`collector/collector.go`](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/collector.go): success/duration and socket timeout | The reduced candidate adds EVPN-only success; global failure visibility/duration and bounded reads remain gaps. Successful HTTP alone cannot replace them |

The reduced candidate and archived prototypes omit the legacy BGP/BFD uptime gauges. Preserve intended meanings,
not misleading `_total` gauge suffixes or the L3 remote-VTEP `-1` sentinel. Neither baseline exporter supplies learn/age/move event rates, DF or reachability.
Occupancy derivatives and UPDATE rates are not event counts; true event rates need a defined
counter. Keep per-MAC/IP diagnostics out of labels.

### What the prototype's checks become

Reviewed local `evpn-on-cloud@1c8e88873af80ea66f6b111638ca1453275cc4e2` (November 2); no claim
about current remote head. Three evidence levels matter:

- [Monitoring role](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af80ea66f6b111638ca1453275cc4e2/ansible/roles/evpn_monitoring/tasks/main.yml)
  and image configure collectors; this is intended coverage, not a captured scrape inventory.
- [Health role](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af80ea66f6b111638ca1453275cc4e2/ansible/roles/evpn_health_check/tasks/main.yml)
  runs during deploy and through `health-check.yml`; it is not continuous metrics or an agent.
- [Task breakdown §2.5](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af80ea66f6b111638ca1453275cc4e2/docs/evpn-task-breakdown.md),
  cited by Jira, plans overview, BGP/churn, VNI/MAC, transport/BFD/latency/bandwidth and
  failure/DF views. All are unchecked and broader than the implemented checks.

These are 16 task definitions, numbered in source order, not 16 executions: common checks
run per host and VNI/ping tasks loop over stretches.

| Tasks | What the code actually checks | Continuous signal or other home |
| --- | --- | --- |
| 1 | A container-name result contains `frr` | Exact router service/container lifecycle outside FRR metrics; the substring can also match `frr_exporter` |
| 3, 4, 8, 12 | IPv4 BGP summary says Established for each expected relay/VTEP adjacency | `frrk8s_bgp_session_up` plus expected peer inventory; a session alone does not establish EVPN route exchange |
| 5, 6 | Relay EVPN summary has `pfxRcd > 0` from each side | Per-peer/VRF EVPN accepted-prefix gauge; this shows receipt, not that the relay advertised those routes onward |
| 9, 13 | Each workload/on-prem VNI lists an IPv4 remote-VTEP address | Known remote-VTEP count per L2 VNI; individual-member checks were explored in the archived prototype and remain outside the reduced candidate |
| 10, 14, 15 | Per-stretch gateway pings; simulated-VM ping in lab mode | Deploy/e2e forwarding tests; a separately selected continuous probe for runtime reachability/latency |
| 2, 11 | WireGuard output contains a latest-handshake field | Development-transport diagnostics; no handshake-age test or continuous source exists; not a production FRR metric |
| 7 | Relay has no VXLAN interfaces | Deployment/topology invariant; do not require per-VNI occupancy from this relay |
| 16 | A simulated cross-VLAN ping fails | Isolation test with working-path positive controls; an arbitrary ping failure does not prove isolation |

FRR's [`bgp_vty.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bgpd/bgp_vty.c)
uses the same per-family `pcount` for summary `pfxRcd` and neighbor `acceptedPrefixCounter`.
Per-family gauges preserve the relay check; aggregate IPv4+EVPN counts cannot. Advertised
counts add the other direction but prove neither exact-route arrival nor end-to-end propagation.

MAC/ARP-ND occupancy is collector coverage, not an explicit health assertion. No prototype
FRR template configures BFD sessions or ES/DF (future §§2.3–2.4). The plan also requests
storm diagnostics, but interface bytes are not a BUM counter. The repository has no rules,
dashboard or health-agent artifact despite conflicting completion prose; §2.5.6 stays unchecked.
Map the retiring lab workload-VTEP role (§5.4) to OCP-native checks; host/AWS/probe sources
remain outside the FRR exporter.

## Runtime, image and collection integration

### Runtime shape if `frr-metrics` is chosen

Proposal under decisions 10/16: a separate exporter container from the same pinned FRR
image, running `/frr-metrics` through its tini entrypoint. This preserves vtysh/libraries/users
and provenance while separating routing and exporter lifecycles; it adds no health-check agent.

Qualify non-root `frr`, no capabilities, read-only root and only required socket/config/cert
mounts under rootful RHEL 10 SELinux. It needs no routing capabilities or router network
namespace. With a private namespace, bind container-reachable and publish to host loopback;
container loopback alone was unreachable through publication. Host networking can bind host
loopback directly. Qualify approved remote access separately.

Socket access grants full daemon configuration even through a read-only mount: compromise
of the exporter can compromise routing. Fixed commands/no request-derived arguments reduce
input surface but do not make socket access read-only. Derive permissions from the image;
independent `:Z` relabels break sharing. Do not copy router privilege or disable SELinux.

Host extraction needs compatible libraries, host vtysh, architecture and socket permissions;
the embedded design has no FRR RPM. Host FRR plus exporter changes the payload direction and
needs its own decision, FIPS/library and lifecycle proof.

### Interim exporter from the embedded 4.22 image

The already pinned `openshift4/frr-rhel9@sha256:82fd7cc0…`
(`v4.22.0-202609221726.p2.g1277b23`, amd64/arm64/s390x/ppc64le index) contains standalone
`/frr-metrics`: HTTP `127.0.0.1:7573`, configurable bind/port/path, unused kubeconfig.
Collectors/parser/liveness match upstream `6be1ff9`; vtysh differs only by a comment, so
names and labels match 5.x, not its TLS/auth contract. Image: RHEL 9.8,
`frr10-10.4.3-3.el9_8.2`, `/usr/bin/vtysh`, `frr` 998:997 with frrvty membership,
empty vtysh.conf, Go 1.25.14/strictfipsruntime.

Rootless October 27 test: two pinned-image routers with eBGP/BFD/EVPN and an unreachable
peer; exporter used non-root frr, no capabilities, read-only root and only shared sockets.

| Case | `/metrics` | `/livez` |
| --- | --- | --- |
| Routers up | 200, 21 `frrk8s_*` families (13 BGP, 8 BFD) with one sample per peer, up 1 for the live peer and 0 for the dead one; prefix gauges summed across families | 200 |
| Router stopped, socket files left | 200, no `frrk8s_*` series, log `exit status 1` | 500 |
| Router restarted | Series recover | 200 |
| No `/etc/frr/vtysh.conf` | 200, **no `frrk8s_*` series** (`invalid character '%'`) | **200** |
| `podman stop` | Exits in about 0.3 s (no graceful-shutdown handler) | |

Use only for development/e2e until accepted. Loopback still admits host users/processes and
host-network containers; every unbounded scrape can load FRR. The same family/BFD/failure
limitations apply. Later checked branches (4.23, 5.0–5.2) need in-cluster config. Floating
4.22 tags move: own digest updates/scanning. Product Security must assess OCP 4.22/RHEL 9
content inside RHEL 10 bootc, errata ownership, nested-image SBOM and whole-container FIPS
startup/crypto validity. A strict-FIPS build alone does not qualify this appliance.

### Concrete EGA integration work

At `cbc7d43`, the metrics unit is unused and expects the wrong binary/unit path. Monitoring
recognizes `frr-exporter.service`, otherwise starts legacy Podman; a rename alone can create
two exporters. Handlers restart the image router when present, otherwise use `frr_image`;
that fallback cannot establish same-image pairing. Test configuration-triggered restarts,
not just the first scrape.

7504/7704 migration must:

- Replace socket-directory chmods in monitoring and all router roles with image-owned permissions.
- Disable both old/new exporters persistently across router restart/reboot; clear overrides
  on re-enable. Stop owning services before container removal, or restart policies recreate them.
- Cover every production group, deployment-owned resources, teardown and redeploy. Recheck
  groups when [#23](https://github.com/openshift/evpn-gateway-appliance/pull/23) lands; the baseline
  deploy covers three groups but teardown removes exporters only on-prem.
- Verify binary help/startup/series per target platform, provenance/SBOM/FIPS and running
  router/exporter image IDs against the approved platform image. Equal `frr:embedded` tags
  alone do not prove pairing; do not copy an upstream development binary into a release image.

### Proposed units, ownership and e2e checks

Rootless Fedora/Podman 5.8.8/systemd 258 tests (October 27) are not rootful RHEL 10/systemd 257
qualification. Repeat SELinux socket-access/lifecycle tests on the appliance. Keep raw units
consistent with main; if moving to Quadlet, port router/exporter/dependencies together.

Observed basis for an implementation sketch:

- Image-owned `/usr/lib/systemd/system/frr-container.service.wants/frr-metrics.service`;
  `BindsTo=` plus `After=` propagated router stop/restart/crash and directory replacement.
  `After=` alone is neither readiness nor restart propagation.
- Preserve tini, image vtysh.conf, matching UID semantics and non-root read-only exporter;
  no exporter-side private relabel. `/livez` is not scrape completeness. Check actual exit
  codes before allowing 143; only the archived full prototype demonstrated coordinated exit 0.
  Avoid duplicate journal logging.
- Router's private `:Z` socket mount blocks a confined peer. Shared `:z` connected in the
  lab but exposes any bind-mounting container with matching DAC access. Pair it with tighter
  ownership or qualified shared MCS labels; never `label=disable`.
- Router `RuntimeDirectoryMode=0777` allows socket replacement and resets/removes the directory
  each lifecycle. Replace `RuntimeDirectory=` with tmpfiles: `d /run/frr 0750 998 997`, after reserving/checking
  host IDs; shared relabel is still needed because tmpfiles creates `var_run_t`. Test deleted
  directory/inode recovery and matching identities; mode/name agreement alone is insufficient.

Qualify persistent `frr-metrics.service` disable overrides, rollback and re-enable. Masking a
vendor `/usr/lib` unit can work; a regular legacy unit in `/etc` can block it and needs deliberate
migration. Coordinate privilege/binding/auth and permitted/rejected-access CI with
[CORENET-7704](https://redhat.atlassian.net/browse/CORENET-7704). Parked 7678 work also edits
these files and must be rebased. Tighten the e2e `name=frr` check: it also matches `frr-metrics`.

## Scraping and rules

### Scraping, expectations, dashboards and rules

- Select external-target mechanism, path, CA/server name, client credentials/rotation and labels;
  cluster frr-k8s ServiceMonitors do not discover appliances. Keep credentials out of query
  sources; appliances need no Kubernetes API access merely to be scraped.
- Slice 7 owns validated expected peers/VNIs/BFD/collectors, their updates/removal/freshness,
  and stable appliance identity. Observed data/global `absent()` cannot enumerate vanished
  objects; [zero comparisons miss absence](https://prometheus.io/docs/prometheus/latest/querying/operators/#comparison-binary-operators).
  Keep target down, collection failed, object missing and object down distinct. Require valid
  status only from capable sources; 4.22 legitimately has none.
- Scope all joins to the intended source/query domain; test duplicate/cross-cluster names
  because `max` can hide a failed target. Scraper HA deduplication does not establish identity.
  Match VNIs by appliance/VRF/VNI; missing required counts remain unknown, not zero.
- Gate expected-session checks on BFD capability and successful BFD collection, with explicit
  legacy fallback. Test BFD-only and independently failing collectors; BGP samples are not
  BFD-success evidence. The reduced candidate has no BGP/BFD success gauge; EVPN success
  cannot supply it. If inventory and discovery both disappear, validate coverage against
  deployment inputs: neither vanished series supplies an alert anchor.

### Scrape-path evidence

No scrape path is selected. The [version-specific CMO/COO/ACM evidence](https://github.com/dfarrell07/evpn-gateway-appliance/blob/0ebd06027901f984f93bd300ac1b48ed7dbaeb3c/plans/context/evpn-aws/frr-metrics-details.md#scrape-path-evidence)
retains the October 27 baseline and November 2 support/federation findings. API availability
alone does not establish support: [4.22 guidance](https://docs.redhat.com/en/documentation/monitoring_stack_for_red_hat_openshift/4.22/html-single/support_for_monitoring/index)
lists Probe/out-of-reference configuration unsupported. [KCS 6988164](https://access.redhat.com/solutions/6988164)
supports limited external monitoring with capacity cautions; its public portion does not
establish the exact 4.22+ EndpointSlice/mTLS recipe, and subscriber steps were not inspected.

Qualify discovery/write RBAC, actual source/return routing and firewall policy, authentication,
namespace/label handling, query/data-source RBAC and any federation on the selected versions.
CUDN/EVPN advertisement alone does not establish monitoring-pod reachability on the default
network. Budget for both UWM replicas and verify Alertmanager routing, notification delivery
and inhibition in the chosen path. AWS state/traffic metrics do not supply on-prem latency.

### Facts that shape the rules

- `frrk8s_bgp_updates_total` and `frrk8s_bgp_updates_total_received` are counters; announced/received-prefix `_total`
  families are gauges. State 1 means Established; administrative shutdown reads 0.
- Inspected templates configure no BFD sessions. Gate on declared sessions and source capability.
- VXLAN/WireGuard can work with operstate `unknown`; `node_network_up=0` is insufficient.
  For declared devices, alert on explicit down-like states, aggregating operstate away to
  preserve `for:` across transitions. Unknown is not forwarding proof.
- Image node-exporter binds loopback, with neither systemd nor textfile configured. Systemd
  also needs D-Bus. Remote access/service panels require unit changes; verify embedded version.
- `maximum-prefix` has no restart timer; exceeding it needs manual clear. Warn from configured
  limits, recognizing aggregate family counts can warn early. In the 2026-11-02 lab, 1000 prefixes was
  exceeded at 600 hosts; test 7519 scale against actual route counts.
- The 2026-11-02 lab rejected template commands on 10.4.3/10.6.2 despite forwarding; fix through
  collection owners. Traditional defaults yielded hold 180s versus the [design PR's](https://github.com/openshift/evpn-gateway-appliance/pull/17) 90s.
  A down device can remain in VNI inventory; VNI-missing means absent/unconfigured, not forwarding failure.
- Test resets/gaps: [`increase()`](https://prometheus.io/docs/prometheus/latest/querying/functions/#increase)
  extrapolates. Measure alert latency as protocol detection + scrape/evaluation + `for:` +
  notification delay, separately from HA failover. Update inventory before intentional FRR
  removal and test reloads live;
  promtool cannot test reload behavior.

## Validation and experiments

### Required evidence per slice

Product qualification still needs the selected payload, scrape access, lifecycle and rules/UI.
Local containers do not establish rootful RHEL 10/SELinux or FIPS qualification.
`internal/frr` tests start Docker unless `-short`.

At `348b6ce`, the reduced candidate passed the full local Go suite with controller envtests,
FRR integration, metrics race tests and lint. Command builds and EVPN test compilation passed
at `202b2ff`; its [hosted CI](https://github.com/dfarrell07/frr-k8s/actions/runs/42088338524) results are pending.
The intervening change simplifies one unit test; production and end-to-end sources are identical.

Historical full-prototype/reference checks covered broader collectors, access behavior,
Red Hat toolchain/runtime smoke and synthetic load. The [detailed validation record](https://github.com/dfarrell07/evpn-gateway-appliance/blob/0ebd06027901f984f93bd300ac1b48ed7dbaeb3c/plans/context/evpn-aws/frr-metrics-details.md#required-evidence-per-slice)
preserves the option-specific test matrix, revisions, image digest, CI retries, FIPS-mode
experiments and scale limits.
Those results establish neither a reduced-candidate build nor appliance qualification.
The official downstream image build remains untested beyond its builder pull; the November 4
check needed CI-registry authorization. Selected-image/platform delivery, live dense-VTEP
scale, forwarding, rootful RHEL 10/SELinux, FIPS and appliance lifecycle/access remain unqualified.

### IPv6 graceful restart CI investigation

FRR 10.6.2 restart completion overtook replacement-route replay, allowing stale-route deletion.
The [standalone reproducer](https://github.com/dfarrell07/frr-k8s/tree/16c3731d5bc5b3e2d127edd33197d317b6b6df02/.github/frr-gr/reproducer)
reproduced it without metrics or Kubernetes. Separate replay/startup fixes are linked in
[adjacent findings](#adjacent-findings-to-handle-separately); the related VRF reload failure
already has [FRR #23851](https://github.com/FRRouting/frr/pull/23851).

The [detailed investigation](https://github.com/dfarrell07/evpn-gateway-appliance/blob/0ebd06027901f984f93bd300ac1b48ed7dbaeb3c/plans/context/evpn-aws/frr-metrics-details.md#ipv6-graceful-restart-ci-investigation)
preserves immutable runtime inputs, fixes, timing regressions and observer results. Historical
patched-runtime CI validated the combined FRR changes; it does not qualify this candidate or
the selected downstream/appliance runtime. Sampled route retention does not measure a
forwarding outage; the separate stock-bgpd crash attribution remains unproven.

## Upstream evidence

Use focused issues/PRs for #519 and additive EVPN work, then integrate into the selected
`openshift/frr` branch. Downstream-only patches need support/rebase owners.

Basic L2/L3 EVPN fits the [design](https://github.com/metallb/frr-k8s/blob/a57f09cf7458056f32f5a903f62f1a1ac18331e8/design/basic-evpn-support.md).
The [reduced candidate's generated-configuration tests](https://github.com/dfarrell07/frr-k8s/blob/348b6ce29a852c420407a2d0970f8cc2027d381d/e2etests/tests/evpn.go)
check EVPN prefixes against BGP summaries, configured L2/L3 inventory, L2 gauge presence
and EVPN success through the authenticated endpoint; [execution status](#required-evidence-per-slice) remains separate.
ES/DF needs a product source and separate agreement: the design excludes multihoming;
archived fixture/runtime smoke does not establish cluster coverage.

[#506](https://github.com/metallb/frr-k8s/issues/506)/[#507](https://github.com/metallb/frr-k8s/pull/507)
cover VRF-listing cost; [#513](https://github.com/metallb/frr-k8s/issues/513) proposes in-cluster
rules/dashboards (no replies in the November 2 baseline). Neither establishes appliance scope.
