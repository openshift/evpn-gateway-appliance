# evpn_aws_infra

Provisions the AWS side of the EVPN fabric: infra and workload VPCs, a
Transit Gateway connecting them, EC2 router instances in each, their
security groups, and (via `tasks/teardown.yml`) tears it all down again.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema.

## AWS Site-to-Site VPN (`tunnel.type: ipsec`)

Creates, per on-premises appliance, a customer gateway and a dynamic-routing VPN connection with two
tunnels on the role's Transit Gateway (TGW). AWS terminates IPsec; the EC2
routers receive no UDP 500/4500 rules. WireGuard ingress and the routes through
the infra EC2 instance apply only to WireGuard.

| Input (host variables override per appliance) | Default | Contract for `ipsec` |
| --- | --- | --- |
| `evpn_aws_infra_vpn_customer_gateway_ip` | Empty | Required on-premises static public IPv4 address; validated before any AWS resource is created. |
| `evpn_aws_infra_vpn_customer_gateway_asn` | `65044` | Customer gateway BGP ASN; the collection's `group_vars/all.yml` sets it from `bgp.onprem_asn`. Keep it distinct from the TGW's default Amazon-side ASN (`64512`) and any VPC Route Server ASN reachable through the TGW, or BGP drops the routes as AS-path loops; preflight also rejects AWS's reserved 7224, 9059, 10124 and 17943. |
| `evpn_aws_infra_vpn_tunnel_inside_cidrs` | `[169.254.10.0/30, 169.254.11.0/30]` | Exactly two distinct canonical /30 networks in `169.254.0.0/16`, excluding AWS reserved ranges. |

AWS generates both PSKs (32 alphanumeric characters by default). Keys are handled with `no_log`, kept in memory, and never
written to files by the role.
Keep AWS CLI client-side history disabled: `cli_history=enabled` records
request/response bodies, including keys.

Both tunnels pin the IKEv2 AES256-GCM-16/SHA2-256/DH14 profile and the lifetimes, rekey and DPD options in
[`tasks/vpn.yml`](tasks/vpn.yml), and provisioning reads them back.

