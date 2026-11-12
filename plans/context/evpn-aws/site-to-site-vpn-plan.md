# AWS Site-to-Site VPN transport

CORENET-7500 proposal (assignee Daniel Farrell; Jira acceptance criteria absent on 2026-11-10). [Provisioning](../../../ansible/roles/evpn_aws_infra/tasks/main.yml)
creates Transit Gateway (TGW), but no VPN; [pending #23’s discovery](https://github.com/openshift/evpn-gateway-appliance/blob/c1e84985ad3dbf6691ff90d57c01222d06748ae9/ansible/playbooks/discover_peers.yml)
and [relay](https://github.com/openshift/evpn-gateway-appliance/blob/c1e84985ad3dbf6691ff90d57c01222d06748ae9/ansible/roles/evpn_cloud_infra/templates/frr-infra-relay.conf.j2)
are not baseline. AWS OpenShift tests remain experimental.
Test Platform must approve [identity containment and cancellation
cleanup](#aws-test-approvals), and each AWS lane must prove cancellation cleanup within its grace period before it is enabled. Record [owner, date and evidence](kickoff-decisions.md).

## Delivery and proof

### Questions for owner decision

1. Jaime Caamano (7498), consulting Vincenzo Palmieri (7515): choose Transit Gateway (TGW) or virtual private gateway (VGW).
2. Who approves AWS (non-bare-metal) EVPN support, or an exception?
3. Who takes 7501 and records its corrected [virtual-interface (VIF) criterion](source-audit.md#3-configuration--structure-mismatches) before acceptance?
4. Who owns cluster isolation, multipath and BGP Cloud Connector (BCC) coordination for FRR, RouteAdvertisements and primary-ENI SourceDestCheck?
5. Name a coordinator for [relay availability and multihoming](#evpn-peering), transport, security, and CI budgets, gates and cleanup.
6. OpenShift Virtualization (CNV): set migration goodput, dirty rate, concurrency and recovery, and validate the [prototype’s](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af80ea66f6b111638ca1453275cc4e2/docs/design.md) expected migration failure at reduced MTU ([HPSTRAT-714](context.md)).
7. Networking and CI owners: approve the dev/test IPsec migration. Architecture: agree transport MTUs. 7515 and 7708 owners: approve the [authentication and limits](#test-obligations) for IPsec and the emulated AWS endpoint.
8. Keep or remove the WireGuard code path after migration?
9. Who supplies the funded AWS account, IAM user, cluster-secrets bundle and IPI Route53 base domain?
10. Test Platform: approve VPN readback in a dedicated account/Region without unrelated VPNs; readback exposes [pre-shared keys](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_TunnelOption.html) and cannot be restricted by tag.
11. Test Platform: approve each lane's cancellation grace period and reapers for gateways, VPNs and Elastic IPs.
12. Choose installer credentials: [mint](https://github.com/openshift/openshift-docs/blob/21de7e2d64fab1a65ba8ca4795e7f79591212049/modules/cco-about-default-behaviors.adoc) with [contained users, roles and keys](https://github.com/openshift/openshift-docs/blob/21de7e2d64fab1a65ba8ca4795e7f79591212049/modules/mint-mode-permission-requirements.adoc), or manual mode with AWS STS and no user or key creation.
13. Jaime and CI/QE owners: choose AWS lane cadence and gates.
14. Agree ownership: [7708](https://redhat.atlassian.net/browse/CORENET-7708) handles IPsec and DX host behavior and validation; [7500](https://redhat.atlassian.net/browse/CORENET-7500) handles AWS lifecycle, configuration handoff and acceptance.

### Ranked evidence spikes

1. Review support, topology and cloud permissions with owners and Test Platform:
   30–60 minutes, $0 cloud.
2. Prepare local IPsec regression in half–one day, then run 30–60-minute routing,
   /32-filter, tunnel and churn tests; hosts cost extra.
3. Run a one-hour AWS canary with FRR routing software for ~$0.45 with TGW or
   ~$0.30 with VGW.

### Implementation order

After the [spikes](#ranked-evidence-spikes), qualify OpenShift, including second-cluster
isolation and cleanup.

Dev/test migration:

1. Implement `tunnel.type: ipsec` in the collection (currently accepted but unimplemented),
   including two tunnels, routing, health checks and teardown.
2. Switch the emulation lane to the Libreswan profile below, with a separate AWS-endpoint
   fixture; move VXLAN forwarding off the EVPN relay.
3. Compare for one week: L2, BGP, MTU, MSS, failover and CI duration.
4. After equivalent coverage passes, drop WireGuard from CI, then from image packages and defaults.

Estimate: 5–8 engineering days (collection 3–5, fixture 1–2, comparison/cleanup 1), excluding
owner review and AWS approval. Local IPsec has no VPN charges; qualify kernel IPsec on a root-privileged runner before switching CI (provisionally ~2–5 extra minutes per run).

Four daily one-hour TGW/FRR runs cost ~$1.79; four-hour nightly OpenShift costs
~$6.32 (one cluster) or $11.13 (two). See [assumptions](#cost-assumptions).
Budget separately: an ≥8-hour natural-rekey soak, and two hosted DX connections if gateway selection is deferred. Estimates exclude bootstrap, LB/NAT, storage, licensing, data, DX ports/partners and metal/CNV.
Allow 1–2 hours for OpenShift [routing checks](#vteps-and-gateway); the two-cluster network costs $0.265/hour plus extras.
Cap capacity/failover at two hours: $0.43 standard or $1.53 large, for network plus customer gateway IP.

## Gateway and CI choices

### Gateway options

VPC means virtual private cloud.

| Gateway | Fit and trade-off |
| --- | --- |
| TGW hub | [Shared infra relay with availability independent of clusters](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af80ea66f6b111638ca1453275cc4e2/docs/design.md); attachment/data fees and isolation policy |
| VGW | Minimal cluster-local relay; lower single-VPC cost; an independent relay adds a [VPN](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPC_VPN.html) per VPC and [direct cluster peerings](https://docs.aws.amazon.com/vpc/latest/peering/vpc-peering-basics.html); no transit hub |

See the [routing checks](#vteps-and-gateway) and [cost model](#cost-model).

### CI on Prow

| Lane | Fixture | Coverage and limits |
| --- | --- | --- |
| Proposed local IPsec | Two-tunnel Libreswan/FRR AWS-endpoint fixture; no OpenShift | Does not test managed VPN, TGW/VGW routing, AWS ECMP or route limits. Non-FIPS hosts cannot qualify production FIPS behavior. |
| AWS + FRR | Proposed canary: TGW/VGW, two real VPN tunnels, FIPS-enabled candidate CGW, separate EC2 relay; no OpenShift | Managed VPN, routing, ECMP, limits, CGW public IP, NAT-T and RHEL FIPS. Replace tunnels; record MED and failover; claim maintenance coverage only when observed. |
| AWS + [IPI](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/aws/ovn/ipi-aws-ovn-workflow.yaml) | AWS canary plus OpenShift; 4.22 → 5.x update if offered | OCP routing and MTU; nonzero EVPN cases per version. Adapt the [external FRR peer](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/openshift/test/infraprovider/openshift.go) from bare-metal setup or provide equivalent EGA assertions. Stock [non-metal workers](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/conf/aws/ipi-conf-aws-ref.yaml); no CNV. |

[Baremetalds](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/baremetalds/e2e/bgp-vip/ovn-bgp/evpn/verify/baremetalds-e2e-bgp-vip-ovn-bgp-evpn-verify-commands.sh) runs supported bare-metal EVPN but not AWS interfaces.

## Implementation detail

### Requirements and scope

7498 requires AWS VPN and Direct Connect (DX) and limits WireGuard to development/test;
it does not require WireGuard there.
Evidence reflects [baseline 0cd313a](https://github.com/openshift/evpn-gateway-appliance/tree/0cd313a6194ee1b3697b9389f249c675f7e74040), rechecked 2026-11-11.
Target 4.22 (7498's minimum) and 5.x ([OCPSTRAT-3413](https://redhat.atlassian.net/browse/OCPSTRAT-3413) targets 5.1 with 4.22 backports); decision 18 sets the matrix.
OpenShift Ethernet VPN (EVPN), identical in [4.22](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/nw-bgp-evpn-about.adoc) and [5.0](https://github.com/openshift/openshift-docs/blob/a9790d0b28faa2df30204aa69ddc7e65959d2e1e/modules/nw-bgp-evpn-about.adoc), supports primary cluster user-defined networks (CUDNs) only on bare metal;
[Virtualization excludes public-cloud EVPN](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/conditional-virt-choose-a-vm-networking-topology.adoc). AWS `.metal` uses [platform AWS](https://github.com/openshift/installer/blob/0b8b4f3205a7a7d0101e7e41595363f2ab2730f4/pkg/asset/manifests/infrastructure.go).
[7498](https://redhat.atlassian.net/browse/CORENET-7498) and [OCPSTRAT-3413](https://redhat.atlassian.net/browse/OCPSTRAT-3413) seek AWS enablement; checked criteria/comments grant no exception.

7515 owns native OpenShift integration;
7709 owns MTU, TCP segment sizing (MSS) and do-not-fragment (DF) controls.
7514 qualifies internet mode, 7511 owns security/FIPS, and [CNV-98581](https://redhat.atlassian.net/browse/CNV-98581) reviews VM coverage.

### VTEPs and gateway

Use [Unmanaged](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/procedure-enabling-bgp-evpn-primary-cudn.adoc) elastic network-interface (ENI) IPv4 VXLAN endpoints (VTEPs),
as [OVN permits](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/docs/features/bgp-integration/evpn.md).

[TGW VPN](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html) supports equal-cost multipath routing (ECMP) and up to 1.25 Gbps/tunnel, or 5 Gbps Large Bandwidth Tunnels
at $0.60/hour/connection. VGW caps at 1.25 Gbps/tunnel without ECMP/large tunnels.
[Customer gateway (CGW) dynamic advertisement limits](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html) are 1,000 (TGW) or 100 (VGW).
DX requires [transit VIF → DX gateway → TGW](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-transit-gateways.html) (maximum [MTU](https://docs.aws.amazon.com/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html) 8500),
or [private VIF → VGW](https://docs.aws.amazon.com/directconnect/latest/UserGuide/create-private-vif.html) in the same Region and [DX gateway](https://docs.aws.amazon.com/directconnect/latest/UserGuide/virtualgateways.html) across Regions
(maximum MTU 9001).

Cluster VPNs carry VXLAN; separate relay BGP sessions avoid transitive peering.
[One DX gateway supports 20 VGWs](https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html).

Require isolated, nonoverlapping VPC ranges. Associate each TGW attachment
[with one lookup table; propagate into selected tables](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html).
Add static [VPC subnet routes](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpc-attachments.html) through TGW for on-premises VTEP/control and infrastructure/cluster
control traffic; propagation does not update VPC tables. Enable required availability zones.
Filter advertised prefixes at their BGP source. During migration remove owned lab routes
through the infrastructure attachment and relay interface that would bypass IPsec/DX;
same-prefix statics override propagation. Assert routes and capture relay traffic.
At cutover stop and disable `wg-quick@wg0` on both former WireGuard endpoints; after reboot verify `wg0` and its routes stay absent.
Test both tunnels, [VGW asymmetry](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-route-priority.html) and compatible TGW ECMP without assuming single-flow aggregation.

Verify primary-ENI annotations and [all node subnets](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/go-controller/pkg/clustermanager/vtep/controller.go);
[discovery](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/go-controller/pkg/node/controllers/evpn/evpn_node_controller.go) does not automatically identify primary ENIs.
TGW propagation into the [VPN attachment’s table](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html) advertises VPC CIDRs over VPN;
VGW advertises its VPC CIDR.
At relay/appliance IPv4 ingress, reject [OCP VTEP /32s](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/go-controller/pkg/clustermanager/routeadvertisements/controller.go) and VPC/control leaks;
preserve EVPN next hops and independent VTEP covering routes.
OVN-Kubernetes RouteAdvertisements accepts only /32 routes within cluster VTEP CIDRs;
7515 must allow the on-premises VTEP prefix, and tests must assert its installation on workers.
Test withdrawal/replacement, security groups/ACLs, UDP 4789, TCP 179,
return paths and source/destination checks.

### EVPN peering

Current appliance BGP is single-hop on the WireGuard inner address; workload sessions are multihop.
For proposed dev/test IPsec and production VPN/DX, peer from an advertised on-premises EVPN address
(update-source, ebgp-multihop) distinct from the IPsec endpoint.
Consult 7515 on per-cluster discovery, autonomous system numbers, route targets and peering.
Keep underlay BGP on each IPsec inside /30 separate from these EVPN sessions.
[7503 owns relay high availability; 7502 owns multihoming](delivery-plan.md).

### Direct Connect

Order DX labs after gateway selection:
each hosted [connection](https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html) permits one VIF, non-adjustable. A DX gateway associated with a VGW/private VIF
cannot attach to TGW.
[Allowed prefixes](https://docs.aws.amazon.com/directconnect/latest/UserGuide/allowed-to-prefixes.html) originate TGW advertisements or filter VGW VPC CIDRs;
they do not install forwarding routes.
[Quotas](https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html) are 200 AWS-to-on-premises prefixes per TGW (IPv4 and IPv6 together)
and, by default, 100 on-premises prefixes per address family per BGP session, configurable to 1,000.
Qualify DX MTU and failover per the [networking handoff](networking-spec.md#required-handoff-to-ciqe).

### BGP Cloud Connector

Do not make 7500 depend on BCC. Test startup/deletion to prove its [broad selector](https://github.com/openshift/bgp-cloud-connector/blob/59f8b4b12a6edb33a70e9a04b74009318aff8c48/internal/controller/routeadvertisements.go) cannot advertise PodNetwork routes to EVPN peers.
[BCC 59f8b4b1](https://github.com/openshift/bgp-cloud-connector/blob/59f8b4b12a6edb33a70e9a04b74009318aff8c48/docs/cloud-integration.md) reconciles per-AZ Route Server peers and disables primary-ENI
source/destination checks. Infrastructure owners supply servers/endpoints,
table associations and propagation. Its [CUDNs](https://github.com/openshift/bgp-cloud-connector/blob/59f8b4b12a6edb33a70e9a04b74009318aff8c48/internal/controller/clusterudn.go) provide L3, not EVPN;
[Route Server](https://docs.aws.amazon.com/vpc/latest/userguide/dynamic-routing-route-server.html) updates VPC tables, not TGW.
Return routes must target the selected TGW or [VGW via VPC route propagation/explicit routes](https://docs.aws.amazon.com/vpc/latest/userguide/route-table-options.html#route-tables-vgw), never workers.

### Test obligations

Use Libreswan at both ends of local/CI emulation: [already installed](../../../image/rhel10/Containerfile),
[RHEL-supported and FIPS-capable](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_and_managing_networking/index).
Emulate one route-based VPN connection:

- [Two tunnels](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html) with separate outside endpoints.
- FRR BGP over a distinct, nonreserved link-local /30 per tunnel (AWS: keepalive 10 s, hold 30 s).
- CGW-side NAT.

Pin the same explicit [AWS-supported tunnel options](https://docs.aws.amazon.com/vpn/latest/s2svpn/tunnel-configure.html) in emulation and the AWS canary:

- IKEv2 only; IKE AES256-GCM-16 with SHA2-256 PRF, DH14; ESP AES256-GCM-16, PFS14 ([RHEL 10 FIPS disables CBC except for Kerberos](https://gitlab.com/redhat/centos-stream/rpms/crypto-policies/-/blob/0f4ff0ce0fd83b10e46d0d2afaae6ada14ce4e2e/crypto-policies.spec); confirm against the candidate's crypto-policies).
- Pre-shared keys: random per run, 64 characters, FIPS-strength; alphanumerics, periods and underscores; no leading zero.
- AWS defaults: DPD 40 s with `Clear`; startup `Add` (CGW initiates); lifetimes IKE 28,800 s, ESP 3,600 s; rekey margin 270 s, fuzz 100%.

[Libreswan](https://libreswan.org/man/ipsec.conf.5.html) needs [`uniqueids=no`](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-best-practice.html) and a nonzero `dpddelay` (IKEv2 times out via `retransmit-timeout`); compare observed DPD/rekey timing in the AWS canary.
NAT-T with [AES-GCM-16](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-best-practice.html) gives tunnel MTU 1438, MSS 1398.
IPv4 VXLAN costs 50 bytes: workload MTU 1388; inner TCP MSS 1348 (IPv4), 1328 (IPv6).
Apply that same budget and bidirectional inner MSS clamp locally and in AWS; test oversized UDP/DF
without relying on [PMTUD (unsupported by AWS VPN)](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html).
Test IKE and ESP rekeys from each peer with continuous forwarding; Libreswan's fuzz makes the CGW rekey first, so disable CGW rekey initiation in one canary phase.

Read back both tunnels’ [TunnelOptionSet via DescribeVpnConnections](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_VpnConnectionOptions.html)
and negotiated algorithms via [GetActiveVpnTunnelStatus](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_GetActiveVpnTunnelStatus.html); assert the returned parameters and check the negotiated SHA2-256 PRF on the CGW (the API omits the PRF).
Exercise [initiation](https://docs.aws.amazon.com/vpn/latest/s2svpn/initiate-vpn-tunnels.html), [dead-peer detection/rekey](https://docs.aws.amazon.com/vpn/latest/s2svpn/tunnel-configure.html),
[maintenance routing preferences (MED)](https://docs.aws.amazon.com/vpn/latest/s2svpn/routing-vpn-tunnel-updates.html), failover and coordinated
[AWS/host pre-shared-key changes](https://docs.aws.amazon.com/vpn/latest/s2svpn/modify-vpn-tunnel-options.html).
Pin appliance, kernel, IPsec, FRR and OpenShift payloads; test reboot and FIPS.
Reuse [OVN EVPN](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/test/e2e/evpn.go) and [OpenPERouter reflector](https://github.com/openperouter/openperouter/blob/4d69e363fd75b234e258bde4c4252130b50fbe62/e2etests/tests/route_reflector.go) cases against EGA artifacts.

Qualify large tunnels separately.
On relay loss, measure the EVPN forwarding outage and MAC flush time; assert VPN tunnels
and underlay BGP stay up. 7503/7515 must qualify [graceful restart](https://docs.frrouting.org/en/latest/bgp.html#bgp-gr-support-for-l2vpn-evpn).

### Cost model

[Oregon fixtures](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/us-west-2/index.json) include one VPN, two IPv4s and attachments ([billing](https://aws.amazon.com/vpn/pricing/)).

| Network fixture | Hourly | If leaked 24 h |
| --- | --- | --- |
| VGW, one cluster VPC | $0.06 | $1.44 |
| TGW: infra, one cluster | $0.21 | $5.04 |
| TGW: infra, two clusters | $0.26 | $6.24 |
| Large TGW: infra, one cluster | $0.76 | $18.24 |

Added cluster/DX attachments cost $0.05/hour; [TGW ingress](https://aws.amazon.com/transit-gateway/pricing/) costs $0.02/GB.
Route Server costs $0.75/endpoint-hour; CGW IPv4 costs $0.005/hour.

### Cost assumptions

FRR assumes a native AMI, m6i.xlarge CGW and two t3.small relay/peer instances:
~$0.23 [Linux compute](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/US%20West%20%28Oregon%29/Linux/index.json) plus $0.215 TGW network/hour.
OpenShift uses six m6i.xlarge instances/cluster plus CGW and relay.
Durations are assumed.

### CI setup and fixtures

Keep the Cluster Network Operator (CNO) managed while applying
[route advertisements/FRR provider](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/nw-route-advertisements-enable.adoc) and [local gateway/global IP forwarding](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/procedure-enabling-bgp-evpn-primary-cudn.adoc).
PerfScale [5.0 network-workloads (14h)](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/config/openshift-eng/ocp-perfscale/openshift-eng-ocp-perfscale-main__aws-5.0-nightly-x86.yaml) includes EVPN [setup](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift-qe/bgp-setup/openshift-qe-bgp-setup-commands.sh);
[5.1 evpn (6h)](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/config/openshift-eng/ocp-perfscale/openshift-eng-ocp-perfscale-main__aws-5.1-nightly-x86.yaml) omits it. Setup unmanages the Cluster Version Operator and CNO
and replaces FRR; neither proves EGA parity.

Use an unattached customer VPC with [static public IP](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-options.html), UDP 500/4500 and no bypass route.
Nested fixtures need [supported KVM](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/amazon-ec2-nested-virtualization.html) and separate budget; AWS omits physical WAN conditions.

Two-cluster CI needs [custom provision](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/cucushift/installer/rehearse/aws/cases/multi-clusters-one-phz/provision/cucushift-installer-rehearse-aws-cases-multi-clusters-one-phz-provision-commands.sh) and [independent per-cluster cleanup](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/cucushift/installer/rehearse/aws/cases/multi-clusters-one-phz/deprovision/cucushift-installer-rehearse-aws-cases-multi-clusters-one-phz-deprovision-commands.sh) that tolerates missing metadata, attempts every cluster, then reports failures (one-VPC prior art).

### Regional leases

Match EC2_REGION, REGION and AMIs to LEASED_RESOURCE. Lease only us-west-2 until provisioning and cleanup pass elsewhere
([provisioner](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift/image-based/infra/aws/ec2/openshift-image-based-infra-aws-ec2-commands.sh),
[defaults](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift/image-based/infra/aws/ec2/openshift-image-based-infra-aws-ec2-ref.yaml),
[cleanup](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/aws/deprovision/stacks/aws-deprovision-stacks-commands.sh),
[job](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/config/openshift/evpn-gateway-appliance/openshift-evpn-gateway-appliance-main.yaml)).

### AWS test approvals

Deliver [pipeline profile requirements](pipeline-spec.md#clusters-and-accounts) ([how-to](https://docs.ci.openshift.org/how-tos/adding-a-cluster-profile/)):

- Obtain quotas for the selected gateway, VPN connections, customer gateways, Elastic IPs and OpenShift clusters; default TGW quota is [five/account/Region](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html).
- Reserve a dedicated Boskos quota slice with regional headroom.

[Profiles expose credentials to all steps](https://docs.ci.openshift.org/how-tos/adding-a-cluster-profile/), including [PR-built ansible-test-runner](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift/evpn-gateway-appliance/e2e/openshift-evpn-gateway-appliance-e2e-ref.yaml)
via CLUSTER_PROFILE_DIR.
Prove least privilege and tag containment across created identities/keys and
passed roles before the canary ([users](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/aws/provision/iam-user/aws-provision-iam-user-commands.sh)/[roles](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/conf/aws/user-min-permissions/ipi-conf-aws-user-min-permissions-commands.sh)/[EC2](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift/image-based/infra/aws/ec2/openshift-image-based-infra-aws-ec2-commands.sh)).
Use [enforced permission boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) or approved precreated roles.
Retain [Prow trust and ok-to-test checks](https://docs.prow.k8s.io/docs/life-of-a-prow-job/).

### Cancellation mechanics

Time-limited steps, in order:

1. Stop interrupted work.
2. Snapshot CGW and relay security association metadata, routes and journals, excluding PSKs and IKE/ESP keys.
3. Clean fixtures.
4. Collect remaining diagnostics.
5. Destroy clusters.

[IPI](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/deprovision/ipi-deprovision-chain.yaml) permits [2h gather-extra](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/gather/extra/gather-extra-ref.yaml) before [60m destroy](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/deprovision/deprovision/ipi-deprovision-deprovision-ref.yaml);
default [grace is 1h](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/core-services/prow/02_config/_config.yaml).
Register every fixture CloudFormation stack in
`SHARED_DIR/to_be_removed_cf_stack_list` in creation order before creating it;
`aws-deprovision-stacks` deletes only listed stacks, in reverse order, and silently skips an absent list.
Journal other resources by job ID; keep job-ID tags for reconciliation.
Run [aws-deprovision-stacks](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/aws/deprovision/stacks/aws-deprovision-stacks-commands.sh) before [ipi-aws-post](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/aws/post/ipi-aws-post-chain.yaml) or, for STS,
[ipi-aws-post-manual-oidc-sts](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/aws/post/manual-oidc-sts/ipi-aws-post-manual-oidc-sts-chain.yaml) (adds OIDC/credentials deprovision);
await attachment ENI removal before [VPC deletion](https://docs.aws.amazon.com/vpc/latest/userguide/delete-vpc.html).
Test partial-failure cleanup,
artifact-size limits and artifacts free of PSKs and IKE/ESP keys (no raw `ip xfrm state`).
