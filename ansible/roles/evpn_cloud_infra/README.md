# evpn_cloud_infra

Configures the cloud-side EVPN relay: terminates the transport from the
on-prem appliance and configures FRR as a route relay (not a VTEP) between
the on-prem appliance and the workload-VPC VTEP, preserving VTEP IPs
end-to-end via `next-hop-unchanged`.

This role also owns `tasks/wireguard_keys.yml`, shared with
`evpn_onprem_appliance` via `include_role` (not a hardcoded path — see that
role's comment for why).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `bgp`, `frr_image`, `stretches`).

## Requirements

- `workload_vtep_host` must name an actual inventory host with a `private_ip`
  host variable (defaults to `workload-router`; no multi-peer/HA support yet).
- `stretches` (only `subnet` is read) must match the on-prem/workload stretch
  list — used to build the WireGuard server's `AllowedIPs` (wireguard
  transport only).

## Known limitations (tracked, not fixed by this role)

- The relay re-advertises every EVPN route from each peer with no
  route-map/prefix-list/route-target filtering beyond a defensive
  `maximum-prefix`; see `templates/frr-infra-relay.conf.j2`.
- WireGuard key generation/loading (`tasks/wireguard_keys.yml`) only runs
  for `tunnel.type: wireguard`; every task touching key material sets
  `no_log: true`.
