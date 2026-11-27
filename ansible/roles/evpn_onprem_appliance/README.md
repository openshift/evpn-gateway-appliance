# evpn_onprem_appliance

Configures the on-prem side of the EVPN fabric: the transport endpoint, the
VLAN trunk interface, per-stretch VXLAN interfaces and bridges, and FRR
configured as the on-prem VTEP.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `stretches`, `trunk_interface`, `infra_relay_host`, `bgp`,
`infra_vpc_cidr`, `workload_vpc_cidr`, `ocp_pod_network_cidr`). The latter
three (plus `tunnel.network_cidr`) all default to the lab/dev values below if
left unset — only override them if your VPC/pod-network CIDRs differ.

## Input requirements

- Stretch VLANs, names and IPv4 subnets must be unique; VLANs must be 2-4094 and names non-empty.
  VNIs are derived as `10000 + vlan`. Use a network CIDR with prefix length at most 30 and an
  `onprem_gateway` inside it, excluding the network and broadcast addresses. Write the gateway
  without a prefix.
- The three BGP ASNs must be distinct and in 1-4294967295.
- `tunnel.onprem_ip` and `tunnel.cloud_ip` must be distinct IPv4 addresses without prefixes,
  both inside `tunnel.network_cidr` (default `10.44.44.0/24`).
- WireGuard requires `tunnel.port` in 1-65535; other transports do not use it.

## Known limitations (tracked, not fixed by this role)

- The on-prem networking (nmstate, `tasks/nm_networking.yml`) is exercised by
  the Molecule lane against a veth stand-in trunk; it is not yet validated
  against actual hardware or a real tagged customer trunk (source-audit.md).
- Only WireGuard endpoints are configured by this role (development/test use).
  `ipsec` and `direct-connect` select externally configured underlays.
- The FRR templates set no inbound/outbound route policy beyond a
  defensive `maximum-prefix`; see the comment at the top of
  `templates/frr-onprem-appliance.conf.j2`.

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
