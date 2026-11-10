# network.evpn_gateway_test

Test-only companion collection for the EVPN Gateway Appliance e2e lane
([`test/e2e/`](../README.md)). **Not published** — it is built and installed into
the e2e execution environment next to `network.evpn_gateway` so the lane can stand
up a simulated on-prem side and verify it.

It exists so the production collection's contract stays clean: the appliance role
takes a real `trunk_interface`, and everything that only makes sense in the
emulated fabric (fabricating a trunk and fake on-prem hosts, pinging from them)
lives here instead.

## Dev/test workload

Production `deploy.yml` discovers OCP frr-k8s pods into `cloud_workload`.
This collection is the dev/test path: list standalone VMs in `cloud_workload`,
run `deploy_workload`, then `network.evpn_gateway.deploy -e skip_frr_discovery=true`.

## Roles

| Role | Purpose |
| --- | --- |
| `evpn_onprem_appliance_sim` | Simulate the on-prem customer side the appliance attaches to: a VLAN trunk bridge, per-stretch VLAN sub-interfaces, and a network namespace per stretch acting as an on-prem host. `tasks/healthcheck.yml` asserts those hosts can reach the cloud gateway. |
| `evpn_cloud_workload` | Standalone workload VTEP for non-OCP topologies. |

## Playbooks

| Playbook | When | What |
| --- | --- | --- |
| `network.evpn_gateway_test.simulate` | before `network.evpn_gateway.deploy` | build the simulated on-prem environment |
| `network.evpn_gateway_test.deploy_workload` | before `network.evpn_gateway.deploy` | deploy the standalone workload VTEP |
| `network.evpn_gateway_test.healthcheck` | after the deploy | run the simulated-host data-plane checks |
| `network.evpn_gateway_test.teardown` | on cleanup (non-clab runs) | remove the simulated on-prem environment |
