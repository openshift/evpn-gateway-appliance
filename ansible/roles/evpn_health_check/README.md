# evpn_health_check

Read-only validation suite for the EVPN fabric: BGP session state, EVPN
prefix counts, VXLAN interface presence/absence, and end-to-end ping checks.
Tasks are conditional on inventory group membership, so it's safe to apply
to `hosts: all` (see `playbooks/health-check.yml`).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `tunnel`).

No infrastructure changes are made by this role.

## Production vs dev/test

In production, OCP 4.22+ native EVPN (frr-k8s / CUDNs) is the workload
VTEP. The role validates the infra relay's BGP session and EVPN prefix
exchange with the OCP peer when `ocp_vtep_peer_ip` is defined.

The standalone workload VTEP checks (`cloud_workload` group) only run
when `standalone_workload_vtep` is set to `true` — this is the
`deploy-dev.yml` path for lab and migration-validation use. See
CORENET-7515.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `standalone_workload_vtep` | bool | `false` | Enable standalone VTEP health checks (dev/test only). |
| `ocp_vtep_peer_ip` | str | (undefined) | OCP-native EVPN peer IP. Enables OCP BGP/EVPN checks on the infra relay. |
| `workload_vtep_host` | str | — | Standalone workload VTEP inventory hostname. Only used when `standalone_workload_vtep` is `true`. |
