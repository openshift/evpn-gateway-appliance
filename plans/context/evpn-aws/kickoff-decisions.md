# EVPN Gateway Appliance (EGA) — decisions by delivery gate

Use these inputs with [`pipeline-spec.md`](pipeline-spec.md). Jira acceptance
criteria are requirements; an item below is a decision only once it records an
owner, date and evidence. Everything else is a proposal for discussion, and role
owners are proposed. Status rechecked on 2026-10-15; review directions retain their dates.

## Decisions at a glance

Each row is detailed under the gate that first needs a part of it; owners are proposed.
A bundled row does not make every choice a prerequisite for that entire gate. Use the
specific input in "Needed for": source lint needs reviewed files, an AWS test needs identity,
and publication needs its destination. Resolve the remaining choices alongside ready work.

| # | Decision | Owner | Needed for | Status |
| --- | --- | --- | --- | --- |
| 1 | Correct three Jira criteria: 7501's VIF wording, 7504's VNI/MAC views, 7505's "approved upstream" images | PM / Networking | [Start now](#start-now-without-waiting-for-engineering) | Review direction 2026-10-01; accountable owner and Jira correction pending |
| 2 | Official product name, the long-lead approvals, and the supported architectures the Engineering ID request asks for | PM / Product Security / releng | [Start now](#start-now-without-waiting-for-engineering); Engineering ID | Open |
| 3 | What to import publicly, and owners for the source defects | Source owners / releng | [Gate A](#gate-a--source-ci) | Open |
| 4 | Source CI: Prow contexts, tide, GitHub Actions, Konflux GitHub App | Engineering / Networking | [Gate A](#gate-a--source-ci) | Review direction 2026-10-02; Prow merged, with `ci/prow/images` and `ci/prow/verify` required since release#86670 (2026-10-13); hosted lanes and Konflux contexts/App remain open |
| 5 | Collection name, shape, content class, scope and layout | Architecture / AAP content | Reviewed source scope/layout for [Gate A](#gate-a--source-ci); destination/class/matrix before publication | Name directed in review 2026-10-02 (`network.evpn_gateway`); accountable owner/publication approval and the rest remain open |
| 6 | Cluster-side design (native OCP EVPN vs OpenPERouter) and the unified cross-cloud question | Architecture / Networking / PM | First cluster-side implementation/topology lane; no block on static source CI | Open |
| 7 | Product home: team tenant, existing offering or ART | PM / Engineering / ART | [Gate B](#gate-b--non-releasing-konflux-builds) | Open; action item assigned 2026-10-01 |
| 8 | Konflux cluster | Engineering / Konflux platform / releng | [Gate B](#gate-b--non-releasing-konflux-builds) | Open; action item assigned 2026-10-01 |
| 9 | Build canary inputs: tenant, Application, RBAC, quota, MPC capacity | Engineering / Konflux platform | [Gate B](#gate-b--non-releasing-konflux-builds) | Open |
| 10 | FRR and exporter payload, RHEL base, package access | Networking / PM / Product Security | [Gate B](#gate-b--non-releasing-konflux-builds) | Review direction 2026-10-01 (FRR, `frr-metrics`); accountable owner/approvals and the rest remain open |
| 11 | Test backend, AWS identity, funded accounts and labs | QE / AWS / releng / management | First selected AWS/lab test in [Gate B](#gate-b--non-releasing-konflux-builds); no block on a bootc-only canary | Open for the AWS/lab backend; the credential-free emulated EVPN lane (containerlab + test EE + pytest/testinfra) is already realized (see [Already settled](#already-settled)), decision owner/date pending |
| 12 | Artifact set: qcow2, AMI, vmdk/ova, installers, FIPS variant | PM / Architecture | Before adding optional formats/variants, then [Gate C-stage](#gate-c-stage--trial-publication); qcow2/AMI remain Jira requirements | Open |
| 13 | AMI channel and entitlement | PM / cloud publishing / releng | [Gate C-stage](#gate-c-stage--trial-publication) | Open; action item assigned 2026-10-01 |
| 14 | Stage publication objects and how the collection finds the released AMI | Releng / channel owners / Architecture | [Gate C-stage](#gate-c-stage--trial-publication) | Open |
| 15 | Collection publisher and destination | PM / AAP content / releng | [Gate C-stage](#gate-c-stage--trial-publication) | Open |
| 16 | Metric source for 7504's VNI/MAC views and the standalone `frr-metrics` question | Networking / 7504 owner | Selected metrics/dashboard implementation and qualification | Review direction 2026-10-01; accountable owner/approvals pending |
| 17 | Product identity: Engineering ID, CPE, registry paths, ProdSec stream | PM / Product Security / releng | [Gate C-stage](#gate-c-stage--trial-publication) for the Engineering ID; [Gate C-prod](#gate-c-prod--supported-release) for the rest | Open |
| 18 | Support matrix, including the AWS/OCP support decision and ROSA | PM / Architecture / QE | [Gate C-prod](#gate-c-prod--supported-release) | Open |
| 19 | Qualification evidence and sign-offs | Networking / QE / Product Security / docs | [Gate C-prod](#gate-c-prod--supported-release) | Open |

## Already settled

The items below include requirements, repository facts and dated review directions;
a direction without an accountable decision owner remains a proposal
under the rule above. Reviewer identity alone does not supply that owner.

| Requirement, fact or review direction | Evidence |
| --- | --- |
| Direct Connect and Site-to-Site VPN are the production transports; WireGuard is development/test only | CORENET-7498 acceptance criteria |
| Canonical source is public `github.com/openshift/evpn-gateway-appliance`, Apache-2.0, owned by OpenShift Core Networking | DPP-22292 (approved and created 2026-09-28; license, `OWNERS` and these documents, no product source) |
| Azure and GCP implementations are out of scope for this epic | CORENET-7498 scope |
| FRR and `frr-metrics` come from the Red Hat–built `frr-rhel9` image ([option A](pipeline-spec.md#runtime-payload-corenet-7505); the review wrote "openshift/frr image", read here as the image built from `openshift/frr`), and `frr-metrics` must be changed to need no Kubernetes cluster and to export EVPN metrics (decision 10, in part) | Review of pull request #2 by the Networking maintainers, 2026-10-01 (comment by `jcaamano`) |
| A Direct Connect gateway attached to a TGW uses a transit VIF, not a private VIF (7501's "private VIF" is read that way) | Same review |
| The collection's namespace and name are `network.evpn_gateway` (7499 names `redhat.evpn_migration`); the collection's issue tracker is to move to a Jira project not yet chosen, recorded in its README | Review comments on pull request #3, 2026-10-02 (`jcaamano`) |
| Source CI runs as Prow tests that call scripts or Make targets, with no test logic in the test definition; GitHub Actions is not assumed | Review comment on pull request #3, 2026-10-02 (`jcaamano`) |
| 7504's VNI/MAC views and 7505's "approved upstream" images follow decision 10 | Same review |
| The emulated CORENET-7508 integration lane is containerlab + a test execution environment running the collection's `deploy.yml` + pytest/testinfra/vtysh JSON, behind a runner-agnostic `test/e2e/run.sh` (kind/real OVN-K reserved for later OCP interop lanes); distinct from the still-open AWS/lab test backend (decision 11) | `test/e2e/` lane in the CORENET-7508 PR; **accountable decision owner and date pending — TODO confirm** |

The review spoke for the Networking maintainers ("we") and named no decision owner. Decision 10's
listed owners are Networking, PM and Product Security; PM and Product Security confirmation is not
recorded. The review left the proposed responsibilities for a later look and assigned an action
item for decisions 7, 8 and 13 to `@knobunc`.

## Open decisions, by the first gate they block

### Start now, without waiting for engineering

- **Jira conflicts (review direction 2026-10-01; owner and Jira correction pending).** The review
  proposed resolutions for the three criteria. A Direct Connect gateway attached to a TGW
  needs a transit VIF, so 7501's "private VIF and TGW associations" is read as a transit VIF.
  7505's "approved upstream" images and 7504's
  VNI/MAC views follow decision 10: the Red Hat–built `frr-rhel9` image and an `frr-metrics` that
  gains EVPN metrics ([coverage](pipeline-spec.md#metrics-corenet-74997504)). The Jira criteria
  still carry the old wording and have no comments (checked 2026-10-01), so correcting them
  remains an action. *Owner: PM / Networking.*
- **Product name.** "EVPN Gateway Appliance (EGA)" is a working name. The prototype's
  [L2-stretch plan](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af8/docs/evpn-l2-stretch-plan.md)
  weighed "Connectivity", "Gateway", "Bridge" and "Edge", noted that "Gateway" suggests L3 routing,
  and recommended "EVPN Connectivity Appliance"; the repository name and `OWNERS` component use
  "Gateway". Approval of the official name is the first long-lead step below. *Owner: PM / Product
  Security.*
- **Long lead.** Confirm the product home and existing onboarding coverage, then start
  applicable name, readiness, export, privacy, ProdSec/RH-SDL and product-identity requests
  alongside engineering. Reuse approvals owned by an existing offering; request inputs and
  release obligations follow the [productization path](productization.md). The BGP Cloud
  Connector operator template fits only in part; its measured 47 days from new repository
  (July 30) to first advisory (September 15) is a precedent, not an EGA schedule. *Owner:
  PM / Product Security / releng.*

### Gate A — source CI

- **Public import.** A reviewed snapshot without the internal history, with the [import
  blockers](source-audit.md#0-public-import) removed; owners for the remaining source defects and
  versioned validation rules (CI can report debt while fixes proceed). *Owner: Source owners /
  releng.*
- **Source CI.** Prow onboarding in `openshift/release` (its
  [#86165](https://github.com/openshift/release/pull/86165) merged 2026-10-06 with OWNERS, a tide query,
  plugins and a ci-operator config whose `verify` runs `make verify OFFLINE=1`; the
  October 13 [runner switch](ci-source.md#where-things-stand) selects PR-built
  `Dockerfile.ci` and adds required image-build status; the [source-CI queue](ci-source.md#queue) adds standard linters on
  [maintained tools](ci-bootstrap-spec.md#use-maintained-tools-keep-custom-checks-small), one
  complete feature per PR); making Konflux contexts block even before they appear, and whether Konflux
  nudge PRs merge automatically or by owned review ([merge
  policy](ci-bootstrap-spec.md#konflux-implementation-checks)). GitHub Actions is off by default in
  the `openshift` org and enabled per repository at the owner's request (a June 2026 PCO-1330
  comment, not yet formally announced); `openshift` peers' workflow files have no runs, so make Prow
  the required gate ([peer evidence](ci-bootstrap-spec.md#findings-that-change-the-design)); request it for hosted KVM lanes or `release_ah.yaml`.
  Installing the Konflux GitHub App on an `openshift` repository takes a DPP ticket (CORENET-7409).
  *Owner: Engineering / Networking.*
- **Collection.** *Owner: Architecture / AAP content.*
  - **Name.** Directed 2026-10-02 in review of pull request #3: namespace `network`, name
    `evpn_gateway`; the org's validated collection, `network.offline_migration_sdn_to_ovnk`, uses the
    same namespace (7499 still names `redhat.evpn_migration`, so the Jira text needs correcting; the merged
    `galaxy.yml` uses `network.evpn_gateway`). The product name still awaits approval, and customers' playbooks depend on the
    collection name, so confirm the namespace with AAP content before first publication; public
    Galaxy lists no collections under `redhat` (queried 2026-09-29).
  - **Shape.** Shipped role list and collection API, with roles and 7509's RBAC split by operator:
    the design is being revised because the VPC, gateway configuration and gateway VM may have
    different administrators, and managed services cannot deploy VMs in customer networks
    (HPSTRAT-714, September 16). CORENET-7515 now requires a production/emulation split;
    confirm whether that needs separate collection artifacts. It does not by itself require
    separate repositories.
  - **Content class.** Review lab-only exclusions at import. Set destination-required content
    class/importer profile and supported
    ansible-core/AAP EE matrix. Certified content cannot use `community.aws`, which alone has the
    Direct Connect modules and `ec2_customer_gateway`. Terraform stays lab scaffolding.
  - **Scope.** Decide whether the collection manages OCP EVPN resources before implementing
    that feature. Its behavioral tests then need a cluster and suitable dependencies;
    static collection lint/build checks remain independent of cluster availability.
  - **Layout.** Keep the merged `ansible/` layout for source CI unless source owners identify
    a separate repository need. One optional publisher's root-only `release_ah.yaml` behavior
    does not justify a repository split before the destination/publisher is chosen. Native
    `ansible-galaxy` already builds from the subdirectory; later publication can consume that
    artifact. A separate repository, if selected, adds an explicit collection revision to tests.
- **Architecture.** CNV-95804's GCP spike prefers an OpenPERouter VNF to Ansible-templated FRR for
  the on-prem role; OpenPERouter is already built in Konflux (`telco-5g-tenant`) and has a
  Technology Preview epic (CNV-95115). Azure/GCP are out of scope here, so do not block AWS on a
  unified design; keep AWS-specific roles, tests and publication separable. The cluster-side design
  also has a history to reconcile: HPSTRAT-714's July 24 update recorded design v2.1, which
  recommended productizing OpenPERouter instead of running FRR on worker nodes and demoted
  OCP-native EVPN to an on-prem-only alternative, while CORENET-7498 (created September 8) plans on
  OCP-native EVPN and the September 2 and 16 updates say the design is being revised. Confirm which
  design is current before building cluster-side test lanes or deciding the collection's OCP scope.
  This question does not block existing-source lint, packaging or a bootc build.
  *Owner: Architecture / Networking / PM.*

### Gate B — non-releasing Konflux builds

- **Product home.** Separate offering in a team tenant (this plan's assumption, as BGP Cloud
  Connector did), an addition to an existing networking offering such as BGP Cloud Connector
  (reusing its tenant, Engineering ID, CPE and stream), or content shipped under OpenShift and built
  by ART, as MicroShift's bootc image is. This selects the build owner, registry namespace, CPE and
  advisory stream. *Owner: PM / Engineering / ART.*
- **Konflux cluster.** A public `openshift` repository in a team tenant builds on a public cluster;
  new public tenants go to `kflux-prd-rh02`, where BGP Cloud Connector's tenant is. Public clusters
  cannot reach Red Hat–internal services or labs, so internal-lab qualification such as CNV's NSX
  lab runs outside Konflux ITSs. Every disk-CDN and Marketplace RPA in cached KRD runs on private
  `stone-prod-p02`; have releng confirm those managed pipelines for a `kflux-prd-rh02` tenant before
  relying on them ([channel check](bib-configuration-spec.md#customer-delivery-channels)). Under the
  ART home the image would build from its `openshift-priv` mirror on ART's `kflux-ocp-p01`. *Owner:
  Engineering / Konflux platform / releng.*
- **Build canary.** Tenant, Application (or approved ComponentGroup model), names, RBAC and quota;
  source and build-registry visibility. Single-use rootful MPC capacity for disks and a scoped
  `privileged_nested_param` exception for the bootc build, which most bootc products in KRD carry
  ([precedents](containerfile-refactor-spec.md#required-outcomes)). `kflux-prd-rh02` defines dynamic
  rootful MPC hosts. *Owner: Engineering / Konflux platform.*
- **Payload.** The 2026-10-01 review directs FRR and `frr-metrics` to [option
  A](pipeline-spec.md#runtime-payload-corenet-7505), the Red Hat–built `frr-rhel9` image
  (2026-10-01). #16 (2026-10-15) implements option A with the OCP 4.22 image as bound
  containers; #6, now on hold, proposed option B for RHEL 10. Record owner/date approval
  before treating either payload as finalized. `openshift4/frr-rhel9` is published;
  `openshift5/frr-rhel9`, which the 5.1 target needs, was not in Pyxis on 2026-10-01. Still open:
  node-exporter's source; the approved RHEL bootc base stream (latest minor or EUS; generic or
  RHEL 10 platform base), BIB and payload inventory; support terms for OCP content used outside a
  cluster; package access in both build stages (activation key for entitled RPMs) plus a tenant
  [`registry.redhat.io` pull
  secret](https://konflux-ci.dev/docs/building/secrets/creating-registry-pull-secrets/) for the
  bootc base, BIB and the OCP images; launch access and runtime registry-egress contract.
  *Owner: Networking / PM / Product Security.*
- **Tests.** Test backend, AWS identity at each execution site (an owned OpenShift CI cluster
  profile for AWS lanes; Konflux federation for ITSs), VM Import role/PassRole and bucket access,
  private candidate pulls, qcow2 capacity, resource ledger/reaper and evidence retention. A funded
  owner for the test AWS accounts, the DX hosted connection, bare-metal/nested-virt instances and
  any vSphere lab time. *Owner: QE / AWS / releng / management.*

### Gate C-stage — trial publication

- **Artifact set.** 7506/7522 require qcow2 and an AMI. The design places the on-prem appliance on
  VMware/NSX segments, which adds vmdk/ova if vSphere is supported; it does not replace qcow2 unless
  the Jira changes. The task breakdown (§7.3.3) also names bare metal, which would add an installer
  artifact (`build-vm-image` 0.3.2 accepts `anaconda-iso`, `bootc-installer`, `iso` and
  `pxe-tar-xz`). RHEL kernels refuse WireGuard and TCP-MD5 in FIPS mode. Options include
  WireGuard tests in non-FIPS development environments, IPsec-only labs or a separate FIPS
  variant; a separately shipped variant needs approval.
  Settle supported FIPS-mode BGP authentication ([contract](containerfile-refactor-spec.md#required-outcomes)). *Owner: PM /
  Architecture.*
- **AMI channel.** *Owner: PM / cloud publishing / releng.*
  - **The gap.** 7506/7522 require an AMI "through an approved AWS workflow"; its source (task
    breakdown §3.2.3, "via VMImport or EC2 Image Builder") describes building one, not a customer
    channel. Details: [customer channels](bib-configuration-spec.md#customer-delivery-channels).
  - **Candidates, none approved.**
    - A **customer-built AMI**: RHEL's documented `bootc-image-builder --type ami` run against the
      registry image lands the AMI in the customer's own account (a privileged host, an S3 bucket
      and the `vmimport` role; no Red Hat AMI channel, but a different support contract).
    - A **Marketplace listing**, the only channel Konflux wires (`push-disk-images-to-marketplaces`;
      all 17 KRD RPAs are RHEL AI or xKS listings, and `cloudMarketplacesPrePush` gives private AMIs
      for stage before listing IDs exist).
    - **CDN download of the raw disk** for customers to import, which RHEL accepted for its AWS CVM
      Tech Preview image with the AMI deferred to GA (RHELDST-37290, RHELOPC-1651).
    - **Community AMIs**, which pubtools implements but no Konflux task calls (KONFLUX-9757, New).
  - **To decide.** The channel, who pays for the appliance's RHEL entitlement in customer accounts,
    and whether a Tech Preview may ship as a download only.
- **Publication.** Stage registry/CDN/AMI/collection destinations and metadata; stage ECP/RPA/RP
  with supported catalog refs, customer readback and retry/tag-restoration rehearsal. How the
  collection resolves the released AMI and bootc reference: publish the collection last with an ID
  map, or resolve by release identity at run time. Stage `rh-advisories` already needs the
  Engineering ID and a Pyxis delivery repository, which reaches stage through a daily sync. Disk
  downloads first need a content set and Pulp repository, an empty RPM repository for download
  visibility and Content Gateway product data, each requested from other teams ([internal
  guide](https://gitlab.cee.redhat.com/konflux/docs/users/-/blob/1105e2e/modules/releasing/pages/releasing-disk-images-to-cdn.adoc)).
  *Owner: Releng / channel owners / Architecture.*
- **Collection.** Public Galaxy, hosted Hub certified/validated content, or private Automation Hub;
  approved support contract, namespace, importer/signing and publisher boundary. The org's
  SDN-migration collection ships on Automation Hub as validated
  `network.offline_migration_sdn_to_ovnk`. Proposed hosted-Hub option, if Actions is enabled:
  GitHub release → pinned `release_ah.yaml` with a Hub service account, as `hashicorp.vault`
  does. Destination and publisher remain decision 15, not an approved default; a trusted
  native publisher or AAP's Zuul path can meet the same contract. Prove the selected path
  with trial credentials on an isolated server first. *Owner: PM / AAP content / releng.*
- **Observability.** Direction set 2026-10-01: `frr-metrics` is to be fixed to run without a
  Kubernetes cluster and to include EVPN metrics, so BGP/BFD series and the VNI/MAC views share one
  source. Open: who makes the change and where it lands (upstream frr-k8s, `openshift/frr` or a
  maintained patch of the OCP build), which EVPN series it adds (VNI and MAC learning, VTEP and DF
  alerts), what the appliance runs until it ships (options: the 4.22 binary, an auth-optional
  build, or node-exporter textfile series from `vtysh`/`bridge fdb`), since OCP 4.23 and 5.x builds exit outside
  Kubernetes ([standalone operation](pipeline-spec.md#metrics-corenet-74997504)), and CloudWatch
  for DX/VPN panels. *Owner: Networking / 7504 owner.*

### Gate C-prod — supported release

- **Identity.** Product version, Engineering ID and channel-specific product IDs, CPE, registry
  paths, Pulp repository/customer-download metadata, release/advisory content and clearance;
  approved security update stream and demonstrated SBOM ingestion. Concretely: a ProdSec
  product-definitions entry, KRD's `prodsec/<tenant>.yaml` template
  ([example](examples/release/bgp-cc-prodsec-template.yaml)) and a Cicada repository definition in
  pyxis-repo-configs. The Engineering ID is the exception to this gate: stage `rh-advisories`
  already needs it ([Publication](#gate-c-stage--trial-publication)), and BGP Cloud Connector's took
  12 days from request to assignment ([measured
  path](productization.md#measured-path-bgp-cloud-connector)). *Owner: PM / Product Security /
  releng.*
- **Support.** CORENET-7523 matrix: OCP versions (5.1 target with 4.22 backports per
  PERFSCALE-5814), AWS regions, FRR version, transports and their bandwidth limits, architecture,
  topology/HA and scale. Published 4.22 EVPN and BGP support is bare-metal only, so AWS needs an
  explicit support decision. The parent outcome HPSTRAT-714 names ROSA, so decide whether ROSA HCP
  is in the matrix. L2 versus the parent feature's L2+L3 requirement. *Owner: PM / Architecture /
  QE.*
- **Qualification.** Approved source/test revisions and vulnerability-assessment freshness; OCP VTEP
  addressing on AWS; transport/MTU and HA capacity; automatic rollback including lost host access;
  supported OCP update paths with external EVPN; dashboards/docs and security/performance
  acceptance. *Owner: Networking / QE / Product Security / docs.*

Gate A does not need final product IDs, Marketplace listings or a completed HA
implementation. Stage publication needs its own release configuration before it
can be tested. Production requires the complete supported-release evidence.
