# evpn_cloud_workload

Configures the workload-VPC standalone EVPN VTEP, emulating OpenShift's
workload EVPN: per-stretch VXLAN interfaces and bridges, FRR configuration,
and peering with the infra relay.

> **Test collection only.** In production, OCP-native EVPN (frr-k8s + CUDNs)
> replaces this standalone VTEP. Deploy via `network.evpn_gateway_test.deploy_workload`.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`stretches`, `bgp`, `frr_image`).

## Requirements

- `infra_relay_host` must name an actual inventory host with a `private_ip`
  host variable (defaults to `infra-router`; no multi-peer/HA support yet).
- `private_ip` set as a host variable on the host this role runs against.
