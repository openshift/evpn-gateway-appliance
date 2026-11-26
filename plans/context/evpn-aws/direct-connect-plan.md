# AWS Direct Connect and transport preflight

Proposed packet path: the customer's Direct Connect (DX) circuit carries plain IPv4 between the appliance and the Transit Gateway (TGW), VXLAN runs directly between the appliance and OpenShift VTEPs, and EVPN BGP goes through the relay.
The appliance terminates no tunnel; this is the [design document's](https://github.com/openshift/evpn-gateway-appliance/blob/505496ff29c54e559f28a33d4098cef996dd2262/docs/design.md) "skips all tunnel setup" mode, on the same TGW as the [Site-to-Site VPN](site-to-site-vpn-plan.md).

## Requirements

[CORENET-7501](https://redhat.atlassian.net/browse/CORENET-7501)'s acceptance criteria (Jira, 2026-11-25) are the requirements. They map to the rows below, from §2.2, "Transport pre-flight checks", of the [task breakdown](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/blob/1c8e88873af8/docs/evpn-task-breakdown.md) that generated the story ([context](context.md#stories)); the DX rows are 7708's:

| Acceptance criterion | Rows | Status, as proposed |
| --- | --- | --- |
| Provide a preflight playbook for every supported transport mode. | R1 | Met |
| Hard-block Direct Connect paths that cannot carry the required MTU. | R3, R5 | Left to 7708; proposed: the VIFs and the appliance's uplink block provisioning and deployment, and a narrower hop in the customer's network shows only in R5's health check |
| Validate private VIF and TGW associations. | R2, R4 | Left to 7708; proposed: **transit** VIFs (R2), and the association in the health checks (R4) |
| Validate required UDP reachability for IPsec and WireGuard. | R6 | Partly, by decision 22: the deploy run proves it, with no earlier probe (R6 below) |
| Audit workload MTU and capture latency and loss baselines. | R7, R8 | Met as decision 22 reads it: the MTU the operator declares, not the cluster's, is audited (question 3); the baseline is reported and kept in the run's statistics, with no comparison against BFD timers (question 4) |
| Require acknowledgment of internet-mode limitations. | R9 | Met |

The task breakdown's rows:

- R1: a preflight playbook that runs read-only checks and blocks deployment with a clear failure.
- R2, DX: the virtual interface (VIF) exists and is accepted. The breakdown and Jira say "private"; a TGW-associated DX gateway needs a **transit** VIF ([already settled](kickoff-decisions.md#already-settled); Jira correction pending, decision 1).
- R3, DX: hard-block an underlay MTU below 1550, which a 1500-byte workload IP MTU over IPv4 VXLAN needs ([networking handoff](networking-spec.md#required-handoff-to-ciqe) item 4).
- R4, DX: the DX gateway's TGW association reaches the infra and workload VPCs.
- R5, DX: the jumbo path works end to end, appliance → DX → TGW → OpenShift node VTEPs.
- R6, internet mode (IPsec, WireGuard): UDP reachability (500/4500, 51820).
- R7: audit the workload MTU against the transport.
- R8: a latency and loss baseline against the BFD timers.
- R9: an operator acknowledgment of internet-mode limits.

The [DX and VPN gate](pipeline-spec.md#required-gates) and [metrics plan](frr-metrics-plan.md) (item 9) cite the same checks.

## Delivery and proof

### Questions for owner decision

Questions 1–4 are decided ([decision 22](kickoff-decisions.md#decisions-at-a-glance), 2026-11-25). Questions 5–7 and 9 are proposals (implementers, 2026-11-18) that the 7708 pull request implements, pending its owner.

1. Decided: 7501 is the preflight and 7708 the DX transport, as [decision 20](kickoff-decisions.md#decisions-at-a-glance) and the [delivery plan](delivery-plan.md) give it to [CORENET-7708](https://redhat.atlassian.net/browse/CORENET-7708). 7501's DX checks need DX mode to protect, so they merge with it, and 7501 closes when that pull request merges.
2. Decided: R1 is the role's `preflight` tasks, which `deploy.yml` runs first through `playbooks/preflight.yml` and `provision-aws.yml` runs before creating anything. R9 is `evpn_health_check_accept_internet_mode_limits`, default false, since AAP job templates cannot prompt mid-run. Existing WireGuard and IPsec inventories must set it.
3. Decided: R7 reads the cluster's CUDN MTU, which the collection does not reach, so the operator must declare it: `evpn_health_check_workload_mtu` (0, the default, fails) is checked against each transport's budget (WireGuard 1370, IPsec 1388, DX 1500, its `safe` mode contract), and [CORENET-7709](https://redhat.atlassian.net/browse/CORENET-7709) owns enforcement. Until 7709 lands, DX accepts only `safe` mode; the sample inventory's `unsafe` default suits WireGuard.
4. Decided: R8 reports, as the breakdown's "warn" asks. The appliance starts `bfdd` but no BGP neighbor enables BFD, and on DX the VIF's BFD (AWS [300 ms × 3](https://docs.aws.amazon.com/directconnect/latest/UserGuide/bgp-specific-settings.html)) belongs to the customer router. Health checks record loss and average RTT over 20 pings from the VTEP address to the workload VTEP; total loss fails, and partial loss and RTT are reported only. Without BFD, BGP hold timers bound detection. The baseline runs only after deployment, since the internet-mode path does not exist before it.
5. Proposed: a customer router, not the appliance, terminates the VIF's BGP session. AWS [enables MD5 on every VIF and it cannot be turned off](https://docs.aws.amazon.com/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html), and FIPS-mode kernels disable the `md5` hash that TCP-MD5 needs ([authentication contract](containerfile-refactor-spec.md#required-outcomes)), so a FIPS appliance cannot hold that session.
6. Proposed: the collection creates the DX gateway association to its TGW, in the same account, allowing the VPC CIDRs, as the prototype's lab Terraform does. A DX gateway in another account, which needs an [association proposal its owner accepts](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-transit-gateways.html), is not supported.
7. Proposed: a plaintext DX underlay is supported, and the documentation says EVPN and VXLAN cross it [unencrypted](https://docs.aws.amazon.com/directconnect/latest/UserGuide/encryption-in-transit.html). A customer who needs encryption enables MACsec on a dedicated 10 Gbps or faster connection and their own router, which the collection neither checks nor configures, or uses the IPsec transport. IPsec over DX, a private-IP VPN on the DX attachment that #52 neither creates nor accepts (public customer gateway only), is not in scope.
8. Open, Daniel and decision 11 owners: who funds and hosts a real circuit for qualification?
9. Proposed: no VPN backing up DX, since AWS uses a 1500-byte MTU when a VPN advertises the same route ([networking handoff](networking-spec.md#required-handoff-to-ciqe) item 4).

### Implementation order

Two pull requests, each one commit passing `verify` alone:

1. 7501, on #52: this plan; a guard rejecting `tunnel.type: direct-connect`, which the argument specs accepted but which fell into WireGuard's branches, including a TGW static route for `tunnel.network_cidr` to the infra attachment ([same-prefix statics override propagation](site-to-site-vpn-plan.md#vteps-and-gateway), so routes learned over DX would be ignored; a TGW prefers a static route to a propagated one for the same prefix, [route evaluation order](https://docs.aws.amazon.com/vpc/latest/tgw/how-transit-gateways-work.html)); and the transport preflight with the internet-mode rows of the [checks below](#preflight-checks) and the R8 baseline.
2. 7708: the [DX mode](#dx-mode-corenet-7708), which lifts the guard, with the DX rows of the checks below and their negative cases in `make check`.

## Implementation detail

### Preflight checks

Each check runs as early as its inputs exist and changes nothing; the DX rows are 7708's, proposed here:

| When | Check | R |
| --- | --- | --- |
| Before `provision-aws.yml` creates anything (controller) | Only transit VIFs are attached to the DX gateway (AWS refuses a TGW association for a gateway [attached to a private VIF](https://docs.aws.amazon.com/directconnect/latest/UserGuide/direct-connect-transit-gateways.html)). AWS can send the TGW's traffic over any of them, so each, read in its own Region (a VIF lives in its connection's Region), must be readable by this account and use `mtu` 8500 in `safe` mode ([API](https://docs.aws.amazon.com/directconnect/latest/APIReference/API_VirtualInterface.html); transit VIFs take 1500 or 8500). At least one must be `available` (a hosted VIF still `confirming` is not accepted) with every IPv4 `bgpPeers[].bgpStatus` `up`; the others are reported, so one VIF in maintenance does not block a deploy. The DX gateway is `available`, its Amazon-side ASN differs from the TGW's (both default to 64512, and [the association then fails](https://repost.aws/knowledge-center/direct-connect-associate-transit-gateway) after the VPCs and instances exist), it serves only transit gateways, has a free slot ([six](https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html)) and has no [allowed prefixes overlapping](https://docs.aws.amazon.com/directconnect/latest/UserGuide/allowed-to-prefixes.html) the VPCs | R2, R3 |
| Health checks, after deploy (controller, when `evpn_health_check_dx_telemetry` is true) | The VIF checks again, then the project TGW's association is `associated` (or `updating`) with [allowed prefixes](https://docs.aws.amazon.com/directconnect/latest/UserGuide/allowed-to-prefixes.html) covering both VPCs, and the most specific TGW route to `tunnel.onprem_ip` uses the DX attachment | R4 |
| First play of `deploy.yml` (appliance) | `tunnel.next_hop` is another host on a directly connected subnet whose device MTU is at least 1550 bytes in `safe` mode, and no route within a VPC CIDR is anything but FRR's. Nothing is sent: the VTEP address does not exist yet, so hops past the uplink are proven by the health check's ping | R3 |
| Health checks, after deploy | `ping -M do -s 1522` (1522 + 28 = 1550 bytes) from the VTEP address to the workload VTEP, which also proves the return route | R5 |
| Before `provision-aws.yml` creates anything, and the first play of `deploy.yml` (controller) | Internet mode requires the acknowledgment variable; DX requires `safe` mode, `tunnel.onprem_ip` inside `tunnel.network_cidr`, which lies outside the VPC CIDRs (AWS refuses a VPC route more specific than the local route), and `next_hop` outside it; the workload MTU the operator must declare (question 3) must fit the transport | R3, R7, R9 |
| Health checks, after deploy | Loss and average RTT from the VTEP address to the workload VTEP, reported, failing only on total loss; for internet mode, the WireGuard handshake and the BGP session over it, or IPsec's Child SAs (IKE on UDP 500, or 4500 behind NAT) and its underlay BGP sessions (ESP), which prove the transport's packets pass both ways | R6, R8 |

`up` "does not indicate the state of the routing function", hence the route check.
`DescribeVirtualInterfaces` returns each VIF's MD5 key, so the query must select fields and never log the raw response.
For R6, those tunnel checks fail the deploy run. Decision 22 adds no earlier probe: WireGuard answers only an authenticated handshake, and an IKE probe of the AWS endpoints would only repeat Libreswan's first exchange, without proving ESP.
DX has no modules in `amazon.aws`, and `community.aws`'s [`directconnect_virtual_interface`](https://github.com/ansible-collections/community.aws/blob/0b09b16b651bb4fd639cbe0e77461551e0a523a6/plugins/modules/directconnect_virtual_interface.py) models only private and public VIFs, so the checks would use the AWS CLI, as the role already does ([certified-content limits](source-audit.md#aws-role-and-certified-content)).
No CI lane runs `evpn_aws_infra` against AWS. With 7708, `make check` would play the DX checks, the transport preflight, association and teardown against a fake AWS CLI on `PATH` that serves API-shaped state and applies `--query`; each bad input or state would fail with its own message, read-only checks may make only `describe-` and `search-` calls, teardown may delete only the project TGW's associations, and no case may print the MD5 key.

### DX mode (CORENET-7708)

Proposed for 7708, so that 7501's checks have a mode to protect:

- Shared TGW-terminated path: the #52 conditions that mean "AWS terminates the transport" (EVPN to the relay's private IP, the VTEP dummy, relay FRR, no WireGuard routes) also cover `direct-connect`; Libreswan and the AWS inside peers stay IPsec only, and WireGuard and IPsec render unchanged. EVPN uses `ebgp-multihop 255`, since the customer's path has an unknown hop count, and serves one appliance without multihoming (7502). It requires `safe` MTU mode (8500-byte VIFs) until 7709 supplies the reduced-MTU controls, so a 1500-byte VIF fails preflight (R3).
- AWS: associate the customer's DX gateway with the TGW (question 6) and route `tunnel.network_cidr` from the infra VPC through the TGW; teardown deletes only the project TGWs' DX gateway associations, in every mode, and never the customer's gateway, VIFs or connection.
- Appliance: the customer router routes `tunnel.network_cidr` to the appliance and advertises it over the VIF (question 5). The appliance routes the VPC CIDRs to `tunnel.next_hop` over the named uplink with FRR static routes: measured 2026-11-18 with FRR 10.5.3 in the arm64 emulated lab (unmanaged uplink; not reproduced on x86), after a 10 s uplink flap zebra never re-resolved the BGP next hops over kernel routes, which left no remote VTEPs until FRR restarted, while FRR static routes recovered; we saw no route update when carrier returned. With a NetworkManager-managed uplink, unnamed static routes could stay down after a short flap or fall back to the management interface, so they name the uplink, with `onlink`: without it, the kernel rejected the routes after NetworkManager re-added the uplink address. On x86 (measured 2026-11-25 with FRR 10.6.2 and kernel 7.2 in the e2e `dx` scenario, three 5 s carrier losses), FRR's static routes were withdrawn within 0.6 s of carrier loss, leaving the policy rules' blackhole, and were back within 0.8 s of carrier return, with the EVPN session up throughout; a kernel route on the uplink survived carrier loss as `linkdown`, but setting the uplink administratively down and up deleted it for good, while FRR reinstalled its static routes. Underlay BGP with the customer router would also work, at the cost of customer router configuration. AWS accepts [100 prefixes per transit VIF by default](https://docs.aws.amazon.com/directconnect/latest/UserGuide/limits.html) and idles the session above that.
- Emulation: #52's IPsec topology with a plain routed 8500-byte link in place of the tunnels; credential-free, as the e2e lane's `dx` scenario.
- Real-circuit qualification: the [Test Platform engagement](site-to-site-vpn-plan.md#aws-test-approvals) shared with the VPN canary (question 8).

### Cost

Preflight and emulation cost nothing.
A real lane adds a [TGW attachment](https://aws.amazon.com/transit-gateway/pricing/) ($0.05/hour) and a [port](https://aws.amazon.com/directconnect/pricing/): a 50 Mbps hosted connection costs $0.03/hour and a 1 Gbps dedicated port $0.30/hour (US, 2026-11-18), plus partner or colocation charges this plan does not estimate. A hosted VIF gets the 8500-byte MTU only if the partner's parent connection is jumbo-capable.
Transit VIFs work on [hosted connections of any speed](https://docs.aws.amazon.com/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html).
