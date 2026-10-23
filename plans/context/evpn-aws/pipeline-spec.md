# EVPN Gateway Appliance (EGA) — CI/CD implementation and release plan

Source-CI boundaries and delivery contracts reviewed 2026-10-15; Jira coverage baseline
2026-10-08. Proposed implementation and release design for this document set. Jira acceptance criteria define requirements; linked contracts propose
how to implement and demonstrate them, and decisions require an owner/date in
[`kickoff-decisions.md`](kickoff-decisions.md). [Source evidence](source-evidence.md) records
sources, revisions, Jira findings and verification limits.

## Outcome and ownership

Deliver a traceable release set: the bootc appliance image (the registry update
source), on-prem disk images (qcow2 per 7506/7522, plus vmdk/ova if vSphere is
supported), an AMI, and the Ansible collection (`redhat.evpn_migration` in 7499;
`network.evpn_gateway` directed in review 2026-10-02, owner/publication approval pending),
with versioned dashboards, alerts, deployment/lifecycle documentation and support
boundaries.

CORENET-7506 and 7522 require building and publishing an AMI "through an approved
AWS workflow". The raw disk from BIB is its input. Which customer channel carries
that AMI, and how its RHEL entitlement is paid for, is an open decision
([AMI channel](kickoff-decisions.md)). Converting a customer's RHEL instance with
`bootc install to-existing-root` is not the Jira's deliverable; use it for test
convenience only unless the Jira changes.

