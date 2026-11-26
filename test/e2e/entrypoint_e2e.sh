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

# Run a collection playbook from the execution environment, the same artifact AAP runs.
# Launch it as a sibling on the host runtime through the mounted socket. run.sh mounts
# the work dir at the same path here and on the host so the EE can bind the staged files.
ee_playbook() {
	local pb="$1"
	echo ">> ansible-playbook ${pb} (via execution environment: $EGA_EE_IMAGE)"
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" run --rm --net=host --user 0 \
		-v "${lab_dir}:${lab_dir}:Z" \
		-e ANSIBLE_HOST_KEY_CHECKING=False \
		-w "${lab_dir}" \
		"$EGA_EE_IMAGE" \
		ansible-playbook -i "${lab_dir}/inventory/hosts.yml" \
			"$pb" \
			-u root --private-key "$ssh_key" 2>&1 | tee -a "${lab_dir}/ansible.log"
}

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
	# Topology selection belongs to the scenario, not the caller's environment.
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

	# containerlab writes clab-<name>/ next to its topology. Stage it out of the read-only
	# repo, with a distinct name and directory for each scenario (also for deploy/destroy).
	lab_dir="${EGA_WORK_DIR}/lab"
	mkdir -p "$lab_dir" "$EGA_ARTIFACT_DIR"
	cp "$src_topo" "$lab_dir/"
	topo="${lab_dir}/$(basename "$src_topo")"
	cd "$lab_dir"

	# Share teardown between explicit destroy and the per-scenario EXIT trap.
	cleanup() {
		if [ "$stage" = deploy ]; then
			echo ">> stage=deploy; leaving lab up for inspection: $topo" >&2
			return
		fi
		echo ">> containerlab destroy: $topo"
		containerlab destroy --name "$lab_name" -t "$topo" --cleanup
	}
	if [ "$stage" = destroy ]; then
		cleanup
		exit 0
	fi
	# Best-effort cleanup preserves the scenario's status, including partial-deploy failures.
	# The trap finishes before this subshell returns and the next scenario starts. On every
	# exit, including a failed task, a test pre-shared key (inventory/ipsec) in the playbook
	# output fails the scenario (CORENET-7500 AC2).
	: >"${lab_dir}/ansible.log"
	# shellcheck disable=SC2329 # invoked through the EXIT trap below
	on_exit() {
		local rc=$?
		if grep -q TEST_ONLY_EGA_IPSEC "${lab_dir}/ansible.log"; then
			echo "error: an IPsec pre-shared key appeared in the playbook output" >&2
			rc=1
		fi
		cleanup || true
		exit "$rc"
	}
	trap on_exit EXIT

	# ansible reaches nodes over SSH; bind an ephemeral public key into each node.
	ssh_key="${lab_dir}/ssh/id_ega"
	mkdir -p "${lab_dir}/ssh"
	[ -f "$ssh_key" ] || ssh-keygen -t ed25519 -N '' -C ega-e2e -f "$ssh_key" >/dev/null
	chmod 644 "${ssh_key}.pub"
	export EGA_SSH_PUBKEY="${ssh_key}.pub"

	echo ">> containerlab deploy: $topo"
	EGA_NODE_IMAGE="$EGA_NODE_IMAGE" containerlab deploy --name "$lab_name" -t "$topo" --reconfigure

	# sshd starts only after host-key generation; wait rather than racing the boot.
	export ANSIBLE_HOST_KEY_CHECKING=False
	inv="${lab_dir}/clab-${lab_name}/ansible-inventory.yml"
	echo ">> waiting for SSH on all nodes"
	ansible -i "$inv" all -u root --private-key "$ssh_key" \
		-m ansible.builtin.wait_for_connection -a 'timeout=120'

	# Remove the old copy first: cp -r into an existing inventory would nest it and
	# silently reuse stale files when the work dir persists across runs. -L copies the
	# files that a scenario inventory symlinks from another one.
	rm -rf "${lab_dir}/inventory"
	cp -rL "$inventory_src" "${lab_dir}/inventory"

	# Each scenario owns its ordered setup, deploy and validation playbooks.
	read -r -a playbooks <<< "$EGA_PLAYBOOKS"
	for playbook in "${playbooks[@]}"; do
		# deploy leaves the lab up for inspection, so it skips the product teardown and its checks.
		if [ "$stage" = deploy ] && [[ "$playbook" == *.teardown || "$playbook" == *.teardown_check ]]; then
			echo ">> stage=deploy; skipping ${playbook}"
			continue
		fi
		ee_playbook "$playbook"
	done
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
