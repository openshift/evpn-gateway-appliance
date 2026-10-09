# evpn_health_check

Read-only validation suite for the EVPN fabric: BGP session state, EVPN
prefix counts, VXLAN interface presence/absence, and end-to-end ping checks.
Tasks are conditional on inventory group membership, so it's safe to apply
to `hosts: all` (see `playbooks/health-check.yml`).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `tunnel`).

No infrastructure changes are made by this role.
