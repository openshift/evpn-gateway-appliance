# FRR metrics and observability plan (CORENET-7504)

This is an implementation proposal and source investigation for
[CORENET-7504](https://redhat.atlassian.net/browse/CORENET-7504), first checked
2026-10-22 and refreshed 2026-10-29; dated rows say when they were checked. Its
acceptance criteria cover dashboards and alerts for the complete EVPN solution;
making `frr-metrics` work outside Kubernetes is the first enabling change, not the
whole story.

Code in flight, all unmerged and unreleased (see [status](#status-and-next-steps)):

- Slice 1 upstream: [#518](https://github.com/metallb/frr-k8s/issues/518) and
  [#519](https://github.com/metallb/frr-k8s/pull/519), one commit
  [`9a0eec0`](https://github.com/dfarrell07/frr-k8s/commit/9a0eec00fbc8830c92eea718b28b03557b8e6e83)
  on upstream main `6be1ff9` ([details](#first-patch-as-submitted)). Whether upstream
  will distribute the binary outside the project is open
  ([options](#if-upstream-declines-the-flag)).

This document does not approve payload, endpoint exposure or support decisions.
[Decisions 10 and 16](kickoff-decisions.md#decisions-at-a-glance) retain their existing
status until accountable-owner approval is recorded. Read the controlling [metrics
contract](pipeline-spec.md#metrics-corenet-74997504), [Containerfile
contract](containerfile-refactor-spec.md) and [source-audit lifecycle and exposure
findings](source-audit.md#1-security--identity-findings) with this plan.

## Status and next steps

As of 2026-10-29:

| Work | State | Blocked on |
| --- | --- | --- |
| Slice 1, `--disable-metrics-auth` (upstream #518, #519) | Open; review comments applied, +18/−3; behind main | Lead maintainer's doubt about distributing the binary outside frr-k8s; no reply since our 2026-10-29 answer ([options](#if-upstream-declines-the-flag)) |
| Lifecycle WIP ([`f62448f`](https://github.com/dfarrell07/frr-k8s/blob/f62448fab424fd46abf61787bd7b0cd30dbd436e/cmd/metrics/exporter.go) in the fork) | Unmerged; `main` split into `run`/`serve` with listener cleanup on TLS failure, plus the [adjacent findings](#adjacent-findings-to-handle-separately); focused tests pass, full CI, CLI subprocess cancellation and appliance qualification remain | Splitting into upstream-sized changes |
| Minimal upstream SIGTERM and vtysh stderr fixes | Fork branches [`metrics-sigterm-shutdown`](https://github.com/dfarrell07/frr-k8s/commit/23d4584aa414740a2f297cf92dd33a2ba9a74dff) and [`metrics-vtysh-stderr`](https://github.com/dfarrell07/frr-k8s/commit/917970c203eb3df630ca19bbedb8028aeaa63de3) (2026-10-27), each one commit on main `58664da` with tests; `make test` and lint pass | Submission ([order](#evidence-and-open-questions)) |
| Interim exporter from the pinned 4.22 FRR image | Checked live: works without a cluster on loopback HTTP; for development and e2e only until accepted | Decision 16 (interim source), decision 10 (payload), Product Security |
| Image exporter unit and router-unit fixes | Design; unit directives checked rootless on a Fedora host | A draft PR can open now; merging waits on the interim decision, socket-directory hardening and a rootful test on the appliance |
| Collection migration, teardown, e2e scrape | Design | 7499/7504 split; EGA #23 landing |
| BGP, BFD and interface rules and dashboards | Drafts on [`corenet-7504-monitoring-drafts`](https://github.com/dfarrell07/evpn-gateway-appliance/tree/corenet-7504-monitoring-drafts/monitoring) apply the alert fixes below and pass promtool | Nothing blocks a source PR (job labels parameterized); deployment needs the scrape location; PM answer on Grafana versus Perses |
| VNI/MAC, VTEP and DF views and alerts | Not started | Upstream EVPN collector (slices 3 to 5) or an interim textfile source; decision 16; DF also needs CORENET-7502/7503 |
| DX, VPN and latency | Not started | AWS metric source and an owner |

Critical path: the VNI/MAC and VTEP/DF criteria need an approved EVPN data source. The
proposed one is an upstream EVPN collector, with no upstream issue yet, synced downstream
before the 5.1 branch cut (ask 7); decision 16 also lists an interim node-exporter
textfile. Proposed split (ask 2) so part of the story can close earlier: BGP, BFD and
interface views and alerts on the interim exporter; EVPN VNI/MAC, VTEP and DF; and AWS
DX, VPN and latency with its own owner.

Next:

1. Take the [asks](#evidence-and-open-questions) to their owners in the order listed;
   for #519 (ask 8) chase a keep-or-separate-project decision, then submit the SIGTERM
   fix upstream and then the vtysh stderr fix.
2. Open a draft EGA PR for the [image unit](#proposed-units-ownership-and-e2e-checks)
   and its smoke scrape.
3. Open a source PR for the [BGP, BFD and interface
   rules](#rules-and-dashboards-buildable-now) with a promtool gate.

## Requirements and scope

On 2026-10-27 the story is assigned and In Progress, with no subtasks or issue links; its comments are automation warnings and progress notes, not requirements. Related: [CORENET-7499](https://redhat.atlassian.net/browse/CORENET-7499) replaces the legacy exporter; [CORENET-7505](https://redhat.atlassian.net/browse/CORENET-7505) requires the frr-k8s binary and pinned inputs. Neither makes an upstream binary a supported Red Hat build.

| 7504 acceptance area | Existing source or candidate | Work needed |
| --- | --- | --- |
| Appliance, VLAN and tunnel status | node-exporter interface counters/state; optional systemd collector | Deploy the selected build with explicit access controls; qualify interface/service meanings and map them to deployed resources |
| BGP sessions, prefix counts, route churn | `frr-metrics` BGP collector | Standalone operation and collection-failure visibility; additive address-family metrics; label UPDATE rates as message activity unless route-event instrumentation is added |
| VNI and MAC learning behavior | FRR zebra EVPN JSON | New EVPN collector, bounded labels and migration tests; aggregate MAC count is occupancy, not learning-event rate |
| DX, VPN, BFD, latency and bandwidth | Existing BFD collector; node-exporter; AWS CloudWatch | Qualify BFD; choose the AWS integration and latency measurement source with the story owner; interface bytes are not a latency or capacity measurement |
| BGP, VTEP, BFD, transport and DF alerts | Existing session state plus proposed EVPN data, declared expectations and external transport data | Define failure semantics, missing-data handling, controlled fault tests and notification delivery |

Decision 1 (review direction 2026-10-01; owner and Jira correction pending) covers
correcting 7504's VNI/MAC criterion; fold the
"MAC occupancy as the learning view" and "UPDATE rate as churn" clarifications into
that edit. Exporter lifecycle and TLS hardening below improve 5.x production use;
propose tracking them with CORENET-7511 (hardening). They do not gate rule and dashboard
authoring, but the appliance slice (7) requires them before it deploys the exporter.

Keep the first FRR change small enough to review independently: explicit standalone authentication selection, tests and documentation. It should not introduce an appliance-specific controller, build another image distribution, change Kubernetes defaults, or require a running cluster.

## Source baseline and repository boundaries

Inspected source revisions, not published or deployed builds; undated observations are
from 2026-10-22.

| Repository / revision | What it contains and why it matters |
| --- | --- |
| [`metallb/frr-k8s`, `0d3197bb`](https://github.com/metallb/frr-k8s/tree/0d3197bbe0090b88b4a106c222cc8c5118168138/cmd/metrics) | Upstream Go controller, metrics exporter, status controller and tests. Primary candidate for the standalone and collector changes |
| [`openshift/frr`, `567c9101`](https://github.com/openshift/frr/blob/567c9101668ad51d96feb15ff121d69d6256fc1a/Dockerfile.openshift) | Downstream fork of frr-k8s, despite the name. Builds the Go binaries and installs the RHEL FRR package into the OpenShift image. It is not the FRRouting C daemon repository |
| `openshift/frr` release-5.1 and release-5.2, `567c9101` | Both currently match downstream main. Their exporter file is identical to the inspected upstream file |
| [`openshift/frr` release-4.22, `943578e5`](https://github.com/openshift/frr/blob/943578e55487fc99389a36e0b50ee3e02101050e/cmd/metrics/exporter.go) | Earlier HTTP exporter without native Kubernetes authentication; useful history, not the proposed target fix |
| [`FRRouting/frr` 10.4.3, `6ddbeb5e`](https://github.com/FRRouting/frr/tree/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra) | C daemons and CLI JSON producers, used to establish candidate EVPN fields; verify fixtures against the chosen image's RHEL package |
| [`tynany/frr_exporter` v1.12.0, `85392e48`](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/bgp.go) | Exporter selected by the merged Ansible role; comparison baseline for coverage lost on replacement |
| Original EGA collection baseline, `5af03731` | Merged collection and source checks; no merged `image/` tree at that revision |
| [EGA main, `cbc7d43`](https://github.com/openshift/evpn-gateway-appliance/blob/cbc7d436e9836c51ee7f8b51c49bd9b533d93024/image/rhel10/Containerfile) | Image PR #6 merged 2026-10-23 at `be5a2b9a`; since then the image tree changed only by a Hadolint comment (checked 2026-10-29), while the emulated e2e lane (EGA #22) and the test-collection split (EGA #25) landed. It embeds FRR and node-exporter; its metrics unit is not installed/enabled. Source availability does not establish runtime qualification or approval of decisions 10/16 |
| Internal prototype `evpn-on-cloud` at `1c8e88873af8` (checked 2026-10-29) | Ships `tynany/frr_exporter` (BGP, L2VPN, BFD collectors) and node-exporter, `vtysh` health checks and dashboard and alert names in its task breakdown, but no alert rules or dashboards. Its checks go beyond this plan's rules in three places: the relay must have no VXLAN devices, WireGuard needs a recent handshake, and each stretch is pinged end to end. The task breakdown already plans replacing `frr_exporter` with `/frr-metrics` |

Upstream main `6be1ff9` (2026-10-28), the base of #519, has no `cmd/metrics`,
`internal/frr` or `internal/tlsconfig` change since `0d3197bb`, and none through `eec32ea` (2026-10-29); it builds with Go 1.27.3
(upstream [#514](https://github.com/metallb/frr-k8s/commit/76700f7e5fffc67ff6fa82d914ce73c041b39692))
and uses controller-runtime 0.25.1. Its integration fixtures select FRR 10.6.2, which
does not qualify the RHEL 10.4.3 payload.

The [ART 5.1 input at `7b8eb39d`](https://github.com/openshift-eng/ocp-build-data/blob/7b8eb39dbd3076ac757d0f811b72e7bed9997938/images/ose-frr.yml)
selects the release branch and RHEL 9 build for `openshift5/frr-rhel9`, with a
modification selecting `frr10`. A build-data declaration does not show customer registry availability; resolve the actual image once the change lands and builds. Repeat the prior
[binary/FIPS evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs) for that candidate.

### Files to change or preserve

| Path in frr-k8s / openshift/frr | Role and implementation boundary |
| --- | --- |
| `cmd/metrics/exporter.go` | Flags, handler construction, Prometheus registries, RBAC filter and TLS listener; first patch belongs here |
| `cmd/metrics/collector/{bgp,bfd}.go` and tests | Existing names, types, labels and fixtures; preserve existing series while adding coverage |
| `cmd/metrics/vtysh/{vtysh,bgp,bfd}.go` | Absolute vtysh executable, VRF discovery and local JSON queries; shared with the status controller |
| `internal/frr/parse.go` and tests | Shared parsed neighbor model; retain aggregate prefix values for current consumers while adding family data |
| `internal/tlsconfig/{tlsconfig,tlsopt}.go` | Certificate generation/reload and TLS parameters; `OptFor` also serves controller/statuscleaner code, so test shared-helper changes across callers |
| `cmd/metrics/liveness/` | Local daemon-presence handler; separate from Kubernetes auth and from forwarding health |
| `charts/frr-k8s/templates/{controller,service-monitor}.yaml`, `config/default/frr-k8s_auth_proxy_patch.yaml` | Existing HTTPS, service-account token and probe contract; defaults must remain compatible |
| `e2etests/tests/metrics.go` | Cluster-backed BGP/BFD scrape assertions; useful regression coverage, not a standalone scenario |
| Upstream `Dockerfile`, downstream `Dockerfile.openshift`, `Makefile` | Native build inputs; upstream image build names `cmd/metrics/exporter.go` explicitly, whereas downstream builds the package |

If production code is split into another Go file, update the upstream Dockerfile's
single-file build to build `./cmd/metrics`; otherwise `go build ./cmd/metrics` can
pass locally while the image build omits the new file. Do not change generation,
controller or Helm interfaces just to pass a standalone flag that Kubernetes
deployments do not need.

## Exporter startup and authentication

### Current behavior

The [exporter](https://github.com/metallb/frr-k8s/blob/0d3197bbe0090b88b4a106c222cc8c5118168138/cmd/metrics/exporter.go)
constructs its handler before the TLS server:

```text
main
  newMetricsHandler
    promHandler: BGP + BFD registry and default Go/process metrics
    rbacFilter
      rest.InClusterConfig
      rest.HTTPClientFor
      filters.WithAuthenticationAndAuthorization
  TLS configuration
  ListenAndServeTLS
```

`rest.InClusterConfig()` is unconditional in the baseline; the inherited
`--kubeconfig` flag and `KUBECONFIG` are not used. The filter delegates bearer-token
authentication to TokenReview and authorization to SubjectAccessReview: no token is a
401 and an authenticated request without permission a 403; an invalid token produced
500 in the inspected filter, so tests should preserve that rather than assume 401;
backend errors fail the request. The inspected dependency caches authentication for
one minute and authorization allow/deny for five minutes/30 seconds, so a cached
allowed scrape does not prove the review API is reachable: test backend failure with
fresh identities or a fresh filter. A custom
`--metrics-path` changes the authorized non-resource URL, which existing `/metrics`
RBAC does not cover. The `/livez` handler is outside the filter but on the TLS
listener, and the FRR queries use no Kubernetes client.

[Upstream #409](https://github.com/metallb/frr-k8s/pull/409), merged 2026-03-24 (merge
`a670e00`), introduced this path: HTTPS on `0.0.0.0:9141`, path
`/metrics`, TLS 1.3 minimum, and an in-memory self-signed certificate when no pair is
given. Downstream 4.22 predates it and serves plain HTTP on `127.0.0.1:7573` with no
native auth ([interim exporter](#interim-exporter-from-the-embedded-422-image));
substituting that binary changes the listener and security contract and does not
implement the change for the 5.1 target.

### First patch as submitted

Upstream #519 adds `--disable-metrics-auth` (default `false`). When set, `newMetricsHandler(disableAuth bool)` returns the Prometheus handler before calling `rbacFilter`; TLS and its defaults are unchanged, the default startup error without cluster config stays, and nothing falls back automatically on a configuration or authentication error. The "Starting exporter" log line gains a `metricsAuthDisabled` field (info level, hidden by the exporter's error-level logging). A short README section documents the flag, the dashboard reuse it enables and the access caveat. The PR has no dedicated unit test (the reviewer called one excessive); the injected-factory version is on fork branch `backup/disable-metrics-auth-ae39e72`.

### If upstream declines the flag

On #519 the lead maintainer doubted that frr-k8s should distribute `frr-metrics` for use outside the project and suggested "a separate project … generic enough to be consumed by multiple parties", fearing a different FRR configuration or metric set adding branches that frr-k8s CI cannot test. On 2026-10-29 an EGA teammate answered that no divergence is expected and a shared project is the fallback; there has been no reply. The exporter already exists twice, as metallb's `frr-tools/metrics` (`metallb_` names) and frr-k8s's `cmd/metrics` (`frrk8s_`). A similar metallb auth opt-out, [metallb#3086](https://github.com/metallb/metallb/issues/3086), was withdrawn without a maintainer reply.

| Option | Fit |
| --- | --- |
| Flag kept in frr-k8s, documented as unsupported outside a cluster | Cheapest; may still be refused |
| Out-of-tree exporter importing `cmd/metrics/collector` | Keeps the `frrk8s_*` names with no upstream support promise; `collector` has no API stability guarantee |
| Downstream carry of the flag in the Red Hat frr-k8s build | Support terms are open under decision 10; carry and rebase cost |
| New generic exporter consumed by frr-k8s and metallb | Removes the duplication; needs maintainer buy-in, an owner and a prefix-compatibility plan |
| Keep `tynany/frr_exporter`, the collection's current exporter | Per-AFI series and different labels and state values need a mapping; check its counter coverage first |

Next: ask 8 ([questions](#evidence-and-open-questions)); raise merging with metallb's
exporter only if a maintainer wants it. Meanwhile keep the 4.22 interim for BGP and BFD and
plan 5.x on one of the first three rows. If `frr_exporter` stays possible, write its
mapping into the `ega:` recording rules as a spec: the drafts join on frr-k8s's
`peer` and `vrf` labels and 0/1 state, so swapping exporters is not free.

### Access model beyond the first patch

| Option | Fit and cost |
| --- | --- |
| Loopback HTTPS with an authenticated host proxy or local scraper | A bounded development configuration, and a production candidate only with an owned access path; the proxy or scraper is more software to build, support and credential, and none is supplied by this change |
| Native mTLS | Good candidate if direct remote scraping is required: a client CA with `RequireAndVerifyClientCert`, issuance, rotation, revocation policy and wrong/missing/untrusted-certificate tests. Today's TLS flags configure only the server certificate |
| [Exporter-toolkit web configuration](https://github.com/prometheus/exporter-toolkit/blob/da538ec96a1e990f7891389c5264f81f0f69e9c8/docs/web-configuration.md) | Standard exporter approach with client-certificate and basic auth and request-time reload; node-exporter already supports it, so it would give both exporters one certificate model. Its format is labeled experimental and overlaps the existing TLS options: evaluate it, but keep it out of the initial patch |
| External kubeconfig with delegated Kubernetes auth | Still needs a reachable cluster, credentials and review-API permissions; not standalone |
| Automatic unauthenticated fallback or restoring the old HTTP exporter | Reject for this change: changes security on credential failure, or swaps in a different release contract |

Neither the 4.22 exporter nor slice 1 (server TLS with auth disabled) is a production
remote access mode: until mTLS or an approved proxy exists, nothing off the appliance
should scrape it. TLS trust must match the scraper's DNS or IP endpoint; a self-signed
start is a lab convenience, and scrape configurations must not set `insecureSkipVerify`.

### Adjacent findings to handle separately

These behaviors exist at upstream `0d3197bb`; each needs a focused patch and tests
rather than a broad rewrite. The `f62448f` WIP already fixes the incomplete pair, the
signal/shutdown lifecycle and the certificate-watcher error; the unbracketed IPv6
listener and server tests for supplied certificates remain.

- `tlsconfig.For` needs **both** cert and key; giving only one silently selects a
  self-signed certificate. Reject an incomplete pair before serving.
- The listener uses `fmt.Sprintf("%s:%d", address, port)`, so an unbracketed IPv6
  literal such as `::1` fails; use `net.JoinHostPort` and test IPv4, IPv6 and hostnames.
  The default `0.0.0.0` bind is dual-stack on Linux with `net.ipv6.bindv6only=0`
  (checked 2026-10-27: `*:` listener, `[::1]` scrape 200), so firewalls must cover both
  families.
- `vtysh.Run` uses `CombinedOutput`, so anything `vtysh` writes to stderr breaks JSON
  parsing. Without `/etc/frr/vtysh.conf`, FRR 10.6.2's `vtysh` exits 0 with valid JSON on
  stdout and a warning on stderr, and the scrape returned 200 with no `frrk8s_*` series
  (checked 2026-10-27). The same `Run` serves `/livez` and the status exporter.
  In-cluster deployments are unaffected because the Helm chart and CNO ship `vtysh.conf`
  into the shared `/etc/frr`, but failures there log only `exit status 1`. The EGA roles
  deploy `/etc/frr/vtysh.conf` on the host; a separate exporter container must see one
  too. A minimal fix ([`metrics-vtysh-stderr`](https://github.com/dfarrell07/frr-k8s/commit/917970c203eb3df630ca19bbedb8028aeaa63de3)) uses `Output()` and on
  failure adds stderr, or stdout when stderr is empty (vtysh prints unknown-command
  errors there), to the error; its tests fail on the current code, and it parsed the
  real 10.6.2 output. `frr_exporter` also keeps the streams separate.
- The `cmd/metrics` main package (`exporter.go`) has no tests at upstream `0d3197bb` (the `f62448f` WIP adds auth and server tests),
  and TLS tests cover option parsing only; supplied-certificate, hot-reload and
  client-trust behavior need targeted server tests when touched.
- With a supplied certificate, SIGTERM/SIGINT are captured for the certificate watcher
  but nothing stops the listener: a trusted-certificate probe kept running after
  SIGTERM while the self-signed control exited. This is proposed as a fix needed before
  appliance qualification (decision 19 is open); keeping the image's init process does not fix it. The Helm
  chart passes a certificate only when `tls.metricsTLSSecret` is set (default
  self-signed) and kustomize never does, while CNO always does; the chart and CNO set
  `terminationGracePeriodSeconds: 0`, which masks the hang; under systemd it waits for
  the stop timeout.
  Besides the WIP's larger rework, a minimal upstream fix ([`metrics-sigterm-shutdown`](https://github.com/dfarrell07/frr-k8s/commit/23d4584aa414740a2f297cf92dd33a2ba9a74dff)) passes the
  caller's context to
  `tlsconfig.For` and uses `ctrl.SetupSignalHandler()` with a bounded `srv.Shutdown`, the
  other frr-k8s binaries' idiom. It stopped in about 0.6 s with exit 0 in both
  certificate modes, against 15.6 s and SIGKILL before (checked 2026-10-27), and leaves
  the certificate watcher's error to a follow-up.

Lifecycle target (proposal): `main` owns one signal context shared with certificate watching. On SIGTERM or SIGINT it stops new requests, bounds active CLI work and shuts the listener down within the grace period. Test both certificate modes, idle and during a blocked CLI query; a SIGKILL is a failure. [controller-runtime 0.25.1's `Start`](https://github.com/kubernetes-sigs/controller-runtime/blob/67b72c2517be1d2b0dec612477eb20c3c959a8aa/pkg/certwatcher/certwatcher.go) can fail registration after its own 10-second retry without logging. Log that error and exit nonzero through the same shutdown path, and keep the last valid certificate on a transient reload error. Mount certificate directories, not single files, since atomic replacement leaves a file mount on the old inode.

## Collection semantics and failure behavior

### Existing series

The BGP collector emits session state, advertised/received prefix occupancy and
message counters by `peer,vrf`. The prefix series ending in `_total` are gauges: keep
that contract and never `rate()` them. UPDATE counters count messages, not routes.
Do not rename existing series or add labels to them in a compatible patch.

`ParseNeighbours` sums `addressFamilyInfo` across families: a synthetic IPv4-plus-EVPN
peer with 2+5 advertised and 3+7 received prefixes emits 7 and 10. To expose EVPN,
keep that aggregate and add per-family gauges labeled `peer,vrf,afi,safi`. Choose names
visibly different from the existing `_total` gauges, for example
`frrk8s_bgp_family_announced_prefixes` and `frrk8s_bgp_family_received_prefixes`, and
leave the final names to the slice 3 issue. FRR 10.4.3
uses the JSON key `l2VpnEvpn`; map known families explicitly, never treat a missing
family as zero, and test mixed-family and EVPN-only neighbors. Message counters belong
to the TCP session, so do not copy them onto each AFI/SAFI. FRR omits
`sentPrefixCounter` when a family has no update subgroup (as for the probe's
configured but down peer): omit only the new advertised gauge, keep received counts
and peer state, and keep collection successful, while still rejecting malformed data.

BFD emits state, control/echo packet counters, up/down events and zebra
notifications, also by `peer,vrf`, without local address, interface or
single-hop/multihop mode. The audit configured one established single-hop and two down
multihop sessions with different local addresses to one peer in one VRF: the registry
rejected the duplicate label
sets and `ContinueOnError` served HTTP 200 with a surviving down-state sample, which
misreports an established session.

FRR's session key is family, multihop flag, peer, local address, interface, VRF and
BFD name ([`struct bfd_key`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfd.h)).
Both the peers and counters JSON carry `peer`, `local`, `vrf`, `interface`,
`multihop` and the session `id`
([`_peer_json_header`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfdd_vty.c)),
but the exporter's counters struct keeps only `peer`. At 10.4.3 the header omits `local` for a zero
address and `vrf` and `interface` when empty, while upstream fixtures show
`"vrf":"default"`; treat a missing `vrf` as unknown, not `default`, and verify it on the
chosen image.
Retain the full identity in parsing and join peers to counters on the session ID (a correlation key, never a label) with the full key as a cross-check, never on peer address. Fail the collector on a duplicate key. A session present in only one read is a routine race: emit what is consistent and report the collector as partial. Either add `local`, `interface` and `multihop` labels to the existing BFD series with a release note, or add parallel session families; present both in the BFD identity issue. Test that every family has unique label sets and that success is false when the chosen contract cannot represent the data.

BFD's VRF discovery comes from BGP, so BFD-only VRFs are missed: a real 10.4.3 probe
showed a BFD session in a kernel VRF without BGP in the BFD CLI but in neither BGP
discovery command (a VRF with an L3 VNI did appear in BGP discovery, which must not be
generalized to BFD-only VRFs). The unfiltered bulk `show bfd peers json` and
`show bfd peers counters json` returned it with explicit VRF and session fields
([producer](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfdd_vty.c)
filters only when a VRF is given), which would also cut BFD to two commands. Test
sessions disappearing or recreated between the two reads, do not merge counters across
VRFs with the same peer IP, and qualify older supported FRR versions before changing
the default. BFD can be absent by design; alert only where sessions are expected.

### Failure visibility and deadlines

[Collectors](https://github.com/metallb/frr-k8s/tree/0d3197bbe0090b88b4a106c222cc8c5118168138/cmd/metrics/collector)
log vtysh and parse errors and emit nothing else, so `/metrics` can return 200 with
only Go/process series, or partial BFD data when the counters read fails after state
was emitted (both observed). `promhttp_metric_handler_errors_total` catches gathering
and encoding errors, including duplicate metric sets, but not errors a collector only
logs; it increments after gathering, so the failing response can still carry the
previous value
([`client_golang` v1.24.0](https://github.com/prometheus/client_golang/blob/48dd383f94cc36bb0179724166383effd9f64847/prometheus/promhttp/http.go)).

Add a small status contract in node-exporter style: a wrapper collector emitting, for
example, `frrk8s_scrape_collector_success{collector}` and
`frrk8s_scrape_collector_duration_seconds{collector}` (names for review), or a const
`collector` label per collector, since
[separate collectors cannot register identical descriptors](https://github.com/prometheus/client_golang/blob/48dd383f94cc36bb0179724166383effd9f64847/prometheus/registry.go).
Test registration and gathering with BGP, BFD and EVPN enabled together.
Emit status for every enabled collector, distinguish an empty successful read from a
failed one, and count success only when every read, schema check and identity check
passed. Build each collector's result completely before emitting it, so a failed BFD
counters read cannot leave success with half the data; independent collectors still
report when another fails, under the handler's existing partial-response policy. Alert
on exporter `up` and on required collector status being present and valid.

`vtysh.Run` has no deadline, and the server's 3-second `ReadTimeout` bounds only request
reads. Bound admitted scrapes with promhttp's `MaxRequestsInFlight` (503 on excess,
without a queue or cache), set to at least the number of scrapers: OpenShift runs two
Prometheus replicas, so a limit of 1 would reject a scrape whenever the two overlap.
Test two simultaneous scrapers. Its `Timeout`
does not cancel gathering, and `Collector.Collect` gets no request context, so derive
one collection budget from the exporter's lifecycle context and share it across
discovery and CLI reads; per-command limits must fit within it. Use `CommandContext`
with bounded output, explicit timeout errors and a finite `Cmd.WaitDelay`: cancellation
kills only the direct process, `Wait` can otherwise outlast the deadline while a
descendant holds a pipe, and `WaitDelay` does not kill descendants, so test cleanup for
any CLI path that spawns children. Apply the same bounds to `/livez`'s `show daemons`,
which runs outside the admission limit and authentication, keeping its response
meanings, and keep a default wrapper for the status controller or update and test both
callers.

VRF discovery runs `show bgp vrf all json`, dumping routes to get VRF names, at least
three times per scrape. [Upstream #507](https://github.com/metallb/frr-k8s/pull/507)
(head `f70dd12`, open on 2026-10-29) switches to `show bgp vrfs json` with a matching
parser; reuse it if merged rather than swapping only the command, then consider one
shared per-scrape VRF list, avoiding a background cache unless measurements justify
one.

### Liveness has a narrower meaning

`/livez` runs `show daemons` and expects zebra, bgpd, watchfrr, staticd and bfdd: a
command failure is 500 and a missing daemon 404. Success proves neither peering nor
forwarding; keep the Kubernetes probe behavior rather than an always-successful process
probe. The appliance's `bgpd=yes`/`bfdd=yes`
daemons file does not necessarily stop zebra or staticd: FRRouting 10.4.3's
[`daemon_list`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/tools/frrcommon.sh.in)
forces zebra, staticd and mgmtd on when available. Check the packaged script and the
real daemon list; if supported appliances intentionally omit BFD or staticd, separate
liveness from a configured readiness policy rather than weakening cluster probes.

## EVPN data sources and proposed metric contract

### What FRR 10.4.3 actually exposes

The evidence is the JSON-producing C code
([`zebra_evpn.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra/zebra_evpn.c), [`zebra_vxlan.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra/zebra_vxlan.c),
[`zebra_evpn_mac.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra/zebra_evpn_mac.c), [`zebra_evpn_mh.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra/zebra_evpn_mh.c),
[`zebra_vty.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/zebra/zebra_vty.c), [`bgp_vty.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bgpd/bgp_vty.c),
[`bgp_evpn_vty.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bgpd/bgp_evpn_vty.c)) plus real output, not guessed command
output. Topotest expected JSON can be a partial match, so a fixture alone is not a
schema; confirm parsers against the exact RHEL payload.

| Command | Verified shape / meaning | Consequence for the collector |
| --- | --- | --- |
| `show evpn json` | Global object with `numVnis`, `numL2Vnis`, `numL3Vnis`, duplicate-detection configuration and multihoming details; disabled EVPN can return `{}` | Useful capability/context observation; do not interpret `{}` as an enabled appliance with every metric zero |
| `show evpn vni json` | Object keyed by VNI; L2 entries contain `vni`, `type`, `vxlanIf`, `tenantVrf`, `numMacs`, `numArpNd`, numeric `numRemoteVteps`, optional `remoteVteps` array of IP strings | Best first bulk source for VNI inventory and counts; a known zero-MAC VNI still has an entry |
| Same command, L3 entry | `numMacs` counts router MACs, `numArpNd` counts next hops, and `numRemoteVteps` is the string `"n/a"` | Distinguish VNI type and semantics; omit unsupported remote-VTEP measurement rather than invent zero or port the legacy `-1` sentinel |
| `show evpn vni <vni> json` / `show evpn vni detail json` | Single object / array of detailed objects. L2 uses `vxlanInterface`, and `remoteVteps` entries are objects with `ip,flood`; L3 detail has a state | Do not reuse the summary struct blindly or invent a common L2 `state` field. Prefer the summary before adding per-VNI detail queries |
| `show bgp l2vpn evpn vni json` | Top-level global metadata alongside VNI-keyed objects with string-valued `inKernel` (`"True"`/`"False"`), type, RD/RTs and originator fields | Do not decode every top-level key as a VNI. Describes control-plane knowledge and kernel presence, not end-to-end VNI health |
| `show evpn mac vni all json` | VNI-keyed MAC maps, omitting zero-MAC VNIs; entries have `type` of `local`, `remote` or `auto`, sequences, duplicate flags and forwarding metadata | Useful for optional local/remote/duplicate aggregates, expensive at scale. Do not publish MAC/IP/sequence as time-series labels |
| `show evpn es detail json` | Array of segment objects with `esi`, optional `accessPort`, `flags`, `dfPreference`, counts and remote VTEP details | Candidate local ES/DF metrics; require `local` applicability and the explicit flags (`local`, `df`, `nonDF`, `operUp`). A remote-only segment without `nonDF` is not evidence that this appliance is DF |

FRR 10.6.2's real `show evpn vni json` matched this on 2026-10-27 (numeric L2
`numRemoteVteps`, `"n/a"` for L3, the same keys, plus additive `vlan` and `bridge`);
`show bgp l2vpn evpn vni json` still mixes global keys with VNI-keyed objects and
reports `inKernel` as a string.

The summary avoids serializing every MAC but is not constant cost (`num_valid_macs`
walks the table, excluding internal auto-only entries), and FRR calls the full MAC
commands expensive at scale. Benchmark expected VNI/MAC counts, JSON size and daemon CPU
before choosing intervals; a local/remote split at high scale may need a FRRouting
summary enhancement, which is a C/RHEL-package delivery path, not an openshift/frr Go
patch.

### Proposed additive metrics

Names are proposals. Keep the `frrk8s` namespace, gauges for occupancy and state,
fixed labels and additive compatibility. Start an EVPN collector disabled by default so ordinary
BGP-only deployments do not query unsupported/unused EVPN commands. Enable it
explicitly for the required appliance role after capability qualification.

| Proposed series | Labels / type | Meaning and limits |
| --- | --- | --- |
| `frrk8s_evpn_vni_info` | `vni,vrf,type,interface`; gauge 1 | Observed inventory, not expected inventory or health. Keep descriptive interface labels on info rather than every measurement |
| `frrk8s_evpn_macs` | `vni,vrf`; gauge, L2 only | L2 valid MAC occupancy; omit for L3 VNIs rather than mixing router MACs into the same measurement |
| `frrk8s_evpn_neighbors` | `vni,vrf`; gauge, L2 only | L2 ARP/ND occupancy; L3 next hops require their own future family |
| `frrk8s_evpn_remote_vteps` | `vni,vrf`; gauge | L2 known remote-VTEP count, not reachability. Omit when not applicable |
| `frrk8s_evpn_remote_vtep_present` | `vni,vrf,vtep`; gauge 1, optional | Membership for expected-specific-VTEP checks; bounded by configured VNI/peer scale and emitted only if that requirement needs it |
| `frrk8s_evpn_es_df` | `esi`; gauge 0/1 for applicable local ES | Local DF role; do not infer per-VNI role from an ES-wide flag or report every non-DF as failed |
| `frrk8s_evpn_es_oper_up` | `esi`; gauge 0/1 | Local segment operational state from verified flags; absence, remote-only ES and bypass require explicit handling |
| Collector status/duration | fixed `collector`; gauges | Completeness and cost of the enabled collector; alerts need these alongside exporter `up` |

Start with L2-only occupancy and a VNI info family that identifies both types; skip only
unsupported L3 measurements, keeping mixed parsing and collector status valid, and never
fail a whole appliance because an L3 VNI is present. Add the per-family prefix gauges
independently of this collector, since a route relay needs them without local VNIs. Use
pointer fields or presence checks so Go zero values never turn an absent field into
healthy state; tolerate unknown fields but reject malformed required ones, mismatched
VNI keys, invalid ranges and wrong types. Test `{}`, `[]`, missing optional arrays,
mixed L2/L3, unknown commands, warning text with exit status 0, truncated JSON, one
failed subquery and a disappearing VNI.

### Learning, reachability and DF need honest semantics

MAC occupancy over time is a useful learning view, but `rate()` of it is not a
learning-event rate, sampling misses intermediate moves, and per-MAC sequence numbers
and duplicate-detection counts are not a global mobility counter. True learn, withdraw
or move rates need a defined source counter with known reset behavior. Keep per-MAC
diagnostics in on-demand FRR commands, not labels.

A known remote VTEP or an established session does not prove the VXLAN data path, and
BGP next hops can differ from peers through a relay. Name VTEP alerts after their
actual signal: missing expected membership, a mapped BFD session, an interface failure
or an explicit data-plane probe, and choose a supported latency source rather than
making latency a side effect of the exporter patch. FRR 10.4.3's BFD
`rtt-min/avg/max` are echo samples in microseconds that the exporter currently
discards; they report zeros with no samples, and `_display_rtt` in [`bfdd_vty.c`](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfdd_vty.c) starts the minimum
at 1000 µs, which caps a larger true minimum. Check the
[`bfd_packet.c` sampling path](https://github.com/FRRouting/frr/blob/6ddbeb5eaf71bc5a3f05f22e211684fb85a34091/bfdd/bfd_packet.c) and the selected RHEL package's
patched source before proposing RTT gauges; missing samples must never read as zero
latency.

DF role changes are legitimate failover. Alert only against the intended local ES/HA
policy with convergence time, coverage checks and all expected participants; summing
DF gauges from visible nodes cannot prove a single DF when one is unobserved. Account
for bypass, startup delay and administratively down segments before defining a
zero- or multiple-DF alert. DF also needs the multihoming and HA work of CORENET-7502
and 7503 to exist.

### Legacy migration contract

The v1.12.0 L2VPN collector is off by default. It runs BGP L2VPN EVPN session and prefix collection plus `show evpn vni json`, and provides aggregate MAC, ARP/ND and remote-VTEP gauges (`bgp_l2vpn_evpn_*_total`, gauges despite the suffix) labeled `vni,type,vxlanIf,tenantVrf`; remote-VTEP uses `-1` for nonnumeric output. It does **not** provide DF metrics, per-MAC mobility events or VTEP reachability. Its [common collector](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/collector.go) exposes collector success/duration and a socket timeout (default 20 s); its optional [vtysh wrapper](https://github.com/tynany/frr_exporter/blob/85392e48b7b85c243298f23faf0a92821a7f7a28/collector/command.go) adds its own timeout; preserve that visibility when replacing it.

Migration tests compare intended meanings, not legacy names, sentinels or mislabeled
`_total` gauges. Inventory existing dashboards and rules before removing the old
exporter; the merged EGA collection had none at `cbc7d43`.

## Runtime, image and collection integration

### Preferred appliance candidate

Run the exporter as its own container **from the same pinned FRR image**, command
`/frr-metrics`, keeping the image's tini entrypoint. That keeps the image's vtysh, RHEL
users, glibc and binary provenance while separating the exporter's lifecycle from
routing. It is a runtime proposal under decisions 10 and 16, not an approved unit, and
adds no health-check container (CORENET-7505 asks for Ansible health checks without an extra container). The concrete design is
under [proposed units](#proposed-units-ownership-and-e2e-checks).

The exporter needs no routing capabilities or the router's network namespace, since it
talks over Unix sockets; test it with no capabilities, a read-only root, a non-root
image user, only the needed socket, configuration and certificate mounts and an
explicit bind address, under SELinux enforcing, and validate both host reachability and
the absence of unintended remote reachability. A private namespace
needs a container-reachable listener published to host loopback (a container-loopback
listener was unreachable through the published port in the audit); host networking
binds host loopback directly; qualify any approved remote bind separately. Socket
access as `frr`/`frrvty` grants full runtime configuration of every FRR daemon (vtysh
has no read-only role), so an exporter compromise is a routing compromise: a read-only
mount does not limit it, the exporter's small input surface (an HTTP server issuing
fixed commands with no request-derived arguments) is the control, and it needs a
threat-model entry. Derive socket ownership and permissions from the image instead of
relying on a world-writable directory. Two containers with independent private `:Z`
relabels of one directory break each other; do not solve that by copying
`--privileged` or disabling SELinux labeling.

| Alternative | Assessment |
| --- | --- |
| Host-extracted exporter | Needs compatible libraries, a host `/usr/bin/vtysh`, socket permissions and matching architecture; the embedded design has no host FRR RPM |
| `podman exec frr /frr-metrics` | Harder to supervise independently; prove signals, orphan cleanup and FRR recreation first |
| Wrapper backgrounding the exporter with FRR | Couples routing and metrics lifecycles; avoid an ad hoc multi-process entrypoint |
| Host FRR package plus host exporter | Changes the embedded-container direction; needs the payload decision, library/FIPS checks and lifecycle validation |

### Interim exporter from the embedded 4.22 image

The FRR image the appliance already pins (`openshift4/frr-rhel9@sha256:82fd7cc0…`,
`v4.22.0-202609221726.p2.g1277b23`, a manifest list for amd64, arm64, s390x and ppc64le)
contains a `/frr-metrics` that needs no cluster. Its flags are `--metrics-bind-address`
(default `127.0.0.1`), `--metrics-port` (default `7573`), `--metrics-path` and an unused
`--kubeconfig`; it serves plain HTTP with no TLS or auth. Its collector sources,
`liveness.go` and `internal/frr/parse.go` are byte-identical to upstream main `6be1ff9`,
and `vtysh/vtysh.go` differs only by a `#nosec` comment, so the series names and
`peer`/`vrf` labels match the 5.x exporter; within the shipped code only `exporter.go`
(listener, TLS, auth) differs. The image ships RHEL 9.8, `frr10-10.4.3-3.el9_8.2`,
`/usr/bin/vtysh`, user `frr` (998:997, also in `frrvty`) and an empty
`/etc/frr/vtysh.conf`; the exporter is built with Go 1.25.14 and `strictfipsruntime`.

Checked 2026-10-27 in rootless containers: two routers from that image with eBGP,
BFD and L2VPN EVPN, plus one unreachable peer; the exporter in a separate container
from the same image, `--user frr`, `--cap-drop all`, `no-new-privileges`,
`--read-only`, sharing only the router's `/var/run/frr`, with effective, permitted and
bounding capabilities all zero.

| Case | `/metrics` | `/livez` |
| --- | --- | --- |
| Routers up | 200, 21 `frrk8s_*` families (13 BGP, 8 BFD) with one sample per peer, up 1 for the live peer and 0 for the dead one; prefix gauges summed across families | 200 |
| Router stopped, socket files left | 200, no `frrk8s_*` series, log `exit status 1` | 500 |
| Router restarted | Series recover | 200 |
| No `/etc/frr/vtysh.conf` | 200, **no `frrk8s_*` series** (`invalid character '%'`) | **200** |
| `podman stop` | Exits in about 0.3 s (no graceful-shutdown handler) | |

This allows BGP/BFD collection, dashboard development and an e2e scrape without
slice 1; it is an interim, not the target. The listener is plain HTTP with no authentication, so it belongs only on
host loopback, where every host process, every host-network container (the router,
node-exporter) and every SSH user can still read it and, because 4.22 has no admission
limit, make each request run several vtysh commands against bgpd. The collector defects
above (summed families, BFD identity, silent collection failure) apply unchanged; and
every later release branch (release-4.23, release-5.0 to release-5.2) requires
in-cluster config. `registry.redhat.io/openshift4/frr-rhel9` has tags up to v4.22.
Later builds include three rebuilds of the same source and
`v4.22.0-202610241138.p2.g943578e`, whose source changes only Go and protobuf. The
floating `v4.22.0` and `v4.22` tags move with each build, so pin by digest. Decide who
advances the pin, how often and against which scanner. Using it needs:

- the interim-source answer under decision 16 (the
  [Observability](kickoff-decisions.md#gate-c-stage--trial-publication) gate lists the
  4.22 binary as an option);
- the payload answer under decision 10 (open); and
- Product Security's view on running an OpenShift 4.22 payload component (CPE
  `cpe:/a:redhat:openshift:4.22::el9`, RHEL 9 userspace) inside a RHEL 10 bootc
  product: errata ownership, whether the bootc SBOM enumerates the nested image, and
  FIPS validity of the whole container's crypto on a RHEL 10 FIPS host (the exporter
  itself does no crypto but must start under `fips=1`).

Not yet checked on a real appliance: SELinux enforcing, bootc
systemd lifecycle, FIPS mode and the 4.22 lifecycle dates against the appliance's
support window.

### Concrete EGA integration work

At EGA main `cbc7d43`, `frr-container.service` runs the embedded FRR and nothing
installs or enables `frr-metrics.service`, an unused file that expects
`/usr/bin/frr-metrics` and orders after `frr.service`, a different unit. The emulated e2e
lane (`test/e2e`, #22, CORENET-7508) sets `frr_exporter: false` and defers metrics
validation to this story. The monitoring role looks for `frr-exporter.service` and
otherwise runs the legacy container, so renaming only the image unit would start a
second exporter. The FRR handlers in `evpn_onprem_appliance`, `evpn_cloud_workload` and
`evpn_cloud_infra` restart `frr-container.service` when present and otherwise fall
back to Podman with `frr_image`, which cannot keep the same-image router/exporter
pairing; template notifications flush before monitoring deploys, so make
configuration-triggered restarts cover the exporter and test that, since a first
scrape alone misses the mismatch.

Agree one image/collection contract: unit and container names, which side owns
configuration, flags, port, path, restart dependencies, user, socket and certificate
locations, logs and scraped labels. Put image-owned units in the vendor location and
Ansible-owned overrides in local locations, per the
[Containerfile contract](containerfile-refactor-spec.md). Migrate
`ansible/roles/evpn_monitoring` (including its `/var/run/frr` mode 0775 task, which conflicts with the proposed `tmpfiles.d` ownership) and its README with the inventory examples,
`ansible/README.md` and teardown; reject unsupported modes before touching the host,
retire the legacy container without stopping the new runtime, keep idempotence, and
verify from the built collection. On disable, stop both exporters' units and remove
their containers; skipping tasks leaves them running.

At `cbc7d43`, `deploy.yml` applies monitoring to all three host groups while
`teardown.yml` removes exporter containers only on-prem; EGA
[#23](https://github.com/openshift/evpn-gateway-appliance/pull/23) (CORENET-7515, open)
removes the `cloud_workload` play from `deploy.yml` (the roles move to the test
collection) and leaves `teardown.yml` unchanged, so recheck the production groups after it lands. Teardown must stop each
owning service before removing its container, since `Restart=always` recreates it, cover
every group and remove only resources this deployment owns; test teardown and redeploy
per group. `After=` orders startup only: it does not mean FRR is ready or restart the
exporter when the router is recreated. Test start before configuration, late FRR
readiness, FRR crash and replacement (including runtime-directory replacement), exporter
crash, role-notified restart, reboot, upgrade, rollback and scrape recovery. A binary
hash in smoke evidence is not a scrape, and a flag in source is not proof the pinned
image has it: verify `/frr-metrics --help`, startup and series for every target-platform
binary of the approved digest, keeping provenance, SBOM and FIPS evidence, and never
copy an upstream statically built development binary into a release image.

### Proposed units, ownership and e2e checks

Proposed and not run on an appliance; the directives were checked rootless on a Fedora
host with SELinux enforcing, Podman 5.8.8 and systemd 258 on 2026-10-27. The
appliance is rootful and RHEL 10 ships systemd 257, so repeat the checks there,
including whether a confined `container_t` exporter can connect to sockets created by
the `spc_t` router.

On main, use a raw unit like `frr-container.service`; if the image moves to Quadlet,
port both units together, since the router's unit name and every dependency change. A
sketch for `/usr/lib/systemd/system/frr-metrics.service` (main still installs units in
`/etc/systemd/system`; the vendor path follows the
[Containerfile contract](containerfile-refactor-spec.md)):

```ini
[Unit]
Description=FRR metrics exporter (same image as frr-container)
BindsTo=frr-container.service
After=frr-container.service

[Service]
Restart=always
RestartSec=10
SuccessExitStatus=143
ExecStart=/usr/bin/podman run --pull=never --rm --replace --name frr-metrics \
    --log-driver=none --network host --user frr --cap-drop all \
    --security-opt no-new-privileges --read-only \
    -v /run/frr:/var/run/frr:ro \
    frr:embedded /frr-metrics \
    --metrics-bind-address=127.0.0.1 --metrics-port=7573
ExecStop=/usr/bin/podman stop --ignore -t 10 frr-metrics
```

- Enable it with an image-owned link,
  `/usr/lib/systemd/system/frr-container.service.wants/frr-metrics.service`, not
  `systemctl enable` (which writes into `/etc`), and drop the unused unit.
- `BindsTo=` with `After=` carried stop, restart and a SIGKILL crash-restart of the
  router to the exporter; `PartOf=` added nothing, and without `After=` the exporter
  can start before the runtime directory exists.
- `SuccessExitStatus=143` stops every router restart from recording a failure, since
  the unfixed exporter in self-signed mode has no signal handler (check tini returns 143; the SIGTERM fix exits 0); `--log-driver=none`
  avoids duplicate journal lines.
- `--user frr` resolves from the image even with `--read-only`; keep tini, no
  `--userns` (the socket permissions rely on a shared UID), host networking, no
  `/livez` healthcheck (it returns 200 on an empty scrape), the image's own
  `vtysh.conf`, and no `z`/`Z` on the exporter's mount.
- With `Type=simple`, systemd's kill reaches only the Podman client, so a failed
  `ExecStop` orphans the container until the next `--replace`; a Quadlet port would
  use `Type=notify` with `--sdnotify=conmon`.

With explicit bind and port flags the endpoint is the same address and port for 4.22 and
5.x, but the scheme changes from HTTP (4.22) to HTTPS (5.x, which also needs the slice 1
flag or [an alternative](#if-upstream-declines-the-flag), and its TLS settings), so the
e2e check and any scrape configuration take the scheme as a variable.

Two router-unit changes are prerequisites:

- Its `-v /var/run/frr:/var/run/frr:Z` mount locks a confined exporter out (`EACCES`); only a shared label connected. A plain `:z` (`container_file_t:s0`) lets any confined container that bind-mounts the directory reach it, including a rootless one, so land it only with tighter ownership (an image-owned `tmpfiles.d` entry `d /run/frr 0750 998 997`) or a fixed shared MCS level on both containers (`label=level:s0:cN,cM`). Never use `label=disable`; revisit when the router stops running privileged.
- Its `RuntimeDirectory=frr` uses mode 0777, which lets any local user replace the
  `*.vty` sockets and is not yet recorded in
  [source-audit.md](source-audit.md#1-security--identity-findings); systemd resets it on
  every start and removes it on stop. Replace `RuntimeDirectory=` with the `tmpfiles.d`
  entry above, after confirming 998 and 997 are unallocated on the host (or reserving
  them with `sysusers.d`), and keep the router's shared relabel, since tmpfiles creates
  the directory as `var_run_t`. `BindsTo=` recreates the exporter when the directory is
  replaced; a running container otherwise keeps the deleted one.

Both containers use `frr:embedded`, which `payload-load.service` re-tags from the
deployment's `/usr` image cache on every boot, so an upgrade or rollback keeps them
paired. If `payload-load` fails, for example on a full disk since each upgrade copies
the full image, both stay down; assert in the upgrade and rollback e2e that both
containers report the same image ID.

Proposed for the collection: replace `monitoring.frr_exporter` with a
`monitoring.frr_metrics` switch that requires `frr-metrics.service` in `service_facts`
and has no Podman fallback (the e2e inventory's `frr_image` is community
`quay.io/frrouting/frr:10.5.3`, which has no `/frr-metrics`). This changes the
collection's public variables, so treat it with the collection API decisions. Fail
with a migration message if the old variable is set and remove any leftover legacy
container idempotently. Disable the exporter with `systemctl mask --now`: masking
fails while the unit file is in `/etc/systemd/system`, so it needs the vendor path,
and a mask survives upgrades but not a rollback past the deployment it was made in, so
the role reapplies it on every run and uses `unmask` to re-enable. The FRR handlers
restart `frr-container.service`, and `BindsTo=` carries that to the exporter.

| Work item | Story in [delivery-plan.md](delivery-plan.md) | Note |
| --- | --- | --- |
| Slice 1 upstream (#518, #519) | CORENET-7499 lists it; this plan tracks it for 7504 | Asks 2 and 8 |
| Image unit and router-unit fixes | Neither | Draft PR now; merging per the [status table](#status-and-next-steps) |
| Role swap, variable migration, teardown | CORENET-7499 (unassigned) | Ask 2 |
| e2e metrics scrape | CORENET-7504 (the 7508 row and `test/e2e/README.md` defer it) | |
| Rules, dashboards, alerts | CORENET-7504 | Rules PR now; dashboards wait on the PM answer |

A proposed order: (1) image unit, router-unit fixes and a 7573 scrape in
`image/tools/smoke-nested.py`; (2) the role migration with teardown for every group,
after EGA #23 lands; (3) e2e checks; (4) the 5.x payload switch once slice 1, or
[an alternative](#if-upstream-declines-the-flag), and its downstream build exist.
CORENET-7678's parked runtime work (closed EGA #21; its branch is not public) also
edits these image files and must be rebased before either lands.

In the e2e lane, the job [openshift/release#87688](https://github.com/openshift/release/pull/87688)
(merged 2026-10-29, head `3250ff5`) bakes `ocp/4.22:metallb-frr` into the appliance as
`FRR_IMAGE`; confirm it is the same build as the pinned `frr-rhel9` with
`/frr-metrics -h`. Enable the switch in `test/e2e/inventory/group_vars/all.yml` (and fix its
Quadlet comments, since the image ships raw units). First tighten the existing `HEALTH: FRR
container is running` check, whose `name=frr` filter and substring test also match a
`frr-metrics` or `frr_exporter` container. Then add
a task to `evpn_health_check` that polls the exporter (`http://127.0.0.1:7573/metrics`
for 4.22) until each expected peer's `frrk8s_bgp_session_up` is 1 and the `frrk8s_*`
set is not empty. Add restart and exporter-kill recovery checks to the harness rather
than the shipped health check. The nested lane does not prove SELinux enforcing; that
needs the real AMI.

### Scraping, expectations, dashboards and rules

Principles that hold whichever scraper is chosen:

- A cluster ServiceMonitor for frr-k8s does not discover external appliances. Agree
  the external-target mechanism, network path, CA, server name, client credentials,
  rotation and job labels before writing a scrape configuration; keep credentials out
  of rule and dashboard sources, and never give the appliance Kubernetes API access
  just to be scraped.
- Join on the appliance identity labels (below), not `instance`, whose port differs
  per exporter; keep job and instance for provenance and define duplicate-target
  behavior. The relay is not expected to have VXLAN devices or local VNIs, so the
  deployment topology (not yet approved; [networking-spec.md](networking-spec.md) records only lab
  and test topologies) and enabled role decide which panels and
  alerts apply.
- Observed inventory cannot show what vanished before the scrape, so compare against a
  declared expected set derived from validated deployment configuration, with its
  update, removal and freshness owned. A global `absent()` does not enumerate per-peer
  or per-VNI omissions, and
  [comparisons against zero do not detect absent series](https://prometheus.io/docs/prometheus/latest/querying/operators/#comparison-binary-operators).
  Keep exporter down, collector failed, expected object missing and object observed
  down distinct, and include a successful scrape with required status omitted in the
  rule fixtures.
- Layer dashboards: appliance, service and interface state; BGP per family and BFD;
  VNI, MAC and segment observations; DX, VPN and explicit probes. Show unavailable data
  as unavailable, not zero. Set thresholds and convergence timers with the owner. Test
  healthy, failure, missing series, partial collection,
  counter reset, maintenance and intentional removal, failover and recovery with the
  [native promtool contract](pipeline-spec.md#metrics-corenet-74997504); notification
  delivery and runbooks need a live check beyond rule evaluation.

### Where metrics are scraped and shown

Checked 2026-10-27; support statements come from Red Hat documentation and need
confirmation from the owning teams.

- OpenShift monitoring cannot use `ScrapeConfig`: the Cluster Monitoring Operator
  sets `scrapeConfigSelector: null` for user-workload Prometheus on
  [release-4.22](https://github.com/openshift/cluster-monitoring-operator/blob/7e452df90f68a0fcd9203300ef9e43ad274338cb/assets/prometheus-user-workload/prometheus.yaml)
  and [main](https://github.com/openshift/cluster-monitoring-operator/blob/5874161568c13df53cea7442b5b622ebaf308fc9/assets/prometheus-user-workload/prometheus.yaml),
  removes the `ScrapeConfig` CRD and its RBAC from the operators it deploys, and its
  config map has no additional-scrape-config field. `Probe` objects are reconciled
  but the [4.22 support page](https://docs.redhat.com/en/documentation/monitoring_stack_for_red_hat_openshift/4.22/html-single/support_for_monitoring/index)
  lists them, and any configuration outside the config map reference, as
  unsupported.
- The remaining in-cluster route to an external target is a user-workload
  `ServiceMonitor` on a Service without a selector, with manual endpoints. That
  Prometheus discovers with the Endpoints role by default; prefer a manual
  EndpointSlice (labels `kubernetes.io/service-name` and
  `endpointslice.kubernetes.io/managed-by`) with `spec.serviceDiscoveryRole:
  EndpointSlice` on the ServiceMonitor, since the Endpoints API is deprecated from
  Kubernetes 1.33 (a manual `Endpoints` object still works through mirroring). Creating
  either needs RBAC beyond the default `edit` role. Red Hat documentation does not
  describe this pattern, so its support status is unknown.
- The scrape leaves user-workload Prometheus pods on the default network. Without route
  advertisement it is SNATed to the node IP; when the default pod network is advertised
  with `RouteAdvertisements`, as on EVPN clusters, it leaves with the pod IP
  ([OVN-Kubernetes](https://github.com/ovn-kubernetes/ovn-kubernetes/blob/98bd8874f9dc6c881680291746ea10f235585542/docs/features/bgp-integration/route-advertisements.md)),
  and an EgressIP for the monitoring namespace changes it again. The appliance's
  listener and firewall must allow whichever source applies and route the reply back;
  appliance addresses reachable only inside a CUDN or EVPN VRF are unreachable from the
  default network. The CMO NetworkPolicy allows all egress, but an EgressFirewall or
  AdminNetworkPolicy may not, and scrapes do not use the cluster proxy. Two
  user-workload Prometheus replicas each scrape every target, so propose an interval of at
  least 30 seconds, and keep the exporter's collection budget below the scrape timeout
  and the rate windows valid at that interval.
- User-workload Prometheus enforces a `namespace` label and overrides honored labels,
  so appliance series land in the ServiceMonitor's namespace, separate from the
  platform-scraped frr-k8s and OVN-K series. Both are visible through Thanos Querier;
  a rule that joins them needs that namespace in `namespacesWithoutLabelEnforcement`.
  Rules labeled `openshift.io/prometheus-rule-evaluation-scope: leaf-prometheus` run in
  user-workload Prometheus; others run in Thanos Ruler through Thanos Querier. Alerts from
  both go to the platform Alertmanager by default; `enableUserAlertmanagerConfig` lets
  `AlertmanagerConfig` objects in user namespaces add routes there, and enabling the
  user-workload Alertmanager sends user alerts to it instead. Configure inhibitions in
  whichever is chosen.
- The Cluster Observability Operator's MonitoringStack (GA in COO 1.5) selects
  `ScrapeConfig` objects (`monitoring.rhobs/v1alpha1`) in its source, but its API
  reference and release notes do not document them. A MonitoringStack is not behind
  Thanos Querier, so its dashboards need their own Perses data source and cannot join
  cluster frr-k8s series. It also documents remote-write and OTLP receivers, which
  would let an appliance push instead of being scraped; its `webTLSConfig` has a server
  certificate, key and CA but no client CA, so exposing a receiver needs a route
  and an authenticating proxy.
- Grafana was removed from OpenShift monitoring in 4.11 ([KCS 4605641](https://access.redhat.com/solutions/4605641)). COO 1.5 made Perses dashboards GA, with a Grafana JSON import tool ([release notes](https://docs.redhat.com/en/documentation/red_hat_openshift_cluster_observability_operator/1-latest/html-single/red_hat_openshift_cluster_observability_operator_release_notes/index)). Its default data source is the cluster-wide Thanos Querier, so non-admin viewers need `cluster-monitoring-view` or a namespace-scoped data source. ACM observability does not scrape external targets; it federates allowlisted user-workload series from each managed cluster and ships a Grafana that accepts custom dashboards, so it layers on the first option below. Confirm with the PM whether ACM is in scope.
- DX state is in CloudWatch at 5-minute intervals by default (`ConnectionState`,
  `VirtualInterfaceBgpStatus`); VPN `TunnelState` has no verified interval. Bringing them into Prometheus needs a
  community exporter (YACE or `cloudwatch_exporter`) with AWS credentials and API
  cost; the alternatives are CloudWatch alarms or a Grafana CloudWatch data source.
  None covers on-prem.

| Option | Fit | Main risk |
| --- | --- | --- |
| User-workload `ServiceMonitor` with manual endpoints, Perses dashboards, `PrometheusRule` alerts | Only path built from documented components; appliance series are queryable with cluster frr-k8s and OVN-K series through Thanos Querier; `ServiceMonitor` TLS takes a CA, server name and client certificate from Secrets, fitting native mTLS | External-endpoint pattern support unconfirmed; manual endpoints and extra RBAC; joins with platform series need `namespacesWithoutLabelEnforcement`; the scrape can ride the transport it monitors |
| COO MonitoringStack with `ScrapeConfig` static targets | Documented stack with full TLS options | A second Prometheus and Alertmanager to own; `ScrapeConfig` is `v1alpha1` and undocumented; dashboards need a separate data source and cannot join cluster series |
| ACM observability on top of the first option | Multicluster view and retention; a shipped Grafana for custom dashboards | Requires ACM; no external scraping of its own; allowlist upkeep |
| Push from the appliance to a COO receiver | Exporter stays on loopback | Adds an agent to the appliance payload (decision 10) and an exposed, authenticated receiver |
| Separate Prometheus and Grafana host | Not evaluated | A new component to own, outside the console and alerting |
| Customer-run monitoring | Not evaluated | Only sample configuration ships; integration untested |

Recommend the first option as the default proposal (no owner decision yet), with the COO
MonitoringStack as the fallback if Monitoring says the external-endpoint pattern is
unsupported. Keep the rule and dashboard sources independent of that choice. Whatever
scrapes the appliance needs an "appliance unreachable" signal distinct from "transport
down", because the scrape path may cross the DX or VPN link it reports on.

The story title says "Grafana dashboards". Ask the PM whether that means Grafana JSON specifically, or Perses with Grafana JSON as an export. Ask the OpenShift Monitoring team: (a) is a user-namespace `ServiceMonitor` on manual endpoints for off-cluster IPs supported on 4.22 and later; (b) is user-workload `ScrapeConfig` or an additional-scrape-config field on any roadmap; (c) is COO `monitoring.rhobs/v1alpha1` `ScrapeConfig` supported, and from which COO version; (d) is `namespacesWithoutLabelEnforcement` the recommended way to join appliance and frr-k8s series; (e) which Perses data source and RBAC should non-admin viewers use.

### Rules and dashboards buildable now

The BGP, BFD and interface layers can be written now against the series the 4.22
and 5.x exporters share and node-exporter's default `netclass`/`netdev` collectors.
Facts that shape them, checked 2026-10-27:

- Counter names carry no added `_total`: `frrk8s_bgp_updates_total` (sent) and
  `frrk8s_bgp_updates_total_received` are counters, while
  `frrk8s_bgp_{announced,received}_prefixes_total` are gauges. Session state is 1 only
  when Established, so administrative shutdown also reads 0.
- No collection template configures a BFD peer (every role that renders `/etc/frr/daemons` sets `bfdd=yes` only), so BFD
  series are empty today and the BFD criterion waits on ask 3's owner. Gate every BFD
  alert on a declared expected session.
- Collection failure removes all BGP series while `up == 1`; one failed VRF query
  drops every BGP series, and an FRR with no neighbors looks the same. A failed BFD
  counters read keeps `frrk8s_bfd_session_up` but drops the event counters. Alert on
  expected series missing, not on `== 0`.
- VXLAN and WireGuard devices usually report operstate `unknown`, so
  `node_network_up == 0` while they work. Alert on
  `node_network_info{operstate=~"down|lowerlayerdown|notpresent|dormant"}` for
  expected devices instead, aggregating `operstate` away so a change between down
  states does not reset `for:`. A broken VXLAN or WireGuard device in `unknown` gives
  no interface signal; only VTEP or probe alerts catch it.
- UPDATE rates count messages, not prefixes: one UPDATE can carry many routes, session
  re-establishment, route refresh and soft clears produce full-table bursts, and
  End-of-RIB markers count too. Use them as a per-peer panel against a baseline,
  never as an alert threshold.
- The image's node-exporter unit listens only on `127.0.0.1:9100` and enables
  neither the `systemd` collector (it also needs the D-Bus socket) nor a textfile
  directory, so a remote scrape and service-state panels both need a unit change. It
  embeds OpenShift's node-exporter build (the Podman path pins v1.9.1); confirm its
  version, and note that `--collector.netclass.netlink` drops `adminstate`.

Drafts on
[`corenet-7504-monitoring-drafts`](https://github.com/dfarrell07/evpn-gateway-appliance/tree/corenet-7504-monitoring-drafts/monitoring)
(19 alerts in 20 rules, 8 recording rules, 25 panel queries and 17 `promtool test rules`
cases) pass `promtool check rules --lint=all
--lint-fatal` and `promtool test rules` with promtool 3.5.0 (rechecked 2026-10-28). The
cases cover healthy operation with VXLAN in `unknown`, missing inventory, exporter down
and missing targets, BGP series missing while `up == 1`, unpaired and paired failover
and recovery, maintenance, intentional removal, counter resets, BFD and BGP correlation,
prefix limits, and interfaces flapping between down states. Alert names, job names,
inventory series and thresholds are proposals; the drafts' `monitoring/README.md` records the inventory schema.

The drafts also implement the following; `max_prefix` and
the expected MTU are separate inventory series because PromQL cannot compare a label
with a value, and inhibition stays a README note until an Alertmanager is chosen:

- Gate session-down on the expected inventory with `for: 5m`, an `admin_down` flag (the
  exporter drops administrative state) and an `expect_prefixes` flag for the
  zero-prefix alert; warn separately on peers outside the inventory. The templates use
  `frr defaults traditional` (keepalive 60 s, hold 180 s, connect retry 30 s), so a
  silent path loss pages (critical, without a surviving redundancy group) about 8 minutes later; BFD or shorter timers, not a shorter
  `for:`, reduce that.
- Every template sets `maximum-prefix` without `restart`, so exceeding it holds the
  session down until cleared by hand: carry `max_prefix` in the inventory, warn above
  80% (the summed gauge errs early until slice 3), and note the manual clear in the
  runbook.
- Severity: a session down is a warning while another session in its
  `redundancy_group` is up and critical otherwise; groups span appliances, so a relay's
  sessions to both members of an on-prem pair back each other up. Put `role`, `site` and
  `pair` on every expected series for routing. Inhibit only the unreachable
  appliance's own collector and series-missing alerts, not the far side's
  session-down, which is the best transport signal.
- Keep the inventory-missing alert in a static `PrometheusRule` (a deleted generated
  one would take it along), compare a rendered per-appliance item count with the
  observed one, and label inventory rules and appliance alerts `leaf-prometheus` so
  they evaluate together; only joins with platform series go to Thanos Ruler.
- Correlate BFD with BGP through `bgp_peer` on `ega_expected_bfd_session`: both down is
  one path alert, BGP down with BFD up a control-plane warning, and BFD down with BGP up
  a path warning only where BGP is not BFD-registered. Alert when
  `node_network_mtu_bytes` differs from an expected `mtu`.
- On intentional removal, update the inventory before FRR. promtool cannot test rule
  reloads, so check on a live Prometheus that a removed inventory item stops its alert.

| Layer | Buildable now | Waits for |
| --- | --- | --- |
| Appliance, VLAN, tunnel | `up`, uptime, `node_network_info` operstate, carrier changes, throughput, errors/drops, MTU for the role's devices (`vxlan{10000+vlan}`, `br-vni*`, `trunk.*`, `wg0` in development) | systemd collector for service state; a selected per-tunnel IPsec source |
| BGP, prefixes, churn | Session state, expected-versus-up, prefix gauges (all families summed), UPDATE rates as a churn proxy, OPEN and sent-NOTIFICATION counters as re-establishment indicators | Per-family prefixes (slice 3); owner acceptance of UPDATE rate as churn |
| VNI and MAC | Per-VNI VXLAN device traffic and inventory from node-exporter | VNI, MAC/ARP occupancy and remote VTEPs (slice 4), or an interim node-exporter textfile (for example from `show evpn vni json`; kickoff-decisions lists `vtysh`/`bridge fdb` textfile series as an option, decision 16) |
| BFD, DX, VPN, latency | BFD state, down events and packet rates where a session is declared | BFD identity fix before trusting values; CloudWatch for DX/VPN; a latency source |
| Alerts | Exporter down or missing target, appliance unreachable, inventory missing, BGP series missing, gather errors, expected session down or missing, flapping, zero accepted prefixes where expected, gated BFD, interface down or missing, node collector failure | VTEP, DF/ES and transport alerts |

Label every `frr-metrics` and node-exporter target with `appliance`, `role` and `site`
(and `pair` for HA) generated from the Ansible inventory. With user-workload monitoring, use one Service and endpoints per appliance
and copy those labels with ServiceMonitor `targetLabels`, or set them with per-endpoint
`relabelings`. Generate the expected sets (`ega_expected_target`,
`ega_expected_bgp_session`, `ega_expected_bfd_session`, `ega_expected_interface`, names
proposed) on the Prometheus side from the same variables as the FRR templates: Ansible
renders a `PrometheusRule` with one recording rule per item (`expr: vector(1)` with its
labels, in the same namespace as the ServiceMonitor), so the set survives an appliance
being down and a removed rule ends its series on reload; a textfile on the appliance
would vanish with it. The `peer` label must match FRR's neighbor key exactly (compressed
IPv6, or the interface name for unnumbered peers); dynamic `bgp listen` neighbors cannot
be listed in advance. Map CloudWatch dimensions (`VpnId`, `TunnelIpAddress`,
`ConnectionId`, `VirtualInterfaceId`) to the same labels.

Keep rules as Prometheus rule YAML with `*_test.yaml` fixtures and dashboards in one
source format chosen after the PM answers the Grafana question above (Grafana JSON,
which Perses can import, or Perses dashboards as code), in a source directory proposed
as `monitoring/`, and ship them
in the collection only once a consumer exists
([pipeline-spec.md](pipeline-spec.md#publication) proposes the monitoring
role's files). A `check-monitoring` target in `make check` would run `promtool check
rules --lint=all --lint-fatal` and `promtool test rules` (plus `amtool check-config`
and `amtool config routes test` if inhibitions ship as Alertmanager configuration), and
a stdlib Python check that each
dashboard parses and has a `uid`, title and schema version, with every panel query,
once Grafana variables are substituted, wrapped in a temporary rule file for
`promtool check rules`. The only new tool is promtool, pinned
in `Dockerfile.ci` and added as
[ci-source.md describes](ci-source.md#how-to-add-a-check); it runs offline.

## Implementation sequence and validation

Each slice needs its own evidence and stays separately reviewable; the rows are
dependencies, not one serial PR. Metric contracts and dashboards can proceed while the
standalone fix is in upstream review, and downstream build and runtime canaries can
start after slice 1 (or [an alternative](#if-upstream-declines-the-flag)) and its shutdown and access fixes. Full 7504 acceptance needs every
acceptance area with role applicability explicit; disabling a collector does not waive
a criterion, and churn and latency need a measured source or an owner-approved
clarification.

| Slice | Repository / concrete change | Required evidence |
| --- | --- | --- |
| 1. Standalone serving | frr-k8s, or [an alternative](#if-upstream-declines-the-flag): explicit opt-out from Kubernetes auth, unchanged default TLS/auth, CLI documentation and handler/startup tests | No service-account mount, no Kubernetes environment, nonexistent kubeconfig: standalone TLS scrape succeeds; default mode still fails; bad cluster credentials never bypass auth |
| 2. Reliable collection | frr-k8s: status/duration, explicit BFD identity/compatibility, native scrape admission and bounded CLI execution; reuse #507 if merged and evaluate bulk BFD queries | Command/parse failure, duplicate identity and timeout visible; empty success distinct; BFD-only VRF covered; partial BFD read handled; total multi-query budget, excess scrapes and recovery tested; no stranded CLI child/pipe wait; existing status-controller behavior preserved |
| 3. EVPN prefixes | frr-k8s: retain per-family neighbor values and add gauges without changing legacy aggregates | IPv4/IPv6/EVPN-only and mixed sessions; existing metric fixtures unchanged; down/unnegotiated family with absent advertised count; family disappearance, parse errors and peer resets covered |
| 4. L2 VNI/MAC observations | frr-k8s: optional zebra EVPN collector with typed summary parsing and bounded labels | Empty/disabled EVPN, zero-MAC VNI, mixed L2/L3, `n/a`, unknown fields/commands, malformed JSON, disappearing VNI, scale/command budget |
| 5. Local ES/DF and VTEP membership | frr-k8s, and FRRouting only if the agreed semantics require missing daemon data | Local/remote/bypass ES, active/down, DF failover, missing participant, bounded peer labels; no claim that membership proves reachability |
| 6. Red Hat delivery | openshift/frr release branch and its native build pipeline | Upstream source carried downstream; actual built image exposes flags/series and passes architecture/FIPS checks; image publication/digest resolved |
| 7. Appliance/collection | EGA: selected runtime units and role migration, explicit endpoint policy and scrape wiring; requires the exporter lifecycle fixes described above | Approved scraper access path; certificate-watcher failure and blocked-query shutdown/cleanup verified; installed collection paired with image; SELinux-enforcing boot/restart/reboot/upgrade/rollback, registry-unavailable runtime and real BGP/BFD/EVPN series |
| 8. Complete 7504 | EGA dashboard/rule sources and selected AWS/probe integration | Every acceptance area has a measured source; promtool fixtures, live dashboard state changes, failure injection, recovery and delivered notifications |

### Validation commands

Focused commands from the frr-k8s root:

```bash
go test ./cmd/metrics/... ./internal/tlsconfig
go build -o /tmp/frr-metrics ./cmd/metrics
go vet ./cmd/metrics/... ./internal/tlsconfig
go test -short ./internal/frr -run 'Test(Neighbour|Neighbours|UnnumberedNeighbours|Routes|BFDPeers|VRFs)$'
```

`internal/frr` has a `TestMain` that starts Docker-backed FRR unless `-short` is set,
even with a parser-only `-run` filter. Before an upstream PR, run upstream's `make
test`, `go mod tidy` with no diff and lint; tests must not depend on the developer's
kubeconfig, service-account files or network.

### Experiments completed during this investigation

The standalone-auth and lifecycle rows ran against WIP revisions `fdf0421` through `c0dc674`; the 2026-10-26 recheck at `f62448f` repeated only focused tests and `go vet`. "Audit" rows isolated one behavior each.

| Experiment | Result and limit |
| --- | --- |
| Unmodified exporter, no cluster variables, nonexistent kubeconfig | Exit 1 before listener setup, failing to get in-cluster configuration |
| Auth WIP: unit, race, vet, lint and the native Dockerfile builder stage | Passed; all four binaries built; not full upstream CI or cluster e2e |
| Auth WIP: native-built exporter, rootless read-only container, no capabilities or cluster config, synthetic vtysh | Both certificate modes served BGP/BFD samples over trusted HTTPS; default and explicit-false auth still rejected missing cluster config; TLS defaults, minimum version, liveness and the mode notice checked; fixtures do not qualify FRR sockets or a release image |
| Same fixture with vtysh exiting 1 | `/metrics` 200 with session series absent; `/livez` 500 |
| Audit: supplied certificate and SIGTERM | Trusted HTTPS succeeded; the process stayed alive after SIGTERM and was killed explicitly; self-signed mode exited |
| Lifecycle WIP: HTTP drain tests and signal probes | Drain, watcher-error and forced-close tests passed; idle SIGTERM/SIGINT exited 0 in both modes with tini; blocked CLI, real sockets and appliance lifecycle unqualified |
| Audit: controller-runtime certificate watcher with files removed before `Start` | Registration failed after 10 seconds with nothing logged and the initial certificate still served; neither watch nor reload started |
| Audit: promhttp admission and Go subprocess pipe waiting | Limit 1 with one blocked gather returned 503 without another gather, and release restored 200; a 50 ms deadline took about 1 s with an inherited pipe versus 70 ms with a 20 ms `WaitDelay`; descendants still needed cleanup. Library behavior only, not FRR qualification |
| Audit: private namespace and host-loopback publication | Container-loopback listener unreachable through the published port; container-interface listener returned 200 |
| Audit: atomic certificate-file and runtime-directory replacement | A file mount kept old content; a directory mount saw the new file; a recreated socket-directory path left the existing mount on the old directory |
| Audit: controller-runtime auth filter with a synthetic review API | Allow, deny, missing token, custom path and cached-versus-fresh outage behavior matched the contract above; no real credentials |
| Pinned 4.22 FRR image (`frr10-10.4.3-3.el9_8.2`), real daemons, rootless network namespace | Daemon startup, paths, both VRF discovery commands and real JSON confirmed; the lab router needed `NET_ADMIN`, `NET_RAW` and `SYS_ADMIN`, so this is not a minimal-capability or host-security qualification |
| Real kernel L2/L3 VNIs | Zero-MAC L2 VNI stays in the summary; L3 `numRemoteVteps` is `"n/a"`; summary and detail shapes differ; BGP VNI output has global metadata |
| BFD-only VRF and bulk BFD commands | The session appeared in BFD output but not BGP discovery; unfiltered BFD peers and counters included it |
| Audit: two Red Hat FRR routers on a private network | eBGP with IPv4/EVPN and BFD established; a remote VTEP and per-family counts observed; no VXLAN forwarding or DF/HA |
| Audit: peer removal and recreation with the exporter running | Scrape state went 1, 0, 1; prefix aggregates matched summed family values (stable socket storage, not the unit's directory lifecycle) |
| Audit: one up single-hop and two down multihop BFD sessions on one peer and VRF | Duplicate-metric error; partial 200 kept a down-state sample |

Remaining: cluster tests, release-image rebuild and publication, bootc, SELinux and FIPS
qualification, blocked-CLI cleanup, and scale and fault injection.

## Evidence and open questions

A PR search on 2026-10-22 and an issue search of `metallb/frr-k8s` on 2026-10-26 found
no parallel standalone-auth work, which is an observation, not proof. The upstream PR
template asks for an agreed issue before non-trivial changes, so each slice needs its
own issue (slice 1: #518 and #519, [status](#status-and-next-steps)).
Upstream [#506](https://github.com/metallb/frr-k8s/issues/506) tracks the VRF-listing
cost that #507 addresses. [openshift/frr #141](https://github.com/openshift/frr/pull/141),
an open sync PR at `f31f540a`, did not touch `cmd/metrics/exporter.go` on 2026-10-22;
recheck it and #507 before proposing patches, and coordinate behavior with downstream
`OWNERS` and upstream rather than inferring approval from this plan.

On 2026-10-29 #506, #507, #518 and #519 are open; #519 carries the scope question (ask 8).
In [#420](https://github.com/metallb/frr-k8s/issues/420) a maintainer turned
down driving an externally managed FRR as against the project's premise, sharing "a
single FRR instance running on kubernetes nodes": a different ask from #518, but the
same scope line. [#513](https://github.com/metallb/frr-k8s/issues/513)
(2026-10-22, no replies) proposes Grafana dashboard and alert-rule subcharts for the
frr-k8s chart, covering in-cluster targets; offer its author the BGP/BFD rule
expressions and promtool cases if useful. The merged
[EVPN design](https://github.com/metallb/frr-k8s/blob/58664da64bb9388afc61009261524d6591b745f7/design/basic-evpn-support.md)
leaves its Metrics section as "TBD.", the natural place to propose the EVPN collector.
Downstream `openshift/frr` main promotes to 5.1, so an upstream change synced before
the 5.1 branch cut reaches 5.1 without a carry.

Proposed upstream order, each with its own issue:

1. The SIGTERM fix ([adjacent findings](#adjacent-findings-to-handle-separately)); it
   touches `exporter.go`, so rebase #519 after it.
2. The vtysh stderr fix, after or rebased onto #507, which edits the same file.
3. Slice 2: additive per-collector status and duration gauges, then command deadlines
   and admission control; BFD identity needs agreement first because it changes
   existing series.
4. An EVPN metrics issue against the design's TBD section, referencing #513.

Asks, in priority order. Owners in [kickoff-decisions.md](kickoff-decisions.md) are
proposed, not accountable, so route each through the 7504 assignee; decision 16's
proposed owner includes the 7504 owner.

1. **Decision 16 owner (Networking, owner pending):** accept the pinned 4.22 `frr-metrics` on host
   loopback as the interim source for development and e2e, and decide whether VNI/MAC
   gets an interim textfile source; then the metric contract, including VTEP and DF/HA
   semantics.
2. **Epic owner (CORENET-7498):** CORENET-7499 is unassigned; propose that 7499 takes
   the role swap and teardown while 7504 takes the image unit, e2e scrape, rules and
   dashboards, and confirm the story split proposed in the status section.
3. **PM:** the [Grafana question](#where-metrics-are-scraped-and-shown); the decision 1
   Jira correction for the VNI/MAC criterion; and an owner for BFD configuration and for
   AWS DX/VPN metrics.
4. **Product Security:** whether an unauthenticated plain-HTTP loopback exporter is acceptable at GA or only before it (and for node-exporter); the [interim payload questions](#interim-exporter-from-the-embedded-422-image) (CPE, errata, SBOM, FIPS) and who re-pins it; whether exporter-held full vtysh control is acceptable; the access model, CA and rotation owner; and whether tenant VRF and VTEP labels need data classification before user-workload monitoring.
5. **OpenShift Monitoring:** the five questions in
   [where metrics are scraped](#where-metrics-are-scraped-and-shown).
6. **Decision 10 owner:** accept the 4.22 payload for the interim and the 5.x release
   build.
7. **openshift/frr owners:** which 5.x branches carry slice 1 (or its
   [alternative](#if-upstream-declines-the-flag)) and the bug fixes, and the 5.1
   branch-cut date.
8. **frr-k8s maintainers (#519):** keep the flag or prefer a separate project; options
   and fit are in [If upstream declines the flag](#if-upstream-declines-the-flag).
9. **Network and security:** the scrape path to each appliance (in-band or management),
   certificate issuance, key storage on bootc, rotation and revocation, who can read
   the client-certificate Secret, and the AWS metric source, credentials and latency
   measurement.
