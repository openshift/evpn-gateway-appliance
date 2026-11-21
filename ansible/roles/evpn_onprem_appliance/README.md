# evpn_onprem_appliance

Configures the on-prem side of the EVPN fabric: the transport endpoint, the
VLAN trunk interface, per-stretch VXLAN interfaces and bridges, and FRR
configured as the on-prem VTEP.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema (`tunnel`, `stretches`, `trunk_interface`, `frr_image`, `bgp`,
`evpn_onprem_appliance_ipsec`, `infra_vpc_cidr`, `workload_vpc_cidr`, `ocp_pod_network_cidr`). The latter
three (plus `tunnel.network_cidr`) all default to the lab/dev values below if
left unset — only override them if your VPC/pod-network CIDRs differ.

## AWS Direct Connect (`tunnel.type: direct-connect`)

Not yet qualified on a real circuit (CORENET-7498). The customer's network carries
the underlay: a customer router terminates the transit VIF's BGP session (AWS
requires MD5, which FIPS-mode kernels disable), routes `tunnel.network_cidr` to
the appliance and advertises it over the VIF. Set `tunnel.next_hop` to that
router's address on the appliance's uplink: FRR routes `infra_vpc_cidr` and
`workload_vpc_cidr` to it, naming the uplink that reaches it; as for IPsec,
policy rules drop VPC traffic while the uplink is down. Add no other routes
or policy routing for those CIDRs (kernel, NetworkManager or another daemon):
zebra can leave BGP next hops over kernel routes unresolved after the uplink's
carrier returns, and the preflight refuses any route FRR did not install. The role does
not configure the uplink, which must not be `trunk_interface`: give it an
address on `tunnel.next_hop`'s subnet, outside `tunnel.network_cidr`, and an MTU
of at least 1550. It configures no tunnel and no underlay BGP. As with IPsec,
nmstate owns `ega-vtep` (`tunnel.onprem_ip/32`), and the EVPN neighbor is the
relay's `private_ip`, with source `tunnel.onprem_ip` and only the `l2vpn evpn`
address family; both ends use `ebgp-multihop 255`, since the customer's routed
path has an unknown hop count. `tunnel.cloud_ip` and `tunnel.port` are not used.
It serves one appliance without multihoming (CORENET-7502). The
transport preflight requires `tunnel.mtu_mode: safe` until the reduced-MTU
controls (CORENET-7709) exist.

## AWS Site-to-Site VPN (`tunnel.type: ipsec`)

This transport is not yet qualified for production (MTU/MSS controls are CORENET-7709;
FIPS and hardening CORENET-7708). Set `tunnel.onprem_ip` to the
appliance VTEP address, `tunnel.network_cidr` to the network advertised to AWS
(default `10.44.44.0/24`), and `bgp.onprem_asn` to the AWS customer gateway ASN.
Set `infra_relay_host` to the relay inventory hostname with a `private_ip` host
variable. `tunnel.cloud_ip` and `tunnel.port` are used only by WireGuard.

IPsec assumes one relay (`hostvars[infra_relay_host]`); the appliance activates IPv4
unicast only on the two AWS inside peers (with prefix lists) and L2VPN EVPN only on
the relay address.

