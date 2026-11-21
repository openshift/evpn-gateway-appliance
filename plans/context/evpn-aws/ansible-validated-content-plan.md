# Ansible validated content candidacy: `network.evpn_gateway`

[CORENET-7705](https://redhat.atlassian.net/browse/CORENET-7705) requires an accurate
[validated-content-discussion#57](https://github.com/ansible/validated-content-discussion/issues/57)
checklist, docs/ownership files, production lint, Prow lint/sanity evidence and an authorized
Automation Hub upload. This does not complete CORENET-7499 or production qualification. The goal
is to make every ticked box true; the table names what each remaining box waits on.

In the 2026-11-10 review, Jaime proposed using the existing
[`galaxy.yml` dependencies](https://github.com/openshift/evpn-gateway-appliance/pull/28#discussion_r4525991902)
and [Prow `OWNERS`](https://github.com/openshift/evpn-gateway-appliance/pull/28#discussion_r4526006542)
instead of adding `requirements.yml` and `CODEOWNERS`; CORENET-7705's criteria now follow that
direction. This does not settle the collection support matrix or publication decisions.

## State of each box on main (`91b1ba5`, 2026-11-19)

| Box | On main | Action |
| --- | --- | --- |
| Production-ready | README limits use to lab/dev/test; WireGuard is dev/test only; the workload VTEP still ships | True once decision 18 and the 7500, 7505, 7509, 7708 and 7709 work land |
| Moved into `redhat-cop` | Repository remains in `openshift` | Follows decision 15 (publisher and destination) |
| Lint in a GitHub workflow | Lint runs per PR in Prow; no `.github/` workflow | Link Prow lint results in the candidate issue; add an Action only if Actions is enabled |
| Production lint passes | `production` profile with no skips ([#30](https://github.com/openshift/evpn-gateway-appliance/pull/30), [#37](https://github.com/openshift/evpn-gateway-appliance/pull/37)) | Link a Prow lint result in the candidate issue |
| README: license link, install, versions | Present ([#28](https://github.com/openshift/evpn-gateway-appliance/pull/28)): license, installation and the current CI baseline | A supported ansible-core/Python/AAP matrix remains to be defined |
| Installation information points at Hub | Dependencies are declared in `galaxy.yml`; no `requirements.yml` | #28 documents selecting private Hub configuration for published and source installs |
| 2+ active maintainers in CODEOWNERS | Prow `OWNERS` lists four; no `CODEOWNERS` | True if the candidacy review accepts Prow `OWNERS`, per the #28 review direction |
| Changelog, Code of Conduct | Present (#28) | No additional work identified |
| Sanity evidence | Prow `verify` runs `ansible-test sanity` (core 2.21, Python 3.12) on the installed artifact ([#36](https://github.com/openshift/evpn-gateway-appliance/pull/36)) | Link a run in the candidate issue |
| OpenSSF badge | README feedback, contribution and test-policy section ([#54](https://github.com/openshift/evpn-gateway-appliance/pull/54)) | Register on bestpractices.dev after #54 merges; tick with the badge link |
| No duplicate, no legal blocker | Candidate author's declaration | No additional work identified |
| Packaging, YAML only, OSI license, README purpose | Present | Retain clean-build evidence |

## Steps

1. **Make the issue accurate and confirm owner inputs.** Complete each box's action in the table,
   including production-ready and `redhat-cop`. Obtain the production-readiness and publisher
   owner confirmations, as specified by the ticket, and record the evidence.
2. **Upload the reviewed artifact.** An authorized `network` namespace publisher uploads
   the collection to console.redhat.com and records successful import.
