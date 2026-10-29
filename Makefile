# Entry point + container delegation. By default the requested target(s) run inside the
# pinned CI image (Dockerfile.ci) for parity with CI; the real targets live in rules.mk.
#
#   make <target>              run <target> inside the CI image (built first)
#   make <target> USE_IMAGE=0  run on the host with local tools instead
#   make ci-image              just build the CI image
#   make appliance-image       build image/rhel10 on the host
#   make nested-ci-appliance-image       build the :ci appliance, then the nested child, on the host
#
# OFFLINE is forwarded into the container; TERMS (a file kept outside the repo) is
# bind-mounted read-only and its in-container path passed through.

USE_IMAGE ?= 1
CI_IMAGE ?= localhost/evpn-gateway-appliance-ci:local
EE_IMAGE ?= localhost/evpn-gateway-appliance-ee:local
CONTAINER_ENGINE ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)
comma := ,

# One container run. $(1) = goals to run inside (empty -> the image's default goal).
CONTAINER_RUN = $(CONTAINER_ENGINE) run --rm \
	$(if $(TERMS),-v $(abspath $(TERMS)):/terms:ro$(comma)Z,) \
	$(CI_IMAGE) make $(1) OFFLINE=$(OFFLINE) $(if $(TERMS),TERMS=/terms,)

# Delegate to the image unless we are already inside it (EGA_IN_CI_IMAGE is set in
# Dockerfile.ci) or the user opted out with USE_IMAGE=0.
ifndef EGA_IN_CI_IMAGE
ifeq ($(USE_IMAGE),1)
DELEGATE := 1
endif
endif

ifeq ($(DELEGATE),1)
ifeq ($(MAKECMDGOALS),)
# Bare `make`: delegate with no goal so the container uses rules.mk's own default goal.
.DEFAULT_GOAL := container-default
.PHONY: container-default
container-default: ci-image
	$(call CONTAINER_RUN,)
else
# Forward the named goals into a single container run: the first builds the image and
# runs them, the rest are no-ops. The appliance targets build on the host.
FWD := $(filter-out ci-image ee-image appliance-image ci-appliance-image nested-ci-appliance-image e2e-kind,$(MAKECMDGOALS))
ifneq ($(FWD),)
.PHONY: $(FWD)
$(firstword $(FWD)): ci-image
	$(call CONTAINER_RUN,$(FWD))
$(filter-out $(firstword $(FWD)),$(FWD)):
	@:
endif
endif
else
include rules.mk
endif

# Build the pinned CI image (host-side; needs podman/docker). Defined last so that on the
# non-delegate path rules.mk's first target stays the natural default goal.
.PHONY: ci-image
ci-image:
	@test -n "$(CONTAINER_ENGINE)" || { echo "no podman/docker found; use USE_IMAGE=0 to run on the host" >&2; exit 1; }
	$(CONTAINER_ENGINE) build -f Dockerfile.ci -t $(CI_IMAGE) .

# Build the e2e execution environment ($(EE_IMAGE)) from the collection's EE metadata. Uses
# the CI image (for ansible-builder); builds the EE into whichever store this runs against,
# so for the e2e lane (rootful siblings) run it the same way as `ci-image`: `sudo make ee-image`.
# No `ci-image` prerequisite on purpose: the CI image ($(CI_IMAGE)) must already exist (locally
# run `make ci-image` first, as the README shows; the CI VM lane loads it from a passed-in image),
# so this never forces a CI-image rebuild.
.PHONY: ee-image
ee-image:
	EGA_E2E_IMAGE=$(CI_IMAGE) EGA_EE_IMAGE=$(EE_IMAGE) test/e2e/ee/build.sh

# Appliance bootc image (image/rhel10/Containerfile). Host-side: the build needs the
# host engine and a registry auth file that must stay outside the build context.
# Unset BOOTC_BASE, FRR_IMAGE, and NODE_EXPORTER_IMAGE keep the Containerfile defaults.
# ci-appliance-image is the parent of the nested child. It is the same Containerfile
# with the CentOS CI base from image/streams.yaml bootcImageCi, tagged :ci.
# appliance-image stays on :dev so a release build does not replace that parent.
APPLIANCE_TAG ?= localhost/evpn-appliance-rhel10:dev
APPLIANCE_IMAGE ?= localhost/evpn-appliance-rhel10:ci
BOOTC_BASE_CI ?= quay.io/centos-bootc/centos-bootc:stream10
CONTAINER_AUTH_FILE ?= $(HOME)/.docker/config.json
BOOTC_BASE ?=
FRR_IMAGE ?=
NODE_EXPORTER_IMAGE ?=
# Extra `podman build` flags honored ONLY by ci-appliance-image (the CI parent build), not by
# the release appliance-image. Empty normally; the e2e lane sets --network=host plus an insecure-
# registry drop-in so the Containerfile's build-time skopeo can pull FRR/node-exporter from an
# on-VM local registry (see test/e2e/run_remote.sh).
APPLIANCE_CI_BUILD_ARGS ?=

.PHONY: appliance-image ci-appliance-image
ci-appliance-image: APPLIANCE_TAG = $(APPLIANCE_IMAGE)
ci-appliance-image: BOOTC_BASE = $(BOOTC_BASE_CI)
ci-appliance-image: _ci_build_args = $(APPLIANCE_CI_BUILD_ARGS)

appliance-image ci-appliance-image:
	@test -n "$(CONTAINER_ENGINE)" || { echo "no podman/docker found" >&2; exit 1; }
	@test -f "$(CONTAINER_AUTH_FILE)" || { echo "registry auth file missing: $(CONTAINER_AUTH_FILE)" >&2; exit 1; }
	REGISTRY_AUTH_FILE="$(CONTAINER_AUTH_FILE)" $(CONTAINER_ENGINE) build \
		-f image/rhel10/Containerfile \
		-t "$(APPLIANCE_TAG)" \
		$(if $(BOOTC_BASE),--build-arg BOOTC_BASE=$(BOOTC_BASE)) \
		$(if $(FRR_IMAGE),--build-arg FRR_IMAGE=$(FRR_IMAGE)) \
		$(if $(NODE_EXPORTER_IMAGE),--build-arg NODE_EXPORTER_IMAGE=$(NODE_EXPORTER_IMAGE)) \
		--secret id=dockerconfig,src="$(CONTAINER_AUTH_FILE)" \
		$(_ci_build_args) \
		image/rhel10

# kind+OVN-K e2e lane (test/e2e-kind/). Host-side, rootful.
.PHONY: e2e-kind
e2e-kind:
	test/e2e-kind/run.sh

# Nested CI child. Host-side. No registry auth. Layers storage.conf onto :ci.
NESTED_CI_TAG ?= localhost/evpn-appliance-rhel10:nested-ci

.PHONY: nested-ci-appliance-image
nested-ci-appliance-image: ci-appliance-image
	@test -n "$(CONTAINER_ENGINE)" || { echo "no podman/docker found" >&2; exit 1; }
	$(CONTAINER_ENGINE) build --pull=never \
		-f image/rhel10/Containerfile.nested-ci \
		--build-arg APPLIANCE_IMAGE=$(APPLIANCE_IMAGE) \
		-t "$(NESTED_CI_TAG)" \
		image/rhel10
