# EVPN Gateway Appliance — Ansible Collection

Deploys and configures the EVPN Gateway Appliance (EGA) fabric: the on-prem
appliance, the AWS infra/workload relays, and the BGP EVPN sessions
connecting them, using FRR and (dev/test only) WireGuard.

Collection FQCN: `network.evpn_gateway`.

## Status

This collection is derived from an internal prototype. It is **not yet
certified or published content** — see "Known limitations" below and each
role's README for specific open items before relying on it beyond a
lab/dev/test environment.

## Layout

```
galaxy.yml, meta/runtime.yml        Collection identity and metadata
requirements.txt, bindep.txt        Control-node Python / system dependencies
meta/execution-environment.yml      Execution-environment dependency pointers
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

## Prerequisites (control node)

The machine running these playbooks needs:

- **Collections** — `ansible-galaxy collection install .` (resolves
  `galaxy.yml`'s dependencies: ansible.utils, ansible.posix, amazon.aws,
  containers.podman).
- **Python** — `boto3`/`botocore` for the amazon.aws modules:
  `pip install -r requirements.txt`.
- **System** — `wireguard-tools` (the WireGuard key pair is generated on the
  control node); see `bindep.txt`.
- **AWS** — credentials available in your environment for
  `provision-aws.yml`/`teardown-aws.yml`, e.g.
  `source <(aws configure export-credentials --format env)`.
- **SSH** — the EC2 key pair named by `ssh_key_name` must exist in AWS, with
  its private key available to your environment (e.g. loaded into ssh-agent).

(When building an execution environment, ansible-builder reads the Python and
system dependencies from `requirements.txt`, `bindep.txt` and
`meta/execution-environment.yml`.)

## Quick start (from a source checkout)

```bash
cd ansible
# Provision AWS infra and generate the inventory (run at least once):
ansible-playbook playbooks/provision-aws.yml
# (or hand-edit inventory/hosts.yml from inventory/hosts.yml.j2)
ansible-playbook playbooks/deploy.yml
ansible-playbook playbooks/health-check.yml
```

## Required variables

See each role's `meta/argument_specs.yml` for its full schema. The shared
ones (`tunnel`, `bgp`, `stretches`) are normally set once in
`inventory/group_vars/all.yml`. Notably:

- **`evpn_aws_infra_admin_cidr`** has no safe default — `evpn_aws_infra`
  fails closed until you set it, unless you explicitly set
  **`evpn_aws_infra_allow_open_admin_cidr: true`** to allow `0.0.0.0/0`
  (disposable labs only). See that role's README.
- **`aws_region`** — cross-check it matches the region you intend to
  provision in.

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
- Replaced hardcoded `hostvars['infra-router']`/`hostvars['workload-router']`
  lookups (and static `hostname` lines) with the explicit
  `infra_relay_host`/`workload_vtep_host` variables and `inventory_hostname`,
  so renaming those inventory hosts just needs the one matching variable
  updated, not template edits.
- Replaced the static `frr version 10.3.1` line in all three FRR templates
  with a value derived from `frr_image`'s tag, so it can't silently drift
  from the image actually deployed.
- Replaced hardcoded WireGuard `AllowedIPs` CIDRs with values derived from
  `stretches` (server side) and the
  `infra_vpc_cidr`/`workload_vpc_cidr`/`ocp_pod_network_cidr` variables
  (client side) — all three default to their previous hardcoded values if
  left unset.
- Replaced `/24`-assumption bridge-SVI and namespace-IP derivations
  (`ansible.utils.ipaddr`/`ipmath` now read the actual prefix length from each
  stretch's `subnet`) and the regex-derived on-prem tunnel `/24` (now the
  explicit `tunnel.network_cidr` variable, defaulting to the previous
  `10.44.44.0/24`) — so non-`/24` stretches and tunnel subnets are no longer
  silently mishandled.
- Added `ansible.utils` (used via `ipsubnet` but undeclared) to
  `galaxy.yml` dependencies.
- Added `galaxy.yml`, `meta/runtime.yml`, per-role `meta/argument_specs.yml`
  and `README.md`, control-node dependency files (`requirements.txt`,
  `bindep.txt`, `meta/execution-environment.yml`), `.ansible-lint`/`.yamllint`,
  and a tarball content-allowlist check — all required or recommended by
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
- `frr_exporter`/`node_exporter` use community container images that Red Hat
  does not build or security-track; supportable replacements are part of the
  runtime payload work (source-audit.md §2).
- `ansible-lint` production-profile debt: 83 `var-naming[no-role-prefix]`
  findings are tracked/skipped (see `.ansible-lint`) rather than fixed,
  since renaming the shared variable API is a breaking change that needs
  coordination, not a mechanical per-file change.
- Collection shape (layout) and publication channel are unresolved.
- The router AMI is selected by a "latest CentOS Stream 10" lookup, not a
  pinned release identity; upstream builds are rolling and get deregistered,
  and the image type is not guaranteed. A release-identified base belongs to
  the runtime payload work (source-audit.md §2).
- The CI install smoke test installs the built tarball with `--no-deps
  --offline`, so it verifies the collection builds, installs, and all roles
  are discoverable, but **not** that `galaxy.yml`'s collection dependencies
  (or the declared Python/system deps) actually resolve, nor that every FQCN
  import is satisfiable. `ci-bootstrap-spec.md` ("Required source checks")
  calls for verifying dependencies and FQCN imports, plus exercising the
  roles in a supported AAP execution environment. Closing it means installing
  the dependencies into the CI image and dropping `--no-deps` (and, for the
  EE contract, a pinned test EE).
- The appliance does not enforce inter-tenant (VNI/VLAN) data-plane isolation:
  with a VLAN-per-subnet layout, `ip_forward` plus a per-VNI SVI gateway in the
  global routing table means it routes between tenant subnets. The health-check
  "VLAN isolation" assertion is disabled pending a decision on the intended
  model (VRF-per-tenant or a forwarding filter, or accepting inter-tenant
  routing). CORENET-7508 calls for L2/VNI isolation testing in integration CI.

This work tracks against the EVPN Gateway Appliance delivery plan proposed
in [PR #2](https://github.com/openshift/evpn-gateway-appliance/pull/2)
(not merged into this repository).
