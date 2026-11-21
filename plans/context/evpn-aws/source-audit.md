# EVPN source audit checklist

These are open findings against the inspected prototype source, which has not shipped:
nothing here describes released content or customer deployments. Recheck them on
the onboarding revision; this audit did not fix the product source.
[`pipeline-spec.md`](pipeline-spec.md) defines which gate each finding blocks.
Owners below are proposed responsibilities, pending team agreement. Baseline:
internal [`evpn-on-cloud` at
`1c8e88873af8`](https://gitlab.cee.redhat.com/datucker/evpn-on-cloud/-/tree/1c8e88873af8)
(2026-09-08, 18 commits), rechecked from a local clone on 2026-09-29.
Collection PR #7 merged at `31cfdbb9` on 2026-10-14; the 2026-10-15 image-source
observations below used #16 (`13189813`, then open) and #6 (`67524c74`, then on hold).
On 2026-10-22, #16 was closed and #6 was open with embedded FRR at `e3239e6c`.
PR #6 merged on 2026-10-23 at `be5a2b9a`
([current source baseline](frr-metrics-details.md#source-baseline-and-repository-boundaries)). Findings below belong to
the prototype or explicitly dated earlier snapshots; recheck each on the imported revision
before treating it as a current defect. Local qualification is not merged or deployed code.

## 0. Public import

The canonical repository is now public
[`openshift/evpn-gateway-appliance`](https://github.com/openshift/evpn-gateway-appliance)
(DPP-22292, created 2026-09-28). It now holds these documents, a `Makefile` and a CI build image,
and the import is arriving in reviewed pieces, not as one snapshot. Collection
[#7](https://github.com/openshift/evpn-gateway-appliance/pull/7) and image
[#6](https://github.com/openshift/evpn-gateway-appliance/pull/6) have merged (#6 on 2026-10-23 at `be5a2b9a`; #16 closed); earlier findings cite
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
| [x] | **WireGuard private keys** written/echoed without `no_log` | Releng | Prototype `ansible/roles/evpn_cloud_infra/tasks/wireguard_keys.yml:26-52`; generation/cache handling fixed in #7 (`no_log: true`). Config-template output remains exposed on main; [#34](https://github.com/openshift/evpn-gateway-appliance/pull/34) proposes the separate fix |
| [ ] | **AWS credentials in verbose provisioning logs** | Releng / Security | Synthetic reproduction based on main `4513031` (2026-11-04): `ansible/playbooks/provision-aws.yml` exports controller secrets into verbose connection output, even with task-level `no_log` enabled in the probe. [#39](https://github.com/openshift/evpn-gateway-appliance/pull/39) proposes inheriting credentials through local execution without privilege escalation; verify after merge. |
| [x] | **Collection build ships lab files and git-ignored keys** | Releng | `ansible-galaxy collection build` ignores `.gitignore`; without `build_ignore` the tarball includes `inventory/hosts.yml`, `ansible.cfg` and any `.wg-keys/` present ([measured](ci-bootstrap-spec.md#measured-collection-build-and-import-behavior)). Fixed in #7: `build_ignore` plus the `check-ansible-build` tarball allowlist |
| [x] | **SSH open to `0.0.0.0/0`** | Releng / Source Owner | Prototype `ansible/roles/evpn_aws_infra/tasks/main.yml:253`; fixed in #7 (`evpn_aws_infra_admin_cidr` required unless a lab opts in) |
| [x] | **WireGuard open to `0.0.0.0/0`** | Releng / Source Owner | Prototype `ansible/roles/evpn_aws_infra/tasks/main.yml:255`; fixed in #7 (same admin CIDR) |
| [ ] | **Dynamic runtime image pulls** | Releng / Source Owner | Runtime pulls require an approved egress policy, pinned/approved inputs, and a post-boot test. They are incompatible with any claimed offline behavior unless preseeded. |
| [ ] | **Unproven AWS access path** | Source Owner | The image lacks the proposed cloud-init path. Select and test an approved launch-time access mechanism; do not infer that a particular agent is mandatory. |
| [ ] | **Unproven container lifecycle management** | Source Owner | Raw `systemd` `podman run` units require boot/reboot/lifecycle testing. Quadlets are one possible implementation, not an unverified release requirement. |
| [ ] | **Missing service facts select the fallback lifecycle** | Source Owner / QE | Rechecked 2026-11-04: the merged collection gathers `service_facts`; its startup and [restart handlers](https://github.com/openshift/evpn-gateway-appliance/commit/041cd2e90ad39e821c45520d45ec12f5b41ff86f) select `frr-container.service`, matching the embedded image. The Podman fallback still uses `frr_image`. Reconcile image/daemon-file ownership and exporter migration, then qualify deployment, notified restart, reboot and teardown on the paired image and collection. [#53](https://github.com/openshift/evpn-gateway-appliance/pull/53) (open) covers legacy-exporter removal and teardown groups; source agreement alone is not runtime qualification. |
| [ ] | **Runtime containers are broadly privileged and exposed** | Source Owner / Security | In the inspected prototype, FRR ran `podman run --privileged --network host` (`image/Containerfile:83-90`), which also ran it unconfined by SELinux. In this repository, node-exporter mounts the whole host read-only (`-v /:/rootfs:ro`) on the host network (`image/rhel10/node-exporter.service`); frr_exporter uses the host network (`ansible/roles/evpn_monitoring/tasks/main.yml`). In the prototype, both exporters listened unauthenticated on every interface and no role configured a host firewall. Here the bootc image's node-exporter binds `127.0.0.1:9100`, but the `evpn_monitoring` Podman exporters still listen on every interface, and the router unit's `RuntimeDirectoryMode=0777` (`image/rhel10/frr-container.service`) lets any local user replace FRR sockets; replacing `RuntimeDirectory=` with a tmpfiles entry (for example `d /run/frr 0750 998 997`, after checking the host IDs, plus a shared relabel) and dropping the router roles' `0777` on `/var/run/frr` (`ansible/roles/*/tasks/main.yml`) would fix that ([earlier analysis](https://github.com/openshift/evpn-gateway-appliance/blob/a7739d046379655fa628808ccb72d971cc0cc4c3/plans/context/evpn-aws/frr-metrics-details.md#proposed-units-ownership-and-e2e-checks)). Establish the capabilities, devices and mounts each container needs (EGA #51's FRR RPM alternative closed 2026-11-20, so the FRR container stays); bind or authenticate the metrics endpoints and restrict inbound access to the required peers; and cover all of it in 7511's exposure review and the SELinux-enforcing boot tests. **Update 2026-10-29:** FRR no longer runs `--privileged`; `image/rhel10/frr-container.service:14-20` grants `--cap-drop=all` plus NET_ADMIN, SYS_ADMIN, NET_RAW, NET_BIND_SERVICE, SETUID, SETGID, KILL, DAC_OVERRIDE and CHOWN with `no-new-privileges`, mirrored as `<role>_frr_container_caps` in the three FRR role defaults. The two exporters still set no listen address and no role configures a host firewall, and the capability set is not yet qualified on the pinned image under enforcing SELinux. **Update 2026-11-12:** DAC_OVERRIDE stays. A rejected change removed it after a source check showing that only `nhrpd` requests `ZCAP_DAC_OVERRIDE` (`nhrpd/nhrp_main.c:38-40`, to write `/proc/sys/net/ipv4/conf/<if>/send_redirects` in `nhrpd/linux.c:106`) and that the daemons this image starts request none of it (`bgpd/bgp_main.c:105`, `bfdd/bfdd.c:39`, `zebra/main.c:102`, `mgmtd/mgmt_main.c:36`, `staticd/static_main.c:37`, `watchfrr/watchfrr.c:1336`). Those lines are from tag `frr-10.4.3`, the version the pinned image reports through `bgpd --version`. That check covers the daemons and misses the root processes. The daemons run as `frr` and create `/var/run/frr/<daemon>.vty` as `srwxrwx--- frr:frrvty`, using `umask(0007)` and a chown to the vty group (`lib/vty.c:2049`, `lib/vty.c:2097`). Root never joins `frrvty`, because `watchfrr_privs` sets only `vty_group` (`watchfrr/watchfrr.c:1336`), so root counts as other on those sockets. Measured on the pinned image with `--cap-drop=all` and the unit's set: without DAC_OVERRIDE, `watchfrr` logs `bgpd: access to socket /var/run/frr/bgpd.vty denied: Permission denied`, then `all configured daemons failed to start -- exiting watchfrr`, and `vtysh -c 'show bgp summary json'` returns `bgpd is not running`; with `--cap-add=DAC_OVERRIDE` it logs `all daemons up, doing startup-complete notify` and the same command returns JSON; adding `--group-add frrvty` instead of the flag also brings every daemon up and returns JSON. Prow e2e `pull-ci-openshift-evpn-gateway-appliance-main-e2e` build `2120871155182080000` failed with `bgpd is not running` on all three nodes. SYS_ADMIN is not leftover from the old `--privileged` run. zebra, bgpd, bfdd and mgmtd each request it, and FRR exits when `cap_set_proc` cannot grant it (`lib/privs.c:344`). Separately, `/var/run/frr` is 0777 with no sticky bit on the host (`image/rhel10/frr-container.service:10` and the `/var/run/frr` tasks in the three roles), so any local user can unlink or replace those sockets. Replace DAC_OVERRIDE only after measuring the `frrvty` group path, the daemon restart path and enforcing SELinux on the bootc image. **Update 2026-11-20:** `evpn_monitoring` no longer runs `frr_exporter`; the image's `image/rhel10/frr-metrics.service` serves FRR metrics on `127.0.0.1:7573` as `frr` with no capabilities, a read-only `/var/run/frr` mount and SELinux labeling disabled (`frr-container.service`'s `:Z` mount relabels `/var/run/frr` on every FRR start); it reaches FRR through `vtysh`, which can also change FRR's configuration, since FRR has no read-only vty. The fallback `node_exporter` still listens on every interface. |
| [ ] | **No BGP policy or limits** | Networking / Source Owner | Every FRR template sets `no bgp ebgp-requires-policy` (`frr-*.conf.j2`) and defines no route-map or prefix-list (open #52 would add AWS IPsec underlay prefix-lists); the VTEPs set per-VNI route targets but the relay filters by none, and EVPN neighbors have only a `maximum-prefix` backstop (default 1000, no restart timer); the relay re-advertises every EVPN route from each peer with `next-hop-unchanged`, and the OCP peer uses `ebgp-multihop 4`. Nothing at the relay constrains which routes a peer may send, and only the EVPN family is capped. Multi-cluster isolation (7517), peer restriction (7511) and storm containment (7519) need explicit inbound/outbound policy and limits, plus tests that a rogue or misconfigured peer is contained |

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
| [x] | `docker.io/tynany/frr_exporter` | removed in #53 | `ansible/roles/evpn_monitoring/tasks/main.yml:27` |
| [ ] | `quay.io/prometheus/node-exporter` | `:latest` | `image/Containerfile:143,151` |
| [ ] | `quay.io/prometheus/node-exporter` | `:latest` | `ansible/roles/evpn_monitoring/tasks/main.yml:58` |
| [ ] | `quay.io/centos-bootc/bootc-image-builder` | `:latest` | `image/build-ami.sh:38` |
| [ ] | Newest public CentOS Stream 9 AMI when `router_ami` is empty | query result | `ansible/roles/evpn_aws_infra/tasks/main.yml:14-28` |

Replacing tags with digests is not enough for the community FRR, exporter and
node-exporter images: Red Hat does not build or security-track them. The Red Hat
builds in the [controlling plan](pipeline-spec.md#runtime-payload-corenet-7505)
are the supportable candidates; installing RHEL's FRR RPM would have removed the FRR
container rows, but EGA #51's RPM alternative closed 2026-11-20, so they need pinning. The AMI row needs release-identity
selection, not a digest.

## 3. Configuration & Structure Mismatches

| Status | Finding | Owner | Context |
| --- | --- | --- | --- |
| [ ] | **FRR Version Mismatch** | Releng / Networking | Templates declare `10.3.1`, but image pulls `10.5.3`. Align both with the selected payload; RHEL 9's `frr10` is 10.4.3, below the version the lab validated. |
| [x] | **Cross-role include** | Releng | Fixed: `evpn_onprem_appliance/tasks/main.yml` uses `include_role` (FQCN) for the cross-role `wireguard_keys` include, which resolves from a clean installed collection; no `playbook_dir`-relative path remains. |
| [x] | **On-prem trunk dropped filtered VLANs** | Releng / Networking | `physical.yml` enabled `vlan_filtering` on `trunk-br` without per-port VLAN membership, so a real tagged customer trunk was dropped at ingress — a silent data-plane blackhole with BGP still Established. Fixed (7499): the networking rework drops `physical.yml` and renders `trunk-br` via nmstate, with the trunk port's `trunk-tags` carrying every stretch VLAN; `trunk-br`'s own (self) VLAN membership, which nmstate/NM cannot express, is reconciled by an NM dispatcher. Exercised by the 7499 Molecule lane (`nm_networking`). |
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
