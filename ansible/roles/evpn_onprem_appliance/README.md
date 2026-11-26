# evpn_onprem_appliance

Configures the on-prem side of the EVPN fabric: the transport endpoint, the
VLAN trunk interface, per-stretch VXLAN interfaces and bridges, and FRR
configured as the on-prem VTEP.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `stretches`, `trunk_interface`, `bgp`,
`infra_vpc_cidr`, `workload_vpc_cidr`, `ocp_pod_network_cidr`). The latter
three (plus `tunnel.network_cidr`) all default to the lab/dev values below if
left unset — only override them if your VPC/pod-network CIDRs differ.

## Known limitations (tracked, not fixed by this role)

- The on-prem networking (nmstate, `tasks/nm_networking.yml`) is exercised by
  the Molecule lane against a veth stand-in trunk; it is not yet validated
  against actual hardware or a real tagged customer trunk (source-audit.md).
- The role provisions WireGuard. With `ipsec` or `direct-connect`, the environment
  must already provide the routed underlay. The WireGuard mode is single-appliance.
- The FRR templates set no inbound/outbound route policy beyond a
  defensive `maximum-prefix`; see the comment at the top of
  `templates/frr-onprem-appliance.conf.j2`.
- All-active multihoming is enabled with `multihoming.enabled`, a shared
  `es_id`/`es_sys_mac`, and `bond_interfaces`. It requires two appliances and
  an upstream LACP-capable Ethernet Segment. The role creates persistent
  NetworkManager bond/member connections; the default remains single-link
  operation.

## Example

```yaml
- hosts: onprem_appliances
  become: true
  roles:
    - evpn_onprem_appliance
  vars:
    infra_relay_host: infra-router
    tunnel:
      type: wireguard
      port: 51820
      onprem_ip: 10.44.44.1
      cloud_ip: 10.44.44.2
      # network_cidr: 10.44.44.0/24   # optional; defaults shown
    bgp:
      onprem_asn: 65044
      infra_asn: 65100
      workload_asn: 65200
    stretches:
      - vlan: 100
        name: production
        subnet: 10.42.1.0/24
        onprem_gateway: 10.42.1.1
        cloud_gateway: 10.42.1.2
    trunk_interface: trunk0
```

For two physical appliances in `onprem_appliances`, set `trunk_interface: bond0` and use the same
multihoming identity on both hosts. The CE-facing LACP bundle spans both
appliances, so each appliance may contribute one local bond member. The
appliances exchange Ethernet-Segment routes through the EVPN relay; the role
does not create a direct appliance-to-appliance BGP or BFD session. The shared
anycast SVI MAC must be identical on both appliances and distinct from the ES MAC.

Use a routed transport and give each host its own `tunnel.onprem_ip` and
`bgp.onprem_asn`. Set `tunnel.cloud_ip` to the BGP/BFD peer address and
`tunnel.underlay_interface` to the local interface FRR tracks for uplink loss.
The relay derives its appliance neighbors from inventory and enables BFD on each
adjacency. An optional per-appliance `multihoming.df_pref` sets the DF preference.

```yaml
multihoming:
  enabled: true
  bond_interfaces: [eno1]
  # Numeric discriminator + shared system MAC selects FRR's Type-3 ESI form.
  es_id: 1
  es_sys_mac: "02:aa:bb:cc:dd:ee"
  anycast_mac: "02:00:5e:00:00:01"
```
