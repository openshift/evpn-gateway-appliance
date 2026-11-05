# EVPN Gateway Appliance (EGA) — project context

EVPN Gateway Appliance (EGA) enables the use of EVPN with OpenShift in public clouds.

Requirements baseline rechecked on 2026-10-13; collection-CI scope and epic child statuses
refreshed on 2026-10-16. This is planning context for the
proposed delivery design, not a support statement or an ownership assignment.

## Scope

OCPSTRAT-3413 and CORENET-7498 propose integrating OpenShift with enterprise EVPN
fabrics via AWS Direct Connect or Site-to-Site VPN. The design builds on the broader
OpenShift Networking EVPN effort (OKEP-5088, OCP 4.22). OCPSTRAT-3413's Target
Version is `openshift-5.1`; CORENET-7498 requires OCP 4.22 or later. PERFSCALE-5814
records a 5.1 target with backports to 4.22 (it also gives completion and customer-release
timing; see the ticket). The parent outcome
[HPSTRAT-714](https://redhat.atlassian.net/browse/HPSTRAT-714) covers AWS, Azure
and GCP and names the managed offerings ROSA, ARO and OSD.

The intended product consists of:

1. **OVN-Kubernetes EVPN** — the OpenShift CNI. OKEP-5088 provides the EVPN
   building blocks in 4.22, but its stated supported goal is on-prem deployment;
   cloud enablement needs separate approval. Published 4.22 EVPN documentation
   limits support to bare-metal clusters; AWS test success does not expand support.
2. **Migration appliance and relay roles** — a bootc image deployed for on-prem
   attachment and AWS-side EVPN connectivity, with qcow2 and AMI artifacts in
   Jira. The design's VMware/NSX on-prem target would also need vmdk/ova.
3. **Ansible collection** — deploys and configures the appliance, relay and AWS
   resources. The design leaves OCP CUDN/FRR configuration to documented operator
   steps (CORENET-7512); managing it from the collection is an open scope choice.

The prototype lives in an internal GitLab repository. Its public home,
[`openshift/evpn-gateway-appliance`](https://github.com/openshift/evpn-gateway-appliance),
was created on 2026-09-28 (DPP-22292). It holds a license, an `OWNERS` file naming four approvers
and reviewers (added 2026-09-29), these planning documents, a `Makefile` and CI image definitions.
The Ansible collection merged with #7 on 2026-10-14. Embedded OCP 4.22 image sources
merged with [#6](https://github.com/openshift/evpn-gateway-appliance/pull/6) on 2026-10-23
at `be5a2b9a`; #16 and the superseded collection #3 are closed.
[Source CI](ci-source.md#where-things-stand) lists the checks that now run. Green source verify does not establish
image-build or deployment behavior. Repository #8/#12 and release#86670 merged;
Prow now uses PR-built `Dockerfile.ci`. Local Make delegates by default, with host
checks available through `USE_IMAGE=0`.

## The prototype at a glance

The source baseline summarized here is the internal prototype
[`evpn-on-cloud` at `1c8e88873af8`](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/tree/1c8e88873af8)
(2026-09-08). Its `docs/evpn-task-breakdown.md` is where every CORENET-7499–7524 story
comes from, and the source audit and networking handoff cite its files and lines.
The image described below is the prototype's; the merged `image/rhel10/Containerfile`
(#6) instead embeds the OpenShift FRR image and node-exporter, with no `frr_exporter`.

| Path | What it holds |
| --- | --- |
| `ansible/roles/evpn_onprem_appliance` | On-prem appliance: VLAN sub-interfaces, a bridge and a VXLAN device per stretch, FRR VTEP. `physical.yml` attaches a real tagged trunk, now exercised by the 7508 e2e; the veth/namespace simulation was extracted to the `network.evpn_gateway_test` test collection (7515) |
| `ansible/roles/evpn_cloud_infra` | Infra-VPC relay: WireGuard server plus an FRR relay with `next-hop-unchanged` and no VXLAN |
| `ansible/roles/evpn_cloud_workload` | Standalone cloud VTEP that validated the proof of concept; CORENET-7515 removes it from production, where OCP-native EVPN is the workload VTEP |
| `ansible/roles/evpn_aws_infra` | AWS provisioning (infra and workload VPCs, TGW, security groups, router instances) through `aws` CLI calls |
| `ansible/roles/evpn_monitoring`, `evpn_health_check` | `frr_exporter` and `node_exporter` podman units; the health-check suite |
| `ansible/playbooks/` | `deploy`, `health-check`, `provision-aws`, `teardown`, `teardown-aws`; inventory groups `cloud_infra`, `cloud_workload`, `onprem_appliances` |
| `ansible/inventory/group_vars/all.yml` | The de facto API: `tunnel.type` (`wireguard` works; `ipsec` and `direct-connect` are not implemented), `tunnel.mtu_mode`, `bgp` ASNs (65044 on-prem, 65100 relay, 65200 workload), `stretches` (VLAN, subnet, gateways; the VNI is 10000 + the VLAN ID) and `frr_image` |
| `image/` | `Containerfile` (CentOS Stream 9 bootc; FRR and both exporters as systemd `podman run` units), `build-ami.sh` (BIB `--type ami`, S3 upload, VM Import, AMI registration), `setup-vmimport-role.sh` |
| `hack/terraform/` | Lab scaffolding for the AWS test environment, not product |
| `docs/` | `design.md`, `evpn-l2-stretch-plan.md`, `evpn-sample-flows.md`, `evpn-task-breakdown.md`, `presentation.html` |

One bootc image serves both roles and Ansible selects the behavior: a qcow2 for the on-prem
appliance and an AMI for the infra-VPC relay (`evpn-l2-stretch-plan.md`, "What Already
Exists"). That is why the AMI is a customer-launched artifact and why the plan asks how
customers obtain it. HPSTRAT-714's September 2 update describes an infrastructure-VPC
gateway that can interconnect several clusters for one customer. The prototype has no CI,
no collection metadata (`galaxy.yml`, `meta/runtime.yml`), no `argument_specs`, and
implements only the WireGuard transport ([source audit](source-audit.md)).

## Jira requirements

### Refreshing requirements with read-only Jira commands

```bash
# Verify auth
acli jira auth status

# List all direct children of the EVPN epic (26 on 2026-09-29; 27 on 2026-09-30, see Stories)
acli jira workitem search --jql 'parent = CORENET-7498' \
  --fields "key,summary,status,assignee" --paginate --csv

# View a single ticket
acli jira workitem view CORENET-7505
```

`view` returns a limited field set. Request custom fields explicitly with `--fields`
before treating absent sprint, point or acceptance data as unset.

### Parent feature and epic

| Ticket | Summary | Status |
| -------- | --------- | -------- |
| [OCPSTRAT-3413](https://redhat.atlassian.net/browse/OCPSTRAT-3413) | EVPN Integration Design and AWS support (Feature) | In Progress |
| [HPSTRAT-714](https://redhat.atlassian.net/browse/HPSTRAT-714) | EVPN Support on Public Cloud Platforms (Outcome, parent) | In Progress |
| [CORENET-7498](https://redhat.atlassian.net/browse/CORENET-7498) | Enable EVPN integration on AWS (Epic) | In Progress |

### Stories

The 2026-10-16 read-only child search shows CORENET-7507 Closed, 7506 and 7508 In Progress,
and the other original requirement stories (7499–7524) To Do. Collection lint is complete
under 7507; [CORENET-7667](https://redhat.atlassian.net/browse/CORENET-7667) now tracks
Molecule, VNI/ASN/transport validation and publication.
[CORENET-7615](https://redhat.atlassian.net/browse/CORENET-7615) tracks review and landing
of these documents. Its criteria require review of the artifact graph, gates and proposed
responsibilities, and listing open decisions and the three cited Jira conflicts with proposed
owners. Recording decisions as their owners make them is follow-up work, not a closure
criterion. Release engineering's proposed scope is [7505](https://redhat.atlassian.net/browse/CORENET-7505)
(pin component images), [7506](https://redhat.atlassian.net/browse/CORENET-7506)
(appliance image CI), [7507](https://redhat.atlassian.net/browse/CORENET-7507)
(completed collection lint), 7667 (remaining collection CI) and [7522](https://redhat.atlassian.net/browse/CORENET-7522)
(publish release artifacts). The other stories supply the acceptance evidence the
release gates consume ([pipeline plan](pipeline-spec.md#required-gates)). The
[delivery plan](delivery-plan.md) lists every story with its next proof.

The 2026-10-13 read-only refresh covered the feature/outcome/epic, all 26 requirement
stories, CORENET-7615 and CORENET-7622. CI criteria still require standard image/Ansible
lint, builds/publication, per-role Molecule scenarios, input validation and simulated EVPN behavior;
they add no scanner migration or additional orchestration framework. Other epic work includes import
stories CORENET-7620/7621, completed Prow onboarding CORENET-7622 and
[CORENET-7664](https://redhat.atlassian.net/browse/CORENET-7664) for standard source lint.
A later October 13 refresh found CORENET-7515 explicitly requires a collection split
between production and emulation/test harnesses; the [delivery contract](pipeline-spec.md#outcome-and-ownership)
retains that boundary. Use live tickets to confirm ownership and scheduling.

### Documentation and prior-art tickets

| Ticket | Summary | Status |
| -------- | --------- | -------- |
| [OSDOCS-20531](https://redhat.atlassian.net/browse/OSDOCS-20531) | Docs for OCPSTRAT-3413 | New |
| [CORENET-7400](https://redhat.atlassian.net/browse/CORENET-7400) | BGP Cloud Connector productization template (prior art) | Closed |
| [CORENET-7409](https://redhat.atlassian.net/browse/CORENET-7409) | BGP Cloud Connector Konflux onboarding (prior art) | Closed |
| [RHELDST-25935](https://redhat.atlassian.net/browse/RHELDST-25935) | Create RHEL AI Pulp repo for disk images (prior art) | Closed |

The documentation and prior-art status baseline is 2026-09-29; evidence and dates
are recorded in the audit. Requirement stories cite the task breakdown that generated them.

Use the linked feature/epic for current contacts and
[the decision list](kickoff-decisions.md) to agree responsibility for each gate.

## Transport context

- Intended AWS transport: **Direct Connect** or **Site-to-Site VPN**
  (WireGuard = dev/test only). The current source implements only WireGuard;
  the production transports remain blocking implementation work under
  CORENET-7498's live acceptance criteria.
- On-prem appliances and cloud infrastructure relays have different roles;
  record the actual packet path for each supported transport. Do not transfer
  the WireGuard lab relay's forwarding behavior to the production VPN topology.
- OCP nodes run frr-k8s DaemonSet; EVPN routes propagate via BGP between appliance and nodes
- Out of scope: Azure, GCP, cloud-provider-specific EVPN control plane

## Primary references

- [OCP 4.22 EVPN
  documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-evpn-for-user-defined-networks)
- [OKEP-5088 design](https://ovn-kubernetes.io/master/okeps/okep-5088-evpn/)
- [Red Hat Developer
  example](https://developers.redhat.com/articles/2026/09/03/extend-layer-2-networks-into-red-hat-openshift-virtualization-with-bgp-and-evpn)
  (2026-09-03)
- [Inspected task
  breakdown](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af8/docs/evpn-task-breakdown.md)
  (internal)

## Relevant repositories

Use [`prior-art.md`](prior-art.md) for exact files and the
[source evidence](source-evidence.md) for checked revisions and read limits.

| Repository | Use |
| --- | --- |
| [openshift/evpn-gateway-appliance](https://github.com/openshift/evpn-gateway-appliance) | Canonical public repository (license, `OWNERS`, these documents, the `Makefile` and the CI build image, with product source arriving in reviewed pieces); the inspected prototype is internal [`evpn-on-cloud`](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud) |
| [openshift/release](https://github.com/openshift/release) | Prow and OpenShift CI configuration for the repository |
| [konflux-release-data](https://gitlab.cee.redhat.com/releng/konflux-release-data) | Tenant source definitions and separate managed stage/prod publication objects |
| [build-definitions](https://github.com/konflux-ci/build-definitions), [container-build-catalog](https://github.com/konflux-ci/container-build-catalog) | BIB, index, source and standard build-task contracts |
| [release-service-catalog](https://github.com/konflux-ci/release-service-catalog) | Managed pipeline contracts; inspect the actual RPA's resolver revision |
| [rhtap-ec-policy](https://github.com/release-engineering/rhtap-ec-policy), [Conforma policy](https://github.com/conforma/policy) | Central rule data and rules; resolve the target policy during implementation |
| [aipcc-konflux-data](https://github.com/red-hat-data-services/aipcc-konflux-data), [integration catalog](https://github.com/konflux-ci/tekton-integration-catalog), [Testing Farm adapter](https://gitlab.com/testing-farm/integrations-konflux) | AWS workflows and test backends |
| [bootc](https://github.com/bootc-dev/bootc), [bootc-foundry](https://github.com/osbuild/bootc-foundry), [image-builder](https://github.com/osbuild/image-builder) | Lifecycle/build examples; old BIB upstream moved into image-builder |
| [ovn-kubernetes](https://github.com/ovn-kubernetes/ovn-kubernetes), [OpenShift fork](https://github.com/openshift/ovn-kubernetes) | EVPN test/topology helpers, API constraints and OTE case selection |
| [ocp-build-data](https://github.com/openshift-eng/ocp-build-data), [openshift/frr](https://github.com/openshift/frr) | Red Hat builds of the payload: `frr-rhel9` (RHEL `frr10` plus `frr-metrics`) and node-exporter; ART's MicroShift bootc precedent |
| [bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector), [network.offline_migration_sdn_to_ovnk](https://github.com/openshift/network.offline_migration_sdn_to_ovnk) | The networking org's public repositories: Konflux/OpenShift CI product and Automation Hub collection precedents |
| [ansible-content-actions](https://github.com/ansible/ansible-content-actions), [openperouter](https://github.com/openperouter/openperouter) | Collection CI/release workflows; host-mode FRR EVPN router with containerlab CI |
| [Konflux users documentation](https://gitlab.cee.redhat.com/konflux/docs/users) | Internal federation and delivery contracts |
| [Pyxis configuration](https://gitlab.cee.redhat.com/releng/pyxis-repo-configs), [production advisories](https://gitlab.cee.redhat.com/releng/advisories), [stage advisories](https://gitlab.cee.redhat.com/rhtap-release/advisories) | Channel metadata and publication evidence |

Use an isolated checkout at the recorded revision when reproducing a finding.
The inspected product-source and KRD commits are cached baselines, not current
remote heads. Their revisions are not a claim about deployed resources.
