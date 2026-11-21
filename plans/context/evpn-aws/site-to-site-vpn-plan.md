# AWS Site-to-Site VPN transport

Proposed packet path: IPsec from the appliance to the AWS gateway, VXLAN directly between the appliance and OpenShift VTEPs, and EVPN BGP through the relay.

The posted [CORENET-7500](https://redhat.atlassian.net/browse/CORENET-7500) acceptance criteria are the requirements; this plan proposes how to meet them:

- AC1: create and delete the customer gateway and two-tunnel VPN on the TGW (decision 20); a rerun with a project VPN present fails before creating anything (after any failed run, run `teardown-aws.yml` first), and a customer gateway left by a failed run is reused; teardown, in every transport mode, leaves no VPN, customer gateway or Elastic IP.
- AC2: explicit FIPS-compatible tunnel options (IKEv2, AES256-GCM-16, SHA2-256, DH14); hand per-tunnel parameters and keys to the appliance and configure Libreswan and FRR there, without writing keys to logs or artifacts.
- AC3: EVPN BGP from an advertised on-premises address, separate from underlay BGP; VXLAN reachability asserted; accept only VPC prefixes and advertise only the VTEP network.
- AC4: document the MTU budget as a limit (controls are CORENET-7709).
- AC5: health checks for both Child SAs, both underlay sessions, the EVPN session (asserted through each appliance's relayed EVPN prefixes) and AWS tunnel telemetry.
- AC6: a credential-free emulated IPsec scenario in the e2e lane, enabled in the shared job once CI owners agree. The AWS canary is outside 7500 ([decision 20](kickoff-decisions.md#decisions-at-a-glance)).
- AC7: README and role docs for `tunnel.type: ipsec` inputs, limits and teardown; WireGuard is development/test only.

[Provisioning](../../../ansible/roles/evpn_aws_infra/tasks/main.yml) creates a Transit Gateway (TGW). The implementation, [#52](https://github.com/openshift/evpn-gateway-appliance/pull/52), builds the VPN on that TGW (decision 20).
Test Platform must approve identity containment and cancellation cleanup, and each AWS lane must prove cleanup within its grace period before enablement ([AWS test approvals](#aws-test-approvals)); record [owner, date and evidence](kickoff-decisions.md).

## Delivery and proof

### Questions for owner decision

1. Decided ([decision 20](kickoff-decisions.md#decisions-at-a-glance)): Transit Gateway (TGW).
2. Decision 18 owners (PM / Architecture / QE): approve AWS (non-bare-metal) EVPN support or an exception.
3. Who takes 7501 and records its corrected [virtual-interface (VIF) criterion](source-audit.md#3-configuration--structure-mismatches) before acceptance?
4. Who owns BGP Cloud Connector (BCC) coordination for FRR, RouteAdvertisements and primary-ENI SourceDestCheck?
5. Name a coordinator for transport, security, and CI budgets, gates and cleanup.
6. Networking and CI owners: approve the dev/test IPsec migration. Architecture: agree transport MTUs. The IPsec [cipher profile](#test-obligations) is decided ([decision 20](kickoff-decisions.md#decisions-at-a-glance)); PSK authentication is #52's choice, pending the 7708 owner. 7708 and CI/QE owners: agree transport limits and emulation fidelity.
7. Decided ([decision 21](kickoff-decisions.md#decisions-at-a-glance)): keep the WireGuard code path; it carries the credential-free per-PR e2e lane (7508).
8. Decision 11 owners: supply the funded AWS account, IAM user, cluster-secrets bundle and IPI Route53 base domain.
9. Test Platform: approve VPN readback in a dedicated account/Region without unrelated VPNs; readback cannot be restricted by tag and exposes [pre-shared keys](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_TunnelOption.html) under Standard PSK storage; consider [Secrets Manager storage](https://docs.aws.amazon.com/vpn/latest/s2svpn/enhanced-security.html) instead, gated by `secretsmanager:GetSecretValue`.
10. Test Platform: approve each lane's cancellation grace period and reapers for gateways, VPNs and Elastic IPs.
11. Test Platform and the AWS lane owner: choose installer credentials: [mint](https://github.com/openshift/openshift-docs/blob/21de7e2d64fab1a65ba8ca4795e7f79591212049/modules/cco-about-default-behaviors.adoc) with [contained users, roles and keys](https://github.com/openshift/openshift-docs/blob/21de7e2d64fab1a65ba8ca4795e7f79591212049/modules/mint-mode-permission-requirements.adoc), or manual mode with AWS STS and no user or key creation.
12. Jaime and CI/QE owners: choose AWS lane cadence and gates. Jaime's [owner proposal](https://github.com/openshift/evpn-gateway-appliance/pull/42#discussion_r4616321441) (2026-11-18, with CI/QE): the VPN and underlay canary per trusted PR and periodic full-stack qualification (real AWS and OpenShift, on-premises emulated as an EC2 customer gateway), both on a shared AWS substrate, with fork PRs gated by ok-to-test. The canary's owner (outside 7500, decision 20) and 7708 (qualification) take it up.
13. Decided ([decision 20](kickoff-decisions.md#decisions-at-a-glance)): 7500 = AWS VPN lifecycle, configuration handoff, minimal appliance two-tunnel Libreswan/FRR configuration and acceptance checks; 7708 = Direct Connect, host hardening, FIPS validation and qualification.

### Ranked evidence spikes

1. Review support, topology and cloud permissions with owners and Test Platform.
2. Prove the pinned profile locally: partly done by #52's emulated scenario (two tunnels and routing); prefix filters and churn are not asserted.
3. Run a one-hour AWS canary with FRR routing software: ~$0.45 ([cost model](#cost-model)).

### Implementation order

[#52](https://github.com/openshift/evpn-gateway-appliance/pull/52) implements AC1–AC5, AC7 and AC6's emulated scenario on the TGW; the AWS canary, outside 7500, follows Test Platform approval and, with the [spikes](#ranked-evidence-spikes), checks it.
Provisioning runs the VPN tasks once (AC1); converging against an existing VPN would need an adopt-on-rerun path outside 7500 (unassigned).

Beyond 7500: compare the IPsec scenario with WireGuard (kept, question 7) for L2, BGP, MTU, MSS, failover and CI duration,
and qualify kernel IPsec on a root-privileged runner before CI owners enable it in the shared job (AC6).
WireGuard keys live on the controller in `.wg-keys` next to the playbooks, so an ephemeral execution environment (AAP included) regenerates them and rewrites both WireGuard configs on every run; reusing the hosts' existing keys is a follow-up for the WireGuard path's owner ([decision 21](kickoff-decisions.md#decisions-at-a-glance)).
OpenShift qualification (IPI lanes and a second cluster) belongs to 7708/7515 ([OCP qualification lanes](pipeline-spec.md#ocp-qualification-lanes)).

## CI on Prow

| Lane | Fixture | Coverage and limits |
| --- | --- | --- |
| Local IPsec scenario in the existing e2e lane (AC6) | The 7508 e2e stack, opt-in via `EGA_SCENARIO=ipsec` with `evpn-ipsec.clab.yml`, with IPsec in place of WireGuard for that run: the TGW node terminates both tunnels (Libreswan and FRR as the AWS endpoint), the relay carries only EVPN BGP, and VXLAN goes directly to the workload VTEP; credential-free, no OpenShift; enable in the shared job once CI owners agree | No managed VPN, TGW routing, AWS ECMP or route limits; no production FIPS qualification. |
| AWS + FRR | Canary: TGW, two real VPN tunnels, candidate CGW, separate EC2 relay; no OpenShift | Managed VPN, routing, ECMP, limits, CGW public IP; failover, rekey and relay loss (outside 7500, decision 20). NAT-T and RHEL FIPS qualification: 7708/7511. Replace tunnels; record MED; claim maintenance coverage only when observed. |

## Implementation detail

### Requirements and scope

Evidence reflects [baseline a7739d0](https://github.com/openshift/evpn-gateway-appliance/tree/a7739d046379655fa628808ccb72d971cc0cc4c3), rechecked 2026-11-16.
Target 4.22 (7498's minimum) and 5.x ([OCPSTRAT-3413](https://redhat.atlassian.net/browse/OCPSTRAT-3413) targets 5.1); [decision 18](kickoff-decisions.md#decisions-at-a-glance) sets the matrix.
[Virtualization excludes public-cloud EVPN](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/conditional-virt-choose-a-vm-networking-topology.adoc). AWS `.metal` uses [platform AWS](https://github.com/openshift/installer/blob/0b8b4f3205a7a7d0101e7e41595363f2ab2730f4/pkg/asset/manifests/infrastructure.go).
The [prototype](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af80ea66f6b111638ca1453275cc4e2/docs/design.md) expects migration failure at reduced MTU ([CNV-98581](https://redhat.atlassian.net/browse/CNV-98581)/7709).
One VPN connection has one customer gateway, so each appliance gets its own customer gateway, VPN connection (two tunnels), underlay BGP and key handoff; teardown removes every appliance's VPN and customer gateway.
All appliances share `tunnel.type` and `bgp.onprem_asn` (the workload imports EVPN routes for that ASN only); each has its own `onprem_ip` and `network_cidr` within the shared `tunnel.network_cidr`.
With multihoming (CORENET-7502), the appliances keep distinct VTEP addresses and a shared ESI, and each advertises its own VTEP network, so the TGW has a distinct route per appliance rather than same-prefix ECMP.
7500 builds and tests the per-appliance VPNs without multihoming; `deploy.yml` gates IPsec with multihoming until active-active forwarding and designated-forwarder failover over IPsec are qualified, a follow-up of 7500 or 7502.

### VTEPs and gateway

Use [Unmanaged](https://github.com/openshift/openshift-docs/blob/4cca8fa1a141991f9252a10765fd7c297fcb6cb8/modules/procedure-enabling-bgp-evpn-primary-cudn.adoc) elastic network-interface (ENI) IPv4 VXLAN endpoints (VTEPs),
as [OVN permits](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/docs/features/bgp-integration/evpn.md).

Tunnel throughput and ECMP limits are in [networking-spec.md item 3](networking-spec.md#required-handoff-to-ciqe).
[Large tunnels](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html) cost $0.60/hour/connection; qualify them separately.
The TGW accepts up to 1,000 [dynamic customer gateway (CGW) advertisements](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html).

Cluster VPNs carry VXLAN; separate relay BGP sessions avoid transitive peering.

Require isolated, nonoverlapping VPC ranges. For TGW, associate each attachment
[with one lookup table; propagate into selected tables](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html).
In #52, the implementation uses the TGW's default route table; per-attachment tables are deferred until a second cluster attaches.
Add static [VPC subnet routes](https://docs.aws.amazon.com/vpc/latest/tgw/tgw-vpc-attachments.html) through TGW for on-premises VTEP/control and infrastructure/cluster
control traffic; propagation does not update VPC tables. Enable required availability zones.
Filter prefixes at their BGP source. Never route `0.0.0.0/0` over VPN: [OSD/ROSA forbid it](https://github.com/openshift/openshift-docs/blob/adb7bdbea2116c18efd4f99a1d22c4f62d1046f5/modules/aws-vpn.adoc) to preserve internet/SRE access.
During migration remove owned lab routes through the infrastructure attachment and relay interface that bypass IPsec/DX;
same-prefix statics override propagation. Assert routes and capture relay traffic.
Changing transport means `teardown.yml`, `teardown-aws.yml`, then provisioning again (provisioning is not rerunnable); deploy also stops `wg-quick@wg0` for other transports. In the canary, verify after reboot that `wg0` and its routes stay absent.
Test both tunnels and TGW ECMP without assuming single-flow aggregation.

7515 configures VTEP CIDRs and hands the relay the node addresses OVN-Kubernetes [discovers and annotates in `Unmanaged` mode](https://github.com/ovn-kubernetes/ovn-kubernetes/blob/c4deeb85a03f955099f745d9fefbf7d74412f9f5/docs/features/bgp-integration/evpn.md); EGA has no cross-cluster discovery.
TGW propagation into the [VPN attachment’s table](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html) advertises VPC CIDRs over VPN.
At relay/appliance IPv4 ingress, reject [OCP VTEP /32s](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/go-controller/pkg/clustermanager/routeadvertisements/controller.go) and VPC/control leaks;
preserve EVPN next hops and independent VTEP covering routes.
7515 must install the on-premises VTEP prefix on workers (RouteAdvertisements accepts only /32s within cluster VTEP CIDRs); 7500 verifies reachability over VPN.
Test withdrawal/replacement, security groups/ACLs, UDP 4789, TCP 179,
return paths and source/destination checks.

### EVPN peering

Peer EVPN from an advertised on-premises address (`update-source`, `ebgp-multihop`),
separate from per-tunnel underlay BGP.
The implementation assumes one relay (relay HA is CORENET-7503): IPv4 unicast only on the two AWS inside peers, L2VPN EVPN only on the relay.
Consult 7515 on per-cluster discovery, autonomous system numbers, route targets and peering.

### BGP Cloud Connector

7500 supplies VPN underlay connectivity. BCC [creates per-node Route Server peers and disables SourceDestCheck](https://github.com/openshift/bgp-cloud-connector/blob/441abc7f1ec9c41a79a026fdacce7470e227395d/docs/cloud-integration.md), never VPN or TGW resources.
Its RouteAdvertisements has [empty node and FRRConfiguration selectors](https://github.com/openshift/bgp-cloud-connector/blob/441abc7f1ec9c41a79a026fdacce7470e227395d/internal/controller/routeadvertisements.go), risking EVPN FRRConfiguration selection and routed CUDN export toward the relay.
Before combining BCC unicast advertisements with 7515 EVPN, qualify (owner per question 4) selector boundaries in both directions, shared-resource ownership/removal order, and distinct ASNs for workers, Route Servers, AWS gateway, relay and customer gateway ([networking handoff](networking-spec.md#required-handoff-to-ciqe)).
VPN return routes must target the TGW, never workers.

### Test obligations

Use Libreswan at both ends of local/CI emulation: [already installed](../../../image/rhel10/Containerfile),
[RHEL-supported and FIPS-capable](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html-single/configuring_and_managing_networking/index).
Configure one route-based VPN connection:

- [Two tunnels](https://docs.aws.amazon.com/vpn/latest/s2svpn/VPNTunnels.html) with separate outside endpoints.
- FRR BGP over a distinct, nonreserved link-local /30 per tunnel ([AWS: keepalive 10 s, hold 30 s](https://docs.aws.amazon.com/vpn/latest/s2svpn/Juniper_Troubleshooting.html)); accept only VPC prefixes and advertise only the appliance VTEP network (AC3).
- CGW-side NAT in 7708 qualification; no NAT in emulation or the AWS canary.

Pin the same explicit [AWS-supported tunnel options](https://docs.aws.amazon.com/vpn/latest/s2svpn/tunnel-configure.html) in emulation and the AWS canary:

- IKEv2 only; IKE AES256-GCM-16 with SHA2-256 PRF, DH14; ESP AES256-GCM-16, PFS14 ([RHEL 10 FIPS disables CBC for IKE/IPsec](https://gitlab.com/redhat/centos-stream/rpms/crypto-policies/-/blob/0f4ff0ce0fd83b10e46d0d2afaae6ada14ce4e2e/crypto-policies.spec); confirm against the candidate's crypto-policies).
- AWS generates both pre-shared keys (32 characters by default), which the handoff reads back; they pass Libreswan 5.4's FIPS minimum (PSK >= half the PRF key size, 16 bytes for SHA2-256). Emulation uses `TEST_ONLY` keys.
- IKE/ESP lifetimes 28800/3600 s, rekey margin 270 s with 100% fuzz, DPD timeout 40 s with action `clear`, AWS startup action `add` (#52).

Compare observed DPD/rekey timing with these settings in the AWS canary.
NAT-T with [AES-GCM-16](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-best-practice.html) gives tunnel MTU 1438, MSS 1398.
IPv4 VXLAN costs 50 bytes: workload MTU 1388; inner TCP MSS 1348 (IPv4), 1328 (IPv6).
7500 documents the 1388/1348/1328 budget as a limit (AC4); CORENET-7709 supplies the MSS clamp and DF controls, and the canary uses them once available.
Canary/qualification: test oversized UDP/DF without relying on [PMTUD (unsupported by AWS VPN)](https://docs.aws.amazon.com/vpn/latest/s2svpn/vpn-limits.html).
In the AWS canary, test IKE and ESP rekeys from each peer with continuous forwarding; with equal margins and fuzz either peer may rekey first, so disable CGW rekey initiation in one phase.
Budget a separate ≥8-hour AWS natural-rekey soak at the pinned lifetimes, with continuous forwarding.

Read back both tunnels’ [TunnelOptionSet via DescribeVpnConnections](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_VpnConnectionOptions.html)
and, in the AWS canary, negotiated algorithms via [GetActiveVpnTunnelStatus](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_GetActiveVpnTunnelStatus.html); assert the returned parameters and check the negotiated SHA2-256 PRF on the CGW (the API has no PRF field; record what `phase1IntegrityAlgorithm` reports for AES-GCM).
Hand off both tunnels' outside addresses, inside /30s, ASNs and PSKs without writing keys to logs or artifacts (AC2).
Health checks assert both Child SAs, both underlay BGP sessions, relayed EVPN prefixes, and, when `evpn_health_check_vpn_telemetry` is true (only against AWS, not in emulation), `VgwTelemetry` Status `UP` for both tunnels (AC5); assert VXLAN reachability between appliance and cloud VTEPs (AC3).
Exercise [initiation](https://docs.aws.amazon.com/vpn/latest/s2svpn/initiate-vpn-tunnels.html), [dead-peer detection/rekey](https://docs.aws.amazon.com/vpn/latest/s2svpn/tunnel-configure.html),
[maintenance routing preferences (MED)](https://docs.aws.amazon.com/vpn/latest/s2svpn/routing-vpn-tunnel-updates.html), failover and coordinated
[AWS/host pre-shared-key changes](https://docs.aws.amazon.com/vpn/latest/s2svpn/modify-vpn-tunnel-options.html).
Pin appliance, kernel, IPsec and FRR payloads; test reboot. FIPS validation belongs to 7708/7511.
7708/7515 reuse [OVN EVPN](https://github.com/openshift/ovn-kubernetes/blob/b313a0e6860449f2a4292047a495c2c28d2cd1d6/test/e2e/evpn.go) and [OpenPERouter reflector](https://github.com/openperouter/openperouter/blob/4d69e363fd75b234e258bde4c4252130b50fbe62/e2etests/tests/route_reflector.go) cases against EGA artifacts.

Qualify large tunnels separately.
CORENET-7503/7515 qualify relay recovery; the AWS canary verifies that VPN tunnels and underlay BGP stay up during relay loss.

### Cost model

[Oregon fixtures](https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonVPC/current/us-west-2/index.json) include one VPN, two IPv4s and attachments ([billing](https://aws.amazon.com/vpn/pricing/)).

| Network fixture | Hourly | If leaked 24 h |
| --- | --- | --- |
| TGW: infra, one cluster | $0.21 | $5.04 |
| TGW: infra, two clusters | $0.26 | $6.24 |
| Large TGW: infra, one cluster | $0.76 | $18.24 |

Added cluster/DX attachments cost $0.05/hour; [TGW ingress](https://aws.amazon.com/transit-gateway/pricing/) costs $0.02/GB.
CGW IPv4 costs $0.005/hour. Each added appliance adds a VPN connection and its TGW attachment, ~$0.10/hour.
Assumptions: native AMI, m6i.xlarge CGW and two t3.small relay/peer instances; ~$0.23 [Linux compute](https://b0.p.awsstatic.com/pricing/2.0/meteredUnitMaps/ec2/USD/current/ec2-ondemand-without-sec-sel/US%20West%20%28Oregon%29/Linux/index.json) plus $0.21 TGW network and $0.005 CGW IPv4/hour; durations assumed.
An 8-hour soak costs at least ~$3.56 (8 h × ~$0.445); weekly (an assumption pending question 12; ~4.3 runs/month), ~$15/month before data transfer.

### CI setup and fixtures

Use an unattached customer VPC with [static public IP](https://docs.aws.amazon.com/vpn/latest/s2svpn/cgw-options.html), UDP 500/4500 and no bypass route.

### AWS test approvals

Deliver [pipeline profile requirements](pipeline-spec.md#clusters-and-accounts):

- Obtain quotas for the TGW, VPN connections, customer gateways, Elastic IPs and OpenShift clusters; default TGW quota is [five/account/Region](https://docs.aws.amazon.com/vpc/latest/tgw/transit-gateway-quotas.html).
- Lease only us-west-2 until provisioning and cleanup pass in another Region; leases, provisioning, AMIs and cleanup must use the same Region.

[Profiles expose credentials to all steps](https://docs.ci.openshift.org/how-tos/adding-a-cluster-profile/), including [PR-built ansible-test-runner](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift/evpn-gateway-appliance/e2e/openshift-evpn-gateway-appliance-e2e-ref.yaml)
via CLUSTER_PROFILE_DIR.
Prove least privilege and tag containment across created identities/keys and
passed roles before the canary ([users](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/aws/provision/iam-user/aws-provision-iam-user-commands.sh)/[roles](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/ipi/conf/aws/user-min-permissions/ipi-conf-aws-user-min-permissions-commands.sh)/[EC2](https://github.com/openshift/release/blob/b7c7fa63d07cea4f2221d030964fb359b5dde226/ci-operator/step-registry/openshift/image-based/infra/aws/ec2/openshift-image-based-infra-aws-ec2-commands.sh)).
Use [enforced permission boundaries](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) or approved precreated roles.
Retain [Prow trust and ok-to-test checks](https://docs.prow.k8s.io/docs/life-of-a-prow-job/).
Scope [one Test Platform engagement](https://github.com/openshift/evpn-gateway-appliance/pull/42#discussion_r4616321409) for both the canary and 7708's full-stack qualification lane (IPI installer permissions, cluster quotas), as one or two profiles; the same substrate suits the unowned 7516–7519 qualification harness.

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
