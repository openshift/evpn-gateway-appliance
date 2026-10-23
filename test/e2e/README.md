# Emulated EVPN end-to-end lane (CORENET-7508)

This lane deploys the on-prem appliance, relay and an emulated workload as a three-AS BGP
EVPN fabric and validates control-plane and data-plane behavior, using the collection's
own `playbooks/deploy.yml` as the thing under test. It is the simulated-topology gate
(L7) described in `plans/context/evpn-aws/pipeline-spec.md` and `ci-bootstrap-spec.md`.

Two entry points, by how they are meant to be run:

- `test/e2e/run.sh` — run **locally, on a rootful host**, with the images already present.
- `test/e2e/run_remote.sh` — the **CI** path: from an unprivileged local checkout it builds
  and runs the lane on a target over SSH (and, with no target, locally for convenience).

Both are runner-agnostic — the same scripts work under a Prow test step or a GitHub Actions
VM; the runner only provides env and collects artifacts.

## Layout

```text
test/e2e/
  run.sh              run the lane locally (rootful): podman run the toolchain image
  run_remote.sh       run against a remote target (or locally, no target): export, ship, build, run
  entrypoint.sh       in-container steps: clab deploy -> deploy.yml + health check
  topology/
    evpn.clab.yml     the emulated fabric
  inventory/          e2e Ansible inventory + group_vars
  ee/                 execution-environment definition + build.sh (make ee-image)
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
- `EGA_TOPOLOGY` — topology file under `topology/` (default `evpn.clab.yml`).
- `EGA_STAGE` — `full` (deploy + validate + tear down), `deploy` (same but leave the lab up
  for inspection), or `destroy` (tear down a lab left up by `deploy`). Default `full`.
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

Leave the lab up for inspection with `EGA_STAGE=deploy`, then tear it down with
`EGA_STAGE=destroy`:

```bash
sudo EGA_STAGE=destroy test/e2e/run.sh
```

## run_remote.sh — remote target (or local, no target)

### Execution model

`run_remote.sh` builds on `run.sh`: it just gets everything in place on the target and then
runs `run.sh` there. From an unprivileged local checkout it exports the base images to
tarballs, ships them over SSH, and on the target loads a local registry, builds the EE and
appliance images, and runs `run.sh`. The local side needs no root — only the target does the
rootful work. With no target (`SSH_REMOTE` unset) it does the same export/build/run on this
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
deltas (`scenarios/<name>.yml`, applied as extra-vars), plus a topology variant via
`EGA_TOPOLOGY` when the change is topological. The same scenario file drives both the deploy
vars and the test expectations. A full deploy costs minutes, so tests are grouped by
scenario: deploy once per scenario, run its tests, tear down (fresh topology each time for
EVPN-state isolation).

**Orchestration — OPEN.** The single-entrypoint contract holds either way: CI calls `run.sh`
once; the runner only sets env + collects artifacts; scenario iteration lives in the repo,
never in runner config. Two candidate shapes, undecided:

- *Harness-driven:* `entrypoint.sh` loops scenarios (clab deploy -> `deploy.yml` ->
  `pytest -m <scenario>` -> destroy), one JUnit per scenario. Simple, language-agnostic,
  fabric buildable with no pytest in the loop; serial.
- *pytest-driven:* a parametrized scenario fixture owns the fabric lifecycle (shelling small
  reusable deploy/destroy scripts). Native per-scenario reporting, great local DX, and
  `pytest-xdist` recovers parallelism repo-side; but the fabric lifecycle becomes a pytest
  concern and the fixtures carry more complexity.

`EGA_SCENARIO` (optional) narrows a run to one scenario for local iteration under either
shape. Build the seam (scenario overlay + `EGA_SCENARIO` + the first `conftest.py`) with the
first real assertion; add scenario files lazily as CORENET-7514 / the isolation decision land.

## Deferred (tracked, not covered yet)

- Internet-mode MTU enforcement and MSS clamping: the roles implement no nftables/MSS
  tasks today; the assertions land under CORENET-7514, which implements the clamp. This
  lane provides the internet-mode (WireGuard) topology hook.
- VNI isolation: the appliance currently routes between tenant subnets; the isolation
  test will be authored as `xfail` pending an isolation-model decision.
- `frr_exporter` + metrics: the image ships no `frr-exporter` Quadlet (would hit the podman
  fallback), so it's off here and its metrics validation is deferred to CORENET-7504.
  `node_exporter` is enabled (it has a matching Quadlet).
