# Kind peers lane

Proves `deploy.yml` discovery against upstream frr-k8s and that the relay reaches BGP
Established with each kind node. No user-defined network, test pod, or ping. Those stay
for a later change on this same lane.

`make e2e-kind` (rootful podman, CI image and execution environment already built, or let
the Make target build the CI image) runs `run.sh`. `EGA_STAGE=deploy` leaves the cluster
and containerlab up. `EGA_STAGE=destroy` tears both down. Any other exit destroys them.

The cluster comes from `ovn-org/ovn-kubernetes` tag `v1.4.0` `contrib/kind.sh` (Helm
install, no `--evpn-enable` and no `--route-advertisements-enable`). frr-k8s is the
all-in-one manifest at `b43efcb206be`, the ref that tag uses, plus the kube-rbac-proxy
image rewrite. Only `manifests/frrconfiguration.yml` is applied after that.

Containerlab runs the appliance, the relay (`10.100.0.1`), and the transit gateway. Kind
nodes are the workload. The entrypoint calls `network.evpn_gateway_test.simulate` so the
appliance gets `trunk0`, then `network.evpn_gateway.deploy` with discovery left on
(`-e frr_k8s_ns=frr-k8s-system`). Health checks run on the relay and the appliance.
The relay check fails unless each discovered node is BGP Established. Discovered
nodes are not asked for EVPN prefixes.
