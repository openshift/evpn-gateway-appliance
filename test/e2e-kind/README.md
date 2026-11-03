# kind+OVN-K EVPN e2e lane (CORENET-7695)

Validates the collection's production discovery path against a kind cluster
running OVN-K with EVPN. Separate from the containerlab lane (`test/e2e/`).

## What it validates

1. `deploy.yml` discovery populates `cloud_workload` from frr-k8s pods.
2. Workload ASN read from `FRRConfiguration` CR.
3. Relay BGP EVPN sessions with kind nodes (Established, Type-2/3).
4. L2 reachability: agnhost pod on CUDN reachable from on-prem side.

## Layout

```text
test/e2e-kind/
  run.sh              runner-agnostic entry point
  entrypoint.sh       kind + clab + bridge + deploy + verify
  setup-cluster.sh    kind create + OVN-K + CR setup
  topology/           3-node clab (appliance, relay, TGW)
  inventory/          no cloud_workload (discovery fills it)
  manifests/          VTEP, CUDN, FRRConfiguration, RouteAdvertisements, test pod
```

## Usage

```bash
sudo make ci-image ee-image
sudo make nested-ci-appliance-image CONTAINER_AUTH_FILE="$HOME/.docker/config.json"
git clone --depth 1 https://github.com/ovn-kubernetes/ovn-kubernetes.git /tmp/ovn-k
sudo OVN_K_DEPLOY_SCRIPT=/tmp/ovn-k/contrib/kind.sh test/e2e-kind/run.sh
```

## Contract

Same env as `test/e2e/run.sh`, plus: `EGA_KIND_CLUSTER`, `OVN_K_IMAGE`,
`OVN_K_DEPLOY_SCRIPT`.
