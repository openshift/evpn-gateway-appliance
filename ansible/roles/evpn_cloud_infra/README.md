# evpn_cloud_infra

Configures the cloud-side EVPN relay: terminates the transport from the
on-prem appliance and configures FRR as a route relay (not a VTEP) between
the on-prem appliance and the workload-side VTEPs, preserving VTEP IPs
end-to-end via `next-hop-unchanged`.

This role also owns `tasks/wireguard_keys.yml`, shared with
`evpn_onprem_appliance` via `include_role` (not a hardcoded path — see that
role's comment for why).

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `bgp`, `stretches`).

## Workload-side peering

The relay peers with every host in the `cloud_workload` inventory group,
reading `private_ip` from each host's vars and `workload_asn` from the role
input. Record the peers manually in the inventory, or leave the group empty
and let the role discover them: `frr_kubernetes_namespace` and
`frr_kubernetes_label` must then be set, and the role reads running frr-k8s
pods on the Ansible controller into `cloud_workload`.

## Requirements

- Set `private_ip` to the relay's private address.
- `tunnel.onprem_ip` must be an IPv4 address without a prefix. The three BGP ASNs must be
  distinct and in 1-4294967295.
- For WireGuard, set a distinct IPv4 `tunnel.cloud_ip` without a prefix inside `tunnel.network_cidr`
  (default `10.44.44.0/24`) and `tunnel.port` in 1-65535. Supply each stretch's IPv4 network CIDR
  in `stretches[].subnet`, matching the on-prem/workload stretch list. Per-stretch VLANs, names
  and gateways are not required by this role.

## Known limitations (tracked, not fixed by this role)

- The relay re-advertises every EVPN route from each peer with no
  route-map/prefix-list/route-target filtering beyond a defensive
  `maximum-prefix`; see `templates/frr-infra-relay.conf.j2`.
- WireGuard key generation/loading (`tasks/wireguard_keys.yml`) only runs
  for `tunnel.type: wireguard`; every task touching key material sets
  `no_log: true`.
