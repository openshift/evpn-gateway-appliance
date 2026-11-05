# evpn_onprem_appliance

Configures the on-prem side of the EVPN fabric: the transport endpoint, a
tagged VLAN trunk carrying one sub-interface per stretch, per-stretch VXLAN
interfaces and bridges, and FRR configured as the on-prem VTEP. The role
drives NetworkManager through nmstate, so that package must be installed on
the target.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `stretches`, `trunk_interface`, `frr_image`, `bgp`,
`infra_vpc_cidr`, `workload_vpc_cidr`, `ocp_pod_network_cidr`). The latter
three (plus `tunnel.network_cidr`) all default to the lab/dev values below if
left unset — only override them if your VPC/pod-network CIDRs differ.

## Known limitations (tracked, not fixed by this role)

- The role replaces the NetworkManager profile on `trunk_interface` with
  `ega-port-<trunk_interface>` and gives that interface no address. A trunk
  interface that carries the management connection will disconnect the host.
- The VXLAN `neigh_suppress` port flag cannot be expressed by nmstate. A
  NetworkManager dispatcher sets it when the interface comes up, so a reapply
  that emits no up event leaves it unset until the next deploy or boot.
- `tunnel.type: wireguard` is the only implemented transport. `ipsec` and
  `direct-connect` are accepted values but have no implementation yet —
  production requires Direct Connect or Site-to-Site VPN.
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
    trunk_interface: eth0
    frr_image: quay.io/frrouting/frr:10.5.3
```
