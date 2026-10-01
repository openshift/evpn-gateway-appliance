# evpn_cloud_workload

Configures the workload-VPC standalone EVPN VTEP: per-stretch VXLAN
interfaces/bridges and FRR peering with the infra relay.

> **Not part of the supported production design.** This standalone VTEP
> validated the original proof of concept, but is removed from production,
> where OCP-native EVPN is the workload VTEP instead. Treat this role as a
> dev/test and migration-validation tool, not a production component
> (`context.md`, "The prototype at a glance").

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `bgp`, `frr_image`).

## Requirements

- `infra_relay_host` must name an actual inventory host with a `private_ip` hostvar (defaults to `infra-router`; no multi-peer/HA support yet).
- `private_ip` set as a hostvar on the host this role runs against.
