#!/usr/bin/env bash
# In-container steps for the e2e lane. Runs INSIDE the pinned CI image (Dockerfile.ci),
# launched by run.sh with the host runtime socket mounted, so containerlab's node
# containers are siblings on the host runtime with the host kernel.
#
# EGA_SCENARIOS selects comma-separated names under scenarios/ (default: all *.env files).
# Each scenario gets its own lab, work directory and artifact directory.
# Stages (EGA_STAGE); deploy/destroy require one explicit EGA_SCENARIOS name:
#   full     deploy the fabric (containerlab + the collection's deploy.yml), validate, tear down.
#   deploy   same as full but leave the lab up for inspection.
#   destroy  tear down the lab left up by `deploy`.
set -euo pipefail

self_dir="$(cd "$(dirname "$0")" && pwd)"
stage="${EGA_STAGE:-full}"
: "${EGA_NODE_IMAGE:?}"
: "${EGA_RUNTIME_SOCK:?}"
: "${EGA_EE_IMAGE:?}"
EGA_WORK_DIR="${EGA_WORK_DIR:-/tmp/ega/work}"
EGA_ARTIFACT_DIR="${EGA_ARTIFACT_DIR:-/tmp/ega/artifact}"

case "$stage" in
	full | deploy | destroy) ;;
	*)
		echo "error: unknown EGA_STAGE: $stage" >&2
		exit 2
		;;
esac

# containerlab talks to the mounted host socket; podman is its runtime.
export DOCKER_HOST="unix://${EGA_RUNTIME_SOCK}"
export CONTAINERLAB_RUNTIME="podman"

# Shared EE playbook runner (ee_playbook/ee_runtime), exported so a scenario's
# checks.sh (a child process) can run collection playbooks with its own extra
# vars against the same lab.
# shellcheck source=/dev/null
source "${self_dir}/lib/ee-playbook.sh"

