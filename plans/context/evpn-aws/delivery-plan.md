# EVPN Gateway Appliance (EGA) — release engineering delivery plan

Requirements baseline rechecked: 2026-10-13; collection-CI scope refreshed 2026-10-16.
[`pipeline-spec.md`](pipeline-spec.md) is the canonical plan; this is the proposed work
breakdown. See [context](context.md#stories) for current story statuses. Ownership below is proposed.

| Story | Next proof |
| --- | --- |
| [CORENET-7499](https://redhat.atlassian.net/browse/CORENET-7499) — collection MVP | Real-trunk and VMware port-security validation; idempotent teardown; transport gating; MTU modes, TCP MSS clamping and DF-bit enforcement; `frr-metrics` in place of `frr_exporter` (review direction 2026-10-01: fix it to need no cluster and to [export EVPN metrics](pipeline-spec.md#metrics-corenet-74997504); the change has no owner yet); collection packaging (`network.evpn_gateway`, [review direction 2026-10-02](kickoff-decisions.md#already-settled); Jira still names `redhat.evpn_migration` and needs correction) and its interim internal Automation Hub publication; validated-content candidacy is [CORENET-7705](https://redhat.atlassian.net/browse/CORENET-7705), not a 7499 criterion: [plan](ansible-validated-content-plan.md) |
| [CORENET-7500](https://redhat.atlassian.net/browse/CORENET-7500)–[7503](https://redhat.atlassian.net/browse/CORENET-7503) — transports and HA | Site-to-Site VPN transport (7500, no description yet; task breakdown §2.1 puts Libreswan on the appliance), transport preflight (7501, as a transit VIF per the 2026-10-01 review), all-active multihoming (7502) and relay HA (7503) |
| [CORENET-7504](https://redhat.atlassian.net/browse/CORENET-7504) — observability | Dashboards and alerts as versioned source. BGP/BFD series come from `frr-metrics`; VNI/MAC views follow from the EVPN metrics to be added to `frr-metrics` (review direction 2026-10-01, owner/approval pending; which series, and the VTEP/DF alerts, are [open](pipeline-spec.md#metrics-corenet-74997504)); DX/VPN panels need CloudWatch |
| [CORENET-7505](https://redhat.atlassian.net/browse/CORENET-7505) — component images | Digest-pinned native build inputs and resolved payload evidence from Red Hat content: the `frr-rhel9` image for FRR and `frr-metrics` ([option A](pipeline-spec.md#runtime-payload-corenet-7505), review direction 2026-10-01, owner/approval pending), with node-exporter, the RHEL base and package access still open and the Jira's "approved upstream" wording still to be updated; update ownership for bases, BIB, payloads and runtime pulls |
| [CORENET-7506](https://redhat.atlassian.net/browse/CORENET-7506) — appliance CI | Non-releasing bootc canary; qcow2 and raw derivatives by digest nudge (plus vmdk/ova if vSphere is supported); substantive SBOM/provenance and platform metadata; the raw disk imported and booted as an AMI in AWS; CI → stage → production promotion gates |
| [CORENET-7507](https://redhat.atlassian.net/browse/CORENET-7507) / [7667](https://redhat.atlassian.net/browse/CORENET-7667) — collection CI | 7507 Closed with ansible-lint/yamllint complete (rechecked 2026-10-16). 7667: Molecule for every shipped role; native argument/preflight validation of VNI/ASN/transport with runtime negative cases; build and clean install of the tarball; tested `MANIFEST.json` digest carried to the approved Hub/Galaxy publication |
| [CORENET-7508](https://redhat.atlassian.net/browse/CORENET-7508) — integration CI | Emulated appliance + relay + workload topology in CI (containerlab fabric from the appliance image, configured by the collection's `deploy.yml` in a test EE, validated by its health check; runner-agnostic `test/e2e/run.sh`). Shipped: three-AS eBGP Established, Type-2/3 exchange, bidirectional L2. Deferred: VNI isolation (xfail pending an isolation-model decision), internet-mode MTU/MSS (7514), frr_exporter/metrics (7504). Remaining: explicit pytest/testinfra assertions and the openshift/release job wiring; failures and skips visible as failures |
| [CORENET-7509](https://redhat.atlassian.net/browse/CORENET-7509) — AAP templates | Deploy, add-stretch, health-check and upgrade templates; validated surveys; webhook GitOps; RBAC; production approval; applied as code to a disposable AAP |
| [CORENET-7510](https://redhat.atlassian.net/browse/CORENET-7510) — upgrade/rollback | Pre/post health checks, serial HA peer upgrades, automatic rollback after failed validation, BGP recovery after reboot, prior image restored |
| [CORENET-7511](https://redhat.atlassian.net/browse/CORENET-7511) — hardening | Supported BGP authentication (FIPS-compatible), automated SSH key rotation, FIPS mode on image-mode RHEL, access restricted to required peers, bridge exposure review |
| [CORENET-7512](https://redhat.atlassian.net/browse/CORENET-7512)–[7520](https://redhat.atlassian.net/browse/CORENET-7520) — QE validation | frr-k8s relay peering (7512), multiple VNIs and day-2 stretch (7513), internet-mode MTU/MSS (7514), standalone VTEP retirement and production/test collection separation (7515; started — on-prem sim extracted to `network.evpn_gateway_test`), end-to-end L2 (7516), multi-AS eBGP (7517), MAC mobility (7518), failure recovery and scale (7519), each transport (7520) |
| [CORENET-7521](https://redhat.atlassian.net/browse/CORENET-7521) — documentation | DX, VPN and development-only WireGuard modes; operations, upgrade, rollback, troubleshooting and migration runbooks; DX qualification and internet-mode limits; HA deployment |
| [CORENET-7522](https://redhat.atlassian.net/browse/CORENET-7522) — publication | The exact tested set: collection pinned to its qualified appliance release, qcow2 and AMI, component containers through an existing Red Hat distribution, dashboards and alerts, documentation. Stage before production, customer readback, ledger for partial publication. Released tags and signatures cannot be fully withdrawn |
| [CORENET-7523](https://redhat.atlassian.net/browse/CORENET-7523) — support matrix | Supported OCP, AWS region, FRR and transport combinations; WireGuard and reduced-MTU limits; supported on-prem environments; bandwidth and operational limits per transport |
| [CORENET-7524](https://redhat.atlassian.net/browse/CORENET-7524) — reviews | Appliance and Ansible security review; throughput, latency and convergence baselines; release notes with support boundaries and limitations |

Proposed responsibilities: Networking owns behavior/topology, QE owns qualification,
and Product owns scope and support. Confirm their dependencies and owners;
production qualification proceeds alongside the CI/CD implementation.

## Next mergeable work

Numbers in "Needs decisions" refer to the [decision index](kickoff-decisions.md#decisions-at-a-glance);
"Gate" and "Done when" follow the [pipeline plan's sequence](pipeline-spec.md#sequence-only-block-work-on-inputs-it-needs).
Stable row IDs are retained; source checks on merged inputs can land before product import.

| # | Change and where | Done when | Needs decisions | Gate |
| --- | --- | --- | --- | --- |
| 2 | **Source CI.** Standard lint for maintained source, then native product checks as reviewed inputs arrive; the [source-CI queue](ci-source.md#queue) owns status and priorities | The selected check meets its [verification](ci-source.md#how-to-add-a-check) and preserves useful existing coverage | 4; 5 for product scope | A |
| 1 | **Public import.** Import a reviewed snapshot of the prototype into `openshift/evpn-gateway-appliance` ([import blockers](source-audit.md#0-public-import)); close the remaining unsafe-input and packaging defects with their source owners; retain the reviewed collection layout unless an independent source ownership need justifies a split | The [current import scan](source-audit.md#0-public-import) and manual review pass, including RFC 1918 lab-address review; do not wait for a scanner replacement ([deferred](ci-source.md#deferred)); the source commit is recorded; each defect has a fixer or a tracked exception | 3, 5 | A |
| 3 | **Tenant and bootc canary.** Settle the product home and payload (FRR/`frr-metrics` have a review direction pending owner/approval; node-exporter, base and package access remain open); obtain the tenant on the public cluster, the Konflux GitHub App (DPP ticket), package access and MPC capacity; onboard one non-releasing bootc Component | A bootc build with provenance and an SBOM from the reviewed source | 7, 8, 9, 10 | B |
| 4 | **Disk Components.** Add the qcow2 and raw Components after the source digest and BIB files exist | Index and SBOM wiring proven, a digest nudge cycle completed, each disk boots and meets the target policy | 9, 10 (12 for formats beyond qcow2 and raw) | B |
| 5 | **Candidate tests.** Add required candidate-consistency and boot/lifecycle tests, including the raw-to-AMI boot, in `push`-context ITSs with owned AWS identity (Konflux OIDC federation; an owned OpenShift CI cluster profile for Prow lanes); adapt the chosen backend to complete push and manual Snapshots | Tests block on the complete candidate; cleanup and retained test evidence proven | 11 | B, then C-stage |
| 6 | **Productization, in parallel from the start.** Product-name approval, the Engineering ID, ProdSec registration and export compliance ([productization path](productization.md)); settle the AMI channel; obtain stage channel data, including disk-CDN repository requests, and create the matching stage release objects | Ordered stage publication, customer consumption and retry recovery proven | 2, 13, 14, 17 | C-stage |

Native dependency-update extraction (L2) accompanies tool maintenance when useful;
it does not delay product suites. Bot activation remains owner-authorized work. Role validation/behavior (L5) and native
image-build proof (L6) come before destination certification and scheduled link work ([later priorities](ci-bootstrap-spec.md#later-sequence)).
They need reviewed source, approved inputs and qualified runners. A local build can precede
the tenant work in row 3; it does not replace that row's Konflux provenance/SBOM canary.

## Deliverables

In the product repository: one generic bootc Containerfile, one BIB wrapper per
disk format (qcow2 and raw first) plus explicit TOML customization, pinned PR/push
pipelines and source CI, collection packaging and QE test interfaces. Add dependency
update configuration when selected. An EE, platform overlays and separate exporter images need
a specific product requirement before becoming Components.

In `konflux-release-data`: tenant/RBAC, Application or approved migrated model,
one Component/ImageRepository pair each for bootc, qcow2, raw and any approved
vSphere format (a collection carrier only if the collection must be in the
Snapshot); nudges, required ITSs, and channel ReleasePlans. Managed configuration
is a separate change: approved product data, the ProdSec template, justified ECPs,
stage/prod RPAs and their releng-approved constraint file. A tenant-only collection
release pipeline need not have an RPA. Follow the [KRD mechanics](#krd-mechanics) below.

In `openshift/release`: the repository's Prow configuration and CI jobs.

Use [`kickoff-decisions.md`](kickoff-decisions.md) for missing inputs,
[`prior-art.md`](prior-art.md) for concrete files and [`examples/`](examples/README.md)
for real YAML. Never copy another product's IDs, secret paths, task digests or
policy exclusions as EVPN defaults.

The [pipeline completion checklist](pipeline-spec.md#completion) proposes evidence for the Jira
acceptance criteria; it does not add requirements or settle open decisions.

## KRD mechanics

Checked against KRD `8c18efee29` (its `AGENTS.md`, `tests/` and `tenants-config/` scripts).
`konflux-release-data` holds two workflows that must not share a merge request:

| Workflow | Paths | Rules |
| --- | --- | --- |
| Managed release configuration | `config/<cluster>/product/{ReleasePlanAdmission,EnterpriseContractPolicy}/`, `constraints/product/<team>.yaml`, `prodsec/<tenant>.yaml`, `exceptions/` | Applied to the releng-owned managed namespace when merged; validate with `tox` (`tox -e test`) |
| Tenant infrastructure | `tenants-config/cluster/<cluster>/tenants/<tenant>/` (Applications, Components, ImageRepositories, ITSs, ReleasePlans) | Kustomize: edit `cluster/`, never `auto-generated/`; add new files to `kustomization.yaml`, run `tenants-config/build-manifests.sh`, commit both source and generated output; validate with `tox -e tenants-config-test`; ArgoCD reconciles after merge. `tenants-config/add-namespace.sh` creates a tenant |

Easy to miss:

- **Every RPA needs a constraint file.** `constraints/product/<directory>.yaml` is a JSON
  schema bounding what that team's RPAs may say: `origin`, allowed policies, registry URL
  patterns, product name and version, the release pipeline's URL, revision and path, service
  accounts and signing configuration. The tests fail an RPA whose directory has no constraint.
  Releng owns constraints (a team cannot approve changes to its own), while a team can
  self-approve RPAs inside them through a CODEOWNERS entry. Anything outside the schema, such as
  the disk-CDN or Marketplace pipeline path or a feature-branch revision (xKS's constraint
  allows `release2758`), is therefore a releng-approved constraint change; ask for it early.
- **CODEOWNERS.** Add an entry for the team's RPA directory
  (`/config/<cluster>/product/ReleasePlanAdmission/<team>/`) so it can update RPAs without
  releng, and entries for both the source and `auto-generated/` tenant paths.
  `tox -e codeowners-lint-fix` repairs ordering.
- **Cluster.** New tenants are refused on `stone-prd-rh01` and `kflux-prd-rh03`;
  `tenants-config/verify-onboarding-allowed.sh` names `kflux-prd-rh02` as the alternative,
  which agrees with the [cluster decision](kickoff-decisions.md).
- **Workflow.** Push branches to the GitLab project; do not fork, because CI needs secrets a
  fork cannot read.
- **Operations runbooks.** Konflux releng's SOPs
  ([`releng/`](https://gitlab.cee.redhat.com/konflux/docs/sop/-/tree/f4f0e13/releng), `f4f0e13`)
  cover what release owners will need: rollback and tag removal (cited in the
  [pipeline plan](pipeline-spec.md#publication)), invalid-signature repair (a Pyxis admin deletes the
  bad signatures and a re-release re-signs them; the list must include architecture-specific,
  index and source-container digests), Engineering ID creation, and holding stage releases
  during a signing-service overload by setting `release.appstudio.openshift.io/block-releases: "true"`
  on stage RPAs. A stalled stage release may therefore be a platform hold, not an EVPN
  configuration fault.
- **KRD's own agent guidance.** Follow its `AGENTS.md`, `.claude/commands/create-rpa.md`
  (RPAs that use the `rh-advisories` pipeline, which fits the bootc image),
  `.claude/commands/recommend-cluster.md` and `.cursor/rules/onboarding.mdc` (other pipeline
  types), including its rule to never guess team, cluster, registry or pipeline values. Take
  them from [decisions](kickoff-decisions.md) or merged files.