Source lives in the public
[`openshift/evpn-gateway-appliance`](https://github.com/openshift/evpn-gateway-appliance)
repository (DPP-22292, created 2026-09-28), owned by OpenShift Core Networking.
That settles the forge (GitHub, Prow/tide merges, optional GitHub Actions by
request) and, for a team tenant, a public Konflux cluster.

Proposed responsibilities: Releng owns CORENET-7505/7506/7667/7522's delivery
mechanisms, Networking owns product behavior/topology, and QE owns qualification. Their
acceptance evidence gates production, without blocking unrelated source CI.

[CORENET-7498](https://redhat.atlassian.net/browse/CORENET-7498) explicitly requires
Direct Connect and Site-to-Site VPN, and limits WireGuard to development/test.
The legacy `evpn_cloud_workload` role must leave the production path; separate
emulation and test harnesses from production collection content (CORENET-7515).
Terraform remains lab scaffolding. Confirm which AWS provisioning roles ship;
the source intends Ansible provisioning. Shipping an EVPN EE is optional and does
not replace the collection. The parent [OCPSTRAT-3413](https://redhat.atlassian.net/browse/OCPSTRAT-3413)
includes L2 and feasible L3 support: qualify L2 first, and obtain an explicit
scope decision before including or deferring the parent's L3 requirement.

## Sequence: only block work on inputs it needs

| Gate | Inputs needed | Exit evidence |
| --- | --- | --- |
| A — source CI | Existing Prow verify and tools; reviewed product import for product checks | Planning, public-safety, YAML, Markdown and collection checks run in `verify`. Add standard lint for helpers and Dockerfiles, then image-source checks once the image sources land. [Queue](ci-source.md#queue) |
| B — non-releasing Konflux builds | source access, tenant/cluster/RBAC, approved image/package inputs; MPC capacity for privileged-nested bootc builds and rootful disk builds | bootc build + provenance, then on-prem disk canaries, digest nudge, disk boot and target-policy results |
| C-stage — trial publication | channel-specific stage destination, credentials, product metadata including the Engineering ID, applicable ECP/RP/RPA | stage container/download/AMI/collection install and launch evidence |
| C-prod — supported release | approved configuration matrix and AWS/OCP support decision, qualified candidate, production destinations/listings, security/QE/PM sign-off | same candidate published, customer paths verified, rollback and operational handoff recorded |

Source CI needs no Konflux tenant, cloud credentials or publication channel
([queue](ci-source.md#queue)). Before importing the image source for A's image checks, remove baked access, tracked
private/generated material and unsafe build inputs ([public import](source-audit.md#0-public-import)).
Feature completeness, HA qualification, final Marketplace IDs, and all parent
deployment-matrix decisions are production requirements; they are not
prerequisites for a non-releasing build canary. Source is public; choose build
registry visibility during onboarding and mark development artifacts as
unsupported. Konflux supports [public or private image
repositories](https://konflux-ci.dev/docs/building/imagerepository/);
build images contain entitled RHEL content, so apply Red Hat's redistribution
rules before making a build repository public.

Stage release objects are needed **before testing stage publication**. Create
stage ECP/RPA and matching RP once stage inputs are approved; KRD validates ECP
references, so submit related managed objects together. Keep tenant and managed
configuration changes separate. Production follows successful stage validation.
KRD derives CPE and product stream from a per-tenant `prodsec` template and checks
production RPAs against ProdSec product-definitions; stage RPAs skip that check.
`rh-advisories` still requires release-note product fields, including an
Engineering ID, even for stage. Konflux's guide expects an approved official product
name first, so start naming approval before stage work ([lead times](productization.md)). Delivery
repositories are created in production Pyxis and reach
stage on a daily sync ([identity evidence](source-evidence.md#10-production-identity-precedents)).
For Marketplace, the approved `cloudMarketplacesPrePush` stage path can supply
private AMIs needed to obtain production listing IDs; do not wait for those IDs
before starting stage. See RHELOPC-2351/2331/2327 and the merged xKS stage RPA.

[`kickoff-decisions.md`](kickoff-decisions.md) lists the remaining inputs.
Do not guess names, CPEs, registry paths, entitlement secrets, or policy exceptions.

## Artifact graph and candidate integrity

```text
reviewed source ──► bootc digest ──► digest-update commit ──► qcow2 digest
       │                     └───► digest-update commit ──► raw digest ──► test AMI
       └────────► collection build + MANIFEST.json digest
                                     │
           exact compatible set ─────┴──► required candidate tests ──► channel releases
```

Start with one bootc Component and add disk derivatives (qcow2, raw for the AMI,
then any approved vSphere format) as their packaging canaries pass.
The collection need not be a Konflux Component: bind it to the set by its
`MANIFEST.json` digest with its verified content chain
(see [collection integrity](ci-bootstrap-spec.md#collection-content-integrity)).
Do not create eight Components, overlay images, an exporter image, or an EE by
default. FRR, node-exporter and the frr-k8s metrics binary are payload
dependencies, not automatically EVPN-owned builds (CORENET-7505).
CORENET-7522 also requires component-container publication: record each remaining
runtime container's approved customer pullspec/digest and distribution/maintenance
owner. Reuse an approved existing distribution and include it in customer readback.

### Runtime payload (CORENET-7505)

7505 asks for "approved upstream FRR and node-exporter images", extraction of the
frr-k8s metrics binary, Ansible health checks without an extra container, and
pinned images. The wording comes from task breakdown §3.1, which chose the
community `quay.io/frrouting/frr`, `quay.io/prometheus/node-exporter` and
`quay.io/metallb/frr-k8s` images. The design justifies the FRR container as "the
same upstream image used by OVN-Kubernetes and FRR-K8s in OpenShift", but
OpenShift ships the Red Hat–built `frr-rhel9` (`ose-frr`) instead. That image
installs RHEL's `frr10` package and also contains `/frr-metrics` and `/frr-status`;
OCP has no separate frr-k8s image. Red Hat does not build or security-track the
community images, so they cannot be supported product content without a PM and
Product Security exception. Every supportable choice therefore changes 7505's
text, and PM owns that update:

| Option | FRR | `frr-metrics` | Consequences |
| --- | --- | --- | --- |
| A. OCP images | `openshift4/frr-rhel9` (`openshift5/` for 5.x once published) as a digest-pinned runtime container | Same image (runs standalone only on 4.22; [see below](#metrics-corenet-74997504)) | Closest to the design's container model and 7505's wording; 7522's "component containers" reuse OCP's distribution. Needs support terms for OCP content outside a cluster; the image carries OpenShift's CPE, so FRR fixes arrive with OCP z-stream images; runtime pulls or logically bound images must be qualified |
| B. RHEL package | `frr10` (RHEL 9.8+) or `frr` (RHEL 10) installed in the bootc image as a systemd service | `COPY --from` the OCP image by digest (4.22 only, as above), or build from frr-k8s source with Red Hat Go FIPS settings | RHEL errata and support; hermetic build and bootc rollback cover FRR; removes the FRR container and its pull. Selects a RHEL 9.8+ or RHEL 10 base (9.7 lacks `frr10`; 9.6 EUS delivery is open); RHEL 9's `frr10` stream retires in November 2030 |
| C. Community images | As in the source | `quay.io/metallb/frr-k8s` | Unsupportable without an exception |

**Review direction (2026-10-01; decision owner pending).** The Networking maintainers' review of pull request #2 chose option A
for FRR and `frr-metrics` and required `frr-metrics` to be fixed so that it needs no Kubernetes
cluster and exports EVPN metrics ([decision record](kickoff-decisions.md#already-settled)). The
review named no decision owner, PM and Product Security have not confirmed it, and 7505's
"approved upstream" wording is still to be edited in Jira. Consequences: the 5.1 target needs
`openshift5/frr-rhel9`, which Pyxis did not list on 2026-10-01 (`openshift4/frr-rhel9` is
published); proposed option A needs standalone and EVPN changes in that build while
preserving FIPS compatibility (below); and node-exporter's source, the RHEL base and
package access are still open.

A and B carried the same FRR 10.4.3 package in the checked baseline. OCP's `frr-metrics`
queries FRR through `/usr/bin/vtysh`. ART builds it with Red Hat Go in strict FIPS
mode (`CGO_ENABLED=1`, `strictfipsruntime`, dynamically linked against RHEL 9
glibc) even though the Containerfile asks for `CGO_ENABLED=0`. The inspected upstream
v0.0.26 binary failed `check-payload`'s CGO check; certified native Go FIPS modules
are another supported scanner path ([evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).
Qualify the selected build against its FIPS policy. node-exporter has no RHEL package; OCP's
`ose-prometheus-node-exporter-rhel9` is the Red Hat build. Whatever
is chosen, pin images in their consuming native inputs, retain resolved build/payload
evidence, and verify each binary's architecture per platform
([payload evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).

### Metrics (CORENET-7499/7504)

7499 replaces the legacy `frr_exporter` with `frr-metrics`. Upstream `frr-k8s`
(`20c36775`) gives that binary two collectors, BGP and BFD, so 7504's criteria
split as follows:

| 7504 criterion | Source | Coverage |
| --- | --- | --- |
| Appliance, VLAN and tunnel status views | node-exporter (v1.12.1): default [`netclass`](https://github.com/prometheus/node_exporter/blob/6044da783597cc3b57aef7580ddcdcff58a4ee99/collector/netclass_linux.go) (`node_network_up`, carrier and carrier-change counters for every device, so VLAN, bridge, VXLAN and WireGuard interfaces) and `netdev` counters; `systemd`, off by default, for service state | Interface/service state is available; `node_network_up=0` includes `unknown`, which can still carry traffic ([kernel semantics](https://docs.kernel.org/networking/operstates.html)). IPsec has no per-tunnel series on the appliance: `xfrm`, also off by default, gives aggregate error counters only; use CloudWatch `TunnelState` for AWS VPN tunnels; appliance-side per-tunnel views need a selected source, for example a textfile from `ipsec status` |
| BGP sessions, route churn | `frr-metrics`: per-peer, per-VRF session state and message counters (updates, keepalives, notifications) | Sessions covered; update-message counts are a churn proxy, not counts of individual route additions/withdrawals. Qualify the dashboard's stated meaning |
| Prefix counts | `frr-metrics`: sent and accepted counters **summed across every address family** of a neighbor ([`parse.go`](https://github.com/metallb/frr-k8s/blob/20c36775/internal/frr/parse.go)) | Partial: EVPN routes cannot be separated from IPv4/IPv6 on a session that carries both; OpenShift's `release-4.22` and `release-5.1` builds parse it the same way and label series only by peer and VRF |
| BFD | `frr-metrics` BFD collector: control/echo packets, session up/down events | Covered |
| VNI and MAC learning, VTEP and DF alerts | None | Gap. The legacy exporter's L2VPN collector provided them |
| DX, VPN, latency, bandwidth | CloudWatch ([`AWS/DX`](https://docs.aws.amazon.com/directconnect/latest/UserGuide/monitoring-cloudwatch.html), [`AWS/VPN`](https://docs.aws.amazon.com/vpn/latest/s2svpn/monitoring-cloudwatch-vpn.html) including `TunnelState`) | State and traffic/rates; latency needs a selected measurement source |
| Cluster-side EVPN status | OVN-K's `ovnkube_clustermanager_cluster_user_defined_networks` gains a `transport` label, and CUDN and RouteAdvertisements condition metrics are planned ([CORENET-6581](https://redhat.atlassian.net/browse/CORENET-6581), Code Review) | Complements the appliance series from the OCP side; confirm names in the selected OCP release |

**Standalone operation.** `frr-metrics` does not run outside Kubernetes on every build.
OpenShift's `release-4.22` serves plain HTTP on `127.0.0.1:7573` and needs no cluster (a
kube-rbac-proxy sidecar fronts it there). From 4.23, 5.0 to 5.2 and upstream main, since
upstream's 2026-03-24 change "Replace kube-rbac-proxy with native TLS and RBAC", it serves
HTTPS on `0.0.0.0:9141` with a self-signed certificate unless given one, authenticates and
authorizes every scrape through the Kubernetes API, and builds that handler with
`rest.InClusterConfig()` only. Upstream v0.0.26 run without a cluster exits at start-up with
`unable to load in-cluster configuration, KUBERNETES_SERVICE_HOST and KUBERNETES_SERVICE_PORT
must be defined`. The 5.x builds, which are the 5.1 target, therefore cannot serve an
appliance as they stand. The 2026-10-01 review directs `frr-metrics` to be fixed to need
no cluster; its decision owner and approvals remain pending. Whether that is an upstream
change or a maintained patch of the OCP build is open.
Interim options checked so far are the 4.22 binary, a build with authentication made optional
(upstream or a maintained patch), and node-exporter textfile series (below). Any interim
exporter needs owner approval and standalone qualification. Configure the selected
build's bind options and the deployment's TLS/authentication path explicitly; available
flags and defaults differ by release.

The 2026-10-01 review proposes adding EVPN metrics to `frr-metrics`; confirm the metric
source, series and implementation owner before targeting those new series in dashboards.
The VNI/MAC gap is a coverage choice, not an impossibility: node-exporter's textfile collector
can publish EVPN counts gathered from `vtysh ... json` and `bridge fdb` (or per-tunnel IPsec
state from `ipsec status`) without a new container, or frr-k8s can gain EVPN collectors
upstream. A textfile producer is custom code with its own owner, metric contract and
maintenance cost; choose it with the 7504 owner, and use existing FRR and bridge diagnostics
during early role/build work. None of this is a prerequisite for source CI. Confirm the OpenShift build's collectors match upstream.

When the rules arrive, use pinned `promtool check rules --lint-fatal` and
[`promtool test rules`](https://prometheus.io/docs/prometheus/latest/configuration/unit_testing_rules/)
for syntax and declared healthy, firing, recovery and missing-series cases. Native fixtures
support empty expected alerts; a healthy filter returning no series is not automatically a
failure. On the candidate, verify the required source series/labels for enabled features and
expected dashboard results under controlled states. This checks the real metric contract;
static rule tests alone do not prove live scraping or notification delivery.
No custom PromQL parser or dashboard framework is needed. Tool/runtime and consumer proof
belong to the rule check's later PRs, not the current source-CI queue.

### Disk formats and the collection

The disk set follows CORENET-7523's supported on-prem environments. The product
design places the on-prem appliance on VMware/NSX segments, but 7506/7522 name
only qcow2 and AMI. `build-vm-image` 0.3 also emits `vmdk` and `ova`, and Portal
already builds vmdk. Add a derivative Component for each approved format; do not
treat qcow2 as the vSphere deliverable. Keep AWS-specific roles, tests and
publication separable: Azure/GCP siblings OCPSTRAT-3414/3415 also target 5.1, the
same task emits vhd/gce, and the Marketplace publisher also handles Azure VHD.
CNV's GCP spike (CNV-95804) built the same on-prem role as an OpenPERouter VNF on
ESXi and names Ansible-templated FRR as the alternative. CORENET-7498 scopes Azure
and GCP out, so a unified cross-cloud design must not block AWS delivery.

The collection deploys the appliance, so each collection release must name the
appliance release it was qualified with. The source's AWS role launches the newest
CentOS Stream 9 AMI when `router_ami` is empty ([source audit](source-audit.md#2-floating-image-references)).
Resolve the relay AMI from release identity (published per-region IDs or the
Marketplace product/version) and pin the bootc update reference. Production AMI IDs
exist only after publication: either publish the collection last with that map,
or resolve at run time. Stage readback must cover whichever path is chosen.

### Konflux resource model

Use the checked Portal/KRD Application model as the baseline, but confirm the
target cluster's resource model before onboarding. ComponentGroups and NudgeConfig
are undergoing migration (STONEINTG-1381/1787); current upstream API examples do
not establish customer rollout. STONEINTG-1789/1793 explicitly gate new-model
Snapshot creation on UI/release readiness; prove build → Snapshot → test → release
on the deployed model, beyond checking that its CRDs exist.
When adding a maintained release line, qualify its own Component/test/release
configuration through a branch build, nudge and stage publication. Validate the
prepared source against the approved product-version mapping, not only its internal
consistency. See the [branch configuration checks](ci-bootstrap-spec.md#konflux-implementation-checks).

### Inputs and updates

Use native declarations in the consuming Containerfile, BIB wrapper and release reference;
retain one resolved dependency record with the build evidence. A new shared inventory
format or converter is not required. Resolve build/runtime inputs by digest and
track human-readable versions as well; 7505 allows approved tags or digests, but
only a digest fixes an image input. Use maintained RPM lockfiles and verified
prefetch for added packages, synchronized with the pinned base;
land base and necessary lockfile updates together, including on native nudge PRs.
Record installed versions too. `FROM` alone does not fix changing repositories.
Prove hermetic bootc builds in PR and push pipelines. The current BIB disk task
still uses networked pulls/tool installation; qualify its inputs, egress and
policy separately ([disk contract](bib-configuration-spec.md#enterprise-contract-and-package-access)).
Assign update ownership for bases, BIB, task/tool images, payloads,
and collection dependencies, and exercise a dependency/CVE rebuild through the
whole graph. Prove update discovery for custom resolver/script/BIB references too;
disabling Mintmaker on disk Components must not strand BIB updates.

### Nudging

Native nudging opens dependency PRs after successful push builds; it is **not proof that
the bootc ITS passed**. Keep it for candidate construction, then gate promotion on both
source-image and derivative evidence.

- **Controller.** With build-service, configure `build-nudges-ref` on bootc; approved
  integration-service nudging uses `NudgeConfig` with `immediate` edges. Start with
  build-service: integration-service nudging is still onboarding early adopters
  (STONEINTG-1744), and its GitHub App credential support, which a GitHub-hosted EVPN
  needs, was fixed on September 8 and STONEINTG-1764 is Closed as of October 8;
  that status does not qualify the deployed controller. This controller migration is separate
  from ComponentGroup adoption.
  On September 25 `NudgeConfig` also gained status types for batches that accumulate
  several builds before firing one nudge (KFLUXSE-479; no batching field in the spec yet),
  so re-read the nudge model before relying on one nudge per build. Verify ownership
  before changing either: the checked API accepts `validated`, but the implementation skips
  those edges and does not enforce `gatingGroup`
  ([migration evidence](source-evidence.md#1-candidate-construction-and-qualification-are-separate)).
- **Triggers.** Use the common-branch annotation to coalesce same-repository derivative
  PRs. `build-nudge-files` selects files to rewrite; PaC CEL selects which builds run.
  Scope bootc triggers so a disk-only nudge does not rebuild bootc and perpetuate the
  loop, as BGP Cloud Connector's operator push PipelineRun does: its `build-nudge-files`
  names the digest script its nudges rewrite, and its CEL skips pushes that change only
  that script, `bundle/` or `catalog/`
  ([`.tekton`](https://github.com/openshift/bgp-cloud-connector/blob/4e507d5d49/.tekton/bgp-cloud-connector-operator-push.yaml)).
- **Proof.** Show that the nudge updates both wrappers, triggers their builds, and
  records the actual consumed digest. Detect stranded update branches/PRs and assign
  recovery ownership. Test repeat updates where the selected controller or merge policy
  reuses branches or has a similar lifecycle risk: KONFLUX-15909 records a GitLab
  auto-merge leaving its branch behind, preventing later nudges.

### Candidate Snapshot

An automatic Snapshot combines the just-built Component with other Components from the
Global Candidate List. It can therefore contain new bootc plus old disks, or only one
updated derivative ([Snapshot behavior](https://konflux-ci.dev/docs/testing/integration/snapshots/)).

- **Assemble from evidence.** Build the candidate from recorded successful build runs and
  verified attestations, following each run's Snapshot association. Identify a build by
  its run UID and `pipelinesascode.tekton.dev/sha`, never by newest timestamp: Konflux's
  own load-test probe picked the wrong duplicate run that way (KONFLUX-16041). Monitor
  signing/Snapshot creation through a bounded deadline: quota/admission failures can
  leave a green build without a Snapshot (KONFLUX-13079). Recover from retained verified
  outputs or rebuild, then run qualification.
- **Reject inconsistent sets.** Select or construct a final candidate Snapshot and reject
  missing components or incompatible inputs. Snapshot construction omits, rather than fails
  on, a Component with no promoted image yet (a first build, or builds finishing together),
  no git source or an invalid digest, and only records that in
  `test.appstudio.openshift.io/create-snapshot-status`, so check the expected component
  set itself. Compare both disks' recorded source digests
  to the selected bootc image (including index-to-platform-child resolution), using the
  [input-binding and runtime checks](bib-configuration-spec.md#verified-task-baseline);
  stock disk-task provenance does not supply a dedicated bootc-input result. Do not
  require identical source SHAs: digest nudges legitimately introduce later commits.
- **The collection.** Test the selected collection with those disks. The Snapshot does
  not name the collection: pass its commit and built `MANIFEST.json` digest to candidate
  tests as an explicit, recorded input. A Snapshot's source revision identifies it only
  while the collection shares the image repository; a separate collection repository
  needs that input or an RHTAS-style carrier Component.

A minimal illustration for the component-set part of "Reject inconsistent sets". The
dated local proof exercised this block with six synthetic cases:
complete, missing, extra, tag-pinned, recorded omission and empty components. Those tests
pass locally (2026-10-07); deployed gate proof remains open. This block does not bind a
disk's input digest to the bootc image, which the disk-input checks above still require:

```bash
# want="bootc,qcow2,raw"  (the Component names the candidate must hold)
jq -e --slurp --arg want "$want" '
  length == 1 and (.[0] |
    ($want | split(",") | sort) as $w
    | ([.spec.components[].name] | sort) == $w
    and all(.spec.components[]; .containerImage | test("@sha256:[0-9a-f]{64}\\z"))
    and ((.metadata.annotations["test.appstudio.openshift.io/create-snapshot-status"] // "") == "")
  )
' snapshot.json
```

The single-document guard and absolute regex end are deliberate: host jq 1.8.1
controls on 2026-10-07 showed the earlier streaming check passed a trailing-newline
digest and an invalid Snapshot followed by a valid one. The revised block rejects
those, empty input, duplicates and malformed JSON; the six existing cases still pass.
Use native jq ([stream/exit semantics](https://jqlang.org/manual/#invoking-jq)), not
a new Snapshot parser or schema service. This checks the set/digest suffix only;
actual registry-reference parsing, trusted evidence and disk-input binding remain required.

### Evidence and retention

- **Bill of materials.** Retain source and nudge commits, bootc/disk index and child
  digests, companion source-container digest, collection version, tarball checksum and
  verified `MANIFEST.json` digest, payload inventory, BIB/config hashes, task bundles, resolved policy/data
  identities, Snapshot namespace/name/UID, test revisions/results, publication records,
  and AMI IDs per account/region with backing disk checksum. Preserve artifacts and
  evidence beyond PR registry expiry and cluster garbage collection.
- **Snapshot protection.** Protect the selected candidate Snapshot during qualification
  and approval using `test.appstudio.openshift.io/keep-snapshot: "true"` or an approved
  Go duration (for example, `720h`, measured from creation). Assign removal/expiry
  ownership. Snapshot garbage collection counts rather than ages: about 640 push and 70
  pull-request Snapshots per tenant namespace (quota 1024), plus the latest five
  unreleased push Snapshots per Component, so a busy nudge loop can delete an unprotected
  candidate within a day or two. A duration that cannot be parsed leaves the Snapshot unprotected,
  and protected Snapshots still count toward the limits. This protects the CR, not image
  blobs, signatures or run evidence.
- **After release.** The Release protects its Snapshot only until KubeArchive deletes the
  Release: 5 days by default, `releaseGracePeriodDays` up to 30. Set that deliberately,
  read older Release/Snapshot/PipelineRun records through KubeArchive, and recreate a
  Snapshot from the bill of materials to re-release an older candidate
  ([release retention](https://konflux-ci.dev/docs/releasing/create-release-plan/)).
  Verify those independent retention paths and retrieve required build/test and
  selected-publisher evidence after pruning with the execution-site owners.
  Reuse retained records; export logs only where qualification or recovery needs them.
- **Access.** Define reader access and sanitization for each evidence destination.
  Preserve publicly useful candidate identities, test counts and diagnostics; keep
  customer data and private lab material in access-controlled evidence storage. Prove required evidence
  completeness and safe forge reporting through the
  [CI evidence contract](ci-bootstrap-spec.md#evidence-visibility).
- **Durability.** Build releasable images without `quay.expires-after`; even `never`
  violates the release policy. Also preserve the release and upgrade baselines through
  Component/tenant retirement: deleting an ImageRepository can delete its Quay repository
  even without expiry labels. Use approved durable artifact storage or an owned
  repository-preservation path, and prove retrieval/verification after build credentials
  are removed. Include raw disks needed to recreate test AMIs, released collection
  tarballs, source containers and signed metadata; customer raw downloads remain
  optional. See [Snapshot
  retention](https://konflux-ci.dev/docs/testing/integration/snapshots/#quotas-and-garbage-collection)
  and [repository deletion](https://konflux-ci.dev/docs/building/deleting/).

## 1. Source and collection CI

Follow the [source-CI queue](ci-source.md#queue) for small,
independent Make targets and the [CI bootstrap sequence](ci-bootstrap-spec.md#later-sequence)
for role tests, native builds and dependency updates. Those contracts own tool selection,
pin/consumer proof on the selected CI runner; keep existing coverage until parity
is proven. Role tests need their own reviewed inputs/runner, not destination approval;
local builds need no tenant. The Konflux extension still meets Gate B's provenance/SBOM
requirements, and publication retains the destination's supported Ansible/AAP checks.
Provide Molecule scenarios for every shipped role (7667), starting with one real scenario
and extending coverage, reusing native role validation and product preflight assertions.
Keep ordinary checks unprivileged; use dedicated capacity for systemd, kernel,
VM/cloud and physical-topology behavior. Fix the [source findings](source-audit.md)
at their stated gates; reject invalid network/transport inputs before host mutation.

Verify source checks as [source CI](ci-source.md#how-to-add-a-check) describes. Runner,
context, trigger or status changes also need a failing run that Tide refuses to merge.

Keep collection CI independent of image orchestration, as the networking org's
`network.offline_migration_sdn_to_ovnk` does: lint, sanity and import scripts plus
migration/rollback integration on AWS clusters, all in OpenShift CI. Destination and
publisher remain [decision 15](kickoff-decisions.md) inputs. For hosted Hub, a GitHub release
through SHA-pinned ansible-content-actions' `release_ah.yaml` is an option when the owner
enables Actions (PCO-1330), as `hashicorp.vault` and validated `redhat-cop/network.*`
collections do ([examples](prior-art.md#collection-and-lifecycle-references)). AAP's Zuul
or another approved trusted native publisher can satisfy the same [publication
contract](ci-bootstrap-spec.md#collection-and-ee-artifacts): tested manifest identity,
restricted credentials and candidate approval. Publication itself does not require Actions;
the SDN-migration collection never ran its configured workflows (no workflow runs,
checked 2026-10-01) and reached Automation Hub another way (DPP-17276). CORENET-7499's interim "internal publishing workflow" is task breakdown
§1.5.16's "internal Automation Hub": the private Automation Hub in the disposable AAP that 7509
needs can serve it and doubles as the isolated trial destination. Label its contents unsupported.
Use RHTAS's Konflux carrier only if the collection must travel in the Snapshot; shipping an EVPN EE
remains optional.

CORENET-7667 requires an approved Hub or Galaxy destination. Agree the content
class, support contract, namespace and importer/signing/approval with AAP early.
Role-only content is directed toward validated content, which carries no support
requirements, and certified collections cannot depend on community collections
([content guidance](https://access.redhat.com/articles/4916901)). The EVPN
prototype is role-only and uses `community.aws`; the reviewed import's declared and
actual dependencies must determine its content class. `redhat.rhel_system_roles`
is a role-only Red Hat collection supported both from Automation Hub and as an
RPM ([delivery](https://access.redhat.com/articles/3050101)); agree which model
applies before choosing the publisher.
CDN/RPM delivery would require a separate scope decision.
AAP's Zuul publisher and a Konflux tenant publisher are alternatives; the contract holds the
trial-destination, approval and signature checks. Native Konflux collection publishing remains
unfinished (KONFLUX-5470).

## 2. Bootc and disk builds

Use the [Containerfile contract](containerfile-refactor-spec.md) for approved inputs,
RPM locks/prefetch, hermetic bootc builds, filesystem lint, effective labels/policy,
source-container publication and runtime lifecycle. Verify source archives cover
all shipped platforms/payloads and contain only publishable inputs, including
submodules. Prove the actual service manager, reboot and retained-state upgrade.
Start with a non-releasing canary and justify each target-policy exception.

Implement the [BIB contract](bib-configuration-spec.md) for the disk Components:
explicit wrapper/TOML/task wiring, approved bundles, platform-map propagation,
trusted substantive SBOMs and digest-bound source inputs. Build releasable disks
with the intended customer bootc update origin; changing origin/customization by
rebuilding creates a new candidate. Qualify persistent customer registry auth and
signature trust across install/switch/upgrade, serial HA updates and rollback,
including retained configuration and runtime payload. Keep stage credentials/trust
on disposable test hosts.

Compare the RHEL AI MAPT/cloud-importer and xKS Testing Farm/tmt backends against
actual image size, storage, network and credential needs. Neither a helper VM nor
multi-region test replication is inherently required. Extract the explicit OCI
platform/layer, reuse only an AMI whose ledger matches the disk/import identity,
and launch that exact ID. Prove launch access, booted identity, health, persistence
and reboot; a Git SHA or image name is insufficient. Verify identity again after
harness preparation: dependency installation must not silently replace the image
being qualified ([backend contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle)).
Frequent functional runs, such as relay-role and OpenShift CI interop lanes, need
not import disks: RHEL documents converting a package-mode RHEL 9.6+/10 instance
on AWS with `system-reinstall-bootc <image>`, which wraps `bootc install
to-existing-root`
([procedure](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/deploying-the-rhel-bootc-images)),
and CI can call the wrapped command directly. Release qualification still boots the
imported AMI, because that is the artifact customers receive.

## 3. Integration gates and test infrastructure

### Required tests and contexts

#### Result integrity

- Required ITSs must match the candidate's context. The Snapshot's
  `AppStudioTestSucceeded` verdict counts only required (non-optional, context-matching)
  scenarios and is `True` when there are none ("no required testing pipelines defined"), so
  an ITS that is deleted, misnamed or filtered out by context passes the Snapshot silently.
  Test Tasks must emit valid `TEST_OUTPUT`; a PipelineRun-only result is insufficient.
- The controller can pass successful pipelines with missing or skipped results, so
  enforce expected task / assertion coverage and reject missing evidence or
  infrastructure failure explicitly. Define permitted warnings; they are passing
  outcomes in Konflux.
- Require every named prerequisite to exist and finish with an accepted verdict; a
  completion waiter is insufficient
  ([checked helper behavior](source-evidence.md#2-green-status-is-not-complete-release-evidence)).

#### Context matching ([semantics](https://konflux-ci.dev/docs/testing/integration/choosing-contexts/))

- `component_<name>` matches that component's PR and push builds; multiple contexts are
  **OR**, not AND. It does not cover arbitrary manually assembled Snapshots.
- Use component tests for PR feedback and a separate non-optional **`push`-context**
  candidate suite. That context also covers ordinary manual Snapshots with no PaC
  event/PR labels. Check the complete set before expensive qualification.
- A strict `application`-context consistency test would also reject a bootc PR paired
  with old disks, preventing the merge that produces the downstream nudge.
- There is no built-in “staging” ITS context.

#### The candidate sequence ([controller order](source-evidence.md#1-candidate-construction-and-qualification-are-separate))

1. A bootc PR's group Snapshot has no derivatives. A nudge PR that rebuilds both disks
   does produce a complete group Snapshot for pre-merge checks.
2. After the nudge merges, each derivative's push build updates the Global Candidate
   List before its Snapshot is created, so the last derivative's push Snapshot normally
   holds the new bootc and both new disks. Qualify that Snapshot as the candidate.
3. The consistency preflight rejects earlier, incomplete push Snapshots. If a failed
   status on every bootc merge would mislead, report them as `SKIPPED` instead, which
   release preflight also rejects.
4. Construct a manual Snapshot only when no push Snapshot is complete, such as after a
   missing Snapshot or racing builds, and run the same required tests on it. Do not use
   an `override` Snapshot merely to select a release: it also changes the Global
   Candidate List.

Prove this PR → push → nudge → complete candidate sequence on the target cluster before
making the checks blocking.

For the Application baseline, put consistency/policy preflight before provisioning
tasks inside each costly candidate pipeline. If ComponentGroups are approved,
`testGraph` can order ITSs: set `failFast: true` on gating dependencies and prove
their contexts match; the controller omits absent/filtered parents. Select the
complete Snapshot without skipping on a different triggering component.
[Ordering contract](https://konflux-ci.dev/docs/testing/integration/order/).

### Test infrastructure and credentials

Prove that changes to test infrastructure execute at the intended revision before
making those tests blocking. Record resolved Pipeline/Task identities; use
approved immutable test revisions for release qualification.
See the [resolver canary](ci-bootstrap-spec.md#konflux-implementation-checks).

Tests consuming AWS/lab credentials run with approved source/pipeline revisions
and bounded permissions; prefer the documented Konflux OIDC → AWS STS federation
over static keys ([federation contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle)).
Enforce the [execution boundary](ci-bootstrap-spec.md#konflux-implementation-checks)
outside contributor-controlled code; publication credentials stay in release
workflows. Preserve diagnostic evidence before teardown. Key resources, evidence
and leases by PipelineRun UID; retries
must be idempotent and concurrent attempts isolated. Exclusively lease shared labs.
Reconcile the accepted attempt with the Snapshot's scenario reference. Canary
duplicates, cancellation and deterministic subnet allocation (CORENET-7120).
Reuse the selected backend's durable resource records and cleanup, plus an owned
scheduled reaper that protects active runs and retained releases. A retained run artifact
can be the ledger; this does not require a new database, service or account-wide cleanup
tool. The [AWS lifecycle contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle)
defines retention, inventory, expiry and deletion proof; monitor remaining owned resources.

The emulated EVPN lane (CORENET-7508) needs no AWS/lab credentials: it stands up a
containerlab fabric from the appliance image and runs the collection's `deploy.yml` in a
test EE, behind runner-agnostic entry points so CI only sets env and collects artifacts —
portable across Prow and a GitHub Actions VM. `test/e2e/run.sh` is the inner lane (clab
deploy -> `deploy.yml` -> validate) on a host with a kernel; `test/e2e/run_remote.sh` wraps
it for the VM model — it exports the injected base images, ships them to the target over SSH,
builds the EE and appliance images there, then runs the lane. Its toolchain (containerlab,
pytest, testinfra, skopeo) is pinned in `Dockerfile.ci`; the test EE is built by
`make ee-image`. The openshift/release Prow job wiring (the ci-operator config that calls
`run_remote.sh`) is the remaining cross-repo TODO.

### Required gates

| Required gate before supported production | Acceptance coverage / owner handoff |
| --- | --- |
| Source/API | 7499, 7501, 7667: packaging, idempotent deploy/teardown, every shipped role, validation before mutation; real trunk/VMware qualification where supported |
| Appliance | 7505, 7506, 7511: boot of each approved on-prem format and raw/AMI, reboot persistence, approved payload/egress behavior, security scanning of embedded and runtime-fetched dependencies, launch access, FIPS build/runtime and payload checks on supported architectures, supported BGP authentication, automated SSH key rotation, access restricted to required peers and endpoints, and a bridge exposure review |
| Simulated EVPN | 7508: appliance + relay + emulated workload on a containerlab fabric, three-AS eBGP Established, Type-2/3 routes, bidirectional L2 (shipped — configured by the collection's `deploy.yml` in a test EE, validated by its health check). Deferred: VNI isolation (authored as xfail pending an isolation-model decision), internet-mode MTU/MSS to 7514, frr_exporter/metrics to 7504. Still to add: explicit pytest/testinfra assertions and the openshift/release job wiring |
| DX and VPN | 7500, 7501, 7514, 7520: actual VIF/gateway/route path, inner MTU/DF/MSS, oversized UDP drop without fragmentation, IKE/IPsec, failover and dynamic-BGP/TGW ECMP when claimed; VPN relay outside data path; preflight for UDP reachability, workload MTU, latency/loss baselines and acknowledged internet-mode limits; the WireGuard relay bottleneck measured |
| HA and lifecycle | 7502, 7503, 7510: on-prem LACP/shared ES, dual-appliance inventory, Type-1/4 and DF/BFD behavior, no duplicate BUM, MAC re-advertisement, FRR-crash, power-loss and cable-pull recovery, relay ECMP, tunnel survival and BGP recovery when a relay returns; pre/post checks, serial peer upgrades, automatic rollback on failed validation, configuration compatibility |
| OCP interoperability | 7512, 7513, 7515: pinned OCP release, native primary-CUDN/VTEP/FRRConfiguration/RouteAdvertisements APIs, correct prerequisites and peer advertisements, multiple VNIs/RTs and day-2 addition of a new EVPN CUDN; supported policies/services and ARP suppression per the [networking handoff](networking-spec.md#required-handoff-to-ciqe); OCP updates with the fabric connected; no production standalone VTEP |
| End-to-end qualification | 7516–7519: ARP/BUM/TCP/UDP, isolation, forward and reverse propagation across every ASN, second OCP cluster/distinct ASN, BGP flap and reconvergence on every hop, MAC mobility/GARP/withdrawal, rapid moves and duplicate detection, cutover/rollback under traffic, appliance/relay/node/DX/VPN failures, storm containment, convergence at 100/500/1000 MACs and latency/throughput during reconvergence |
| AAP and publication | 7504, 7509, 7521–7524, OSDOCS-20531: deploy/add-stretch/health/upgrade templates, validated surveys, webhook GitOps, RBAC and production approval, applied as code to a disposable AAP; versioned dashboards/alerts/docs with native rule syntax/unit tests and expected series/labels/query states on a running candidate, including 7504's VNI/MAC views from the [agreed metric source](#metrics-corenet-74997504), a support matrix that names OCP, AWS region, FRR, transport, on-prem environment and per-transport bandwidth limits, release notes with support boundaries, and security/performance sign-off |

### OCP qualification lanes

#### Cases and evidence

- Coordinate with CORENET-7075/7564's BGP/EVPN OTE lane, and verify the expected EVPN
  cases actually execute. The OTE suite silently drops its EVPN specs unless the cluster
  has the `EVPN` feature gate, the FRR routing provider, local gateway mode and an
  external FRR container, which only the bare-metal local-gateway BGP lanes provide.
  Require a nonzero EVPN case count; suite success alone is insufficient
  ([lane-by-lane evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).
- The specs sit in `openshift/conformance/*` on 4.22 and 5.0 but only in
  `ovn-kubernetes/conformance/*` from 5.1 (CORENET-7467). The serial lane
  (`e2e-metal-ipi-ovn-dualstack-bgp-local-gw-serial`) therefore runs no EVPN serial
  cases on 5.1 and 5.2, and disruptive EVPN coverage there needs an OTE serial suite.
- Since September 24 ([#85832](https://github.com/openshift/release/pull/85832)) the
  `e2e-metal-ipi-core-networking-dualstack-bgp-lgw-ote` lane is a required presubmit on
  main, 5.1 and 5.2, and on 4.22 and 5.0 the required
  `e2e-metal-ipi-ovn-dualstack-bgp-local-gw` lane runs the specs. "Required" here means
  required if present: these jobs have `always_run: false` and no `run_if_changed`, so a PR
  runs them only after someone comments `/test <name>`, and Tide blocks on them only once
  they have run (OpenShift's Prow config does not set `require_manually_triggered_jobs`).
  Those lanes gate OVN-K changes, not EVPN candidates: for qualification, invoke the lane or an EVPN-specific
  one against the selected OCP payload and collect its result explicitly. CORENET-7564's CNO lanes merged on 2026-10-06
  ([`release` `83e107c9`, CNO config](https://github.com/openshift/release/blob/83e107c90ccaf987752096257c7489e4bc022a22/ci-operator/config/openshift/cluster-network-operator/openshift-cluster-network-operator-main.yaml));
  the added OTE jobs also use `always_run: false`. This is merged configuration, not an
  EVPN candidate run or proof the expected cases executed.
- Run the interoperability suite against each new y-stream's nightly/EC payloads before
  extending the support matrix; OpenShift CI's periodic layered-product `lp-interop`
  jobs are an existing mechanism.
- Record actual operand digests and CNO management state after job preparation;
  qualification of the supported payload must reject undeclared image overrides or
  disabled reconciliation ([conditional FRR override example](prior-art.md#preserving-the-test-subject)).

#### Clusters and accounts

- Choose a provisioner/profile or owned lab with the required external-router topology;
  a stock cloud/HyperShift cluster does not establish that capability.
- HPSTRAT-714 names ROSA as a target, while OCPSTRAT-3413 leaves managed versus
  self-managed unstated. If the 7523 matrix includes ROSA HCP, qualify it on ROSA
  clusters: OpenShift CI's `rosa-aws-sts-hcp` cluster profile, as BGP Cloud Connector
  uses, or the integration catalog's `rosa-hcp-provision` task in Konflux. CORENET-7546
  is adding BGP/EVPN e2e CI on bare-metal HyperShift.
- BGP Cloud Connector's OpenShift CI jobs already enable the FRR provider and route
  advertisements on `ipi-aws` and ROSA HCP clusters; extend that setup with local
  gateway mode, the VTEP and an external relay for an AWS EVPN lane
  ([example](prior-art.md#openshift-ci-adapters)).
- Those jobs use shared cluster-profile accounts (`openshift-org-aws`, `rosa-e2e-01`),
  while PerfScale's AWS EVPN job has its own `aws-perfscale-qe`. Lanes that create TGWs,
  VPN connections and relays need an owned profile: Boskos leases, credentials and a
  `cluster-profiles-config.yaml` entry added through `openshift/release`, optionally
  restricted to the repository or a Konflux tenant
  ([how-to](https://docs.ci.openshift.org/how-tos/adding-a-cluster-profile/)). See the
  [OpenShift CI adapter contracts](prior-art.md#openshift-ci-adapters).

#### Transports and labs

- Site-to-Site VPN can be exercised wholly in AWS with a simulated on-prem gateway (for
  example, Libreswan on an instance with a public address).
- DX needs a partner hosted connection, which the lab Terraform already anticipates.
  Order one whose parent connection is jumbo-capable, since AWS can enable jumbo frames
  on a hosted connection only then, and the 1550-byte path cannot be qualified without
  them. Run DX qualification in the release lane; agree its frequency and any
  evidence reuse with QE, preserving candidate binding and required coverage.
- CORENET-6549/6838 supply real reusable test utilities. CORENET-6566/6567 explicitly
  describe manual NSX qualification and excluded CI work: Closed is not evidence of
  automated coverage.
- CNV is building a VCF9/NSX lab in which an FRR bridge VM plays the on-prem appliance's
  role toward OCP EVPN, then validating MTV migration over it
  (CNV-94591/96841/96863/97081). Ask CNV to host the vSphere disk and cutover
  qualification there rather than building a separate NSX lab. That lab is on Red Hat's
  internal network, which public Konflux clusters cannot reach
  ([cluster decision](kickoff-decisions.md)).
- The MCN operator workstream (7006/7015/7017/7083/7084) is separate; share
  infrastructure where useful without making the appliance depend on that operator.

### OCP update paths

Qualify the supported **OCP update paths**, as well as appliance updates, with the
external fabric connected and traffic running. Record before/after OCP payloads,
node/FRR rollout, route recovery, isolation and workload continuity; include retained
post-migration state where supported. OCPSTRAT-3413 explicitly requires cluster
lifecycle interoperability. PERFSCALE-5814 expects a 5.1 release with backports
to 4.22. Select tested versions and update paths from the approved support matrix;
include 4.22 → 5.x only if that path is offered.
CORENET-6989 records passing BGP upgrade tests and deferred EVPN-to-EVPN coverage;
it is not that proof. QE owns these results and
releng binds them to the candidate/support matrix. See the [upgrade
evidence](prior-art.md#ocp-upgrade-qualification).

### Support scope and scale

A TGW-associated Direct Connect gateway requires a transit VIF. The 2026-10-01 review
interprets 7501's "private VIF and TGW associations" that way; Jira correction remains pending. Resolve the other source-contract mismatch, the per-transport inner
MTU (1500-byte workload IP packets need jumbo DX; AWS VPN leaves at most 1396 bytes), with Architecture
before implementing its check, as the
[networking handoff](networking-spec.md#required-handoff-to-ciqe) details.

Obtain explicit AWS/OCP support authorization: CORENET-7094 is on-prem scope, and
published OCP 4.22 EVPN documentation limits support to bare-metal clusters. The
4.22 BGP routing documentation is also bare-metal only; the BGP-on-AWS feature
OCPSTRAT-2448 closed as Obsolete, and OCPSTRAT-3267 now delivers AWS/ROSA routing
through Route Server as the BGP Cloud Connector operator. OCPSTRAT-3413 targets
OpenShift 5.1, so qualify on the 5.x payloads the support matrix names, not only
4.22. A successful AWS test does not establish support.
[OCP EVPN
limitations](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-evpn-for-user-defined-networks).

Keep IPv4 underlay, enabled route advertisements, `routingViaHost: true` and
`ipForwarding: Global` as the documented initial baseline;
qualify any expansion explicitly. The 4094 combined MAC-/IP-VRF-per-VTEP API
limit is not a tested scale commitment. CORENET-7537's 1000-CUDN target is distinct
from 7519's 1000-MAC gate. Agree workload dimensions and pass/fail budgets with
[PERFSCALE-5814](https://redhat.atlassian.net/browse/PERFSCALE-5814):
CUDNs, external routers, pod density and on-prem/cloud traffic. Its intake
[PRFRSR-345](https://redhat.atlassian.net/browse/PRFRSR-345) leaves scale targets
open and expects QE coverage of backports. OCP-side EVPN scale characterization
belongs to [OCPSTRAT-3769](https://redhat.atlassian.net/browse/OCPSTRAT-3769)
(5.1), whose linked bugs already record EVPN CPU and latency costs; take cluster
limits from it and measure the appliance/transport path here. Bind measurements
to the candidate; the merged AWS workload still needs product qualification. Use
CORENET-6581/OCPSTRAT-3054/3770 for OCP telemetry contracts and test dashboards
against the selected OCP version.

## 4. Promotion and operation

### Release entry gates

- **Approval and control.** Set production ReleasePlans to
  `release.appstudio.openshift.io/auto-release: "false"`; choose stage automation
  deliberately. Release automation verifies the exact candidate's required tests and
  approvals before creating Release CRs. Record the approval's candidate, channels and
  responsible approver; control who can create Releases and change the gate/publisher
  configuration. Disabling auto-release and setting an author label do not enforce that
  approval. Manual release capability is not proof that product gates passed, and
  one-shot Release CRs do not belong in a continuously reconciled GitOps directory.
- **Freezes.** Check the channel's applicable shipping freezes and approved exceptions
  at release entry and before delayed retries. Conforma's configured calendar is not a
  live freeze check; agree the release owner's enforcement path until the platform
  provides one ([freeze
  evidence](source-evidence.md#5-release-configuration-and-publication-need-their-own-gates)).
- **Resolved configuration.** For managed channels, validate the resolved RP → RPA → ECP
  and destination against the approved application/release line. Canary policy on each
  channel's mapped Snapshot as well as the complete candidate; mapping can remove an
  in-Snapshot base-image match ([policy
  contract](bib-configuration-spec.md#enterprise-contract-and-package-access)).
  Label-based RPA selection currently checks the origin namespace without enforcing its
  application allowlist (RELEASE-2372).
- **Test evidence.** Require the named suites and approved test revisions, not just an
  aggregate green status: contexts or deleted ITSs can leave a suite unexecuted. Reject
  missing, skipped, failed and infrastructure-error evidence. Recheck this in the
  release entry point (a tenant pre-release pipeline can precede managed release),
  including the collection publisher. Manual Release validation and image Conforma
  checks do not themselves enforce arbitrary EVPN integration-test requirements.
  Tenant-only publishers must enforce applicable artifact policy too; omitting a managed
  target also omits its managed verification pipeline.
- **Failing closed.** Tenant preflight, publisher and `finalPipeline` gates must make a
  failed check fail the Tekton PipelineRun. The release controller checks `Succeeded`,
  not ITS `TEST_OUTPUT`; writing a failure report while exiting successfully does not
  block release. Canary both reported failure and missing required evidence.

### Source and vulnerability assessment

- **Source.** For each component, verify attested repository/commit against approved
  source from the intended release line, including reviewed nudge commits. Snapshot
  source fields and a push label alone are not that approval; current branch-tip
  equality would also reject valid older candidates.
- **Vulnerabilities.** Reassess the exact candidate's vulnerabilities within Security's
  approved freshness window, including embedded/runtime payloads; retain scan time,
  scanner/database/policy identities and approved exceptions. Assess full vulnerability
  reports for the expected components/platforms, including non-RPM payloads: Clair's
  `SCAN_OUTPUT` summary can omit findings with an available fix but no RHSA link. Use
  the effective release policy and Security's criteria, with the
  [reporting example](prior-art.md#security-inventory-handoff) adapted to verified evidence.
- **What the release policy blocks.** Reviewed KRD roots exclude `cve.cve_blockers`
  (KONFLUX-7113); verify the effective EVPN policy and deployed enforcement before relying
  on CVE blocking. KONFLUX-15693,
  approved on September 28 (target end date estimate October 30), is meant to block
  releases missing Critical errata older than 30 days or Important errata older than
  90 days; younger gaps only warn. Its September 7 refinement thread floated starting
  release-time checks as warnings before making them mandatory, so confirm when
  blocking is enabled. With digest-pinned, hermetic inputs, errata arrive only through
  merged base-digest and lockfile update PRs; a
  [scheduled rebuild](https://konflux-ci.dev/docs/building/scheduled-builds/) of the same
  commit does not introduce newer pinned base/package inputs. Merge those PRs inside the
  windows, and keep the release preflight for Security's own criteria until the deployed
  gate proves equivalent coverage.
- **Embargo and disclosure.** Verify clearance for every public channel and map the
  release's fixed-CVE list to all affected delivered components. The managed embargo
  check examines the populated release-note CVEs; it does not discover omitted CVEs or
  replace vulnerability assessment. The checked disk-CDN pipeline lacks this task, so
  cover clearance in the existing preflight until the deployed channel proves
  equivalent enforcement. See the
  [disk delivery contract](bib-configuration-spec.md#customer-delivery-channels).

### Publication

Publish the same approved artifacts through channel-specific workflows: bootc registry
(`registry.redhat.io`, authenticated; customers' appliances update from it); disk CDN;
the approved AMI channel; Hub / Galaxy collection. Ship dashboards and alert rules
inside the collection, for example as monitoring-role files, so CORENET-7522's dashboard
publication needs no separate channel.

- **Ledger.** Reuse retained Release status, managed/internal run results and published
  identities for channel completion and retries; add only missing readback evidence to the
  selected evidence store, not another publication service/database. Reconcile
  unfinished work and completed side effects with the release owner before creating a
  replacement Release. For Marketplace, require AMI vetting evidence and reconcile
  existing versions by artifact identity; approve publisher retirement settings against
  the rollback policy ([channel contract](bib-configuration-spec.md#customer-delivery-channels)).
- **Assert before publishing.** Check each channel's exact expected component names and
  digests: mapping silently omits unmatched names, and `singleComponentMode` can reject
  a manual Snapshot. For disk downloads, also check mapped files, unique destinations and
  per-component checksums ([channel contract](bib-configuration-spec.md#customer-delivery-channels)).
  Check channel coverage against the release bill of materials.
- **Partial publication.** Define recovery for a partially published set and when
  customer update tags advance. `rh-advisories` can skip an already released Snapshot
  based on historical advisory data; retry success does not prove a mutable tag was
  restored. Stage-test release-owner-approved `skipFilter: true` re-publication or an
  explicit tag-restoration procedure, then verify live digests. Separately rehearse a
  registry retry with the correct image digest but missing required SBOM/attestation
  metadata: `push-snapshot` skips matching digests without checking attachments, and
  `skipFilter` does not disable this check. Prove a channel-owner repair procedure and
  reject incomplete customer readback
  ([pinned implementation](source-evidence.md#5-release-configuration-and-publication-need-their-own-gates)).
- **Serialization.** Serialize publication per mutable customer channel and recheck its
  current version before a retry; an older candidate needs explicit rollback
  authorization. Konflux's auto-release supersession check does not order these manual
  promotions. Rehearse two approved candidates completing out of order and retrying the
  older one.
- **Rollback.** Released registry content has no self-service rollback. Konflux releng's
  draft [rollback
  SOP](https://gitlab.cee.redhat.com/konflux/docs/sop/-/blob/f4f0e13/releng/container-release-rollback.md)
  (cached; it covers bootc) removes or re-points tags with Pub, edits Pyxis and retracts
  advisories. Re-pointing needs an existing tag on the correct digest, so give every
  release an immutable version tag (the networking org's cached BGP Cloud Connector RPA
  adds `{{ git_sha }}` and `{{ labels.version }}-{{ timestamp }}` beside the moving
  `{{ labels.version }}`), and agree this path with releng before appliances follow a
  customer update tag. A bad image on that tag reaches every appliance that upgrades
  before the fix.

### Customer readback

For Konflux releases, use each ReleasePlan's `finalPipeline`; other selected publishers
must provide equivalent customer readback for their channels:
download/checksum visibility, registry pull and required signatures, SBOMs,
attestations and source content; collection install and published AMI launch.
Use representative consumer permissions and the channel's subscription/launch access.
For AMIs, match the actual launched ID and booted identity to the publication ledger;
RHEL AI's Marketplace smoke example selects the latest match within a version stream
and needs adaptation for an exact EVPN release ([example](prior-art.md#runnable-test-patterns)).
A private test AMI or successful Pulp upload alone is insufficient (RHELDST-25997).
Make failed readback fail the publication workflow and, for Konflux, the Release;
retain the partial-publication ledger. This detects publication failures but cannot undo
published content. Tag removal
through Pub also leaves cosign and PQC signatures in place, with no removal path
(rollback SOP). The
[BIB delivery contract](bib-configuration-spec.md#customer-delivery-channels)
specifies phase handling and the AAP precedent.

### Security inventory and maintenance

Agree and canary Product Security's inventory-ingestion contract before production:
product/update stream, SBOM location and disk/collection payload coverage. Verify
each released inventory reaches that service after publication. An OCI carrier,
CI-only SBOM or product CPE alone does not establish ongoing CVE monitoring. The
internal ImageRepository template registers a build-push SBOM webhook to Bombino
(Portal's disk repositories carry it); ask Product Security whether that or a
release-time path is the contract for EVPN's disk and collection payloads.
Reuse the approved inventory and existing services; see the [security-data
examples](prior-art.md#security-inventory-handoff).
Run package/payload vulnerability updates and maintenance releases through the
same gates. Record release, networking/QE, AWS cleanup, security, AAP and support
owners, rollback authority, evidence retention, and incident routing.

## Completion

Use the [delivery plan](delivery-plan.md#next-mergeable-work) for the next mergeable changes.

Done means every required artifact is traceable to the tested compatible set,
all applicable product gates passed, customer publication/installation works,
and upgrade, rollback and cleanup were exercised. Implementation acceptance
requires real target-cluster builds; this plan audit does not claim those ran.
