# Networking source gaps and CI handoff

[`pipeline-spec.md`](pipeline-spec.md) controls release gates. This note records
source findings and test contracts, not an approved deployment topology.
Baseline: internal [`evpn-on-cloud`
`1c8e88873af8`](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/tree/1c8e88873af8),
rechecked from a local clone on 2026-09-29.

## Verified gap

`ansible/inventory/group_vars/all.yml` selects `tunnel.mtu_mode: unsafe` and
comments that safe mode needs an underlay MTU of at least 1550. The design promises
TCP MSS clamping, but the checked roles do not implement the corresponding
iptables/nftables/MSS tasks. The design's 1399-byte AWS VPN figure is also out of
date (item 3).

Production DX and VPN remain implementation work; WireGuard is development/test
only in CORENET-7498. The task breakdown (§2.1) terminates Site-to-Site VPN
IPsec on the on-prem appliance itself (Libreswan in the bootc image) and on the
AWS TGW, leaving the cloud EVPN relay outside that data path. The appliance is
therefore the AWS customer gateway, with a static, registered public IP (directly
or behind NAT with NAT-T). The prototype image already installs Libreswan
(`image/Containerfile:6`), although the design says Ansible installs it. Keep it in
the image, as image mode requires, cover IKE/IPsec in the FIPS tests, and keep the
tunnel PSKs from the AWS VPN configuration out of logs and inventories.
The WireGuard lab topology forwards through a relay. Tests must identify which role
actually handles each packet before asserting MTU or HA.

## Required handoff to CI/QE

1. Remove `evpn_cloud_workload` from the production deployment and collection
   support surface (CORENET-7515). Any retained lab fixture must be clearly
   separated; the Jira requirement does not force deletion of every lab file.
