# evpn_aws_infra

Provisions the AWS side of the EVPN fabric: infra and workload VPCs, a
Transit Gateway connecting them, EC2 router instances in each, their
security groups, and (via `tasks/teardown.yml`) tears it all down again.

See [`meta/argument_specs.yml`](meta/argument_specs.yml) for the full input
schema.

## Required: `evpn_aws_infra_admin_cidr`

No safe default exists for admin-plane ingress (source-audit.md §1). Set:

```yaml
evpn_aws_infra_admin_cidr: 203.0.113.4/32
```

Set `evpn_aws_infra_allow_open_admin_cidr: true` only for a disposable lab —
never in CI.

## Input migration

Rename existing role inputs to the prefixed names; legacy aliases are not provided:

| Previous name | Role input |
| --- | --- |
| `aws_region` | `evpn_aws_infra_aws_region` |
| `project_name` | `evpn_aws_infra_project_name` |
| `infra_vpc_cidr` | `evpn_aws_infra_infra_vpc_cidr` |
| `workload_vpc_cidr` | `evpn_aws_infra_workload_vpc_cidr` |
| `router_instance_type` | `evpn_aws_infra_router_instance_type` |
| `ssh_key_name` | `evpn_aws_infra_ssh_key_name` |
| `router_ami` | `evpn_aws_infra_router_ami` |

Shared `infra_vpc_cidr` and `workload_vpc_cidr` remain fabric settings; the
source inventory maps them to the AWS role inputs.

## Returned facts

The role exports cached IP facts as
`evpn_aws_infra_infra_public_ip`, `evpn_aws_infra_infra_private_ip`,
`evpn_aws_infra_workload_public_ip` and `evpn_aws_infra_workload_private_ip`.
The provisioning playbook uses these to render the inventory. These replace the
unprefixed `infra_public_ip`, `infra_private_ip`, `workload_public_ip` and
`workload_private_ip` facts.

## Known limitations (tracked, not fixed by this role)

- Uses 46 `aws` CLI calls instead of `amazon.aws` modules (Python 3.14
  compatibility was the prototype's rationale); `tasks/teardown.yml` already
  uses `amazon.aws` modules, so the two paths are inconsistent today.
- Future transports (ipsec/direct-connect) would need `community.aws`-only
  modules (`ec2_customer_gateway`, Direct Connect), which would reintroduce a
  certified-content blocker; today the collection depends only on `amazon.aws`
  (source-audit.md).
