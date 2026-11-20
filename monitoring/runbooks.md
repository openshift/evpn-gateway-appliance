# EGA alert runbooks

[README.md](README.md) says what each alert reads and when it stays silent. For Prometheus
alerts, `job` and `instance` say which host it is about; AWS alerts name the resource in their
dimension labels, in the rule's region.

Where to run the commands:

- **FRR (`vtysh`)**: on an appliance, `vtysh -c '...'` as root where FRR runs as `frr.service`,
  or `podman exec frr vtysh -c '...'` where it runs in the `frr` container.
- **The `frr-metrics` exporter**: the FRR alerts read its series. On an appliance it runs as
  `frr-metrics.service` once it replaces the legacy exporter (see the
  [metrics plan](../plans/context/evpn-aws/frr-metrics-plan.md)); read its log with
  `journalctl -u frr-metrics.service`.
- **AWS**: the `aws` CLI with `--region` set to the alert rule's region. An AWS alert clears at
  the first evaluation after a whole healthy 5-minute period, about 5 to 15 minutes after
  recovery plus CloudWatch's publishing delay.

The critical alerts do not tell planned work from failure. Before planned work that restarts
FRR or WireGuard, such as a reboot or bootc upgrade, add an expiring Alertmanager silence for
the affected `job` and `instance` (or `peer` and `vrf`) here and on each neighbor that monitors
the session, and afterwards check that the sessions are back. Reconnecting sends BGP OPENs, so
EGABgpPeerFlapping can fire after the work: keep the silence for 15m after it, or include that alert.

## EGAFrrCollectorFailed

The exporter could not read or parse the `collector` label's FRR data for 2m, so that
collector's series are missing and its alerts, such as EGABgpSessionDown for `bgp`, cannot fire;
BFD session states stay current when only its counter read fails.

- On an appliance, check the router: `systemctl status frr.service` where FRR runs natively, or
  `systemctl status frr-container.service` and `podman logs --tail 50 frr` where it runs in a
  container.
- Run the commands the collector runs, and check that each answers with valid JSON:
  - `bgp`: `show bgp vrfs json`, then `show bgp vrf VRF neighbors json` for each VRF;
  - `bfd`: `show bgp vrfs json` to list VRFs, then `show bfd vrf VRF peers json` and
    `show bfd vrf VRF peers counters json`;
  - `evpn`: `show evpn vni json`.
- Which collectors fail points at the daemon: `bgp` and `bfd` together at bgpd (both list VRFs
  from it), `evpn` alone at zebra, `bfd` alone at bfdd, all three at `vtysh` itself.
- Read the exporter's log for the read or parse error.

If `vtysh` hangs or fails, restart the router: `systemctl restart frr.service` where FRR runs
natively, `systemctl restart frr-container.service` on a bootc image with the FRR container, or
`podman restart frr` elsewhere. That drops every BGP session on the host, and with
it every stretch's EVPN routes, until they re-establish. A parse error that persists while FRR
answers means the exporter does not match this FRR version; report it with the command output.
After a hang clears, collectors can take 2 to 3 minutes to recover (zebra is the slowest), so
wait for that before restarting FRR again.

## EGAFrrMetricsDown

Prometheus could not scrape an FRR metrics target that reported in the last day, for 2m, so
none of that host's FRR alerts can fire. Prometheus's Targets page shows the scrape error. After a day
without a successful scrape the alert clears even though nothing recovered. Turning
`frr-metrics` off or tearing an appliance down also fires it: remove the target or silence it first.

- Check that the appliance is up and reachable from Prometheus.
- On the appliance: `systemctl status frr-metrics.service` and
  `journalctl -u frr-metrics.service -n 50`; read it locally with
  `curl -ksS --max-time 10 https://127.0.0.1:7573/metrics`.
- A scrape slower than `scrape_timeout` also fails: compare `scrape_duration_seconds` with it.
  Scrape time grows by about 20ms per VRF (about 4s at 200 VRFs), so size `scrape_timeout` for
  hosts with hundreds of VRFs.
  If the local `curl` times out while `frr-metrics.service` is active, an FRR daemon or `vtysh`
  is usually hung, and restarting `frr-metrics` does not help. A hang stalls every collector, so
  find the daemon with `timeout 5 vtysh -d DAEMON -c 'show version'` for `zebra`, `bgpd` and
  `bfdd`, then restart the router as for EGAFrrCollectorFailed.

