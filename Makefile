# Entry point + container delegation. By default the requested target(s) run inside the
# pinned CI image (Dockerfile.ci) for parity with CI; the real targets live in rules.mk.
#
#   make <target>              run <target> inside the CI image (built first)
#   make <target> USE_IMAGE=0  run on the host with local tools instead
#   make image                 just build the CI image
#
# OFFLINE is forwarded into the container; TERMS (a file kept outside the repo) is
# bind-mounted read-only and its in-container path passed through.

USE_IMAGE ?= 1
IMAGE ?= evpn-gateway-appliance-ci:local
CONTAINER_ENGINE ?= $(shell command -v podman 2>/dev/null || command -v docker 2>/dev/null)
comma := ,

# One container run. $(1) = goals to run inside (empty -> the image's default goal).
CONTAINER_RUN = $(CONTAINER_ENGINE) run --rm \
	$(if $(TERMS),-v $(abspath $(TERMS)):/terms:ro$(comma)Z,) \
	$(IMAGE) make $(1) OFFLINE=$(OFFLINE) $(if $(TERMS),TERMS=/terms,)

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
container-default: image
	$(call CONTAINER_RUN,)
else
# Forward the named goals into a single container run: the first builds the image and
# runs them, the rest are no-ops. `image` is never forwarded (it builds on the host).
FWD := $(filter-out image,$(MAKECMDGOALS))
ifneq ($(FWD),)
.PHONY: $(FWD)
$(firstword $(FWD)): image
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
.PHONY: image
image:
	@test -n "$(CONTAINER_ENGINE)" || { echo "no podman/docker found; use USE_IMAGE=0 to run on the host" >&2; exit 1; }
	$(CONTAINER_ENGINE) build -f Dockerfile.ci -t $(IMAGE) .
