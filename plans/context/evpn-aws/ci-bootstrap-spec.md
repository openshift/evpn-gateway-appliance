# CI bootstrap specification

The CI design has two separate responsibilities. Build CI must produce the
collection and appliance artifacts from recorded, pinned inputs; integration CI
must exercise the privileged, cloud, and topology behaviours that a normal build
pod cannot.

[`ci-source.md`](ci-source.md) owns the static checks in `verify`. This document
proposes later checks and records tool evidence. Jira criteria and recorded decisions
govern scope; listing a tool does not require installing it.

## Later CI

The later rows are a backlog, not prerequisites for the [source-CI queue](ci-source.md#queue).

### Key CI infrastructure

Repository/runner state rechecked on 2026-10-15; older measurements retain their own dates.

| Piece | State | Blocks |
| --- | --- | --- |
| Prow onboarding ([#86165](https://github.com/openshift/release/pull/86165): tide, plugins, `ci-operator` config) | Merged 2026-10-06; the runner now builds the PR's `Dockerfile.ci` ([current state](ci-source.md#where-things-stand)) | A failing run that Tide refuses to merge is not yet recorded |
| Repository settings: secret scanning and push protection | Not checked; needs an organization or repository owner ([deferred](ci-source.md#deferred)) | Provider-token detection at push time |
| Update bot | None configured here. Dependabot version updates already run in the `openshift` organization (`check-payload`'s update runs); Renovate (`mintmaker`) serves Konflux components. Native Renovate extraction finds this build root's base image but misses its inline pip pins; qualify the chosen bot against the actual inputs ([proof and native alternative](#build-root-update-extraction)) | Automatic pip updates are not yet qualified |
| GitHub Actions | No owned EGA workflow is configured; request owner enablement only for a selected hosted lane | Optional rows |
| Konflux tenant and GitHub App (CORENET-7409) | No approved EGA setup is recorded here | Konflux lane in L6; Konflux candidate gates in L7 |
| AWS test identity and an OCP test cluster | No qualified EGA identity/cluster is recorded here | AWS and OCP qualification in L7; not unprivileged Molecule or a local simulated topology |

### Later sequence

Rows are ordered by useful follow-on work; stable IDs are not a serial dependency chain.
The [source-CI queue](ci-source.md#queue) does not wait for them. Dependency extraction accompanies tool
maintenance when useful; it does not precede product tests as a separate prerequisite.
Prefer role behavior and native builds before destination certification and scheduled link work.
Include required tool pins and checks in the same feature PR; verify the source it guards.
Gate proof (L1) accompanies each new required context rather than becoming a separate
project that holds the other work back.

| # | Add | Inputs needed | Tools | Done when |
| --- | --- | --- | --- | --- |
| L1 | Extend the gate proof to multiple build/test contexts as they arrive, including bot changes, delayed contexts and retries | The existing `verify` context and the additional contexts being made required; prove each merge boundary as it arrives | Prow, `tide` | Each expected current-commit context blocks merge when missing or failed |
| L5 | Bounded role validation/behavior, then per-role Molecule coverage | One reviewed role entry point first; scenario tools/dependencies and an appropriate runner for the selected behavior; no destination approval, manifest migration or tenant prerequisite ([test placement](#test-placement)) | Pinned Molecule with native Ansible inventory/playbooks for the first scenario; direct Ansible proof only when it avoids a demonstrated setup blocker | Invalid input fails before mutation; Molecule coverage for every shipped role, with idempotence for mutating roles and relevant validation/behavior failure cases; privileged/cloud behavior uses its required lane |
| L6 | Native Containerfile build first; Konflux pipeline extension later | Reviewed image source, approved base/package inputs and a qualified build runner; tenant/GitHub App/MPC capacity only for the Konflux extension | Podman/Buildah, `bootc container lint`, native systemd unit verification for authored units; reuse Konflux build tasks when onboarded | Native clean build passes and broken COPY fails; the later Konflux build adds provenance/SBOM and a qualified merge context |
| L2 | Native tool-pin extraction as maintenance warrants; update automation later | Existing pins and [qualified extraction](#build-root-update-extraction); owner authorization only for bot activation; any pin-layout change has its own image proof | Dependabot or Renovate | The bot extracts every intended package and image pin; a bump PR has independent candidate-image proof and passes the current-SHA gate. A base-image-only PR does not prove pip coverage |
| L4 | Destination-required collection import/sanity/docs checks | Approved destination/content class and supported matrix; reviewed tarball and pinned tools | Native importer/sanity commands; optional nox wrapper only for a demonstrated orchestration need | The required destination checks pass on the built artifact; reviewed exceptions are explicit |
| L3 | Scheduled checks, never merge-blocking: link liveness, pinned-link resolution, fresh-resolution collection compatibility | The corresponding source target and a scheduled runner; no unrelated lint prerequisite ([what may block](#what-may-block-a-pull-request)) | Existing link/pin targets; lychee after coverage parity; scheduled Prow or owner-enabled Actions | A broken link fails the scheduled job with a retained report and blocks no unrelated pull request; automatic issue creation is separate work |
| L7 | The simulated EVPN topology lane (CORENET-7508), then candidate gates: disk boot, AWS lifecycle, OCP lanes, release policy | Topology: reviewed roles/image and a runner with kernel networking; candidate gates: the artifacts and infrastructure each gate exercises | kind and containerlab as openperouter runs them, or a Konflux VM; the [pipeline plan](pipeline-spec.md#3-integration-gates-and-test-infrastructure) | The lane reports a required, nonzero set of EVPN checks |

Additional security/workflow engines need a demonstrated coverage gap worth their setup
and maintenance. Basic native lint and product scenarios proceed without a speculative
scanner suite or an additional workflow platform.

Start L5 with one real scenario, then extend the same suite as roles are ready. Reuse native
argument specs and role preflight rules; an extra schema/parser, nox suite or destination
checker is not a prerequisite. This does not claim current roles already reject all invalid
VNI/ASN/transport settings; the [local mechanism proof](#test-placement) is narrower.

L6 can use a native [Podman build](https://docs.podman.io/en/latest/markdown/podman-build.1.html)
once source, inputs and runner are approved. Keep resource/privileged builds in their
qualified lane, separate from offline source verify. Konflux tenant absence blocks the
Konflux extension, not this native build proof. A local build does not complete Gate B
provenance, candidate qualification or release approval.

### Build-root update extraction

Do not infer inline pip coverage from a bot's Dockerfile support. A 2026-10-06 offline
Renovate 44.119.1 extract of the then-current build-root Dockerfile found only the base
image and missed its inline `pip install` pins; a `requirements` file read with
`pip install -r` is extracted. Dependabot's Python support likewise needs a supported
manifest (Renovate's [Dockerfile](https://github.com/renovatebot/renovate/blob/ee46402e73cc334edb5fbbb6d91230a9a1903af2/lib/modules/manager/dockerfile/extract.ts)
and [pip requirements](https://github.com/renovatebot/renovate/blob/ee46402e73cc334edb5fbbb6d91230a9a1903af2/lib/modules/manager/pip_requirements/index.ts)
managers; Dependabot's [Python](https://github.com/dependabot/dependabot-core/blob/e29ea64fca53850c3c18799ef8c2aaadcfd5d23e/python/lib/dependabot/python/file_fetcher.rb)
and [shared](https://github.com/dependabot/dependabot-core/blob/e29ea64fca53850c3c18799ef8c2aaadcfd5d23e/python/lib/dependabot/python/shared_file_fetcher.rb)
fetchers; the Dependabot result is a source read, not an EGA run).

If update automation is wanted, move the `Dockerfile.ci` pins into a native manifest first,
verify it as [source CI](ci-source.md#how-to-add-a-check) describes, and assign one updater
per pin. Bot activation is the repository owner's choice and blocks no other check.

## Required source checks

The collection-CI criteria were split, rechecked read-only on 2026-10-16: CORENET-7507 is
Closed with YAML/Ansible lint complete; [CORENET-7667](https://redhat.atlassian.net/browse/CORENET-7667)
requires Molecule scenarios for every role, VNI/ASN/transport validation, and build/publication
to an approved Hub or Galaxy destination. The merged `check-ansible` lint/build/install
checks are the baseline; Molecule scenarios, input validation and publication remain under
7667. Neither nox, a second input schema, documentation style lint nor a new execution
environment is an acceptance criterion.

Use existing `make verify OFFLINE=1`, with one native target/prerequisite per selected check.
The [source-CI queue](ci-source.md#queue) owns priorities. Keep testing the tarball outside
the checkout so source roles cannot hide packaging failures. Static checks do not execute
argument validation or prove runtime dependencies. Runtime negative scenarios must invoke
the same argument specs and preflight assertions as deployment, proving rejection before change.

Measured on the prototype (`1c8e88873af8`, exported clean, 2026-09-29). #7 changed this
source, so treat the counts as what each tool can and cannot see, not as today's baseline:

| Check | Result | What it shows |
| --- | --- | --- |
| `ansible-lint` 26.4.0 from `ansible/`, default profile or `--profile production roles playbooks` | Same 113 findings in 16 files: 83 `var-naming[no-role-prefix]`, 12 `risky-shell-pipe`, 8 `ignore-errors`, 7 `name`, 3 other, including a `load-failure` for the `playbook_dir` include | The largest bucket is a mechanical rename; the pipe and `ignore-errors` findings need source review |
| `yamllint` 1.38.0, default config | 72 (58 are the 80-column `line-length`) | Default config is mostly line length; `ansible-lint`'s own YAML rules flagged one line |
| `ansible-playbook --syntax-check`, all 5 playbooks | Passes, although `amazon.aws` is not installed | `include_tasks` files are not parsed (a static `import_tasks` of the same file fails with `couldn't resolve module/action`), so syntax checking says nothing about declared dependencies |
| Collections used, none declared | `containers.podman`, `amazon.aws`, `ansible.posix`, and `community.aws` (teardown only) | Installed alone, the tarball failed on `ansible.posix.sysctl`; `community.aws` matters for certified content ([decision 5](kickoff-decisions.md#gate-a--source-ci)) |
| `ansible-galaxy collection build` with a minimal `galaxy.yml` and no `build_ignore` | Succeeds and ships `inventory/hosts.yml` (public lab IPs), `ansible.cfg` and `.gitignore`; it ignores `.gitignore`, so a git-ignored `.wg-keys/` ships too | See [measured behavior](#measured-collection-build-and-import-behavior) |
| `detect-secrets` 1.5.0 on the tree | 0 findings | It cannot see the baked `authorized_keys` line or public IPs |
| `bootc container lint --fatal-warnings` (bootc 1.16.13) on the built image | Fails on 3 warnings: content in `/run` (`frr`, `pluto`, `rhsm`), `/var/log`, and `/var/cache/dnf`/`/var/lib/dnf` leftovers despite `dnf clean all` | The build itself needs no privileges ([lint coverage](containerfile-refactor-spec.md#required-outcomes)) |
| ShellCheck | 16 × SC2086, all in `image/build-ami.sh` | `hadolint` and `gitleaks` were not measured then |

Install selected tooling in the CI image rather than during test execution, and use clean and
seeded-failure runs as execution proof. Source verification needs no AWS identity, tenant or
developer workstation; role tests acquire privileges only for demonstrated behavior.

### Use maintained tools; keep custom checks small

Prefer a maintained tool, pinned in the CI image, to a program this project must keep alive.
The [custom-code budget](ci-source.md#custom-code-budget) lists the remaining helpers and when
each can go; [deferred](ci-source.md#deferred) records why the scanner and link-checker
replacements wait. Peer configurations ([prior art](prior-art.md#choose-the-example-by-delivery-problem))
are examples to reuse selectively, not a tool mandate; copy neither their whole hook suites
nor their suppressions.

#### Findings that change the design

- Prow is the required gate. `openshift` peers' workflow files had no relevant Actions runs
  (checked 2026-10-01), and enabling Actions needs owner authorization.
- pre-commit installs hook environments from the network at run time, which the offline
  `verify` job cannot do; this repository pins tools in `Dockerfile.ci` and calls them from Make.
- Required checks must report a current-SHA result; a skip cannot replace execution. The
  existing `verify` job has no path filters.
- Generated outputs need drift checks only where generation is actually used.
- Standalone ShellCheck does not see shell embedded in Tekton Tasks; when EGA authors Tasks,
  reuse the catalog's native task checks (for example Checkton) and upstream task tests.
- The old staged workflow in superseded #3 passed actionlint but had high-severity
  unpinned-action findings under zizmor. Fix authorization, permissions, checkout persistence
  and pins before any selected publication workflow holds credentials
  ([publication contract](#collection-and-ee-artifacts)).

#### Custom-logic audit

The [source budget](ci-source.md#custom-code-budget) owns existing and proposed source
CI glue. Do not maintain a second inventory here. Later custom work has these boundaries:

| Work | Reuse first | Residual work justified by the requirement |
| --- | --- | --- |
| Collection artifacts/publication | Native Ansible build, install, verify and approved publisher; native `manifest` inclusions | Required-content assertions, tested-content identity and customer readback; [artifact contract](#collection-and-ee-artifacts) |
| Role, health and topology tests | Native role argument/preflight validation and reviewed product health assertions; selected Molecule/containerlab lane | Appliance scenarios and expected-case assertions; [test placement](#test-placement) |
| Candidate/results/policy | Native jq, maintained Konflux formatter and effective Conforma policy | Exact candidate set, nonzero required cases and trusted subject/test revision; [candidate contract](pipeline-spec.md#candidate-snapshot) and [result contract](#test-placement) |
| AWS lifecycle/leases | Selected backend provisioning, cleanup and durable run records; Boskos only for shared Prow labs | Uncovered appliance assertions and owned-resource cleanup after partial creation/cancellation; [AWS contract](bib-configuration-spec.md#disk-validation-and-aws-lifecycle) |
| Publication evidence/retention | Release status, managed pipeline results and existing archive services | Binding/retrieval and channel readback that those services do not supply; [evidence](#evidence-visibility) and [readback](pipeline-spec.md#customer-readback) |
| Metrics/FIPS | Native promtool checks once rules exist, check-payload and built-image bootc lint | Product series/state and boot/runtime assertions; [metrics](pipeline-spec.md#metrics-corenet-74997504) and [image](containerfile-refactor-spec.md#required-outcomes) contracts |

These are requirements for selected later lanes, not six new programs. Before writing an
adapter, run the selected backend against one real scenario and identify the missing
behavior. Reuse upstream task lint/tests only when authoring Tasks; a few PipelineRuns do
not need a task-repository scaffold. A new artifact carrier, EE, result formatter, policy
engine or ledger service needs its own product or demonstrated implementation need.
[Prior art](prior-art.md#choose-the-example-by-delivery-problem) retains the concrete sources.

### What may block a pull request

Keep the source merge gate tied to maintained source and pinned tool inputs. Changing
external lookups (advisories, scanner databases, link liveness and latest versions) belong
on a schedule rather than failing unrelated PRs. Release-gate them only where the approved
product/security policy requires it. Selected runtime/integration tests retain their own
lane requirements. Automatic issue creation is separate work.

Vulnerability acceptance has its own release gate ([agent
guide](agent-guide.md#verified-facts-that-are-easy-to-get-wrong), Policy row).
Fresh-resolution compatibility runs on a schedule ([collection
contract](#collection-and-ee-artifacts)). `make verify` follows the split: its link check is
offline. A later qualified native online target belongs in a scheduled job; full local
`make check` keeps the current authenticated helpers until their replacement proofs pass.

## Test placement

Run the selected native lint, collection build/install and source scanning checks in the
normal PR and push CI path. Add schema validation only for a demonstrated invariant; reuse
product preflight assertions in runtime tests rather than writing another validator. Use Molecule's native Ansible inventory/playbooks for the smallest scenario; a localhost
controller/preflight case needs no container driver. Run it in that path when the selected
behavior works unprivileged. Put only tests requiring Podman privileges, systemd, kernel
networking, AWS credentials, physical trunks, Direct Connect, or an OCP EVPN
topology in a dedicated ITS, Testing Farm, or delegated-lab pipeline.

Run the Molecule `idempotence` step for each role that
changes a host: 7499 requires idempotent deploy and teardown, and the AWS role's 46 `aws` calls
through `command` make its idempotency hand-built ([source
audit](source-audit.md#aws-role-and-certified-content)). Where a driver cannot support the step,
record the reason and the lane covering the property. Document mock/container overrides and
which lane covers the hidden behavior (kernel networking, FIPS, SELinux or AWS APIs); a green
container scenario alone does not qualify it. Give validation its own negative
scenarios: an invalid VNI, ASN or transport input must fail before any host change, with the
host left unchanged and the failure report asserted (7499, 7501, 7667).

Use the role's `meta/argument_specs.yml` for types, required values and choices, and its own
preflight assertions for domain bounds and cross-field rules. Exercise those same entry points
from CI; a parallel Python validator or JSON schema would repeat the role's rules without
proving that deployment uses them. Keeping the first negative cases in the Molecule suite,
with native Ansible inventory and a short sequence, avoids a preflight runner whose cases
would later move. A direct Ansible target is still useful if a
specific tooling blocker delays the scenario; reuse the same playbooks and remove duplicate
execution once Molecule owns them. Neither path needs cloud identity for controller-only
validation.
Test the installed collection for packaging-sensitive cases. An isolated metadata-validator
call alone does not prove the real deployment path rejects input before making a change.

Argument specs alone are not enough. On 2026-10-12, native `validate_argument_spec`
against the on-prem role's [argument specs](https://github.com/openshift/evpn-gateway-appliance/blob/31cfdbb94c680a5107d8fc5ccd246a30b25860f6/ansible/roles/evpn_onprem_appliance/meta/argument_specs.yml)
accepted negative VLAN/ASN values and `ipsec`, which has no setup path; only an unknown
transport failed. Add role preflight assertions before the first mutating task and prove
the real entry point rejects those cases.

Molecule's [Ansible-native configuration](https://docs.ansible.com/projects/molecule/ansible-native/)
([source](https://github.com/ansible/molecule/blob/da31a19eb0c2aa50faa7255a42ee9792bafa4361/docs/ansible-native.md)) runs a localhost `converge`/`verify` sequence on existing inventories and playbooks without
a container driver, VM or cloud credentials (checked locally with Molecule 26.10.0 on
2026-10-12). Start with one real role scenario; do not copy example host-key bypasses or
pick a platform matrix up front.

Merged
[role validation](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/playbook/role/__init__.py)
and [validation action](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/plugins/action/validate_argument_spec.py)
explain the native entry point. Keep fixtures with the selected scenario and any residual
glue in the [source budget](ci-source.md#custom-code-budget).

Reuse reviewed product health assertions across role, topology, boot and upgrade tests.
The merged
[`evpn_health_check` role](https://github.com/openshift/evpn-gateway-appliance/blob/31cfdbb94c680a5107d8fc5ccd246a30b25860f6/ansible/roles/evpn_health_check/tasks/main.yml)
and [health playbook](https://github.com/openshift/evpn-gateway-appliance/blob/31cfdbb94c680a5107d8fc5ccd246a30b25860f6/ansible/playbooks/health-check.yml)
already define Ansible assertions, conditional on inventory groups; they are not yet
qualified product behavior. Each lane must prove its expected assertions ran; an omitted
host group or skipped topology branch is not health evidence. A single-host boot lane cannot
prove the three-node topology. Use tmt only if the chosen backend benefits from it; do not
rewrite the product checks or ship a test harness merely to standardize their invocation.

CORENET-7508's simulated topology needs kernel networking but no credentials.
Peer CI demonstrates a hosted-VM option. Upstream OVN-K runs its `evpn`
lane on GitHub-hosted Ubuntu with kind and an external FRR container
([evidence](source-evidence.md#9-payload-platform-and-ocp-test-inputs)).
openperouter, the FRR EVPN router in CNV-91892 and TELCOSTRAT-324, runs containerlab
fabrics there too. Its [CI
matrix](https://github.com/openperouter/openperouter/blob/4d69e363/.github/workflows/ci.yaml)
includes a Quadlet-based `systemdmode` host deployment and a `hostmode-boot` lane
that starts the router from static configuration files without its controller;
both are closer to the appliance and relay than a Kubernetes lane. CORENET-7502's all-active multihoming
fits the same simulation: FRR's [`bgp_evpn_mh`
topotest](https://github.com/FRRouting/frr/blob/7fca2819/tests/topotests/bgp_evpn_mh/test_evpn_mh.py)
dual-attaches hosts to two VTEPs with Linux 802.3ad bonds sharing `ad_actor_system`
and asserts Type-1 routes, ES readiness, MAC learning and DF election. Physical LACP
qualification remains separate.

Those runners also expose KVM: RHEL System Roles tests its networking role in
CentOS Stream 9/10 VMs and bootc containers across an ansible-core matrix
([workflow](https://github.com/linux-system-roles/network/blob/9a4537d21b/.github/workflows/qemu-kvm-integration-tests.yml)).
The `openshift` org enables Actions only when the repository owner requests it
(PCO-1330). The selected EGA lane must exercise its actual artifacts. Inside Konflux,
the catalog's `kind-aws-spot` provisioner can host the same topology on an
AWS VM with SSH access (run-owned Secrets; the VM is destroyed by timeout or `deprovision`) ([BIB
contract](bib-configuration-spec.md#verified-task-baseline)).
OpenShift CI's ordinary test pods are unprivileged. Its `nested_podman` step option
runs rootless Podman in a user-namespaced pod with only SETUID/SETGID
([SCC](https://github.com/openshift/release/blob/f348a67312/clusters/build-clusters/build-shared/nested-podman/rbac.yaml)).
That may allow veth, bridge and VXLAN devices inside the pod's own network
namespace, but it cannot load kernel modules; canary it before choosing it over
hosted runners, a Konflux VM or privileged pods on a claimed test cluster.

CORENET-7509's job templates, surveys, webhook trigger, RBAC and approvals need a
running Automation Platform; an EE run cannot test them. Keep them as code in the
collection (certified `ansible.controller`/`ansible.platform` modules; a validated
`infra.aap_configuration` dependency only if the content class allows it) and apply
them to a disposable AAP, either the [containerized
installer](https://gitlab.cee.redhat.com/ansible/aap-containerized-installer/-/tree/6277f6bb)'s
single-host growth topology on a VM or the AAP operator on the OCP test cluster.
AAP's own ephemeral-instance configuration-as-code testing is in progress under
[ANSTRAT-2281](https://redhat.atlassian.net/browse/ANSTRAT-2281).

Ship dashboards and alert rules as versioned source. When rules arrive, use pinned
`promtool check rules --lint-fatal` and `promtool test rules`; candidate tests verify
expected source series, labels and query states, including valid empty healthy results.
Follow the [metrics contract](pipeline-spec.md#metrics-corenet-74997504).
Add dashboard lint only for a demonstrated invariant; no extra framework is prescribed.

Place Konflux tests as the [pipeline
plan](pipeline-spec.md#3-integration-gates-and-test-infrastructure) describes: component-context
checks for PR feedback, and a required `push`-context suite on the complete post-nudge candidate.
Optional ITSs may give slow PR feedback but cannot be the only proof of qcow2 boot, raw-to-AMI boot,
upgrade/rollback or EVPN interoperability.

Make each qualification adapter prove its failure path: failed assertion, zero
tests, missing/malformed `TEST_OUTPUT`, skipped task, timeout and credential error.
Konflux reads TaskRun results, accepts `SKIPPED`/`WARNING`, and can pass a successful
pipeline with no test results. Check required task/assertion coverage and truthful
result counters; an aggregate green status is insufficient. Emit results from the
test Task, with infrastructure errors failing the gate, and retain detailed logs.

The controller's `TEST_OUTPUT` schema is strict: `result` is case-sensitive and `timestamp`
is a 10-digit epoch or an ISO date-time. One maintained formatter is `make_result_json` in
[`konflux-test` `93d5bd8f`, `test/utils.sh`](https://github.com/konflux-ci/konflux-test/blob/93d5bd8fc7acab112e33cd37c07d7398d05270aa/test/utils.sh). Its
[upstream tests](https://github.com/konflux-ci/konflux-test/blob/93d5bd8fc7acab112e33cd37c07d7398d05270aa/unittests_bash/test_utils.bats)
cover formatting; their presence is source evidence, not an EVPN execution proof.
On 2026-10-08 it rejected an unknown result but returned empty output with status 0 for a
nonnumeric counter and serialized negative or fractional counters. Validate the single
emitted JSON result and its nonnegative integer counters with jq against the
[controller contract](https://github.com/konflux-ci/integration-service/blob/2508848c0ee92ee1896de755ea38b586070348de/helpers/integration.go)
before publishing it, and fail the Task if validation fails.
Map actual backend failures/errors to `FAILURE` or `ERROR`; use `SUCCESS` only when every
required case passed, the expected count is nonzero and candidate evidence is verified. A helper
that formats JSON does not prove which cases ran or which subject they tested.
For external test backends, verify the actual deployed image/digest and installed collection from
runtime evidence. An override parameter or echoed install command does not prove the selected
candidate ran; reject unverifiable subjects.

For Prow-backed qualification, use an adapter for the selected EVPN job and full
candidate. The stock `run-prowjob` task builds a public GitHub archive URL from PaC
labels, which suits EVPN's public repository, but it selects one triggering
Component, emits no `TEST_OUTPUT`, and leaves the remote job running on interrupt.
Adapt candidate selection and case-level result collection; retain the remote job
ID early and prove bounded cleanup after Tekton cancellation or loss.
Compare the [OpenShift CI examples](prior-art.md#openshift-ci-adapters) before reuse.

## Evidence visibility

Choose evidence access independently of source-repository visibility. Use synthetic
traffic and inventories for qualification. Public results should preserve candidate
digests, run/test identities, assertion counts and useful failure diagnostics.
Keep customer/support captures and private inventories in approved restricted
storage, with the same candidate/run binding and release-gate read access.

Prevent credentials from entering stdout, JUnit, `TEST_OUTPUT.note`, console logs
or packet captures; disable shell tracing around secret handling and use Ansible
`no_log` where needed. Sanitize before publishing: integration reports copy task
notes into forge reports, and PaC can publish failure-log snippets. Check all output
surfaces with synthetic sensitive markers; a private artifact bucket does not
protect text already posted on a public PR. Automatic step-log masking remains
unproven for the target deployment ([source
evidence](source-evidence.md#3-retention-spans-artifacts-credentials-and-execution-sites)).

If a selected lane exports logs needed for qualification, verify access and completeness
and fail required evidence collection on missing or unreadable logs. Reuse the backend
records where sufficient; the stock [export task](prior-art.md#log-export-and-public-results)
can report success despite missing pods or failed reads.

## Collection and EE artifacts

Start reviewed role behavior tests before destination-required importer/sanity workflows;
the [later priorities](#later-sequence) keep these independent. Tests that exercise packaging
still use the installed tarball. Publishing to the chosen destination continues to require
its full supported checks; early role testing is not certification evidence.

Build the collection tarball from the valid collection root and retain its
archive checksum, tested `MANIFEST.json` digest, source revision and build provenance.
Verify the [native checksum chain](#collection-content-integrity), not only the manifest's presence. Validate `galaxy.yml`,
`meta/runtime.yml`, role argument specifications, version compatibility and
exclusion of lab payload, inventory, secrets and build output. Run pinned
`galaxy-importer` against the built tarball with explicit, verified configuration
for the chosen destination/content class. Its default disables `ansible-test`;
a successful local import is not certification. Add the required sanity/core-version
matrix separately, using AAP's agreed requirements rather than stale example pins;
for certified content, the Ansible partner team's SHA-pinned certification checker
bundles importer, production-profile lint and sanity-matrix jobs.
Use direct native commands for the selected importer/sanity checks; `ansible-test sanity`
installs its test environments from the network, so it runs in this lane rather than the
offline `verify` gate. Consider antsibull-nox
only when a real matrix or repeated environment setup would otherwise require custom orchestration.
The source read on 2026-10-07 of merged
[`antsibull-nox` `d611d9a8`, build/import session](https://github.com/ansible-community/antsibull-nox/blob/d611d9a87ee543eca2092a56650ce3a7b68ada0a/src/antsibull_nox/sessions/build_import_check.py)
found default Galaxy downloads and unconstrained core/importer installation. A wrapper pin
alone does not establish offline execution or reuse the CI toolchain. If selected for a
real matrix, configure only needed sessions and qualify provisioning/artifact identity;
no wrapper, docs/license suite or EE build is prerequisite to initial native smoke/lint.

### Measured collection build and import behavior

Probed on 2026-09-29 with a synthetic collection (ansible-core 2.21.4, ansible-lint
26.8.0, galaxy-importer 0.4.43). On toolchain changes, requalify the selected consumer
and relevant counterexamples as [source CI](ci-source.md#how-to-add-a-check) describes.

- **Exclusions.** `build_ignore` is a deny list of globs. `!` negation is not supported:
  `['*', '!roles', '!meta', ...]` builds a tarball holding only `MANIFEST.json` and
  `FILES.json`. With a deny list, any new file (an untracked `inventory2.txt`, a scratch
  directory) ships by default. This measured the deny-list path, not Ansible's `manifest`
  inclusion feature. The later manifest migration ([notes](ci-source.md#tool-notes)) uses that
  maintained builder feature plus required-path assertions, replacing `check-collection-tarball.sh`.
- **Identity.** Two builds of one tree differ in tarball bytes but produce identical
  `MANIFEST.json` and `FILES.json`, and on this fixture those files were identical across
  ansible-core 2.16.14, 2.18.9, 2.19.4 and 2.21.4. Comparing the manifest digest therefore
  survives `release_ah.yaml`'s unpinned `ansible-core>=2.16` in that case; still record the
  tool version and repeat the comparison on the real collection.
- **Importer verdict.** The importer fails on a `galaxy.yml` without `repository`, a
  missing `meta/runtime.yml` `requires_ansible`, and any role without a README. It only
  warns, and still reports success, for a missing changelog, a module from an undeclared
  collection (`syntax-check[unknown-module]`) and `requires_ansible: ">=2.16"` (its lint
  wants `>=2.16.0`). It did not object to a tarball that shipped an inventory and a private
  key. A passing import therefore proves neither the dependency list nor the exclusions.
- **Native install isolation, rechecked 2026-10-07.** An empty path/cwd alone did not qualify
  role discovery: a wrong-namespace artifact borrowed every expected role from `PYTHONPATH`.
  With an explicit install path, `ANSIBLE_COLLECTIONS_SCAN_SYS_PATH=false` and a minimal
  temporary `.cfg`, the clean artifact passed and the wrong one failed its required-role
  assertion. `check-ansible-install` sets only `ANSIBLE_COLLECTIONS_PATH` today
  ([queue](ci-source.md#queue)).
- **Installed alone.** The tarball installs, but `ansible-playbook --syntax-check` on a role
  that uses `ansible.posix.sysctl` fails until that collection is installed, so declare
  every collection the roles use.

### Collection content integrity

Merged ansible-core 2.21.4
[`997ad6b3`, `lib/ansible/galaxy/collection/__init__.py`](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/galaxy/collection/__init__.py)
builds `MANIFEST.json` with the SHA-256 of `FILES.json`, which lists payload checksums.
`install_artifact` checks payloads against `FILES.json` but omits the manifest-to-FILES
checksum comparison. `verify_local_collection` checks that link too. Comparing only
`MANIFEST.json` or relying on install success does not establish this chain.

A 2026-10-07 host check confirmed it: a tarball whose role and `FILES.json` checksum were
changed, with `MANIFEST.json` untouched, still installed, and
`ansible-galaxy collection verify --offline` rejected it.

In PR CI the tarball is built and installed in one job, so this matters once an artifact moves
between systems. At publication/readback, run `collection verify` and require both
content verification and the independently retained tested manifest digest; signature
verification authenticates that root when the channel supports it. Retain the tarball
checksum for exact-byte transfers; a trusted rebuild may change gzip bytes, so compare
verified content identity. Offline verification alone trusts the local manifest.
Installed-content verification does not scan unlisted archive members or replace
the approved packaging and public-input exclusions.
Use the [native verification contract](https://docs.ansible.com/projects/ansible/latest/collections_guide/collections_verifying.html);
no project checksum walker, new artifact schema or second workspace is needed.

The merged `ansible/tools/check-collection-tarball.sh` reports unapproved root paths,
requires README/runtime metadata and prints the manifest digest, but does not classify
files inside approved directories; `check-ansible-install` separately requires every
source role to be discoverable. Keep it until native manifest inclusions plus
required-path checks replace it ([budget](ci-source.md#custom-code-budget)).

Keep CI on the canonical repository and choose the approved destination and trusted
publisher under [decision 15](kickoff-decisions.md). For hosted Hub with owner-enabled Actions,
the [examples](prior-art.md#collection-and-lifecycle-references) provide a GitHub-release path
using ansible-content-actions' `release_ah.yaml`; Actions is a prerequisite for that workflow,
not for native collection publication. If selected, use a SHA-pinned, reviewed copy or
wrapper that compares the rebuilt `MANIFEST.json` digest with the tested one
and verifies its content chain before `ansible-galaxy collection publish`; tarball
bytes legitimately differ between builds of one commit. Hold the credential in a GitHub environment that
only approved release tags and release owners can deploy. Prefer the workflow's
service-account inputs: a personal offline token lapses unless something refreshes
it, which is why the same repository carries `refresh_ah_token.yaml`. Canary that
an unapproved tag, branch or fork cannot reach the environment and that a
rejected candidate cannot publish.

For an owner-selected Actions workflow, use least-privilege `permissions`,
`persist-credentials: false` on checkout, SHA-pinned actions and job timeouts. Pass shell
values through `env` instead of `${{ }}` expansion; never check out PR code in a
`pull_request_target` job. Start with native `actionlint`; add `zizmor` only for identified
security rules not covered by actionlint. Include selected tool pins with the workflow feature.
See GitHub's [secure-use guide](https://docs.github.com/en/actions/reference/security/secure-use)
and zizmor's [audits](https://docs.zizmor.sh/audits/).

A Konflux tenant publisher (RHTAS carrier image plus the standard `ansible-galaxy` publisher) or
AAP's Zuul job are alternatives. For a tenant publisher, declare the `release`, `releasePlan` and
`snapshot` string inputs; the controller supplies `namespace/name` references, unlike ITS `SNAPSHOT`
JSON. A separate service account in the build namespace does not isolate Hub credentials from
workloads that can select it or mount its secrets, so production use needs a managed or otherwise
isolated release service ([Konflux trust model](https://konflux-ci.dev/docs/trust-model/)).
Whichever path is chosen, rehearse on an isolated trial server or repository with verified
visibility and promotion settings. Hub's `staging` approval queue is not isolated: auto-approval can
promote its contents, and hosted Hub expects uploads ready for approval (AAP-47430).
`release_ah.yaml` hard-codes the production hosted Hub URL, so rehearse through a wrapper that
targets the trial server. The disposable AAP proposed above for CORENET-7509 can be that server: the
containerized installer's `samples/inventory-growth` includes `[automationhub]`.

Serialize collection publication and record destination, FQCN, version, manifest
digest and import/approval status. Wait for successful import and any required
approval, then poll customer visibility with a bounded timeout; upload completion
alone is not enough. Assign recovery ownership for a failed importer/approval
service and rehearse a retry (AAP-93498/93724). Resume an existing version only when
its verified content matches the tested manifest digest; otherwise fail and use a new version.
Do not delete/re-upload to make a retry pass. Verify through the actual customer
endpoint before installation; version equality alone is insufficient.

Follow the selected destination's approved signing contract. Where it requires collection
signatures, verify them with the customer's trusted keyring, independently of any OCI
carrier. When that contract uses Ansible's signature protocol, require `+1` or the
approved stricter count:
plain `1`/`all` accept an empty signature set, and `1` is ansible-core's default, so an
unsigned collection installs without complaint (read in 2.21.4's `verify_file_signatures`).
For that contract, reject unsigned, wrong-key and tampered content. Installing the extracted
local tarball does not exercise server-provided signatures; signed readback must use the
exact FQCN/version from the destination.
[Consumer
verification](https://docs.ansible.com/projects/ansible/latest/collections_guide/collections_installing.html#installing-collections-with-signature-verification).

Keep supported dependency ranges in collection metadata and a resolved version /
checksum inventory for CI, including transitive collections and Python libraries.
Check the built `MANIFEST.json`, runtime metadata and customer documentation agree.
Exercise claimed minimum and current allowed resolutions in the supported AAP EE;
schedule fresh-resolution compatibility checks, recording the new resolved inventory
without silently changing a qualified candidate's inputs. AAP-93724's dependency
break and AAP-94061's packaged/README mismatch motivate these checks.
Hermeto's native Galaxy support remains unimplemented (STONEBLD-3730). Do not
mistake `requirements.yml` for a complete lockfile or carrier RPM SBOMs for the
collection's dependency inventory. Reuse RHTAS's prior-release-to-candidate
Molecule sequence with explicit versions and pinned tooling; see `prior-art.md`.

Declare controller-side Python/system dependencies in packaged files that `ansible-builder` can
discover; keep development dependencies separate. Collection `meta/execution-environment.yml`
references paths relative to the collection root. Do not mandate root `requirements.txt` or
`bindep.txt`: the [native collection metadata contract](https://docs.ansible.com/projects/builder/en/latest/collection_metadata/)
also supports declared files under `meta/`.

`check-ansible-install` already runs `ansible-builder introspect` on the installed
collection; a missing declared dependency file fails it, and declared files may live under
`meta/` ([Builder source](https://github.com/ansible/ansible-builder/blob/ea0df628f9d36b34d64b0d93f3491ecd17ef4426/src/ansible_builder/_target_scripts/introspect.py)).

Run introspection against the installed artifact and require its expected dependency inventory.
Successful discovery alone does not prove undeclared requirements or EE compatibility. Exercise
the selected roles in the supported AAP EE, including localhost filters, SDKs/CLI tools and
writable paths used there. Use an approved existing EE or a pinned test EE; a workstation install
alone cannot establish that contract.

An EVPN-owned Execution Environment is optional unless Product approves it as a
shipped artifact. If shipped, pin its base and builder images, generate its context
with a pinned `ansible-builder`, and validate the generated Containerfile with
the target cluster's current build pipeline. Do not assume a generated stage
name, a raw-tarball OCI workaround, an EC exception, or a particular catalog task
without a reviewed target-cluster precedent.

## Konflux implementation checks

Configure and test merge protection separately from release gates. Exercise a
change to each declared build input, including lockfiles/tool config, to prove CEL
path filters trigger the intended pipelines. A filter listing only source directories
misses declared inputs such as build-argument files and prefetched modules, and a
merged commit that matches no path produces no build for that revision, so a
Snapshot can lack the newest commit's component.

Apply the same test to every other change filter. Prow's `run_if_changed` and
`skip_if_only_changed` match a regular expression against each changed path ([Prow
jobs](https://docs.prow.k8s.io/docs/jobs/#triggering-jobs-based-on-changes)): the first runs a job
if any path matches, the second skips it only if all paths match. Prefer a short
`skip_if_only_changed` list of documentation-only paths, so a new top-level directory runs checks
by default, over a `run_if_changed` list that must name every input. The first source gate
remains `always_run`. Add a later lane's filter only when its runtime cost justifies it; use the
platform's native filter configuration and seeded changes to declared inputs, configuration,
a new top-level path and excluded docs to record which contexts run. That is filter evidence,
not a separate repository path-classification program.

### Tide and Konflux contexts

In the `openshift` org, Prow's tide merges. Its per-repository context options in
[`core-services/prow/02_config/_config.yaml`](https://github.com/openshift/release/blob/4069337512/core-services/prow/02_config/_config.yaml)
treat present non-Prow contexts, such as Konflux checks, as required unless the
repository sets `skip-unknown-contexts` or an optional `Red Hat Konflux.*` regex,
as some do. Tide's effective required-context set combines explicit `required-contexts`,
registered required Prow presubmits and branch-protection contexts when their import is enabled
([policy assembly](https://github.com/kubernetes-sigs/prow/blob/f21dfc59dd24d5f364a427f5d1a9d13ce4d3e598/pkg/config/tide.go),
[presubmit requirements](https://github.com/kubernetes-sigs/prow/blob/f21dfc59dd24d5f364a427f5d1a9d13ce4d3e598/pkg/config/branch_protection.go)).
A required, reporting, unconditional Prow presubmit for the target branch blocks even while its
context is absent; it needs no duplicate entry in `required-contexts`. An unregistered Konflux
context must enter that effective required set to block while absent. The upstream test case
`no policy - use prow jobs` records this automatic Prow requirement without explicit context
options ([test definition](https://github.com/kubernetes-sigs/prow/blob/f21dfc59dd24d5f364a427f5d1a9d13ce4d3e598/pkg/config/tide_test.go)).
These are inspected upstream merged code and test definitions, not a run of those tests or
proof of EVPN's deployed Tide version.

BGP Cloud Connector sets neither `skip-unknown-contexts` nor the optional regex,
and its branch protection requires two Prow contexts. An unlisted Konflux check
cannot hold a merge while absent; once reported, its pending/failing status is
required under the inspected Tide policy. On its PRs the Konflux
GitHub App for the cluster reports builds as `Konflux kflux-prd-rh02 /
<component>-on-pull-request` and ITSs as `Red Hat Konflux / <scenario> /
<application>`, with optional ITSs `neutral`. List EVPN's blocking Konflux contexts
in `required-contexts` when onboarding the repository. Review that list when ITS,
Component or Prow context names change: a missing listed context blocks merge, while
a Konflux context omitted from the effective required set does not block while absent.
Verify the current SHA's expected build/ITS set, including the interval before Konflux checks appear, after
a new commit and after a failed-then-successful retry.

The repository's onboarding [PR #86165](https://github.com/openshift/release/pull/86165) merged
2026-10-06 at `fa0885de` ([current state](ci-source.md#where-things-stand)), after the first skeleton of September 29. It originally built `Dockerfile.root`,
defined `verify` and generated one `always_run` presubmit. The October 13
[runner switch](ci-source.md#where-things-stand) uses PR-built `Dockerfile.ci`
and adds required `ci/prow/images` alongside verify. Its
`main` tide query requires `approved`, `lgtm`, `jira/valid-reference` and `verified`, and sets no
`required-contexts`, `skip-unknown-contexts` or `trusted_apps`. The generated `verify` presubmit
matches main, always runs, reports `ci/prow/verify` and sets neither `optional` nor `skip_report`;
the native policy therefore requires it without another context-list change. Qualify that
behavior with the repository PR runs ([current state](ci-source.md#where-things-stand)).
BGP Cloud Connector's query requires
only `approved` and `lgtm`. A Konflux nudge PR carries no Jira key in its title, so it would need a
human to add the reference and `/verified`; decide whether to keep that query or to add the nudge
author's exception described below.

### Who may run pipelines

Include a fork/external-contributor change, its approval and a subsequent commit
in that canary. Verify both authorization to execute and required status reporting
on the current SHA. A forge label or an earlier `/ok-to-test` is insufficient.
PaC runs a PR without approval when its author is an organization member, a
collaborator, has push access to branches in the repository or is listed in the default
branch's `OWNERS`. Bot identity alone does not authorize execution; unauthorized bots
may receive no Pending status ([authorization rules](https://pipelinesascode.com/docs/guides/running-pipelines/),
[checked GitHub ACL](https://github.com/openshift-pipelines/pipelines-as-code/blob/78992f09a5fe82f0d214db8333c061b08ae6eb86/pkg/provider/github/acl.go)).
In the `openshift` org that covers thousands of people, and one `/ok-to-test`
comment is read by both Prow and PaC. Konflux PR pipelines therefore must never
receive AWS or lab credentials. SHA-qualified `/ok-to-test` is a GitHub-App-only
Technology Preview
([evidence](source-evidence.md#7-test-backends-require-adaptation-and-lifecycle-ownership)).

### Nudge PR merging

Konflux bot PRs, digest nudges included, are not org members. Prow holds their tests
for a human `/ok-to-test` unless the repository's trigger configuration lists the
cluster's app in `trusted_apps`, and tide waits for `lgtm` and `approved`. BGP Cloud
Connector configures neither: its last three nudge PRs (#116, #128, #142) waited 2–8
days for a maintainer. On the same cluster, `openshift-hyperfleet/hyperfleet-operator`
trusts `red-hat-konflux-kflux-prd-rh02` and adds a tide query that merges that
author's `konflux-nudge` PRs once required tests pass; five of its last six merged
within 25 minutes (`openshift/release` `74128203`). Every EVPN bootc change needs one
nudge PR before a complete candidate exists. Choose that configuration or owned
human review with a response target, and enable automatic merging only after the
merge-policy checks above are proven.

### Credential boundary

Before providing AWS/lab identity, approve the executed source and pipeline
revisions and enforce that approval outside contributor-controlled code. Canary
that an unapproved change cannot mount a protected Secret or select a credentialed
service account. Kubernetes workload-creation permission can grant both; an IAM
role bound to a service account alone does not approve the Git revision. Use a
separate runner/namespace or proven admission controls where that boundary is
needed. [Kubernetes permission
model](https://kubernetes.io/docs/concepts/security/rbac-good-practices/#workload-creation).

OpenShift CI has a precedent for protecting the harness. `app-sre/infra`'s `validate` and
`terraform-plan` tests mount credentials on pull-request runs. `validate` restores the Makefile
and scripts from the trusted base (`git checkout "${PULL_BASE_SHA}" -- Makefile hack/`);
`terraform-plan` runs its planner from `git show "${PULL_BASE_SHA}:…" | python3 -I -` (`-I` keeps
a pull-request-added `json.py` from shadowing the standard library), and that planner refuses
authors who are not organization members or collaborators
([configuration](https://github.com/openshift/release/blob/988805e8e926/ci-operator/config/app-sre/infra/app-sre-infra-main.yaml)).
That protects the tooling that drives privileged calls, not the code under test; code that must
run with the credential still needs the approval above.

### Parallel release lines

For parallel release lines in the Application model, use separate Component sets
and Applications. Before adopting shared Components with versions/groups, prove
version-aware nudges between two maintained lines; STONEINTG-1835 tracks the gap.
Align source branches, PaC CEL/labels, nudge targets,
image/pull-secret references, approved test revisions, RP/RPA mappings and customer
update channels. Registry repositories may be shared; resource identity and
publication authority must remain explicit. Check the prepared source's product
version against the intended release line; matching version strings within the
source do not establish that mapping (AIPCC-31752). If configuration is generated,
change its authoritative inputs and review the regenerated diff, including task
revisions and upgrade-test baselines. Rehearse build → nudge → complete candidate →
stage publication, checking for unintended cross-line updates. Reuse Portal's
branch definitions and [version
overlays](https://konflux-ci.dev/docs/building/configuration-as-code/#defining-multiple-versions-or-variants-of-an-application),
or a [ProjectDevelopmentStreamTemplate](https://konflux-ci.dev/docs/patterns/managing-multiple-versions/)
as OpenPERouter's KRD tenant (`telco-5g-tenant/openperouter-operator`) does.

Validate RP/RPA application membership and the intended policy/destination in
configuration CI and release preflight. Canary a label selecting the wrong RPA
within the same origin namespace: current forward resolution bypasses the RPA's
application allowlist (RELEASE-2372), even though it rejects a different origin.

Set an accountable ReleasePlan author when using standing attribution. KRD's
local generation helper can fill a missing author, but its CI only checks presence;
review the source/generated result. Attribution is distinct from candidate approval.

### Build-to-Snapshot handoff

Canary the build-to-Snapshot handoff with concurrent builds, delayed signing and
Snapshot quota/admission failure. Observe it after the producing build finishes;
Chains/Snapshot creation depends on build completion. Record the build's
namespace/name/UID, source revision and output digest; follow its `appstudio.openshift.io/snapshot`
or `snapshots` annotation in the checked model and verify the referenced content.
Use that same run for completion and signature checks; re-listing the Component's
runs can silently validate an older successful build. Konflux's load-test probe failed
on equal timestamps and a deleted pre-start run until it selected by commit SHA
(KONFLUX-16041); cover those cases if the selected handoff uses similar lookup logic.
Monitor `test.appstudio.openshift.io/create-snapshot-status` before runs are pruned.
A successful Tekton build or timestamp-based lookup is insufficient. After a
missing-Snapshot failure, restore capacity and explicitly reconstruct a candidate
from retained verified outputs or rebuild; do not assume pruning permits automatic
recovery. Run the same required qualification on the recovered candidate.
[Controller
handoff](https://github.com/konflux-ci/integration-service/blob/11cc455b/internal/controller/buildpipeline/buildpipeline_adapter.go).

### Generated PipelineRuns and resolvers

Tekton performs [substitution without escaping](https://tekton.dev/docs/pipelines/variables/).
In custom adapters, pass external values through environment variables or arguments, quote
their use, validate constrained inputs and avoid `eval` or inserting them into script source.
The release catalog is moving its own managed-task logic from inline `script` blocks into
versioned, unit-tested scripts (RELEASE-2455). Adapter tests can feed quotes, newlines and
shell metacharacters.

A Component's `.tekton/` PipelineRuns start as generated files. Setting
`build.appstudio.openshift.io/request: configure-pac` on the Component, as the Portal
examples do, makes Konflux open a pull request that adds default
`<component>-pull-request.yaml` and `<component>-push.yaml` PipelineRuns;
`configure-pac-no-mr` skips that pull request and the team writes the files by hand
([creating a component](https://konflux-ci.dev/docs/building/creating-github/)). Treat the
generated pull request as the starting point for this plan's customizations (hermetic,
privileged-nested bootc builds, RPM prefetch, path filters, nudge files and the BIB wiring
for disk Components). Its PipelineRuns run only for submitters allowed to run them or after
an authorized `/ok-to-test` (see [who may run pipelines](#who-may-run-pipelines)).

Before changing generated PipelineRuns, inspect the selected cluster's generated
PR and push files and the exact task bundle. Check proposed fields against both
KRD's schema and the deployed CRD; support in one does not establish acceptance
by the other (KONFLUX-15811, RELEASE-2827). If an EE needs a `run-script-oci-ta`
style generation step, prove the trusted-artifact handoff, prefetch handoff, and
base-image attribution in a throwaway component first. Pin resolved bundles by
the current approved mechanism; the `build-definitions` external-task YAML files
are bundle-reference stubs, not Tekton Task definitions.

Verify updater discovery for each reference form: BIB wrappers, Git-resolved
tests, nested bundles and images invoked inside scripts. MintMaker's default
Tekton scope is `.tekton/`; qualify native managers and supported file patterns first.
A [custom manager](https://docs.renovatebot.com/modules/manager/regex/) is only for a
reproduced extraction gap worth its maintenance, with budgeted configuration and seeded
proof. Approved manual update ownership is an alternative, not a failure to implement a
new regex/parser. Keep one updater per pin. MintMaker's enabled `ansible-galaxy` and
`github-actions` managers can also
propose collection-dependency and SHA-pinned workflow updates, including
`release_ah.yaml`. Show an update proposal and rebuild path for these inputs, or assign
manual update ownership and cadence. Include generated locks: where CI installs from a lock
compiled from a human-edited input (for example `pip-compile` output), show that the update
proposal regenerates the lock, because a bot change to the input alone leaves CI on the old
locked versions and the proposal inert. RHAI's AIPCC-31900/30134 show how configured automation
can still miss references. [Manager scope](https://konflux-ci.dev/docs/mintmaker/default-config/),
[supported references](https://docs.renovatebot.com/modules/manager/tekton/).
For a selected updater, verify that intended changes produce an update PR and rebuild.
Investigate repeat-update or branch-lifecycle behavior when the chosen setup needs it;
monitor actual runs, not just webhook delivery (KFLUXSPRT-7906/9022).

Canary test-code resolution with a harmless PR-only Pipeline/Task marker and
verify the resolved SHA, including nested references. At `11cc455b` the integration
controller rewrote a git resolver to the PR's revision only when `url` matched the
source repository and `revision` matched the PR target branch; `org`/`repo` API mode
and explicitly pinned revisions got no rewrite. On `main` since September 27
(KONFLUX-15531) it also rewrites `serverURL`/`org`/`repo` resolvers that match the
component's repository and points fork PRs at the fork; pinned revisions still get none,
and the deployed version is unchecked. Keep cloud
credentials out of unapproved PR execution. Release qualification uses approved
immutable test revisions. [Tekton contract](https://tekton.dev/docs/pipelines/git-resolver/),
[controller
implementation](https://github.com/konflux-ci/integration-service/blob/11cc455b/tekton/integration_pipeline.go).

Exercise release-preflight evidence retrieval after live test PipelineRuns are
pruned, using the release identity and the target cluster's KubeArchive or export path.
Retain run UIDs, candidate digests and resolved test revisions. When retries are supported,
reconcile the accepted attempt with Snapshot status and retain attempt identities and
required evidence; prove cancellation cannot clean up another active run.
A visible historical UI entry does not prove that a release gate can read it.
Match retrieved Snapshot identity and component digests to the release record.
With their owners, prove retention/retrieval of the selected publishers' required
evidence and diagnostics; reuse retained Release/backend records where sufficient.
For a selected report-export path, canary missing reports and failed copies; a green archive job can hide both
([report-copy example](prior-art.md#security-inventory-handoff)). Common-cluster
internal-service archival is still tracked by KONFLUX-15431; tenant archival does
not establish coverage there.
For tenant release preflight and final readback, translate rejected evidence into
a failed Task/PipelineRun, not only `TEST_OUTPUT`. Prove a failed preflight prevents
publication and a failed readback fails the Release while retaining the ledger.
Before delegating EVPN's evidence gate to Conforma, canary the deployed policy/data:
required test identities, effective dates, task trust, absent/wrong-subject evidence,
retry selection and index/child coverage. Preserve complete-candidate and approved
test-revision binding; a successful scanner-attestation PoC alone is insufficient.

## Source CI completion

Make-status repair, YAML, Markdown and the collection checks merged with clean current-SHA Prow
results. A failing run that Tide refuses to merge is still unrecorded
([current state](ci-source.md#where-things-stand)).

[Source CI](ci-source.md#queue) owns the next linters. Scanner/link migrations remain deferred. [Required source checks](#required-source-checks) and
[later lanes](#later-sequence) retain the role, publication and release obligations; current
source CI does not complete those Jira criteria.
