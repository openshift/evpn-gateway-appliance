# Kind scenario assets

The `kind` e2e scenario proves the production path for real: the cloud infra
role discovers frr-k8s pods from a Kubernetes API and the relay reaches BGP
Established with every kind node. The kind nodes are the unmanaged VTEP for
the production CUDN.

Select it with `EGA_SCENARIOS=kind` (or let the default discovery run it
alongside `emulated`). `scenarios/kind.env` defines its topology
(`topology/kind.clab.yml`), inventory (`inventory/kind/`) and playbook
sequence. `EGA_STAGE=deploy` leaves the cluster and containerlab up;
`EGA_STAGE=destroy` tears both down. Any other exit destroys them.

The `l2-pod` scenario (`scenarios/l2-pod.env`) reuses this same topology,
inventory and kind cluster setup, and adds
`network.evpn_gateway_test.l2_pod` after the deploy: a pod on the primary
CUDN that the appliance must reach on its stretched address.

`entrypoint_e2e.sh` detects the kind network's `ega-kind-br` node in the
scenario topology and, before the containerlab deploy, calls
`setup-cluster.sh setup <work_dir>` here; the scenario cleanup calls its
`teardown`. The kubeconfig lands in the scenario's work dir and is passed to
the execution environment so the peer discovery can read the API.

`kind.yaml` is the cluster: kube-proxy off, the default CNI off, and
`service-lb-controller` disabled. `setup-cluster.sh` creates it as `ega-kind`
with `kindest/node:v1.36.1` on `10.89.0.0/24`, with node addresses drawn from
`10.89.0.128/25` so they stay clear of the transit gateway at `10.89.0.2`.
The chart, CRDs, and frr-k8s manifest are baked in the CI image under
`/opt/ega/e2e`. The chart pulls
`ghcr.io/ovn-kubernetes/ovn-kubernetes/ovn-kube-ubuntu:master`. The host
loads the openvswitch module, raises the inotify limits, and turns bridge
netfilter off before that chart install.

FRR in the frr-k8s manifest is `quay.io/frrouting/frr:10.4.3`. The controller
image is `quay.io/metallb/frr-k8s:main`. `setup-cluster.sh` applies
`manifests/frrconfiguration.yml` after the speakers are up, then the VTEP,
the production CUDN, and the route advertisement.

Containerlab runs the appliance, the relay (`10.100.0.1`), and the transit
gateway. The transit gateway's eth1 is attached to the `ega-kind-br` bridge.
The relay routes `10.89.0.0/24` at the gateway. `group_vars` sets
`workload_vpc_cidr` to that prefix. The deploy skips the nodes' post-deploy
stage (see the topology header). The scenario's playbooks run
`network.evpn_gateway_test.simulate` so the appliance gets `trunk0`, then
`network.evpn_gateway.deploy`, which discovers the frr-k8s pods in
`frr-k8s-system` (`frr_kubernetes_namespace` in the kind group_vars).
