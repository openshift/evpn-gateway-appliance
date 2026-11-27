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

For `tunnel.type: direct-connect`, the appliance pings the workload VTEP from
`tunnel.onprem_ip`, and the workload VTEP pings `tunnel.onprem_ip` back, both
unfragmented at 1550 bytes.
`evpn_health_check_dx_telemetry` (default true for `direct-connect`) also runs the AWS role's
[`dx_status`](../evpn_aws_infra/README.md#read-only-direct-connect-checks-tasks_from-dx_status)
entry point on the controller.

On the appliance, the health checks also report loss and average RTT over 20
pings from `tunnel.onprem_ip` to the workload VTEP, and keep them in the run's
statistics (`set_stats`, AAP job artifacts); total loss fails.

## Transport preflight (`tasks_from: preflight`)

`provision-aws.yml` and `deploy.yml` run these read-only checks before any
change (CORENET-7501):

- WireGuard and IPsec require `evpn_health_check_accept_internet_mode_limits:
  true`; the failure lists their limits.
- `evpn_health_check_workload_mtu`, the workload IP MTU, must be set and fit the transport's budget
  (Direct Connect: 1500, the `safe` mode contract).
- For `direct-connect`: at most one host in `onprem_appliances` and no
  `multihoming.enabled`; `tunnel.mtu_mode: safe`, `tunnel.onprem_ip` inside
  `tunnel.network_cidr`, which must lie outside the VPC CIDRs, and
  `tunnel.next_hop` outside it and the VPC CIDRs, as are the stretch subnets;
  `evpn_aws_infra_infra_vpc_cidr` and `evpn_aws_infra_workload_vpc_cidr`, when
  set, equal to `infra_vpc_cidr` and
  `workload_vpc_cidr`; on the appliance, `tunnel.next_hop` reached
  without a gateway on a directly connected uplink (not the trunk) of at least
  1550 bytes, and no routes within the VPC CIDRs except FRR's.
