# evpn_onprem_appliance

Configures the on-prem side of the EVPN fabric: the transport endpoint, the
VLAN trunk interface, per-stretch VXLAN interfaces and bridges, and FRR
configured as the on-prem VTEP.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `stretches`, `trunk_interface`, `bgp`,
`evpn_onprem_appliance_ipsec`, `infra_vpc_cidr`, `workload_vpc_cidr`, `ocp_pod_network_cidr`). The latter
three (plus `tunnel.network_cidr`) all default to the lab/dev values below if
left unset — only override them if your VPC/pod-network CIDRs differ.

## AWS Site-to-Site VPN (`tunnel.type: ipsec`)

This transport is not yet qualified for production (MTU/MSS controls are CORENET-7709;
FIPS validation, hardening and qualification CORENET-7708 and CORENET-7511, including the egress filter and fail-closed boot below). Set `tunnel.onprem_ip` to the appliance VTEP address,
`tunnel.network_cidr` to the network advertised to AWS (default `10.44.44.0/24`, containing the VTEP),
`bgp.onprem_asn` to the customer gateway ASN, and `infra_relay_host` to the relay, which needs a
`private_ip` host variable. `tunnel.cloud_ip` and `tunnel.port` are WireGuard-only.

Supply `evpn_onprem_appliance_ipsec` (schema in [`meta/argument_specs.yml`](meta/argument_specs.yml)) from this
appliance's entry of the AWS role's `evpn_aws_infra_vpn` handoff, which `deploy.yml` does in memory, or from
Ansible Vault; never from plaintext inventory, since Ansible error excerpts can print neighbouring lines.
The only persistent key copy is `/etc/ipsec.d/ega-aws.secrets` (root, `0600`, no diffs); on bootc hosts,
earlier deployments keep their own `/etc` copy until pruned.

The IPsec replacement handler needs python3 3.11 or later (RHEL 10 ships 3.12).
IPsec needs Libreswan 5.0 or later (RHEL 10's; 4.x lacks `leftinterface-ip`). Non-bootc hosts get it
installed; bootc images must ship it with XFRM interface support (tested with 5.4.1), and `/etc/ipsec.conf` and
`/etc/ipsec.secrets` must include `/etc/ipsec.d`, as RHEL's do. The role runs
`ega-aws-1` and `ega-aws-2` as route-based tunnels on `ipsec1` and `ipsec2`, which it reserves, with eBGP to AWS
over each, advertising only `tunnel.network_cidr` and accepting only the two VPC prefixes; EVPN peers with the relay
from `tunnel.onprem_ip`. Other traffic the appliance sends to the VPCs takes the tunnel's 169.254 inside address as
its source, which AWS does not route back, so test reachability from the VTEP address (`ping -I <tunnel.onprem_ip>`).
When one tunnel fails, flows using it stop until BGP notices, up to the 30 s BGP hold time, and then move to
the other tunnel. A connection or key change replaces the tunnels one at a time, a down one first, and fails if a tunnel or its
BGP session is not back within 90 s; later deploys retry until a replacement succeeds. If
deploy reports that another replacement is still running when none is, an `ipsec` command it started is stuck
(for example on a stopped pluto) and holds the lock: restart `ipsec.service`, which briefly drops both tunnels,
check that `lslocks` no longer lists `/etc/ipsec.d/ega-aws.lock`, then rerun deploy. Do not delete the lock file
instead: a new file is a second lock, so two replacements could run at once.
Libreswan loads both tunnels' keys at once, so after a bad key change the other tunnel also fails at its next
re-authentication: correct the keys and redeploy promptly. While neither tunnel provides a route to a VPC,
policy rules drop traffic to both VPC prefixes, so a covering route cannot send it unencrypted. A route more
specific than a VPC prefix still wins, even with both tunnels up, and sends that traffic (VXLAN and EVPN BGP
included) unencrypted: install none, and keep DHCP classless static routes (option 121) off the uplink, until
CORENET-7511's egress filter. The rules live on the VTEP's NetworkManager profile, so at boot they apply once NetworkManager
activates it, together with the VTEP address. Until then, appliance-originated traffic to the VPC prefixes could
leave unencrypted; VXLAN cannot, because the VTEP address does not exist yet. On real VM boots NetworkManager
installed the rules with or before the uplink's default route and no cleartext left, but that ordering is not
guaranteed (a fail-closed boot is CORENET-7511). Changing a VPC prefix or `tunnel.onprem_ip` needs a teardown first, because nmstate keeps the old rules. FRR applies configuration
changes in place (`evpn_frr`); a new AWS inside address or ASN resets that tunnel's BGP session. Teardown
removes only the role's connections, keys and rules, plus any XFRM policies, states and interfaces (`ipsec1`,
`ipsec2`) left with the reserved if_id 1 or 2, even when pluto is stopped; it removes `ega-aws.conf` last, so a
rerun retries a failed removal, and leaves if_ids 1 and 2 alone on a host without that file. It leaves other Libreswan connections
running and the Libreswan service enabled; with no appliance connections it carries no traffic, so disable it if nothing else uses it. IPsec
assumes one relay (relay HA is CORENET-7503).

The host needs reachability to both AWS endpoints on UDP 500 and 4500 (or ESP without NAT); the role
configures no host firewall. While AWS maintenance has one endpoint down, deploy's health checks fail until it
returns, and a deploy that changes the IPsec configuration fails after 90 s until both are up.

MTU budget (a limit, not enforced): AWS VPN tunnels carry at most 1446 bytes, or 1438 with
NAT-T and AES-GCM, and VXLAN adds 50, leaving a 1388-byte workload MTU behind NAT-T (1396
without; inner TCP MSS 1348 for IPv4, 1328 for IPv6, at 1388); AWS VPN does not support path MTU discovery
([VPN quotas](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html)). There is no
MTU/MSS/DF control yet (CORENET-7709).

## Known limitations (tracked, not fixed by this role)

- The on-prem networking (nmstate, `tasks/nm_networking.yml`) is exercised by
  the Molecule lane against a veth stand-in trunk; it is not yet validated
  against actual hardware or a real tagged customer trunk (source-audit.md).
- `direct-connect` is not implemented yet (CORENET-7708), so the argument specs reject it:
  WireGuard's paths would add a TGW static route that overrides routes learned over Direct Connect.
- WireGuard and EVPN have no inbound/outbound route policy beyond a
  defensive EVPN `maximum-prefix`; IPsec underlay IPv4 has the VPC/VTEP prefix
  lists described above. See the comment at the top of
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
