# bootc Containerfile refactor contract

This document defines source changes needed before a releasable bootc Component;
it does not prescribe unapproved registry locations, systemd style, or cloud
access implementation. The controlling release sequence is
[`pipeline-spec.md`](pipeline-spec.md).

## Required outcomes

| Area | Required proof |
| --- | --- |
| Base and packages | Approved digest-pinned RHEL bootc base and package-access path; record installed RPM versions/repository inputs as well as source revision. Validate final image labels against the effective EC policy, including product identity/CPE and CI-provided metadata. |
| Runtime payload | reviewed native declarations and resolved build evidence for Red Hat–built inputs under the chosen [payload option](pipeline-spec.md#runtime-payload-corenet-7505); a digest-pinned `frr-metrics` binary; health checks in Ansible without an extra container (CORENET-7505) |
| Configuration | no generated inventory, private keys, baked user SSH key, mutable image ref, or secret-bearing build output |
| Networking | configuration survives reboot; supported transport/MTU selection validates before mutation; resources removed only by deployment ownership markers |
| Access | an approved launch-time access path for each disk format, without a baked credential: an approved AWS mechanism for the AMI (for example, EC2 metadata), and a hypervisor mechanism for on-prem disks, such as the vSphere guestinfo/OVF properties Portal's vmdk reads at first boot, or a cloud-init seed for KVM; no shared default password |
| Operations | defined health endpoint/log path and observable failure behavior; the selected systemd/container-management implementation is tested on bootc |

Use native `systemd-analyze verify` for authored units/drop-ins when the selected image
build supplies their dependency/executable paths. Validate against that image's filesystem
and supported systemd version; do not substitute an unrelated host's installed services or
write a unit-file parser. Where supported, use `--recursive-errors=yes --man=no --generators=no`
so verification warnings fail without documentation/generator side effects. Source-only
runs are diagnostic when required image executables are absent. This belongs in the native
image validation lane, not a speculative extra source-CI tool/job.

Without `--recursive-errors=yes`, an unknown directive only warns and exits 0 (host
systemd 258.11, 2026-10-12; option added in v250, see
[`23799eb9`, man/systemd-analyze.xml](https://github.com/systemd/systemd/blob/23799eb9be13c9726c707c9fd7239d99dc25889d/man/systemd-analyze.xml)).
Passing verification does not prove boot, handler ownership or network behavior.

Run the selected bootc version's `container lint` after the final filesystem
changes, failing errors and unapproved warnings (`--fatal-warnings` where supported).
`bootc container lint --list` shows what that gate covers. In 1.16.13 there are seven
fatal checks (`bootc-kargs`, `kernel`, `var-run`, `api-base-directories`, `etc-usretc`,
`baseimage-root`, `utf8`) and eight warnings that `--fatal-warnings` promotes (`var-log`,
`sysusers`, `baseimage-composefs`, `runtime-deps`, `var-tmpfiles`, `nonempty-boot`,
`buildah-injected`, `nonempty-run-tmp`). `bootc-kargs` rejects a malformed or mis-keyed
`kargs.d` file but not a wrong argument: `fisp=1` passes, so assert the FIPS argument and the
booted state separately.
Konflux's build task appends metadata after the Containerfile's last step, so also
lint the pushed image. By default it writes `/root/buildinfo`, which is
`/var/roothome` in bootc images. The bases already ship `var/roothome/buildinfo/*.json`
in their last layer (CentOS Stream 9 on September 23, `rhel9-eus/rhel-9.8-bootc` on
September 29), which `var-tmpfiles` rejects under `--fatal-warnings`: the unmodified
CentOS Stream 9 base (digest `a7ae6e28…`, built September 28) fails bootc 1.16.13's lint
with that one warning ([bootc #1546](https://github.com/bootc-dev/bootc/issues/1546),
closed in August 2025 as a CI mitigation, is the history, not a fix). Set
`ICM_KEEP_COMPAT_LOCATION=false` and remove inherited copies, after confirming that
scanners and policy read `/usr/share/buildinfo`
([layer evidence](source-evidence.md#11-bootc-specific-build-behavior)).
Create runtime directories such as `/run/frr` at boot with the required ownership
and labels; a Containerfile `mkdir /var/run/frr` does not survive the runtime tmpfs.
The lint reports it as `nonempty-run-tmp`, non-empty logs as `var-log` and other `/var`
content as `var-tmpfiles`, which also prints the `tmpfiles.d` line to add (measured on the
CentOS Stream 9 base). Use supported tmpfiles/service-directory handling and test it
after reboot.
Qualify upgrades on an already configured host: locally modified `/etc` can mask
new image defaults, and new image content under `/var` is not applied on upgrade.
Keep Ansible-owned configuration and image-owned defaults explicit; test migration
and rollback with retained state. [Filesystem contract](https://bootc.dev/bootc/bootc-filesystem.7.html),
[build lint](https://developers.redhat.com/articles/2025/02/26/best-practices-building-bootable-containers).

**PR #6 review, 2026-10-12:** its proposed
[`67524c74`, `image/rhel10/Containerfile`](https://github.com/openshift/evpn-gateway-appliance/blob/67524c74561280138e12fa55b4439ac131f7f8f7/image/rhel10/Containerfile)
writes image-owned units/drop-ins under `/etc/systemd/system`. The
[maintainer's placement question](https://github.com/openshift/evpn-gateway-appliance/pull/6#discussion_r4210638961)
fits the proposed ownership split: put image-owned units in `/usr/lib/systemd/system` and
local Ansible overrides in `/etc/systemd/system`. Upstream
[`724d18a2`, `man/systemd.unit.xml`](https://github.com/systemd/systemd/blob/724d18a22ac466b058a104de69bf7226acec4729/man/systemd.unit.xml)
defines their precedence. #16 places its generated Quadlet units under
`/usr/share/containers/systemd/`. Confirm the chosen layout on the RHEL base and test image
updates with a retained local override; this review is not boot or upgrade qualification.

The [public CentOS mirror suggestion](https://github.com/openshift/evpn-gateway-appliance/pull/6#discussion_r4210828876)
is a Prow test-base proposal. CI's [external-image policy](https://docs.ci.openshift.org/how-tos/external-images/#mirror-private-images)
does not support central mirroring of external private images. Recheck authenticated RHEL
registry/build access separately. Qualify any public mirror, replacement
base and payload access before selecting that lane. A CentOS smoke does not qualify RHEL
package contents, FIPS or support; retain an authenticated build on the chosen RHEL base.

Define CORENET-7511's supported FIPS configuration for the selected RHEL version
and architectures. Its image must set `fips=1` through `/usr/lib/bootc/kargs.d/`
and enable the FIPS userspace crypto policy, following
the [RHEL
procedure](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/using_image_mode_for_rhel_to_build_deploy_and_manage_operating_systems/enabling-the-fips-mode-while-building-a-bootc-image).
RHEL-family kernels refuse to load WireGuard in FIPS mode, and WireGuard is a
Technology Preview ([CentOS Stream 9
kernel](https://gitlab.com/redhat/centos-stream/src/kernel/centos-stream-9/-/commit/840b99a9),
[RHEL 9.7
notes](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/9.7_release_notes/technology-previews)).
An always-FIPS generic image cannot run the WireGuard dev/test transport. Options are
WireGuard tests in explicitly non-FIPS development environments, development and lab
topologies over IPsec, or a separate FIPS variant and test lane; a separately shipped
variant needs approval under decision 12. Lab results do not qualify production FIPS behavior.
Also decide whether `wireguard-tools` belongs in the supported image. The same kernels
disable their `md5` hash in FIPS mode, and TCP-MD5 BGP signatures depend on it. FRR's only session authentication is
that MD5 password (TCP-AO is an open feature request, FRRouting/frr#7240), and GTSM
(`ttl-security`) limits reach without authenticating. CORENET-7511's BGP authentication
therefore needs a FIPS-mode answer for each actual session, agreed with Product Security
([crypto
manager](https://gitlab.com/redhat/centos-stream/src/kernel/centos-stream-9/-/blob/a78a602ce2/crypto/testmgr.c)).
Separate the EVPN overlay peers from AWS underlay routing peers. IPsec can protect
the VPN path's sessions, but does not authenticate an unrelated DX VIF session.
AWS [requires TCP-MD5 on Direct Connect VIFs](https://docs.aws.amazon.com/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html);
record whether the appliance or an external customer router terminates that session.
DX also [provides no encryption by default](https://docs.aws.amazon.com/directconnect/latest/UserGuide/encryption-in-transit.html).
Do not infer authentication or encryption from private connectivity. Qualify each
chosen peer/protection path without silently disabling FIPS or adding an unapproved
encrypted-DX variant with different MTU and performance limits.
On that configuration's candidate qcow2/AMI, assert `/proc/sys/crypto/fips_enabled`
is `1` and `update-crypto-policies --show` is `FIPS`; then exercise deployment, SSH/key rotation,
supported BGP authentication, applicable VPN operations, reboot and upgrade in
that mode. Scan the final image and every runtime payload with pinned
[`check-payload`](https://github.com/openshift/check-payload) on each platform;
OpenShift CI's `fips-check-image-scan` step runs it on an unpacked image, as
BGP Cloud Connector does. The inspected upstream `frr-metrics` v0.0.26 failed its
CGO check; certified native Go FIPS modules are another supported scanner path
([evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).
A scanner pass or a FIPS-enabled base alone does not prove the workflows above.
Use the [MicroShift/RHTAS examples](prior-art.md#fips-build-and-test-examples);
do not use `fips-mode-setup --check` or the presence of a particular dracut module
as the bootc acceptance check.

Every payload option adds RPMs: the RHEL 9.8 EUS bootc base's SBOM lists podman,
NetworkManager, nftables, python3, openssh-server and skopeo, but not cloud-init,
Libreswan, FRR, nmstate or greenboot.

- **Hermetic build.** For added RPMs, commit `rpms.in.yaml`, `rpms.lock.yaml` and
  approved repository inputs and enable RPM prefetch. Set `hermetic: "true"` in both PR
  and push PipelineRuns' `spec.params`; verify the actual build task's `HERMETIC=true`
  in signed provenance and prove package consumption without a network fallback. Canary
  that the effective release policy rejects a non-hermetic bootc build; a pipeline
  parameter or a green check with the rule excluded is insufficient. See
  [hermetic build configuration](https://konflux-ci.dev/docs/building/hermetic-builds/).
- **Privileged-nested.** Plan the bootc build on a remote MPC platform with
  `privileged-nested: "true"`: the remote buildah task documents it as the bootc
  workaround (a privileged build with a real `/var/tmp` for SELinux attributes), and the
  bootc policies in cached KRD for RHEL's own bases, xKS, RHEL AI, Portal, RHDH and
  CentOS Stream all exclude `buildah_build_task.privileged_nested_param`. Two other
  bootc products lack that exclusion: one excludes the whole `hermetic_task` rule instead
  and one excludes neither. RHEL's bases and xKS keep the
  hermetic rule, so hermetic remains a realistic target. CentOS Stream's
  [bootc push
  pipeline](https://gitlab.com/redhat/centos-stream/containers/bootc/-/blob/d22f06b8/.tekton/centos-bootc-push.yaml)
  (`d22f06b8`) pairs it with
  RPM prefetch on four platforms; Portal uses `linux-root/amd64`. Request that one scoped
  exception with evidence rather than copying either list.
- **Entitled packages.** Entitled RHEL packages, including AppStream's FRR under the
  package option, need build access. Konflux's documented path is a tenant
  [`activation-key` secret](https://konflux-ci.dev/docs/building/activation-keys-subscription/)
  that both the buildah and prefetch tasks read (Portal's PipelineRuns pass it).
  MintMaker's lockfile refresh of entitled RPMs also needs a labeled custom key secret
  and its matching RPM-lockfile configuration.
- **Resolution.** Resolve against the actual pinned base's rpmdb (`context.image` or a
  Containerfile context, not `bare`); ART's MicroShift bootc build records that bare
  resolution omits base-kernel conditional dependencies
  ([evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)). Include source
  RPM repositories for source-container completeness. Preserve package/TLS verification.
  Portal's lockfiles are useful examples; keep EVPN's build hermetic with package
  signature checks on.
- **Refresh.** Regenerate with base/input/repository changes in the same reviewed PR; run
  required checks on the resulting commit. Prove the selected update paths refresh the
  correct lockfile. If using MintMaker, its `refresh-rpm-lockfiles` preset does not supply
  a native Component nudge's update step. Accept an unchanged lockfile only with
  successful resolution/validation against the new inputs, rather than requiring a file
  diff or exempting bot branches. Scope RPM inputs/prefetch to the Component and verify
  subdirectory output/commit paths; a skipped updater is not successful refresh
  evidence. The refresh preset's
  [documented CVE-information limitation](https://konflux-ci.dev/docs/mintmaker/user/#configuration-presets)
  also requires independent vulnerability scanning and remediation checks. See the
  [AAP example](prior-art.md#build-and-release-implementations),
  [RPM prefetch](https://konflux-ci.dev/docs/building/prefetching-dependencies/#rpm) and
  [Mintmaker lockfiles](https://konflux-ci.dev/docs/mintmaker/rpm-lockfile/).

Keep `build-source-image` enabled for the registry-shipped bootc image. Feed the
final index digest into `source-build-oci-ta`'s `BINARY_IMAGE_DIGEST`, together with
source and prefetch artifacts, as Portal does. Resolve its `sha256-<digest>.src`
companion and retain its digest. Verify source/SRPM coverage for every shipped
platform and payload, including content copied from other build stages. The
checked task discovers parents from only the first index child's SBOM and final
`FROM`; it can continue without parent sources when that SBOM is empty. Use the
supported `BASE_IMAGES` override if needed, and verify the resulting source archive.
A successful task can also report `drop` with empty source-image outputs; reject
that for this artifact. A nonempty source container alone is not completeness proof.
Verify source publication and customer access in stage with `pushSourceContainer`;
the managed registry publisher defaults it to true. This companion is not another
product Component. [Task
contract](https://github.com/konflux-ci/container-build-catalog/tree/094f3fe/task/source-build-oci-ta).

Inspect the source archive's contents as well as its completeness. The checked
[archive
builder](https://github.com/konflux-ci/build-tasks-dockerfiles/blob/5ab0fa76/source-container-build/app/source_build.py)
uses `git ls-files --recurse-submodules`; the binary build context, `.containerignore`
and Git `export-ignore` do not limit that inventory. Keep private/generated lab
material out of tracked source inputs. If repository separation or filtering is
needed, agree a supported path that retains all required sources before publication
(KFLUXSPRT-7230/3291). Collection archive exclusions do not cover this artifact.

## Component design

Build one generic bootc appliance Component first. Build qcow2, raw (the AMI input)
and any approved vSphere format as BIB derivatives from its nudged digest; do not use independent
multi-stage rebuilds
as a substitute for the digest dependency chain. Platform overlays are allowed
only where their package/configuration delta is explicit and they still consume
the pinned generic bootc digest. bootc-foundry's `rhel-10-ec2` shows a typical EC2
delta (cloud-init, `nm-cloud-setup`, Amazon time/SSH settings). A vSphere
deliverable needs vmdk/ova and its own reviewed guest-integration delta
([platform evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).

Agree the image/collection service contract with that first payload. The
[source audit](source-audit.md#1-security--identity-findings) records the container-versus-host
FRR lifecycle conflict between the proposed images (#6, #16) and the merged collection. Start one native host scenario
for the selected image and installed collection: deployment and notified restart must use
the intended lifecycle, preserve image-owned defaults and work after reboot. Do not use
a build result or role lint as that proof, or add a general inventory validator to bridge
two different payload designs. The non-releasing build can still qualify independently.

The base stream sets the update cadence and an end date. RHEL 9 offers
`rhel9/rhel-bootc` and EUS streams such as `rhel9-eus/rhel-9.8-bootc`;
`rhel-9.4-bootc` reached end of life on 2026-08-25. RHEL 10 has defined platform
bases, including `rhel10/rhel-bootc-aws` and `rhel10/rhel-bootc-kvm`, though
registry.redhat.io served neither on 2026-09-29. Deriving from those would replace EVPN-owned
platform deltas, but would make the AWS and on-prem images separate bootc Components. Only
if FRR came from the RHEL package would RHEL 9 have to be 9.8 or later in the checked baseline (EUS:
`rhel9-eus/rhel-9.8-bootc`) until 9.6 delivery lands. Record the chosen stream, its end date and
the planned minor-version move, and keep refreshes inside KONFLUX-15693's errata windows once
that gate ships ([base evidence](source-evidence.md#11-bootc-specific-build-behavior)).

Under the OCP-image direction from the 2026-10-01 review ([decision
record](kickoff-decisions.md#already-settled)), run `frr-rhel9` by digest as the FRR container
and use the `/frr-metrics` in that same image; the review also requires changing it to need no
cluster and to export EVPN metrics. #16 (2026-10-15) follows option A with the 4.22 image as
bound Quadlet containers; #6, now on hold, proposed the package option for RHEL 10, which would
change the recorded direction and needs an owner/date decision before it is treated as approved. Under that option, install
`frr10` (RHEL 9) or `frr` (RHEL 10) in the Containerfile, enable `frr.service`, and
copy `/frr-metrics` with a digest-pinned `COPY --from` of `frr-rhel9` (OCP has no
separate frr-k8s image), so that updaters and the SBOM track it. The package's
tmpfiles and sysusers entries create `/run/frr` and the `frr` user; verify them
after reboot. On an SELinux host `frr10` also pulls its `frr10-selinux` policy package
(a conditional dependency in CentOS Stream 9's metadata; confirm on the RHEL base), so boot tests
run enforcing and check
for AVC denials from FRR, the metrics binary and any container-run payload. Verify each
binary's architecture per platform.

Keep image references in the native input that actually consumes them: Containerfile
`FROM`/`ARG` for build payloads, BIB's wrapper for its builder/source/origin, and the
collection's approved release reference for deployment. Prefer one declaration per input
and native updater support. Record the effective resolved digests in build provenance/SBOM
and retained candidate evidence. The plan does not require a shared YAML/env inventory,
a converter into three formats, or an inventory validator before the native build.
Where two consumers truly need the same value, use their existing dependency/update
mechanism first and assert only a demonstrated residual mismatch. CI rejects floating
release inputs at the consuming build/policy boundary. Whether runtime images are preseeded or pulled at boot is a
product decision: the selected behavior must be tested both with the stated
registry-egress policy and after reboot.
Retain the prior payload through failed upgrade/rollback and test registry failure
during recovery. Evaluate preseeded images (Portal/AAP-68191) or bootc's logically
bound images on the selected RHEL version; the latter coordinates pulls and
retention with OS deployments. Do not assume an OS rollback restores independently
updated or pruned Podman images. This does not require a general disconnected
installation feature.
For logically bound images, prove installation populates their store and configure
each consuming service to use it; the documented Podman setting is
`--storage-opt=additionalimagestore=/usr/lib/bootc/storage`, scoped to those services.
Test their actual pinned payload with registry access unavailable after installation
and during rollback. See the [payload-delivery examples](prior-art.md#payload-delivery).

If embedding images, canary the hermetic build with full OCI configuration and
payload inventory intact; Portal and RHEL AI drop the hermetic rule to pre-pull
images, which EVPN should avoid. Outer build-stage pre-pulls do not make full images
available to nested Podman; reconstructing a rootfs via `podman import` can lose
ENV/ENTRYPOINT/CMD and other metadata, and multi-layer images copied into image
storage on overlay-on-overlay can lose whiteouts (RHEL AI's workaround is in
KFLUXSPRT-8581). KONFLUX-15262 and
[Buildah #6944](https://github.com/podman-container-tools/buildah/issues/6944) remain
open. Verify the embedded image's identity and runtime behavior, including any
intentional transformation, rather than assuming base-image prefetch solves this.

Select target-platform children for nested image pulls and the extracted metrics
binary, and verify their architecture and execution in every shipped platform's
boot test. If using `TARGETARCH`/`TARGETPLATFORM`, declare the build arguments in
each consuming stage and reject unsupported or missing values. Portal's
`--arch ${TARGETARCH:-amd64}` fix is an x86_64 precedent, not multi-architecture
proof; see the [Containerfile argument
contract](https://github.com/containers/common/blob/a5ccdae8/docs/Containerfile.5.md#L609).

`enforceContainerFirstSecurityLabels` does not specify the first filesystem
layer or a four-label checklist; its schema describes `name` and `cpe` values.
Set approved product identity in source and inspect the resulting image after
build-task label injection. Use the target policy's complete required-label set.
Review `name` against customer repository mappings and any justified `canonicalName`;
the release task accepts that override even for a single destination. Canary absent
`cpe` as well as mismatches: `check-labels` skips absence, so presence needs the
effective policy/source gate ([checked
behavior](source-evidence.md#5-release-configuration-and-publication-need-their-own-gates)).

Do not assume Quadlets, cloud-init, SSM, or a particular AWS agent is mandatory.
Choose the least-complex supported mechanism that satisfies access, lifecycle,
and recovery tests on the supported RHEL/bootc version. If it requires cloud
metadata or a launch agent, include it in the image and validate it in the raw
AMI test rather than treating a Containerfile build as proof.

## Source stop-ships

Before the [public import](source-audit.md#0-public-import), remove private access
and generated material. Keep credentials and baked access out of artifacts/logs, and
review build execution risks before running it. Contain unresolved runtime
exposures in the selected test scope before deployment; the security and functional
findings below must be resolved before a supported release:

- personal/public fallback SSH access, tracked generated inventory, controller
  plaintext private keys, and `no_log` omissions around secret material;
- global host-key bypasses, broad public SSH/BGP rules, and secret values in
  CI logs;
- unreviewed runtime privileges or host mounts, unauthenticated metrics listeners on every
  interface, and BGP peers with no inbound policy or limits ([source
  audit](source-audit.md#1-security--identity-findings));
- selectable but unimplemented transports, unsafe default MTU/DF/MSS choices,
  ephemeral network state, and broad interface cleanup patterns; and
- the legacy standalone cloud workload VTEP in the production path
  (CORENET-7515).

A bounded non-releasing build can proceed before transport/feature completeness
with reviewed source, build inputs and execution scope. Record its build evidence
separately from runtime qualification.

The source must make the production topology configurable from validated OCP
frr-k8s peer data. A single hard-coded lab router or current three-node
health-check topology is not a product interface.

## Acceptance checks

1. Non-releasing Konflux bootc build produces an approved digest, SBOM, and
   Snapshot from the reviewed source.
2. Native image-source lint, secret scanning and image-reference consistency pass
   before publishing the candidate image. Collection lint/build/install and runtime
   argument/preflight rejection qualify the collection paired with that candidate;
   collection packaging is not a prerequisite for a non-releasing image build.
3. The qcow2 derivative boots and recovers service/network configuration after
   reboot.
4. The raw derivative imports as an AMI that boots in AWS and reports the
   candidate bootc digest, with ownership-scoped cleanup. A `bootc install
   to-existing-root` conversion does not qualify the delivered AMI.
5. Required transport, HA, OCP, AAP, security, upgrade, and rollback gates in
   `pipeline-spec.md` pass before calling the appliance supported.
