#!/usr/bin/env bash
# Shared execution-environment playbook runner (CORENET-7513).
#
# Sourced by entrypoint_e2e.sh; both functions are exported so a scenario's
# checks.sh (a child process) can run collection playbooks with its own extra
# vars — e.g. a scenario-specific stretch list — against the same lab.
#
# The EE is the same artifact AAP runs: it carries the collection and its
# derived deps (wireguard-tools for the control-node key generation, netaddr
# for ansible.utils' ipaddr filters, boto3), so nothing is built, installed or
# pre-seeded here. The toolchain ships podman-remote (not a local podman): the
# EE is launched as a sibling on the host runtime through the same mounted
# socket containerlab uses. It joins the host network to reach the nodes on
# the clab management network, and runs as root to read the (root-owned) key
# and inventory and write ansible's temp dirs.
#
# Required environment:
#   EGA_RUNTIME_SOCK  host podman socket
#   EGA_EE_IMAGE      execution-environment image (the artifact AAP runs)
#   EGA_LAB_DIR       lab work dir (bind-mounted; holds inventory/ and the key)
#   EGA_WORK_DIR       scenario work dir (bind-mounted; holds the kind kubeconfig)
#   EGA_SSH_KEY       SSH private key for the lab nodes
#   KUBECONFIG        optional; forwarded into the EE when it exists
ee_runtime() {
	podman-remote --url "unix://${EGA_RUNTIME_SOCK}" "$@"
}

ee_playbook() {
	local pb="$1"
	shift
	local kube_env=()
	if [ -n "${KUBECONFIG:-}" ] && [ -f "$KUBECONFIG" ]; then
		kube_env=(-e "KUBECONFIG=${KUBECONFIG}")
	fi
	echo ">> ansible-playbook ${pb} (via execution environment: $EGA_EE_IMAGE)"
	ee_runtime run --rm --net=host --user 0 \
		-v "${EGA_LAB_DIR}:${EGA_LAB_DIR}:Z" \
		-v "${EGA_WORK_DIR}:${EGA_WORK_DIR}:Z" \
		-e ANSIBLE_HOST_KEY_CHECKING=False \
		"${kube_env[@]}" \
		-w "${EGA_LAB_DIR}" \
		"$EGA_EE_IMAGE" \
		ansible-playbook -i "${EGA_LAB_DIR}/inventory/hosts.yml" \
			"$pb" \
			"$@" \
			-u root --private-key "$EGA_SSH_KEY"
}

export -f ee_runtime ee_playbook
