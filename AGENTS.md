# Agent instructions

EVPN Gateway Appliance (EGA) connects OpenShift EVPN to AWS through a bootc image, disk
images, an AMI and an Ansible collection. This public repository holds the collection
(`ansible/`, see its README), CI entry points and the delivery plans
(`plans/context/evpn-aws/`). Check the tree before assuming other product source exists.

## Working here

- For plan, CI or collection changes, use the reading map in
  `plans/context/evpn-aws/agent-guide.md` to choose which plans to open. Before fixing
  something `source-audit.md` records, read that row: some fixes depend on an open decision.
- Jira acceptance criteria are the requirements. A decision exists only when
  `plans/context/evpn-aws/kickoff-decisions.md` records an accountable owner, date and
  evidence (owners in its table are proposed). Other plan content is a proposal or dated
  evidence to recheck; merged code is current state.
- Keep plan file names, decision numbers and headings or audit-row titles that source comments
  cite stable; if a rename is needed, `git grep` and update every reference.
- Sign off every commit for the DCO (`git commit -s`).
- Start PR titles with a Jira key (`CORENET-1234: ...`) or `NO-JIRA:` for untracked changes;
  Tide needs one. Ask if unsure. Draft PRs get no CI until marked ready or someone comments
  `/test all`.

## Verify

```bash
make verify OFFLINE=1             # Prow's gate: check plus the image tool tests; Prow swaps the image base
make check OFFLINE=1 TERMS=path   # also screens names listed in a private file outside the repo
make check USE_IMAGE=0            # no OFFLINE: online link/pin/Galaxy checks; needs host gh auth
```

Run the first before committing and before pushing. `USE_IMAGE=0` uses host tools, so results
can differ from Prow. In a linked Git worktree the image path fails (its copied `.git` points
outside the build context); run `make verify OFFLINE=1 USE_IMAGE=0` there.

## Public repository

- Never commit customer or support material, credentials, account IDs, private lab
  inventories, raw Jira exports or internal chat. Cite internal sources by ticket key or link
  and summarize them.
- Never push the internal prototype's history; import a reviewed snapshot
  (`plans/context/evpn-aws/source-audit.md#0-public-import`).
