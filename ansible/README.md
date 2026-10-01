# EVPN Gateway Appliance — Ansible Collection

Deploys and configures the EVPN Gateway Appliance (EGA) fabric: the on-prem
appliance, the AWS infra/workload relays, and the BGP EVPN sessions
connecting them, using FRR and (dev/test only) WireGuard.

> **FQCN is a placeholder.** `galaxy.yml`'s `namespace`/`name` are not
> final — see the comment at the top of that file and decision #5 in the
> delivery-planning discussion on
> [PR #2](https://github.com/openshift/evpn-gateway-appliance/pull/2) for
> the open decision. Do not build automation against this FQCN yet.

## Status

This collection is derived from an internal prototype. It is **not yet
certified or published content** — see "Known limitations" below and each
role's README for specific open items before relying on it beyond a
lab/dev/test environment.

## Layout

```
galaxy.yml, meta/runtime.yml        Collection identity and metadata
roles/
├── evpn_onprem_appliance/          On-prem: VLAN trunk, VXLAN, FRR VTEP
├── evpn_cloud_infra/               Infra VPC: WireGuard server, FRR relay
├── evpn_cloud_workload/            Workload VPC: standalone FRR VTEP (dev/test — see role README)
├── evpn_aws_infra/                 AWS provisioning (VPCs, TGW, EC2, security groups)
├── evpn_monitoring/                frr_exporter + node_exporter
└── evpn_health_check/              Read-only validation suite
playbooks/
├── deploy.yml                      Full deploy, idempotent
├── health-check.yml                Validation only
├── provision-aws.yml               Provision AWS infra, update inventory
├── teardown.yml                    Remove appliance/relay/VTEP configuration
└── teardown-aws.yml                Destroy AWS infrastructure (irreversible)
inventory/
└── hosts.yml.j2                    Sample inventory template (real hosts.yml is generated, gitignored)
tools/
└── check-collection-tarball.sh     CI: assert the built tarball ships only approved paths
```

`inventory/` and `ansible.cfg` are excluded from the published collection
tarball (`galaxy.yml`'s `build_ignore`) — they're here for the "run
straight from a source checkout" workflow below, not for the installed
collection.

## Quick start (from a source checkout)

```bash
cd ansible
# Edit inventory/hosts.yml (see inventory/hosts.yml.j2) with your host IPs,
# or run playbooks/provision-aws.yml to generate it from fresh AWS infra.
ansible-playbook playbooks/deploy.yml
ansible-playbook playbooks/health-check.yml
```

## Required variables

See each role's `meta/argument_specs.yml` for its full schema. The shared
ones (`tunnel`, `bgp`, `stretches`) are normally set once in
`inventory/group_vars/all.yml`. Notably:

- **`evpn_aws_infra_admin_cidr`** has no safe default — `evpn_aws_infra`
  fails closed until you set it (see that role's README).

## Known limitations (tracked, not all fixed here)

This collection was restructured from the prototype with the fixes
`source-audit.md` identified as in-scope for the Ansible content
specifically:

- Removed `host_key_checking = False` from `ansible.cfg`.
- `no_log: true` on every task handling WireGuard private key material.
- Fixed a `playbook_dir`-relative cross-role include that broke once
  installed from a real collection (`evpn_onprem_appliance`).
- Added explicit `service_facts` gathering so the bootc-systemd-vs-podman
  fallback logic the roles depend on actually runs (`playbooks/deploy.yml`).
- `evpn_aws_infra` no longer opens SSH/WireGuard to `0.0.0.0/0`
  unconditionally; it requires an explicit admin CIDR.
- Pinned the `frr_exporter`/`node_exporter` image tags instead of `:latest`.
- Added a defensive EVPN `maximum-prefix` to the FRR templates.
- Replaced hardcoded `hostvars['infra-router']`/`hostvars['workload-router']` lookups (and static `hostname` lines) with the explicit `infra_relay_host`/`workload_vtep_host` variables and `inventory_hostname`, so renaming those inventory hosts just needs the one matching variable updated, not template edits.
- Replaced the static `frr version 10.3.1` line in all three FRR templates with a value derived from `frr_image`'s tag, so it can't silently drift from the image actually deployed.
- Replaced hardcoded WireGuard `AllowedIPs` CIDRs with values derived from `stretches` (server side) and the `infra_vpc_cidr`/`workload_vpc_cidr`/`ocp_pod_network_cidr` variables (client side) — all three default to their previous hardcoded values if left unset.
- Replaced `/24`-assumption bridge-SVI and namespace-IP derivations (`ansible.utils.ipaddr`/`ipmath` now read the actual prefix length from each stretch's `subnet`) and the regex-derived on-prem tunnel `/24` (now the explicit `tunnel.network_cidr` variable, defaulting to the previous `10.44.44.0/24`) — so non-`/24` stretches and tunnel subnets are no longer silently mishandled.
- Added `ansible.utils` to `galaxy.yml` dependencies — it was already used (`ipsubnet`) but undeclared.
- Added `galaxy.yml`, `meta/runtime.yml`, per-role `meta/argument_specs.yml`
  and `README.md`, `.ansible-lint`/`.yamllint`, and a tarball
  content-allowlist check — all required or recommended by
  `ci-bootstrap-spec.md` and previously missing entirely.
- Excluded the real `inventory/hosts.yml` (held real lab public IPs) from
  this import; only the safe `hosts.yml.j2` template is included.

Still open, and **not** resolved by this change (see linked docs for
ownership):

- No real BGP inbound/outbound policy (route-maps/prefix-lists/route-target
  filtering) — only a defensive `maximum-prefix` backstop. Needs
  Networking to design the actual policy
  (source-audit.md §1, "No BGP policy or limits").
- `evpn_aws_infra`'s 46 raw `aws` CLI calls are not certified-content
  eligible; migrating to `amazon.aws` modules is an open follow-up.
- `frr_exporter`/`node_exporter` metrics endpoints are unauthenticated on
  every interface (`network: host`, no listen-address binding, no host
  firewall) — how this should be locked down in production is not yet
  decided.
- `ansible-lint` production-profile debt: 83 `var-naming[no-role-prefix]`
  findings are tracked/skipped (see `.ansible-lint`) rather than fixed,
  since renaming the shared variable API is a breaking change that needs
  coordination, not a mechanical per-file change.
- Collection name/namespace, shape and publication channel are unresolved.

This work tracks against the EVPN Gateway Appliance delivery plan proposed
in [PR #2](https://github.com/openshift/evpn-gateway-appliance/pull/2)
(not merged into this repository).
