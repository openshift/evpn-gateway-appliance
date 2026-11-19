# e2e lane

Proves the cloud infra role discovers upstream frr-k8s pods, the kind nodes
are the unmanaged VTEP for the production CUDN, and the relay reaches BGP
Established with each kind node. The appliance health check requires a remote
VTEP on that VNI.

`entrypoint_e2e.sh` is this lane. `test/e2e/run.sh` and `test/e2e/run_remote.sh`
default to it, and Prow sets the same entrypoint for `ci/prow/e2e`.
`test/e2e/run_simulate.sh` is the containerlab lane.

`EGA_STAGE=deploy` leaves the cluster and containerlab up. `EGA_STAGE=destroy`
tears both down. Any other exit destroys them.

`kind.yaml` is the cluster: kube-proxy off, the default CNI off, and
`service-lb-controller` disabled. `setup-cluster.sh` creates it with
`kindest/node:v1.36.1` and loads `OVN_K_IMAGE` into the nodes. The host
loads the openvswitch module, raises the inotify limits, and turns bridge
netfilter off before that chart install.

`run_remote.sh` takes the `ovn-kubernetes` image from `RELEASE_IMAGE_LATEST`
and loads it on the VM as `localhost/ovn-kubernetes:ci`. It also sparse-checks
out `helm/ovn-kubernetes` at v1.4.0, fetches the NetworkAttachmentDefinition
CRD from multus-cni v4.1.3, the MultiNetworkPolicy CRD at v1.0.1, the
IPAMClaim CRD at v0.5.1-alpha, and the frr-k8s manifest at `b43efcb206be`.
The lane reads the chart at `ovnk-helm` and those manifests under `manifests/`.
`setup-cluster.sh` applies the three CRDs and the FRRConfiguration CRD, then
the chart, which turns on multi-network, network segmentation, local gateway,
route advertisements, EVPN, and preconfigured UDN addresses. frr-k8s is applied once that network is up, so
advertisements have a speaker.

FRR in that manifest is `quay.io/frrouting/frr:10.4.3`. The controller image is
`quay.io/metallb/frr-k8s:main`. The lane then applies
`manifests/frrconfiguration.yml`.

Containerlab runs the appliance, the relay (`10.100.0.1`), and the transit
gateway. Kind nodes are the workload. The relay has a route to each node.
`prepare-evpn.sh` creates an unmanaged VTEP on the kind network, the
production CUDN, and the route advertisement that selects that
configuration. The CUDN reserves 10.42.1.1 for the appliance and uses
10.42.1.254 as the OVN gateway. deploy passes that kind network as
`workload_vpc_cidr`, so the appliance tunnel route covers the VTEPs.
ovn-kubernetes records each node's kind-network address in `k8s.ovn.org/vteps`.
The entrypoint calls
`network.evpn_gateway_test.simulate` so the appliance gets `trunk0`, then
`network.evpn_gateway.deploy`, which discovers the frr-k8s pods
(`-e frr_k8s_ns=frr-k8s-system`). Health checks run on the relay and the
appliance. The relay check fails unless each discovered node is BGP
Established.