Each host in `onprem_appliances` (or, without that group, the role values) gets its own customer gateway and
VPN connection, tagged `Project: <project>` and `Name: <project>-cgw-<ip>` or `<project>-vpn-<ip>`, where
`<ip>` is its customer gateway IP. Host variables override the
`evpn_aws_infra_vpn_customer_gateway_ip` and `_tunnel_inside_cidrs` role values; preflight requires distinct
customer gateway IPs and inside networks across appliances (AWS requires inside networks unique per TGW) and
one shared customer gateway ASN. Each customer gateway uses a project-specific device name to prevent AWS deduplicating gateways across
projects with the same IP and ASN ([CLI behavior](https://docs.aws.amazon.com/cli/latest/reference/ec2/create-customer-gateway.html)).
Rerunning IPsec provisioning with any project VPN present fails at preflight before anything is created.
Provisioning creates new VPCs and a TGW on every run, so after any failed run, run teardown-aws.yml first. Adding or removing an appliance needs teardown-aws.yml and
a new provisioning run: deploy fails when the project's VPNs don't match the appliances.

The fresh TGW's defaults associate and propagate the VPN attachments to its default route table.
Both VPC route tables send
`tunnel.network_cidr` (default `10.44.44.0/24`) through the TGW. Each on-premises
appliance advertises its own network within it over BGP; `available` means AWS
provisioning completed, not that IKE/BGP sessions are up.

Each VPN connection and its public IPv4 addresses bill hourly whether or not tunnels come up, so run
`ansible-playbook playbooks/teardown-aws.yml` after a failed or abandoned run.

## Read-only VPN handoff (`tasks_from: vpn_handoff`)

Reads the existing **available** VPNs tagged `Project: <project>` and
`Name: <project>-vpn-<ip>`, and their TGW's Amazon-side ASN. A missing, duplicate
or extra VPN (matched by that Name tag), or a customer gateway whose ASN differs from the inputs, fails
before building the handoff.
This entry point creates no AWS resources; set `evpn_aws_infra_aws_region`,
`evpn_aws_infra_project_name` and each appliance's customer gateway IP and ASN to the
provisioned values, and run it on localhost with `connection: local` and `become: false`. The
`deploy.yml` playbook reads this handoff only for `ipsec` appliances without
an inventory-supplied `evpn_onprem_appliance_ipsec`. It passes each appliance its
entry of the secret `evpn_aws_infra_vpn` fact (keyed by customer gateway IP; each entry follows the
`evpn_onprem_appliance_ipsec` schema in [`evpn_onprem_appliance`'s argument
spec](../evpn_onprem_appliance/meta/argument_specs.yml)) in memory with `no_log`; the
handoff is never written to inventory or another controller file. Never debug
or cache either secret dictionary.

## Read-only VPN status (`tasks_from: vpn_status`)

Requires exactly one available VPN named `<project>-vpn-<ip>` per appliance, with 2×N `VgwTelemetry`
endpoints `UP` across N appliances. It retries for up to
five minutes, then fails with the tunnel states. Module results containing tunnel options and customer gateway
configuration are protected with `no_log`; checks print only per-tunnel states.

For the health integration (`evpn_health_check` checks AWS telemetry by default for `ipsec`), see [`evpn_health_check`](../evpn_health_check/README.md).

## AWS Direct Connect (`tunnel.type: direct-connect`)

The customer provisions the DX connection, transit VIFs and DX gateway; the
role never creates or deletes them. Set `evpn_aws_infra_dx_gateway_id` to an
existing DX gateway whose Amazon-side ASN differs from the TGW's default `64512`,
with only transit VIFs attached, each readable by this account at MTU 8500 with
a customer router ASN other than `64512` (AWS can use any of them), and at least
one `available` with every IPv4 BGP peer `up`.

Before creating anything, `tasks/dx_preflight.yml` checks the gateway, its
associations and the VIFs (the transport preflight checks `safe` MTU mode).
Provisioning then associates the gateway with the TGW, allowing exactly the two
VPC CIDRs (what AWS advertises to on-premises), and routes `tunnel.network_cidr`
from the infra VPC through the TGW; the TGW's default route table propagates
the routes the customer advertises over the VIFs. Rerunning provisioning fails
at preflight while the project has a TGW in that Region; run `teardown-aws.yml` first.

In every transport mode, teardown first deletes the project TGWs' Direct Connect gateway associations. If
provisioning stopped before AWS created the TGW's DX attachment, teardown cannot find the association yet; when TGW
deletion then fails, run teardown again. When an association exists, teardown needs
`directconnect:DescribeDirectConnectGatewayAssociations` and
`directconnect:DeleteDirectConnectGatewayAssociation`.

`DescribeVirtualInterfaces` returns each VIF's BGP MD5 key; every call selects
only the fields it needs, so the key is never registered or logged. Keep AWS
CLI client-side history disabled: `cli_history=enabled` records the full response.

Provisioning needs `directconnect:DescribeDirectConnectGatewayAttachments`,
`directconnect:DescribeVirtualInterfaces`,
`directconnect:DescribeDirectConnectGateways`,
`directconnect:DescribeDirectConnectGatewayAssociations` and
`directconnect:CreateDirectConnectGatewayAssociation`.

## Read-only Direct Connect checks (`tasks_from: dx_status`)

Rechecks the VIFs, then requires the project TGW's association to allow both VPC
CIDRs and the most specific TGW route (active or blackhole) to
`tunnel.onprem_ip` to use the attachment of `evpn_aws_infra_dx_gateway_id`. Health checks run
it on the controller with the `onprem_appliances` hosts' `evpn_aws_infra_*` and
`tunnel` variables (set them in `group_vars/all.yml`, not with `-e` at
provisioning); it needs `directconnect:DescribeDirectConnectGatewayAttachments`,
`directconnect:DescribeVirtualInterfaces`,
`directconnect:DescribeDirectConnectGatewayAssociations`,
`ec2:DescribeTransitGateways` and `ec2:SearchTransitGatewayRoutes`.

## Permissions

The preflight, handoff, telemetry and teardown run on the controller with `amazon.aws`, boto3/botocore and AWS
credentials; the handoff and teardown also need the AWS CLI. IPsec provisioning adds `ec2:CreateCustomerGateway`,
`ec2:CreateVpnConnection` and `ec2:CreateTags` on those two resource types, first used after the VPCs and TGW
exist. It and the controller tasks need `ec2:DescribeVpnConnections` (provisioning, handoff, telemetry and teardown),
`ec2:DescribeTransitGateways` (handoff), `ec2:DescribeCustomerGateways` (provisioning, handoff and teardown),
and, for teardown with every transport, `ec2:DeleteVpnConnection`, `ec2:DescribeTransitGatewayAttachments` and
`ec2:DeleteCustomerGateway`.

## Required: `evpn_aws_infra_admin_cidr`

No safe default exists for admin-plane ingress (source-audit.md §1). Set:

```yaml
evpn_aws_infra_admin_cidr: 203.0.113.4/32
```

Set `evpn_aws_infra_allow_open_admin_cidr: true` only for a disposable lab —
never in CI.

## Inputs and returned facts

Role-owned inputs and the returned `evpn_aws_infra_{infra,workload}_{public,private}_ip` facts
carry the `evpn_aws_infra_` prefix; shared settings such as `tunnel` do not.

## Known limitations (tracked, not fixed by this role)

- Uses `aws` CLI calls instead of `amazon.aws` modules for provisioning (Python 3.14
  compatibility was the prototype's rationale); `tasks/teardown.yml` mostly
  uses `amazon.aws` modules (VPN teardown uses the CLI for TGW attachments and customer
  gateways), so the two paths are inconsistent today.
- VPN supports TGW only; a VGW would need provisioning, routing and handoff changes.
- Direct Connect associates a DX gateway in the same account only; a gateway in
  another account needs an association proposal its owner accepts.