# A subshell keeps scenario defaults, exports, cwd and the EXIT trap from leaking into
# the next scenario. Enable errexit here even though the caller collects each exit status.
run_scenario() (
	set -e
	scenario="$1"
	scenario_file="${self_dir}/scenarios/${scenario}.env"
	if [ ! -f "$scenario_file" ]; then
		echo "error: unknown e2e scenario: $scenario (no $scenario_file)" >&2
		exit 2
	fi
	# Topology selection and any kubeconfig belong to the scenario, not the caller's environment.
	unset EGA_TOPOLOGY
	# Scenario definitions are repository-controlled.
	# shellcheck disable=SC1090
	source "$scenario_file"
	: "${EGA_TOPOLOGY:?scenario did not define EGA_TOPOLOGY}"
	: "${EGA_INVENTORY:?scenario did not define EGA_INVENTORY}"
	: "${EGA_PLAYBOOKS:?scenario did not define EGA_PLAYBOOKS}"
	export EGA_WORK_DIR="${EGA_WORK_DIR}/${scenario}"
	export EGA_ARTIFACT_DIR="${EGA_ARTIFACT_DIR}/${scenario}"

	src_topo="${self_dir}/topology/${EGA_TOPOLOGY}"
	inventory_src="${self_dir}/${EGA_INVENTORY}"
	lab_name="ega-${scenario}"
	# An ega-kind-br node means the topology attaches to the kind network, so
	# the cluster must exist before the clab deploy.
	needs_kind="$(yq '.topology.nodes.ega-kind-br != null' "$src_topo")"

	# containerlab writes clab-<name>/ next to its topology. Stage it out of the read-only
	# repo, with a distinct name and directory for each scenario (also for deploy/destroy).
	lab_dir="${EGA_WORK_DIR}/lab"
	mkdir -p "$lab_dir" "$EGA_ARTIFACT_DIR"
	cp "$src_topo" "$lab_dir/"
	topo="${lab_dir}/$(basename "$src_topo")"
	# Deploy honors --name, but destroy resolves the lab by the topology's
	# name field: the staged copy must carry the scenario's lab name or
	# destroy silently no-ops and leaks the lab into the next scenario.
	yq -i ".name = \"${lab_name}\"" "$topo"
	cd "$lab_dir"

	# Share teardown between explicit destroy and the per-scenario EXIT trap.
	cleanup() {
		if [ "$stage" = deploy ]; then
			echo ">> stage=deploy; leaving lab up for inspection: $topo" >&2
			return
		fi
		# Attempt both teardown steps regardless of the first one's outcome, and keep
		# any original failure: the EXIT trap runs this best-effort, while an explicit
		# destroy fails the lane on teardown errors.
		# cleanup_rc must not collide with the trap's rc (the scenario status).
		cleanup_rc=0
		echo ">> containerlab destroy: $topo"
		containerlab destroy --name "$lab_name" -t "$topo" --cleanup || cleanup_rc=$?
		if [ "${needs_kind:-}" = "true" ]; then
			"${self_dir}/kind/setup-cluster.sh" teardown "${EGA_WORK_DIR}" || cleanup_rc=$?
		fi
		return "$cleanup_rc"
	}
	if [ "$stage" = destroy ]; then
		cleanup
		exit 0
	fi
	# Cleanup preserves the scenario's status when it failed; a cleanup failure
	# after a successful scenario fails the scenario.
	trap 'rc=$?; cleanup || [ "$rc" -ne 0 ] || rc=1; exit "$rc"' EXIT

	# ansible reaches nodes over SSH; bind an ephemeral public key into each node.
	ssh_key="${lab_dir}/ssh/id_ega"
	mkdir -p "${lab_dir}/ssh"
	[ -f "$ssh_key" ] || ssh-keygen -t ed25519 -N '' -C ega-e2e -f "$ssh_key" >/dev/null
	chmod 644 "${ssh_key}.pub"
	export EGA_SSH_PUBKEY="${ssh_key}.pub"
	# checks.sh and the sourced ee_playbook consume these; a scenario may hand
	# its own stretch list to the collection playbooks through them.
	export EGA_LAB="$lab_name"
	export EGA_LAB_DIR="$lab_dir"
	export EGA_SSH_KEY="$ssh_key"

	if [ "$needs_kind" = "true" ]; then
		# Fully configured kind cluster; its kubeconfig feeds the peer discovery
		# and any scenario checks. ee_playbook forwards it into the EE.
		"${self_dir}/kind/setup-cluster.sh" setup "${EGA_WORK_DIR}"
		export KUBECONFIG="${EGA_WORK_DIR}/kubeconfig"
	fi

	echo ">> containerlab deploy: $topo"
	# The kind topology's bridge node installs forwarding rules in its post-deploy
	# stage; that cannot run on the nft-only RHEL 10 CI hosts (the rules need an
	# xt-compat match those kernels cannot resolve), and bridged traffic never
	# traverses them because setup-cluster.sh disables bridge netfilter. Skipping
	# post-deploy keeps the node exec: stanzas (clab 0.81.1 runs those regardless).
	skip_post=()
	if [ "$needs_kind" = "true" ]; then
		skip_post=(--skip-post-deploy)
	fi
	EGA_NODE_IMAGE="$EGA_NODE_IMAGE" containerlab deploy --name "$lab_name" -t "$topo" --reconfigure "${skip_post[@]}"

	# sshd starts only after host-key generation; wait rather than racing the boot.
	export ANSIBLE_HOST_KEY_CHECKING=False
	inv="${lab_dir}/clab-${lab_name}/ansible-inventory.yml"
	echo ">> waiting for SSH on all nodes"
	# The generated inventory also lists bridge nodes, which have no SSH daemon.
	ansible -i "$inv" linux -u root --private-key "$ssh_key" \
		-m ansible.builtin.wait_for_connection -a 'timeout=120'

	# Remove the old copy first: cp -r into an existing inventory would nest it and
	# silently reuse stale files when the work dir persists across runs.
	rm -rf "${lab_dir}/inventory"
	cp -r "$inventory_src" "${lab_dir}/inventory"

	# Each scenario owns its ordered setup, deploy and validation playbooks.
	read -r -a playbooks <<< "$EGA_PLAYBOOKS"
	for playbook in "${playbooks[@]}"; do
		ee_playbook "$playbook"
	done

	# A scenario may own deeper assertions than its playbooks: run its checks.sh
	# on the same lab. It applies its own manifests itself (it may have to retire
	# objects the kind bring-up left behind first) and may call the exported
	# ee_playbook with scenario-specific extra vars.
	if [ -x "${self_dir}/scenarios/${scenario}/checks.sh" ]; then
		"${self_dir}/scenarios/${scenario}/checks.sh"
	fi
	echo ">> scenario ${scenario} complete"
)

if [ -n "${EGA_SCENARIOS:-}" ]; then
	# Names become path components and lab names, so reject empty entries and paths.
	if [[ ! "$EGA_SCENARIOS" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*(,[a-zA-Z0-9][a-zA-Z0-9_-]*)*$ ]]; then
		echo "error: EGA_SCENARIOS must be comma-separated scenario names" >&2
		exit 2
	fi
	IFS=, read -r -a scenarios <<< "$EGA_SCENARIOS"
else
	shopt -s nullglob
	scenarios=()
	for scenario_file in "${self_dir}/scenarios/"*.env; do
		scenario="${scenario_file##*/}"
		scenarios+=("${scenario%.env}")
	done
fi
if [ "${#scenarios[@]}" -eq 0 ]; then
	echo "error: no e2e scenario definitions found" >&2
	exit 2
fi
if [[ "$stage" != full && ( -z "${EGA_SCENARIOS:-}" || "${#scenarios[@]}" -ne 1 ) ]]; then
	echo "error: EGA_STAGE=$stage requires exactly one explicit scenario in EGA_SCENARIOS" >&2
	exit 2
fi

rc=0
for scenario in "${scenarios[@]}"; do
	echo "========== e2e scenario: $scenario =========="
	# Do not use `if run_scenario` or `run_scenario || ...`: Bash disables errexit
	# throughout functions in those contexts, masking failed deploys and playbooks.
	set +e
	run_scenario "$scenario"
	scenario_rc=$?
	set -e
	if [ "$scenario_rc" -ne 0 ]; then
		echo "error: scenario $scenario failed (exit $scenario_rc)" >&2
		rc=1
	fi
done
exit "$rc"
