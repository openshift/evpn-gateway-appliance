# e2e lane

`entrypoint_e2e.sh` brings up the kind cluster and the containerlab fabric, runs
`deploy.yml`, then each directory under `test/e2e/scenarios/`. `EGA_SCENARIO`
selects one. `exclusive: true` in `scenario.yml` rebuilds the cluster before
the next scenario.

`test/e2e/kind/` is the cluster only. Each scenario directory supplies its
own manifests and checks.

`test/e2e/run.sh` and `test/e2e/run_remote.sh` default to `entrypoint_e2e.sh`,
and Prow sets the same entrypoint for `ci/prow/e2e`.
`test/e2e/run_simulate.sh` is the containerlab lane.

`EGA_STAGE=deploy` leaves the cluster and containerlab up. `EGA_STAGE=destroy`
tears both down. Any other exit destroys them.
