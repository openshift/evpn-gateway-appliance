# Run every recipe under bash with pipefail so a failed pipe (e.g. `git ls-files |
# xargs ...`) fails the target instead of being masked, for every entry point.
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# The single entry point CI runs (`make verify OFFLINE=1`).
.PHONY: verify
verify: check

# Static source checks aggregating the planning-docs corpus integrity, the
# public-safety scan, the repo-wide yaml, Markdown and shell lint, and the Ansible
# collection checks.
.PHONY: check
check: check-corpus check-public check-yaml check-markdown check-shell check-ansible

# Planning-docs corpus integrity: link + anchor + pin resolution, embedded-snippet
# tests, and public-safe over the plans/ docs (check-all.sh bundles them).
#
#   make check-corpus            full run (link + pin checks need network + authenticated gh)
#   make check-corpus OFFLINE=1  skip the network/gh checks (link + pin resolution)
#
# The corpus checkers (check-all.sh and friends) and check-public-safe.py are stdlib-only
# Python; they need just python3 plus curl/gh at runtime for the corpus network checks.
TOOLS := plans/context/evpn-aws/tools
.PHONY: check-corpus
check-corpus:
	$(TOOLS)/check-all.sh $(if $(OFFLINE),--offline,)

# Public-exposure scan over tracked and new-but-not-ignored files (emails, non-doc
# IPs, AWS account IDs, keys/tokens, secret assignments, internal links) for this
# PUBLIC repository. --exclude-standard keeps gitignored local artifacts (generated
# inventory, keys) out; --allow-private skips RFC1918 lab addrs; annotate known-public
# values with an inline `public-safe: ok`.
#
#   make check-public TERMS=path also screen for customer/partner/account names listed
#                                in `path` (keep that file OUTSIDE the repo; never commit it)
#
TERMS ?=
.PHONY: check-public
check-public:
	git ls-files -z -c -o --exclude-standard | xargs -0 -r python3 $(TOOLS)/check-public-safe.py --allow-private $(if $(TERMS),--terms $(TERMS),)

# Lenient repo-wide yaml check (anchors + duplicate merge keys) over every tracked/
# untracked-not-ignored yaml, including the plans corpus and .ci-operator.yaml, using
# the root .yamllint.
.PHONY: check-yaml
check-yaml:
	# Exclude ansible/: the collection has its own strict yaml lint (ansible/.yamllint)
	# in the check-ansible-lint target, so linting it here too would be redundant.
	git ls-files -z -c -o --exclude-standard -- '*.yml' '*.yaml' '*.yamllint' ':(exclude)ansible/' | xargs -0 -r yamllint -c .yamllint --

# Repo-wide Markdown lint with the root .markdownlint-cli2.jsonc (tool and host setup:
# ci/markdownlint/README.md). markdownlint-cli2 reads arguments as globs; a leading ':'
# makes each Git-selected path literal. Require the root config instead of falling back
# to native defaults when it is missing.
.PHONY: check-markdown
check-markdown:
	git ls-files -z -c -o --exclude-standard -- '*.md' | sed -z 's/^/:/' | xargs -0 -r markdownlint-cli2 --config .markdownlint-cli2.jsonc --

# Repo-wide shell lint with ShellCheck (installed in Dockerfile.ci). --norc ignores every
# .shellcheckrc and `env -u` drops options inherited through SHELLCHECK_OPTS, so exceptions
# can only be in-file `# shellcheck disable=` comments.
.PHONY: check-shell
check-shell:
	git ls-files -z -c -o --exclude-standard -- '*.sh' | xargs -0 -r env -u SHELLCHECK_OPTS shellcheck --norc --

# ── Ansible collection source checks ─────────────────────────────────────────
# Lint, playbook syntax, collection build + tarball allowlist, and a clean-env
# install smoke with ansible-builder dependency introspection. Runs under
# `make verify OFFLINE=1` on the network-less build root; the only step that
# touches the network is the install smoke, and only when OFFLINE is unset
# (then it also resolves galaxy.yml's collection deps). The toolchain
# (ansible-core, ansible-lint, yamllint, ansible-builder) is pinned in
# Dockerfile.root.

