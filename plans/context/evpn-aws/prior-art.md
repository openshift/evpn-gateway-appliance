# EVPN CI/CD — primary examples to reuse

Read with [`pipeline-spec.md`](pipeline-spec.md) and the
[source evidence](source-evidence.md). These are source pointers, not approved
EVPN resource values. Checked revisions matter: a merged definition does not
prove the target cluster deploys that task, policy, or pipeline.

## Choose the example by delivery problem

| Problem | Closest example | Boundary |
| --- | --- | --- |
| Bootc + derivative Components | Ansible Automation Portal | Same-Application bootc/qcow2/vmdk and nudges; EVPN needs raw plus its approved on-prem formats, not Portal's complete operator estate |
| Supportable runtime payload | RHEL AppStream `frr10` (RHEL 9.8+) or `frr` (RHEL 10), the RPM inside OCP's `frr-rhel9`; that image's `frr-metrics` and OCP's node-exporter under `openshift4/` (`openshift5/` once 5.x ships) | RPM gives RHEL support and errata; OCP content outside a cluster and EVPN metric coverage need decisions |
| Bootc image under OpenShift | ART's MicroShift bootc build | Alternative product home; also shows rpmdb-aware lockfile resolution for bootc |
| BIB artifact correctness | Current build-vm-image + build-image-index code; [AIPCC-1307](https://redhat.atlassian.net/browse/AIPCC-1307)/[32351](https://redhat.atlassian.net/browse/AIPCC-32351) | Verify approved bundle rollout and both sides of platform-map wiring |
| AWS boot tests | RHEL AI MAPT/cloud-importer and xKS Testing Farm/tmt | Two viable patterns; xKS full integration is still in progress |
| Disk downloads | Portal disk CDN RPA | One RPA maps two formats to one Pulp repo; upload success is not customer visibility |
| Marketplace | RHEL AI production RPA and xKS stage pre-push | xKS's multi-architecture branch is not the standard production catalog |
| Collection | OpenShift Networking's `network.offline_migration_sdn_to_ovnk` (Prow CI); `hashicorp.vault` and validated `redhat-cop/network.*` (GitHub release → `release_ah.yaml` → Automation Hub); RHTAS Molecule/upgrade tests | Actions is off by default in the `openshift` org; floating `@main` workflow rebuilds from the tag; bind by `MANIFEST.json` digest |
| Explicit promotion gate | HyperShift's Prow-backed ITS and `create-release` task | Reuse the gate boundary; select EVPN's complete candidate and approved test revisions |
| Networking onboarding | BGP Cloud Connector, [CORENET-7409](https://redhat.atlassian.net/browse/CORENET-7409) | Tenant/RBAC, RP/RPA split, nudges and CEL; operator/bundle/FBC design is not an appliance design |
| OCP qualification | OVN-K EVPN test utilities and BGP/EVPN OTE work | Reuse topology helpers; OTE silently drops EVPN specs on clusters missing EVPN prerequisites |
| Simulated EVPN on PRs | Upstream OVN-K `evpn` kind lane; openperouter's containerlab and `systemdmode` lanes, all on GitHub-hosted runners | Privileged, credential-free source feedback; not candidate qualification; `openshift`-org repositories must request Actions |
| On-prem design alternative | CNV-95804's OpenPERouter VNF on stock ESXi with IPsec to GCP | Spike results, not a product; GCP is explicitly out of scope for EVPN-AWS per Jira CORENET-7498 |
| New OCP y-streams | OpenShift CI `lp-interop` periodic jobs | Existing layered-product interop cadence; EVPN still needs its external-router topology |

Pinned files for the payload, MicroShift, OTE, simulated-lane and `lp-interop`
rows are in [source evidence §9](source-evidence.md#9-payload-platform-and-ocp-test-inputs).

## Merged internal configuration

[KRD](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/8c18efee29)
was inspected at `8c18efee29` (2026-09-18), a cached baseline that may lag the current
head. Source definitions below are preferable to `tenants-config/auto-generated` copies.

Under `tenants-config/cluster/stone-prod-p02/tenants/ansible-plugins-tenant/`:

- `components/automation-portal-bootc-main.yaml`: Application
  `automation-portal-installer-main`, `build-nudges-ref` to qcow2/vmdk and
  `build-nudge-simple-branch`.
- `components/automation-portal-qcow2-disk-image-main.yaml`: BIB wrapper as
  `dockerfileUrl`, `skipGitOpsResourceGeneration`, disabled Mintmaker.
- Compare `components/automation-portal-{bootc,qcow2-disk-image,vmdk-disk-image}-2-2.yaml`
  with the `-main` files: separate Applications, source branches and nudge edges,
  with shared build registry repositories. The `-2-2` VM ITSs select `release-2.2`;
  that branch's `.tekton/*-2-2-{pull-request,push}.yaml` aligns CEL and labels.
  Match its bootc RPA's component mapping/product stream too; both main and 2.2
  RPAs publish `latest`, so copied configurations do not isolate customer channels.
- `integration-tests/automation-portal-disk-images-enterprise-contract-main.yaml`
  and VM-test ITSs: optional and component-scoped examples. EVPN's required full
  candidate gates deliberately need stronger coverage.
- `release-plans/rp-automation-portal-installer-main-quay-aap.yaml`: real
  `tenantPipeline` using community-catalog `push-snapshot-to-quay`, without a
  managed target. This demonstrates the release mechanism, not a production
  Hub trust boundary; its separate service account still runs in the build tenant.

Under `config/stone-prod-p02.hjvn.p1/product/`:

- `ReleasePlanAdmission/ansible-plugins/rpa-automation-portal-bootc-main-prod.yaml`:
  OCI registry, `rh-advisories`, mapping/tag policy and security-label flag.
- `ReleasePlanAdmission/ansible-plugins/rpa-automation-portal-disk-images-main-prod.yaml`:
  `singleComponentMode: true` with **both qcow2 and vmdk mappings to the same
  Pulp repository**; `push-disk-images-to-cdn` and registry-release service account.
- `EnterpriseContractPolicy/registry-ansible-plugins-{bootc,disk-images}-{stage,prod}.yaml`:
  policy precedents to diagnose applicability, not wholesale exclusion recipes.
- `ReleasePlanAdmission/rhel-bootc-xks/rhel-bootc-xks-disk-images-aws-marketplace-9-8-stage.yaml`:
  `cloudMarketplacesPrePush`, private AMI creation and the temporary `release2758`
  pipeline revision. Read [RHELOPC-2351](https://redhat.atlassian.net/browse/RHELOPC-2351) and
  [RELEASE-2758](https://redhat.atlassian.net/browse/RELEASE-2758) with this file.
- RHEL AI `ReleasePlanAdmission/rhel-ai/` AWS Marketplace production definitions:
  managed stratosphere service account/secret and starmap. The tenant's test
  credentials are a separate concern.

KRD `tests/test_ecp.py` / `tests/conftest.py` constrain static exclusions,
including allowed non-container label exceptions; `tests/test_consistency.py`
requires ECP references from RPAs. Stage ECP/RPA work should land together.
The [KRD repository](https://gitlab.cee.redhat.com/releng/konflux-release-data/-/tree/8c18efee29)
is the source for these paths.

The private [Portal
repository](https://github.com/ansible-automation-platform/automation-portal-bootc-container/tree/5c34cf9d)
shows the BIB wrapper to imitate: its release-2.2 wrapper
([`disk-images/bib-portal-qcow2.yaml`](https://github.com/ansible-automation-platform/automation-portal-bootc-container/blob/5afc61bc/disk-images/bib-portal-qcow2.yaml))
sets `tagged-as` to the customer bootc origin, whereas its main-branch wrapper named the
disk repository and was corrected ([AAP-79487](https://redhat.atlassian.net/browse/AAP-79487));
[KONFLUX-14595](https://redhat.atlassian.net/browse/KONFLUX-14595) explains why that field
sets the installed update source. Its `bootc/rpms.{in,lock}.yaml`
show RPM prefetch. EVPN's own build must be hermetic, its tests must select the complete
candidate rather than the triggering Component, and its upgrade test must exist before it is
required; Portal's upgrade design is still a proposal
([AAP-72802](https://redhat.atlassian.net/browse/AAP-72802)).

## Build and release implementations

AAP's [candidate
selector](https://github.com/ansible-automation-platform/aap-konflux-tools/blob/f2138795/select-compliant-snapshot/select-compliant-snapshot.sh)
accepts an explicit Snapshot and compares its image digests with bundle references
at that Snapshot's source revision; its [report
task](https://github.com/ansible-automation-platform/aap-konflux-pipelines/blob/47bb13e0/tasks/compliant-snapshot-comprehensive-details/0.2/task.yaml)
exports component/source metadata as an OCI artifact. Reuse those comparison and
reporting patterns, not AAP's bundle, GitHub and namespace filters. The
[validation
wrapper](https://github.com/ansible-automation-platform/aap-konflux-pipelines/blob/47bb13e0/tasks/validate-compliant-snapshot/0.1/task.yaml)
returns `validation-status=failed` while exiting zero, and the [parent
pipeline](https://github.com/ansible-automation-platform/aap-konflux-pipelines/blob/47bb13e0/pipelines/pde-integrationtestscenarios/product-build-ci/product-build-ci.yaml)
cancels on that result, so preserve failure propagation when adapting it.
[AAP-81070](https://redhat.atlassian.net/browse/AAP-81070) records that automatic triggering is not enabled.

The catalog's [disk-CDN e2e
fixture](https://github.com/konflux-ci/release-service-catalog/tree/155acaca/integration-tests/push-disk-images)
provides RP/RPA setup and stage publication wiring
([RELEASE-2699](https://redhat.atlassian.net/browse/RELEASE-2699)). Its disk-specific
check asserts one successful `push-disk-images` TaskRun; the documented payload can
be a tiny text file. Reuse the setup, then add EVPN's real disk sizes, per-artifact
customer readback and boot tests. It does not replace those acceptance gates.

AAP's [dependency-lockfile-update
pipeline](https://github.com/ansible-automation-platform/aap-konflux-pipelines/blob/47bb13e0/pipelines/build/dependency-lockfile-update/0.1/pipeline.yaml)
and Controller's [PaC entry
point](https://github.com/ansible-automation-platform/automation-controller-container/blob/84d0425d/.tekton/pull-request-rpm-lockfile.yaml)
update lockfiles on source/nudge PRs before merge;
[AAP-90611](https://redhat.atlassian.net/browse/AAP-90611)'s
wider rollout is still In Progress. The checked publisher hard-codes root
`rpms.lock.yaml`, so adapt authentication, trigger paths, directories and pins, and
verify the committed result. For MintMaker's Dockerfile updates, compare the supported
[`refresh-rpm-lockfiles`
preset](https://github.com/konflux-ci/mintmaker-presets/blob/091c89df/refresh-rpm-lockfiles.json)
and
[helper](https://github.com/konflux-ci/refresh-rpm-lockfiles/blob/970acfcb/src/refresh_rpm_lockfiles/__init__.py),
which maps Containerfiles to RPM input files and sets each output path.

HyperShift supplies another concrete gate in
[`.tekton/pipelines/ho-release-gate.yaml`](https://github.com/openshift/hypershift/blob/43d6b36b/.tekton/pipelines/ho-release-gate.yaml):
extract the Snapshot image, run blocking/informing Prow jobs, evaluate results,
then explicitly create a Release only on pass. It triggers periodic
jobs through Prow's Gangway executions API with a `gangway-token` secret and injects
the candidate as a `MULTISTAGE_PARAM_OVERRIDE_<PARAM>` environment override, which
is how an EVPN gate would run its OpenShift CI AWS lanes on a Konflux candidate. The companion
`ho-release-gate-run.yaml`
uses `taskRunSpecs` to assign the release-creation task its own service account.
KRD's `crt-redhat-acm-tenant/hypershift-operator/nightly-promotion/` has the actual
CronJob, ITS, RBAC and `auto-release: "false"` ReleasePlan. Do not copy its
latest-single-component selection or floating test-code refs.
[CNTRLPLANE-3434](https://redhat.atlassian.net/browse/CNTRLPLANE-3434) and [release PR #81877](https://github.com/openshift/release/pull/81877)
show why requested image overrides need runtime verification: the original
override was overwritten before deployment.

- [Integration-service](https://github.com/konflux-ci/integration-service/tree/11cc455b):
  `gitops/snapshot.go` for contexts; `internal/controller/snapshot/snapshot_adapter.go`
  and `pkg/dag/utils.go` for ComponentGroup ordering/filtering. `testGraph` needs
  explicit `failFast` and matching prerequisites. Application examples do not
  gain this behavior automatically. For the NudgeConfig controller handoff, read
  [STONEINTG-1671](https://redhat.atlassian.net/browse/STONEINTG-1671)/[1672](https://redhat.atlassian.net/browse/STONEINTG-1672)/[1682](https://redhat.atlassian.net/browse/STONEINTG-1682)
  and the checked source linked in the audit.
- [build-vm-image](https://github.com/konflux-ci/build-definitions/tree/3349e7e2/task/build-vm-image):
  `0.3/build-vm-image.yaml` and `CHANGELOG.md`; metadata version 0.3.2.
  Inspect result formatting, platform-map output and placeholder-SBOM fallback.
  `external-task/*/current` files are bundle references, not Task definitions.
- [build-image-index](https://github.com/konflux-ci/container-build-catalog/tree/094f3fe/task/build-image-index):
  version 0.4, `IMAGE_PLATFORM_MAP` input and index creation even for one platform.
- [release-service-catalog
  production](https://github.com/konflux-ci/release-service-catalog/tree/155acaca/pipelines/managed):
  compare `rh-advisories`, `push-disk-images-to-cdn`,
  `push-disk-images-to-marketplaces` and `push-artifacts-to-cdn`. Inspect tasks
  actually resolved by each pipeline; the presence of `create-advisory` does not
  establish a Brew/Errata Tool requirement.
- [AAP final
  pipeline](https://github.com/ansible-automation-platform/aap-konflux-pipelines/blob/c4f53fee/pipelines/final/post-release-managed-pipeline/0.1/pipeline.yaml):
  KRD
  `tenants-config/cluster/stone-prod-p02/tenants/ansible-tenant/applications/aap/27/releaseplans/prod.yaml`
  pins this in `spec.finalPipeline`. It receives `release`, `releasePlan` and
  `snapshot` references; its notifications/symlink updates are not customer
  qualification. Implement failing readback checks. The
  [release
  controller](https://github.com/konflux-ci/release-service/blob/e55aefd1/controllers/release/adapter.go)
  runs final processing after publication finishes, including failure, and waits
  for it before marking release success.
  [CONTENT-3829](https://redhat.atlassian.net/browse/CONTENT-3829)'s generic CAT pullability
  pipeline is still To Do; no such pipeline was found in community-catalog
  development `fef4a035`.
- [release-service-utils
  schema](https://github.com/konflux-ci/release-service-utils/blob/70b9ef1/schemas/dataKeys.json):
  `enforceContainerFirstSecurityLabels` describes `name`/`cpe` values, not a
  filesystem layer. Its `src/tasks/managed/reduce_snapshot/reduce_snapshot.py`
  also explains single-component selection and manual-Snapshot rejection.
  Check Conforma label rules and effective central rule data
  for the final required-label set.
- [Central rule data](https://github.com/release-engineering/rhtap-ec-policy/blob/363039a/data/rule_data.yml)
  and [label rules](https://github.com/conforma/policy/blob/651b57d0/policy/release/labels/labels.rego):
  required labels and how the image configuration is validated. Target-cluster
  effective policy/data still needs to be recorded during implementation.

## Security inventory handoff

Product Security's [SBOM
guidance](https://github.com/RedHatProductSecurity/security-data-guidelines/blob/c61b2152/docs/sbom.md)
distinguishes build/release and component/product metadata. Compare real advisory
records: [Helm
CLI](https://gitlab.cee.redhat.com/releng/advisories/-/blob/ffa7ed0939/data/advisories/helm-cli-tenant/2026/26441/advisory.yaml)
has eight archive rows without SBOM URLs;
[Hummingbird](https://gitlab.cee.redhat.com/releng/advisories/-/blob/ffa7ed0939/data/advisories/hummingbird-tenant/2026/49787/advisory.yaml)
links its source-RPM SBOM and attestation, and that SBOM downloads successfully.
The new [generic-archive example, PR #102](https://github.com/RedHatProductSecurity/security-data-guidelines/pull/102)
is still unmerged: its README explicitly describes partial dependencies and
placeholder source provenance, not Konflux-generated production output. Use it
to agree the EVPN contract with Security, not as a ready-made disk/collection publisher.

RHEL AI's [`copy-clair-scan-results` final
pipeline](https://github.com/red-hat-data-services/aipcc-konflux-data/blob/70af2437/pipelines/copy-clair-scan-results.yaml)
is a report-retention example. It reads only `components[0]`;
[AIPCC-27944](https://redhat.atlassian.net/browse/AIPCC-27944) tracks broader bootc
adoption. Four isolated shell cases confirmed first-component-only copying and
success despite missing reports, attestation-download failure, or an earlier copy
failure followed by a successful copy. Adapt with verified input attestations,
an explicit required-report inventory per artifact, strict failure propagation and
destination digest readback. Copying an old report does not refresh its scan.

For earlier CVE feedback, RHEL AI's
[`check-clair-cves`
task](https://github.com/red-hat-data-services/aipcc-konflux-data/blob/70af2437/tasks/check-clair-cves.yaml)
reads complete `REPORTS` blobs instead of the filtered build summary
([AIPCC-27940](https://redhat.atlassian.net/browse/AIPCC-27940)). It selects one triggering Component,
downloads attestations without verification, parses the SLSA v0.2 layout and
defaults to warnings. Adapt full-candidate/platform selection, attestation
verification/schema and effective policy thresholds before using it as a gate.
It reports existing scan data; release-time freshness still needs independent proof.

### Log export and public results

The integration catalog's
[`export-pipeline-logs`](https://github.com/konflux-ci/tekton-integration-catalog/blob/1251d299/tasks/export-logs/0.1/export-logs-to-quay.yaml)
is an OCI log-archive example, but it copies raw logs, suppresses read errors, does
not wait for running tasks and uses a floating utility image, so it proves neither
completeness nor sanitization
([evidence](source-evidence.md#3-retention-spans-artifacts-credentials-and-execution-sites)).
Reuse the archive transport with pinned tools, an explicit log inventory and an
approved destination.
[`FormatNote`](https://github.com/konflux-ci/integration-service/blob/a5769458/status/format.go)
returns `TEST_OUTPUT.note` directly to forge reporting, so review those fields too.

## Runnable test patterns

The [Konflux federation
guide](https://gitlab.cee.redhat.com/konflux/docs/users/-/blob/1105e2e/modules/getting-started/pages/oidc-federation.adoc)
(`1105e2e`, 2026-09-16)
shows projected service-account tokens, AWS STS trust and SDK configuration.
Use a pinned tool image instead of its runtime AWS CLI download. Preserve the
full issuer path when configuring trust, bind the exact tenant/service account,
and follow the account's IAM retention-tag policy. Integration-service's
`tekton/integration_pipeline.go` and tests verify that a custom PipelineRun's
service account survives defaulting; test the deployed cluster before relying on it.

[RHEL AI configuration](https://github.com/red-hat-data-services/aipcc-konflux-data/tree/70af2437):

- `pipelines/rhelai-disk-image-test.yaml`: Snapshot configuration, image-exists
  check, helper VM, extraction/import, test VM, product tests and VM finalizers.
- `tasks/config-from-snapshot.yaml`: product-specific component-name parsing;
  do not turn its `*-aws*` convention into a Konflux requirement.
- `tasks/check-cloud-image-exists.yaml`: names test images using eight Git-SHA
  characters, with no disk digest in the lookup. Replace this cache identity
  before using it to qualify a candidate; cloud-importer checks the `Name` tag.
- `tasks/extract-and-upload-cloud-image.yaml`: remote helper credential handoff
  copies only access/secret keys, not an STS session token or renewable identity.
- `pipelines/cleanup-resources.yaml`: separate AMI cleanup. Adapt ownership and
  retained-release protection and deploy a schedule; do not copy substring
  filters or a Slack destination as EVPN defaults.
- [`pipelines/rhelai-marketplace-test.yaml`](https://github.com/red-hat-data-services/aipcc-konflux-data/blob/70af2437/pipelines/rhelai-marketplace-test.yaml):
  an implemented post-publication launch/test/cleanup example
  ([AIPCC-19057](https://redhat.atlassian.net/browse/AIPCC-19057)/[17575](https://redhat.atlassian.net/browse/AIPCC-17575)).
  Its AWS path truncates the version to major.minor;
  [MAPT](https://github.com/redhat-developer/mapt/blob/26c624ab/pkg/provider/aws/action/rhel-ai/rhelai.go)
  selects the latest matching Marketplace AMI and hard-codes RHEL AI's owner,
  name and supported instance types. Adapt it to the release's exact regional
  AMI IDs and verify booted identity, with EVPN's consumer permissions, approved
  subscription and instance matrix. It supplies no full-candidate `SNAPSHOT` input.
  Private pre-push and [Marketplace listing
  tests](https://docs.aws.amazon.com/marketplace/latest/userguide/ami-single-ami-products.html)
  exercise different distribution paths.

[`tekton-integration-catalog`](https://github.com/konflux-ci/tekton-integration-catalog/tree/2a46aa2)
(`2a46aa2`):
`tasks/mapt-oci/fedora-virtual-machine/{provision,deprovision}/0.1/` provides
pinned catalog tasks. Compare their current interface and capacity needs with
the direct MAPT tasks before selecting them. Their static-key secret contract
needs adaptation for federation. [MAPT's AWS
provider](https://github.com/redhat-developer/mapt/blob/26c624ab/pkg/provider/aws/aws.go)
does support session tokens. [Cloud-importer
v0.0.4](https://github.com/mapt-oss/cloud-importer/tree/bc82eac83687/pkg/provider/aws)
creates its own import bucket/role; account setup and cleanup differ from EVPN's
direct AWS scripts.

The xKS alternative ([RHELOPC-2265](https://redhat.atlassian.net/browse/RHELOPC-2265),
still In Progress) uses `ci/pull-disk-image.sh`, `ci/ami.py`, `ci/ec2.py` and
`tests/disk-image-smoke/{main.fmf,run.py,cleanup.py}`. `try/finally` plus
`tmt finish`/state-file cleanup is useful, but an external reaper is still needed
for host loss. Its MRs are private and were not verified directly.

The [Testing Farm
adapter](https://gitlab.com/testing-farm/integrations-konflux/-/tree/10547a6/pipeline/tmt-via-testing-farm)
(`10547a6`) includes
its parameter/result contract and README; the GitLab remote still resolves to
that commit on 2026-09-23. Read `scripts/tf-{resolve-secrets,pre-process,scheduler}.sh`:
they infer inputs from triggering-component/group metadata, whereas manual
candidates need explicit selection. The scheduler forwards `SNAPSHOT_b64` and
accepts explicit `GIT_URL`/`GIT_REF`. The Pipeline's five bundle refs and its runtime
image share `IMAGE_TAG`; pin them separately in the reviewed adapter. Retain
Snapshot binding and machine-readable test results.

[OVN-K's route-advertisement
tests](https://github.com/ovn-kubernetes/ovn-kubernetes/blob/a25a653b0/test/e2e/route_advertisements.go)
include `runEVPNNetworkAndServers` and BUM/EVPN tests. Read
[CORENET-6549](https://redhat.atlassian.net/browse/CORENET-6549)/[6838](https://redhat.atlassian.net/browse/CORENET-6838)/[6892](https://redhat.atlassian.net/browse/CORENET-6892)
for utility reuse, [CORENET-7120](https://redhat.atlassian.net/browse/CORENET-7120) for subnet
allocation and
[CORENET-7121](https://redhat.atlassian.net/browse/CORENET-7121) for failure dumps.
[CORENET-7075](https://redhat.atlassian.net/browse/CORENET-7075)/[7564](https://redhat.atlassian.net/browse/CORENET-7564)/[6592](https://redhat.atlassian.net/browse/CORENET-6592)
track actual OTE/blocking
behavior. The closed NSX tickets 6566/6567 do not supply automated CI coverage.

### EVPN feature interaction tests

OVN `68936e39` supplies concrete regression expectations:
[`ovn-northd.at`](https://github.com/ovn-org/ovn/blob/68936e39/tests/ovn-northd.at)
has `LS EVPN conntrack skip with stateful ACLs and LBs`, including combinations
with/without ACLs and load balancers.
[`system-ovn.at`](https://github.com/ovn-org/ovn/blob/68936e39/tests/system-ovn.at)
checks EVPN ARP suppression flows, broadcast proxy handling, unicast non-suppression
and removal of learned bindings. Adapt the assertions to real OCP/fabric traffic;
these upstream flow tests are not a downstream release qualification run. Red Hat's
kernel QE also keeps OVN-level EVPN cases in the internal
[`kernel-qe/kernel`](https://gitlab.cee.redhat.com/kernel-qe/kernel/-/blob/7d69850ab2/networking/openvswitch/ovn/bgp/runtest.sh)
(`7d69850ab2`, 2026-09-18): `basic_l2evpn` (gated on OVN 25.09.0-25 or newer), `l2evpn_frr`,
`evpn_options`, `evpn_l3_indirect_nexthop` and `ovn_evpn_ct_skip`. Ask that team before writing
new OVN-side EVPN checks.
[FDP-3458](https://redhat.atlassian.net/browse/FDP-3458) explains the stateful-traffic
failure;
[FDP-3463](https://redhat.atlassian.net/browse/FDP-3463)/[3464](https://redhat.atlassian.net/browse/FDP-3464)
and the ARP [coverage/verification work](https://redhat.atlassian.net/browse/FDP-3431)
remain New. Verify the fix and executed cases in the selected OCP release.

### Preserving the test subject

At tmt `10bcf1d4`,
[`provision/bootc.py`](https://github.com/teemtee/tmt/blob/10bcf1d4/tmt/steps/provision/bootc.py)
builds a new qcow2 using BIB. Its default `add-tmt-dependencies: true` first adds
cloud-init/rsync and filesystem changes to a derived image; disabling it still
builds a new disk. For a prebuilt qcow2,
[`virtual.testcloud`](https://github.com/teemtee/tmt/blob/10bcf1d4/tmt/steps/provision/testcloud.py)
accepts an explicit `file://` image. Canary launch access and guest customization
against the selected artifact before adopting that backend.

The independent
[`package_managers/bootc.py`](https://github.com/teemtee/tmt/blob/10bcf1d4/tmt/package_managers/bootc.py)
can install dependencies by building a derived container, `bootc switch` and
reboot. [TFT-3177](https://redhat.atlassian.net/browse/TFT-3177) describes this
intentional design. Pin/review the complete test plan, including preparation and
required packages, and check booted identity after preparation. A base-image digest
passed to a harness does not prove the selected delivery disk was qualified.

OpenShift's [`BGP
pre-step`](https://github.com/openshift/release/blob/f8287e1d/ci-operator/step-registry/baremetalds/e2e/ovn/bgp/pre/baremetalds-e2e-ovn-bgp-pre-commands.sh)
conditionally sets CNO `Unmanaged` and replaces FRR/reloader images when `FRR_IMAGE`
is set. [CORENET-6591](https://redhat.atlassian.net/browse/CORENET-6591) introduced this temporary
route to FRR 10; 6592 tracks cleanup.
The [main OTE
jobs](https://github.com/openshift/release/blob/f8287e1d/ci-operator/config/openshift/ovn-kubernetes/openshift-ovn-kubernetes-main.yaml)
do not set that variable themselves. Check the resolved job and running operands;
development override results cannot qualify an unchanged supported OCP payload.

### Cloud image tests and cleanup

[`osbuild/cloud-image-val` at
`eca2cec`](https://github.com/osbuild/cloud-image-val/blob/eca2cec/test_suite/cloud/test_aws.py)
provides explicit-AMI inputs and runtime image-ID/region, ENA and boot-mode checks.
Reuse selected assertions; adapt its IMDSv1 helper to IMDSv2 and remove unrelated
RHEL/RHUI, billing and mutable-package assumptions. The newer phase CLI from
[CLOUDX-2090 / PR #616](https://github.com/osbuild/cloud-image-val/pull/616) merged
to `refactor/civ-core` ([`f0ddf54`](https://github.com/osbuild/cloud-image-val/blob/f0ddf54/cli.py)),
not main. Its result collector merges present XML files; preserve EVPN's
expected-instance/case coverage checks. [RHELOPC-2765](https://redhat.atlassian.net/browse/RHELOPC-2765)
is New and points to a separate internal `rhel-image-tests` migration; its
implementation was unavailable for this audit.

[`osbuild/cloud-cleaner` at `135b45d`](https://github.com/osbuild/cloud-cleaner/blob/135b45d/aws.py)
is a historical cleanup example for EC2 instances, self-owned AMIs and EBS snapshots.
Its default six-hour age rule permits deletion of untagged resources unless
protected by `persist=true`; it neither checks run liveness nor follows inventory
pagination, and catches deletion errors without failing the process. It does not qualify an
EVPN reaper. Prefer the selected backend or an owned cleanup service; prove ownership/leases,
complete inventory, failed deletions and resource coverage before adding residual glue
([lifecycle contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle)).

## OpenShift CI adapters

The networking org's [BGP Cloud Connector
configuration](https://github.com/openshift/release/blob/ff1189c2/ci-operator/config/openshift/bgp-cloud-connector/openshift-bgp-cloud-connector-main.yaml)
has `e2e-aws-operator` (`ipi-aws`) and `e2e-rosa-operator` (`rosa-aws-sts-hcp`)
jobs. Before installing, both patch CNO for the FRR provider and route
advertisements (ROSA through the repository's `hack/enable-frr.sh`) and wait for
the `frr-k8s` rollout. The configuration also runs the `fips-check-image-scan`
step. Reuse the enablement and job structure; EVPN additionally needs local
gateway mode, a VTEP and an external relay/fabric.

The [current integration guide](https://konflux-ci.dev/docs/testing/integration/third-parties/openshift-ci/)
offers Prow execution or cluster provisioning. EaaS cluster provisioning is
deprecated ([KONFLUX-13430](https://redhat.atlassian.net/browse/KONFLUX-13430));
migration/decommission remains In Progress under
[KONFLUX-15294](https://redhat.atlassian.net/browse/KONFLUX-15294). Use the approved OpenShift CI
profile or an owned EVPN lab.

At `openshift/konflux-tasks` `9751a202`,
[`run-prowjob/0.1`](https://github.com/openshift/konflux-tasks/blob/9751a202/tasks/run-prowjob/0.1/run-prowjob.yaml)
constructs a public GitHub archive URL from PaC labels, selects one triggering
Component and dispatches fixed generic operator/bundle jobs. It is not a generic
EVPN OTE dispatcher. Its three `PROWJOB_*` results omit `TEST_OUTPUT`; its interrupt
handler leaves Prow running. Adapt these boundaries or reuse HyperShift's explicit
job-dispatch pattern above, binding actual cases and remote lifecycle to the candidate.
Pin the resolved test code, tools and OCP payload, not only the adapter YAML.

[`provision-ephemeral-cluster/0.1`](https://github.com/openshift/konflux-tasks/blob/9751a202/tasks/provision-ephemeral-cluster/0.1/provision-ephemeral-cluster.yaml)
accepts explicit release/workflow/profile inputs and creates a TestPlatformCluster
claim with a PipelineRun/TaskRun owner reference. Reuse that managed lifecycle;
prove cleanup on cancellation as well as owner deletion, and qualify the actual
external-router topology. Provisioning success alone supplies no EVPN test verdict.

[AWS EVPN performance CI #83378](https://github.com/openshift/release/pull/83378)
merged September 9 ([PERFSCALE-5782](https://redhat.atlassian.net/browse/PERFSCALE-5782)),
despite the older [PERFSCALE-5505](https://redhat.atlassian.net/browse/PERFSCALE-5505)
remaining New. The [periodic
job](https://github.com/openshift/release/blob/f8287e1d/ci-operator/config/openshift-eng/ocp-perfscale/openshift-eng-ocp-perfscale-main__aws-5.0-nightly-x86.yaml)
wires AWS cluster/bastion provisioning, EVPN and post-cleanup; open
[#85175](https://github.com/openshift/release/pull/85175) moves that AWS BGP/EVPN
setup into reusable `openshift-qe/bgp-setup` step references. Reuse its dual-ENI
external-router setup and [kube-burner
workload](https://github.com/kube-burner/kube-burner-ocp/tree/bd8a9b26/cmd/config/evpn)
as test scaffolding. The [EVPN
step](https://github.com/openshift/release/blob/f8287e1d/ci-operator/step-registry/openshift-qe/evpn/openshift-qe-evpn-commands.sh)
unconditionally stops CVO, sets CNO Unmanaged, overrides FRR and fetches floating
test code. It neither selects EVPN's appliance candidate nor establishes DX/VPN
or supported OCP coverage. Bind the candidate, pin dependencies, restore the
supported payload contract and prove required cases before making it a gate.

One QE example is still unmerged: the [OpenPE external-ToR
proposal](https://github.com/RedHatQE/openshift-virtualization-tests/pull/6332)
([CNV-91892](https://redhat.atlassian.net/browse/CNV-91892), open on September 29).
`tests/network/bgp/data/openpe/` supplies router configuration and
`tests/network/libs/bgp.py` selects a digest-pinned image. It needs the BGP
localnet/worker topology, and its author reports cluster integration unvalidated.
Treat it as an implementation candidate, not an available lab gate.

## OCP upgrade qualification

[CORENET-6989](https://redhat.atlassian.net/browse/CORENET-6989)'s closing discussion
records passing BGP 4.21→4.22 upgrade tests, while deferring EVPN→EVPN coverage.
[OCPBUGS-114403](https://redhat.atlassian.net/browse/OCPBUGS-114403) records an EVPN
controller panic encountered during an OCP update with post-migration pod state.
The [upstream fix and regression tests](https://github.com/ovn-kubernetes/ovn-kubernetes/pull/6866)
merged at `e63fce3c`; the Jira remains POST and does not establish the fix's presence
in a chosen OCP payload. Check that payload and preserve this class of retained-state
coverage. The [OTE lanes](https://github.com/openshift/release/pull/85482): the core-networking
and BGP local-gateway ones became required-if-present OVN-K presubmits (run by an explicit `/test`)
on main, 5.1 and 5.2 on
September 24 (#85832; see the [lane list](source-evidence.md#9-payload-platform-and-ocp-test-inputs)),
but none is an upgrade lane.

## Payload delivery

[RHEL's logically bound images
guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/building-and-managing-logically-bound-images)
and [bootc's implementation
contract](https://github.com/bootc-dev/bootc/blob/44c7024e/docs/src/logically-bound-images.md)
cover pre-reboot pulls and rollback retention. Podman consumers must explicitly use
bootc's additional image store; enable it per bound service, never globally for
unrelated images. Qualify installer population and customer registry authentication.

The [physical binding
guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/building-and-managing-physically-bound-images)
has runnable system-role prior art in [`linux-system-roles/podman` at
`0ef63e71`](https://github.com/linux-system-roles/podman/tree/0ef63e71):
`library/manage_image_cache.py`, `tasks/handle_images.yml` and
`templates/lsr_podman_copy_images*`. It copies OCI content with
`skopeo copy --preserve-digests`, fetching from `docker://` during the build and
caching under `/var`; its boot service copies into container storage and deletes
the cache. Adapt and prove hermetic input handoff, service ordering and retained-state upgrade/rollback
before reuse. A first-boot cache is insufficient upgrade evidence. The separate
xKS [RHELOPC-2752](https://redhat.atlassian.net/browse/RHELOPC-2752) embedding spike
remains open; it does not establish a stock Konflux solution.

## Host update and recovery

RHEL AI already runs a Konflux upgrade ITS per release line: KRD's
`rhelai-bootc-3-5-test-bootc-cuda-aws-upgrade-x86-64` (optional, `component_`
context) resolves
[`rhelai-bootc-upgrade-test.yaml`](https://github.com/red-hat-data-services/aipcc-konflux-data/blob/2893f77/pipelines/rhelai-bootc-upgrade-test.yaml).
MAPT launches the published AMI for the configured release version, the pipeline
runs `bootc switch` to the candidate image, reboots, then checks services and runs
product tests. Reuse the published-baseline-to-candidate shape. For EVPN, pin the
prior release's exact AMI or image digest, exercise `bootc upgrade` through the
customer update tag as well as `switch`, add failed-upgrade rollback, and make the
suite required. At `f133e71` its diagnostic steps tolerate failures, it prints
`bootc status` without asserting the booted digest, and it resolves its tasks from
`main`.

Bootc's [download-only
test](https://github.com/bootc-dev/bootc/blob/44c7024e/tmt/tests/booted/test-download-only-upgrade.nu)
checks that reboot preserves the old image and discards the locked staged
deployment; it then stages again and explicitly applies. Adapt these assertions
to EVPN's approved digests and serial HA updates. The [RHEL
example](https://developers.redhat.com/articles/2026/02/18/control-updates-download-only-mode-bootc)
describes the RHEL 10.2 OSTree path; qualify the selected product version/backend.

[Greenboot-rs `28fc9586`](https://github.com/fedora-iot/greenboot-rs/tree/28fc9586)
provides `tests/greenboot-bootc-qcow2.sh` and `tests/greenboot-bootc.yaml`:
inject a failing health check, upgrade, then assert recovery and service state.
Reuse the failure/assertion pattern with the chosen RHEL packages and EVPN payload.
[RHEL-246674](https://redhat.atlassian.net/browse/RHEL-246674)/[EDM-5303](https://redhat.atlassian.net/browse/EDM-5303)
show why pending configuration must be distinguished from a bad upgrade: a
Flightctl enrollment check caused healthy, unconfigured hosts to reboot.
[RHEL-61158](https://redhat.atlassian.net/browse/RHEL-61158) separately tracks early
kernel failure; a userspace check alone does not prove bootloader recovery.

## FIPS build and test examples

MicroShift's [bootc FIPS
Containerfile](https://github.com/openshift/microshift/blob/69c4bad1/test/image-blueprints-bootc/el9/layer2-presubmit/group2/rhel98-bootc-source-fips.containerfile),
[VM
scenario](https://github.com/openshift/microshift/blob/69c4bad1/test/scenarios-bootc/el9/periodics/el98-src%40fips.sh)
and [Robot suite](https://github.com/openshift/microshift/blob/69c4bad1/test/suites/fips/validate-fips.robot)
connect image configuration to booted kernel/userspace checks and host/payload
inspection. The scenario skips aarch64; it is not all-platform qualification.
Current main removes the dracut-module check
([USHIFT-6978](https://redhat.atlassian.net/browse/USHIFT-6978)); use actual runtime state.

RHTAS's [component
pipeline](https://github.com/securesign/pipelines/blob/586127b5/pipelines/docker-build-multi-platform-oci-ta.yaml)
has an opt-in `fips-check` (default `false`) resolving [this pinned
task](https://github.com/securesign/pipelines/blob/bbb9af6a1fd581b805afc907172e03dbb91ebeeb/tasks/fips-check.yaml).
It unpacks an image and fails on `check-payload scan local` failure, without an FBC.
Its Skopeo copy selects one platform from an index, and it emits no `TEST_OUTPUT`.
Adapt platform/payload coverage and result reporting before reuse as an ITS;
neither this static check nor host mode proves the appliance's FIPS-mode workflows.

## Collection and lifecycle references

OpenShift Networking's public
[`network.offline_migration_sdn_to_ovnk`](https://github.com/openshift/network.offline_migration_sdn_to_ovnk/tree/67b3eac1)
(`network` namespace, installed from Hub's validated repository; OWNERS include
the EVPN feature and epic assignees) is the in-org collection precedent. Its
[OpenShift CI
configuration](https://github.com/openshift/release/blob/ff1189c2/ci-operator/config/openshift/network.offline_migration_sdn_to_ovnk/openshift-network.offline_migration_sdn_to_ovnk-main.yaml)
builds an `ansible-test-runner` image from `ci/Dockerfile`, runs `ci/` lint, sanity
and import scripts in it, and runs migration/rollback integration on `ipi-aws`
clusters. Its `.github/workflows` (ansible-content-actions PR checks and a
`release_ah.yaml` caller) have never run: the repository has no Actions runs and
no GitHub releases. [DPP-17276](https://redhat.atlassian.net/browse/DPP-17276)
records the `openshift` org declining to enable Actions in June 2025;
a June 2026 comment on [PCO-1330](https://redhat.atlassian.net/browse/PCO-1330) (not yet
formally announced) says the policy now enables it per repository on the owner's request, with
pinned trusted actions and
a cost caveat for private repositories.

Portal's internal collection also carries an unrun `release_ah.yaml` caller and no
tags, so it is not a working publisher either. Its first-boot documentation maps
configuration per deployment platform: cloud-init user-data on clouds and OVF
properties/guestinfo on vSphere. Reuse that per-platform split; guestinfo values are
visible to vSphere administrators, so keep long-lived secrets out of them and ship
no default credential.

Working publishers use the same reusable workflow where Actions runs. Red Hat's
[`ansible-collections/hashicorp.vault`](https://github.com/ansible-collections/hashicorp.vault/tree/3d36f142c7)
has published five releases to Automation Hub (1.0.0–1.3.0, seven successful
release runs) from `release_ah.yml` using `ah_client_id`/`ah_client_secret` in a
`release` environment, most recently 1.3.0 on July 9; the validated
[`redhat-cop/network.bgp`](https://github.com/redhat-cop/network.bgp/tree/fe7b9b4e9c)
does the same with a token.
[`release_ah.yaml`](https://github.com/ansible/ansible-content-actions/blob/cbdec1f7/.github/workflows/release_ah.yaml)
checks out the tag, rebuilds at the repository root (it has no path input), installs
an unpinned `ansible-core>=2.16`, and publishes the first `./*.tar.gz`. Pin it, add
the tested-manifest comparison, and restrict the environment. The same repository's `certification.yml`
calls the SHA-pinned [partner certification
checker](https://github.com/ansible-collections/partner-certification-checker/blob/f4bf7ba4d3f008b2db8fc6a812fa3f89fdf42c2e/.github/workflows/certification-reusable.yml):
pinned galaxy-importer build/import, production-profile `ansible-lint` and a fixed
ansible-core sanity matrix. Its importer step also builds a tarball with
`--git-clone-path` and discards it, so keep a retained built-tarball install check
and manifest digest.

RHTAS provides Molecule upgrade tests and a Konflux carrier, if one is needed. Its
[`artifact-signer-ansible/Dockerfile`](https://github.com/securesign/artifact-signer-ansible/blob/b89ed211/Dockerfile)
is a pinned multi-stage collection build with the archive under `/releases/`, and
[`securesign/pipelines`](https://github.com/securesign/pipelines/tree/586127b5)
holds the Molecule preparation and `ansible-upgrade.yaml` pipelines (deploy the
released collection, then install and test the candidate). Pin versions and tools
instead of copying floating refs or runtime installs. RHTAS's private release
scripts explicitly skip the collection, so it is not a managed Hub-publishing
precedent.

A third implemented path, found through [AAP-77136](https://redhat.atlassian.net/browse/AAP-77136),
is Zuul: a [job](https://github.com/ansible/zuul-config/blob/61de027f/zuul.d/jobs.yaml)
builds from source and an [upload
role](https://github.com/ansible/ansible-zuul-jobs/blob/acb7ddbc/roles/upload-ansible-collection-fork/tasks/main.yaml)
calls `ansible-galaxy collection publish`. It also rebuilds, so the same manifest
comparison applies. During [AAP-93498](https://redhat.atlassian.net/browse/AAP-93498)'s
import failure the publication was done manually ([AAP-93724](https://redhat.atlassian.net/browse/AAP-93724)),
so retain artifacts and a recovery owner.

No managed Hub publisher exists in the Konflux release catalog (production `155acaca`,
development `737de554`). The managed `release-to-github` pipeline is not a drop-in
collection release either: at utils
[`8f24a5e`](https://github.com/konflux-ci/release-service-utils/blob/8f24a5e/src/tasks/managed/create_github_release/create_github_release.py)
it uploads only `*.zip`/`*.json` files plus signed `SHA256SUMS`, and runs
`gh release create v<version>` without a target, so an absent tag lands on the
default branch head. A Konflux-side publisher would use the [tenant release
mechanism](https://konflux-ci.dev/docs/releasing/tenant-release-pipelines/)
and the [standard collection build/publish
contract](https://docs.ansible.com/projects/ansible/latest/dev_guide/developing_collections_distributing.html)
with stage credentials and import/approval verification, and must satisfy the
[credential/gate boundary](ci-bootstrap-spec.md#collection-and-ee-artifacts).
Keep trial destinations separate from the production approval queue, since
[Hub's approval
contract](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.7/administer-con_approval_pipeline)
allows auto-promotion from staging ([AAP-47430](https://redhat.atlassian.net/browse/AAP-47430)).
Native Konflux collection support is unfinished
([KONFLUX-5470](https://redhat.atlassian.net/browse/KONFLUX-5470)/[ANSTRAT-1155](https://redhat.atlassian.net/browse/ANSTRAT-1155)),
which does not block the selected publication path.

The [Ansible content build/import
action](https://github.com/ansible/ansible-content-actions/blob/cbdec1f7/.github/actions/build-import/action.yaml)
is another starting point ([AAP-53892](https://redhat.atlassian.net/browse/AAP-53892)),
with adaptations: pin tooling, import the selected tarball, and pass verified
configuration into the importer process. Its config step writes a literal `\n` and
exports the path only within that step; an isolated Bash/ConfigParser check produced
no configured options and no path in the next shell. Pair the importer with
[Builder introspection](https://github.com/ansible/ansible-builder/blob/de19e3eb/docs/collection_metadata.rst)
and actual AAP EE execution, because import warnings alone do not prove runtime
readiness. Test fresh consumer resolution of dependencies as well as the pinned
release set: AAP's snapshot collection broke preflight when an allowed
`community.postgresql` update changed a parameter name (AAP-93724).

[RHELAI-2749](https://redhat.atlassian.net/browse/RHELAI-2749) records a real upgrade
failure caused by a fixed installed image tag. [Bootc documentation at
`44c7024e`](https://github.com/bootc-dev/bootc/tree/44c7024e/docs/src)
includes `upgrades.md` and `building/management-services.md`, explaining update tracking
and competing automatic-update scheduling. Use a tested customer update origin
and serial HA rollout; preserve the immutable build input.
Also read `security.md` and `logically-bound-images.md` for client signature policy
and payload retention, plus [RHEL's registry-authentication
contract](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/deploying-the-rhel-bootc-images).
Provision credentials at deployment; avoid examples that bake them into shared
images.
[KONFLUX-5894](https://redhat.atlassian.net/browse/KONFLUX-5894)/[CLOUDDST-25571](https://redhat.atlassian.net/browse/CLOUDDST-25571)
document the separate stage trust path.
