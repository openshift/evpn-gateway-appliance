# Verify the disconnected HA upgrade

[Rollout.qnt](Rollout.qnt) specifies the state transitions implicit in the
[upgrade playbook](../../ansible/playbooks/upgrade.yml). Quint is the source;
its TLC backend translates that same specification to TLA+ and explores it
exhaustively. There is no second handwritten model to keep in sync.

## Use when

Check a change to the order of fleet distribution, peer activation or rollback.
The model starts with two peers on distinct prior images. Both need the same
new candidate. It tracks the booted image, the next boot selection and the
rollback slot separately from the controller's observations.

| Model action | Corresponding playbook behavior |
| --- | --- |
| `preflight`, `distribute`, `verifyCopy` | All peers must pass preflight. A verified local OCI copy on a peer does not select it for boot. |
| `checkServing`, `stage` | Require a fresh health result from the other peer before changing the active peer's next boot. |
| `validateStage`, `rejectStage`, `cancelOwnedStage` | Only a validated stage can reboot. A failed stage may be cancelled if it still belongs to this turn; otherwise stop for inspection. |
| `bootCandidate`, `inspect` | Reboot the active peer and read the actual boot and rollback slots. An unexpected identity cannot advance. |
| `accept`, `reject` | Evaluate the final BGP and other fabric check results after retries. Only acceptance releases the next peer. |
| `queuePrior`, `bootPrior`, `confirmRecovery` | Recheck the rollback slot, select the saved image, reboot, verify both slots and check fabric health. Verified recovery ends the rollout as a failure. |
| `halt` | A failed command, unreachable host or failed assertion can stop the controller. This outcome makes no claim of recovery. |

The [distribution tasks](../../ansible/playbooks/tasks/upgrade_distribute.yml)
and [per-peer tasks](../../ansible/playbooks/tasks/upgrade_peer.yml) implement
these actions. Sets such as `passed` record what the controller has observed;
the separate `nodes` map records what is currently running.

## Don't use when

Use the [live HA scenarios](../../test/e2e/upgrade/README.md) to qualify an
image. This model does not execute Ansible, bootc, SSH or FRR. It abstracts
digest and source comparisons as image identities, copy completion as one
observation per peer, and retries as a final result. It covers one controller
run in local mode. Registry mode, already-current peers, restart and resume,
concurrent writers between a guard and its command, and continuous packet
delivery are outside the proof.

## How

1. Use Quint 0.32.0 with Java and its TLC backend (verified with Apalache
   0.56.1 and TLC 2.19). Run from this directory. The compiler uses a local
   socket; preinstall the toolchain before running at a disconnected site.
2. Check the full fault model:

   ```console
   quint typecheck Rollout.qnt
   quint verify Rollout.qnt --backend=tlc --invariant=safety --temporal=finishes
   ```

   To inspect the generated TLA+ module, run
   `quint compile Rollout.qnt --target=tlaplus --invariant=safety --temporal=finishes`.

   TLC explored **363 distinct states**, to depth 22, with none left on the
   queue. No peer stages before both copies and both preflight results exist.
   B cannot stage before A passes post-boot validation. Rejecting A leaves B
   unstaged. A rollback cannot queue a different image or report recovery
   without the saved image running and both health results passing. Under
   weak fairness, the controller eventually finishes, possibly by stopping.
   Weak fairness means a continuously enabled controller step eventually runs.
3. Check recovery under functioning management and a healthy prior image:

   ```console
   quint verify Rollout.qnt --backend=tlc --step=operationalRecoveryStep --invariant=safety --temporal=restores
   ```

   TLC explored **191 distinct states**. Once rescue begins, if the rollback
   slot remains intact, commands complete, the selected prior image boots and
   its health checks pass, every fair execution reaches verified recovery.
   This check uses the same rollback guards as the fault model.
4. Confirm the success and rollback paths are reachable. Each of these
   *should* exit with a counterexample: the final state is the requested witness.

   ```console
   quint verify Rollout.qnt --backend=tlc --invariant='not(success)'
   quint verify Rollout.qnt --backend=tlc --invariant='not(recoveredA)'
   quint verify Rollout.qnt --backend=tlc --invariant='not(recoveredB)'
   ```

## Example

The playbook checks A again before B stages. If A already lost BGP, B cannot
start. The check cannot guarantee that A stays healthy after it passes. Run:

```console
quint verify Rollout.qnt --backend=tlc --invariant=stillHealthyAtHandoff
```

TLC finds a 15-state counterexample. A passes post-boot validation, passes
the fresh serving check, then loses BGP before B stages.

## Edge cases

- A rollback slot change observed before queueing rollback blocks recovery.
  An unexpected running image or failed health check after the recovery reboot
  cannot be reported as verified recovery.
- If B rejects the candidate after A succeeded, B may roll back while A stays
  on the new image. The playbook does not undo successful upgrades fleet-wide.
- Cancellation models a supported pending-deployment removal as one step.
  Failure to inspect, remove or verify the deployment can stop the rollout.
  The model does not establish support for a particular bootc backend.
