# Source CI: the next pull requests

This proposal covers the static checks that run in the existing Prow `verify` job: what
runs today, how to add a check, and what comes next. Jira criteria and
[recorded decisions](kickoff-decisions.md) govern scope. Product builds, role tests and
release lanes are [later CI](ci-bootstrap-spec.md#later-sequence).

## Where things stand

Rechecked on 2026-10-16 against main `7d7b39c`, after collection
[#7](https://github.com/openshift/evpn-gateway-appliance/pull/7) and Markdown lint
[#15](https://github.com/openshift/evpn-gateway-appliance/pull/15) merged.

| Piece | State |
| --- | --- |
| Gate | Prow runs `make verify OFFLINE=1`; `verify: check`. `check` runs `check-corpus` (`tools/check-all.sh`: planning links and anchors; revision pins only without `OFFLINE`), `check-public` (public-safety scan), `check-yaml`, `check-markdown` and `check-ansible` (collection lint, playbook syntax, build with tarball allowlist, clean install, Builder introspection and role discovery) |
| Runner | The merged [release config](https://github.com/openshift/release/blob/fbf3035dcf9869169a86a3658d74085119487570/ci-operator/config/openshift/evpn-gateway-appliance/openshift-evpn-gateway-appliance-main.yaml) builds `ansible-test-runner` from the PR's `Dockerfile.ci`, overriding its base image, and reports required `ci/prow/images` and `ci/prow/verify` (since [release#86670](https://github.com/openshift/release/pull/86670), 2026-10-13) |
| Tools | `Dockerfile.ci` pins ansible-core, ansible-lint, yamllint, ansible-builder and the four Galaxy dependencies, installs markdownlint-cli2 from `ci/markdownlint/package-lock.json`, and installs Git from the base repositories. Local `make` builds and runs the same image; `USE_IMAGE=0` uses host tools. `Dockerfile.root` is unused (#13 removes it); do not pin tools there |
| Open | Ruff [#18](https://github.com/openshift/evpn-gateway-appliance/pull/18), ShellCheck [#19](https://github.com/openshift/evpn-gateway-appliance/pull/19) and Hadolint [#20](https://github.com/openshift/evpn-gateway-appliance/pull/20) (drafts), image sources [#16](https://github.com/openshift/evpn-gateway-appliance/pull/16) (opened 2026-10-15; [#6](https://github.com/openshift/evpn-gateway-appliance/pull/6) is on hold), `Dockerfile.root` removal [#13](https://github.com/openshift/evpn-gateway-appliance/pull/13) |

Known limits of the current checks:

- `check-public-safe.py` skips missing inputs, files over 2,000,000 bytes, known binary
  suffixes and files with an early NUL byte, and skips every rule on a line carrying its
  inline approval marker. It reads the working tree, not history or commit messages.
- `check-pins.py` resolves hexadecimal revisions only; a link pinned to a tag is not checked.
  Cite tool and repository sources by commit SHA, with the release version in prose.
- Positive Prow runs exist for the current runner. A safe failing run that Tide refuses
  to merge has not been recorded; capture one the next time the runner or required
  contexts change. Harmless seeded failures include a reserved `example.com` address for the
  public-safety scan, a duplicate YAML key or an unknown Ansible module; confirm the job fails
  for that reason, not a setup error.

Jira: [CORENET-7615](https://redhat.atlassian.net/browse/CORENET-7615) tracks these plans,
[CORENET-7622](https://redhat.atlassian.net/browse/CORENET-7622) Prow onboarding,
[CORENET-7664](https://redhat.atlassian.net/browse/CORENET-7664) standard documentation and tool
lint, [CORENET-7507](https://redhat.atlassian.net/browse/CORENET-7507) completed collection lint,
[CORENET-7667](https://redhat.atlassian.net/browse/CORENET-7667) remaining collection CI and
[CORENET-7506](https://redhat.atlassian.net/browse/CORENET-7506) appliance CI. Tide needs a
valid key in each PR title; agree new keys with their owners.

## How to add a check

1. **Prefer one complete feature per PR:** the tool pin in `Dockerfile.ci`, native configuration,
   the Make target and the source fixes that make the tree pass. Prow builds the PR's own
   `Dockerfile.ci`, so the tool and its first use can land together. Pin PyPI tools in the
   existing `pip install`; for others use a lockfile or an exact
   release with its checksum.
2. **Wire it in `rules.mk`:** a `.PHONY` `check-<name>` target listed in `check`'s
   prerequisites. `rules.mk` already runs recipes under Bash with `pipefail`. Select inputs
   the way existing targets do:
   `git ls-files -z -c -o --exclude-standard -- '<pattern>' | xargs -0 -r <tool> --`.
3. **Use the tool's own configuration.** Wrapper scripts and finding baselines become code to
   maintain; reach for one only for a gap the tool cannot cover, and record it in the
   [budget](#custom-code-budget). Prefer fixing source to adding exceptions; keep exceptions
   narrow and commented.
4. **Keep the merge gate offline.** Advisory databases, link liveness and latest-version
   checks belong in a scheduled lane ([what may block](ci-bootstrap-spec.md#what-may-block-a-pull-request)).
5. **Verify:** run `make check OFFLINE=1` on the clean tree; seeding one defect the check
   should reject, then restoring it, shows the check can fail. Confirm the PR's `ci/prow/images` and
   `ci/prow/verify` passed on the final SHA.

Prefer the existing `verify` job unless a separate job has a clear runtime, resource,
privilege or scheduling reason.

## Queue

Each row is independent; take whichever has ready inputs.

| Check | Inputs | Notes |
| --- | --- | --- |
| Python and shell: Ruff, ShellCheck | Git-tracked and new unignored `*.py`, `*.sh` | Draft [#18](https://github.com/openshift/evpn-gateway-appliance/pull/18) and [#19](https://github.com/openshift/evpn-gateway-appliance/pull/19); basic rule sets (Ruff `E4,E7,E9,F`) |
| Dockerfile: hadolint | Git-tracked and new unignored `Dockerfile*` and `Containerfile*` | [#20](https://github.com/openshift/evpn-gateway-appliance/pull/20) pins Hadolint 2.15.1 via `hadolint-py`, fixes DL3059/SC2155 and records reviewed exceptions for DL3007/DL3041 in `Dockerfile.ci` and DL3041 in `image/rhel10/Containerfile`. Lint does not replace the native image build |
| Ansible lint findings | `ansible/` | Main runs the `production` profile, skips only `var-naming[no-role-prefix]`. Fix those findings and drop the skip; no new tool |
| Role-discovery smoke | `check-ansible-install` | Set `ANSIBLE_COLLECTIONS_SCAN_SYS_PATH=false` for `ansible-doc` so a collection on the Python path cannot satisfy the role count ([tool notes](#tool-notes)) |

Later work belongs to [later CI](ci-bootstrap-spec.md#later-sequence): a native image build
of the image sources (#16 proposes one, with a nested CI derivative), and Molecule role scenarios (pin Molecule in `Dockerfile.ci`; start with one
role's controller-only negative cases, [test placement](ci-bootstrap-spec.md#test-placement)).

Finding, 2026-10-22. `make nested-ci-appliance-image` builds that derivative on the host.
The record is
[Finding 2026-10-22 nested CI vfs image](containerfile-refactor-spec.md#finding-2026-10-22-nested-ci-vfs-image).

`ansible-test sanity` is the standard collection check for publication, but it installs its
test environments from the network, so it belongs in the destination-check lane (L4), not
the offline gate.

## Deferred

These replacements and additions were evaluated and are not scheduled. Revisit one only
for a demonstrated coverage need or maintenance saving.

- **Provider tokens and history.** Ask the repository owner to confirm GitHub secret
  scanning and push protection are enabled; on a public repository they cover provider
  tokens across history without a Prow lane.
- **Gitleaks in place of `check-public-safe.py`.** Gitleaks finds provider tokens the helper
  does not, but its default configuration excludes paths such as lockfiles and SVGs, and
  it has no email, IP or private-term rules. Porting those rules costs more than the
  100-line helper. Gitleaks as an additional provider-token check is a reasonable later
  proposal; `gitleaks dir` does not honor `.gitignore`, so feed it Git-selected files.
- **History and commit-message scanning in Prow.** Needs a chosen scanner; confirm with one
  run that the job's clone contains `PULL_BASE_SHA`, and never fall back to a shorter range;
  scheduled and postsubmit runs need an explicit range.
- **lychee in place of `check-links.py`/`check-pins.py`.** `lychee --offline` over all tracked
  Markdown would also cover files the helper skips (it reads only `plans/context/evpn-aws/*.md`
  and `examples/README.md`, not `AGENTS.md` or `ansible/`). It cannot replace `check-pins.py`:
  with a token it confirms that a private repository exists, not that a path exists at a
  revision. Locally, lychee 0.24.2 also read `[`, `*` and `?` in input names as globs.
- **Codespell.** No demonstrated need beyond Markdown lint.
- **Image inventory validators.** #6 removed its custom inventory helpers; start with
  hadolint, ShellCheck and a native build. #16 instead renders the bound-image units from one
  inventory with a 435-line `image/tools/payload.py` (render, cache and load) and adds its
  tests to `verify`; weigh that against the [budget](#custom-code-budget) in its review.

## Tool notes

Observations from local runs and source reads, with the version and date where they were
made, so agents can start their own research from evidence rather than repeat it. They are
not requirements. Recheck one against the current tool before relying on it.

### Runner and Prow

- Prow overrides `Dockerfile.ci`'s `FROM` (with `ocp/ubi-python-312:9`), so a local image can
  differ from Prow's. In a linked Git worktree the image's copied `.git` points outside the
  build context; use `USE_IMAGE=0` there.
- `Dockerfile.ci` makes `/src` read-only, and a copy keeps those permissions: a check that
  copies a source file and then writes to the copy fails with `Permission denied` (seen with
  `ansible-test` here and #16's payload test in Prow). Copy and then `chmod -R u+w`, or write
  new files instead.
- The build context keeps `.git`, so a local image contains repository metadata and history,
  and `safe.directory '*'` trusts every repository. Both are fine for this CI image; review
  them before publishing any image built the same way.
- A separate job is generated in `openshift/release` with `make ci-operator-config`,
  `make jobs WHAT=openshift/evpn-gateway-appliance` and `make checkconfig`
  ([`0f724979`, Makefile](https://github.com/openshift/release/blob/0f72497967354022420becb86928c655a2b117c9/Makefile)).
  Config validation alone shows neither command availability nor execution.
- `git rev-parse` can echo a full SHA whose object is absent; `git cat-file -e "${PULL_BASE_SHA:?}^{commit}"`
  checks that a history range is really present in the job's clone.
- One way to approximate the Prow runner locally, from staged files only (`checkout-index`
  ignores `export-ignore`; plain `git add .` would skip tracked files that match ignore rules):

  ```bash
  set -euo pipefail
  src=$(mktemp -d); trap 'rm -rf "$src"' EXIT
  git checkout-index --all --prefix="$src/src/"
  git -C "$src/src" init -q
  git -C "$src/src" add --force --all -- .
  chmod -R a+rX "$src/src"
  podman build -f "$src/src/Dockerfile.ci" --iidfile "$src/id" "$src/src"
  podman run --rm --network none --read-only --tmpfs /tmp -u 1234:0 -e HOME=/tmp \
    "$(cat "$src/id")" bash -c 'set -e; python3 -m pip check; make verify OFFLINE=1'
  ```

  `HOME=/tmp` is needed because ansible-lint writes a cache under `$HOME` and the image root is
  read-only here. [`pip check`](https://pip.pypa.io/en/stable/cli/pip_check/) reports missing or
  incompatible installed dependencies. Run against the image's `/src`: a writable copy would
  hide its source-permission failures, and `git diff` would miss newly created untracked files.
- [release#86815](https://github.com/openshift/release/pull/86815) is an open, do-not-merge
  experiment that builds #6's image with Prow's native image inputs
  ([`ac280109`, config](https://github.com/openshift/release/blob/ac2801091c39f2a043ac63df58947b18e3ae1b67/ci-operator/config/openshift/evpn-gateway-appliance/openshift-evpn-gateway-appliance-main.yaml));
  its rehearsal had not passed when last checked. A public-base build would not qualify the
  authenticated RHEL build.

### yamllint

Checked: 1.38.0 (rechecked 2026-10-15), [`cba56bcd`](https://github.com/adrienverge/yamllint/blob/cba56bcde1fdd01c1deb3f945e69764c291a6530/yamllint/rules/key_duplicates.py).

- `key-duplicates` compares scalar text, so `true`/`True` or `01`/`1` as duplicate keys pass
  although the YAML loader merges them; a misspelled `kind` also passes, since lint is not a
  schema check.
- `# yamllint disable-file` skips parsing the file entirely, and a config `ignore:` key hides
  files even when Git selected them (seen with an earlier collection `.yamllint`).

### ansible-lint and Ansible

Checked: core 2.21.4 at [`997ad6b3`](https://github.com/ansible/ansible/tree/997ad6b3491920e355c69eb35614097be9759dca).

- The [`basic` profile](https://docs.ansible.com/projects/lint/profiles/#basic) adds common
  coding rules to fatal loading checks, and its [syntax rule](https://docs.ansible.com/projects/lint/rules/syntax-check/)
  runs Ansible's parser. A raw `apt-get` command passed `min` but failed `basic` with `command-instead-of-module`
  (rechecked 2026-10-15).
  Warnings fail only with `--strict`; a profile declared in config does not by itself fail
  warn-listed rules ([profiles](https://github.com/ansible/ansible-lint/blob/665d9e07a1943254d2910faffc106adaf7ea7294/src/ansiblelint/data/profiles.yml)).
  On #7 at `55d471e0`, the 12 `risky-shell-pipe` warnings fell in `safety` and the 8
  `ignore-errors` in `shared`/`production`; they are findings to review, not 20 confirmed bugs.
- `ansible-playbook --syntax-check` does not parse `include_tasks` files
  ([prototype measurement](ci-bootstrap-spec.md#required-source-checks)), and neither lint nor
  syntax checking runs role argument validation ([test placement](ci-bootstrap-spec.md#test-placement)).
- `ansible-lint` documents the [yamllint settings](https://docs.ansible.com/projects/lint/rules/yaml/#yamllint-configuration)
  it expects; the collection's `.yamllint` follows them.
- [`ansible-galaxy collection download`](https://docs.ansible.com/projects/ansible/latest/collections_guide/collections_downloading.html)
  resolves dependencies and writes an offline requirements file; on 2026-10-07 the four
  Galaxy lower bounds resolved with no transitive Galaxy dependencies.

### Collection build, install and discovery

Checked: core 2.21.4.

- `build_ignore` is a deny list without negation, so new files ship by default;
  `ansible/tools/check-collection-tarball.sh` allowlists the tarball.
- The native `manifest` directive ([builder](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/galaxy/collection/__init__.py),
  [upstream cases](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/test/integration/targets/ansible-galaxy-collection-cli/tasks/manifest.yml))
  needs `distlib`. On merged `ansible/` (main `31cfdbb9`, 2026-10-15, core 2.21.4 and
  distlib 0.4.0 in a host venv) this configuration kept README, runtime and EE metadata, the
  dependency files and all six roles' entry points and READMEs, and excluded `ansible.cfg`,
  inventory, `tools/`, stray root files and `.wg-keys/` and hidden-directory fixtures:

  ```yaml
  manifest:
    omit_default_directives: true
    directives:
      - include README.md LICENSE requirements.txt bindep.txt
      - recursive-include meta *.yml *.yaml
      - recursive-include roles *.yml *.yaml *.j2 *.md
      - recursive-include playbooks *.yml *.yaml
      - recursive-exclude roles */.*/**
  ```

  Without the `recursive-exclude`, a file under a hidden role subdirectory shipped. An invalid
  directive fails the build, but a missing `meta/runtime.yml` still builds, so required paths
  still need an explicit check.
- `collection install` checks payloads against `FILES.json` (a payload edited without updating
  `FILES.json` fails) but not `FILES.json` against `MANIFEST.json`; `collection verify` does,
  which matters once an artifact moves between systems ([content integrity](ci-bootstrap-spec.md#collection-content-integrity)).
- `ANSIBLE_COLLECTIONS_PATH` replaces the default collection paths, but `ansible-doc` still
  scans `ansible_collections` on the Python path unless `ANSIBLE_COLLECTIONS_SCAN_SYS_PATH=false`
  ([config](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/config/base.yml)).
  A wrong-namespace artifact satisfied all six role headers that way
  ([measured](ci-bootstrap-spec.md#measured-collection-build-and-import-behavior)).
  `ANSIBLE_CONFIG=/dev/null` is rejected (unsupported extension, exit 5); a temporary `.cfg`
  containing `[defaults]` works ([config manager](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/config/manager.py)).
- `ansible-doc -t role -e main <role>` returns 0 even when the role does not exist, so a
  discovery check must assert the expected names. Listing with a collection filter
  (`ansible-doc -t role -l network.evpn_gateway`) avoids warnings from unrelated collections
  ([`doc.py`](https://github.com/ansible/ansible/blob/997ad6b3491920e355c69eb35614097be9759dca/lib/ansible/cli/doc.py)).

### Ruff and ShellCheck

- Ruff 0.17's default rule set reports more than `E4,E7,E9,F` (for example FURB167 and
  PLW1510 on the planning helpers), so a basic check names its rules. 0.17.0 treats an
  existing `@` filename literally
  ([`5b27c1cc`](https://github.com/astral-sh/ruff/blob/5b27c1ccfaa230fb195855f5cf3404a21e3379cd/crates/ruff_command_line/src/lib.rs)),
  but reads a missing `@name.py`, even after `--`, as a response file `name.py`; an empty
  `name.py` then passes. Prefixed `./@name.py` is a path, and a missing one fails with E902
  (rechecked 2026-10-16). Ruff 0.15.20 and 0.17.0 both write their report to an
  inherited `RUFF_OUTPUT_FILE`, even with `--isolated`, replacing that file's contents
  ([`f82a36b6`, args](https://github.com/astral-sh/ruff/blob/f82a36b6baf8c0547a17bbde6c0d927ccd45d938/crates/ruff/src/args.rs)).
- ShellCheck's `--norc` still honors `SHELLCHECK_OPTS`
  ([`aac0823e`, manual](https://github.com/koalaman/shellcheck/blob/aac0823e6b58f8a499e856e93738082691cbf212/shellcheck.1.md)),
  and a missing file fails. It does not see shell embedded in Dockerfiles or Tekton; hadolint
  covers Dockerfile `RUN` lines.

### hadolint

Checked: 2.15.1 source at `2eece559`; behavior rechecked with the `hadolint-py` 2.15.1 binary on 2026-10-16.

- Ignore lists from discovered config and the environment merge, a malformed discovered
  config can fall back to defaults, and the Codacy and Code Climate formats can exit 0 with
  findings ([`Main.hs`](https://github.com/hadolint/hadolint/blob/2eece55955ced00200be9729e9728cb7dacca505/app/Main.hs),
  [`Configuration.hs`](https://github.com/hadolint/hadolint/blob/2eece55955ced00200be9729e9728cb7dacca505/src/Hadolint/Config/Configuration.hs),
  [`Environment.hs`](https://github.com/hadolint/hadolint/blob/2eece55955ced00200be9729e9728cb7dacca505/src/Hadolint/Config/Environment.hs)).
- An unpinned `pip install` fails DL3013, but a pinned version that does not exist passes, so
  lint does not replace an image build. Earlier #6 Containerfiles reported DL3006, DL3041 and
  DL3059; #6 has since been rewritten.

### markdownlint-cli2

Checked: 0.23.3, [`916ad0aa`](https://github.com/DavidAnson/markdownlint-cli2/blob/916ad0aaa108c64d294101002066f530ea170b10/README.md).

- Arguments are globs; prefix a filename with `:` to make it literal. `--no-globs` only
  ignores the config's `globs`; nested configurations can override root settings.
- It needs Node >=22 ([engines](https://github.com/DavidAnson/markdownlint-cli2/blob/916ad0aaa108c64d294101002066f530ea170b10/package.json)).
  [`npm ci`](https://docs.npmjs.com/cli/v10/commands/npm-ci/) against a lockfile pins
  transitive packages; a global version pin does not.

### Codespell

Checked: 2.4.3, 2026-10-07.

- `@`-prefixed names and missing inputs need care, and discovered configuration and write
  settings still apply with `--config /dev/null`; there is no isolation switch
  ([`_codespell.py`](https://github.com/codespell-project/codespell/blob/57b21406f092110c18776e39b0bda50d37c945c8/codespell_lib/_codespell.py)).

### lychee

Checked: 0.24.2, 2026-10-06 (glob case rechecked 2026-10-15), [`2bba2716`](https://github.com/lycheeverse/lychee/tree/2bba271688c1abb1503097a064e6c3bc1d1b6a9b).

- Inputs containing `[`, `*` or `?` are classified as globs before checking whether the file
  exists ([`source.rs`](https://github.com/lycheeverse/lychee/blob/2bba271688c1abb1503097a064e6c3bc1d1b6a9b/lychee-lib/src/types/input/source.rs),
  [`resolver.rs`](https://github.com/lycheeverse/lychee/blob/2bba271688c1abb1503097a064e6c3bc1d1b6a9b/lychee-lib/src/types/input/resolver.rs));
  an unmatched escaped glob also passed with zero links.
- Anchors are checked only with `include_fragments` set in a config; it extracts rendered
  Markdown links, not fenced code ([`markdown.rs`](https://github.com/lycheeverse/lychee/blob/2bba271688c1abb1503097a064e6c3bc1d1b6a9b/lychee-lib/src/extract/markdown.rs)).
- With a token, its GitHub API fallback confirms a private repository exists, not that a path
  exists at a revision ([`website.rs`](https://github.com/lycheeverse/lychee/blob/2bba271688c1abb1503097a064e6c3bc1d1b6a9b/lychee-lib/src/checker/website.rs)).

### Gitleaks

Checked: 8.30.1, 2026-10-06 (`dir`, inline allow and `.gitleaksignore` rechecked 2026-10-15), [`83d9cd68`](https://github.com/gitleaks/gitleaks/tree/83d9cd684c87d95d656c1458ef04895a7f1cbd8e).

- The default config carries global path exclusions (lockfiles, SVGs, `go.mod`) that an
  extending config inherits, and a nonmatching allowlist does not undo them
  ([`gitleaks.toml`](https://github.com/gitleaks/gitleaks/blob/83d9cd684c87d95d656c1458ef04895a7f1cbd8e/config/gitleaks.toml),
  [`config.go`](https://github.com/gitleaks/gitleaks/blob/83d9cd684c87d95d656c1458ef04895a7f1cbd8e/config/config.go)).
- An inline `gitleaks:allow` and a source-root `.gitleaksignore` suppress findings, the latter
  even with the ignore path set to `/dev/null`; `--ignore-gitleaks-allow` disables the inline
  form ([`root.go`](https://github.com/gitleaks/gitleaks/blob/83d9cd684c87d95d656c1458ef04895a7f1cbd8e/cmd/root.go),
  [`detect.go`](https://github.com/gitleaks/gitleaks/blob/83d9cd684c87d95d656c1458ef04895a7f1cbd8e/detect/detect.go)).
  An allowlist with both path and value matches either unless `condition = "AND"`.
- A rule whose regex consumes its delimiters misses a second value right after an allowed one.
  `--redact` covers `Line`, `Match` and `Secret`; a narrow capture group can leave parts of a
  value, and JSON reports keep commit-message metadata ([`finding.go`](https://github.com/gitleaks/gitleaks/blob/83d9cd684c87d95d656c1458ef04895a7f1cbd8e/report/finding.go)).
- `gitleaks git` does not read commit messages, and `gitleaks dir` does not honor `.gitignore`.
  For merges, `git log --diff-merges=first-parent` keeps merge-resolution changes, while
  `--first-parent` drops side-branch history
  ([`sources/git.go`](https://github.com/gitleaks/gitleaks/blob/83d9cd684c87d95d656c1458ef04895a7f1cbd8e/sources/git.go),
  [git-log](https://git-scm.com/docs/git-log#Documentation/git-log.txt---diff-mergesformat)).

### Image sources

- #6 (on hold) at `67524c74`: the [Containerfile](https://github.com/openshift/evpn-gateway-appliance/blob/67524c74561280138e12fa55b4439ac131f7f8f7/image/rhel10/Containerfile)
  uses literal `ARG` defaults; nothing in the build reads
  [`payload-images.yaml`](https://github.com/openshift/evpn-gateway-appliance/blob/67524c74561280138e12fa55b4439ac131f7f8f7/image/payload-images.yaml),
  [`payload-images.env`](https://github.com/openshift/evpn-gateway-appliance/blob/67524c74561280138e12fa55b4439ac131f7f8f7/image/rhel10/payload-images.env)
  or `streams.yaml`, and the [README](https://github.com/openshift/evpn-gateway-appliance/blob/67524c74561280138e12fa55b4439ac131f7f8f7/image/README.md)
  still points at the removed helpers. An earlier inventory
  [checker](https://github.com/openshift/evpn-gateway-appliance/blob/d5fb9fdad3d4bc486ba5f4c145806d64d09a39cb/image/tools/check-image-inventory.py)
  passed five broken-input cases (missing build or environment files, empty inventory,
  malformed digest, YAML/environment disagreement).
- #16 at `13189813` (2026-10-15): the [RHEL 10 Containerfile](https://github.com/openshift/evpn-gateway-appliance/blob/131898134326933380f6e26952b637b8efde87e0/image/rhel10/Containerfile)
  renders Quadlet units for digest-pinned OCP 4.22 `frr-rhel9` and node-exporter images from
  [`payload-images.yaml`](https://github.com/openshift/evpn-gateway-appliance/blob/131898134326933380f6e26952b637b8efde87e0/image/payload-images.yaml)
  and lists them as bootc logically bound images; 4.22 because the 4.23 and 5.x metrics binary
  exits outside Kubernetes. Its [README](https://github.com/openshift/evpn-gateway-appliance/blob/131898134326933380f6e26952b637b8efde87e0/image/README.md)
  notes that a plain `podman build` does not populate the bound-image store, so offline boot
  needs a disk built with bootc or an image builder.

### Peer configurations

Examples, not a mandate: [`tmt` hooks](https://github.com/teemtee/tmt/blob/8241dea2a21e4de6dc9f4fddc8b463946f15b471/.pre-commit-config.yaml),
[bootc peer hooks](https://github.com/ansible-automation-platform/automation-portal-bootc-container/blob/ee6c9d81265b96f475d29b79b63d6e92c9b81ea5/.pre-commit-config.yaml),
[AAP pipelines Makefile](https://github.com/ansible-automation-platform/aap-konflux-pipelines/blob/b09356dbc675aa404bfcd7f732a23d8c2b0c40d1/Makefile).

## Custom-code budget

Custom CI code needs a requirement that no maintained tool covers. Current code:

| Code | Lines | What it checks | Keep until |
| --- | --- | --- | --- |
| `plans/context/evpn-aws/tools/check-public-safe.py` | 100 | Email addresses, non-documentation IPv4 addresses (`--allow-private` skips RFC 1918), AWS account IDs, cloud/API tokens, private and SSH keys, support-case numbers, secret assignments and selected chat/private-document links; names only through a private `--terms` file | A native scanner covers its email, address, account and private-term rules |
| `plans/context/evpn-aws/tools/check-links.py`, `check-pins.py` | 111 + 45 | Relative links and anchors in the plans; online, external URLs including fragments (rate-limited hosts are reported as unreachable rather than broken, but still fail the run; rerun later) and GitHub blob/tree paths at a hexadecimal revision through authenticated `gh`. A resolving pin proves the path exists, not the claim made about it | A native link checker handles literal filenames and authenticated revision paths |
| `plans/context/evpn-aws/tools/check-all.sh` | 15 | Runs the helpers above and accumulates failures; `--offline` skips URLs and pins | The helpers above are retired |
| `ansible/tools/check-collection-tarball.sh` | 26 | Tarball root paths against an allowlist, required `meta/runtime.yml` and `README.md`; prints the `MANIFEST.json` digest | The native `manifest` directive plus required-path checks replace it |

Add a row here when a PR adds custom glue, with the reason.
