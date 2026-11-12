# Kind lane

Proves `deploy.yml` discovery against upstream frr-k8s, BGP Established and EVPN
prefixes on the relay, and L2 reachability from the appliance to a pod on the
primary EVPN network.

`make e2e-kind` (rootful podman, CI image and execution environment already built, or let
the Make target build the CI image) runs `run.sh`. `run_remote.sh` is the CI entry: it
ships and builds those images the same way as `test/e2e/run_remote.sh`, then runs `run.sh`.
`EGA_STAGE=deploy` leaves the cluster and containerlab up. `EGA_STAGE=destroy` tears both
down. Any other exit destroys them.

The cluster comes from `ovn-org/ovn-kubernetes` tag `v1.4.0` `contrib/kind.sh` with
multinetwork, network segmentation, and local gateway. Route advertisements and EVPN are
enabled with a later `helm upgrade`. `kind.sh`'s own route-advertisement flag also
installs a demo FRR and points frr-k8s at it, so this lane does not pass that flag.
frr-k8s is the all-in-one manifest at `b43efcb206be`, plus the kube-rbac-proxy image
rewrite. The relay stays the frr-k8s neighbor.

After that the lane applies a VTEP, a RouteAdvertisements, a primary Layer2 CUDN on
`10.42.1.0/24` with VNI 10100, and an agnhost pod in namespace `ega-evpn`.

Containerlab runs the appliance, the relay (`10.100.0.1`), and the transit gateway. Kind
nodes are the workload. The entrypoint calls `network.evpn_gateway_test.simulate` so the
appliance gets `trunk0`, then `network.evpn_gateway.deploy` with discovery left on
(`-e frr_k8s_ns=frr-k8s-system`) and `-e skip_health=true`. The script fails unless each
kind node is BGP Established, the relay has received EVPN prefixes from each node, and
the appliance can ping and HTTP the pod.
