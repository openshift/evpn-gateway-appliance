# EVPN Gateway Appliance (EGA)

EVPN Gateway Appliance (EGA) enables the use of EVPN with OpenShift in public clouds.

This directory is the CI/CD, release-engineering and delivery plan for EGA: how the
appliance image, its disk images and AMI, and the Ansible collection are built, tested,
published and supported. It is not the product design (the prototype's own `docs/` hold
that; [#17](https://github.com/openshift/evpn-gateway-appliance/pull/17) proposes importing its
design document) and it makes no support promise.

**Status: proposed delivery design.** The Networking maintainers reviewed the artifact graph
on 2026-10-01 and recorded a payload direction; accountable decision owners, release responsibilities
and support remain open
([decisions](kickoff-decisions.md#already-settled), [source confidence](source-evidence.md#scope-and-confidence)).

Source CI, rechecked 2026-10-16: Prow's `verify` runs planning, public-safety, YAML,
Markdown and Ansible collection checks in the PR-built `Dockerfile.ci` image
([current state](ci-source.md#where-things-stand)). Markdown lint
[#15](https://github.com/openshift/evpn-gateway-appliance/pull/15) has merged; the
[source-CI queue](ci-source.md#queue) tracks the open Ruff, ShellCheck and Hadolint PRs.

These documents define implementation work and acceptance evidence; they do not establish
product support, assigned ownership or a completed release.

Links between documents are relative, and source references identify repositories, revisions
and paths. Internal Jira, GitLab and private GitHub links need Red Hat access; the finding each
supports is summarized in the text.

The proposal in brief:

- Add source CI to the current planning tree with OpenShift CI (Prow) as the merge gate, one
  complete feature per pull request, with atomic commits ([source CI](ci-source.md)). In parallel, bring a reviewed copy
  of the internal prototype into the public
  [`openshift/evpn-gateway-appliance`](https://github.com/openshift/evpn-gateway-appliance)
  repository (DPP-22292), now arriving in pieces (the collection has merged and its checks run in
  `verify`; the image sources are an open pull request). GitHub Actions is
  optional and off by default in the organization.
- Build one RHEL bootc image in Konflux and derive the qcow2 and raw/AMI artifacts
  that CORENET-7506/7522 require from its digest. Replace the prototype's community
  FRR and exporter images with Red Hat builds: FRR and `frr-metrics` come from OCP's
  `frr-rhel9` image (review direction 2026-10-01, owner/approval pending; node-exporter's
  source is open), which also rewrites CORENET-7505's "approved upstream" wording.
- Publish the Ansible collection to the approved Hub or Galaxy destination, bound
  to the tested set by its verified content and `MANIFEST.json` digest
  ([native integrity contract](ci-bootstrap-spec.md#collection-content-integrity)). Destination and publisher remain
  [decision 15](kickoff-decisions.md) inputs; the reusable Hub workflow is an option
  when the owner enables Actions, not a prerequisite for collection CI.
- Gate release on required Konflux tests of a complete candidate Snapshot, then
  publish that exact set per channel, stage first, with customer readback.
- Start long-lead productization now, adapting BGP Cloud Connector's completed
  operator template (CORENET-7400) as the [productization path](productization.md)
  shows.

Work starts with the public import, source CI and non-releasing builds; production
requires the agreed support matrix and qualification evidence.

## Start here

| Document | Purpose |
| --- | --- |
| [Delivery plan](delivery-plan.md) | CI/CD work breakdown and next mergeable changes |
| [Source CI](ci-source.md) | What the `verify` gate runs, how to add a check, and the next checks |
| [Pipeline plan](pipeline-spec.md) | Proposed artifact graph, gate sequence and release evidence |
| [Decisions](kickoff-decisions.md) | A one-table index of the 19 decisions and their status, then details organized by the first gate they block |
| [Productization](productization.md) | Approvals, Engineering ID and ProdSec steps with measured lead times |
| [Project context](context.md) | Scope, a map of the prototype, Jira requirements and repository map |
| [Agent guide](agent-guide.md) | Rules, verified facts and a task-to-document reading map for coding agents |
| [Examples](examples/README.md) | Real Konflux YAML with provenance, and what not to copy |

Short on time: read this page, the [decision index](kickoff-decisions.md#decisions-at-a-glance)
and the [delivery plan](delivery-plan.md), then open the rest by task through the
[agent guide's reading map](agent-guide.md#which-part-to-read-for-which-task).

Still to confirm: the proposed responsibilities, the product home (team tenant or ART), the
public Konflux cluster it implies and the AMI channel (decisions 7, 8 and 13, assigned as an
action item on 2026-10-01; see the [decision
index](kickoff-decisions.md#decisions-at-a-glance)). Decision 10 records a review direction for FRR
and `frr-metrics`; its accountable owner and remaining approvals are open. Channel owners, Product and QE can resolve stage/production decisions in
parallel. Record accepted decisions in the decision list.

## Implementation contracts

| Document | Purpose |
| --- | --- |
| [CI bootstrap](ci-bootstrap-spec.md) | The contract for CI beyond the first steps: collection publication, test adapters and Konflux onboarding checks |
| [Containerfile](containerfile-refactor-spec.md) | Bootc inputs, source delivery, filesystem and runtime lifecycle |
| [BIB and delivery](bib-configuration-spec.md) | Disk task wiring, AWS tests and customer publication |
| [Source findings](source-audit.md) | Public-import blockers and open defects at the inspected prototype revision |
| [Ansible validated content](ansible-validated-content-plan.md) | Checklist gaps for the `network.evpn_gateway` validated-content candidacy and the fixes |
| [Networking handoff](networking-spec.md) | Source gaps and interfaces to networking/QE qualification |

[Prior art](prior-art.md) identifies reusable code and its limits;
[source evidence](source-evidence.md) records checked revisions and the reasons
for the plan's key decisions. The [EVPN primer](evpn-primer.md) is background.

## CI/CD terms used here

| Term | Meaning in this plan |
| --- | --- |
| Component / Snapshot | A buildable artifact / the selected set of Component image references |
| ITS | IntegrationTestScenario: selects and runs tests for Snapshots |
| PaC / nudge | Pipelines as Code / an automated dependency-update PR |
| RP / RPA | Tenant ReleasePlan / managed ReleasePlanAdmission |
| ECP / Conforma | EnterpriseContractPolicy / its verification tooling |
| KRD | `konflux-release-data`, the GitOps repository for tenants and release objects |
| BIB / MPC | Bootc Image Builder / Multi-Platform Controller for remote build capacity |
| OTE | OpenShift Tests Extension, the binary that carries OVN-K's OpenShift e2e suites |
| EE | Ansible Execution Environment |
| GCL | Global Candidate List: integration-service's per-Application record of each Component's latest successful build, which automatic Snapshots draw from |
| CEL | Common Expression Language, used in Pipelines-as-Code annotations to choose which events and changed paths trigger a build |
| MintMaker / Hermeto | Konflux's Renovate-based dependency updater / its prefetcher for hermetic builds |
| MAPT / tmt / Testing Farm | Multi Architecture Provisioning Tool (cloud VMs for tests) / Test Management Tool / the Red Hat service that runs tmt plans |
| ART | OpenShift's Automated Release Tooling team, which builds OCP images from `ocp-build-data` |
| CNO | OpenShift Cluster Network Operator |
| Pyxis / Cicada / Pulp / CGW | Red Hat's content metadata catalog / configuration-as-code for delivery repositories (`pyxis-repo-configs`) / the repository service behind disk downloads / Content Gateway, the customer download pages |
| StArMap / Bombino | The per-component mapping of images to marketplace listings, regions and accounts (`starmap:` in an RPA) / the SBOM ingestion endpoint that image repositories notify on push |
| TGW / DX / VIF | AWS Transit Gateway / Direct Connect / a Direct Connect virtual interface (private, transit or public) |
| ESI / DF | EVPN Ethernet Segment Identifier (multihoming) / the designated forwarder that sends BUM traffic for a segment |
| CUDN | ClusterUserDefinedNetwork; more EVPN terms are in the [primer](evpn-primer.md) |
| EUS / RHSM | RHEL Extended Update Support streams (for example `rhel9-eus`) / Red Hat Subscription Manager entitlements for RPM access |

## Maintaining the plan

Keep proposals tied to Jira criteria or defects in maintained source. Prefer standard
tools; document the invariant and maintenance owner when custom code is needed.
Keep the work queue in [source CI](ci-source.md#queue), details in
the relevant section, and source measurements beside the claim they support. Remove
stale instructions and duplicate history; preserve cited headings and decision numbers.

Update the pipeline plan and its focused contract together. Record a decision's
owner, date and evidence in the decisions document when it is agreed; role names
are proposed responsibilities until accepted. Jira acceptance criteria are the
requirements; where they conflict with product or AWS facts, the plan names the
conflict and its owner rather than silently choosing. Cite the exact source
revision for implementation behavior, and distinguish merged code, deployed
capability and successful product qualification.

Keep raw issue exports, customer/support material, credentials and private lab
inventories out of this contribution; use synthetic fixtures for public examples
and CI evidence. Keep environment-specific IDs, credentials and executable release
configuration in their implementation repositories. Jira status is a dated
observation; editing these plans does not assign or update Jira work.

Changes land through pull requests approved by an `OWNERS` entry. Tide requires the
`approved`, `lgtm`, `jira/valid-reference` and `verified` labels, so start each pull request
title with a valid Jira key and expect to need `/verified`; the Jira bot may warn that the
story has no target version, which its owner sets.

AGENTS.md lists the verify commands. Prow runs `make verify OFFLINE=1`
([what it checks](ci-source.md#where-things-stand)); `USE_IMAGE=0` uses host tools (pin them to
`Dockerfile.ci` for parity with Prow), and full host checks need `curl` and authenticated `gh`.
`TERMS=path` also screens for names in a private list kept outside the repository. The scan
does not read history or commit messages, so keep private material out of both. Refresh Jira
with the read-only [commands](context.md#refreshing-requirements-with-read-only-jira-commands).
