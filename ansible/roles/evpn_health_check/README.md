# evpn_health_check

Read-only validation suite for the EVPN fabric: BGP session state, EVPN
prefix counts, VXLAN interface presence/absence, and end-to-end ping checks.
Tasks are conditional on inventory group membership, so it's safe to apply
to `hosts: all` (see `playbooks/health-check.yml`).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `tunnel`).

No infrastructure changes are made by this role.

For `tunnel.type: ipsec`, the appliance requires both Libreswan Child SAs and both AWS BGP peers, and
the relay requires EVPN prefixes from every appliance. `evpn_health_check_vpn_telemetry` (default true for `ipsec`) also runs the
AWS role's [`vpn_status`](../evpn_aws_infra/README.md#read-only-vpn-status-tasks_from-vpn_status) on the controller.
