# evpn_health_check

Read-only validation suite for the EVPN fabric: BGP session state, EVPN
prefix counts, VXLAN interface presence/absence, and end-to-end ping checks.
Tasks are conditional on inventory group membership, so it's safe to apply
to `hosts: all` (see `playbooks/health-check.yml`).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `tunnel`).

No infrastructure changes are made by this role.

For `tunnel.type: ipsec`, the appliance requires both Libreswan Child SAs and
both IPv4 underlay BGP peers to be established; the relay checks received
on-prem EVPN prefixes with convergence retries.

Set `evpn_health_check_vpn_telemetry: true` to also run the AWS role's
[`vpn_status`](../evpn_aws_infra/README.md#read-only-vpn-status-tasks_from-vpn_status)
entry point on the controller during deploy/health checks. It defaults to
`false`; source inventory enables it for IPsec, while emulation leaves it disabled.

On the appliance, the health checks also record a baseline: loss and average
RTT over 20 pings from `tunnel.onprem_ip` to the workload VTEP. Total loss
fails; partial loss and RTT fail only above `evpn_health_check_max_loss_percent`
or `evpn_health_check_max_rtt_ms`, when set.

## Transport preflight (`tasks_from: preflight`)

`provision-aws.yml` runs these read-only checks before creating anything, and
`deploy.yml` first imports `playbooks/preflight.yml`, which runs them before any
host changes (CORENET-7501):

- WireGuard and IPsec cross the internet, so deployment requires
  `evpn_health_check_accept_internet_mode_limits: true`: workload packets above
  1370 (WireGuard) or 1388 (IPsec) bytes are not supported (dropped or
  fragmented, untested), with no MSS clamping until
  CORENET-7709, and WireGuard is for development and test only.
- If `evpn_health_check_workload_mtu` is set, it must fit the transport's budget.
