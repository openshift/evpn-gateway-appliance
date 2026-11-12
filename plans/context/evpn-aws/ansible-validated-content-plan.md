# Ansible validated content candidacy: `network.evpn_gateway`

[CORENET-7705](https://redhat.atlassian.net/browse/CORENET-7705) requires an accurate
[validated-content-discussion#57](https://github.com/ansible/validated-content-discussion/issues/57)
checklist, docs/ownership files, production lint, Prow lint/sanity evidence and an authorized
Automation Hub upload. Review is due 2026-11-13. This does not complete CORENET-7499 or
production qualification. Unsupported checklist claims may remain unticked with reasons;
the ticket does not require making every box true.

In the 2026-11-10 review, Jaime proposed using the existing
[`galaxy.yml` dependencies](https://github.com/openshift/evpn-gateway-appliance/pull/28#discussion_r4525991902)
and [Prow `OWNERS`](https://github.com/openshift/evpn-gateway-appliance/pull/28#discussion_r4526006542)
instead of adding `requirements.yml` and `CODEOWNERS`. CORENET-7705 still explicitly
requires both files; reconcile that criterion with the review direction before claiming
story completion. This does not settle the collection support matrix or publication decisions.

## State of each box on main (`1238348`, 2026-11-04)

| Box | On main | Action |
| --- | --- | --- |
| Production-ready | README limits use to lab/dev/test; only WireGuard is implemented; the workload VTEP still ships | Untick with an explanation; owner confirms production scope |
| Moved into `redhat-cop` | Repository remains in `openshift` | Untick; confirm the existing repository home |
| Lint in a GitHub workflow | Lint runs per PR in Prow; no `.github/` workflow | Link Prow lint results in the candidate issue; add an Action only if Actions is enabled |
| Production lint passes | `var-naming[no-role-prefix]` remains skipped; pipefail and ignore-errors fixes merged in [#30](https://github.com/openshift/evpn-gateway-appliance/pull/30) | Merge [#37](https://github.com/openshift/evpn-gateway-appliance/pull/37), or leave lint boxes unticked with a reason if it cannot land before review |
| README: license link, install, versions | Missing | [#28](https://github.com/openshift/evpn-gateway-appliance/pull/28) documents installation and the current CI baseline; a supported ansible-core/Python/AAP matrix remains to be defined |
| Installation information points at Hub | Dependencies are declared in `galaxy.yml`; no `requirements.yml` | #28 documents selecting private Hub configuration for published and source installs |
| 2+ active maintainers in CODEOWNERS | Prow `OWNERS` lists four; no `CODEOWNERS` | Retain Prow ownership; explain the alternative in #57 and leave the literal CODEOWNERS claim unticked unless accepted in candidacy review |
| Changelog, Code of Conduct | Missing | #28 |
| Sanity evidence | Native Prow sanity result pending | Reuse suitable Prow sanity evidence from the collection CI effort, [CORENET-7667](https://redhat.atlassian.net/browse/CORENET-7667), when available; link it in the candidate issue. No separate 7705 CI implementation or requirement to complete the broader story |
| OpenSSF badge | Not done; box already unticked | Leave unticked |
| No duplicate, no legal blocker | Candidate author's declaration | No additional work identified |
| Packaging, YAML only, OSI license, README purpose | Present | Retain clean-build evidence |

## Steps

1. **Correct the issue and confirm owner inputs.** Untick unsupported claims with reasons,
   including production-ready and `redhat-cop`. Obtain the production-readiness and publisher
   owner confirmations of those corrections, as specified by the ticket, and record the evidence.
2. **Upload the reviewed artifact.** An authorized `network` namespace publisher uploads
   the collection to console.redhat.com and records successful import.
