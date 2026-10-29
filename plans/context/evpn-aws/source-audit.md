# EVPN source audit checklist

These are open findings against the inspected prototype source, which has not shipped:
nothing here describes released content or customer deployments. Recheck them on
the onboarding revision; this audit did not fix the product source.
[`pipeline-spec.md`](pipeline-spec.md) defines which gate each finding blocks.
Owners below are proposed responsibilities, pending team agreement. Baseline:
internal [`evpn-on-cloud` at
`1c8e88873af8`](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/tree/1c8e88873af8)
(2026-09-08, 18 commits), rechecked from a local clone on 2026-09-29.
Collection PR #7 merged at `31cfdbb9` on 2026-10-14; image sources are open in #16 (`13189813`,
2026-10-15), and #6 (`67524c74`) is on hold. Findings below belong to
the prototype or explicitly dated earlier snapshots; recheck each on the imported revision
before treating it as a current defect. Local qualification is not merged or deployed code.

## 0. Public import

The canonical repository is now public
[`openshift/evpn-gateway-appliance`](https://github.com/openshift/evpn-gateway-appliance)
(DPP-22292, created 2026-09-28). It now holds these documents, a `Makefile` and a CI build image,
and the import is arriving in reviewed pieces, not as one snapshot. Collection
[#7](https://github.com/openshift/evpn-gateway-appliance/pull/7) has merged and image
[#16](https://github.com/openshift/evpn-gateway-appliance/pull/16) is open (#6 on hold); earlier findings cite
collection [#3](https://github.com/openshift/evpn-gateway-appliance/pull/3). Anything
pushed there is published permanently, so import a reviewed snapshot rather than the internal
history, and vet each piece the same way:

- The history contains a personal SSH public key, still baked in at
  `image/Containerfile:169`. Commit `1b56ba6` removed vendor and competitor names
  as commercially sensitive from the README, design and presentation only. It
  deliberately left them in `hack/terraform/`, which names the lab's DX partner,
  and in `docs/evpn-l2-stretch-plan.md`, which names DX partners and compares
  vendors. Ask the source owners whether to import those files at all.
- The tracked `ansible/inventory/hosts.yml` holds generated lab addresses,
  including public IPs.
- Remove non-public material, baked access keys and private/generated lab inventory
  before import; exclude presentation material not meant for publication. Scan the
  reviewed tree and record its source commit. A scanner alone is not enough:
  `detect-secrets` reports nothing on this tree, so manually review baked access and
  real environment addresses. Use safe examples and reviewed launch-access logic.
  Runtime findings stay at their [publishing/release gates](containerfile-refactor-spec.md#source-stop-ships).
- Vet the snapshot with `python3 plans/context/evpn-aws/tools/check-public-safe.py <snapshot>`
  (without `--allow-private`, so RFC 1918 lab addresses are reported and must be reviewed), which
  scans ordinary text regardless of extension, including Containerfiles and Terraform.
  Review its [input limits](ci-source.md#where-things-stand): oversized/binary/missing inputs
  can pass without examination, so a clean scan alone does not prove complete import review.
  A native scanner does not yet replace it ([deferred](ci-source.md#deferred)).
  The baseline Python scanner with `--allow-private` on `1c8e88873af8` reported two public addresses in `ansible/inventory/hosts.yml`;
  the baked key at `image/Containerfile:169`, whose comment also names an internal lab
  host; and two AWS account IDs that are the public Red Hat and CentOS AMI owners
  (`hack/terraform/main.tf`, `evpn_aws_infra/tasks/main.yml`), which are false positives.
  Vendor and DX-partner names cannot be found by pattern. If source owners identify private
  terms to screen, keep that list outside the repository. Match it locally over the snapshot
  with output suppressed; fail on matches or read
  errors and report only a generic finding in public output.
  The current Python import scanner can print matched material: keep its detailed output restricted
  and publish only a reviewed summary, not raw findings.

## 1. Security & Identity Findings

`[x]` marks a finding verified as fixed on main (2026-10-14); recheck the others against main
before working on them.

| Status | Finding | Owner | File:Line / Context |
| --- | --- | --- | --- |
| [ ] | **Baked SSH key** creates permanent root access | Releng / Source Owner | `image/Containerfile:169` |
| [x] | **Host key checking disabled** globally | Releng | Prototype `ansible/ansible.cfg:4`; fixed in #7 (left at the secure default) |
| [x] | **WireGuard private keys** written/echoed without `no_log` | Releng | Prototype `ansible/roles/evpn_cloud_infra/tasks/wireguard_keys.yml:26-52`; fixed in #7 (`no_log: true`) |
| [x] | **Collection build ships lab files and git-ignored keys** | Releng | `ansible-galaxy collection build` ignores `.gitignore`; without `build_ignore` the tarball includes `inventory/hosts.yml`, `ansible.cfg` and any `.wg-keys/` present ([measured](ci-bootstrap-spec.md#measured-collection-build-and-import-behavior)). Fixed in #7: `build_ignore` plus the `check-ansible-build` tarball allowlist |
| [x] | **SSH open to `0.0.0.0/0`** | Releng / Source Owner | Prototype `ansible/roles/evpn_aws_infra/tasks/main.yml:253`; fixed in #7 (`evpn_aws_infra_admin_cidr` required unless a lab opts in) |
| [x] | **WireGuard open to `0.0.0.0/0`** | Releng / Source Owner | Prototype `ansible/roles/evpn_aws_infra/tasks/main.yml:255`; fixed in #7 (same admin CIDR) |
| [ ] | **Dynamic runtime image pulls** | Releng / Source Owner | Runtime pulls require an approved egress policy, pinned/approved inputs, and a post-boot test. They are incompatible with any claimed offline behavior unless preseeded. |
| [ ] | **Unproven AWS access path** | Source Owner | The image lacks the proposed cloud-init path. Select and test an approved launch-time access mechanism; do not infer that a particular agent is mandatory. |
| [ ] | **Unproven container lifecycle management** | Source Owner | Raw `systemd` `podman run` units require boot/reboot/lifecycle testing. Quadlets are one possible implementation, not an unverified release requirement. |
| [ ] | **Missing service facts select the fallback lifecycle** | Source Owner / QE | The prototype deploy path lacks `service_facts`; merged #7 `7b82f9f3` gathers them, fixing that source gap. The lifecycles still disagree. #6's [default Containerfile](https://github.com/openshift/evpn-gateway-appliance/blob/67524c74561280138e12fa55b4439ac131f7f8f7/image/rhel10/Containerfile) (on hold) installs host FRR, keeps the packaged daemons file and enables `frr.service`; #16's [Quadlet unit](https://github.com/openshift/evpn-gateway-appliance/blob/131898134326933380f6e26952b637b8efde87e0/image/rhel10/frr.container.in) also yields `frr.service`, running a digest-pinned `frr-rhel9` container named `frr`. The [on-prem role](https://github.com/openshift/evpn-gateway-appliance/blob/7b82f9f3786b73ed5464f8fd30d584c09a76a928/ansible/roles/evpn_onprem_appliance/tasks/main.yml) selects `frr-container.service` or else starts its own Podman container `frr` from `frr_image`, replaces the daemons file, and its [restart handler](https://github.com/openshift/evpn-gateway-appliance/blob/7b82f9f3786b73ed5464f8fd30d584c09a76a928/ansible/roles/evpn_onprem_appliance/handlers/main.yml) always uses Podman; the relay repeats this. Reconcile the selected payload, unit/handler and daemon-file ownership, then test deployment/restart/reboot on the paired image and installed collection; gathered facts alone are not runtime qualification. |
| [ ] | **Runtime containers are broadly privileged and exposed** | Source Owner / Security | FRR runs `podman run --privileged --network host` (`image/Containerfile:83-90`), which also runs it unconfined by SELinux; node-exporter mounts the whole host read-only (`-v /:/rootfs:ro`) on the host network (`:144-154`); frr_exporter uses the host network (`:112-122`). Neither exporter sets a listen address and no role configures a host firewall, so both metrics endpoints (node-exporter's default is 9100) listen unauthenticated on every interface. Establish the capabilities, devices and mounts each container needs, or drop the FRR container with the RPM option; bind or authenticate the metrics endpoints and restrict inbound access to the required peers; and cover all of it in 7511's exposure review and the SELinux-enforcing boot tests. **Update 2026-10-29:** FRR no longer runs `--privileged`; `image/rhel10/frr-container.service:14-20` grants `--cap-drop=all` plus NET_ADMIN, SYS_ADMIN, NET_RAW, NET_BIND_SERVICE, SETUID, SETGID, KILL, DAC_OVERRIDE and CHOWN with `no-new-privileges`, mirrored as `frr_container_caps` in the three FRR role defaults. The two exporters still set no listen address and no role configures a host firewall, and the capability set is not yet qualified on the pinned image under enforcing SELinux |
| [ ] | **No BGP policy or limits** | Networking / Source Owner | Every FRR template sets `no bgp ebgp-requires-policy` (`frr-*.conf.j2:12`) and defines no route-map, prefix-list, `maximum-prefix` or route-target filtering; the relay re-advertises every EVPN route from each peer with `next-hop-unchanged`, and the OCP peer uses `ebgp-multihop 4`. Nothing at the relay constrains which routes, or how many, a peer may send. Multi-cluster isolation (7517), peer restriction (7511) and storm containment (7519) need explicit inbound/outbound policy and limits, plus tests that a rogue or misconfigured peer is contained |

## 2. Floating Image References

Pin runtime and build images by SHA digest to fix their identity; this alone does
not guarantee byte-identical rebuilds.
The current CentOS Stream base also needs an approved RHEL bootc replacement for
the intended supported product. Prove RHEL package access independently in the
Containerfile and BIB build, using approved credentials where required. The task
supports optional entitlement/activation-key inputs; it does not prove both
stages universally require RHSM secrets. Resolve this for the build canary,
without blocking source lint/collection CI. Pinning the base does not freeze
packages installed from mutable RPM repositories; record their versions too.

| Status | Image | Current Tag | File:Line |
| --- | --- | --- | --- |
| [ ] | `quay.io/centos-bootc/centos-bootc` | `:stream9` **→ switch to RHEL Image Mode base** | `image/Containerfile:1` |
| [ ] | `quay.io/frrouting/frr` | `:10.5.3` | `image/Containerfile:82,90` |
| [ ] | `quay.io/frrouting/frr` | `:10.5.3` | `ansible/inventory/group_vars/all.yml:51` |
| [ ] | `docker.io/tynany/frr_exporter` | `:latest` | `image/Containerfile:111,118` |
| [ ] | `docker.io/tynany/frr_exporter` | `:latest` | `ansible/roles/evpn_monitoring/tasks/main.yml:27` |
| [ ] | `quay.io/prometheus/node-exporter` | `:latest` | `image/Containerfile:143,151` |
| [ ] | `quay.io/prometheus/node-exporter` | `:latest` | `ansible/roles/evpn_monitoring/tasks/main.yml:58` |
| [ ] | `quay.io/centos-bootc/bootc-image-builder` | `:latest` | `image/build-ami.sh:38` |
| [ ] | Newest public CentOS Stream 9 AMI when `router_ami` is empty | query result | `ansible/roles/evpn_aws_infra/tasks/main.yml:14-28` |

Replacing tags with digests is not enough for the community FRR, exporter and
node-exporter images: Red Hat does not build or security-track them. The Red Hat
builds in the [controlling plan](pipeline-spec.md#runtime-payload-corenet-7505)
are the supportable candidates; installing RHEL's FRR RPM would remove the FRR
container rows instead of pinning them. The AMI row needs release-identity
selection, not a digest.

## 3. Configuration & Structure Mismatches

| Status | Finding | Owner | Context |
| --- | --- | --- | --- |
| [ ] | **FRR Version Mismatch** | Releng / Networking | Templates declare `10.3.1`, but image pulls `10.5.3`. Align both with the selected payload; RHEL 9's `frr10` is 10.4.3, below the version the lab validated. |
| [ ] | **Cross-role include** | Releng | `evpn_onprem_appliance/tasks/main.yml:3` uses `playbook_dir`-relative includes which assumes the old playbook layout; replace or prove it from a clean installed collection. |
| [x] | **On-prem trunk dropped filtered VLANs** | Releng / Networking | `physical.yml` enabled `vlan_filtering` on `trunk-br` without per-port VLAN membership, so a real tagged customer trunk was dropped at ingress — a silent data-plane blackhole with BGP still Established. Fixed (7515): per-port `bridge vlan add` (tagged) on the trunk port + `trunk-br self`; `physical.yml` now exercised by the 7508 e2e. |
| [ ] | **Missing Collection Files** | Releng | `galaxy.yml` (7499 names `redhat.evpn_migration`; the name was [directed in review](kickoff-decisions.md#already-settled) as `network.evpn_gateway` on 2026-10-02), `meta/runtime.yml`, `.ansible-lint`, `.yamllint`, Makefile/CI entry point are completely missing from the prototype. The earlier #3 `f7797863` snapshot added them but failed its own checks; merged #7 adds them and passes `check-ansible` ([current checks](ci-source.md#where-things-stand)). The importer also hard-fails without `repository` in `galaxy.yml`, `requires_ansible` in `meta/runtime.yml` and a README in every role ([measured](ci-bootstrap-spec.md#measured-collection-build-and-import-behavior)). |
| [ ] | **Input validation coverage** | Releng / Source Owner | The prototype lacks argument specs; merged #7 `7b82f9f3` supplies them. Native core 2.21.4 accepts negative VLAN/ASN values and the declared but unimplemented `ipsec` choice in its on-prem metadata ([current proof](ci-bootstrap-spec.md#test-placement)). Add role-owned domain/availability assertions before mutation and real-entry-point negative cases; metadata, lint or isolated validator success alone is not deployment evidence. |
| [ ] | **AWS role depends on the CLI and a community collection** | Source Owner / AAP content | 46 `aws` CLI calls through `command` in `evpn_aws_infra/tasks/main.yml`; `tasks/teardown.yml` uses `community.aws` ([details below](#aws-role-and-certified-content)) |
| [ ] | **Lab DX uses a private VIF with a TGW-associated DX gateway** | Networking / Source Owner | `hack/terraform/vpn.tf:2,32` plans a partner-hosted *private* VIF on the DX gateway it associates with the TGW; that association needs a transit VIF, which the 2026-10-01 review adopted for 7501. The lab has no Site-to-Site VPN resources. |
| [ ] | **Missing Disk Configs** | Releng | `image/bib-<format>.yaml` (for the target on-prem formats), `image/bib-raw.yaml` (for the AMI), and `image/config.toml` are missing for the build-vm-image task. |
| [ ] | **Unproven final image labels** | Releng / Source Owner | `image/Containerfile:164–165` sets description/version only. Add approved product identity, inspect build-task-injected metadata and validate the full effective EC label policy on the final image. `enforceContainerFirstSecurityLabels` is not a first-layer rule. |

## AWS role and certified content

`evpn_aws_infra/tasks/main.yml` makes 46 `aws` CLI calls through `command`, so idempotency is
hand-built and the EE must supply the CLI. AAP's supported EE (internal `ee-supported-container`
`1b04e3cf`) ships `boto3`/`botocore` for `amazon.aws` but no AWS CLI, so using modules avoids a
custom EE. `tasks/teardown.yml` uses `community.aws` transit-gateway modules, which blocks a
certified content class.

Those modules now exist in
[`amazon.aws`](https://github.com/ansible-collections/amazon.aws/tree/8d4a54671b/plugins/modules),
as does `ec2_vpc_vpn` for Site-to-Site VPN. Direct Connect modules (`directconnect_*`) and
`ec2_customer_gateway`, which a Site-to-Site VPN needs, exist only in `community.aws`, and neither
collection has TGW route-table or VPC Route Server modules (checked September 29). Certified content
therefore needs its own DX checks, leaves DX to the customer, and cannot drop the CLI for TGW
routing.