2. Validate native OCP CUDN/VTEP/frr-k8s configuration on a pinned OCP release.
   Include route advertisements, host routing and global forwarding prerequisites;
   obtain AWS support approval separately from experimental interoperability.
   Model day-2 stretch as a new EVPN CUDN (CORENET-7513); the documented OCP 4.22
   contract does not allow enabling EVPN on an existing CUDN. Include deleting and
   recreating an EVPN CUDN, which teardown and rollback exercise:
   [OCPBUGS-128482](https://redhat.atlassian.net/browse/OCPBUGS-128482) and
   [OCPBUGS-128494](https://redhat.atlassian.net/browse/OCPBUGS-128494)
   (4.22.14; ASSIGNED and New respectively on 2026-10-08) report stale VRF interfaces
   blocking node network startup and an old
   management-port address persisting until ovnkube-node restarts.
   OCP 4.22 documents only `Unmanaged` VTEP mode and recommends a dummy-interface
   address for redundant peering. The product design uses each node's primary VPC
   address, which TGW already routes. A dummy /32 would also need VPC routes (VPC
   Route Server can program them from BGP) and TGW routes (static or TGW Connect).
   [OCPSTRAT-3267](https://redhat.atlassian.net/browse/OCPSTRAT-3267) delivers OCP
   worker peering with Route Server as the BGP Cloud Connector operator (its
   CORENET-7400 child; 1.0 images released September 15). The operator reconciles
   Route Server peers and SourceDestCheck across node lifecycle on AWS and ROSA
   HCP. Align the AWS test topology and VTEP routing with it where designs overlap.
   Agree the method with OCP networking and test it on the supported path
   ([evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).
3. Compute inner MTU from the actual DX or VPN path and selected crypto suite.
   Test CUDN MTU, TCP MSS, DF behavior and oversized-UDP drop without fragmentation
   before AWS reassembly (CORENET-7514/6982). The design's 1550 threshold is correct
   for its case: VXLAN over IPv4 adds 50 bytes (outer IPv4, UDP, VXLAN and the inner
   Ethernet header), so a 1500-byte workload IP MTU needs a 1550-byte underlay IP MTU.
   This assumes no inner VLAN tag or outer IPv4 options; measure the actual encapsulation
   ([VXLAN format](https://www.rfc-editor.org/rfc/rfc7348.html#section-5)).
   Only jumbo DX supplies that budget among the required transports. AWS Site-to-Site VPN
   supports a tunnel MTU of 1446 bytes at most, 1406–1446 depending on cipher, hash and NAT traversal, with no jumbo frames
   and no Path MTU Discovery, so the inner MTU is the configured tunnel MTU minus
   50 (1396 at best; the design's 1399/1349 do not match AWS's current table).
   WireGuard's usual 1420-byte interface leaves 1370. These paths require the
   design's reduced-MTU mode with MSS clamping and a matching CUDN MTU. Clamp inner
   TCP in both directions: at an inner MTU of 1396, MSS is at most 1356 for IPv4
   and 1336 for IPv6, subtracting the fixed headers per
   [RFC 6691](https://www.rfc-editor.org/rfc/rfc6691.html#section-2). AWS's table describes TCP directly
   inside IPsec; its MSS values do not include VXLAN. TGW's own MSS clamping sees
   only the outer UDP of VXLAN, so it does not satisfy 7514. Prove the chosen hook
   sees inner SYN/SYN-ACK packets and uses the overlay budget. MSS does not constrain UDP
   ([AWS VPN MTU](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html#vpn-quotas-mtu),
   [algorithm table](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-best-practice.html),
   [TGW MTU/MSS](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html#mtu-quotas)).
   Throughput limits also differ per path ([AWS VPN
   quotas](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html#vpn-quotas-bandwidth)):
   a standard VPN tunnel carries up to 1.25 Gbps and 140,000 packets per second,
   a large-bandwidth tunnel up to 5 Gbps and 400,000, and a Concentrator tunnel
   100 Mbps. Aggregation across tunnels (ECMP) needs a transit-gateway VPN with
   dynamic routing. VXLAN adds a header to every frame, so record the packet-rate
   ceiling as well as bandwidth in CORENET-7523's per-transport limits.
4. Implement CORENET-7501 using the transit VIF required for a TGW-associated DX gateway; correct its
   "private VIF and TGW associations" wording in Jira in parallel. A Direct Connect
   gateway associated with a TGW needs a transit VIF, while private VIFs attach DX gateways to virtual private
   gateways. The prototype's lab Terraform repeats the private-VIF assumption
   ([source audit](source-audit.md#3-configuration--structure-mismatches)). Verify routes,
   peer ASNs, allowed prefixes and failover on the corrected path.
   Transit VIFs and TGW carry at most 8500 bytes; the design's 9001 is a
   private-VIF value. A transit VIF left at its 1500 default cannot carry VXLAN
   with a 1500-byte workload IP MTU, so preflight must read the VIF's configured MTU and
   jumbo capability. AWS uses a 1500-byte MTU when a Site-to-Site VPN advertises the
   same route, so if VPN backs up DX, size workload MTU/MSS for the smallest
   approved path and test established flows during failover: a new SYN clamp does
   not renegotiate an existing session's MSS.
   TGW performs PMTUD only for traffic entering from VPC and Connect attachments
   ([AWS VIF
   MTU](https://docs.aws.amazon.com/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html),
   [TGW MTU](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html)).
   Record the underlay BGP peer separately from EVPN peers: AWS enables mandatory
   TCP-MD5 on the VIF. If the appliance terminates it, qualify it in the chosen
   FIPS configuration; otherwise record the customer router's responsibility
   ([authentication contract](containerfile-refactor-spec.md#required-outcomes)).
5. Persist deployment-owned networking across reboot, and scope teardown to those
   resources. The source builds its bridges and VXLAN devices with ephemeral
   `ip link` commands and never sets `neigh_suppress`. NetworkManager has no
   supported bridge-port property for that VXLAN port flag
   ([NMT-2900](https://redhat.atlassian.net/browse/NMT-2900) /
   [RHEL-272399](https://redhat.atlassian.net/browse/RHEL-272399), filed September 29;
   a hand-edited keyfile setting may work), so nmstate cannot set it
   ([NMT-2897](https://redhat.atlassian.net/browse/NMT-2897) /
   [RHEL-269118](https://redhat.atlassian.net/browse/RHEL-269118)), and a reapply or
   reconnect clears a manual fix. Ping still passed while local MACs went
   unadvertised. After reboot and reapply, assert the port flags and remote Type-2
   routes for on-prem MACs. Validate AWS ENI source/destination-check configuration
   only where an instance forwards transit traffic; do not disable it
   indiscriminately.
6. Keep on-prem all-active multihoming (LACP/shared Ethernet Segment, Type-1/4,
   DF/BFD, duplicate-BUM suppression) separate from cloud relay ECMP/recovery.
   Exercise traffic, route recovery, serial upgrades and failed-upgrade rollback.
7. Qualify the supported OCP feature combinations: Network Policy allow/deny and
   return traffic across the fabric, selected service types, and ARP suppression
   for learned remote bindings. Basic ping and route presence cannot prove these.
   OCP 4.22 supports Network Policy, egress firewall, QoS and ClusterIP services;
   NodePort, external IP and LoadBalancer addresses require fabric reachability and
   are not advertised automatically. It does not support EgressIP, Egress Service,
   Multiple External Gateways, IP-VRF multicast or native IPsec, and it fixes the
   VXLAN destination port at 4789. The IPsec limit is separate from the required
   AWS Site-to-Site VPN underlay. Reuse the [OVN regression
   cases](prior-art.md#evpn-feature-interaction-tests)
   and bind results to the selected OCP payload and support matrix.
8. Replace `frr_exporter` with `frr-metrics` (CORENET-7499) only after deciding how
   the 5.x binary, which exits outside Kubernetes, runs on an appliance, and close
   the coverage gap it opens for CORENET-7504's VNI/MAC views and VTEP/DF alerts.
   Agree the metric source and expected labels first. Candidate tests must distinguish
   missing required series from intentionally empty healthy/conditional query results;
   use the native rule-test contract in [metrics](pipeline-spec.md#metrics-corenet-74997504).

Sources: [AWS VPC Route
Server](https://docs.aws.amazon.com/vpc/latest/userguide/dynamic-routing-route-server.html),
[AWS DX/TGW](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-transit-gateways.html),
[AWS VPN practices](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-best-practice.html),
[OCP EVPN
prerequisites/limits](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-evpn-for-user-defined-networks),
CORENET-7501/7502/7503/7510/7514 and source `docs/evpn-task-breakdown.md`.
