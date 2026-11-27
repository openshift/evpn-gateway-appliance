# End-to-end CI

This plan says what end-to-end (e2e) CI must prove, where each proof runs (emulated, mocked
or live), and what accounts and credentials the live lanes need. It proposes; Jira acceptance
criteria are the requirements, and the decisions it cites stay open until
[recorded](kickoff-decisions.md#decisions-at-a-glance). Image boot, AMI import and release
gates stay in the [BIB contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle)
and the [pipeline plan](pipeline-spec.md#3-integration-gates-and-test-infrastructure); this plan
links to them rather than repeating them.

## Requirements

The prototype's task breakdown (`docs/evpn-task-breakdown.md` at `1c8e88873af8`, see
[context](context.md)) lists six integration-test points under "Integration test [CI]".
[CORENET-7508](https://redhat.atlassian.net/browse/CORENET-7508) carries them as four
criteria (deploy in CI; eBGP and Type-2/3; L2 and VNI isolation; internet-mode MTU and MSS):

1. A CI environment that runs the appliance and relay in containers on a simulated topology,
   without AWS.
2. eBGP Established across three ASes (on-prem 65044, relay 65100, workload 65200).
3. EVPN Type-2 and Type-3 routes exchanged end to end.
4. Bidirectional L2 reachability per VNI across the stretch.
5. VNI isolation: VNI 10100 cannot reach VNI 10200.
6. Internet-mode MTU enforcement: oversized frames dropped, TCP MSS clamped.

The same breakdown's end-to-end validation phase needs real AWS and OpenShift. It became the
QE stories [7512](https://redhat.atlassian.net/browse/CORENET-7512)–[7520](https://redhat.atlassian.net/browse/CORENET-7520)
([delivery plan](delivery-plan.md)); the transport stories (7500, 7501, 7708) and HA stories
(7502, 7503) add scenarios to the same lanes. This plan was checked against their Jira criteria
on 2026-11-25. 7508 is Closed (2026-10-29) with points 5 and 6 unfinished and point 3 checked
only indirectly; 7513, 7515 and [7695](https://redhat.atlassian.net/browse/CORENET-7695) are in
progress on the kind lane; 7512, 7514 and 7516–7520 are To Do and unassigned. Their
documentation criteria (7512's CUDN and frr-k8s configuration, 7515's workload-VTEP docs) stay
with those stories; CI proves behavior.

## Where each proof runs

| Tier | Runs | Proves | Cannot prove |
| --- | --- | --- | --- |
| Offline fakes | `make verify` on every PR once #56 and #57 merge; no network or credentials | AWS call shapes, inputs, query filters, teardown ordering and error handling against a fake `aws` CLI; preflight refusals | Live AWS behavior: the fakes mirror the API documentation |
| Emulated | Required Prow `e2e` on every code PR: containerlab on a disposable EC2 host from the shared `openshift-org-aws` profile | The shipped `deploy.yml`, from the test EE, against nodes built from the CI appliance image (CentOS base): BGP, EVPN, L2 and transport configuration; once merged, teardown with a no-leftover-FRR-routes check (`ipsec`, `dx`), the path probe's VXLAN-drop and partial-loss checks (#48) and frr-metrics' checks (#53) | AWS gateways, AWS-initiated events, OpenShift payloads, hardware; the ART image (ART builds with its own FRR; the lane injects OCP 4.22's `metallb-frr` image) |
| Live AWS | Owned AWS profile; a transport canary and full-stack runs on reviewed `main`, periodic and on demand | Provisioning, handoff, telemetry and teardown against real AWS; OpenShift EVPN against the appliance across a real transport | Direct Connect without a circuit; customer on-prem hardware |
| Standing labs | Leased, outside per-PR CI | Direct Connect, scale, on-prem trunk/VMware | — |

The emulated tier is the per-PR gate. Live lanes add evidence and never replace it.

## Emulated: the per-PR lane

`test/e2e/entrypoint_e2e.sh` runs every `test/e2e/scenarios/*.env` in turn (merged #60), and the
release configuration sets no `EGA_SCENARIOS`, so each merged scenario is required on every PR
that changes code, and merging #52 or #57 makes `ipsec` or `dx` required. This plan keeps
them there ([decisions](#decisions)), in line with jcaamano's #43 comment ("I would use the existing e2e
lane if possible") and #60's run-every-scenario default. The VPN plan asks for kernel IPsec to be qualified on a
root-privileged runner first; Prow's EC2 host is one, and the run below passed there. Prow's
`e2e` ran `emulated` then `ipsec` on #52 at 08816aa in 40 minutes end to end
([run](https://prow.ci.openshift.org/view/gs/test-platform-results-public/pr-logs/pull/openshift_evpn-gateway-appliance/52/pull-ci-openshift-evpn-gateway-appliance-main-e2e/2125449801607680000)).
The scenarios run one after another on one m6i.xlarge, so each one adds to that time. From
2026-11-17 to 2026-11-25, passing `e2e` jobs, EC2 host included, took a median of 31 minutes
and at most 52, well inside the test step's two-hour default
[timeout](https://docs.ci.openshift.org/docs/architecture/timeouts/). When the job
nears it, split scenarios across jobs; that needs the step to pass `EGA_SCENARIOS`, which it
does not today.

| Scenario | Stands in for | Source |
| --- | --- | --- |
| `emulated` | Relay and workload VTEP as containers; WireGuard internet mode | main |
| `ipsec` | TGW as a Libreswan + FRR node with test-only PSKs | #52 (7500) |
| `dx` | Customer router, transit VIF and DX gateway as one routed 8500-byte link, in safe MTU mode; runs deploy, a preflight rerun, health checks including the 1550-byte DF ping, then teardown and a no-leftover-FRR-routes check | #57 (7708) |
| multihoming | Two on-prem appliances on a shared ES over the direct underlay; LACP, BFD, Type-1/4 routes and DF takeover, one copy of each broadcast, the survivor's Type-2 re-advertisement, and recovery after a link loss or an FRR crash. #52 refuses IPsec with multihoming until 7502 qualifies it | #43 (7502) |
| relay HA | Two relays; #49 stops FRR only | #49 (7503) |
| `kind` | Upstream OVN-Kubernetes EVPN (the OpenShift-native API) in kind, not the OpenShift payload, with its own topology and no emulated workload VTEP, which meets 7695's independence from the 7508 lane. #23 adds it as `kind.env` and runs the health check against frr-k8s peers (relay side; the appliance's VTEP checks skip discovered peers) (7515). #26's `l2-pod` checks must join that scenario rather than replace the `*.env` loop. Draft #61's `multi-vni` covers 7513 in part: one CUDN per VLAN, per-VNI route targets and MAC-table separation, and a day-2 stretch added, then its CUDN and workloads deleted and recreated while the appliance-side stretch stays | #23 (7515), #26 (7695), #61 (7513) |

What the emulation cannot show: real IKE interoperability (the TGW node copies the appliance's
proposals), AWS telemetry, NAT-T, AWS-initiated rekey and maintenance, TGW ECMP and route
limits, DX VIF BGP and gateway associations, the customer router's MD5 session and route
advertisement, DX route propagation into the TGW, and the OpenShift payload (kind runs upstream
OVN-Kubernetes). The TGW node falls back to its management default route when its tunnels are
down, so a cleartext-leak check must filter by ingress port and source.

### Remaining 7508 work

7508 closed before these rows were done, so a new story under 7498 takes them ([decisions](#decisions)).

| Point | State on main | Next step |
| --- | --- | --- |
| 1 Environment | Done: containerlab fabric in Prow `e2e` | Install the pinned containerlab release by checksum in `Dockerfile.ci` instead of piping the unpinned `get.containerlab.dev` installer, whose failed fetch exits 0 and leaves no binary |
| 2 eBGP | `evpn_health_check` asserts Established per hop | Independent assertion (below) |
| 3 Type-2/3 | Indirect: relayed prefix counts and a remote VTEP per VNI | Assert each expected Type-2 MAC/IP and Type-3 per VNI by route |
| 4 L2 | Ping per VNI in both directions | Add one TCP and one UDP exchange |
| 5 Isolation | Disabled in `evpn_onprem_appliance_sim` healthcheck: the appliance routes between tenant subnets | The appliance must not route to or from a stretch ([decisions](#decisions)). Add the check as a strict expected failure with the pytest/JUnit work, keeping same-VNI reachability required, and make it required in the PR that stops the routing. It probes both directions between real endpoints, tells L2 leakage from routing by TTL, and reruns after a reboot, a redeploy and a day-2 stretch, in `emulated` and multihoming; today it produces no result. #61 checks route-target and MAC-table separation on kind, but its traffic probes run behind test-only `FORWARD` drops, so 7513's no-traffic-leak criterion stays open until probes run against the shipped configuration |
| 6 MTU/MSS | Not implemented; the clamp is [CORENET-7709](https://redhat.atlassian.net/browse/CORENET-7709) | When 7709 lands: oversized don't-fragment ping dropped, MSS observed on the wire, in `emulated` (WireGuard) and `ipsec` |

Build these on the pytest/testinfra and JUnit harness that `test/e2e/README.md` describes
("Testing plan"), so the deploy is not graded by its own health check; today the artifact
directory stays empty.

Two QE checks are cheapest here and need no AWS: 7519's storm containment (flood broadcast
and excess EVPN advertisements from one on-prem peer; other peers and VNIs keep forwarding) as a
scenario, and 7515's separation as an offline check that production playbooks and the built
collection contain no standalone workload VTEP or test fixture.

## Offline fakes

Keep them small and contract-level: inputs and expected failure messages, never secrets in
output.

- Direct Connect: `test/direct-connect/run.py` (#57, `make check-ansible-direct-connect`, CI
  image only since it needs jmespath) fakes `aws`, `ip` and `cat` for the DX preflight,
  association, status and teardown tasks, the `provision-aws.yml`, `teardown-aws.yml` and
  `deploy.yml` entry points, and the rendered FRR and nmstate configuration. It strips the
  caller's AWS credentials so nothing reaches AWS.
- Preflight: `test/preflight/run.sh` (#56) runs 7501's internet-mode refusals (acknowledgment,
  workload MTU) and the ping baseline against canned inputs, including through `deploy.yml`;
  #57's `run.py` covers the Direct Connect refusals. #56's Direct Connect plan maps 7501's
  criteria to its checks; the 7501 owner confirms any partial mappings and the
  private-to-transit VIF correction ([decision 1](kickoff-decisions.md#decisions-at-a-glance)).
- Site-to-Site VPN: no fake in the repository yet. Reuse #57's fake `aws` for preflight
  refusals and the error paths a live canary cannot inject: partial provisioning (VPN creation
  fails after the customer gateway exists, then a rerun under #52's rerun contract), a WireGuard teardown that
  finds a project VPN, throttling on delete, a persistent `IncorrectState`,
  readback that differs from the pinned tunnel options, a VPN still pending at handoff, and a
  failed key-bearing lookup. A private harness found defects on these paths before #52 fixed
  them. Port only those cases; the live canary covers live behavior.

## Live AWS lanes

Both lanes build on Jaime's [owner proposal](https://github.com/openshift/evpn-gateway-appliance/pull/42#discussion_r4616321441)
(2026-11-18): a transport canary and periodic full-stack qualification on one AWS substrate.
The proposal runs the canary per trusted PR; this plan runs it on `main` (see Trigger). Neither
lane exists yet; both wait for the account work below.

### Transport canary

- Topology: the project TGW and VPC from `evpn_aws_infra`; a Site-to-Site VPN to an EC2
  instance acting as the on-prem customer gateway (public address, the appliance image or
  container); the relay; a standalone test VTEP (the test collection's workload role) instead
  of OpenShift, to keep it short and cheap.
- Proves: the transport preflight against real endpoints (7501), provisioning and the rerun
  guard, the readback of the pinned tunnel options, the PSK handoff without logging, both Child
  SAs (the first check of the pinned proposals against real AWS) and underlay sessions, the EVPN
  session to the relay, `VgwTelemetry` UP, VXLAN reachability, TGW ECMP (several VXLAN flows
  using both healthy tunnels at once, not one flow split), one tunnel failover, relay loss (no
  VXLAN on the relay's interfaces at any time, which is 7520's relay outside the VPN data path;
  existing flows continue until the EVPN hold time expires, then stop until the relay returns,
  since relay HA is 7503), and teardown leaving no VPN, customer gateway or Elastic IP (7500
  AC1–AC5). WireGuard mode runs the same lifecycle without the VPN and records throughput
  through the relay under rising load, with the relay's CPU and drops, to show where 7520's
  WireGuard bottleneck sits; a measurement rather than a gate. The EC2 customer gateway's public
  address is AWS one-to-one NAT, so the canary also asserts NAT detection and ESP over UDP 4500
  (7708).
- Periodic runs outlast the pinned ESP lifetime (3,600 s) to assert a Child SA rekey under
  traffic; a weekly run holds the canary past the IKE lifetime (28,800 s) for the IKE SA rekey;
  lifetimes are not shortened for the test, since the canary pins production's options. Both are
  asserted separately from SA state. Periodic runs also force an endpoint replacement with
  `ReplaceVpnTunnel`; elapsed time alone does not show that AWS maintenance happened.
- Trigger: a postsubmit on `main` for changes to `ansible/roles/evpn_aws_infra/` and the
  transport handoff and health roles, a periodic, and on-demand runs of that postsubmit at an
  approved `main` commit through
  [Gangway](https://docs.ci.openshift.org/how-tos/triggering-prowjobs-via-rest/) (`/test` starts
  only presubmits). Not on pull requests: Prow trust (organization membership or `/ok-to-test`)
  authorizes running a PR, not handing its code a live account, and PR authors
  [administer](https://docs.ci.openshift.org/docs/how-tos/interact-with-running-jobs/#access-the-namespace-on-clusterproject-of-the-running-ci-job)
  their job's namespace. The [credential boundary](ci-bootstrap-spec.md#credential-boundary)
  requires approving the executed revision outside contributor-controlled code. This narrows
  Jaime's per-PR proposal, at a cost: an `evpn_aws_infra` regression merges before the canary
  sees it, and is then fixed forward or reverted.
- Owner: [CORENET-7708](https://redhat.atlassian.net/browse/CORENET-7708), whose
  [decision 20](kickoff-decisions.md#decisions-at-a-glance) scope is transport qualification, with
  the account request below. 7500's Jira criterion 6 still names the canary, gated on CI-owner
  cadence and Test Platform approval of identity containment and cancellation cleanup; those
  gates move with it.

### Full-stack qualification

- Topology: an OpenShift IPI cluster on AWS with native EVPN (FRR provider, local gateway
  mode, route advertisements, a VTEP and an EVPN CUDN), the relay peering frr-k8s, and the
  canary's emulated on-prem site over the VPN.
- Proves, per run: [7512](https://redhat.atlassian.net/browse/CORENET-7512) relay peering,
  Type-2 and Type-3 routes by route in both directions, and VXLAN directly between appliance
  and node VTEPs; [7513](https://redhat.atlassian.net/browse/CORENET-7513) by adapting
  `multi-vni`'s CUDN, route-target, MAC and day-2 checks to the OpenShift payload (traffic isolation once the appliance stops routing);
  [7516](https://redhat.atlassian.net/browse/CORENET-7516) VM-to-pod ping, ARP, TCP and UDP,
  ARP suppression (a remote MAC/IP answered without flooding ARP across the tunnel) and BUM;
  [7517](https://redhat.atlassian.net/browse/CORENET-7517) propagation in both directions, and a
  BGP flap on every hop with sessions and routes back afterwards;
  [7518](https://redhat.atlassian.net/browse/CORENET-7518) one IP and MAC moved from an on-prem
  VM to a pod, the Type-2 mobility sequence number rising with GARP, old-MAC withdrawal, rapid
  moves and duplicate-MAC detection, and cutover and rollback under traffic; the failure half
  of [7519](https://redhat.atlassian.net/browse/CORENET-7519) (appliance, relay, worker, VPN
  tunnel), each followed by route and traffic recovery;
  [7520](https://redhat.atlassian.net/browse/CORENET-7520) for VPN and WireGuard;
  [7514](https://redhat.atlassian.net/browse/CORENET-7514) once 7709 lands, reusing the emulated
  MTU checks against the measured transport budget (CUDN MTU, the same inner limit enforced on
  the appliance and the nodes, inner SYN/SYN-ACK MSS both ways, oversized UDP dropped without
  fragmentation). Weekly, not per
  run: a second cluster with a distinct ASN, checking intended propagation and rejection of
  routes outside the cross-cluster import policy (7517), and the IPsec multihoming variant
  with OpenShift VTEPs (7502).
- Requires a nonzero count of executed EVPN cases, and records the OpenShift payload, appliance
  image and FRR digests ([OCP lanes](pipeline-spec.md#ocp-qualification-lanes)). Results qualify
  only the digests that ran. Whether the ART image's FRR build serves frr-metrics (openshift/frr
  `release-5.x` lacks frr-k8s #519 and #528) is an external dependency of 7504 and #53
  ([FRR metrics plan](frr-metrics-plan.md)).
- Trigger: periodic on `main`, and on demand before a release; a release branch gets its own
  periodic when it ships AWS EVPN as supported (decision 18). Each run is an IPI cluster plus the canary's resources; the
  decision 11 request sizes the budget and the Boskos quota from the cadence
  ([decisions](#decisions)).
- Cluster side: native OCP EVPN, as 7498's first criterion and 7512 require
  ([decisions](#decisions)). Published OCP EVPN support is bare metal only, so passing here is
  evidence, not support, until decision 18 says otherwise.

## Standing labs

These need equipment or durations that a disposable CI run cannot provide. Their results bind
to the candidate through the [release gates](pipeline-spec.md#required-gates).

- Direct Connect: two partner-hosted connections at two locations, each carrying a transit
  VIF at MTU 8500, ordered for each qualification run ([decisions](#decisions)). It proves VIF BGP, the
  gateway-to-TGW association and allowed prefixes, the 1550-byte path from the appliance to the
  workload VTEP (8500-byte VIFs, safe MTU mode), and failover between the VIFs under traffic in
  both directions; the customer router chooses its outbound VIF and influences AWS's choice
  through its advertisements (7519's DX failure). It runs the full-stack suite with DX in place
  of the VPN, including unfragmented 1500-byte inner IP packets both ways between an on-prem
  host and a pod, which is 7516's and 7520's DX case. The customer router, or its stand-in, runs
  the VIF's BGP with MD5, which FIPS-mode kernels disable, so it cannot be the appliance.
  Funding: [decisions](#decisions).
- Scale and performance (the rest of 7519: convergence at 100/500/1000 MACs, and latency and
  throughput measured during reconvergence): with
  [PERFSCALE-5814](https://redhat.atlassian.net/browse/PERFSCALE-5814).
- On-prem trunk and VMware: CNV's NSX lab ([transports and labs](pipeline-spec.md#transports-and-labs)),
  if its owner confirms availability and topology; today it has one FRR bridge VM.
- Physical multihoming: 7502's shared-ES/LACP on two appliances, DF/BFD, duplicate-BUM
  suppression and cable-pull and power-loss recovery need two appliances and one LACP-capable
  switch (EVPN multihoming replaces MC-LAG). They run before each release on borrowed lab hardware, not as a standing
  rig ([decisions](#decisions)).

## Accounts and credentials

Today's lanes use the shared `openshift-org-aws` profile only to rent the containerlab host.
No product credential reaches CI. The live lanes need:

1. A funded AWS account dedicated to this project, used in `us-west-2`, where the `e2e` lane
   already runs, with no VPNs other than the lanes': VPN readback cannot be scoped by tag and
   returns pre-shared keys
   ([VPN plan question 9](site-to-site-vpn-plan.md#questions-for-owner-decision)). This is
   [decision 11](kickoff-decisions.md#decisions-at-a-glance).
2. An owned cluster profile through Test Platform
   ([how-to](https://docs.ci.openshift.org/how-tos/adding-a-cluster-profile/)): credentials in
   the CI secret store, a Boskos lease quota sized to the canary and periodic concurrency,
   a Route53 base domain for IPI, and a `cluster-profiles-config.yaml` entry restricted to
   this repository. Installer credentials use mint mode
   ([question 11](site-to-site-vpn-plan.md#questions-for-owner-decision);
   [decisions](#decisions)). Test Platform must
   approve identity containment and cleanup of cancelled jobs before the canary runs (7500
   criterion 6).
3. IAM scoped to what the collection creates: VPC, TGW, VPN, customer gateway and EC2 (plus
   Elastic IP calls if the canary's customer-gateway instance uses one), plus the IPI
   installer's permissions for the full-stack lane and, for DX runs, the Direct Connect read and
   gateway-association create and delete permissions `evpn_aws_infra` documents (#57); cleanup
   needs the delete permissions too.
4. Cleanup: reuse the [AWS lifecycle contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle)
   (creation records, tags, lease-aware reaper), keyed by the Prow job ID, plus an account
   budget alarm.
5. Direct Connect, when funded: a DX gateway in the project account (Amazon-side ASN other than
   the TGW's) and partner-hosted transit VIFs (MTU 8500, customer ASN other than 64512) accepted
   into that account; #57 supports same-account gateways and VIFs only.

## Work, in order

1. Install the pinned containerlab release by checksum in `Dockerfile.ci` (NO-JIRA).
2. pytest/testinfra assertions with JUnit for points 2–4, and point 5 as an expected failure
   (7508's remaining rows, on the new story); then stop the appliance forwarding IP and make
   point 5 required. The 7515 separation check and
   the 7519 storm scenario follow on the same harness.
3. Scenario extensions: an IPsec multihoming variant, one two-tunnel VPN per appliance, proving
   active-active forwarding and DF failover (7502); whole-relay and link loss and return under
   traffic with BGP sessions re-established, and relay ECMP across flows (7503).
4. VPN error-path cases on #57's fake `aws` (after #52 and #57 merge).
5. Account, profile, IAM and cleanup (decision 11; Test Platform request).
6. Transport canary (7708).
7. Full-stack qualification on native OCP EVPN (QE; decision 18 for support).
8. Point 6 when 7709 lands; Direct Connect lab when funded.

## Jira updates after merge

Proposed for each ticket's owner once this plan merges; Jira stays as it is until then. New
stories are the 7498 owner's to create or assign.

| Jira | Proposed change |
| --- | --- |
| New story | Remaining 7508 work: points 2–6 on the pytest/JUnit harness |
| New story | Multihoming observability: 7504's Ethernet-segment series and DF-failure alert, which need 7502's Ethernet segments: one of the two homes jcaamano offered on #45, instead of moving them into 7502 |
| New story, optional | Appliance IPsec tunnel state and throughput metrics, a diagnostic beside CloudWatch's AWS view, as jcaamano suggested on #45 |
| 7500 | Criterion 6 keeps the emulated scenario, in the shared job once #52 merges if the CI owners agree (above), and drops the canary; criterion 5's failover, rekey and relay-loss tests point at 7708's canary (decision 20) |
| 7501 | "private VIF" becomes "transit VIF" ([decision 1](kickoff-decisions.md#decisions-at-a-glance), pending its owner; jcaamano's direction on #2); its UDP reachability and workload MTU criteria are amended as the 7501 decision in #56 records |
| 7504 | Criteria 2 and 7 move ES/DF metrics and alerting, and the description moves appliance IPsec status, to the two new stories, per [frr-metrics-plan.md](frr-metrics-plan.md) (#45) |
| 7708 | Gains decision 20's scope as criteria: the transport canary, with its account, profile, IAM and cleanup (decision 11's AWS request); the criteria #56's Direct Connect plan proposes for the DX transport (#57) and its lab qualification; FIPS validation and hardening of the IPsec and DX transports, including the IPsec proposals against AWS; the canary's NAT-T check, since the VPN plan puts customer-gateway NAT in 7708 qualification. Host FIPS mode and host hardening are already 7511 criteria, so 7708 relies on 7511's evidence; this narrows decision 20's "host hardening" to the transports, and the decision's owner updates it if approved |
| 7709 | Gains criteria: an oversized don't-fragment ping dropped and MSS observed on the wire in `emulated` and `ipsec` (point 6), which 7514 reuses |
| 7502 | Gains the IPsec multihoming variant, since #52 refuses IPsec with multihoming until 7502 qualifies it; runs the physical criteria on borrowed hardware before each release |
| 7512, 7514, 7516–7520 | One QE owner for the lane, and a link to the full-stack lane; 7514 blocked by 7709; the DX criteria of 7516, 7519 and 7520 blocked on circuit funding (decision 11 owners and the 7708 owner) |
| 7513 | No-traffic-leak criterion blocked on the appliance no longer forwarding IP |
| 7519 | Links PERFSCALE-5814 for its scale points |
| 7503, 7508, 7515, 7695 | No change: their criteria already cover this plan's checks (7508 is Closed; its rows move to the new story) |

## Decisions

This plan answers each of its questions. Each answer stays a proposal until the team named
under Confirms approves it (this repository's approvers do so on this plan's review) and
[kickoff-decisions.md](kickoff-decisions.md#decisions-at-a-glance) records the owner, date and
approval link; dependent plans are then updated as the [agent guide](agent-guide.md) describes.

| Question | Answer | Confirms |
| --- | --- | --- |
| Required lanes | On every code PR: `verify`, `molecule` and `e2e`, with every merged scenario; `ipsec` and `dx` join when #52 and #57 merge, and approving them is 7500 criterion 6's agreement. Near the step timeout, scenarios split into parallel required jobs through `EGA_SCENARIOS`, never into optional ones. Live lanes are never PR gates; the release gates consume their results | This repository's approvers, who own its job configuration (7500 criterion 6's CI owners) |
| Remaining 7508 rows | A new story under 7498; 7508 stays Closed, since reopening it would mix delivered and undelivered work | 7498 owner |
| Isolation model | The appliance must not route to or from a stretch, which 7508 point 5 and 7513's no-traffic-leak criterion require; today it does (ttl 63 in the disabled check). It needs no IP forwarding, since it only originates and terminates its own VXLAN and tunnels, so the on-prem role writes `0` to the `99-ip-forward.conf` the shared image ships with `1` for the relay, in place of its task that writes `1`; IPv6 forwarding is already off. The emulated workload VTEP role, which also routes between its VNI bridges, does the same. Hosts that use `onprem_gateway` as their router lose off-subnet reach, which the role's README states. Per-SVI forwarding blocks only traffic arriving on the SVI, and a VRF or firewall adds state, so neither is chosen | 7498 owner (on-prem role) |
| Canary home and trigger | 7708, whose decision 20 scope is transport qualification; a postsubmit and periodic, not on pull requests (see Trigger), which narrows Jaime's #42 proposal | 7498 owner |
| Cadence | Canary: daily, past one ESP lifetime, and weekly past one IKE lifetime. Full stack: weekly, plus on demand before a release | 7708 owner, QE |
| Cluster side (decision 6) | Native OCP EVPN, which 7498's first criterion and 7512 require; OpenPERouter and the cross-cloud question stay with decision 6 | Decision 6 owners |
| AWS account (decision 11) | A dedicated account through a cluster profile restricted to this repository, in `us-west-2` beside today's `e2e` lane; installer credentials in mint mode, as OpenShift CI's AWS profiles use | Decision 11 owners, Test Platform |
| Test Platform approvals (7500 criterion 6) | Identity containment by that dedicated account and repository-restricted profile; cancellation cleanup by the reaper keyed by Prow job ID (Accounts, item 4) | Test Platform |
| Support (decision 18) | These lanes produce qualification evidence; nothing here waits for decision 18 until a release branch ships AWS EVPN as supported | Decision 18 owner |
| Direct Connect circuits | Two partner-hosted connections at two locations, each carrying a transit VIF at MTU 8500, the minimum for the failover check. Order them for each pre-release run from a partner that provisions hosted connections on demand (for example [Megaport](https://www.megaport.com/services/aws-direct-connect/), in minutes); keep them standing only if the partner's minimum term costs less at the release cadence | Management (funding), decision 11 owners, 7708 owner |
| On-prem trunk and VMware lab | CNV's NSX lab for the trunk and VMware checks; without it, they stay unqualified, which decisions 18 and 19 weigh | CNV lab owner |
| QE owner for 7512, 7514 and 7516–7520 | The QE lead is accountable for the full-stack lane and these stories until assigning them to one QE engineer, recorded in the tickets before the lane is built | QE lead |
| Physical multihoming | The 7502 assignee runs its physical criteria before each release on borrowed hardware: two appliances and one LACP-capable switch; no standing rig | 7502 owner, QE |
