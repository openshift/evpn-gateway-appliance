# BIB disk-component contract

This is an implementation contract for the qcow2/raw derivatives in
[`pipeline-spec.md`](pipeline-spec.md), not ready-to-apply tenant YAML. Resolve
all registry, product, entitlement, and cluster values through the approved
input contract first.

## Verified task baseline

`konflux-ci/build-definitions` `3349e7e2` (2026-09-22) contains `build-vm-image/0.3`
with task version **0.3.2**, unchanged at `a52c0bf9` on 2026-09-29
([task](https://github.com/konflux-ci/build-definitions/blob/a18268d7/task/build-vm-image/0.3/build-vm-image.yaml)).
The directory alone does not identify its behavior; resolve and pin the approved
bundle digest.
Its relevant interface is:

| Input/output | Contract to verify on the target cluster |
| --- | --- |
| Inputs | `PLATFORM`, `SOURCE_ARTIFACT`, `IMAGE_TYPE`, `BIB_CONFIG_FILE`, `CONFIG_TOML_FILE`, and, when required, activation-key or entitlement inputs |
| BIB wrapper | Digest-pinned bootc `source-image` plus explicit tag-form `tagged-as` naming the intended bootc update origin |
| qcow2 | `disk.qcow2`, media type `application/vnd.diskimage.qcow2` |
| raw | `disk.raw.gz`, OCI artifact type `application/vnd.diskimage.raw.gzip` |
| vmdk / ova | `disk.vmdk.gz` / `image.ova.gz`, gzip artifact types; the disk-CDN task decompresses a mapped `source` found only as `<source>.gz`, so customers download uncompressed files |
| provenance | image digest/reference and SBOM results, including SBOM blob URL |
| platform | `PLATFORM` and `IMAGE_PLATFORM_MAP` results; pass the latter to a compatible `build-image-index` task (0.4 in checked `container-build-catalog` main) |

The task uses an MPC remote task and a TaskRun-scoped
`multi-platform-ssh-$(context.taskRun.name)` volume. Prove the target cluster's
MPC and entitlement behavior with a non-releasing build. Do not create a
TaskRun-named SSH secret manually or assume the checked upstream bundle is the
bundle approved on the target cluster.
Have the platform owner confirm a supported **single-use rootful VM** profile
for each selected architecture, including termination after cancellation or
timeout. Pooled rootless capacity is not interchangeable with that profile.
MPC owns its hosts and SSH credentials; route failed cleanup to its operator,
and keep the EVPN test-resource reaper scoped to resources the tests create.
See the [builder isolation evidence](source-evidence.md#4-build-correctness-requires-content-checks).
Size remote-host RAM, storage and timeouts with actual qcow2/raw canaries;
the build step's Tekton `computeResources` budget covers the SSH orchestrator,
not the remote builder (KONFLUX-13030).
Check builder-host kernel/filesystem compatibility too. Rootful MPC access does
not establish `/dev/kvm` availability for VM-wrapped builds or qcow2 boot tests;
KONFLUX-15229/15338 still track that separate capacity requirement. For tests,
the integration catalog's `mapt-oci/kind-aws-spot` 0.3 provisioner, or MAPT
directly, selects an AWS bare-metal instance when `nested-virt` is set, which
provides KVM. Its kubeconfig and SSH Secrets are owner-referenced to the run, but the VM
itself is destroyed by a timeout or a `deprovision` task (see
[source evidence](source-evidence.md#11-bootc-specific-build-behavior)). It expects a static
AWS-key secret, so the federation note below applies.

Before release, verify these independent properties on a real artifact:

- **Index platforms:** thread `$(tasks.build-vm-image.results.IMAGE_PLATFORM_MAP[*])`
  into the index task's `IMAGE_PLATFORM_MAP` array when using a matrix. Check
  every disk descriptor has the expected `linux/amd64` (or approved platform),
  including a single-architecture index. Keep the artifact's OCI empty config;
  platform belongs on the index descriptor. AIPCC-1307 documents why rebuilding
  the index without this mapping loses platform information, and KFLUXSPRT-8972
  shows the cost: a RHEL AI production disk release failed in `apply-mapping` on a
  missing `platform` in September.
- **Input binding:** stock 0.3.2 reads bootc/BIB references from the wrapper;
  it does not emit dedicated input-image provenance results (AIPCC-17690).
  Resolve the wrapper and TOML from the disk build's verified source commit,
  prove `SOURCE_ARTIFACT` preserves those files or records reviewed transformations,
  and retain their hashes, bootc/BIB digests and resolved platform children.
  Check this chain against the trusted task actually executed; an inherited SBOM
  or a current-branch wrapper is insufficient. Confirm the installed identity
  during boot tests below; canary a disk built from the wrong bootc digest.
- **Trusted SBOM:** run the target policy against every child manifest. EC-1777
  requires signatures for SBOM discovery via referrers/tags; signed provenance
  containing the matching task `IMAGE_DIGEST` and `SBOM_BLOB_URL` is a separate
  trusted path. Version 0.3.1 fixes a trailing newline in `IMAGE_DIGEST` that
  broke that association. AIPCC-32351 remains in Review; its earlier candidate
  fixes do not establish that a policy exclusion or new signing identity is
  needed with the corrected bundle. Prove the complete signed-provenance path.
- **SBOM content:** the task copies the source bootc SBOM and can succeed with
  an empty placeholder if download fails. Reject placeholders and missing
  package inventories, keep `SKIP_SBOM_GENERATION=false`, and bind the SBOM to
  the pinned source digest. Account for any disk customizations that add payload;
  SBOM presence alone does not establish completeness.

Sources: [task and
changelog](https://github.com/konflux-ci/build-definitions/tree/3349e7e2/task/build-vm-image),
[index task](https://github.com/konflux-ci/container-build-catalog/tree/094f3fe/task/build-image-index),
[AIPCC-1307](https://redhat.atlassian.net/browse/AIPCC-1307),
[AIPCC-32351](https://redhat.atlassian.net/browse/AIPCC-32351), and
[EC-1777](https://redhat.atlassian.net/browse/EC-1777).

## Repository and Component wiring

Track `image/bib-qcow2.yaml`, `image/bib-raw.yaml` and a wrapper for each other
approved format (for example vmdk/ova for vSphere). The task reads exactly three
keys; the output type is the pipeline's `IMAGE_TYPE` parameter:

```yaml
# image/bib-qcow2.yaml (placeholders in angle brackets)
bootc-builder-image: registry.redhat.io/rhel9/bootc-image-builder@sha256:<approved>
source-image: quay.io/redhat-user-workloads/<tenant>/<bootc-component>@sha256:<nudged>
tagged-as: registry.redhat.io/<evpn-namespace>/<bootc-repository>:<update-channel>
```

`source-image` is the digest the nudge rewrites; `tagged-as` becomes the installed
update origin (below). Provide an explicit tracked TOML customization file, shared
where appropriate, and size the root filesystem for two deployments plus retained
payload, since upgrades stage a second image:

```toml
# image/config.toml (passed as CONFIG_TOML_FILE)
[[customizations.filesystem]]
mountpoint = "/"
minsize = "<measured size>"
```

Validate it with the selected builder; the documented field is `minsize`, not
`size`, and no user, key or password customization belongs in shipped disks.
Upstream BIB moved into
[osbuild/image-builder](https://github.com/osbuild/image-builder/tree/aa779907c8/bootc-image-builder);
the old repository is archived. Select the supported RHEL builder independently
of upstream examples and assign an owner for updates. The source's `build-ami.sh`
uses `--type ami`; for bootc images that type writes the same `disk.raw` as `raw`
([image
definitions](https://github.com/osbuild/images/blob/908902a8/data/distrodefs/bootc-generic/imagetypes.yaml)),
so EC2 settings must come from the bootc image itself.

| Wiring | Implementation contract |
| --- | --- |
| Bootc dependency | Build-service `spec.build-nudges-ref` names both derivatives; approved integration-service nudging uses `NudgeConfig` with `immediate` edges. Verify the active controller independently of the Application/ComponentGroup model. The common-branch annotation can group same-repository changes. |
| Disk source | Portal points `source.git.context` at `disk-images` and `dockerfileUrl` at a BIB wrapper. These identify the dependency file; they do not configure the custom Tekton task automatically. |
| Disk pipeline | Pass explicit repository-relative `BIB_CONFIG_FILE` and `CONFIG_TOML_FILE` plus `SOURCE_ARTIFACT`; prove paths against the clone/source-artifact layout. |
| Generated resources | Portal uses `skipGitOpsResourceGeneration: true` and reviewed source-repository PipelineRuns. Verify whether the selected cluster's generator supports the required BIB chain. |
| Updates | Portal disables Mintmaker on disk Components. If adopted, preserve bootc nudges and separately cover BIB/config/tool updates. This is a precedent, not a universal requirement. |
| Trigger scope | `build-nudge-files` selects rewritten files; PaC CEL controls triggering. Exclude derivative-only changes from bootc triggers and prove both derivatives rebuild. |

A successful push build can nudge before source ITS completion. Candidate
promotion must verify the bootc's own test/policy evidence and match each disk's
actual input to the selected bootc digest. RHELOPC-2368's closing comment rejects
its earlier custom-nudge/IDMS design as unnecessary for xKS; do not copy the
abandoned proposal. A disk's inherited SBOM is not source-build qualification.

Keep `source-image` immutable for reproducibility. With the checked task, set
`tagged-as` explicitly to a bootc `repository:tag`: it defaults to `source-image`,
then the task unconditionally runs `podman tag`, which rejects a digest as the
target (`tag by digest not supported` on Podman 5.8.4). This creates a local alias for BIB, not a
registry push. The alias also
sets the installed update origin; choose the customer bootc channel, never the
disk-artifact repository (KONFLUX-14595). A managed switch workflow can change
the origin later but does not remove this build-time tag requirement.

Build the releasable disks with the intended production origin, as Portal's
[release-2.2
wrapper](https://github.com/ansible-automation-platform/automation-portal-bootc-container/blob/5afc61bc/disk-images/bib-portal-qcow2.yaml)
does while consuming a private build digest. Stage qualification of a release
candidate must use those bytes; inject trial credentials/trust and record any
temporary reference override only on disposable hosts. Check the embedded origin
before overriding it, and verify the production update path after publication. If changing
`tagged-as`, trust material or any disk customization requires a rebuild, select
and qualify the new disk digests; earlier stage results do not qualify those bytes.

Test upgrade from the prior released image to the candidate and rollback after
failed validation, extending RHEL AI's [upgrade ITS](prior-art.md#host-update-and-recovery);
a fixed digest or timestamp tag does not track new releases (RHELAI-2749). Qualify
the minimum supported installed disk with retained state and old/new OS and
runtime payloads; check free space before staging updates.
AIPCC-6875 shows that successful first boot does not prove upgrade capacity.
Control when customer update tags advance and disable competing
automatic update scheduling when AAP owns serial peer upgrades. Verify persistent
configuration/data compatibility; OS rollback does not automatically undo it.
If prefetching updates, prove an unexpected reboot cannot activate a peer before
its turn. Ordinary `bootc upgrade` stages an update for the next shutdown;
qualify `--download-only`/`--from-downloaded` on the selected RHEL/backend, or
defer staging. Recheck the approved digest after any interrupted prefetch.

Define health checks for unconfigured first boot and configured operation. Test
delayed configuration, unavailable peers and absence of a rollback target, with
bounded retries and observable failure. Inject an unhealthy reachable host,
loss of host access and failure before userspace starts; test recovery for each.
An SSH-driven rollback cannot recover an unreachable host, and a host health
service cannot run before userspace. Bootc does not execute Containerfile
`HEALTHCHECK` metadata as that controller
([runtime contract](https://bootc.dev/bootc/building/bootc-container-runtime.7.html)).
Use the [update/recovery examples](prior-art.md#host-update-and-recovery) to choose
and qualify the mechanism; package presence alone is insufficient.

Exercise that upgrade after reboot using the customer's persistent registry auth
path (bootc reads `/etc/ostree/auth.json`, then `/run/ostree/auth.json`, then
`/usr/lib/ostree/auth.json`, which lives in the image and must stay empty; logically bound
images use that pull secret, but a unit that runs `podman pull` reads Podman's own auth
files and needs separate credentials) and
signature-requiring policy rules for
the actual update and runtime-payload references. Configure strict bootc mode at
installation (`--enforce-container-sigpolicy` or a supported install-config
equivalent), pass the flag on every `switch`, and verify the recorded mode after reboot.
Bootc still honors registry-specific rules without this flag, but strict mode
additionally rejects a default `insecureAcceptAnything` policy. A later `switch`
without the flag resets that mode; `upgrade` inherits the recorded reference.
Canary signed, unsigned and wrong-key images through the real bootc/Podman clients,
including the customer channel tag, signature format and index/child behavior.
Standalone `cosign verify` or a CI-authenticated pull is insufficient.
Provision customer credentials securely at deployment, never inside shipped disks.
Stage tests need the approved
stage signature endpoint/key and network path; do not ship stage trust in production.
KONFLUX-5894/CLOUDDST-25571 distinguish signature publication from client lookup;
[bootc install policy](https://bootc.dev/bootc/man/bootc-install-config.5.html)
and [switch implementation](https://github.com/bootc-dev/bootc/blob/44c7024e/crates/lib/src/cli.rs)
define the recorded enforcement mode. Qualify support in the selected RHEL version.

No personal SSH key or customer credential belongs in disk customization. Prove
launch-time access and runtime dependency/egress behavior on the actual image.

## Enterprise Contract and package access

Use separate bootc and disk policy canaries. Portal's policies demonstrate
rootful/MPC, package-repository and non-container-artifact accommodations. They
also contain historical broad exclusions; that is not evidence EVPN needs them.
Derive each exception from a target-policy failure and approved rationale. Keep
source-image security/provenance checks intact when a disk-specific rule does
not apply. Record the resolved policy/data identities with the test results.
Specifically check `buildah_build_task.platform_param`: despite its name, it
examines artifact-producing tasks, including BIB. Central rule data disallows
platforms matching `.*root.*`; the xKS/Portal disk policies override that data.
Obtain EVPN's own scoped approval instead of copying their empty deny list.

Run policy canaries on both the complete candidate and each channel's actual
post-mapping Snapshot. The checked disk-CDN pipeline maps/reduces before Conforma,
so a base-image digest present in the full set can be absent during publication.
Inspect the bases actually reported in each SBOM; inherited disk SBOMs do not
necessarily name the consumed EVPN bootc image. Prove the effective policy's
in-Snapshot or approved release-signature path before requesting a narrow exception.
An earlier full-set pass is insufficient; neither stage publication before disk
building nor a blanket workload-registry allowance is a general requirement.
See [policy input and base-image
evidence](source-evidence.md#5-release-configuration-and-publication-need-their-own-gates).

The checked disk task has no `HERMETIC` input: its remote script pulls images,
does not request Podman network isolation, and installs publishing tools with
live `dnf`. Pinning the bootc and BIB images does not make that task hermetic. Qualify its required
egress/package access and retain resolved tool/repository inputs separately,
including its tag-form internal `BUILDAH_IMAGE` and installed publishing RPMs.
Conforma's [hermetic
rule](https://github.com/conforma/policy/blob/ac72407d/policy/release/hermetic_task/hermetic_task.rego)
checks `HERMETIC=true` only for configured task names; the
[defaults](https://github.com/conforma/policy/blob/ac72407d/policy/lib/rule_data/rule_data.rego)
name `buildah` and `run-script-oci-ta`, not `build-vm-image`. Verify target rule
data and any required exception; a passing disk policy is not proof of isolation.

Empty disk OCI configs cannot carry container labels. KRD permits specific
non-container `labels.required_labels` exceptions; its tests also restrict new
static exclusions (RELDEV-317). Use an approved structural exception where
supported, or a time-bounded exception with owner/reference/expiry for a temporary
regression. KRD's `tests/test_ecp.py` makes both concrete: each EVPN ECP must
declare `konflux-release-data/derived-from` naming a root policy (production ones
derive from `registry-standard`, stage from `registry-standard-stage`), and
temporary exclusions go under `volatileConfig.exclude` with `effectiveUntil` and a
Jira `reference`. Do not fabricate labels or copy `trusted_task.trusted` and an entire
Portal exclusion list. Treat trusted SBOM lookup and real SBOM content as separate
checks, even if a precedent excludes `sbom.found`.

Prove approved RHEL package access in both the Containerfile and BIB task.
Entitlement/activation-key inputs are supported when required; they are not
mandatory for every repository-access arrangement. Never copy another tenant's
secret path. Likewise, `enforceContainerFirstSecurityLabels` is not a first-layer
label requirement; validate the bootc's final labels against its effective policy.

## Disk validation and AWS lifecycle

1. Assert filename/artifact type, indexed platform, signed provenance and
   substantive SBOM. Resolve the selected OCI child and disk layer by its
   `org.opencontainers.image.title`; do not choose a blob by size.
2. Boot qcow2 in owned capacity. Test access, exact booted image, single-VM health,
   runtime payload, persistent networking and service recovery after reboot.
   Keep the old three-node `health-check.yml` in topology tests only.
3. For raw, budget storage for decompression, import the exact disk into AWS,
   register/launch a test AMI and record its account/region/ID and disk checksum.
   Reuse only an available AMI whose ledger matches the raw child digest/checksum,
   architecture and import settings; launch that exact ID through an adapted
   backend or direct EC2 API. Canary two different disk builds from the same
   source commit to prove a stale AMI cannot pass.
   Test architecture, boot mode, ENA/storage settings and launch access on the
   intended instance type. Retain boot/health diagnostics before cleanup; collect
   FRR state, routes and packet captures where selected checks or failure investigation
   need them, following the [evidence visibility
   contract](ci-bootstrap-spec.md#evidence-visibility).
4. Prove cleanup on success, failure, timeout and cancellation, including partial
   deployment. Reuse backend cleanup and retained per-run resource records with
   ownership tags, plus an owned scheduled reaper for leaks that survive the run.
   A record retained through cancellation/reaper expiry can be the ledger; no new
   database/service is implied. Cover instances, AMIs, snapshots, volumes, keys,
   security groups, import buckets/objects and helper infrastructure.
   Protect active tests; require an expired lease or confirmed run termination.
   Check every inventory page and report failed deletions and remaining resources;
   a zero process exit alone is insufficient. Retain creation IDs and reconcile
   service-native inventories: AWS [GetResources](https://docs.aws.amazon.com/resourcegroupstagging/latest/APIReference/API_GetResources.html)
   omits resources that were never tagged, so tag-only discovery cannot prove partial-create cleanup.
   Qualify the chosen cleanup service's coverage before writing residual SDK glue;
   count any custom state/lease/deletion handling in the source-CI budget.

### Booted identity

For both formats, check `bootc status --json`'s
`status.booted.image.imageDigest` against the selected bootc platform manifest,
with verified index-to-child resolution, before any test-side switch and after
test preparation and each upgrade/rollback. Verify the reported origin separately. Preserve
`/sysroot/.bootc-aleph.json` where available for the initial install digest and
target origin; it does not describe the current deployment after upgrades.
Use the selected RHEL version's schema, rejecting missing identity evidence.
[Bootc's status
implementation](https://github.com/bootc-dev/bootc/blob/44c7024ec6e80d02fa9627dc7a81c7729cbad0b0/crates/lib/src/status.rs),
[schema](https://github.com/bootc-dev/bootc/blob/44c7024ec6e80d02fa9627dc7a81c7729cbad0b0/crates/lib/src/spec.rs),
[installation record](https://github.com/bootc-dev/bootc/blob/44c7024e/crates/lib/src/install/aleph.rs).

### Test backends

Choose between concrete backends after a canary:

| Precedent | Reuse / limits |
| --- | --- |
| RHEL AI `rhelai-disk-image-test.yaml` | MAPT helper/test VMs and cloud-importer; replace Git-SHA/name-based AMI reuse with candidate identity checks. Separate `cleanup-resources.yaml` handles AMIs; `finally` VM teardown is incomplete. |
| Portal `pipelines/portal-disk-image-test.yaml` (private, `e56e610e3f`) | qcow2 boot under QEMU on a MAPT nested-virt spot Fedora helper in AWS, access through a cloud-init NoCloud seed, SSH-driven product tests, helper deleted in `finally`. The closest qcow2 precedent. EVPN's version must pin the MAPT task, use federated AWS identity, verify SSH host identity and assert the booted image digest. |
| xKS, RHELOPC-2265/2650 | Testing Farm/tmt orchestrates locally runnable OCI extraction, direct AWS import/register, EC2 smoke and cleanup scripts. 2265 remains In Progress; 2650 closed into review follow-up 2754. RHELOPC-2504/2321 provide completed extraction/provisioning work. |

Neither cloud-importer, a helper VM, nor multi-region replication is universally
required. If MAPT fits, compare the pinned `mapt-oci` catalog tasks with direct
git-resolved tasks; validate their parameters and permissions. If reusing RHEL
AI's `config-from-snapshot`, its component-name parsing is an adapter assumption,
not a Konflux naming requirement. Pin test/tool revisions and replace inference
checks with EVPN tests.

The stock Testing Farm adapter also assumes a triggering-component label: an
ordinary manual Snapshot lacks it, so preprocessing selects no image. Use a
reviewed adapter that selects the expected components explicitly and passes the
full candidate (`SNAPSHOT_b64`) to EVPN tests, with explicit test Git SHA and pull
identity. Canary both a manual candidate and a push triggered by each Component.
Pin its five Task bundles independently from the runtime image; one shared
`IMAGE_TAG` defaults to `latest` and cannot hold different images' digests.
Keep TLS verification enabled. See [the adapter source](prior-art.md#runnable-test-patterns).

### Preserving the candidate

Make test preparation preserve the delivery candidate. tmt's `how: bootc` builds
a new qcow2 and, by default, a derived bootc image with test dependencies;
`add-tmt-dependencies: false` still rebuilds the disk. Use an explicit extracted
qcow2 with a qualified VM backend, or connect to the exact imported AMI.
Independently, tmt's bootc package manager can build a derived image, switch and
reboot when installing dependencies. Keep test tools on the controller where
possible; declare guest preparation and reject unexpected image replacement before
counting qualification results. Exercise a dependency-install attempt as a negative
canary. Development tests of derived images remain useful separate evidence.
See the [pinned tmt implementations](prior-art.md#preserving-the-test-subject).

### AWS identity and cleanup

Prefer the documented Konflux OIDC → AWS STS path for tenant tests: projected
tokens with audience `sts.amazonaws.com`, the exact cluster issuer and tenant
service-account subject in IAM trust, and approved bucket/import permissions.
A reviewed `resourceKind: pipelinerun` ITS can set `taskRunTemplate.serviceAccountName`;
the checked controller preserves it. Run AWS SDK/CLI operations with the renewable
credential provider in that pod where practical. RHEL AI's remote importer copies
only access/secret keys; the checked MAPT catalog wrapper also reads a static-key
secret. Neither wiring is a ready-made OIDC adapter. If a helper is needed, prove
its own refreshable identity and importer support; temporary credentials require
the session token too. Exercise upload, import polling and cleanup beyond initial
credential expiry. MAPT itself supports session tokens; the adapter is the gap.
Use pinned tools, required IAM retention tags and approved code. Obtain an approved
secret fallback only if federation is unavailable. Managed Marketplace credentials
remain separate.
See [federation example](prior-art.md#runnable-test-patterns) and
[AWS credential provider](https://docs.aws.amazon.com/sdkref/latest/guide/access-assume-role-web.html).

For direct VM Import, account setup must provide the separate `vmimport` service
role (or approved `RoleName`), trusting `vmie.amazonaws.com`, and grant the test
caller `iam:PassRole` on that role. Verify import-bucket access and any required
KMS grants. The existing `image/setup-vmimport-role.sh` is account bootstrap,
not a per-test step. Cloud-importer instead creates a bucket and import role;
explicitly approve and track that larger resource/permission lifecycle if chosen.
[AWS requirements](https://docs.aws.amazon.com/vm-import/latest/userguide/required-permissions.html).

Separately prove that the external extractor/test identity can pull the private
candidate by digest. AWS STS access does not grant registry access. Use the
approved registry/proxy path; the documented image RBAC proxy grants tenant-wide
pull access and covers `redhat-user-workloads(-stage)`, not every Quay organization.
Canary token issuance under the target cluster's RBAC/admission policy: the public
guide's legacy service-account-token Secret recipe was denied in KFLUXSPRT-8816.
Use an allowed TokenRequest/projected-token path and a dedicated pull identity;
the [external-puller
role](https://github.com/redhat-appstudio/infra-deployments/blob/3f76b7bf/components/konflux-rbac/production/base/bot/konflux-externalpuller-bot-actions.yaml)
provides the narrow ImageRepository reads. Verify actual expiry and renewal at the
external executor across long tests. See [private-image
scope](https://konflux-ci.dev/docs/building/accessing-private-images/)
and the still-open [credential documentation correction](https://github.com/konflux-ci/docs/pull/648).

### Where the tests run

Run the boot and lifecycle tests in the pipeline plan's required `push`-context
[candidate suite](pipeline-spec.md#3-integration-gates-and-test-infrastructure).
`SINGLE_COMPONENT=true` EC tests alone cannot qualify the release set.

## Customer delivery channels

| Channel | Verified implementation and inputs |
| --- | --- |
| Bootc registry | Managed `rh-advisories`, approved stage/prod registry identities, product labels and tag/update policy |
| Disk download | `push-disk-images-to-cdn`: Pulp destination, environment/intention, product metadata, source filename and customer filename/version mapping |
| Marketplace AMI | `push-disk-images-to-marketplaces`: raw artifact, managed `release-stratosphere` service account, approved StArMap/listing/account/region/instance configuration ([stage example](examples/release/xks-aws-marketplace-stage-rpa.yaml)). No Konflux user guide or pipeline README covers onboarding; RHEL AI's and xKS's RPAs and RHELOPC-2351 are the working reference |
| Other AMI distribution | An explicitly owned publication or sharing contract ([AMI channel](#ami-channel)). A private VM Import test AMI is not customer publication |

Check each channel against the tenant's cluster. In cached KRD, all 21
`push-disk-images-to-cdn` and 17 `push-disk-images-to-marketplaces` RPAs run on
private `stone-prod-p02`, while public clusters publish Pulp and Content Gateway
files only through `push-artifacts-to-cdn` (ACS, ROSA CLI). An EVPN team tenant
for the public `openshift` repository would be on public `kflux-prd-rh02`, so have
releng confirm the disk and Marketplace pipelines work there before relying on them.

Portal's **single** disk RPA maps both qcow2 and vmdk to the **same** Pulp
repository, despite `singleComponentMode: true`. Neither one RPA nor one Pulp
repository per format is a general requirement. The catalog's `reduce-snapshot`
task uses the Snapshot's built-component label when this mode is true and rejects
manual Snapshots without component/type labels. For the complete candidate,
disable reduction and use channel mappings, or deliberately release selected
components with traceable evidence. Do not copy `true` onto a full-set release.
RHEL AI keeps both per channel: its cached `bootc-containers-prod-3-5` and
`bootc-containers-full-prod-3-5` RPAs (and matching ReleasePlans) differ only in
`singleComponentMode`, so a complete set and a single-component fix each have a path.
Assert exact expected channel names/digests before publication, then reconcile
the published set with the release ledger. `apply-mapping` drops unmatched names;
`failOnEmptyResult` does not catch a missing subset. Raw CDN distribution is
optional, independent of raw being the AMI build input. If adding architectures,
check destination layout first: one component's `staged.destination` cannot split
its files across per-architecture Pulp repositories (RELEASE-2819).

For disk CDN, preflight every mapped source file. The production publisher
(catalog `f82bf0e3`, utils `1ca0a0a5`) now derives each component's directory from
its own destination and fails on a duplicate destination/filename pair, but it
still logs a missing mapped file and continues. When publishing multiple
components, stage-test different Snapshot orders and verify each customer
filename/checksum against its component. Canary the actual multi-registry pull
secret, realistic artifact size and resolved internal task too.
See the [publication
evidence](source-evidence.md#5-release-configuration-and-publication-need-their-own-gates).

At the checked production catalog revision, disk CDN has no `create-advisory`
task; Marketplace and generic CDN pipelines do. For advisory output or
`mirror.openshift.com` delivery, evaluate `push-artifacts-to-cdn` with
`contentType: disk-image`; it preserves disk bytes without adding an archive.
Canary its different extraction/mapping/signing contract with EVPN's actual BIB
artifacts. Content Gateway (CGW)-only disk-image advisory entries are fixed in
development but not in the checked production catalog. ART's 4.22 Agent ISO
release used a feature branch for 64 GB extraction, timeouts and CGW retries,
and its advisory lists the ISO. Require correct per-file advisory entries and
checksums on the resolved revision, not just a successful push. See the
[implementation evidence](source-evidence.md#5-release-configuration-and-publication-need-their-own-gates).

`create-advisory` creates Konflux advisory
data through an InternalRequest/GitLab workflow. Its name does **not** establish
a legacy Errata Tool/Brew prerequisite (RHELOPC-2263 explicitly uses pure Konflux).
Use the selected channel's actual metadata and approval contract. Collection
Hub/Galaxy publication is addressed in the canonical plan, not by substituting
binary CDN delivery.
Set `mapping.components[].contentType: disk-image` for disk release mappings and
verify generated CVE/artifact coverage. Unlike Marketplace, the checked production
disk-CDN pipeline has no `embargo-check`; PR #2342 remains open (KONFLUX-14912).
Require equivalent pre-publication clearance until that channel supplies it.

Create approved stage ECP/RPA/RP before trial publication; KRD checks that ECPs
are referenced by RPAs.

### AMI channel

CORENET-7506/7522 require an AMI but do not name the channel ([decision](kickoff-decisions.md)).
The Konflux task runs only pubtools' listing push (`--nochannel` for pre-push), so
a Marketplace listing is the only wired path. A CDN-download-only Tech Preview or a
community AMI needs its own owned contract, and so does a customer-built AMI: RHEL
documents `bootc-image-builder --type ami --aws-ami-name --aws-bucket --aws-region`
against a registry image, which needs a privileged host, an S3 bucket and the `vmimport`
role and creates the AMI in the customer's account; RHEL accepted a CDN download alone for
its AWS CVM Tech Preview image (RHELDST-37290).

**Stage.** xKS's Marketplace pre-push supplies private AMIs before production
listing IDs exist (RHELOPC-2351/2330). They are registrations shared with
Stratosphere accounts, not a staging listing.

**Architectures.** The task's `oras pull` passes no `--platform`, in both the
production (`f82bf0e3`) and development catalogs. Pulling a multi-architecture
index overwrites same-named files, so the wrong architecture can publish silently,
and the task's file-exists check does not notice (RHELOPC-2326). The fix is catalog
PR #2453 (RELEASE-2758), open on September 29; xKS's multi-architecture stage run
uses its `release2758` feature branch. Publish single-architecture components, or
confirm the resolved task carries the fix, and launch each resulting AMI.
RELEASE-2775 plans repository enforcement (the ticket gives September 19 and was still In
Progress on September 30) that limits production releases to approved repositories and the
catalog's `development`, `staging` and `production` branches, so use one of those or an
approved exception and record resolved commits.

**Image requirements.** If the channel is Marketplace, qualify these early: source
AMI in `us-east-1`; supported HVM/EBS layout with unencrypted source snapshots and
filesystems; working launch-time administrative access and the declared SSH
scanning port; metadata-dependent access tested with IMDSv2 required; no SSH
password logins, baked authorized keys or hardcoded secrets; no request for AWS credentials
(use instance roles); a Region-agnostic build; operation without launch-time user data
for Launch from Website. AWS rejects an AMI more than two years past its creation date.
A version the seller has restricted for two years is archived: existing users can still
launch it by AMI ID, and AWS deletes it after 13 months without a launch. Together these
bound how long an AMI can be submitted, and how long a restricted one can serve as a
rollback or collection-pinned baseline. BYOL or free editions are accepted only
alongside an equivalent paid version. Once the product exists, the channel owner
retains a successful **Test ‘Add version’** scan for the candidate; it tests
vetting without publishing a version, and private pre-push can precede that setup
([AMI requirements](https://docs.aws.amazon.com/marketplace/latest/userguide/product-and-ami-policies.html),
[scanning
guidance](https://docs.aws.amazon.com/marketplace/latest/userguide/best-practices-for-building-your-amis.html)).

**Retries.** Reconcile them with the actual listing/version/AMI identity. The
publisher skips an existing version on a title substring match without verifying
its AMI against the candidate: reject a collision or a mismatched ledger. Set
`restrict_version` and its retention limits deliberately, since enabling it can
restrict older versions and delete their AMIs and backing snapshots. Keep supported
rollback versions until retirement is separately approved; RHEL AI's copied `true`
is not EVPN's policy
([publisher
implementation](https://github.com/release-engineering/pubtools-marketplacesvm/blob/f0bffb5/src/pubtools/_marketplacesvm/cloud_providers/aws.py)).

### Publication mechanics

For tenant/final readback, confirm the release controller's workspace size
(upstream default `1Gi`, set by its `DEFAULT_RELEASE_WORKSPACE_SIZE`). `useEmptyDir`
retains that size limit and does not share files between Tasks. Stream download/checksum checks
where possible; use approved
storage or an external backend for extraction/boot that exceeds that capacity.
[Workspace contract](https://konflux-ci.dev/docs/releasing/tenant-release-pipelines/#workspace-configuration),
[controller
implementation](https://github.com/konflux-ci/release-service/blob/b277b37/tekton/utils/pipeline_run_builder.go).

Rehearse realistic artifact sizes through extraction and managed/internal release
workspaces, not just the build/import host. Budget compressed and expanded copies,
critical-path duration across parent/Task/InternalRequest timeouts, retries and
cleanup, with observable progress. A longer internal timeout does not extend its
parent's deadline (RELEASE-2832). RELEASE-2811 exhausted an internal 1 GiB workspace
with a large ISO. Jira automation reported its fix (catalog #2562) promoted to
production on September 28, yet production `f82bf0e3` did not contain it on
September 29. Verify the resolved implementation rather than assuming either the
old limit or the fix.

Distinguish Tekton Task retries, automatic managed-pipeline retries and a new
Release. Check the deployed RPA's `status.retryInfo` and retain the Release's
`status.managedPipelineAttempts`; setting `maxRetries` cannot enable an unconfigured
pipeline. Only `OOMKill` and pipeline or task timeouts retry (an `Error` never does),
each attempt raising memory or timeouts on the previous one's values, and an
`{{ incrementer }}`-style tag in release data turns retries off. [Retry
contract](https://konflux-ci.dev/docs/releasing/managed-pipeline-retries/).
Keep the approved inputs and channel serialization valid across all attempts:
the retry path reloads release configuration and starts another managed run;
it does not rerun the successful tenant preflight. Qualify the release-owner
cancellation procedure in stage. Deleting an active PipelineRun is not a stop
mechanism: the controller can recreate it (KONFLUX-11968). Retain the ledger and
confirm both parent and internal/remote work have stopped before recovery.
For CDN, rehearse timeout/cancellation with an active InternalRequest and partial
publication. Establish whether earlier internal/remote work has finished before
starting a replacement Release. Same-run cleanup and Portal idempotency exist,
but are not cross-release serialization or proof of unchanged customer content.

A successful Pulp push did not initially make Portal images customer-visible
(RHELDST-25997); product metadata needed separate work. Implement the pipeline
plan's [customer readback](pipeline-spec.md#4-promotion-and-operation) in
`spec.finalPipeline`, using the Release's actual outputs and the expected channel
ledger. Check the preceding publication phase's
outcome first: the hook also runs after failure. Do not wait for overall
`Released=True` inside it; the controller waits for the final pipeline before
marking success. Required readback tasks must fail on errors. AAP's pinned final
pipeline proves the hook and resource-reference interface, not a ready-made EVPN
gate; see [the example](prior-art.md#build-and-release-implementations).
Provision its service account's Release/RP/Snapshot reads explicitly. Use bounded
polling/Task retries for propagation delays and stream large download checksum
checks or use owned storage. Even when enabled, managed OOM/timeout retries do not
retry this hook; rehearse final-failure recovery without assuming publication is
undone or that a new Release is free of duplicate side effects.

Exact repository paths and read revisions: [`prior-art.md`](prior-art.md) and
[source evidence](source-evidence.md).
