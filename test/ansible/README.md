# network.evpn_gateway_test

Test-only companion collection for the EVPN Gateway Appliance e2e lane
([`test/e2e/`](../e2e/README.md)). **Not published** — it is built and installed into
the e2e execution environment next to `network.evpn_gateway` so the lane can stand
up a simulated on-prem side and AWS VPN endpoint and verify the fabric.

It exists so the production collection's contract stays clean: the appliance role
takes a real `trunk_interface`, and everything that only makes sense in the
emulated fabric (fabricating a trunk and fake on-prem hosts, pinging from them)
lives here instead.

## Roles

| Role | Purpose |
| --- | --- |
| `evpn_onprem_appliance_sim` | Simulate the on-prem customer side the appliance attaches to: a VLAN trunk bridge, per-stretch VLAN sub-interfaces, and a network namespace per stretch acting as an on-prem host. `tasks/healthcheck.yml` asserts those hosts can reach the cloud gateway and, for IPsec, that the appliance drops the non-VPC test prefix and advertises only `tunnel.network_cidr` (AC3). |
| `evpn_aws_vpn_sim` | IPsec scenario only: two Libreswan responder connections per appliance VPN on the TGW plus FRR ASN 64512 advertising the VPC CIDRs plus the non-VPC test prefix 192.0.2.0/24 and installing the learned on-prem route. Uses the node image's FRR service. |

## Playbooks

| Playbook | When | What |
| --- | --- | --- |
| `network.evpn_gateway_test.simulate` | before `network.evpn_gateway.deploy` | build the simulated on-prem environment; for IPsec, add the TGW in memory and configure the AWS VPN endpoint there |
| `network.evpn_gateway_test.healthcheck` | after the deploy | run the simulated-host data-plane checks |
| `network.evpn_gateway_test.teardown` | on cleanup (non-clab runs) | remove the simulated on-prem environment |
