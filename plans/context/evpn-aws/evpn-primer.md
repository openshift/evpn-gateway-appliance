# EVPN Technical Primer

Quick reference for someone coming from the Konflux/release side.

## What EVPN Is (30 seconds)

BGP-based control plane for virtual networks. VTEPs exchange learned MAC/IP
reachability instead of relying only on flooding. Unknown/broadcast traffic still
exists and must be tested. The data plane here is VXLAN (24-bit VNI).

## Key Terms

| Term | Plain English |
| ------ | --------------- |
| VTEP | Tunnel endpoint that wraps/unwraps VXLAN packets |
| VNI | VXLAN tenant ID (like a VLAN ID but 24-bit) |
| FRR / frr-k8s | FRRouting BGP daemon; frr-k8s is its K8s DaemonSet wrapper |
| MAC-VRF | L2 tenant domain in EVPN |
| IP-VRF | L3 tenant domain in EVPN |
| UDN | User Defined Network — OVN-K's tenant network abstraction |
| P-CUDN | Primary Cluster UDN — the one exposed via EVPN |
| RouteAdvertisements CR | Links a network to a BGP config in OVN-K |
| Type-1 route | BGP advertisement of an Ethernet Auto-Discovery route (for multihoming) |
| Type-2 route | BGP advertisement of a MAC, optionally with its IP address (L2 EVPN) |
| Type-3 route | BGP advertisement for inclusive multicast (BUM traffic) |
| Type-4 route | BGP advertisement of an Ethernet Segment (for multihoming designated forwarder election) |
| Type-5 route | BGP advertisement of an IP prefix (L3 EVPN) |
| ARP suppression | Nodes can answer ARP locally for known BGP-learned bindings, reducing flooding |
| BUM traffic | Broadcast/Unknown/Multicast — carried by controlled replication; not eliminated by EVPN |
| IRB | Integrated Routing and Bridging — L2+L3 in one node |
| bootc | Tool that installs and updates an OS from a container image; the appliance uses image-mode RHEL |

## Deployment topology

Conceptual placement only; the supported transport's packet path still requires
networking/QE approval in [the networking handoff](networking-spec.md).

```text
On-prem VLANs (for example VMware/NSX segments)
        │ 802.1Q trunk
Migration appliance ── VTEP: maps VLANs to VNIs, speaks BGP EVPN
        │ Direct Connect (transit VIF) or Site-to-Site VPN (IPsec from the appliance)
AWS Transit Gateway ── routes outer IP packets only
        ├── Infra VPC relay ── BGP EVPN only, next-hop-unchanged, no VXLAN
        └── OCP worker nodes ── VTEPs through OVN-K EVPN and frr-k8s

BGP EVPN: appliance ⇄ relay ⇄ workers.  VXLAN data: appliance ⇄ workers directly.
```

## OKEP-5088 (the OVN-K design)

- OVN-Kubernetes adds EVPN support for Primary CUDNs in OCP 4.22
- FRR runs as a DaemonSet on every node (via frr-k8s)
- New VTEP CRD; ClusterUserDefinedNetwork gains `transport: EVPN`; the existing
  RouteAdvertisements CRD (from OCP BGP support) advertises the network
- Supports both L2 (MAC-VRF) and L3 (IP-VRF) modes
- Published OCP 4.22 documentation limits native EVPN support to bare-metal
  clusters. EVPN-on-AWS needs both interoperability qualification and an explicit
  support decision; 4.22 availability alone does not prove AWS support.

## AWS packet-path distinction

The diagram shows the proposed DX and VPN paths from the task breakdown, where the
relay carries only BGP; it is not proof of an approved or deployed production topology.
In the WireGuard lab (development only) the tunnel terminates on the relay,
which is then in the forwarding path, so lab results do not describe production
throughput, MTU or failover.

On-prem migration appliances attach local workloads to the overlay. Their
all-active Ethernet Segment uses Type-1/4 routes; cloud relay HA instead concerns
ECMP, session recovery and preserving endpoint connectivity. L2 stretch uses
Type-2/3 routes. Type-5 belongs to the IP-VRF (L3) variant, which an L2 CUDN can also
add on top of its MAC-VRF; its supported scope needs a separate decision under the
parent feature.

See [OCP EVPN
documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-evpn-for-user-defined-networks)
and [`networking-spec.md`](networking-spec.md) for the release-test implications.