## EGAFrrMetricsGatherErrors

The exporter served scrapes with some metrics dropped, so series can be missing while
collector success stays 1. It clears once no scrape has dropped a metric for about 10m.

- Read the exporter's log; it names the failing metric on each scrape.
- Duplicate BFD series are the known cause: two BFD sessions with the same peer and VRF, for
  example a single-hop and a multihop session. Compare `show bfd vrf VRF peers json`.

Remove a session only if it is unintended; otherwise report the exporter's peer/VRF collision
and check the sessions in FRR by their local address and interface. Other series stay valid.

## EGABgpSessionDown

A BGP peer has not been Established for 1m. On the appliance the relay peer runs over the
WireGuard tunnel; losing it withdraws every stretch's EVPN routes. The alert clears once the
session is back, or 4m after its series stops, when EGAFrrCollectorFailed or EGAFrrMetricsDown
takes over.

- `show bgp vrf VRF summary` and `show bgp vrf VRF neighbors PEER` for the state and the
  last error (the alert's `vrf` label; `default` on the appliance).
- Administrative shutdown also reads 0: look for `neighbor PEER shutdown` in
  `show running-config`.
- A last error naming the maximum-prefix limit (`bgp.max_prefix`, default 1000) means the peer
  sent too many EVPN routes. EGA sets no restart timer, so the session stays down: fix the
  advertisements or raise the limit, then `clear bgp vrf VRF PEER`.
- For the appliance's relay peer, `wg show wg0`: a `latest handshake` older than about 3
  minutes means the tunnel is down. Check the underlay route and UDP reachability to the
  WireGuard endpoint, then `ping` the peer address over the tunnel.

Otherwise fix the tunnel or underlay; BGP re-establishes on its own once the peer is reachable.

## EGABgpEvpnNoPrefixesAccepted

An Established peer has accepted zero l2vpn/evpn prefixes for 5m. Without EVPN routes the
host learns no remote MACs or VTEPs from that peer.

- On the host that alerts: `show bgp l2vpn evpn summary` and
  `show bgp l2vpn evpn neighbors PEER routes` for what it accepted. `NoNeg` in the summary means
  the peer did not negotiate l2vpn/evpn: check its configuration for the family.
- On the peer: `show bgp l2vpn evpn neighbors HOST_IP advertised-routes`, where `HOST_IP` is
  the alerting host's address on that session, for what it sends. In the reference topology the
  appliance's peer is the infra relay, which has no VNIs of its own and passes on the remote
  VTEPs' routes: if it sends nothing, check `show bgp l2vpn evpn summary` on the relay for its
  sessions toward the VTEPs.
- On the cluster, where OpenShift nodes are the remote VTEPs: the
  `ovnkube_clustermanager_cluster_user_defined_network_condition`,
  `ovnkube_clustermanager_route_advertisement_condition` and
  `ovnkube_clustermanager_vtep_condition` series (see the [README](README.md#frr-and-evpn)) for a
  network, route advertisement or VTEP that is not ready, then the cluster's frr-k8s. In the
  emulated lab, the cloud workload's VNIs and `advertise-all-vni` instead.
- The appliance applies no inbound route policy; its `maximum-prefix` limit tears the session
  down rather than leaving it Established with zero routes.

Zero can be intentional on a peer that carries no EVPN; silence the alert for that peer.

## EGABgpEvpnNoPrefixesAnnounced

An Established peer has been sent zero l2vpn/evpn prefixes for 5m, so it learns none of this
host's VNIs or MACs.

- `show bgp l2vpn evpn neighbors PEER advertised-routes` and `show bgp l2vpn evpn route` for
  the type-2 and type-3 routes this host should send.
- `show evpn vni` for the local VNIs: with none, there is nothing to announce. Check that each
  stretch's `vxlanN` and `br-vniN` devices exist and are up (`ip -d link show`); if not, rerun
  `deploy.yml`.
- Check outbound policy toward the peer (`show running-config`, route maps on the neighbor).

## EGABgpPeerFlapping

3 or more BGP OPENs were sent to a peer in 10m, so the session keeps resetting. It clears once
no OPEN has been sent for about 10m (the rule's window), so it outlasts the fix.

- `show bgp vrf VRF neighbors PEER` for the last reset reason and error.
- For the appliance's relay peer, `wg show wg0` and the underlay path, as for
  EGABgpSessionDown.
- A maximum-prefix shutdown with a restart timer, mismatched timers, MTU problems or packet loss
  on the path can each cause repeated resets; with BFD, loss resets the session through BFD and
  EGABfdPeerFlapping fires too.
- A session that never establishes also sends OPENs on every retry: if EGABgpSessionDown fires
  too and the reset reason is a NOTIFICATION such as a bad peer AS or hold time, fix the peer's
  configuration as for EGABgpSessionDown.

## EGAEvpnVniNoRemoteVteps

An L2 VNI has had no known remote VTEP for 15m, so the stretch has no destination for BUM
traffic and learns no remote MACs.

- `show evpn vni VNI` for the VNI's state and remote VTEPs.
- `show bgp l2vpn evpn route vni VNI type multicast`: each remote VTEP of the VNI needs an
  imported type-3 route to receive BUM traffic; a type-2 MAC/IP route alone adds the VTEP
  without flooding to it. If `show bgp l2vpn evpn route type multicast` has the route but the
  VNI does not, compare the route's route targets with the VNI's imports in
  `show bgp l2vpn evpn vni VNI`; the appliance imports `ONPREM_ASN:VNI` and
  `WORKLOAD_ASN:VNI`.
- On the cluster, the OVN-Kubernetes condition series as for EGABgpEvpnNoPrefixesAccepted: a
  VTEP or network that is not ready advertises no type-3 route. In the emulated lab, check that
  the cloud workload's VXLAN device and bridge for the VNI exist and are up.

A known VTEP does not prove that VXLAN traffic reaches it.

## EGABfdSessionDown

A BFD session has been down for 30s, which can take down the BGP session that uses it. The
appliance's FRR configuration has no BFD peers yet, so on appliances this alert stays quiet.

- `show bfd vrf VRF peers` for the state and diagnostic, and `show bfd vrf VRF peers counters`
  for packet counters.
- Administrative shutdown also reads down: look for `shutdown` under the peer in
  `show running-config`.
- Check loss on the path to the peer from the node: `ping -c 100 PEER`, or
  `ping -c 100 -I VRF PEER` for a non-default VRF.
- If BGP stays up while BFD is down, compare the BFD timers and profile on both ends.

Peer and VRF can be the same for distinct sessions; confirm which session from the output.

## EGABfdPeerFlapping

3 or more BFD down events for a peer in 10m, so the session keeps failing and recovering. It
clears once there has been no down event for about 10m (the rule's window).

- `show bfd vrf VRF peers counters` for the down events and packet counts.
- Check loss and jitter on the path to the peer, as for EGABfdSessionDown, and compare the BFD
  timers on both ends; intervals too short for the path cause repeated drops.

## EGADxConnectionDown

AWS reports a Direct Connect connection down. Traffic over it fails over to another
connection or a VPN only if one is configured.

- `aws directconnect describe-connections --region REGION --connection-id ID` for
  `connectionState`.
- Check the physical link with the colocation or partner: optics, cross-connect and the
  customer router port.

Open a case with the Direct Connect partner or AWS if the port is up on the customer side.

## EGADxVirtualInterfaceBgpDown

AWS reports BGP down on a Direct Connect virtual interface while the connection can be up.

- `aws directconnect describe-virtual-interfaces --region REGION --virtual-interface-id ID` for
  `bgpPeers[].bgpStatus` and the expected peer addresses, ASN and VLAN.
- On the customer router, check the BGP session, MD5 key, ASN and the VLAN subinterface.

If the customer side matches, open a case with the Direct Connect partner or AWS.

## EGAVpnTunnelDown

At least one tunnel of a Site-to-Site VPN is down. A VPN built with one tunnel keeps this
alert firing; README.md says how to alert only when every tunnel is down.

- `aws ec2 describe-vpn-connections --region REGION --vpn-connection-ids ID` and read
  `VgwTelemetry[].Status` and `StatusMessage` for each tunnel.
- On the customer gateway, check IKE and IPsec state, pre-shared keys and that UDP 500 and
  4500 reach the tunnel's outside address.

Restore the tunnel on the customer gateway.
