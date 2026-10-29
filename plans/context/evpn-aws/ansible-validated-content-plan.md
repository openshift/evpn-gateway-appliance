# Ansible validated content candidacy: `network.evpn_gateway`

[validated-content-discussion#57](https://github.com/ansible/validated-content-discussion/issues/57)
ticks boxes that main does not support. For each box below, fix main or untick it with a
reason. Review is due 2026-11-13. The criteria are the issue's list, `validation_checklist.md`
in that repository and the
[`ansible-inclusion` checklist](https://github.com/ansible-collections/ansible-inclusion/blob/main/collection_checklist.md).

## State of each box on main (`cbc7d43`)

| Box | On main | Action |
| --- | --- | --- |
| Production-ready | README says lab/dev/test. Only WireGuard is implemented, and it is dev/test only; `evpn_cloud_workload` is not part of the production design | Untick and explain (step 1) |
| Moved into `redhat-cop` | Still `openshift/evpn-gateway-appliance` | Untick: the box says "is being migrated" (step 1) |
| Lint in a GitHub workflow | No `.github/`; lint runs only in Prow | Link the Prow job and result; add an Action if enabled (step 1) |
| Sanity CI | Passes locally; not run per PR | Same as lint (step 1) |
| README: license link, install, versions | None of the three | Step 2 |
| `requirements.yml` points at Hub | Missing | Step 2 |
| 2+ maintainers in CODEOWNERS | `OWNERS` lists four; no `CODEOWNERS` | Step 2 |
| Changelog, Code of Conduct | Missing | Step 2 |
| `ansible-lint` production passes | 96 findings: 77 `var-naming`, 12 `risky-shell-pipe`, 7 `ignore-errors` | Steps 2, 3 |
| Release tag, 1.0.0 | Main is `0.1.0`, untagged | Step 3 |
| OpenSSF badge | Not done | Leave unticked |
| No duplicate, no legal blocker | Confirmed by the plan author | None |
| Packaging, YAML only, OSI license, README purpose | Met | None |

Reproduce the lint count with `ansible-lint -c <config> roles playbooks` in the CI image, with
`profile: production` and no `skip_list` or `warn_list`.

## Steps

Suggested order. No owners are assigned. Tracked in [CORENET-7705](https://redhat.atlassian.net/browse/CORENET-7705), not CORENET-7499.

1. **Update the issue.** The recommended answers below come from the closed candidates, not
   from an accountable owner; the owners of decisions 5 (production-readiness) and 15
   (publisher) confirm them in [kickoff decisions](kickoff-decisions.md#decisions-at-a-glance).
   - Untick production-ready. Reviewers ask about it
     ([#53](https://github.com/ansible/validated-content-discussion/issues/53)), and
     CORENET-7515 is already splitting test material out of the production collection.
   - Stay in `openshift` and untick `redhat-cop`. The same team's
     `network.offline_migration_sdn_to_ovnk` in the same `network` namespace was approved from
     `openshift` ([#45](https://github.com/ansible/validated-content-discussion/issues/45)).
   - For lint and sanity, link the Prow job and the zero-ignore result, as #45 did; its
     reviewers accepted that but recommended a per-PR Action. Actions can be enabled per
     repository on the owner's request ([prior art](prior-art.md)).
2. **Docs and easy lint PR.**
   - README: license link, Hub install command, supported ansible-core and Python versions, and
     drop "shape and publication channel unresolved".
   - Add `ansible/LICENSE`, a Code of Conduct and a root `CODEOWNERS` mirroring `OWNERS`.
   - Add `ansible/requirements.yml` without the collection itself (it breaks lint), listed in
     `build_ignore` (the tarball check rejects it otherwise).
   - Add `ansible/changelogs/changelog.yaml` with `ancestor: null` and `releases: {}`; a bare
     `config.yaml` does not satisfy lint.
   - Fix the 12 `risky-shell-pipe` and 7 `ignore-errors` findings, then drop both from
     `warn_list`.
3. **`var-naming` PR.** Rename the 65 names behind the 77 findings as the lint rule requires.
   Names read by several roles (the VPC CIDRs, the `*_ip` facts) must change everywhere,
   including `evpn_onprem_appliance`, both `group_vars/all.yml`, `inventory/hosts.yml.j2`,
   `playbooks/provision-aws.yml` and the plans. Check which scheme the rule accepts first. Then
   remove the skip, make the count in `ansible/README.md`, `.ansible-lint` and the
   [queue row](ci-source.md#queue) agree, and run `git grep -w` for old names and the e2e lane.
   Reviewers rerun lint on a fresh clone, so the zero-skip result must hold there. The rename
   breaks variable names, so tag the first release after it. If it cannot land before review,
   keep the skip with a per-rule reason, leave the lint boxes unticked and cite the 96 findings.
4. **Upload to Hub.** Validated content is uploaded to console.redhat.com, not Galaxy, and the
   uploader needs permission on the `network` namespace. Who holds it is not known; if nobody
   on the team does, ask the validated-content reviewers, as the submitters in #54 and #55 did.
   See [CI bootstrap](ci-bootstrap-spec.md#collection-and-ee-artifacts).

Last, make sure the issue's boxes match the table.
