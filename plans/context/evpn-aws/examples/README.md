# Konflux reference examples

Copies of real configuration that EVPN's pipeline resembles, unchanged except for
redacted account, user and product identifiers, internal endpoints and other details
that do not matter to EVPN (each file's header says what), kept
only where the source is internal or private, or small. Public files are linked
at a pinned revision below. Each copy starts with its source repository, revision
and path. They are examples,
not EVPN configuration: never copy another product's names, IDs, secrets, service
accounts, policy exclusions or pinned revisions. Recheck the source for changes
before relying on a detail. KRD copies come from the cached `8c18efee29`
(2026-09-18) checkout and may lag the current head.

| File | What it shows | Reuse for EVPN | Do not copy |
| --- | --- | --- | --- |
| [`tenant/portal-bootc-component.yaml`](tenant/portal-bootc-component.yaml) | bootc Component with `build-nudges-ref` to disk Components; ImageRepository with Bombino SBOM webhook | Nudge wiring; SBOM webhook question for ProdSec | Names, namespace, private visibility choice |
| [`tenant/portal-qcow2-disk-component.yaml`](tenant/portal-qcow2-disk-component.yaml) | Disk Component whose `dockerfileUrl` is a BIB wrapper; `skipGitOpsResourceGeneration`; Mintmaker disabled | Disk Component shape | Disabled Mintmaker without another BIB/tool update path |
| [`tenant/rhelai-aws-disk-image-its.yaml`](tenant/rhelai-aws-disk-image-its.yaml) | ITS resolving a disk boot-test pipeline, `component_` context, optional | ITS shape | Moving `revision` parameter (`main`), `optional: "true"` and component-only context for release gates ([pipeline plan](../pipeline-spec.md#3-integration-gates-and-test-infrastructure)) |
| [`tenant/bgp-cc-release-plan-stage.yaml`](tenant/bgp-cc-release-plan-stage.yaml) | The networking org's stage ReleasePlan on public `kflux-prd-rh02` | ReleasePlan shape, standing attribution | `auto-release: "true"` for production; the `author` label names EVPN's accountable release owner but does not prove approval of a particular candidate |
| [`release/bgp-cc-stage-rpa.yaml`](release/bgp-cc-stage-rpa.yaml) | `rh-advisories` stage RPA: `registry.stage.redhat.io`, immutable plus moving tags, release notes, source containers | Bootc registry channel | Product ID, repository paths |
| [`release/bgp-cc-prodsec-template.yaml`](release/bgp-cc-prodsec-template.yaml) | KRD `prodsec/<tenant>.yaml` template rendering stream and CPE | Shape of EVPN's template | Stream/CPE values (ProdSec assigns them) |
| [`release/registry-standard-ecp.yaml`](release/registry-standard-ecp.yaml) | Root production policy; already excludes `cve.cve_blockers` (KONFLUX-7113) | Starting point for an EVPN ECP (`derived-from: registry-standard`) | — |
| [`release/portal-disk-images-prod-ecp.yaml`](release/portal-disk-images-prod-ecp.yaml) | Derived disk policy: rootful-platform rule data and many exclusions | Shape of a derived policy | Its exclusion list: justify each EVPN exception from a real failure |
| [`release/portal-disk-images-prod-rpa.yaml`](release/portal-disk-images-prod-rpa.yaml) | Disk CDN RPA: two formats to one Pulp repository, `singleComponentMode: true` | Disk download channel shape | `singleComponentMode` for a full-set release |
| [`release/xks-aws-marketplace-stage-rpa.yaml`](release/xks-aws-marketplace-stage-rpa.yaml) | AMI stage RPA: StArMap, `cloudMarketplacesPrePush` private AMIs, all-zero placeholder Marketplace destination IDs | AMI channel shape before listing IDs exist | The `release2758` feature branch, SSH `0.0.0.0/0` security group, `restrict_version: true` (deletes retired AMIs), any product identifiers |

Public examples worth reading in place rather than copying:

- Task and pipeline contracts at the checked revisions: the BIB task
  [`build-vm-image`
  0.3.2](https://github.com/konflux-ci/build-definitions/blob/a18268d7/task/build-vm-image/0.3/build-vm-image.yaml);
  the managed
  [disk-CDN](https://github.com/konflux-ci/release-service-catalog/blob/f82bf0e3/pipelines/managed/push-disk-images-to-cdn/push-disk-images-to-cdn.yaml)
  and
  [Marketplace](https://github.com/konflux-ci/release-service-catalog/blob/f82bf0e3/pipelines/managed/push-disk-images-to-marketplaces/push-disk-images-to-marketplaces.yaml)
  pipelines on the production branch (Marketplace is the only managed AMI publisher).
- AWS disk test: RHEL AI's
  [`rhelai-disk-image-test.yaml`](https://github.com/red-hat-data-services/aipcc-konflux-data/blob/70af2437/pipelines/rhelai-disk-image-test.yaml)
  (Snapshot parsing, helper VM, extract/import, test VM, finalizers) is the structure of a raw→AMI
  boot test. Do not copy its Git-SHA AMI cache identity
  or static keys ([BIB spec](../bib-configuration-spec.md#disk-validation-and-aws-lifecycle)). The
  ITS above resolves a private GitLab copy of this pipeline.
- The networking org's own Konflux build:
  [`openshift/bgp-cloud-connector/.tekton`](https://github.com/openshift/bgp-cloud-connector/tree/4e507d5d49/.tekton)
  (public repository, `openshift` org, `kflux-prd-rh02`), and its
  [OpenShift CI
  configuration](https://github.com/openshift/release/blob/ff1189c2/ci-operator/config/openshift/bgp-cloud-connector/openshift-bgp-cloud-connector-main.yaml):
  lint/unit/verify, a `fips-check-image-scan` step, and AWS/ROSA e2e jobs that
  enable the FRR provider and route advertisements before testing.
- Collection release: [`hashicorp.vault`'s release
  workflow](https://github.com/ansible-collections/hashicorp.vault/tree/3d36f142c7/.github/workflows)
  calling
  [`release_ah.yaml`](https://github.com/ansible/ansible-content-actions/blob/cbdec1f7/.github/workflows/release_ah.yaml).
- OpenShift CI for a collection: the [SDN-migration collection's
  config](https://github.com/openshift/release/blob/ff1189c2/ci-operator/config/openshift/network.offline_migration_sdn_to_ovnk/openshift-network.offline_migration_sdn_to_ovnk-main.yaml).
- Bootc push PipelineRun: CentOS Stream's
  [`centos-bootc-push.yaml`](https://gitlab.com/redhat/centos-stream/containers/bootc/-/blob/d22f06b8/.tekton/centos-bootc-push.yaml)
  shows `privileged-nested: "true"`, RPM prefetch, four platforms and a shared pipeline through the
  git resolver. Reuse its bootc build parameters and resource sizing, not its pipeline repository,
  branch CEL or platform list. It is linked rather than copied because that repository is
  MIT-licensed.
- Explicit promotion gate: HyperShift's
  [`ho-release-gate.yaml`](https://github.com/openshift/hypershift/blob/43d6b36b/.tekton/pipelines/ho-release-gate.yaml).

[`prior-art.md`](../prior-art.md) lists private and larger examples, including
Portal's release-2.2 BIB wrapper with the correct customer bootc origin.
