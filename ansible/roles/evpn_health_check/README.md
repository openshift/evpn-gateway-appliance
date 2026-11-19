# evpn_health_check

Read-only validation suite for the EVPN fabric: BGP session state, EVPN
prefix counts, VXLAN interface presence/absence, and end-to-end ping checks.
Tasks are conditional on inventory group membership, so it's safe to apply
to `hosts: all` (see `playbooks/health-check.yml`).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `tunnel`).

No infrastructure changes are made by this role.

## Workload peers

Infra relay checks iterate the `cloud_workload` inventory group. BGP
Established is required for every peer, and each peer must deliver an EVPN
prefix. The on-prem remote-VTEP check requires that prefix to install a
remote VTEP. The cloud-gateway ping runs when a `cloud_workload` peer is a
standalone VTEP, and skips when every peer was added from frr-k8s: a primary
L2 CUDN does not own that gateway address. Workload-side checks run only
when the play includes `cloud_workload` hosts.
