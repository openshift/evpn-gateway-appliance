# evpn_cloud_workload

Configures the workload-VPC standalone EVPN VTEP, emulating OpenShift's
workload EVPN: per-stretch VXLAN interfaces and bridges, FRR configuration,
and peering with the infra relay.

> **Dev/test and migration-validation only — not part of the production
> design.** OCP 4.22+ native EVPN (frr-k8s / CUDNs) replaces this
> standalone VTEP in production (CORENET-7515). This role is excluded from
> the production `deploy.yml`; use `deploy-dev.yml` to deploy it in lab
> environments for relay-to-workload validation before migrating to
> OCP-native EVPN (`context.md`, "The prototype at a glance").

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `bgp`, `frr_image`).

## Requirements

- `infra_relay_host` must name an actual inventory host with a `private_ip`
  host variable (defaults to `infra-router`; no multi-peer/HA support yet).
- `private_ip` set as a host variable on the host this role runs against.
