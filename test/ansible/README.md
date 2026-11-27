# network.evpn_gateway_test

Test-only companion collection for the EVPN Gateway Appliance e2e lane
([`test/e2e/`](../README.md)). **Not published** — it is built and installed into
the e2e execution environment next to `network.evpn_gateway` so the lane can stand
up a simulated on-prem side and verify it.

It exists so the production collection's contract stays clean: the appliance role
takes a real `trunk_interface`, and everything that only makes sense in the
emulated fabric (fabricating a trunk and fake on-prem hosts, pinging from them)
lives here instead.

## Simulation workload

Production `deploy.yml` discovers OCP frr-k8s pods into `cloud_workload`
when the group is empty. This collection carries the simulation path: the
emulated scenario lists a standalone VTEP in `cloud_workload`, runs
`network.evpn_gateway_test.deploy_workload`, then `network.evpn_gateway.deploy`
(the non-empty group keeps discovery out of the way).

## Roles

| Role | Purpose |
| --- | --- |
| `evpn_onprem_appliance_sim` | Simulate the on-prem customer side the appliance attaches to: a VLAN trunk bridge, per-stretch VLAN sub-interfaces, and a network namespace per stretch acting as an on-prem host. `tasks/healthcheck.yml` asserts those hosts can reach the cloud gateway. |
| `evpn_cloud_workload` | Standalone workload VTEP for the emulated scenario. |

## Playbooks

| Playbook | When | What |
| --- | --- | --- |
| `network.evpn_gateway_test.simulate` | before `network.evpn_gateway.deploy` | build the simulated on-prem environment |
| `network.evpn_gateway_test.deploy_workload` | before `network.evpn_gateway.deploy` | deploy the standalone workload VTEP |
| `network.evpn_gateway_test.healthcheck` | after the deploy | simulated-host data-plane checks; with a standalone VTEP in cloud_workload, also its workload-side checks |
| `network.evpn_gateway_test.l2_pod` | after the deploy (kind scenario fabric) | apply a pod on the primary CUDN and assert the appliance reaches its stretched address (ICMP + HTTP) |
| `network.evpn_gateway_test.teardown` | on cleanup (non-clab runs) | remove the simulated on-prem environment and the standalone VTEP |