Supply `evpn_onprem_appliance_ipsec` from this appliance's entry in the secret `evpn_aws_infra_vpn` handoff
or an equivalent dictionary that is vault-encrypted (never plaintext inventory: Ansible error
excerpts can print neighbouring source lines); see the AWS role's
[returned facts](../evpn_aws_infra/README.md#inputs-and-returned-facts) and this role's
[argument spec](meta/argument_specs.yml) for the handoff schema.

Never log or persist the handoff. Validation and tasks reading keys use
`no_log`; the only persistent PSK copy managed by this role is
`/etc/ipsec.d/ega-aws.secrets` (root-owned, mode `0600`, diffs disabled).

The role installs Libreswan on non-bootc hosts; bootc images must already
contain Libreswan with XFRM interface support (tested with CentOS Stream 10's 5.4.1). It manages
`/etc/ipsec.d/ega-aws.conf` and the secrets file and enables the `ipsec` service; the
packaged `/etc/ipsec.conf` and `/etc/ipsec.secrets` must include `/etc/ipsec.d`, as RHEL's
do. A change to the connections or keys replaces `ega-aws-1` and `ega-aws-2` one at a time, a tunnel that is
already down first, without restarting other Libreswan connections. It runs after any FRR restart, and if a tunnel or its BGP session isn't
back within 90 s or a Libreswan command fails, it stops with an error. Libreswan loads both tunnels' keys at once, so
after a bad key change the tunnel not yet replaced also fails at its next re-authentication; correct the keys and redeploy promptly.
Only a successful replacement records the applied files, so later deploys replace both tunnels until one
succeeds, even after an interrupted run; an IPsec restart or reboot before then loads the new connections. The appliance
initiates `ega-aws-1` and `ega-aws-2` with the tunnel profile pinned on the AWS side
(see the `evpn_aws_infra` README), plus DPD delay 10 seconds and retransmit timeout
40 seconds. On bootc hosts, earlier deployments keep their own copy of `/etc`,
including the secrets file, until they are pruned. The `0.0.0.0/0` selectors are route-based IPsec policy only;
neither BGP nor VPC routes ever carry `0.0.0.0/0`.

Libreswan manages `ipsec1`/`ipsec2` with `leftupdown=""` and `overlapip=yes`,
while nmstate owns `ega-vtep` (`tunnel.onprem_ip/32`, profile `ega-dummy-vtep`) for VXLAN.

FRR peers with both AWS inside addresses using eBGP and timers `10 30`,
advertises only `tunnel.network_cidr`, and accepts only `infra_vpc_cidr` and
`workload_vpc_cidr` exactly. The network's blackhole route ensures it can be
advertised. The EVPN neighbor is
the relay's `private_ip`, with `ebgp-multihop 4`, source
`tunnel.onprem_ip`, and only the `l2vpn evpn` address family. Existing VNI
blocks and the EVPN maximum-prefix limit remain in place. VXLAN traffic
flows directly through the VPN/TGW to workload VTEPs.
Failover relies on BGP timers `10/30`, Libreswan DPD (10 s delay, 40 s retransmit timeout) and AWS DPD action `clear`.
While neither tunnel provides a route to a VPC, policy rules on `ega-dummy-vtep` drop traffic to `infra_vpc_cidr`
and `workload_vpc_cidr` rather than send it unencrypted by another route; it flows again when a tunnel's BGP
session returns. Teardown removes the rules with `ega-vtep`.
An FRR configuration change, such as a new inside address or ASN, restarts FRR and briefly drops both AWS BGP sessions.

Teardown unloads the two owned connections and
their SAs if Libreswan is running, removes the owned connection configuration/secrets, and rereads
secrets, leaving unrelated loaded connections running.

The host needs reachability to both AWS public endpoints (IKE/UDP 500 and
NAT-T/UDP 4500, or ESP without NAT). This role does not configure a host
firewall.

MTU budget (a limit, not enforced): AWS VPN tunnels carry at most 1446 bytes, or 1438 with
NAT-T and AES-GCM, and VXLAN adds 50, leaving a 1388-byte workload MTU behind NAT-T (1396
without; inner TCP MSS 1348 for IPv4, 1328 for IPv6, at 1388); AWS VPN does not support path MTU discovery
([VPN quotas](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html)). There is no
MTU/MSS/DF control yet (CORENET-7709). This is the two-tunnel AWS TGW case only, without
Direct Connect or HA.

## Known limitations (tracked, not fixed by this role)

- The on-prem networking (nmstate, `tasks/nm_networking.yml`) is exercised by
  the Molecule lane against a veth stand-in trunk; it is not yet validated
  against actual hardware or a real tagged customer trunk (source-audit.md).
- WireGuard and EVPN have no inbound/outbound route policy beyond a
  defensive EVPN `maximum-prefix`; IPsec underlay IPv4 has the VPC/VTEP prefix
  lists described above. See the comment at the top of
  `templates/frr-onprem-appliance.conf.j2`.
- Libreswan 5.4 may hold extra Child SAs on the surviving tunnel for up to an hour after the
  other is torn down or fails to come back; AWS documents one SA pair per tunnel, so the AWS canary must
  confirm traffic is unaffected.

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
    frr_image: quay.io/frrouting/frr:10.5.3
```
