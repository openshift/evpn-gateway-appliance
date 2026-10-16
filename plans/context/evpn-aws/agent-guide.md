# Guide for coding agents

Start with the rows your task needs, then read the code you will change. In
[`examples/`](examples/README.md) (real YAML with provenance), open the example a row links.
[`pipeline-spec.md`](pipeline-spec.md) proposes the release sequence.
[`source-evidence.md`](source-evidence.md), [`prior-art.md`](prior-art.md) (about 130 KB
together) and the [tool notes](ci-source.md#tool-notes) are evidence ledgers, not instructions:
open the section a spec links to and recheck it.

## Which part to read for which task

| Task | Read |
| --- | --- |
| Scope, status, who decides what | [Decisions at a glance](kickoff-decisions.md#decisions-at-a-glance), [context](context.md), [delivery plan](delivery-plan.md#next-mergeable-work) |
| An open decision (payload, tenant, AMI channel…) | Its [decisions](kickoff-decisions.md#decisions-at-a-glance) row and gate section; lay out the options and surface them, without deciding |
| Record a decision its accountable owner approved | Add owner, date and a link to the approval (PR review or Jira comment, not chat or private documents; summarize a Jira comment that readers may not be able to open) in its gate section and the Status column of [decisions at a glance](kickoff-decisions.md#decisions-at-a-glance), keeping the number; then `git grep` its number (including plural and range mentions such as "decisions 7–9") and its topic, and update the plans that call it open |
| Import the prototype into this repository | [Source audit §0](source-audit.md#0-public-import), then [source audit](source-audit.md) |
| Fix a source-audit defect (for example the FRR lifecycle) | Its row in [source audit](source-audit.md) and the contract it links; a fix that chooses a payload is decision 10 |
| Bootc image, payload, systemd units, native build | [Containerfile contract](containerfile-refactor-spec.md), [runtime payload](pipeline-spec.md#runtime-payload-corenet-7505), L6 in [later sequence](ci-bootstrap-spec.md#later-sequence) |
| Disk Components (qcow2, raw, vmdk) and BIB wrappers | [task baseline](bib-configuration-spec.md#verified-task-baseline), [wiring](bib-configuration-spec.md#repository-and-component-wiring), [policy and package access](bib-configuration-spec.md#enterprise-contract-and-package-access), [tenant examples](examples/README.md). Image sources are in open PR #16, and the plans propose BIB wrappers under `image/`; Components go in KRD `tenants-config` ([KRD mechanics](delivery-plan.md#krd-mechanics)); needs decisions 7–10 (12 for vmdk) |
| Konflux Component, tenant, nudges, candidate Snapshot | [Resource model](pipeline-spec.md#konflux-resource-model), the opening of [artifact graph](pipeline-spec.md#artifact-graph-and-candidate-integrity), [nudging](pipeline-spec.md#nudging), [KRD mechanics](delivery-plan.md#krd-mechanics), [`portal-bootc-component.yaml`](examples/tenant/portal-bootc-component.yaml); [generated PipelineRuns](ci-bootstrap-spec.md#generated-pipelineruns-and-resolvers). Onboarding waits on decisions 7–9 and the image source on PR [#16](https://github.com/openshift/evpn-gateway-appliance/pull/16), so use placeholders |
| Add or change a source check or tool pin | [How to add a check](ci-source.md#how-to-add-a-check), its [queue](ci-source.md#queue) row, that tool's [tool notes](ci-source.md#tool-notes) subsection and [runner notes](ci-source.md#runner-and-prow); update bots: [build-root extraction](ci-bootstrap-spec.md#build-root-update-extraction); a previously rejected tool: [deferred](ci-source.md#deferred) |
| What CI runs today | [Where things stand](ci-source.md#where-things-stand), `rules.mk` |
| Open a PR, add a plan document, or a Prow job failed | [Maintaining the plan](README.md#maintaining-the-plan) (a new document also gets a row in the README's Start here or Implementation contracts table); infrastructure errors such as pod scheduling timeouts need `/retest`, not a source change |
| Metrics, dashboards, alert rules | [Metrics](pipeline-spec.md#metrics-corenet-74997504); the series depend on open decision 16 and `evpn_monitoring` still runs the legacy exporter, so surface that before writing rules |
| Fix a link or pin failure | The checker's docstring in `plans/context/evpn-aws/tools/`; rerun "unreachable" results and fix the link rather than a cited heading |
| Molecule role scenario | L5 in [later sequence](ci-bootstrap-spec.md#later-sequence), the opening role-test paragraphs of [test placement](ci-bootstrap-spec.md#test-placement), [how to add a check](ci-source.md#how-to-add-a-check). The plan proposes a controller-only negative case first; `evpn_health_check` runs `podman exec frr vtysh` and `wg show`, so it belongs with live-host lanes (L7) |
| Tide and Konflux contexts, integration and AWS tests, collection publication | [Tide and Konflux contexts](ci-bootstrap-spec.md#tide-and-konflux-contexts), [gates and test infrastructure](pipeline-spec.md#3-integration-gates-and-test-infrastructure), [disk validation and AWS lifecycle](bib-configuration-spec.md#disk-validation-and-aws-lifecycle), [collection artifacts](ci-bootstrap-spec.md#collection-and-ee-artifacts) |
| AMI or another customer channel | [AMI channel](bib-configuration-spec.md#ami-channel) or the relevant [delivery channel](bib-configuration-spec.md#customer-delivery-channels); release objects: [promotion](pipeline-spec.md#4-promotion-and-operation), [productization](productization.md) |
| MTU, transports, OCP EVPN behavior | [networking handoff](networking-spec.md), [primer](evpn-primer.md) |
| Which existing example to reuse | [prior art](prior-art.md#choose-the-example-by-delivery-problem) |

## Sources of truth

- **Requirements** are the acceptance criteria of CORENET-7498's children. 7505, 7501 and 7504
  conflict with product or AWS facts; the [proposed resolutions](kickoff-decisions.md#already-settled)
  lack an accountable owner and the Jira text is uncorrected. A review also redirected 7499's
  collection name (decision 5, owner pending). Surface conflicts; do not silently override Jira.
- **Implementation facts** carry a repository, revision and path; recheck them, and remember
  that merged is not deployed. Link GitHub evidence by commit SHA with the version in prose;
  the pin checker skips tags ([limits](ci-source.md#where-things-stand)).

## Verified facts that are easy to get wrong

| Topic | Fact | Evidence |
| --- | --- | --- |
| Tenant | No approved EVPN tenant/cluster is recorded here. `bgp-cloud-connector-tenant` on `kflux-prd-rh02` is the networking org's precedent; recheck EVPN onboarding with its owner | CORENET-7409 |
| Policy | Start an EVPN ECP as a copy of `registry-standard` (or `-stage`) with `konflux-release-data/derived-from`. Reviewed KRD roots exclude `cve.cve_blockers`; verify the effective EVPN policy and deployed enforcement before relying on CVE blocking. EVPN/ProdSec vulnerability acceptance remains required ([evidence](source-evidence.md#2-green-status-is-not-complete-release-evidence)) | KONFLUX-7113, KONFLUX-15693; [example](examples/release/registry-standard-ecp.yaml) |
| Bootc registry | Proposed: customers pull the bootc image from authenticated `registry.redhat.io` via `rh-advisories`, as BGP CC does, and appliances update from it (7510); registry paths are decision 17 | [publication](pipeline-spec.md#publication), [BGP CC stage RPA](examples/release/bgp-cc-stage-rpa.yaml) |
| AMI | The checked catalog's managed AMI publisher is `push-disk-images-to-marketplaces`, and the checked KRD RPAs using it are Marketplace listings. Its `oras pull` has no `--platform`, so a multi-architecture index can publish the wrong architecture silently. The channel is an open decision; RHEL accepted a CDN download alone for its AWS CVM Tech Preview | [AMI channel](bib-configuration-spec.md#ami-channel) |
| FRR payload | OCP's `frr-rhel9` carries FRR and FIPS-capable `frr-metrics`; there is no separate OCP frr-k8s image. The checked 4.23/5.x exporter needs Kubernetes; standalone and EVPN-metrics changes remain work. Recheck 5.x publication and the open image PRs | [runtime payload](pipeline-spec.md#runtime-payload-corenet-7505), [evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs) |
| ITS resolvers | Merged webhook code limits the `url`/`repo`/`org` requirement to Git resolvers (STONEINTG-1586, Closed). Verify bundle admission on the selected cluster; pin release-gating test pipelines to an approved revision | [webhook source](https://github.com/konflux-ci/integration-service/blob/2508848c0ee92ee1896de755ea38b586070348de/internal/webhook/v1beta2/integrationtestscenario_webhook.go) |
| PR trust | Pipelines-as-Code runs PR pipelines without approval for any `openshift` org member, collaborator, author with branch push access or `OWNERS` entry, so PR-triggered pipelines and component-context ITSs must never mount AWS, lab or publishing credentials | [authorization rules](https://pipelinesascode.com/docs/guides/running-pipelines/) |
| Test status | The checked ITS evaluator can accept absent `TEST_OUTPUT`, `SKIPPED` and `WARNING`; optional scenarios are excluded from the required verdict. Release gates need named suites and evidence | [pipeline plan](pipeline-spec.md#3-integration-gates-and-test-infrastructure) |
| Collection proof | The `check-ansible` build/install smoke, lint and syntax checks do not prove controller dependency closure, `MANIFEST.json`-to-`FILES.json` integrity or input rejection; the linked sections give the native mechanism for each | [EE artifacts](ci-bootstrap-spec.md#collection-and-ee-artifacts), [integrity](ci-bootstrap-spec.md#collection-content-integrity), [test placement](ci-bootstrap-spec.md#test-placement) |
| Collection build | `build_ignore` is a deny list without negation (`*` plus `!roles` builds an empty tarball). The builder's `manifest` inclusions need `distlib` (check `Dockerfile.ci`). galaxy-importer hard-fails on missing `repository`, `requires_ansible` and role READMEs but only warns about undeclared collections | [measured behavior](ci-bootstrap-spec.md#measured-collection-build-and-import-behavior), [tool notes](ci-source.md#tool-notes) |
| Bootc lint | `bootc container lint --fatal-warnings` (1.16.13, September 2026) fails the unmodified CentOS Stream 9 base on `var-tmpfiles`, flags `/var/run/frr` content as `nonempty-run-tmp`, and accepts a misspelled `kargs.d` argument, so it cannot replace a FIPS assertion | [lint coverage](containerfile-refactor-spec.md#required-outcomes) |
| OCP tests | The OTE binary silently drops EVPN specs unless the cluster has the EVPN gate, FRR provider, local gateway mode and an external FRR container. Require a nonzero EVPN case count | [OTE evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs) |

## Output rules

- Never copy another product's names, product IDs, CPEs, secrets, service accounts, image or
  registry repository paths, feature-branch revisions or policy exclusions; shared upstream
  task and catalog references are fine. Leave marked placeholders for unsettled values.
- Resolve task bundles and images to digests when generating, with the version beside each.
  If you cannot resolve one, leave a marked placeholder; never invent a digest or copy one you
  did not resolve.
- Keep credentials, customer data and private terms out of logs, public results and shipped
  artifacts. Lab-only material (Terraform, WireGuard defaults, inventories) does not ship;
  private fixtures and detailed reports stay outside the repository.
