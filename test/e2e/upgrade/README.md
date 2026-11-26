# Bootc upgrade scenarios

Verify the collection's serial upgrade and automatic rollback on two real bootc appliances.

## Use when

Two disposable peers already pass `ansible/playbooks/health-check.yml`. Both must start on
bootc image digests distinct from the two candidate digests and have no pending deployment.
They need persistent journals under `/var/log/journal` across reboots.
The controller needs Go, the collection's Ansible dependencies, and inventory credentials for
noninteractive SSH and privilege escalation.

## Don't use when

The peers carry live traffic. The playbook reboots both appliances and deliberately breaks FRR
on the first peer. Container-based scenarios cannot exercise this workflow.

## How

1. Use a lab inventory with exactly two hosts in `evpn_upgrade_peers`. Keep their normal
   topology groups and variables. The playbook visits hosts in ascending inventory name order.
2. Choose a known healthy candidate built for the peers' architecture. It must ship the
   `frr-container.service` unit. Prepare single-platform OCI layouts and their expected
   manifest digests on the controller. Neither peer needs registry access.
3. Build and export the unhealthy candidate with the fixture below. It leaves SSH available
   and adds an FRR service drop-in under `/usr/lib` so bootc can remove it during rollback.
4. Run the scenarios from the repository root. The runner calls `playbooks/upgrade.yml`
   first with the healthy candidate, then with the unhealthy candidate. It separately runs
   `playbooks/health-check.yml` on both peers after each scenario. Keep its output as evidence;
   a passing run finishes with both peers on the healthy candidate.

## Example

On a preparation host, set `GOOD_IMAGE` to the healthy image's approved platform reference
by digest. Set `GOOD_OCI` and `BAD_OCI` to separate, empty directories. Run from the repository root:

```bash
skopeo copy --preserve-digests "docker://$GOOD_IMAGE" "oci:$GOOD_OCI"
podman build --build-arg GOOD_IMAGE="$GOOD_IMAGE" --tag localhost/evpn-e2e-bad:local test/e2e/upgrade
skopeo copy containers-storage:localhost/evpn-e2e-bad:local "oci:$BAD_OCI"
skopeo inspect --format '{{.Digest}}' "oci:$BAD_OCI"
```

Set `BAD_IMAGE` to `localhost/evpn-e2e-bad@` followed by the printed digest. Transfer
both OCI directories to the disconnected controller. Set `GOOD_OCI` and `BAD_OCI` to their
absolute paths on that controller. Set `LAB_INVENTORY` to the lab inventory path.

```bash
go run ./test/e2e/upgrade/main.go -inventory "$LAB_INVENTORY" \
  -good "$GOOD_IMAGE" -good-oci "$GOOD_OCI" -bad "$BAD_IMAGE" -bad-oci "$BAD_OCI"
```

## Edge cases

The healthy scenario checks the local OCI source, running digest and one fresh boot per peer.
Ansible's task events must show both peers verified their copies before the first image switch.
They must show separate post-reboot and handoff BGP checks on the first peer
before the second peer starts staging its image. The rollback scenario
requires the playbook to fail after verifying recovery. It checks two fresh boots on the first
peer, the test image's FRR marker in the intervening boot, the restored running digest, the
failed candidate in the rollback slot, and the unchanged boot ID and digests on the second
peer. A registry error or an unreachable candidate cannot satisfy these checks.

If journal retention drops one of the boots, the runner fails for lack of
evidence. Reset the peers to their starting images before rerunning both scenarios.
