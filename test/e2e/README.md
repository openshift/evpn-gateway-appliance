# Emulated EVPN end-to-end lane (CORENET-7508)

This lane deploys the on-prem appliance, relay and an emulated workload as a three-AS BGP
EVPN fabric and validates control-plane and data-plane behavior, using the collection's
own `playbooks/deploy.yml` as the thing under test. It is the simulated-topology gate
(L7) described in `plans/context/evpn-aws/pipeline-spec.md` and `ci-bootstrap-spec.md`.

This directory is the **CI lane harness** (despite the `e2e` name): it also hosts the molecule
lane, which reuses the same rootful-target machinery. Both lanes share one core, `run_remote.sh`,
and differ only in the in-container script it runs (`EGA_ENTRYPOINT`).

Entry points, by how they are meant to be run:

- `test/e2e/run.sh` — run **locally, on a rootful host**, with the images already present.
- `test/e2e/run_remote.sh` — the **shared CI core**: from an unprivileged local checkout it builds
  and runs a lane on a target over SSH (and, with no target, locally for convenience). Called
  directly it runs the e2e lane (backward compatible); the named wrappers below just set the lane.
- `test/e2e/run_e2e.sh` / `test/e2e/run_molecule.sh` — thin wrappers over `run_remote.sh` selecting
  the e2e or molecule lane. A Prow status then reads `e2e` / `molecule`. The molecule wrapper also
  skips the EE build (molecule drives the role with the CI image's own ansible, not the shipped EE).

All are runner-agnostic — the same scripts work under a Prow test step or a GitHub Actions
VM; the runner only provides env and collects artifacts.

The e2e entrypoint discovers all `scenarios/*.env` definitions by default, in filename
order. Set `EGA_SCENARIOS` to comma-separated names to select scenarios and their order
(a single name selects just that scenario):

```bash
sudo EGA_SCENARIOS=emulated test/e2e/run.sh
```

Each scenario defines its topology, inventory and ordered playbook sequence. Scenarios
run sequentially with separate work/artifact subdirectories and containerlab names
(`ega-<scenario>`). A failed scenario is cleaned up in `full` mode; later scenarios still
run, and the lane fails if any scenario fails. Both runners forward `EGA_SCENARIOS` and
`EGA_STAGE`; scenario iteration and topology selection stay inside the entrypoint.
`deploy` and `destroy` require exactly one explicitly selected scenario; discovery and
multi-scenario runs must use the default `full` lifecycle.

## CORENET-7502 coverage boundary

The `multihoming` scenario runs the collection's normal deploy playbook for
both appliances, the relay, and the workload VTEP, then runs the multihoming
assertions. Run both scenarios in the shared lane with:

```bash
EGA_SCENARIOS=emulated,multihoming test/e2e/run_remote.sh
```

For image exports on a host with a small `/tmp`, set `TMPDIR=/var/tmp` before
invoking the remote runner.

The CI topology emulates the upstream DVS/edge segment with a VLAN-aware Linux bridge
and a VLAN trunk. The edge side terminates one 802.3ad bond with one member toward each
appliance; each appliance contributes one link through its own single-member 802.3ad
bond. This follows the FRR EVPN-MH test topology and models the shared edge actor without
pretending that a plain Linux bridge implements vendor-specific MLAG.
Both appliances run FRR EVPN-MH with the same numeric discriminator and system MAC,
which produces the shared Type-3 ESI. The multihoming path uses one fixed-VNI VXLAN
device per stretch, attached to the shared bridge as an access port;
this avoids requiring the SVD-only NetworkManager/nmstate attributes. VLANs 100, 200,
and 300 are trunked across it.

The lane checks the following behavior.

- both edge links in one LACP aggregator and a shared Ethernet Segment with a common
  anycast gateway IP/MAC;
- live BFD between each appliance and the relay, and receipt of peer Type-1 and Type-4
  routes over eBGP through that relay;
- DF election with distinct preferences, DF takeover after an access or underlay link
  is disabled, and FRR requesting access protodown after uplink loss;
- the surviving appliance's Type-2 advertisement for the actual edge-host MAC and
  zero-loss VXLAN traffic after convergence;
- exactly one copy of a marked broadcast from the cloud on each stretched VLAN;
- FRR container crash and restart, including recovery of the Ethernet Segment and
  VXLAN reachability.

The scenario emulates link loss by administratively disabling one veth. The VM's
access links reject `protodown`, so the appliance can request it and still remain
in the edge LACP bundle. In that state, the edge can send ARP and ICMP replies
to the isolated appliance after the surviving VTEP takes over. Disabling that
appliance's access link in the VM restored reachability. Qualification needs to
verify that FRR withdraws and restores the access link on the appliance NIC,
along with physical power loss, cabling, NSX/DVS behavior, and vendor-specific
RARP handling.

The pinned OpenShift 4.22 FRR 10.4.3 payload and upstream FRR 10.5.3 both
delivered duplicate broadcasts in the VM. The upstream split-horizon draft
delivered one broadcast copy per VLAN with either appliance as DF. A separate
VM probe also received one marked Ethernet multicast frame per VLAN. Detaching
the egress filter brought duplicates back in both probes. Passing the broadcast
check with a supported appliance payload depends on shipping and qualifying
that filter. The draft leaves unknown unicast outside its scope.
[FRR split-horizon draft](https://github.com/FRRouting/frr/pull/23741),
[tested revision](https://github.com/FRRouting/frr/commit/e8a7c9063b79a45c13c63cdbe8d57043e3d72684)

The scenario uses distinct appliance ASNs and a single relay, following the PR review
direction. The earlier appliance plan proposed a shared ASN with direct iBGP or
`allowas-in`. With unique ASNs, the relay preserves the original VTEP next hops and
neither appliance needs a direct peer session or relaxed AS-path loop checks.

## Layout

```text
test/
  ansible/                test-only collection (network.evpn_gateway_test): on-prem sim role + playbooks; installed into the EE
  e2e/
    run.sh                run a lane locally (rootful): podman run the toolchain image, run ${EGA_ENTRYPOINT}
    run_remote.sh         shared core: against a remote target (or locally): export, ship, build, run
    run_e2e.sh            wrapper: select the e2e lane (entrypoint_e2e.sh)
    run_molecule.sh       wrapper: select the molecule lane (entrypoint_molecule.sh; skips the EE build)
    entrypoint_e2e.sh     iterate scenarios: clab deploy -> scenario playbooks -> teardown
    entrypoint_molecule.sh  molecule in-container steps: molecule test against the rootful socket
    topology/
      emulated.clab.yml   the emulated fabric
    inventory/
      emulated/           e2e Ansible inventory + group_vars for the emulated fabric
    scenarios/            *.env definitions: topology, inventory, ordered playbooks
    ee/                   execution-environment definition + build.sh (make ee-image)

ansible/
  extensions/molecule/    molecule scenarios (collection-mode; run by the molecule lane)
    config.yml            shared driver/provisioner/test_sequence; scenarios inherit it
    evpn_onprem_appliance/           per-role dir
      nm_networking/                 per-task group -> scenario names like evpn_onprem_appliance/nm_networking/default
        resources/        shared create/destroy/prepare/converge/present_environment + deploy_vars/modify_vars
        default/          converge + ownership-reconcile + reboot
        modify/           re-converge a changed config (add/remove stretch, SVI edit)
        teardown/         converge then teardown, assert empty
```

## run.sh — local, rootful

### Execution model

Everything runs on a host with a real kernel (veth, netns, VXLAN, netfilter), under rootful
podman. The CI image (`Dockerfile.ci`) carries the toolchain — containerlab, Ansible,
pytest, testinfra — so the same image runs the static checks and this lane, the host
installs nothing, and tool versions are pinned in one place. containerlab runs from that
image against the host's podman socket, so the node containers are siblings on the host
runtime and get the host kernel.

`deploy.yml` itself runs from an **execution environment** (`test/e2e/ee/`, built by
`make ee-image`) — the same artifact AAP runs, built from the collection's own EE metadata
so its runtime deps (`wireguard-tools`, `netaddr`, `boto3`) are derived, not hand-pinned.
The toolchain launches it as a sibling container on the host runtime; the toolchain itself
only drives containerlab and (later) the assertions.

`run.sh` expects the CI, EE and appliance node images to be present already; it sets no env
of its own and builds nothing. `run_remote.sh` is what builds and stages those images (below).

### Contract

- `EGA_E2E_IMAGE` — the CI image (`Dockerfile.ci`), which also carries the e2e tools
  (default `localhost/evpn-gateway-appliance-ci:local`, `make`'s tag).
- `EGA_NODE_IMAGE` — node image containerlab instantiates: the appliance `nested-ci` image
  (vfs storage baked in; `make nested-ci-appliance-image`). Default
  `localhost/evpn-appliance-rhel10:nested-ci`; CI overrides with a digest.
- `EGA_EE_IMAGE` — execution environment that runs `deploy.yml` (`make ee-image`; default
  `localhost/evpn-gateway-appliance-ee:local`). Must be in the same (rootful) store the lane uses.
- `EGA_WORK_DIR` — host dir for the lab working files (the clab lab dir, the ephemeral SSH
  keypair, the staged inventory), mounted at the same path on host and in-container so the
  sibling node/EE containers can bind from it (default `/tmp/ega/work`).
- `EGA_ARTIFACT_DIR` — host dir reserved for produced artifacts, out of the checkout (default
  `/tmp/ega/artifact`; Prow sets it to `$ARTIFACTS`). Mounted but **empty for now** — nothing is
  written here until diagnostics/JUnit capture is added (see Testing plan).
- `EGA_SCENARIOS` — comma-separated scenario names, e.g. `emulated,other`; defaults to all
  `scenarios/*.env` definitions. A single name is supported through the same interface.
- `EGA_STAGE` — `full` (deploy + validate + tear down), `deploy` (same but leave the lab up
  for inspection), or `destroy` (tear down a lab left up by `deploy`). Default `full`.
  `deploy` and `destroy` require `EGA_SCENARIOS` to name exactly one scenario explicitly,
  even if discovery would find only one definition. Other combinations fail before any lab changes.
- `EGA_E2E_SRC` — bind a repo checkout over the image's baked `/src` for live dev (default
  unset → use the baked `/src`; the image is the artifact under test in CI).
- `EGA_RUNTIME_SOCK` — host podman socket (default `/run/podman/podman.sock`).

`EGA_E2E_IMAGE`, `EGA_NODE_IMAGE` and `EGA_EE_IMAGE` default to the tags `make` stamps on
locally-built images (`make ci-image` / `ee-image` / `nested-ci-appliance-image`), so once
you've built them locally you can run `run.sh` without setting any of those three. CI, where the
images are registry pullspecs/digests, sets them explicitly.

### Usage

The clab node image is the appliance `nested-ci` image (vfs baked in); build it with
`make nested-ci-appliance-image`, which builds the `:ci` parent (CentOS CI base + FRR/node-exporter,
pulled with your registry pull secret) and layers the vfs drop-in. Everything is rootful, so
build into the rootful store and run under `sudo`:

```bash
sudo make ci-image          # localhost/evpn-gateway-appliance-ci:local (Dockerfile.ci)
sudo make ee-image          # localhost/evpn-gateway-appliance-ee:local (the EE that runs deploy.yml)
sudo make nested-ci-appliance-image CONTAINER_AUTH_FILE="$HOME/.docker/config.json"   # the clab node image
sudo test/e2e/run.sh
```

The images above use the default tags, so no image env is needed; override any of
`EGA_E2E_IMAGE` / `EGA_NODE_IMAGE` / `EGA_EE_IMAGE` to point elsewhere.

The toolchain image bakes the repo (`COPY . /src` in `Dockerfile.ci`), so by default the lane
runs exactly what the image carries. For a faster dev loop, set `EGA_E2E_SRC="$PWD"` to bind
your live checkout over the baked `/src` and pick up harness edits (`test/e2e/` — topology,
inventory, `entrypoint.sh`, tests) without rebuilding the toolchain image (`sudo
EGA_E2E_SRC="$PWD" test/e2e/run.sh`). It does **not** affect the collection: `deploy.yml` runs
from `EGA_EE_IMAGE`, so collection edits need `make ee-image`.

Explicitly select one scenario to leave its lab up for inspection with `EGA_STAGE=deploy`,
then tear down that same scenario with `EGA_STAGE=destroy`:

```bash
sudo EGA_SCENARIOS=emulated EGA_STAGE=deploy test/e2e/run.sh
sudo EGA_SCENARIOS=emulated EGA_STAGE=destroy test/e2e/run.sh
```

## run_remote.sh — remote target (or local, no target)

### Execution model

`run_remote.sh` builds on `run.sh`: it just gets everything in place on the target and then
runs `run.sh` there. From an unprivileged local checkout it exports the base images to
tarballs, ships them over SSH, and on the target loads a local registry, builds the appliance
images (and, for the e2e lane only, the EE), and runs `run.sh`. The local side needs no root —
only the target does the rootful work. With no target (`SSH_REMOTE` unset) it does the same export/build/run on this
host, which is then the rootful one.

### Contract

- `SSH_REMOTE` — `user@host` of the target; unset runs everything on this host.
- `SSH_OPTS` — ssh/scp options, word-split (remote only), e.g.
  `-i /path/key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`.
- `FRR_IMAGE`, `NODE_EXPORTER_IMAGE` — **required**: the appliance's embedded FRR / node-exporter
  payload (CI injects the in-cluster `metallb-frr` / `prometheus-node-exporter` pullspecs; pass
  them explicitly locally).
- `EE_BASE_IMAGE`, `APPLIANCE_BASE_IMAGE` — exported OS bases (default public CentOS Stream 10
  images; CI injects in-cluster pullspecs).
- `CI_IMAGE` — the CI image to ship (default
  `containers-storage:localhost/evpn-gateway-appliance-ci:local`, the local `make ci-image`
  build; CI passes a digest). A bare ref is a `docker://` pullspec; an explicit skopeo transport
  is honored.
- `REGISTRY_AUTH_FILE` — pull secret for the export, used only if present (default the local
  docker config).
- `ARTIFACTS` — local dir the lane's artifacts are collected into (default `/tmp/ega/artifact`;
  Prow sets it). For a remote target they are copied back off the target into it (even on failure);
  `run.sh` makes the artifact dir world-readable on exit so the SSH user can collect it without
  `sudo`. Empty for now — see `EGA_ARTIFACT_DIR` under `run.sh` and the Testing plan.

### Usage

The one image it needs locally is the CI image (which carries the export tooling and bakes the
repo), so build it rootless and point the script at the target:

```bash
make ci-image               # localhost/evpn-gateway-appliance-ci:local, rootless
SSH_REMOTE=user@vm \
SSH_OPTS="-i /path/key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" \
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> \
REGISTRY_AUTH_FILE="$HOME/.docker/config.json" \
test/e2e/run_remote.sh
```

The remote must be provisioned with `podman`, `skopeo` and `make`, `podman.socket` enabled, and
passwordless `sudo`; the script installs nothing on it.

For convenience and testing it can also run with **no target** (`SSH_REMOTE` unset), doing the
same export/build/run entirely on this host. That path is rootful, so build into the rootful
store and run under `sudo`:

```bash
sudo make ci-image
sudo env FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> \
    REGISTRY_AUTH_FILE="$HOME/.docker/config.json" \
    test/e2e/run_remote.sh
```

## Molecule lane

The Molecule lane tests role behavior in isolation. The on-prem networking scenarios cover
idempotence, ownership reconciliation, teardown, and persistence across reboot. The FRR scenario
covers first startup, live configuration changes, unchanged redeploys, drift correction,
invalid configuration, and reload retries. `run_molecule.sh` reuses the `run_remote.sh` runner
and selects `entrypoint_molecule.sh`.

Because the role needs a real kernel (vxlan/bridge netlink) and a privileged systemd container, the
lane cannot create its instance from the nested, rootless Prow container — same constraint as e2e.
The Molecule Podman driver runs the appliance image as a sibling container over the rootful
Podman socket mounted in the CI image. The networking scenarios check devices, SVI IPs,
self-VLANs, `neigh_suppress`, ownership, and teardown. The FRR scenario checks running and
saved configuration and verifies that configuration changes keep the same service invocation
and BGP process.

```bash
# Same invocation shape as e2e; the wrapper only selects the lane.
SSH_REMOTE=user@vm SSH_OPTS="..." \
FRR_IMAGE=<ocp frr> NODE_EXPORTER_IMAGE=<ocp node-exporter> \
test/e2e/run_molecule.sh
```

Scenarios live under `ansible/extensions/molecule/` (see the Layout above). To run a single scenario,
set `EGA_STAGE` to its nested path, for example `EGA_STAGE=evpn_onprem_appliance/nm_networking/default`.

## Status

Deploy + the collection's health check pass end to end: three-AS eBGP, Type-2/3 exchange,
and bidirectional L2 reachability across the fabric. Still to add: explicit pytest
assertions (Type-2/3, BUM, isolation) and the Prow/CI job wiring (cross-repo).

## Testing plan (not yet built)

**What goes where.** The collection's `evpn_health_check` role stays the *product's* own
"is this deploy healthy" self-check (eBGP Established, expected Type-2/3 routes, stretched
L2 pings); it ships and runs in AAP too. `pytest` (`test/e2e/tests/`) is the CI gate for
what shouldn't live in a shipped health check: negative/isolation tests, independent
verification (don't grade a deploy by replaying its own health check), harness-only probes
(tcpdump/scapy, MSS/MTU), and JUnit evidence mapped to the Jira criteria. pytest runs in the
toolchain (not the EE), against the live fabric, via testinfra's podman backend over the
mounted socket. A `conftest.py` reads the same inventory/`group_vars` the deploy used so
tests and deploy can't drift.

**Scenarios.** Some assertions need a different deploy config (internet vs direct underlay,
MSS on/off, isolation model). A scenario = base `group_vars/all.yml` + a thin overlay of
deltas (`scenarios/<name>.yml`, applied as extra-vars), plus a topology variant selected
by its `scenarios/<name>.env` definition. The same scenario file drives both the deploy
vars and the test expectations. A full deploy costs minutes, so tests are grouped by
scenario: deploy once per scenario, run its tests, tear down (fresh topology each time for
EVPN-state isolation).

**Orchestration.** CI calls `run.sh` once; the runner only sets env and collects artifacts.
`entrypoint_e2e.sh` calls `run_scenario` for every selected `scenarios/<name>.env`, with a
fresh deploy and cleanup per scenario in `full` mode. `EGA_SCENARIOS=emulated` narrows a run
for local iteration without a separate single-scenario interface. Add scenario definitions
as new assertions land; pytest fixtures and per-scenario JUnit evidence remain future work.

## Deferred (tracked, not covered yet)

- Internet-mode MTU enforcement and MSS clamping: the roles implement no nftables/MSS
  tasks today; the assertions land under CORENET-7514, which implements the clamp. This
  lane provides the internet-mode (WireGuard) topology hook.
- VNI isolation: the appliance currently routes between tenant subnets; the isolation
  test will be authored as `xfail` pending an isolation-model decision.
- `frr_exporter` + metrics: the image ships no `frr-exporter` Quadlet (would hit the podman
  fallback), so it's off here and its metrics validation is deferred to CORENET-7504.
  `node_exporter` is enabled (it has a matching Quadlet).