# Collection source tree, and an out-of-tree dir for the clean-install smoke
# (kept outside the checkout so it is neither scanned nor committed).
ANSIBLE := ansible
ANSIBLE_SMOKE_DIR := /tmp/ega-collections

.PHONY: check-ansible
check-ansible: check-ansible-lint check-ansible-syntax check-ansible-build check-ansible-install

.PHONY: check-ansible-lint
check-ansible-lint:
	# git ls-files respects .gitignore, so the generated inventory and local key
	# material are excluded without duplicating .gitignore in ansible/.yamllint.
	cd $(ANSIBLE) && git ls-files -z -c -o --exclude-standard -- '*.yml' '*.yaml' '*.yamllint' | xargs -0 -r yamllint -c .yamllint --
	# ansible-lint (via ansible-compat) installs the collection + deps into
	# $ANSIBLE_HOME/collections to resolve FQCNs; give it a throwaway home so that
	# side effect doesn't leak into the clean-install smoke (check-ansible-install).
	cd $(ANSIBLE) && ANSIBLE_HOME="$$(mktemp -d)" ansible-lint -c .ansible-lint roles playbooks

.PHONY: check-ansible-syntax
check-ansible-syntax:
	# -i localhost, : syntax-check only parses structure; this avoids a noisy
	# "can't parse inventory/hosts.yml" warning (that file is generated, gitignored).
	cd $(ANSIBLE) && for pb in playbooks/*.yml; do \
	  echo "syntax-check $$pb"; \
	  ansible-playbook -i localhost, --syntax-check "$$pb" || exit 1; \
	done

.PHONY: check-ansible-build
check-ansible-build:
	# Build into the smoke dir, not the source tree, so the checkout can stay read-only.
	# --force overwrites a stale tarball so reruns don't fail.
	mkdir -p $(ANSIBLE_SMOKE_DIR)
	cd $(ANSIBLE) && ansible-galaxy collection build --force --output-path $(ANSIBLE_SMOKE_DIR)
	$(ANSIBLE)/tools/check-collection-tarball.sh $(ANSIBLE_SMOKE_DIR)/*.tar.gz

# Install into a clean collections dir OUTSIDE the checkout (source-tree runs
# hide packaging defects), introspect the installed tarball's declared Python/
# system deps (fails on missing/unreadable EE dependency files), and confirm that
# EVERY source role installed and is discoverable (its argument_specs parse) from
# that clean path.
.PHONY: check-ansible-install
check-ansible-install: check-ansible-build
	# Clean only the install tree, keeping the tarball check-ansible-build left here.
	rm -rf $(ANSIBLE_SMOKE_DIR)/ansible_collections
	# OFFLINE=1 (what Prow runs on the network-less build root): resolve deps from the
	# collections baked into the image, failing if a baked version no longer satisfies
	# galaxy.yml's ranges. Online (plain `make verify`): resolve+install galaxy.yml's
	# collection deps from Galaxy to verify the dependency list actually resolves.
	ansible-galaxy collection install $(ANSIBLE_SMOKE_DIR)/*.tar.gz -p $(ANSIBLE_SMOKE_DIR) $(if $(OFFLINE),--offline,)
	ansible-builder introspect $(ANSIBLE_SMOKE_DIR)
	# ansible-doc lists each role twice (short name + FQCN); count the FQCN headers
	# and require one per role directory in the source tree, so a partial install fails.
	expected=$$(ls -d $(ANSIBLE)/roles/*/ | wc -l); \
	found=$$(ANSIBLE_COLLECTIONS_PATH=$(ANSIBLE_SMOKE_DIR) ansible-doc -t role -l 2>/dev/null | grep -cE '^network\.evpn_gateway\.[a-z_]+:$$'); \
	test "$$found" = "$$expected" || { echo "ERROR: expected $$expected collection roles discoverable from the clean install, found $$found" >&2; exit 1; }
