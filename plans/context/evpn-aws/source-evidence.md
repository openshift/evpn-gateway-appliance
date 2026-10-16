# EVPN CI/CD — source evidence

Baseline refreshed **2026-09-24** and rechecked **2026-09-29**, with scoped follow-ups
through **2026-10-16** below. This document explains the consequential choices in the
[pipeline plan](pipeline-spec.md). [Prior art](prior-art.md) identifies reusable
files; the focused specs define implementation acceptance.

## Scope and confidence

The requirements baseline is [OCPSTRAT-3413](https://redhat.atlassian.net/browse/OCPSTRAT-3413),
[CORENET-7498](https://redhat.atlassian.net/browse/CORENET-7498), all 26 direct children
([CORENET-7499](https://redhat.atlassian.net/browse/CORENET-7499)–7524), and
[OSDOCS-20531](https://redhat.atlassian.net/browse/OSDOCS-20531). Full records and comments were
read
for those 29 records and the related work cited here. On September 29 every direct
child was still To Do and unassigned, and every cited Jira status and GitHub PR
state was rechecked. Those dated observations are baselines, not today's remote state.
Related work came from networking, Konflux, bootc, collection and release searches; this is
not an exhaustive inventory of Jira or platform capability.

**Requirements refresh, 2026-10-13:** authenticated read-only `acli` reads covered
OCPSTRAT-3413, HPSTRAT-714, CORENET-7498, all 26 requirement stories, CORENET-7615
and CORENET-7622. At that refresh the 26 were To Do; CORENET-7500 had no description. CORENET-7622
is Closed; CORENET-7620/7621 track the product imports and CORENET-7664 tracks standard source lint.
Assignments have begun. Raw records stay outside this public repository.

**Scoped requirements refresh, 2026-10-16:** CORENET-7615 requires plan review and listing
open decisions and the three Jira conflicts with proposed owners; recording decisions is
follow-up work, not a closure criterion. CORENET-7507 is Closed with YAML/Ansible lint as its
acceptance criteria. CORENET-7667 now owns per-role Molecule scenarios, VNI/ASN/transport
validation and approved Hub/Galaxy publication. The epic child search also shows 7506 and
7508 In Progress; the other original requirement stories remain To Do. These reads update
the work map without claiming a fresh review of every requirement or external source.

**Repository refresh, 2026-10-15:** main is `31cfdbb9`; source Make/YAML, the runner
switch, local image delegation and collection #7 have merged; image sources are open in
PR #16 (opened 2026-10-15), and #6 is on hold. [Source CI](ci-source.md#where-things-stand)
records the current checks and runner. The retired custom image checkers' reproduced false
passes remain dated evidence, not a replacement work queue.
Source verification does not qualify an appliance build, deployment or release.

Local native controls found the collection checksum-chain gap and qualified offline
verification on synthetic core 2.21.4 artifacts ([integrity](ci-bootstrap-spec.md#collection-content-integrity)).
They also tightened the [Snapshot illustration](pipeline-spec.md#candidate-snapshot) against
newline digest suffixes/multiple JSON documents and reproduced the
[native result formatter's limits](ci-bootstrap-spec.md#test-placement).
AWS/OCP documentation was rechecked for transport MTU/authentication and the bare-metal EVPN
support boundary. Upstream PR status/source follow-ups below distinguish merged fixes from
deployed capability. These are source, host and documentation findings; no product build,
FIPS topology, cloud import or release was qualified.

Evidence is deliberately distinguished:

- **Requirement:** product acceptance criteria or an approved platform contract.
- **Implementation:** behavior at an identified source revision; this does not
  establish the deployed version or approval for EVPN.
- **Example:** another product's implementation, with its adaptation limits.
- **Open proof:** target-cluster build, policy, test, publication or support
  evidence that the implementation team must still obtain.

Public source was read in isolated checkouts. Product source, KRD and other
internal GitLab sources are cached revisions that may lag their remotes. Private
GitHub access supplied the Portal and RHTAS
examples; private xKS MRs and the `rhel-image-tests` implementation were not
available. Jira closure was checked against comments and linked implementation.

This was a read-only source and Jira audit. No Jira issue, comment, assignment,
link or status was changed, and no live Konflux build, policy evaluation, cloud
import, publication or qualification ran. Small isolated fixtures checked source
functions and shell decisions; they are not deployment evidence and were not retained in this
repository, so rerun a finding against its cited revision before relying on it.

On September 30 the cited Jira statuses, the GitHub PRs described as open or merged, the AWS
and OCP 4.22 documentation figures, the source-audit findings against the prototype and the
`ansible-lint` baseline were checked again and matched, as were, against local checkouts, the KRD tests, the
Conforma rules, the Snapshot garbage-collection settings, the `bootc` lint list, the
`build-vm-image` interface and
the release catalog's `oras pull`. Two things were added then: the
enforcement timing of KONFLUX-15693 and HPSTRAT-714's earlier design history, whose comments
had not been read in full.

## Inspected source baselines

Reproduce a finding with the linked repository, revision and named file; no
particular checkout location is required. Short revisions identify inspected Git
objects. Resolve approved immutable bundles and deployed policy separately.

| Repository / source | Revision and scope |
| --- | --- |
| [Product source](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/tree/1c8e88873af8) | `1c8e88873af8`, September 8 (18 commits); Containerfile, roles, scripts, design and task breakdown; local clone, history rechecked September 29 |
| [KRD](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/8c18efee29) | `8c18efee29`, September 18; tenant/managed definitions, schemas and consistency tests; cached |
| [Konflux docs](https://github.com/konflux-ci/docs/tree/5b1c6329) | `5b1c6329`; Snapshot, test-context, release and nudge contracts |
| [Pipelines as Code](https://github.com/openshift-pipelines/pipelines-as-code/tree/78992f09) | `78992f09`; authorization rules and approval documentation |
| [Build definitions](https://github.com/konflux-ci/build-definitions/tree/a18268d7) | `a18268d7`; BIB task unchanged from `3349e7e2`, version 0.3.2 |
| [Multi-Platform Controller](https://github.com/konflux-ci/multi-platform-controller/tree/0cc5b509) | `0cc5b509`; allocation strategies, rootful provisioning and host/credential cleanup |
| [Container build catalog](https://github.com/konflux-ci/container-build-catalog/tree/af45de5c) | `af45de5c`; inspected index/source tasks unchanged from `094f3fe` |
| [Source-builder runtime](https://github.com/konflux-ci/build-tasks-dockerfiles/tree/5ab0fa76/source-container-build) | `5ab0fa76`, resolved from the task image's OCI revision label (`157c38d9…` digest) |
| [Build service](https://github.com/konflux-ci/build-service/tree/344dda7a), [integration service](https://github.com/konflux-ci/integration-service/tree/a5769458) | `344dda7a` / `a5769458`; inspected integration runtime unchanged from `11cc455b`, build-pipeline operation order rechecked at `c82ad7ad`, and operation order, context matching and result evaluation rechecked unchanged at `3da3b908` (September 28); nudges, Snapshot construction, test matching/results and model migration |
| [Release service](https://github.com/konflux-ci/release-service/tree/b277b37) | `b277b37`; admission mapping, tenant/final phases and workspace construction |
| [Image controller](https://github.com/konflux-ci/image-controller/tree/1775f73c) | `1775f73c`; repository preservation and robot-account deletion |
| [Release catalog](https://github.com/konflux-ci/release-service-catalog/tree/155acaca) | production `155acaca`, rechecked at `f82bf0e3` on September 29 (disk push, `push-snapshot` and disk-CDN/Marketplace pipelines); development `daf7ad8d` (managed pipeline list rechecked at `737de554`); channel pipelines and pinned task images |
| [Release utils](https://github.com/konflux-ci/release-service-utils/tree/f96d2b08) | main `f96d2b08`, GitHub release task at `8f24a5e`; pinned task-image source revisions are identified in the publication findings below |
| [Internal services](https://github.com/konflux-ci/internal-services/tree/3ad2a0bd), [common-cluster configuration](https://github.com/redhat-appstudio/infra-common-deployments/tree/e920d823) | `3ad2a0bd` / `e920d823`; cancellation and internal release-run cleanup |
| [Conforma policy](https://github.com/conforma/policy/tree/ac72407d), [CLI](https://github.com/conforma/cli/tree/8a9bb474), [central rule data](https://github.com/release-engineering/rhtap-ec-policy/tree/363039a) | `ac72407d` / `8a9bb474` / `363039a`; test, source, label, SBOM and hermetic policy |
| [Portal bootc](https://github.com/ansible-automation-platform/automation-portal-bootc-container/tree/5c34cf9d) | main `5c34cf9d`, release-2.2 `5afc61bc`; wrappers, RPM inputs, VM ITSs and proposed upgrade design; private |
| [RHEL AI pipelines](https://github.com/red-hat-data-services/aipcc-konflux-data/tree/70af2437) | `70af2437`; AWS import/test/readback/cleanup logic unchanged from `b0a320a`; upgrade ITS pipeline at `2893f77` |
| [MAPT](https://github.com/redhat-developer/mapt/tree/26c624ab), [cloud-importer](https://github.com/mapt-oss/cloud-importer/tree/bc82eac83687) | `26c624ab` / v0.0.4 `bc82eac83687`; identity, cache lookup and resource lifecycle |
| [Integration catalog](https://github.com/konflux-ci/tekton-integration-catalog/tree/1251d299), [Testing Farm adapter](https://gitlab.com/testing-farm/integrations-konflux/-/tree/10547a6) | `1251d299` / `10547a6`; task interfaces, completion waiter and credential/Snapshot handoff; inspected MAPT/waiter files unchanged from `2a46aa2` |
| [tmt](https://github.com/teemtee/tmt/tree/10bcf1d4) | `10bcf1d4`; disk rebuilding and guest dependency preparation |
| [Bootc](https://github.com/bootc-dev/bootc/tree/44c7024e), [foundry](https://github.com/osbuild/bootc-foundry/tree/5f7435d), [archived BIB](https://github.com/osbuild/bootc-image-builder/tree/a686afe) | `44c7024e` / `5f7435d` / `a686afe`; filesystem, update/security contracts and BIB migration |
| [OVN-K](https://github.com/ovn-kubernetes/ovn-kubernetes/tree/a25a653b0), [OpenShift CI](https://github.com/openshift/release/tree/f8287e1d), [kube-burner workload](https://github.com/kube-burner/kube-burner-ocp/tree/bd8a9b26) | cached OVN-K `a25a653b0`; CI `f8287e1d`, workload `bd8a9b26`; EVPN helpers, optional OTE jobs, merged AWS performance job and payload overrides |
| [OVN](https://github.com/ovn-org/ovn/tree/68936e39) | `68936e39`; `tests/ovn-northd.at` and `tests/system-ovn.at` feature-interaction regressions |
| [RHTAS collection](https://github.com/securesign/artifact-signer-ansible/tree/b89ed211), [pipelines](https://github.com/securesign/pipelines/tree/586127b5), [release scripts](https://github.com/securesign/releases/tree/e5fe10fb) | `b89ed211` / `586127b5` / `e5fe10fb`; carrier, Molecule/upgrade and publication exclusions; release scripts private |
| [AAP tools](https://github.com/ansible-automation-platform/aap-konflux-tools/tree/f2138795), [pipelines](https://github.com/ansible-automation-platform/aap-konflux-pipelines/tree/47bb13e0) | `f2138795` / `47bb13e0`; explicit candidate selection, reporting, lockfile updater and final pipeline |
| [Galaxy importer](https://github.com/ansible/galaxy-importer/tree/5af8a3f2), [Builder](https://github.com/ansible/ansible-builder/tree/de19e3eb), [content actions](https://github.com/ansible/ansible-content-actions/tree/cbdec1f7) | `5af8a3f2` / `de19e3eb` / `cbdec1f7`; validation defaults, dependency discovery and CI failure handling; working callers [`hashicorp.vault`](https://github.com/ansible-collections/hashicorp.vault/tree/3d36f142c7) and [certification checker](https://github.com/ansible-collections/partner-certification-checker/tree/f4bf7ba4d3f008b2db8fc6a812fa3f89fdf42c2e) |
| [Ansible](https://github.com/ansible/ansible/tree/4a26940b), [Galaxy NG](https://github.com/ansible/galaxy_ng/tree/04335c3a), [Pulp Ansible](https://github.com/pulp/pulp_ansible/tree/6cb4c532) | `4a26940b` / `04335c3a` / `6cb4c532`; signature verification, approval and content identity |
| [Zuul configuration](https://github.com/ansible/zuul-config/tree/61de027f), [upload jobs](https://github.com/ansible/ansible-zuul-jobs/tree/acb7ddbc), [release handbook](https://github.com/ansible-collections/cloud-content-handbook/tree/e2f14f72) | `61de027f` / `acb7ddbc` / `e2f14f72`; existing AAP publication service and rebuild assumptions |
| [RPM refresh](https://github.com/konflux-ci/refresh-rpm-lockfiles/tree/970acfcb), [presets](https://github.com/konflux-ci/mintmaker-presets/tree/091c89df) | `970acfcb` / `091c89df`; lockfile discovery and Dockerfile post-update hooks |
| [HyperShift](https://github.com/openshift/hypershift/tree/05a58d5d), [OpenShift adapters](https://github.com/openshift/konflux-tasks/tree/9751a202) | `05a58d5d` / `9751a202`; explicit promotion gate and Prow/provisioning contracts |
| [Marketplace publisher](https://github.com/release-engineering/pubtools-marketplacesvm/tree/f0bffb5), [cloudimg](https://github.com/release-engineering/cloudimg/tree/84353e6) | `f0bffb5` (2.1.4) / `84353e6`; retry matching and AMI/snapshot retirement |
| [Cloud Image Validator](https://github.com/osbuild/cloud-image-val/tree/eca2cec), [cloud-cleaner](https://github.com/osbuild/cloud-cleaner/tree/135b45d) | CIV main `eca2cec`, refactor CLI `f0ddf54`; cleaner `135b45d` |
| [External-pull RBAC](https://github.com/redhat-appstudio/infra-deployments/tree/3f76b7bf), [federation guide](https://gitlab.cee.redhat.com/konflux/docs/users/-/tree/1105e2e) | `3f76b7bf` / cached `1105e2e`; production token policy and AWS federation |
| [Security-data guidance](https://github.com/RedHatProductSecurity/security-data-guidelines/tree/c61b2152) | `c61b2152`; generic-archive PR #102 remains unmerged at `6c09776d` |
| [MicroShift](https://github.com/openshift/microshift/tree/69c4bad1), [RHEL developer guide](https://gitlab.cee.redhat.com/developer-guide/developer-guide/-/tree/4adc6644) | `69c4bad1` / cached `4adc6644`; MicroShift's bootc FIPS tests; the guide's FIPS guidance (set `fips=1` in the Containerfile's kernel arguments; `fips-mode-setup` is no longer recommended) and its image-mode testing note, which is written for RHEL components |
| [OCP build data](https://github.com/openshift-eng/ocp-build-data/tree/175405a9), [OpenShift FRR](https://github.com/openshift/frr/tree/1277b238), [OpenShift API](https://github.com/openshift/api/tree/231177cd) | `openshift-4.22` `175405a9` / `release-4.22` `1277b238` / `release-4.22` `231177cd`; Red Hat–built FRR, metrics and node-exporter payloads, ART bootc precedent and EVPN gate maturity |
| [OCP docs source](https://github.com/openshift/openshift-docs/tree/30e70de9), [OpenShift OVN-K](https://github.com/openshift/ovn-kubernetes/tree/1fc2bd44), [upstream OVN-K](https://github.com/ovn-kubernetes/ovn-kubernetes/tree/d13564c7), [OpenShift CI](https://github.com/openshift/release/tree/12c7ea28) | `enterprise-4.22` `30e70de9`; OTE `1fc2bd44`; upstream `d13564c7`; CI `12c7ea28`; EVPN limits, OTE case selection, forge-hosted EVPN lane and interop jobs |
| [Infra deployments](https://github.com/redhat-appstudio/infra-deployments/tree/61c76927), [RPM lockfile tool](https://github.com/konflux-ci/rpm-lockfile-prototype/tree/b5940ed) | `61c76927` / `b5940ed`; per-cluster rootful MPC hosts and lockfile resolution context |
| [Networking org repositories](https://github.com/openshift/bgp-cloud-connector/tree/ffcba740), [SDN-migration collection](https://github.com/openshift/network.offline_migration_sdn_to_ovnk/tree/67b3eac1), [OpenShift CI](https://github.com/openshift/release/tree/ff1189c2), [openperouter](https://github.com/openperouter/openperouter/tree/4d69e363), [downstream](https://github.com/openshift-kni/openperouter/tree/93012c12), [osbuild images](https://github.com/osbuild/images/tree/908902a8) | `ffcba740` / `67b3eac1` / `ff1189c2` / `463cab41` (CI rechecked at `4d69e363`) / `93012c12` / v0.251.0; product and collection CI, Hub release, host-mode EVPN lanes, FDP FRR and BIB image types |
| [Product definitions](https://gitlab.cee.redhat.com/prodsec/product-definitions/-/tree/ec73a7fe), [Pyxis repo configs](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs/-/tree/5a3643c), [advisories](https://gitlab.cee.redhat.com/releng/advisories/-/tree/ffa7ed0939) | cached `ec73a7fe` / `5a3643c` / `ffa7ed0939`; ProdSec streams/CPEs, Cicada repository metadata and released bootc/disk/networking advisories |

## 1. Candidate construction and qualification are separate

The [build
adapter](https://github.com/konflux-ci/integration-service/blob/11cc455b/internal/controller/buildpipeline/buildpipeline_adapter.go)
nudges after successful push builds, before ITS completion. Automatic Snapshots
combine the new Component with the Global Candidate List, so derivatives can
still refer to older bootc inputs. [RHELOPC-2368](https://redhat.atlassian.net/browse/RHELOPC-2368)
closed by rejecting its earlier
custom-nudge/IDMS proposal. Native nudges remain useful; a complete candidate and
source-image qualification are still required.

[Context matching](https://github.com/konflux-ci/integration-service/blob/11cc455b/gitops/snapshot.go)
uses OR semantics. Component contexts cover PR/push builds, not arbitrary manual
Snapshots; ordinary manual Snapshots follow the push path. An application-context
consistency gate would reject a new bootc PR against old disks before the merge
that triggers their nudge. This explains the plan's separate PR checks and required
push-context candidate gate. `override` also updates the GCL; it is not just release
selection. See [Snapshot documentation](https://konflux-ci.dev/docs/testing/integration/snapshots/).

The same gate usually needs no manual Snapshot. At `c82ad7ad` the
[build-pipeline
controller](https://github.com/konflux-ci/integration-service/blob/c82ad7ad/internal/controller/buildpipeline/buildpipeline_controller.go)
runs `EnsureGlobalCandidateImageUpdated` before `EnsureSnapshotExists`, and the
adapter updates a Component's GCL entry once its push build succeeds and is signed,
not after tests. When one nudge rebuilds both disks, the later-finishing
derivative's Snapshot therefore contains the new bootc and both new disks.
Near-simultaneous completion read through the controller's cache can still leave
both Snapshots incomplete, and supersession cancellation applies only to PR
Snapshots (`EnsureSupercededSnapshotsCanceled`), so keep a manual fallback.

A successful build may lack a Snapshot after quota/admission failure
([KONFLUX-13079](https://redhat.atlassian.net/browse/KONFLUX-13079)); the controller's
forbidden-create handling can outlive the build
object needed for retry. [KONFLUX-16041](https://redhat.atlassian.net/browse/KONFLUX-16041) closed
on September 24 as a bug in
Konflux's own load-test probe: it chose the newest build by timestamp, and a
same-second duplicate made it follow the wrong run. The fix selects by the
`pipelinesascode.tekton.dev/sha` label. EVPN's candidate tooling needs the same
discipline: follow run/Snapshot associations and verified digests, retain
recovery inputs, and qualify any reconstructed candidate.

ComponentGroup and NudgeConfig APIs do not establish deployment readiness.
[STONEINTG-1789](https://redhat.atlassian.net/browse/STONEINTG-1789)/[1793](https://redhat.atlassian.net/browse/STONEINTG-1793)
gate new-model Snapshot creation on UI/release readiness.
The [DAG implementation](https://github.com/konflux-ci/integration-service/tree/11cc455b/pkg/dag)
omits absent/filtered parents and defaults `failFast` to false. Build-service also
hands legacy nudging off when `NudgeConfig/nudge-config` exists. This handoff is
independent of ComponentGroup adoption. At `a5769458`, the
[API](https://github.com/konflux-ci/integration-service/blob/a5769458/api/v1beta2/nudgeconfig_types.go)
accepts `validated` and reserves `gatingGroup`, but the
[controller](https://github.com/konflux-ci/integration-service/blob/a5769458/internal/controller/buildpipeline/buildpipeline_adapter.go)
only processes immediate edges, with an explicit
[skip
test](https://github.com/konflux-ci/integration-service/blob/a5769458/internal/controller/buildpipeline/buildpipeline_adapter_test.go).
[STONEINTG-1717](https://redhat.atlassian.net/browse/STONEINTG-1717)
defers validated-mode documentation to Phase 2. Component-only `from`/`to` fields
also lack version selection ([STONEINTG-1835](https://redhat.atlassian.net/browse/STONEINTG-1835)).
Prove immediate nudging, release-line isolation and matching test contexts on the
deployed model before adopting these features.

## 2. Green status is not complete release evidence

The [ITS evaluator](https://github.com/konflux-ci/integration-service/blob/11cc455b/helpers/integration.go)
reads TaskRun `TEST_OUTPUT`. Isolated calls confirmed that empty results,
`SKIPPED`, `WARNING`, and `SUCCESS` with inconsistent failure counters can pass.
Adapters must enforce expected cases, counters, subjects and infrastructure
failures. The release controller instead checks PipelineRun `Succeeded` for
tenant/final phases: a report-only failure cannot block publication.

The Snapshot verdict itself is set by the status-report controller's
`EnsureSnapshotFinishedAllTests`, which loads only the required scenarios, treats `TestPassed`
and `TestWarning` as passing, and marks the Snapshot Passed when the required set is empty
(read at `main` `96c1de4f`).

Rerun on September 29 through the real `IntegrationPipelineRunOutcome` methods, identical
at `11cc455b` and `main` (`96c1de4f`): a pipeline with no `TEST_OUTPUT` at all passes, as
do `SUCCESS` with `failures: 5`, `SKIPPED` with `failures: 3`, `SUCCESS` with all counters
zero, and `WARNING` (which also sets the warning flag). `FAILURE`, `ERROR`, or any failing
task among passing ones does not pass, and neither does a result that breaks the schema:
`result` is a case-sensitive enum (`success` fails), `timestamp` must be a 10-digit epoch
or an ISO date-time, and `successes`, `failures` and `warnings` must be present and
non-negative. Unknown extra fields are accepted.

The catalog's [completion
waiter](https://github.com/konflux-ci/tekton-integration-catalog/blob/1251d299/tasks/wait-for-integration-tests/0.1/wait-for-integration-tests.yaml)
defaults `fail-on-failed-test` to false. Even with it true, running its script against a
mock `oc` on September 29 (the file is unchanged on the catalog's main) returned zero for an
absent required scenario, completed `TestInvalid`, an API failure, a missing Snapshot label
and a Snapshot whose status annotation had not been written yet, and waited only for
entries still lacking a completion time; an explicit `TestFail` returned nonzero. Of the
twelve statuses the service defines it fails only on `TestFail`, so
`EnvironmentProvisionError`, `DeploymentError`, `SnapshotCreationFailed` and the rest pass
once complete. Require named-test presence, accepted terminal verdicts and readable evidence
before proceeding.

[KONFLUX-15752](https://redhat.atlassian.net/browse/KONFLUX-15752) records duplicate
ITS runs with different Snapshot/forge references. The crash-recovery fix in
[STONEINTG-1732](https://redhat.atlassian.net/browse/STONEINTG-1732) is present in
`snapshot_adapter.go` at `11cc455b`, but [STONEINTG-1825](https://redhat.atlassian.net/browse/STONEINTG-1825)
reports another duplicate path. Its [PR #1713](https://github.com/konflux-ci/integration-service/pull/1713)
merged on 2026-10-05 at `2508848c`. Source review on October 8 confirms the
[status adapter](https://github.com/konflux-ci/integration-service/blob/2508848c0ee92ee1896de755ea38b586070348de/internal/controller/statusreport/statusreport_adapter.go)
removed that missing-status rerun-label path; the
[Snapshot adapter](https://github.com/konflux-ci/integration-service/blob/2508848c0ee92ee1896de755ea38b586070348de/internal/controller/snapshot/snapshot_adapter.go)
now propagates scenario-list errors instead of continuing with an empty list. Deployment is
unchecked. Isolate resources by run UID and bind qualification to the accepted attempt;
merged code alone does not prove the deployed recovery behavior.

Conforma has real test-attestation support, but its checked
[required-task rules](https://github.com/conforma/policy/blob/ac72407d/policy/release/tasks/tasks.rego)
default to an empty required list and carry a **2027-01-15** deny effective date.
[EC-2177](https://redhat.atlassian.net/browse/EC-2177) raises, at moderate confidence and as a
documentation task, a discovery mismatch that the code confirms: the
[subject filter](https://github.com/conforma/policy/blob/ac72407d/policy/release/lib/attestations.rego)
uses `input.image.digest`, while the
[CLI
constructor](https://github.com/conforma/cli/blob/8a9bb474/internal/evaluation_target/application_snapshot_image/application_snapshot_image.go)
supplies `image.ref` and no `digest` (still so on policy `2b85d8b1` and CLI main, September 30).
Prove required presence, trusted tasks, subject/index/child
binding and retry selection against the deployed policy before delegating EVPN's
preflight. [KONFLUX-3812](https://redhat.atlassian.net/browse/KONFLUX-3812)'s initial
design covered trusted scanners; [STONEINTG-1846](https://redhat.atlassian.net/browse/STONEINTG-1846)
now tracks redesign for user-created attestations and component versions. That
design work does not establish a deployed gate for EVPN's own suites.

[KONFLUX-14242](https://redhat.atlassian.net/browse/KONFLUX-14242) shows why attested source
correlation alone does not authorize a
release branch/commit. Current-branch-tip equality also races subsequent merges.
The reviewed KRD policies exclude one CVE rule; this alone does not establish the
effective EVPN policy or deployed CVE enforcement:
[KONFLUX-7113](https://redhat.atlassian.net/browse/KONFLUX-7113) added `cve.cve_blockers`
to the exclusions of KRD's policies, including both root policies, and 249 of the
412 ECP objects in cached KRD `8c18efee29` carry it (248 in an exclude list; 245 of
407 by unique name). [KONFLUX-15693](https://redhat.atlassian.net/browse/KONFLUX-15693) was approved
on September 28 (target end
date estimate October 30; In Progress on September 30): its acceptance criteria block release of builds
missing Critical errata older than 30 days or Important errata older than 90 days, but a
September 7 refinement comment proposes starting as a warning and making the gate
mandatory later, so the enforcement date is not established. The duplicate closure of
[KONFLUX-14210](https://redhat.atlassian.net/browse/KONFLUX-14210) did not deploy that gate. Retain
approved source/test identities
and Security's fresh candidate assessment until the deployed gate is proven.

Full scan reports and build summaries have different coverage. The checked
[`clair-scan`
task](https://github.com/konflux-ci/konflux-test-tasks/blob/da7066dd/task/clair-scan/0.3/clair-scan.yaml)
pins a `konflux-test` image whose revision label resolves to
[`93d5bd8f`'s summary
policy](https://github.com/konflux-ci/konflux-test/blob/93d5bd8fc7acab112e33cd37c07d7398d05270aa/policies/clair/vulnerabilities-check.rego).
Its patched bucket requires an RHSA link, and its unpatched bucket requires an
empty fix version; a finding with a fix but no RHSA link enters neither. An
isolated OPA evaluation with synthetic controls reproduced that omission. Conforma's
[`cve` rules](https://github.com/conforma/policy/blob/ac72407d/policy/release/cve/cve.rego)
instead consume `REPORTS` and classify patch availability by fix version.
Apply the approved release criteria to full reports; the
[RHEL AI reporting helper](prior-art.md#security-inventory-handoff) needs adaptation
before becoming a trusted full-candidate gate.

AAP's explicit-Snapshot selector/reporting and HyperShift's test→Release pattern
are reusable examples, with limits documented in [prior art](prior-art.md#build-and-release-implementations).
AAP's wrapper reports failure while returning success; its parent cancels on that
result. HyperShift's [CNTRLPLANE-3434](https://redhat.atlassian.net/browse/CNTRLPLANE-3434) incident
shows that accepted image overrides
can still be lost during deployment. Preserve the parent gate and verify runtime
artifact identity, not just supplied parameters.

## 3. Retention spans artifacts, credentials and execution sites

The [Snapshot
GC](https://github.com/konflux-ci/integration-service/blob/11cc455b/cmd/snapshotgc/snapshotgc.go)
accepts `true` or Go durations measured from creation; proposed `30d`/`forever`
examples are not its contract. Protect the selected candidate during qualification.
The [image
controller](https://github.com/konflux-ci/image-controller/blob/1775f73c/internal/controller/imagerepository_controller.go)
can delete Quay content with its last owner even without expiry labels. Repository
preservation still deletes robot credentials.
[AIPCC-20004](https://redhat.atlassian.net/browse/AIPCC-20004) supplies a real
source-repository migration that needed preservation before Component recreation.
Retain artifacts and working read authority through retirement or migration.

Snapshot retention does not retain blobs, signatures or logs. The checked
[Quay-expiration
rule](https://github.com/conforma/policy/blob/ac72407d/policy/release/quay_expiration/quay_expiration.rego)
rejects even `quay.expires-after: never`.
[AIPCC-13293](https://redhat.atlassian.net/browse/AIPCC-13293)'s AMI reclamation/backup work
remains To Do and its backup MR was reverted; prove exact-disk recreation before
reclaiming upgrade baselines.

The [internal-service cleanup
CronJob](https://github.com/redhat-appstudio/infra-common-deployments/blob/e920d823/components/internal-services/internal-production/cronjob/cleanup-internal-requests-pipelineruns.yaml)
deletes completed release runs older than `yesterday` without an archive-success
check; [KONFLUX-15431](https://redhat.atlassian.net/browse/KONFLUX-15431)'s archival work is Draft.
Tenant archival does not prove
coverage there. Release-service's archive fallback chooses by namespace/name and
resourceVersion, not expected UID. Verify recovered identity/digests and evidence
access using the release identity after pruning.

Log retention also needs content and access checks. The [catalog export
example](prior-art.md#log-export-and-public-results)
has no redaction or completeness gate; isolated fixtures reproduced successful
archives with unreadable/missing/incomplete logs. PaC's [failure
snippets](https://pipelinesascode.com/docs/api/configmap/#param-error-log-snippet)
and integration task notes are separate publication surfaces.
[SRVKP-10896](https://redhat.atlassian.net/browse/SRVKP-10896)
is Closed, but its token-only [PR #9832](https://github.com/tektoncd/pipeline/pull/9832)
closed **unmerged**. The replacement [PR #9974](https://github.com/tektoncd/pipeline/pull/9974)
is open, and [SRVKP-11864](https://redhat.atlassian.net/browse/SRVKP-11864) is in Code Review;
its checked head proposes [optional alpha
masking](https://github.com/tektoncd/pipeline/blob/182fd73d/pkg/apis/config/feature_flags.go),
disabled by default. Neither closure nor
masking of known secrets in forge snippets establishes safe raw logs or customer
data filtering. Qualify the actual deployment and each public output surface.

## 4. Build correctness requires content checks

`build-vm-image` 0.3.1 fixes newline-contaminated digest output; 0.3.2 adds the
platform map consumed by `build-image-index` 0.4.
[AIPCC-1307](https://redhat.atlassian.net/browse/AIPCC-1307),
[EC-1777](https://redhat.atlassian.net/browse/EC-1777) and
[AIPCC-32351](https://redhat.atlassian.net/browse/AIPCC-32351) address different properties:
platform descriptors, trusted SBOM
discovery and actual inventory. Keep empty artifact configs, check every child,
and reject the task's empty placeholder SBOM. A directory called `0.3` or a copied
policy exception cannot establish those results. See the [BIB contract](bib-configuration-spec.md).

The same task reads `source-image` and `bootc-builder-image` inside the source
wrapper without dedicated input-image results.
[AIPCC-17690](https://redhat.atlassian.net/browse/AIPCC-17690) closed with source
bootc provenance still an accepted gap, not a delivered feature. Bind the pinned
wrapper/config to the attested source artifact and trusted task, then verify the
booted manifest digest. Bootc's [status
test](https://github.com/bootc-dev/bootc/blob/44c7024e/tmt/tests/booted/test-upgrade-check-status.nu)
uses `status.booted.image.imageDigest`; its [aleph
record](https://github.com/bootc-dev/bootc/blob/44c7024e/crates/lib/src/install/aleph.rs)
captures the initial install and target origin, not subsequent upgrades.

The task unconditionally tags the pulled source locally, so a digest-pinned
`source-image` needs an explicit tag-form `tagged-as`. That alias sets the installed
bootc origin. Portal's main-branch wrapper named the disk repository as the update origin; its
[release-2.2
wrapper](https://github.com/ansible-automation-platform/automation-portal-bootc-container/blob/5afc61bc/disk-images/bib-portal-qcow2.yaml)
is the positive customer-origin example. Qualify production-intended disk bytes;
rebuilding to change the origin or customization creates a new candidate.

The disk task has no `HERMETIC` parameter and installs publishing tools with live
`dnf`. Conforma's [hermetic
rule](https://github.com/conforma/policy/blob/ac72407d/policy/release/hermetic_task/hermetic_task.rego)
checks only configured task names, whose defaults exclude `build-vm-image`.
Treat disk egress/tool inputs separately from hermetic bootc builds. MPC/rootful
access also does not establish KVM, remote RAM/storage or compatible host kernels
([KONFLUX-13030](https://redhat.atlassian.net/browse/KONFLUX-13030)/[15229](https://redhat.atlassian.net/browse/KONFLUX-15229)/[15338](https://redhat.atlassian.net/browse/KONFLUX-15338)).

[KONFLUX-3176](https://redhat.atlassian.net/browse/KONFLUX-3176) establishes
single-use rootful builders for amd64/arm64; the broader
[KONFLUX-9366](https://redhat.atlassian.net/browse/KONFLUX-9366) remains Draft,
including IBM architecture constraints. MPC's
[dynamic
allocator](https://github.com/konflux-ci/multi-platform-controller/blob/0cc5b509/pkg/reconciler/taskrun/dynamic.go)
terminates a VM, whereas its pools reuse hosts. Confirm the selected cluster's
profile and cleanup with the platform owner. The
[platform
policy](https://github.com/conforma/policy/blob/ac72407d/policy/release/buildah_build_task/buildah_build_task.rego)
uses [artifact-producing tasks](https://github.com/conforma/policy/blob/ac72407d/policy/lib/tekton/task.rego),
not only Buildah task names; [central rule
data](https://github.com/release-engineering/rhtap-ec-policy/blob/363039a/data/rule_data.yml)
disallows `.*root.*`. [EC-665](https://redhat.atlassian.net/browse/EC-665) and the
cached KRD xKS/Portal disk policies explain their overrides, not an EVPN approval.

[AAP-80831](https://redhat.atlassian.net/browse/AAP-80831)/[80843](https://redhat.atlassian.net/browse/AAP-80843)
and merged Portal PRs #401/#403 fix nested-pull architecture for
x86_64 with `--arch ${TARGETARCH:-amd64}`. The checked
[Containerfile](https://github.com/ansible-automation-platform/automation-portal-bootc-container/blob/5c34cf9d/bootc/Containerfile.portal-bootc-quadlet)
does not declare `ARG TARGETARCH`. The [primary argument
contract](https://github.com/containers/common/blob/a5ccdae8/docs/Containerfile.5.md#L609)
requires declaring it in each consuming stage; Buildah's
[own
fixture](https://github.com/podman-container-tools/buildah/blob/87d26719/tests/bud/multiarch/Dockerfile.built-in-args)
does so. Verify payload architecture and execution rather than inferring broader
support from the merged fallback fix.

RPM lockfile refresh must follow base changes, including native nudges.
[AAP-84409](https://redhat.atlassian.net/browse/AAP-84409)/[90611](https://redhat.atlassian.net/browse/AAP-90611)
and [AIPCC-32500](https://redhat.atlassian.net/browse/AIPCC-32500) document conflicts blocking
updates; [AIPCC-32369](https://redhat.atlassian.net/browse/AIPCC-32369)
shows a correct refresh can be byte-identical. MintMaker's Dockerfile post-update
hook is not a native-nudge hook. The AAP updater example can skip absent inputs or
publish the wrong lockfile path; prove discovery, resolution and committed output
for EVPN's layout. Fresh CVE assessment remains separate from lockfile refresh.

Source-container discovery checks the first index child and final `FROM`; other
platforms/stages need explicit completeness checks
([KONFLUX-8561](https://redhat.atlassian.net/browse/KONFLUX-8561),
[STONEBLD-4210](https://redhat.atlassian.net/browse/STONEBLD-4210)).
The task can also return `drop` with empty outputs. Its runtime
[`make_source_archive`](https://github.com/konflux-ci/build-tasks-dockerfiles/blob/5ab0fa76/source-container-build/app/source_build.py)
archives `git ls-files --recurse-submodules`: a temporary fixture confirmed that
`.containerignore` and Git `export-ignore` do not exclude a tracked file.
[KFLUXSPRT-7230](https://redhat.atlassian.net/browse/KFLUXSPRT-7230)/[3291](https://redhat.atlassian.net/browse/KFLUXSPRT-3291)
corroborate the repository-wide scope. Inspect publishability
and completeness independently; collection exclusions cover neither problem.

## 5. Release configuration and publication need their own gates

The production catalog's `check-labels` image (`8ac7a9b0…`) resolves to utils
[`51772bf1`](https://github.com/konflux-ci/release-service-utils/blob/51772bf1/scripts/python/tasks/managed/check_labels.py).
Isolated calls confirmed that a matching `canonicalName` accepts a different
destination path; without the override, that mismatch fails. This single-destination
override is intentional ([RELEASE-2185](https://redhat.atlassian.net/browse/RELEASE-2185)).
Missing `cpe` is skipped even in enforce mode; a present mismatch fails. Require
approved identity mappings and the effective required-label policy; avoid turning
[KONFLUX-16033](https://redhat.atlassian.net/browse/KONFLUX-16033)'s proposed extra
guardrails into an assumed platform guarantee.

[RELEASE-2372](https://redhat.atlassian.net/browse/RELEASE-2372) and the
[RPA loader](https://github.com/konflux-ci/release-service/blob/b277b37/loader/loader.go)
show that label-based resolution checks origin namespace but skips application/
group membership. Validate the approved RP→RPA→ECP/destination relationship.
This is not a cross-tenant bypass claim. Release attribution likewise records
identity, not independent candidate approval
([KONFLUX-1274](https://redhat.atlassian.net/browse/KONFLUX-1274),
[RELEASE-2665](https://redhat.atlassian.net/browse/RELEASE-2665)/[2786](https://redhat.atlassian.net/browse/RELEASE-2786)).

Portal's branch definitions are useful, but separate Applications can still map
to the same mutable customer tag. [AIPCC-31752](https://redhat.atlassian.net/browse/AIPCC-31752)
reports internally consistent
source from the wrong requested product line;
[AIPCC-30863](https://redhat.atlassian.net/browse/AIPCC-30863)/[31409](https://redhat.atlassian.net/browse/AIPCC-31409)/[31780](https://redhat.atlassian.net/browse/AIPCC-31780)
show stale
generated identities/references. Validate authoritative inputs and generated
outputs together. [KONFLUX-15811](https://redhat.atlassian.net/browse/KONFLUX-15811) and
[RELEASE-2827](https://redhat.atlassian.net/browse/RELEASE-2827) also demonstrate mismatches
between KRD schemas, CRDs and nested timeout handling.

Stage ECP/RPA/RP objects must exist before stage publication can be tested.
[RHELOPC-2351](https://redhat.atlassian.net/browse/RHELOPC-2351)/[2331](https://redhat.atlassian.net/browse/RHELOPC-2331)
and merged xKS definitions supply a private Marketplace pre-push
path before final listing IDs.
[RHELOPC-2326](https://redhat.atlassian.net/browse/RHELOPC-2326)/[2330](https://redhat.atlassian.net/browse/RHELOPC-2330)'s
successful multi-architecture
trials use a feature branch;
[RELEASE-2758](https://redhat.atlassian.net/browse/RELEASE-2758)/catalog PR #2453 do not establish
rollout
in the standard production catalog. Verify approved refs
([RELEASE-2775](https://redhat.atlassian.net/browse/RELEASE-2775)).

Channel mappings can silently omit unmatched components; `failOnEmptyResult`
only detects an empty set. `singleComponentMode` can reject manual Snapshots.
Reconcile exact expected names/digests for every channel. Disk CDN,
registry and collection publication are not atomic and do not share all metadata,
advisory, credential or security-check contracts.

The disk-CDN pipeline verifies Conforma **after** mapping, using the mapped
Snapshot artifact. The [base-image
rule](https://github.com/conforma/policy/blob/ac72407d/policy/release/base_image_registries/base_image_registries.rego)
permits a matching Snapshot digest, an approved `rh-release` signature, or a
configured registry prefix (deprecated upstream). Removing a base Component can
therefore remove one acceptance path. [CLI index
expansion](https://github.com/conforma/cli/blob/8a9bb474/internal/applicationsnapshot/input.go)
includes child digests; index/child mismatch is not a general reason for an
exception. [EC-1298](https://redhat.atlassian.net/browse/EC-1298) fixed SBOM digest
parsing, while [EC-1957](https://redhat.atlassian.net/browse/EC-1957) added the release
signature path. Check deployed policy/data and actual SBOM bases in both full and
channel canaries; [RHELOPC-2367](https://redhat.atlassian.net/browse/RHELOPC-2367)'s older
stage-registry workaround is not universal.

[KFLUXSPRT-8832](https://redhat.atlassian.net/browse/KFLUXSPRT-8832)/[AIPCC-32027](https://redhat.atlassian.net/browse/AIPCC-32027)
need revision-specific interpretation. At `155acaca`
(September 24) production's shell `pulp-push-disk-images` paired Portal content
directories with components by position: an isolated reversed-order fixture paired
both components incorrectly. By September 29 production had moved to
[`f82bf0e3`](https://github.com/konflux-ci/release-service-catalog/blob/f82bf0e3/tasks/internal/pulp-push-disk-images/pulp-push-disk-images.yaml),
which includes the KFLUXSPRT-8832 OOM/CGW fix and the Python conversion
(RELEASE-1990), requests `4Gi` and runs utils
[`1ca0a0a5`](https://github.com/konflux-ci/release-service-utils/blob/1ca0a0a5/src/tasks/internal/pulp_push_disk_images/pulp_push_disk_images.py)
(resolved from the task image's OCI label). That code derives each component's
directory from its destination and fails on a duplicate destination/filename, but
still logs `didn't find mapped file` and continues. Preflight exact files and
verify per-component customer readback; a ticket closure or branch name cannot
prove rollout.

An alternative is [generic CDN
delivery](https://github.com/konflux-ci/release-service-catalog/blob/155acaca/pipelines/managed/push-artifacts-to-cdn/push-artifacts-to-cdn.yaml):
[RELEASE-2460](https://redhat.atlassian.net/browse/RELEASE-2460)'s disk support reached
production. Its pinned [compression
helper](https://github.com/konflux-ci/release-service-utils/blob/66ee481c/src/helpers/compress_artifacts/compress_artifacts.py)
copies `disk-image` files unchanged; the pipeline includes Conforma, embargo and
advisory steps. However, [RELEASE-2742](https://redhat.atlassian.net/browse/RELEASE-2742)
tracks omitted disk entries for CGW-only delivery. An isolated call to the
production-pinned
[`_populate_disk_image`](https://github.com/konflux-ci/release-service-utils/blob/b52177fc/scripts/python/tasks/managed/populate_release_notes.py)
produced zero entries for `files[]` alone and one for `staged.files[]`. Utils
[`bc152cfa`](https://github.com/konflux-ci/release-service-utils/commit/bc152cfa0d5af5f9db99d367c98ab86398e2f09c)
(#1036) falls back to `files[]`; catalog
[#2562](https://github.com/konflux-ci/release-service-catalog/pull/2562)
adopted it on development on September 22, but production (`f82bf0e3` on
September 29) does not contain it. [RELEASE-2811](https://redhat.atlassian.net/browse/RELEASE-2811)'s
64 GB ISO needed a feature branch for extraction, timeouts and CGW retries; ART's
cached production RPA (`art-agent-installer-iso-4-22-prod`) pins that branch with
`files[]`, `contentType: binary` and 10h/5h timeouts. Its [advisory
2026:67708](https://gitlab.cee.redhat.com/releng/advisories/-/blob/ffa7ed0939/data/advisories/art-installer-agent-tenant/2026/67708/advisory.yaml)
lists the ISO as a `pkg:generic` artifact with filename, checksum and download URL.
Qualify artifact extraction, customer readback and advisory coverage on the
resolved revision before selection.

The checked [disk-CDN
pipeline](https://github.com/konflux-ci/release-service-catalog/blob/155acaca/pipelines/managed/push-disk-images-to-cdn/push-disk-images-to-cdn.yaml)
waits for Conforma but lacks `embargo-check`; PR #2342 remains open. The
[populate
helper](https://github.com/konflux-ci/release-service-utils/blob/b52177fc/scripts/python/tasks/managed/populate_release_notes.py)
matches fixed CVEs by exact component name; the
[embargo
helper](https://github.com/konflux-ci/release-service-utils/blob/21be4ba7/src/tasks/managed/embargo_check/embargo_check.py)
checks the resulting CVE list and skips an empty one. Neither discovers omitted
CVEs or replaces scanning. Validate clearance and component coverage in preflight.

Release calendar rules do not establish live freeze enforcement.
[Conforma's schedule
rules](https://github.com/conforma/policy/blob/ac72407d/policy/release/schedule/schedule.rego)
read configured dates/weekdays for `release`/`production` intention.
[EC-1898](https://redhat.atlassian.net/browse/EC-1898) closed after adding holiday dates
([merged change](https://github.com/release-engineering/rhtap-ec-policy/pull/249));
[KONFLUX-15222](https://redhat.atlassian.net/browse/KONFLUX-15222) still tracks live
freeze integration. Its predecessor [KONFLUX-6214](https://redhat.atlassian.net/browse/KONFLUX-6214)
reported a successful FBC release without the downstream index update, then closed
into that feature. Confirm each EVPN channel's applicable freeze/exception contract,
enforce it before publication/retry, and retain customer readback.

The [already-released
filter](https://github.com/konflux-ci/release-service-utils/blob/e03d63cb/scripts/python/tasks/internal/filter_already_released_advisory_images.py)
uses historical advisory data, not current registry refs. Production `f82bf0e3`
runs the Python port ([utils
`c830acac`](https://github.com/konflux-ci/release-service-utils/blob/c830acac/src/tasks/managed/filter_already_released_advisory_images_managed/filter_already_released_advisory_images_managed.py)),
which behaves the same, honors `skipFilter`, and is documented in `rh-advisories`
as idempotent re-release. A retry can succeed without restoring a tag; owner-approved `skipFilter`
or explicit restoration
needs stage proof. Auto-release supersession does not serialize manual releases.
Serialize mutable channels and require explicit rollback authority for older sets.

Registry attachment recovery needs a separate check. Production catalog's
[`push-snapshot`](https://github.com/konflux-ci/release-service-catalog/blob/155acaca/tasks/managed/push-snapshot/push-snapshot.yaml)
pins utils image `436b54bee56d…`, whose OCI revision label resolves to
[`push_image` at
`b16f61b0`](https://github.com/konflux-ci/release-service-utils/blob/b16f61b005039c3adeb496571b36ff89e9acef2b/src/tasks/managed/push_snapshot/push_snapshot.py).
It returns success on matching destination image digest before inspecting or
copying attachments. Three isolated source-function cases covered clean copying,
a matching image with missing metadata, and a simulated partial-copy failure
followed by a new invocation. The latter two returned success without repairing
metadata. `skipFilter` only bypasses the earlier advisory filter. Require missing
metadata detection and an approved repair path in stage; source containers are
separate copy jobs and need their own readback. Preserve required build evidence,
but distinguish it from customer release signatures:
[RELEASE-2771](https://redhat.atlassian.net/browse/RELEASE-2771)'s
[merged change](https://github.com/konflux-ci/release-service-utils/pull/1011) stops copying build signatures,
still has this digest shortcut, and is absent from this production task image.
[RELEASE-2738](https://redhat.atlassian.net/browse/RELEASE-2738) and
[RELEASE-2439](https://redhat.atlassian.net/browse/RELEASE-2439)
track additional signature/attestation verification; they do not supply EVPN's
channel-specific acceptance evidence.

The disk publisher's [InternalRequest
cleanup](https://github.com/konflux-ci/release-service-utils/blob/467ae840/scripts/python/helpers/internal_request/internal_request.py)
is scoped to the parent run UID, not all replacement runs. Its
[Portal update
helper](https://github.com/konflux-ci/release-service-utils/blob/1548d6dc/utils/cgw_idempotency.py)
can replace a newer download under the same logical filename when an older release
is retried. Reconcile remote side effects and termination before retrying.

`finalPipeline` runs after managed processing finishes, including failures, and
must succeed before the Release succeeds. Waiting inside it for `Released=True`
is circular. Failed readback cannot undo publication. Automatic retry handling
covers eligible managed failures, not arbitrary tenant/final failures; inspect
deployed retry configuration and preserve attempt identities. Its
[workspace
builder](https://github.com/konflux-ci/release-service/blob/b277b37/tekton/utils/pipeline_run_builder.go)
applies the controller size to PVC and `emptyDir` alike (upstream default `1Gi`);
`emptyDir` is not shared across Tasks. Use streaming or appropriately sized
approved backends for disk readback.
[RELEASE-2811](https://redhat.atlassian.net/browse/RELEASE-2811)/[2832](https://redhat.atlassian.net/browse/RELEASE-2832)
show real internal storage/
parent-timeout failures; small CDN fixtures do not qualify large EVPN artifacts.

The [managed retry
path](https://github.com/konflux-ci/release-service/blob/b277b37/controllers/release/adapter.go)
reloads processing resources without rerunning a completed tenant preflight.
Keep approved inputs and channel serialization valid across attempts. The same
controller can recreate a deleted active PipelineRun
([KONFLUX-11968](https://redhat.atlassian.net/browse/KONFLUX-11968)); exercise
explicit cancellation and remote-work termination instead of deleting the run.
[RELEASE-2113](https://redhat.atlassian.net/browse/RELEASE-2113)'s September 16 update separates
deployed retry code from planned
configuration enablement; inspect the actual RPA status rather than ticket closure.

## 6. Customer channels have independent identity and trust contracts

The [Marketplace
publisher](https://github.com/release-engineering/pubtools-marketplacesvm/blob/f0bffb5/src/pubtools/_marketplacesvm/cloud_providers/aws.py)
skips existing versions using title substring matching, without comparing AMI
identity. `restrict_version=true` can delete retired AMIs and backing snapshots;
RHEL AI's production setting is not EVPN's retention policy. Isolated method
calls confirmed matching/deletion decisions without cloud calls. Qualify the
library version inside the actual release image and retain an exact channel ledger.

It is Konflux's only managed AMI publisher. The production catalog's
`marketplacesvm-push-disk-images` task runs release-service-utils'
[`marketplacesvm_push_wrapper`](https://github.com/konflux-ci/release-service-utils/blob/dae9d47bd9/pubtools-marketplacesvm-wrapper/marketplacesvm_push_wrapper.py),
whose command is `pubtools-marketplacesvm-marketplace-push`; the library's
`community-push` and combined entry points, which publish community AMIs with RHSM
registration, are not called ([KONFLUX-9757](https://redhat.atlassian.net/browse/KONFLUX-9757),
New, scopes both marketplace and community delivery). All 17 cached KRD RPAs using
the pipeline are Marketplace listings for RHEL AI or xKS. The task's `oras pull`
passes no `--platform` in the production (`f82bf0e3`) and development catalogs
(checked September 29), so a multi-architecture index overwrites same-named files
([RHELOPC-2326](https://redhat.atlassian.net/browse/RHELOPC-2326); fix in open
catalog PR #2453). CORENET-7506's "approved AWS workflow" comes from task
breakdown §3.2.3 ("via VMImport or EC2 Image Builder"), which describes building an
AMI, not a Red Hat publication channel. RHEL accepted a
CDN download alone for its AWS CVM Tech Preview, deferring the AMI to GA
([RHELDST-37290](https://redhat.atlassian.net/browse/RHELDST-37290),
[RHELOPC-1651](https://redhat.atlassian.net/browse/RHELOPC-1651)).

[AWS AMI requirements](https://docs.aws.amazon.com/marketplace/latest/userguide/product-and-ami-policies.html)
include source-region, disk/encryption and SSH vetting beyond private import/boot.
The [Test ‘Add version’
scan](https://docs.aws.amazon.com/marketplace/latest/userguide/best-practices-for-building-your-amis.html)
needs an existing AMI product and does not publish a version.
[RHELOPC-2324](https://redhat.atlassian.net/browse/RHELOPC-2324)'s
private AMIs and [CLOUDX-495](https://redhat.atlassian.net/browse/CLOUDX-495)'s won't-do closure do
not establish that qualification.
RHEL AI's Marketplace smoke selects the latest version-stream match; adapt to
exact published regional IDs and representative customer access.

Collection identity does not require identical tarballs. In ansible-core (2.21.0
and devel `4a26940b`),
[`verify_local_collection`](https://github.com/ansible/ansible/blob/4a26940b/lib/ansible/galaxy/collection/__init__.py)
checks `MANIFEST.json` against the server's hash, then `FILES.json` and each file
hash, and signatures are detached signatures of `MANIFEST.json`. Two isolated
builds of `network.offline_migration_sdn_to_ovnk` at `67b3eac1` produced different
tarball digests (archive timestamps) but identical `MANIFEST.json` and `FILES.json`.
A rebuild-from-tag publisher is therefore acceptable when the published manifest
matches the tested digest. Such a publisher is in use where Actions runs: Red Hat's
`hashicorp.vault` has seven successful release-event runs of ansible-content-actions'
`release_ah.yaml` that built and published to Automation Hub with service-account
credentials. The networking org's SDN-migration collection and Portal's collection
configure the same caller, but neither repository has ever run it: both have zero
release-event runs and no GitHub releases, and the SDN-migration repository has no
Actions runs at all because the `openshift` org disables Actions by default
([DPP-17276](https://redhat.atlassian.net/browse/DPP-17276),
[PCO-1330](https://redhat.atlassian.net/browse/PCO-1330)).
Its working CI is Prow. [ANSTRAT-2159](https://redhat.atlassian.net/browse/ANSTRAT-2159)
dropped Portal's collection GA from scope ([examples](prior-art.md#collection-and-lifecycle-references)).

RHTAS proves a Konflux carrier and Molecule/upgrade path; its release scripts
skip collection publication. [AAP-77136](https://redhat.atlassian.net/browse/AAP-77136)
identifies another working Zuul→Hub service.
[KONFLUX-5470](https://redhat.atlassian.net/browse/KONFLUX-5470)'s
native support remains New. A tenant publisher is technically possible, but a
separate service account in the build namespace does not isolate its secrets from
workload creators. Apply the [Konflux trust model](https://konflux-ci.dev/docs/trust-model/).

Hub `staging` can feed approval/auto-promotion; it is not inherently an isolated
rehearsal destination. Wait for import, required approval and endpoint visibility
([AAP-47430](https://redhat.atlassian.net/browse/AAP-47430)/[78090](https://redhat.atlassian.net/browse/AAP-78090)/[93498](https://redhat.atlassian.net/browse/AAP-93498)/[93724](https://redhat.atlassian.net/browse/AAP-93724)).
Current Pulp content identity does not guarantee immutable namespace/name/version
content, so compare the manifest on retries.

Importer defaults disable sanity tests, and its local `ansible-test` path can
log failures without failing import. Builder metadata paths are collection-root
relative and missing runtime dependencies can be importer warnings.
[AAP-81769](https://redhat.atlassian.net/browse/AAP-81769),
93724 and 94061 support installed-archive introspection, a supported EE matrix,
and tests of fresh/minimum dependency resolution. Carrier RPM SBOMs do not inventory
collection dependencies; native Galaxy prefetch remains open
([STONEBLD-3730](https://redhat.atlassian.net/browse/STONEBLD-3730)).

Collection signatures cover `MANIFEST.json`, separately from any OCI carrier.
The [Ansible
verifier](https://github.com/ansible/ansible/blob/4a26940b/lib/ansible/galaxy/collection/__init__.py)
accepts an empty signature set with `1`/`all`; use `+1` or the approved stricter
count and test actual server-provided signatures. Bootc/Podman customer pulls
likewise need their own trust-path checks:
[KFLUXSPRT-6108](https://redhat.atlassian.net/browse/KFLUXSPRT-6108)/[6608](https://redhat.atlassian.net/browse/KFLUXSPRT-6608)
and [RELEASE-2179](https://redhat.atlassian.net/browse/RELEASE-2179)
report tag/platform/client-specific failures despite successful publication.
Their support workarounds are not an EVPN instruction to delete signatures.

Finally, advisory publication does not prove ongoing CVE inventory ingestion.
[KONFLUX-15417](https://redhat.atlassian.net/browse/KONFLUX-15417),
[PSSECAUT-1609](https://redhat.atlassian.net/browse/PSSECAUT-1609) and
[PSDEVOPS-4819](https://redhat.atlassian.net/browse/PSDEVOPS-4819) report generic-artifact collector
gaps. [Actual advisory examples](prior-art.md#security-inventory-handoff) distinguish
archive rows without SBOM URLs from usable inventory links. Agree and verify the
disk/collection product-stream ingestion contract; do not invent a PURL scheme
from the still-unmerged generic-archive proposal.

## 7. Test backends require adaptation and lifecycle ownership

RHEL AI MAPT/cloud-importer and xKS TF/tmt are alternatives, not mandatory helper
VM or multi-region architectures.
[RHELOPC-2264](https://redhat.atlassian.net/browse/RHELOPC-2264)/[2265](https://redhat.atlassian.net/browse/RHELOPC-2265)
remain In Progress;
2650 closed into MR review follow-up 2754. Private xKS implementation was not
verified. [Runnable examples](prior-art.md#runnable-test-patterns) identify:

- Trigger-component selectors that fail or skip complete manual candidates.
- Git-SHA/name-prefix AMI caches that do not prove disk identity or availability.
- Testing Farm's shared floating bundle/runtime tag and separate test revision.
- tmt's new-disk provisioner and dependency installation that can replace the
  booted image; verify the candidate again after preparation
  ([TFT-3177](https://redhat.atlassian.net/browse/TFT-3177)).
- Prow's fixed jobs, missing `TEST_OUTPUT`, and remote runs left on interruption.
- HyperShift's useful explicit dispatch/runtime-identity pattern and owned cluster claims.

AWS federation must survive the actual execution path. RHEL AI's helper handoff
copies access/secret keys without STS tokens; MAPT itself supports session tokens.
Use a renewable provider in the federated pod or qualify the helper's independent
identity. VM Import's service role/PassRole is separate from caller authentication.
Private OCI pulls also need independent authority: the image proxy grants
tenant-level ImageRepository access, and production policy can reject legacy
service-account token Secrets
([KFLUXSPRT-8816](https://redhat.atlassian.net/browse/KFLUXSPRT-8816)). Prove the allowed token
lifetime,
renewal and digest pull using the actual external identity.

The [cloud-cleaner example](prior-art.md#cloud-image-tests-and-cleanup) can delete
old untagged resources, omits pagination and prints deletion errors without failing.
[RHELOPC-2762](https://redhat.atlassian.net/browse/RHELOPC-2762) proposes evaluation/setup, not
completed xKS adoption. Protect retained
releases and active runs, inventory every owned resource type and monitor reaper
execution/results. Finalizers alone cannot cover host loss;
[AIPCC-32477](https://redhat.atlassian.net/browse/AIPCC-32477) documents
runner-orphan quota exhaustion. CIV supplies exact-AMI assertions, but its refactor
collector merges only present XML and its main tests include mutable-RHEL assumptions.

Forge merge checks need demonstrated coverage: exercise the current commit, delayed
triggers, replacement commits and retries. Updater incidents:
[KONFLUX-15909](https://redhat.atlassian.net/browse/KONFLUX-15909)/[KFLUXSPRT-9022](https://redhat.atlassian.net/browse/KFLUXSPRT-9022)
describe stranded bot branches on GitLab; token rotation can also
stop new MRs. MintMaker defaults to `.tekton/` and may miss custom/script references.

External-contributor authorization is a separate onboarding check. PaC documents
[SHA-qualified
approval](https://pipelinesascode.com/docs/guides/gitops-commands/#requiring-a-sha-with-ok-to-test)
as GitHub-App-only Technology Preview. Prove the selected forge's authorization and
reporting paths with a replacement commit, so that an earlier `/ok-to-test` does not
carry over to new code; do not prescribe these settings as a universal fix.

[KONFLUX-9110](https://redhat.atlassian.net/browse/KONFLUX-9110) closed administratively into still-New
[KONFLUX-9125](https://redhat.atlassian.net/browse/KONFLUX-9125), concerning Tekton parameter injection.
Tekton's documented substitution contract requires task authors to handle escaping.
Review input handling as well as trusted task identity. Kubernetes also documents
that [workload creation](https://kubernetes.io/docs/concepts/security/rbac-good-practices/#workload-creation)
can expose namespace Secrets and service accounts; selected service-account names
alone do not separate unapproved contributions from credentialed qualification.

## 8. Runtime and support qualification remain product work

Bootc's [filesystem contract](https://bootc.dev/bootc/bootc-filesystem.7.html) distinguishes
first install from upgrades: `/run` is runtime state, `/var` persists, and local
`/etc` changes can mask image defaults.
[RHEL-135034](https://redhat.atlassian.net/browse/RHEL-135034) records a service that works on a
fresh install but fails after `bootc switch` on an existing host, because its new
`/var` directory had no tmpfiles entry. The EVPN source also tests
service facts without gathering them, selecting its direct-Podman fallback.
Test the actual manager, reboot, retained state and prior runtime payload.

[CORENET-7510](https://redhat.atlassian.net/browse/CORENET-7510) requires serial HA upgrades and
automatic rollback; bootc does not
run Containerfile `HEALTHCHECK` as a host rollback controller. Test reachable and
unreachable failures, persistent registry auth and signature policy across
install/switch/upgrade, plus first-boot readiness and interrupted prefetch
([recovery examples](prior-art.md#host-update-and-recovery)). Portal's
[AAP-72802](https://redhat.atlassian.net/browse/AAP-72802) closed a spike; its upgrade ADR remains
Proposed. MicroShift/RHTAS offer [FIPS test examples](prior-art.md#fips-build-and-test-examples),
but those products' exceptions and platform coverage are not EVPN qualification.

CORENET-7498 settles DX/VPN as production transports and WireGuard as development/
test only. AWS requires a transit VIF for DX gateway→TGW, correcting
[CORENET-7501](https://redhat.atlassian.net/browse/CORENET-7501)'s
private-VIF wording. MTU depends on the actual path: AWS
[Site-to-Site VPN](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html#vpn-quotas-mtu)
supports at most a 1446-byte tunnel MTU (1406–1446 by algorithm, per the
[customer gateway best-practices
table](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-best-practice.html)), no jumbo frames
and no PMTUD, so a 1500-byte workload IP MTU over IPv4 VXLAN needs jumbo DX.
[Published OCP 4.22 EVPN
support](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-evpn-for-user-defined-networks)
is bare-metal only. AWS interoperability tests cannot authorize product support.

OCPSTRAT-3413 requires cluster lifecycle qualification as well as appliance
upgrades. [CORENET-6989](https://redhat.atlassian.net/browse/CORENET-6989) records passing BGP
upgrade tests and defers EVPN→EVPN coverage;
[OCPBUGS-114403](https://redhat.atlassian.net/browse/OCPBUGS-114403) and merged OVN-K PR #6866 give
a retained-state failure/fix to check
in the selected payload. Some of OpenShift CI's OTE lanes (#85482) became required-if-present OVN-K
presubmits on September 24 (#85832; section 9 lists them) but none is an upgrade lane;
[CORENET-7564](https://redhat.atlassian.net/browse/CORENET-7564) is In Progress. Closed NSX work
excludes automated CI.
The reusable BGP setup also retains a conditional FRR override that unmanages CNO
([CORENET-6591](https://redhat.atlassian.net/browse/CORENET-6591)/[6592](https://redhat.atlassian.net/browse/CORENET-6592));
verify actual operands and reconciliation state after setup.
Use the [networking handoff](networking-spec.md) and the plan's supported matrix
to agree QE evidence without making all production work a source-CI prerequisite.

## 9. Payload, platform and OCP test inputs

Red Hat already builds equivalents of the appliance's runtime payloads. ART's 4.22
[`ose-frr.yml`](https://github.com/openshift-eng/ocp-build-data/blob/175405a9/images/ose-frr.yml)
delivers `openshift4/frr-rhel9` from the OpenShift FRR repository, whose
[Containerfile](https://github.com/openshift/frr/blob/1277b238/Dockerfile.openshift)
installs `frr10` and copies `/frr-metrics` and `/frr-status` into the image. The
same file has shipped `frr-metrics` since at least `release-4.20`. [PR #130](https://github.com/openshift/frr/pull/130)
moved 4.22 to FRR 10.4.3 for EVPN; the source pulls upstream 10.5.3.
[`golang-github-prometheus-node_exporter.yml`](https://github.com/openshift-eng/ocp-build-data/blob/175405a9/images/golang-github-prometheus-node_exporter.yml)
delivers `openshift4/ose-prometheus-node-exporter-rhel9`. `frr-metrics` runs
`show bgp vrf … neighbors json` and BFD queries and, on `release-4.22`, binds to
`127.0.0.1:7573` by default; later branches differ ([standalone
operation](pipeline-spec.md#metrics-corenet-74997504),
[collectors](https://github.com/openshift/frr/tree/1277b238/cmd/metrics)). It
has no VNI, MAC or VTEP series, unlike the source's `--collector.bgpl2vpn` exporter
configuration. CORENET-7504's acceptance criteria require those views.

That image's FRR is an ordinary RHEL package. [RHEL-125957](https://redhat.atlassian.net/browse/RHEL-125957)
added `frr10` to RHEL 9 AppStream in 9.8 (RHBA-2026:18821, May 19) for OpenShift's
EVPN features. [RHEL-155911](https://redhat.atlassian.net/browse/RHEL-155911) fixed
its image-mode `/var` handling and [RHEL-157859](https://redhat.atlassian.net/browse/RHEL-157859)
moved it to 10.4.3 for EVPN fixes (RHBA-2026:19195). Its CVE trackers follow the
RHEL errata process (for example, RHEL-193237). RHEL 9.7 has no `frr10`,
and 9.6 EUS delivery remains open in [RHEL-134995](https://redhat.atlassian.net/browse/RHEL-134995).
CentOS Stream 9 AppStream carries `frr10-10.4.3-4.el9`; its file list includes
`frr.service`, sysusers entries and tmpfiles lines creating `/run/frr` and
`/var/log/frr`, and it conflicts with `frr`. OpenShift FRR's `release-5.1` Containerfile
installs `frr10` on a RHEL 9 base and `frr` on a RHEL 10 base; ART builds 5.1 on
RHEL 9. OCP has no separate frr-k8s image: the same Containerfile copies the
frr-k8s controller, reloader, `frr-metrics` and `frr-status` into `frr-rhel9`, and
CNO deploys frr-k8s with `FRR_K8S_IMAGE` set to that `metallb-frr` payload
([CNO
`release-4.22`](https://github.com/openshift/cluster-network-operator/blob/80ad6fc01b/manifests/0000_70_cluster-network-operator_03_deployment.yaml)).
Upstream, `/frr-metrics` ships in `quay.io/metallb/frr-k8s`, which the task
breakdown (§1.5.12, §3.1.2) names; §3.1.1 and §3.1.3 name the community FRR and
node-exporter images, which is where CORENET-7505's "approved upstream" wording
comes from. The design's rationale, that its FRR container is "the same upstream
image used by OVN-Kubernetes and FRR-K8s in OpenShift", holds only for upstream
kind CI. The metrics exporter queries FRR through
`/usr/bin/vtysh` ([`vtysh.go`](https://github.com/openshift/frr/blob/1277b238/cmd/metrics/vtysh/vtysh.go)).
The Containerfile builds it with
`CGO_ENABLED=0`, but ART's builder overrides that: `go version -m` on `/frr-metrics`
from `openshift4/frr-rhel9:v4.22.0-202609221726.p2.g1277b23.assembly.stream.el9`
(amd64; `frr10-10.4.3-3.el9_8.2`, CPE `cpe:/a:redhat:openshift:4.22::el9`) reports
Red Hat Go 1.25.14, `CGO_ENABLED=1`, `-tags=strictfipsruntime` and
`GOEXPERIMENT=strictfipsruntime`, and the binary links glibc dynamically.
[`check-payload`](https://github.com/openshift/check-payload/blob/813ddada/internal/validations/validations.go)
rejects crypto-using Go binaries without CGO (`ErrGoNotCgoEnabled`) unless they use a
certified Go FIPS 140 module; its release configurations carry no FRR exception. A scan of
upstream v0.0.26's `/frr-metrics` (amd64, Go 1.25.8, `CGO_ENABLED=0`, statically linked) with
`check-payload` `813ddada` and the embedded 4.22 rules reported `go binary is not CGO_ENABLED`.
OpenShift CI's `fips-check-image-scan` step runs `check-payload scan local` on an
unpacked image. RHEL's
[Application Streams life cycle](https://access.redhat.com/support/policy/updates/rhel-app-streams-life-cycle)
lists an FRR 10 stream for RHEL 9, from 9.8 (May 2026, retiring November 2030),
beside the full-life FRR 8; its RHEL 10 tables list no FRR stream.
No RHEL AppStream package provides node_exporter. Fast Datapath is a third source: OpenPERouter's productized
operator image (Konflux `telco-5g-tenant`) installs `frr-10.7.0-3` from
`fast-datapath-for-rhel-10` since [openperouter #480](https://github.com/openshift-kni/openperouter/pull/480)
(CNV-96018, September 17). A RHEL 9 FDP build ([OSPRH-35211](https://redhat.atlassian.net/browse/OSPRH-35211))
closed, but its advisory entry was dropped on September 22, so confirm shipment
before relying on FDP for a RHEL 9 appliance.

ART builds OCP 4.22 on Konflux with hermetic lockfiles
([`group.yml`](https://github.com/openshift-eng/ocp-build-data/blob/175405a9/group.yml)).
Its [MicroShift bootc
image](https://github.com/openshift-eng/ocp-build-data/blob/175405a9/images/microshift-bootc.yml)
builds `openshift4/microshift-bootc-rhel9` from `rhel-bootc:9.8` with a separate
release process ([USHIFT-4024](https://redhat.atlassian.net/browse/USHIFT-4024)).
It is the precedent for shipping a bootc image under OpenShift instead of a team
tenant. Its comment records that bare lockfile resolution omitted base-kernel
conditional dependencies and broke the hermetic build. The
[lockfile tool](https://github.com/konflux-ci/rpm-lockfile-prototype/blob/b5940ed/README.md)
resolves against an image's rpmdb through `context.image` or a Containerfile.

The product's [L2-stretch
plan](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af8/docs/evpn-l2-stretch-plan.md)
places the on-prem appliance on VMware/NSX segments. `build-vm-image` 0.3 accepts
`vmdk` and `ova`
([task](https://github.com/konflux-ci/build-definitions/blob/a18268d7/task/build-vm-image/0.3/build-vm-image.yaml)),
and archived BIB documents [vmdk as the vSphere
format](https://github.com/osbuild/bootc-image-builder/blob/a686afe/README.md).
bootc-foundry's [`rhel-10-ec2`](https://github.com/osbuild/bootc-foundry/blob/5f7435d/rhel-10-ec2)
shows an explicit EC2 delta: cloud-init, `nm-cloud-setup`, and Amazon time/SSH
settings. Both candidate Konflux clusters define dynamic `linux-root-amd64` and
`linux-root-arm64` MPC hosts
([`kflux-prd-rh02`](https://github.com/redhat-appstudio/infra-deployments/blob/61c76927/components/multi-platform-controller/rings/ring-4/kflux-prd-rh02/host-values.yaml),
[`stone-prod-p02`](https://github.com/redhat-appstudio/infra-deployments/blob/61c76927/components/multi-platform-controller/rings/ring-3/stone-prod-p02/host-values.yaml)).
The networking org's CORENET-7409 tenant is on `kflux-prd-rh02` (cached KRD).

The [4.22 EVPN documentation
source](https://github.com/openshift/openshift-docs/blob/30e70de9/modules/nw-bgp-evpn-about.adoc)
states bare-metal-only support and IPv4 VTEPs, and requires `routingViaHost: true`
and `ipForwarding: Global`. Its
[procedure](https://github.com/openshift/openshift-docs/blob/30e70de9/modules/procedure-enabling-bgp-evpn-primary-cudn.adoc)
requires `Unmanaged` VTEP mode and recommends a dummy interface for redundant
peering. The product design instead uses each node's primary VPC address because
TGW learns only the CIDRs of attached VPCs from those attachments. [VPC Route
Server](https://docs.aws.amazon.com/vpc/latest/userguide/dynamic-routing-route-server.html)
can program VPC and subnet route tables from BGP, but TGW needs Transit Gateway
Connect or static routes. The [`EVPN` feature
gate](https://github.com/openshift/api/blob/231177cd/features/features.go)
is enabled in the 4.22 Default set.

OpenShift's OTE binary [drops `Feature:EVPN`
specs](https://github.com/openshift/ovn-kubernetes/blob/1fc2bd44/openshift/cmd/ovn-kubernetes-tests-ext/main.go)
unless
[`CheckForEVPN`](https://github.com/openshift/ovn-kubernetes/blob/1fc2bd44/openshift/test/infraprovider/openshift.go)
finds the gate, the FRR provider, local gateway mode and an external FRR container.
The [release-4.22
binary](https://github.com/openshift/ovn-kubernetes/blob/b05c351ca4/openshift/cmd/ovn-kubernetes-tests-ext/main.go)
parents its suites into `openshift/conformance/*`, as does
[release-5.0](https://github.com/openshift/ovn-kubernetes/blob/b05c351ca4/openshift/cmd/ovn-kubernetes-tests-ext/main.go),
so default-suite jobs such as the local-gateway BGP lane can run EVPN specs there.
Main dropped that parenting in [CORENET-7467](https://redhat.atlassian.net/browse/CORENET-7467)
(`5f0f1d0a55`), and
[release-5.1](https://github.com/openshift/ovn-kubernetes/blob/5f0f1d0a55/openshift/cmd/ovn-kubernetes-tests-ext/main.go)
has no parents.
At CI `12c7ea28`, no OVN-K job selects EVPN explicitly; the #85482 OTE lanes set
`ovn-kubernetes/conformance/parallel`. The [release-5.1
configuration](https://github.com/openshift/release/blob/cfd56135e6/ci-operator/config/openshift/ovn-kubernetes/openshift-ovn-kubernetes-release-5.1.yaml)
had optional OTE lanes for metal, AWS, Azure and GCP;
[#85832](https://github.com/openshift/release/pull/85832)
(September 24) made the IPv4, dual-stack, AWS, Azure and GCP core-networking OTE
lanes and the BGP local-gateway OTE lane required second-stage presubmits
(`pipeline_skip_if_only_changed`) on main, 5.1 and 5.2. The IPv6, serial,
disruptive, virt and shared-gateway BGP OTE lanes stay optional, and 4.22 and 5.0
are unchanged. Only the metal BGP
local-gateway lane meets all four prerequisites; the shared-gateway BGP lane lacks
local gateway mode, and the AWS lane's
[workflow](https://github.com/openshift/release/blob/cfd56135e6/ci-operator/step-registry/openshift/e2e/aws/core-networking-bastion/openshift-e2e-aws-core-networking-bastion-workflow.yaml)
has no BGP or FRR setup. [#78585](https://github.com/openshift/release/pull/78585)
(merged September 22) added `e2e-metal-ipi-ovn-dualstack-bgp-local-gw-serial`; at
`6092eea7` it is on OVN-K main and `release-4.22` through `release-5.2` with
[`TEST_SUITE:
openshift/conformance/serial`](https://github.com/openshift/release/blob/6092eea7/ci-operator/step-registry/baremetalds/e2e/ovn/bgp/dualstack-local-gw-serial/baremetalds-e2e-ovn-bgp-dualstack-local-gw-serial-workflow.yaml).
The `release-5.1` OTE binary (`1fc2bd44c5`) and `release-5.2` set no parents, so
that lane selects EVPN serial specs only on 4.22–5.0. Upstream OVN-K runs its `evpn` target
with kind and an external FRR container on GitHub-hosted `ubuntu-24.04` runners
([workflow](https://github.com/ovn-kubernetes/ovn-kubernetes/blob/d13564c7/.github/workflows/test.yml)).
OpenShift CI's [`lp-interop`
configurations](https://github.com/openshift/release/blob/12c7ea28/ci-operator/config/stackrox/stackrox/stackrox-stackrox-master__ocp-4-21-lp-interop.yaml)
run layered-product suites periodically against OCP nightly candidates and file
failures in LPINTEROP.

[CNV-95804](https://redhat.atlassian.net/browse/CNV-95804), the GCP counterpart's
spike, reported an end-to-end PoC on September 8: an OpenPERouter VNF VM on stock
ESXi bridged a VMware VLAN into EVPN/VXLAN over IPsec to a GCP OpenShift cluster,
with real Type-2 learning. Its Decision A prefers OpenPERouter over static FRR
because its reconcile loop owns VXLAN/bridge/veth lifecycle and derives MTU, and a
September 14 comment names Ansible plus FRR as the alternative. OCPSTRAT-3414/3415
also target 5.1.

CNV's VCF9/NSX lab ([CNV-94591](https://redhat.atlassian.net/browse/CNV-94591),
[MTV-4653](https://redhat.atlassian.net/browse/MTV-4653)) reported on September 28
that its FRR bridge VM, playing the on-prem appliance's role, peers with every OCP
node over BGP EVPN and exchanges Type-3 and Type-2 routes; the NSX-to-bridge path
was still blocked. The lab is internal, so a public Konflux cluster cannot reach it.

The parent outcome [HPSTRAT-714](https://redhat.atlassian.net/browse/HPSTRAT-714) targets "OpenShift
managed cloud platforms,
including ROSA (AWS), ARO (Azure), and OSD (GCP)". OCPSTRAT-3413 leaves its
self-managed/managed and hosted-control-plane fields blank. BGP Cloud Connector's
Prow lanes already run on `ipi-aws` and `rosa-aws-sts-hcp`, and
[CORENET-7546](https://redhat.atlassian.net/browse/CORENET-7546) is adding BGP e2e CI on bare-metal HyperShift
([openshift/release #85923](https://github.com/openshift/release/pull/85923)).

The source's [AWS
role](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af8/ansible/roles/evpn_aws_infra/tasks/main.yml#L14-28)
selects the newest CentOS Stream 9 AMI when `router_ami` is empty. Neither Jira
nor this source defines how the appliance's RHEL entitlement or AMI billing works
in customer accounts; that is a product decision, not a CI default.

RHEL-family kernels return `EOPNOTSUPP` from WireGuard's module initialization
when FIPS mode is enabled ([CentOS Stream 9
`840b99a9`](https://gitlab.com/redhat/centos-stream/src/kernel/centos-stream-9/-/commit/840b99a9),
also present in CentOS Stream 10), and RHEL 9.7/10.1 release notes list WireGuard
as an unsupported Technology Preview. The source image installs `wireguard-tools`
and uses WireGuard for its lab topology.
The same kernels' [crypto
manager](https://gitlab.com/redhat/centos-stream/src/kernel/centos-stream-9/-/blob/a78a602ce2/crypto/testmgr.c)
disables algorithms without `fips_allowed` in FIPS mode; `md5` has none, and TCP-MD5
signatures allocate the `md5` hash (`net/ipv4/tcp.c`, `tcp_md5_alloc_sigpool`).

OCPSTRAT-3413's Target Version is `openshift-5.1`, as is OCPSTRAT-3267's
(Route Server, In Progress). Its child CORENET-7400 productizes BGP Cloud Connector,
whose `bgp-cc-1.0` images shipped on September 15 (section 10). OCPSTRAT-2448 (BGP on AWS) was
resolved as Obsolete
on 2026-07-09. The 4.22 [BGP routing
module](https://github.com/openshift/openshift-docs/blob/30e70de9/modules/nw-bgp-about.adoc)
lists bare metal as the only supported platform. ART's
[`openshift-5.1` build
data](https://github.com/openshift-eng/ocp-build-data/blob/71d7233a2/images/ose-frr.yml)
delivers `openshift5/frr-rhel9` and `openshift5/ose-prometheus-node-exporter-rhel9`
(as does `openshift-5.0`), and OpenShift FRR's [`release-5.1`
Containerfile](https://github.com/openshift/frr/blob/4eebe4a1/Dockerfile.openshift)
still installs `frr10` on a RHEL 9 base and ships `frr-metrics`. On September 29
registry.redhat.io served neither `openshift5` repository, nor `openshift5/ose-cli-rhel9`,
while `openshift5/ose-operator-registry-rhel9` resolved with the same credentials:
OCP 5 payload images are not yet published.

## 10. Production identity precedents

KRD's
[`tests/test_prodsec.py`](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/blob/8c18efee29/tests/test_prodsec.py)
requires a per-tenant `prodsec/<tenant>.yaml` template with `cpe` and `stream`,
rejects CPE labels and `product_stream` in RPAs, and checks each production RPA's
rendered stream and CPE against ProdSec product-definitions. It skips RPAs with
`intention: staging`. The networking org's
[template](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/blob/8c18efee29/prodsec/bgp-cloud-connector.yaml)
renders `bgp-cc-<major>.<minor>` and `cpe:/a:redhat:bgp_cloud_connector:<major>.<minor>::<rhel_target>`.

ProdSec's
[`data/openshift/bgp-cc.json`](https://gitlab.cee.redhat.com/prodsec/product-definitions/-/blob/ec73a7fe/data/openshift/bgp-cc.json)
(cached) defines the matching product, modules and update streams, with OCPBUGS
tracking, `autofile_trackers: false` and `manifest: true`. It was added on August 13
and gained `bgp-cc-1.0` on August 31. [Advisory
2026:67519](https://gitlab.cee.redhat.com/releng/advisories/-/blob/ffa7ed0939/data/advisories/bgp-cloud-connector-tenant/2026/67519/advisory.yaml)
shipped `bgp-cc-1.0` images to `registry.redhat.io/bgpcc/` on September 15.
The repository
[workflow](https://gitlab.cee.redhat.com/prodsec/product-definitions/-/blob/ec73a7fe/docs/workflow.md)
runs KRD's `prodsec` tests in its own CI.

For the bootc repository, Portal's [Cicada
definition](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs/-/blob/5a3643c/products/ansible-automation-platform/ansible-portal.yaml)
(cached) uses a `Layered` image with build category `Standalone image`,
`privileged_images_allowed: true`, `requires_terms: true`, an engineering ID and
content-stream tags. Its [advisory
2026:34962](https://gitlab.cee.redhat.com/releng/advisories/-/blob/ffa7ed0939/data/advisories/ansible-plugins-tenant/2026/34962/advisory.yaml)
shipped that bootc image through `rh-advisories` as an RHBA and moved both the
`2.2` and `latest` tags.

The release-utils [data-key
schema](https://github.com/konflux-ci/release-service-utils/blob/fd4172f/schemas/dataKeys.json)
requires `product_id`, name, version, stream, CPE and advisory text whenever a
pipeline checks the `releaseNotes` system. Production `rh-advisories` checks it
regardless of intention, and Portal's cached stage bootc RPA carries
`product_id: [480]`. `rh-push-to-registry-redhat-io` checks only Pyxis, mapping and
signing, and creates no advisory. Konflux's internal
[preparing-for-release](https://gitlab.cee.redhat.com/konflux/docs/users/-/blob/1105e2e/modules/releasing/pages/preparing-for-release.adoc)
and [Engineering
ID](https://gitlab.cee.redhat.com/konflux/docs/users/-/blob/1105e2e/modules/releasing/pages/requesting-an-engineering-id.adoc)
guides (cached) add that Pyxis repositories are created in production and synced
to stage daily, and that an Engineering ID needs product-name approval first.

BGP Cloud Connector ran these steps from a cloned productization template
([CORENET-7400](https://redhat.atlassian.net/browse/CORENET-7400)); the
[productization path](productization.md) holds its dated timeline. CORENET-7409 also
records that Konflux app installation in the `openshift` GitHub org needs a DPP ticket
and that the tenant is `bgp-cloud-connector-tenant` on `kflux-prd-rh02`. Its operator
and bundle have no Konflux ITS; functional tests run in Prow (`e2e-aws-operator`,
`e2e-rosa-operator`).

EVPN's own repository followed the same route:
[DPP-22292](https://redhat.atlassian.net/browse/DPP-22292) requested public
`openshift/evpn-gateway-appliance` (Apache-2.0, OpenShift Core Networking team), which was
created on September 28 with only a license; an `OWNERS` file (four
approvers/reviewers) merged on September 29.
On September 29 no `openshift/release` configuration had merged; the onboarding
[PR #86165](https://github.com/openshift/release/pull/86165) was open (below).
The internal [disk-CDN
guide](https://gitlab.cee.redhat.com/konflux/docs/users/-/blob/1105e2e/modules/releasing/pages/releasing-disk-images-to-cdn.adoc)
(cached) lists that channel's prerequisites: content set and Pulp repository
(RHELDST-25935), an empty RPM repository for unified-downloads visibility
(RHELDST-25997), Content Gateway product data and an optional downloads page.

## 11. Bootc-specific build behavior

The buildah task injects metadata into `/usr/share/buildinfo` and, while
`ICM_KEEP_COMPAT_LOCATION` keeps its default `true`, into `/root/buildinfo`
([task
`af45de5`](https://github.com/konflux-ci/container-build-catalog/blob/af45de5/task/buildah-oci-ta/buildah-oci-ta.yaml)).
Image history shows these as `COPY` layers after the Containerfile's final
instruction. In the public CentOS Stream 9 bootc image built on 2026-09-23
(amd64 `sha256:64208528…`), the last layer contains
`var/roothome/buildinfo/content-sets.json` and `labels.json`. bootc's
[`var-tmpfiles` lint](https://github.com/bootc-dev/bootc/blob/65321aed/crates/lib/src/lints.rs)
warns on regular files in `/var`, which apply only at first installation.
The RHEL base does the same: `rhel9-eus/rhel-9.8-bootc:1790648125` (built
2026-09-29, amd64 `sha256:8ba2c88c…`) ends with a 979-byte layer holding
`usr/share/buildinfo/` and `var/roothome/buildinfo/` copies of `content-sets.json`
and `labels.json`. Its SPDX SBOM (tag `sha256-8ba2c88c….sbom`) lists 464 RPMs,
including podman, NetworkManager, nftables, python3, openssh-server, skopeo and
bootc, and none of cloud-init, libreswan, frr/frr10, nmstate, greenboot or
wireguard-tools. [bootc #1546](https://github.com/bootc-dev/bootc/issues/1546) records the resulting
`--fatal-warnings` failure; bootc's own packaging deletes both paths as a workaround.
The CentOS Stream bootc request to set `ICM_KEEP_COMPAT_LOCATION=false`
([issue 1195](https://gitlab.com/redhat/centos-stream/containers/bootc/-/work_items/1195))
is still open. Konflux's internal container-first scanning guide was recorded as documenting
`/root/buildinfo/labels.json` for scanner matching (not re-read for the latest recheck), so
confirm what the scanners read before dropping the compatibility path.
[KONFLUX-7507](https://redhat.atlassian.net/browse/KONFLUX-7507) records the extra
`buildinfo` layer the buildah task adds.

The integration catalog's [`kind-aws-spot` provisioner
0.3](https://github.com/konflux-ci/tekton-integration-catalog/blob/1251d299/tasks/mapt-oci/kind-aws-spot/provision/0.3/kind-aws-provision.yaml)
creates a kind cluster on an AWS VM, optionally with `nested-virt`, from a static
AWS-key secret. The owner reference (`ownerKind`/`ownerName`/`ownerUid`) covers the
kubeconfig Secret and the optional SSH-credentials Secret, so deleting the run
removes them; the VM is destroyed by the `timeout` parameter or the separate
`deprovision` task; by that reading a lost run leaves the VM until the timeout
(not tested). MAPT's AWS
[instance
selection](https://github.com/redhat-developer/mapt/blob/0ffa2da5/pkg/provider/aws/data/compute-request.go)
maps `nested-virt` to bare-metal instance types.

Cicada definitions for the RHEL bootc bases ([RHEL
9](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs/-/blob/5a3643c/products/rhel-bootc/rhel-bootc-rhel9.yaml),
[RHEL 10
AWS](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs/-/blob/5a3643c/products/rhel-bootc/rhel-bootc-aws-rhel10.yaml),
cached)
list `rhel9/rhel-bootc`, `rhel9-eus/rhel-9.6-bootc` and `rhel-9.8-bootc`, and a
`rhel-9.4-bootc` EUS repository with a 2026-08-25 end-of-life date. They also list
RHEL 10 platform bases `rhel10/rhel-bootc-aws` (added July 2026, marked Generally
Available), `-kvm`, `-azure` and `-gcp`. On September 29 neither registry.redhat.io
nor the public container catalog served `-aws` or `-kvm`, and the catalog had none
of the four, while `rhel10/rhel-bootc` resolved: the repositories are defined but
have no published image yet.
