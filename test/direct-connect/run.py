#!/usr/bin/env python3
"""Fake-AWS-CLI tests for the Direct Connect tasks and preflight: run.py plays play.yml (render.yml for the
templates) per case, and the `aws` symlink it creates runs this file as the fake (API-shaped state, --query via
jmespath, writes only in lifecycle and render cases). Bad inputs and states must fail with their check's message,
and no case may print a VIF BGP key.
"""

import copy
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

KEY = "TEST-ONLY-bgp-md5-key"
DXGW = "5f0e6c1e-1b1a-4c2a-9a55-0123456789ab"
HERE = os.path.dirname(os.path.abspath(__file__))
ANSIBLE = os.path.join(HERE, "..", "..", "ansible")


def fake_host(name, argv):
    """The appliance's `ip` and `cat`: only the reads the preflight and deploy make, answered from the case's state.
    Protocols are stored as numbers; like iproute2, ip names the stock ones unless -N is given."""
    with open(os.environ["DX_STUB_STATE"]) as f:
        st = json.load(f)["host"]
    if name == "cat":
        if not argv[0].startswith("/sys/class/net/"):
            os.execv("/bin/cat", ["cat", *argv])
        dev = argv[0].split("/")[4]
        if dev not in st["mtu"]:
            sys.exit("cat: %s: No such file or directory" % argv[0])
        print(st["mtu"][dev])
        return 0
    numeric = argv[0] == "-N"
    args = argv[1:] if numeric else argv
    if args[:2] == ["-j", "route"] and not numeric and args[-1] != st["addr"]:
        sys.exit("fake ip: no state for %s" % argv)
    if args[:4] == ["-j", "route", "show", "match"] and not numeric:
        routes = st["match"]
    elif args[:3] == ["-j", "route", "get"] and not numeric:
        if not st["get"]:
            sys.exit("RTNETLINK answers: Network is unreachable")
        routes = [st["get"]]
    elif args[:4] == ["-j", "route", "show", "root"] and numeric:
        routes = st["root"].get(args[4], [])
    else:
        sys.exit("fake ip: refusing %s" % argv)
    names = {} if numeric else {"2": "kernel", "4": "static", "186": "bgp"}
    print(json.dumps([dict(r, protocol=names.get(r["protocol"], r["protocol"])) if "protocol" in r else r
                      for r in routes]))
    return 0


def fake_aws(argv):
    with open(os.environ["DX_STUB_LOG"], "a") as log:
        log.write(json.dumps(argv) + "\n")
    import jmespath

    opts = {argv[i]: argv[i + 1] for i in range(2, len(argv) - 1) if argv[i].startswith("--")}
    with open(os.environ["DX_STUB_STATE"]) as f:
        st = json.load(f)
    gw = opts.get("--direct-connect-gateway-id")
    cmd = argv[1]

    def fail(code, message):
        """Exit as the CLI does on an AWS error, keeping the state."""
        with open(os.environ["DX_STUB_STATE"], "w") as f:
            json.dump(st, f)
        print("\nAn error occurred (%s) when calling the %s operation: %s" % (
            code, "".join(w.title() for w in cmd.split("-")), message), file=sys.stderr)
        sys.exit(254)

    # errors[cmd] lists what its next calls fail with (None: the call succeeds).
    errors = st.get("errors", {}).get(cmd)
    if errors and errors[0] is None:
        errors.pop(0)
    elif errors:
        fail(*errors.pop(0))
    # hold[name] > 0 delays an AWS change by that many reads of it.
    hold = st.setdefault("hold", {})

    def held(name):
        if hold.get(name, 0) > 0:
            hold[name] -= 1
            return True
        return False

    if cmd in ("describe-direct-connect-gateway-associations", "describe-transit-gateway-attachments") \
            and not held("pending"):
        # each describe moves pending ones on
        for a in st["assocs"]:
            if a["associationState"] == "associating" and st.get("reject"):
                a.update(associationState="disassociated", stateChangeError="TEST rejected")
            a["associationState"] = {"associating": "associated", "disassociating": "disassociated"}.get(
                a["associationState"], a["associationState"])
    live = [a for a in st["assocs"] if a["associationState"] != "disassociated"]
    if cmd.startswith(("create-", "delete-")) and not os.environ.get("DX_STUB_WRITE"):
        sys.exit("fake aws: refusing %s %s in a read-only case" % (argv[0], cmd))
    if cmd == "describe-direct-connect-gateways":
        out = {"directConnectGateways": [g for g in st["dxgws"] if g["directConnectGatewayId"] == gw]}
    elif cmd == "describe-direct-connect-gateway-attachments":
        out = {"directConnectGatewayAttachments": [
            {"virtualInterfaceId": v["virtualInterfaceId"], "virtualInterfaceRegion": v["region"],
             "attachmentType": "TransitVirtualInterface" if v["virtualInterfaceType"] == "transit"
             else "PrivateVirtualInterface", "attachmentState": v.get("attachmentState", "attached")}
            for v in st["vifs"] if v["directConnectGatewayId"] == gw]}
    elif cmd == "describe-virtual-interfaces":
        # A VIF is visible only in its own Region, and only to its owner.
        out = {"virtualInterfaces": [v for v in st["vifs"] if v["region"] == opts["--region"] and not v.get("foreign")
                                     and v["virtualInterfaceId"] == opts["--virtual-interface-id"]]}
    elif cmd == "describe-direct-connect-gateway-associations" and "--association-id" in opts and held("assoc_read"):
        out = {"directConnectGatewayAssociations": []}  # not yet readable after the create
    elif cmd == "describe-direct-connect-gateway-associations":
        out = {"directConnectGatewayAssociations": [
            a for a in st["assocs"] if a["directConnectGatewayId"] == gw
            and opts.get("--association-id") in (None, a.get("associationId"))
            and opts.get("--associated-gateway-id") in (None, a["associatedGateway"]["id"])]}
    elif cmd == "create-direct-connect-gateway-association":
        a = assoc([c.split("=", 1)[1] for c in argv[argv.index("--add-allowed-prefixes-to-direct-connect-gateway") + 1:]
                   if c.startswith("cidr=")], state="associating", gw=opts["--gateway-id"])
        a["associationId"] = "assoc-%d" % len(st["assocs"])
        st["assocs"].append(a)
        out = {"directConnectGatewayAssociation": a}
    elif cmd == "delete-direct-connect-gateway-association":
        a = next((a for a in live if a.get("associationId") == opts["--association-id"]), None)
        if a and st.pop("vanish", False):  # deleted by someone else since teardown found it
            a["associationState"], a = "disassociated", None
        if not a:
            fail("DirectConnectClientException", "Association ID %s does not exist" % opts["--association-id"])
        # AWS refuses to delete an association still being created; it is associated by the next call.
        if a["associationState"] != "associated":
            a["associationState"] = "associated"
            with open(os.environ["DX_STUB_STATE"], "w") as f:
                json.dump(st, f)
            sys.exit("fake aws: association is still associating")
        a["associationState"] = "disassociating"
        out = {"directConnectGatewayAssociation": a}
    elif cmd == "describe-transit-gateway-attachments":
        # AWS lists a deleted attachment for a while, and each TGW has VPC attachments.
        filt = dict(f[5:].split(",Values=", 1) for f in argv if f.startswith("Name="))
        gone = "available" if held("attachment") else "deleted"
        out = {"TransitGatewayAttachments": [{"TransitGatewayId": a["associatedGateway"]["id"],
                                              "ResourceId": a["directConnectGatewayId"],
                                              "State": a["failed_attachment"]}
                                             for a in st["assocs"] if a.get("failed_attachment")] + [
                                            {"TransitGatewayId": a["associatedGateway"]["id"],
                                              "ResourceId": a["directConnectGatewayId"],
                                              "State": "available" if a in live else gone}
                                             for a in st["assocs"]
                                             if a["associatedGateway"]["type"] == "transitGateway"
                                             and filt.get("transit-gateway-id") in (None, a["associatedGateway"]["id"])
                                             and filt.get("resource-id") in (None, a["directConnectGatewayId"])] + [
                                            {"TransitGatewayId": t, "ResourceId": "vpc-" + t, "State": "available"}
                                             for t in st["tgws"] if filt.get("resource-type") in (None, "vpc")]}
    elif cmd == "describe-transit-gateways":
        project = opts["--filters"].split("Values=", 1)[1]
        available = "Name=state,Values=available" in argv
        out = {"TransitGateways": [{"TransitGatewayId": t, "Options": {"AssociationDefaultRouteTableId": "rtb-" + t}}
                                   for t, p in st["tgws"].items() if p == project
                                   and not (available and t in st.get("deleted_tgws", []))]}
    elif cmd == "search-transit-gateway-routes":
        # A route with no CIDR is a prefix-list route; AWS omits TransitGatewayAttachments on a blackhole route.
        states = next(f for f in argv if f.startswith("Name=state,Values=")).split("=", 2)[2].split(",")
        out = {"Routes": [] if held("routes") else [
            dict({"DestinationCidrBlock": c} if c else {"PrefixListId": "pl-0001"},
                 State="blackhole" if t is None else "active",
                 **({} if t is None else {"TransitGatewayAttachments": [{"ResourceType": t}]}))
            for c, t in st["routes"] if ("blackhole" if t is None else "active") in states]}
    elif cmd in ("create-route", "create-transit-gateway-route"):
        out = {"Return": True}
    elif cmd == "describe-instances":
        out = {"Reservations": [{"Instances": [{"NetworkInterfaces": [{"NetworkInterfaceId": "eni-0001"}]}]}]}
    else:
        sys.exit("fake aws: refusing %s %s" % (argv[0], cmd))
    with open(os.environ["DX_STUB_STATE"], "w") as f:
        json.dump(st, f)
    out = jmespath.search(opts["--query"], out) if "--query" in opts else out
    if opts.get("--output") == "text":  # the CLI prints a list's items tab-separated
        out = "\t".join(map(str, out)) if isinstance(out, list) else out
    print(out if opts.get("--output") == "text" else json.dumps(out))


def vif(vid, region="us-west-2", **kw):
    v = {"virtualInterfaceId": vid, "virtualInterfaceType": "transit", "virtualInterfaceState": "available",
         "mtu": 8500, "directConnectGatewayId": DXGW, "region": region,
         "bgpPeers": [{"bgpStatus": "up", "bgpPeerState": "available", "addressFamily": "ipv4", "authKey": KEY}]}
    v.update(kw)
    return v


def assoc(prefixes, gw_type="transitGateway", state="associated", gw="tgw-other", dxgw=DXGW):
    return {"directConnectGatewayId": dxgw, "associationState": state,
            "associatedGateway": {"id": gw, "type": gw_type},
            "allowedPrefixesToDirectConnectGateway": [{"cidr": p} for p in prefixes]}


BASE = {"vifs": [vif("dxvif-aaaa1111"), vif("dxvif-bbbb2222")], "assocs": [], "routes": [], "hold": {},
        "tgws": {"tgw-0001": "ega-test", "tgw-other": "another-project"},
        "dxgws": [{"directConnectGatewayId": DXGW, "directConnectGatewayState": "available", "amazonSideAsn": 64600}],
        # The appliance: a default route via mgmt and the uplink's connected /30 holding next_hop.
        "host": {"match": [{"dst": "default", "gateway": "172.20.20.1", "dev": "eth0", "protocol": "4"},
                           {"dst": "10.99.0.0/30", "dev": "eth1", "protocol": "2", "scope": "link",
                            "prefsrc": "10.99.0.2"}],
                 "get": {"dst": "10.99.0.1", "dev": "eth1", "prefsrc": "10.99.0.2"}, "root": {},
                 "mtu": {"eth0": 1500, "eth1": 8500}, "addr": "10.99.0.1"}}  # match and get answer for addr only


def edit(path, **kw):
    """Return a mutator that updates the object at path (e.g. ('vifs', 1)) with kw."""
    def f(st):
        obj = st
        for p in path:
            obj = obj[p]
        obj.update(kw)
    return f


# Each negative must fail with its check's message, not with an unrelated error.
INPUTS, GATEWAY, SAFE = "Set evpn_aws_infra_dx_gateway_id", "must exist, be available", "requires tunnel.mtu_mode safe"
ATTACHED, SLOT = "only transit VIFs attached", "only transit gateway associations"
READABLE, USABLE = "must be readable by this account", "is available with every IPv4 BGP peer up"


def vif_down(i):
    return edit(("vifs", i), virtualInterfaceState="down")


def bgp_down(i):
    return edit(("vifs", i, "bgpPeers", 0), bgpStatus="down")


# What provisioning checks before creating anything: dx_preflight.
# (name, mutator, extra vars, expected failure message or None for success)
CASES = [
    ("valid transit VIFs", None, {}, None),
    ("detached private VIF ignored", lambda s: s["vifs"].append(
        vif("dxvif-cccc3333", virtualInterfaceType="private", attachmentState="detached")), {}, None),
    ("attaching 1500-byte VIF", lambda s: s["vifs"].append(
        vif("dxvif-dddd4444", mtu=1500, attachmentState="attaching")), {}, READABLE),
    ("detaching 1500-byte VIF ignored", lambda s: s["vifs"].append(
        vif("dxvif-dddd4444", mtu=1500, attachmentState="detaching")), {}, None),
    ("VIF in another Region", edit(("vifs", 1), region="us-east-1"), {}, None),
    ("deleted BGP peers ignored", lambda s: [v["bgpPeers"].append(
        {"bgpStatus": "down", "bgpPeerState": "deleted", "addressFamily": "ipv4", "authKey": KEY}) for v in s["vifs"]],
     {}, None),
    ("IPv6 BGP peers down ignored", lambda s: [v["bgpPeers"].append(
        {"bgpStatus": "down", "bgpPeerState": "available", "addressFamily": "ipv6", "authKey": KEY})
        for v in s["vifs"]],
     {}, None),
    ("disassociated and unrelated associations", lambda s: s["assocs"].extend(
        [assoc(["10.50.0.0/16"]), assoc(["10.200.0.0/16"], state="disassociated")]), {}, None),
    ("another TGW allowing only ::/0", lambda s: s["assocs"].append(assoc(["::/0"])), {}, None),
    ("one VIF down, another usable", vif_down(1), {}, None),
    ("every VIF down", lambda s: [vif_down(i)(s) for i in (0, 1)], {}, USABLE),
    ("BGP down on every VIF", lambda s: [bgp_down(i)(s) for i in (0, 1)], {}, USABLE),
    ("no BGP peers", lambda s: [edit(("vifs", i), bgpPeers=[])(s) for i in (0, 1)], {}, USABLE),
    # AWS may omit any member; a peer without a status or an address family is not known to be up.
    ("BGP peer without status or address family", lambda s: [v["bgpPeers"].append(
        {"bgpPeerState": "pending", "authKey": KEY}) for v in s["vifs"]], {}, USABLE),
    ("VIF owned by another account", edit(("vifs", 1), foreign=True), {}, READABLE),
    ("1500-byte VIF, even when down", lambda s: [edit(("vifs", 1), mtu=1500)(s), vif_down(1)(s)], {}, READABLE),
    ("private VIF", edit(("vifs", 0), virtualInterfaceType="private"), {}, ATTACHED),
    ("no VIF attached", lambda s: [edit(("vifs", i), directConnectGatewayId="other")(s) for i in (0, 1)], {}, ATTACHED),
    ("no DX gateway ID", None, {"dxgw": ""}, INPUTS),
    ("DX gateway missing", lambda s: s["dxgws"].clear(), {}, GATEWAY),
    ("DX gateway deleting", edit(("dxgws", 0), directConnectGatewayState="deleting"), {}, GATEWAY),
    ("DX gateway ASN equals the TGW's", edit(("dxgws", 0), amazonSideAsn=64512), {}, GATEWAY),
    ("DX gateway has five TGWs", lambda s: s["assocs"].extend(
        assoc(["10.%d.0.0/16" % i], gw="tgw-%d" % i) for i in range(5)), {}, None),
    ("DX gateway has six TGWs", lambda s: s["assocs"].extend(
        assoc(["10.%d.0.0/16" % i], gw="tgw-%d" % i) for i in range(6)), {}, SLOT),
    ("DX gateway associated with a VGW", lambda s: s["assocs"].append(
        assoc([], gw_type="virtualPrivateGateway")), {}, SLOT),
    ("allowed prefix covers a VPC", lambda s: s["assocs"].append(assoc(["10.0.0.0/8"])), {}, SLOT),
    ("updating association allowing a VPC prefix", lambda s: s["assocs"].append(
        assoc(["10.100.0.0/16"], state="updating")), {}, SLOT),
    ("allowed prefix inside a VPC", lambda s: s["assocs"].append(assoc(["10.200.5.0/24"])), {}, SLOT),
]


# The transport preflight's own checks (evpn_health_check), with no AWS call.
BUDGET = "exceeds the"
PREFLIGHT = [
    ("direct-connect at its MTU budget", {"evpn_health_check_workload_mtu": 1500}, None),
    ("direct-connect in unsafe MTU mode", {"mtu_mode": "unsafe"}, SAFE),
    ("direct-connect VTEP outside tunnel.network_cidr", {"onprem_ip": "10.45.0.1"}, "onprem_ip 10.45.0.1"),
    ("direct-connect VTEP with a prefix length", {"onprem_ip": "10.44.44.1/24"}, "onprem_ip 10.44.44.1/24"),
    ("direct-connect network_cidr not a network", {"network_cidr": "10.44.44.1/24"}, "network_cidr 10.44.44.1/24"),
    ("direct-connect empty network_cidr", {"network_cidr": ""}, "a plain IPv4 address"),
    ("direct-connect next_hop not an address", {"next_hop": "10.99.0.0/30"}, "next_hop 10.99.0.0/30"),
    ("direct-connect next_hop inside tunnel.network_cidr", {"next_hop": "10.44.44.9"}, "next_hop 10.44.44.9"),
    ("direct-connect network_cidr inside the infra VPC", {"network_cidr": "10.100.44.0/24", "onprem_ip": "10.100.44.1"},
     "network_cidr 10.100.44.0/24"),
    ("direct-connect network_cidr inside the workload VPC",
     {"network_cidr": "10.200.44.0/24", "onprem_ip": "10.200.44.1"}, "network_cidr 10.200.44.0/24"),
    ("direct-connect network_cidr holding the infra VPC",
     {"network_cidr": "10.100.0.0/15", "onprem_ip": "10.101.44.1"}, "network_cidr 10.100.0.0/15"),
    ("direct-connect network_cidr holding the workload VPC",
     {"network_cidr": "10.200.0.0/15", "onprem_ip": "10.200.44.1"}, "network_cidr 10.200.0.0/15"),
    ("direct-connect without next_hop", {"tunnel": {"type": "direct-connect", "onprem_ip": "10.44.44.1"}},
     "following are missing: next_hop"),
    ("direct-connect with only the required tunnel keys",
     {"tunnel": {"type": "direct-connect", "onprem_ip": "10.44.44.1", "next_hop": "10.99.0.1"}}, None),
    ("direct-connect over its MTU budget", {"evpn_health_check_workload_mtu": 1501}, BUDGET),
]

# What health checks read once the project TGW is associated: dx_status.
ROUTE, COVER, TGW = "must advertise 10.44.44.0/24", "allowing both VPC CIDRs", "Expected one available TGW"


def status_base(st):
    st["assocs"].append(assoc(["10.100.0.0/16", "10.200.0.0/16"], gw="tgw-0001"))
    st["routes"].append(("10.44.44.0/24", "direct-connect-gateway"))


STATUS = [
    ("associated, routed over DX", None, None),
    ("aggregate routed over DX", lambda s: s.update(routes=[("10.44.0.0/16", "direct-connect-gateway")]), None),
    ("route propagated after 3 reads", lambda s: s["hold"].update(routes=3), None),
    ("prefix-list route alongside", lambda s: s["routes"].append((None, "vpc")), None),
    ("association updating", edit(("assocs", 0), associationState="updating"), None),
    ("aggregate allowed prefix", edit(("assocs", 0), allowedPrefixesToDirectConnectGateway=[{"cidr": "10.0.0.0/8"}]),
     None),
    ("more specific route elsewhere in the network", lambda s: s["routes"].append(("10.44.44.128/25", "vpc")), None),
    ("more specific route to the VTEP over a VPC", lambda s: s["routes"].insert(0, ("10.44.44.0/25", "vpc")), ROUTE),
    ("more specific blackhole route to the VTEP", lambda s: s["routes"].append(("10.44.44.0/25", None)), ROUTE),
    ("only an IPv6 default route over DX", lambda s: s.update(routes=[("::/0", "direct-connect-gateway")]), ROUTE),
    ("only IPv6 allowed prefixes", edit(("assocs", 0), allowedPrefixesToDirectConnectGateway=[{"cidr": "::/0"}]), COVER),
    ("on-premises network not advertised", lambda s: s["routes"].clear(), ROUTE),
    ("association disassociated", edit(("assocs", 0), associationState="disassociated"), COVER),
    ("every VIF down", lambda s: [vif_down(i)(s) for i in (0, 1)], USABLE),
    ("association missing the workload VPC", edit(("assocs", 0), allowedPrefixesToDirectConnectGateway=[
        {"cidr": "10.100.0.0/16"}]), COVER),
    ("association missing the infra VPC", edit(("assocs", 0), allowedPrefixesToDirectConnectGateway=[
        {"cidr": "10.200.0.0/16"}]), COVER),
    ("deleted project TGW ignored", lambda s: s.update(tgws=dict(s["tgws"], **{"tgw-old": "ega-test"}),
                                                       deleted_tgws=["tgw-old"]), None),
    ("two project TGWs", lambda s: s["tgws"].update({"tgw-0002": "ega-test"}), TGW),
    ("no project TGW", lambda s: s["tgws"].clear(), TGW),
]


def run(tmp, steps, st, extra=None, write=False, args=(), play="play.yml"):
    """Play the task files in steps on state st; return (process, calls as argv lists, new state)."""
    state, log = os.path.join(tmp, "state.json"), os.path.join(tmp, "calls.log")
    with open(state, "w") as f:
        json.dump(st, f)
    open(log, "w").close()
    env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"], DX_STUB_STATE=state, DX_STUB_LOG=log,
               ANSIBLE_NOCOLOR="1", ANSIBLE_LOCALHOST_WARNING="false", ANSIBLE_INVENTORY_UNPARSED_WARNING="false",
               ANSIBLE_ROLES_PATH=os.path.join(ANSIBLE, "roles"))
    if write:
        env["DX_STUB_WRITE"] = "1"
    extra = dict(extra or {}, steps=steps)
    p = subprocess.run(["ansible-playbook", "-v", os.path.join(HERE, play), "-e", json.dumps(extra), *args],
                       env=env, capture_output=True, text=True)
    with open(log) as f, open(state) as g:
        return p, [json.loads(line) for line in f], json.load(g)


def mutations(calls):
    return [c[1] for c in calls if not c[1].startswith(("describe-", "search-"))]


def problems(*checks):
    return [msg for bad, msg in checks if bad]


FAST = {"_evpn_aws_infra_dx_retry_delay": 0}


def associate(tmp):
    """Association, then teardown twice: only the project TGW's association changes."""
    vpcs = ["10.100.0.0/16", "10.200.0.0/16"]
    st = copy.deepcopy(BASE)
    st["assocs"].append(dict(assoc(["10.50.0.0/16"]), associationId="assoc-other"))  # another TGW on the DX gateway
    st["hold"]["assoc_read"] = 2  # the association is not readable right after the create
    p, calls, st = run(tmp, ["dx"], st, FAST, write=True)
    mine = [a for a in st["assocs"] if a["associatedGateway"]["id"] == "tgw-0001"]
    yield "associate the project TGW with exactly the VPC prefixes", problems(
        (p.returncode != 0, "rc=%d\n%s" % (p.returncode, p.stdout[-3000:])),
        (mutations(calls) != ["create-direct-connect-gateway-association"], "calls: %s" % mutations(calls)),
        (len(mine) != 1 or mine[0]["associationState"] != "associated", "project association: %s" % mine),
        (sum(c[1] == "describe-direct-connect-gateway-associations" for c in calls) != 3, "kept polling"),
        (mine and [c["cidr"] for c in mine[0]["allowedPrefixesToDirectConnectGateway"]] != vpcs, "prefixes"))
    for name in ("teardown deletes only the project TGW's association",
                 "teardown again makes no directconnect call"):
        p, calls, st = run(tmp, ["teardown_dx"], st, write=True)
        again = "again" in name
        states = {a["associationId"]: a["associationState"] for a in st["assocs"]}
        yield name, problems(
            (p.returncode != 0, "rc=%d\n%s" % (p.returncode, p.stdout[-3000:])),
            (mutations(calls) != ([] if again else ["delete-direct-connect-gateway-association"]),
             "calls: %s" % mutations(calls)),
            (again and any(c[0] != "ec2" for c in calls), "calls: %s" % [c[1] for c in calls]),
            (states != {"assoc-other": "associated", "assoc-1": "disassociated"}, "states: %s" % states))


def lifecycle_case(name, steps, st, extra=FAST, write=True, args=(), check=None):
    """A lifecycle case as a job: check(p, calls, st) returns its problems."""
    def job(tmp):
        p, calls, new = run(tmp, steps, st, extra, write, args)
        found = check(p, calls, new)
        yield name, found + ([p.stdout[-3000:]] if found else [])
    return job


def failed_attachments(st):
    """The first two associations were rejected, leaving their TGW attachments failed and rejected."""
    st["assocs"][0]["failed_attachment"], st["assocs"][1]["failed_attachment"] = "failed", "rejected"
    return st


def project_assocs(*states, dxgws=(DXGW,)):
    st = copy.deepcopy(BASE)
    st["assocs"] += [dict(assoc(["10.100.0.0/16"], state=s, gw="tgw-0001", dxgw=d), associationId="assoc-%d" % i)
                     for i, (s, d) in enumerate(zip(states, dxgws))]
    return st


LIFECYCLE = [
    associate,
    lifecycle_case("a rejected association fails with its error", ["dx"], dict(copy.deepcopy(BASE), reject=True),
        check=lambda p, c, st: problems(
            (p.returncode == 0 or "TEST rejected" not in p.stdout, "rc=%d" % p.returncode),
            (sum(x[1] == "describe-direct-connect-gateway-associations" for x in c) != 1, "kept polling"))),
    lifecycle_case("an association never readable fails promptly", ["dx"],
        dict(copy.deepcopy(BASE), hold={"assoc_read": 99}), check=lambda p, c, st: problems(
            (p.returncode == 0 or "ended as" not in p.stdout or "None" not in p.stdout, "rc=%d" % p.returncode),
            (sum(x[1] == "describe-direct-connect-gateway-associations" for x in c) > 8, "kept polling"))),
    lifecycle_case("a refused create shows AWS's error and waits for nothing", ["dx"],
        dict(copy.deepcopy(BASE), errors={"create-direct-connect-gateway-association": [
            ("DirectConnectClientException", "TEST quota")]}),
        check=lambda p, c, st: problems(
            (p.returncode == 0 or "TEST quota" not in p.stdout, "rc=%d" % p.returncode),
            (not c or c[-1][1] != "create-direct-connect-gateway-association", "calls: %s" % c))),
    lifecycle_case("teardown retries an association still being created", ["teardown_dx"],
        dict(project_assocs("associating"), hold={"pending": 2}), check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode),
            (st["assocs"][0]["associationState"] != "disassociated", "state: %s" % st["assocs"][0]))),
    lifecycle_case("teardown resumed while disassociating deletes nothing", ["teardown_dx"],
        dict(project_assocs("disassociating"), hold={"pending": 2}),
        check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode), (mutations(c), "calls: %s" % mutations(c)))),
    lifecycle_case("teardown waits for the TGW's DX attachment to go", ["teardown_dx"],
        dict(project_assocs("associated"), hold={"attachment": 3}),
        check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode),
            (sum(x[1] == "describe-transit-gateway-attachments" for x in c) < 4, "did not wait"))),
    lifecycle_case("teardown deletes a project TGW's associations with two DX gateways", ["teardown_dx"],
        project_assocs("associated", "associated", dxgws=(DXGW, "dxgw-second")),
        check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode),
            (mutations(c) != ["delete-direct-connect-gateway-association"] * 2, "calls: %s" % mutations(c)))),
    *[lifecycle_case("teardown stops at once on " + name, ["teardown_dx"],
        dict(project_assocs("associated"), errors={"delete-direct-connect-gateway-association": [(code, "TEST")] * 3}),
        check=lambda p, c, st, code=code: problems(
            (p.returncode == 0 or code not in p.stdout, "rc=%d" % p.returncode),
            (mutations(c) != ["delete-direct-connect-gateway-association"], "calls: %s" % mutations(c))))
      for name, code in (("a denied delete", "AccessDeniedException"), ("an expired token", "ExpiredTokenException"))],
    lifecycle_case("teardown takes an association deleted since it was found as gone", ["teardown_dx"],
        dict(project_assocs("associated"), vanish=True), check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode),
            (mutations(c) != ["delete-direct-connect-gateway-association"], "calls: %s" % mutations(c)))),
    # The CLI has already retried throttling and connection errors; polling on cannot clear the rest.
    lifecycle_case("teardown stops waiting on an AWS error", ["teardown_dx"],
        dict(project_assocs("associated"), errors={"describe-transit-gateway-attachments": [
            None, ("ExpiredTokenException", "TEST expired"), ("ExpiredTokenException", "TEST expired")]}),
        check=lambda p, c, st: problems(
            (p.returncode == 0 or "TEST expired" not in p.stdout, "rc=%d" % p.returncode),
            (sum(x[1] == "describe-transit-gateway-attachments" for x in c) != 2, "kept polling"))),
    lifecycle_case("an AWS error ends the association wait", ["dx"],
        dict(copy.deepcopy(BASE), errors={"describe-direct-connect-gateway-associations": [
            ("ExpiredTokenException", "TEST expired")] * 2}),
        check=lambda p, c, st: problems(
            (p.returncode == 0 or "TEST expired" not in p.stdout, "rc=%d" % p.returncode),
            (sum(x[1] == "describe-direct-connect-gateway-associations" for x in c) != 1, "kept polling"))),
    lifecycle_case("an AWS error ends the route wait", ["dx_status"],
        dict(copy.deepcopy(BASE), assocs=[assoc(["10.100.0.0/16", "10.200.0.0/16"], gw="tgw-0001")],
             errors={"search-transit-gateway-routes": [("ExpiredTokenException", "TEST expired")] * 2}), write=False,
        check=lambda p, c, st: problems(
            (p.returncode == 0 or "TEST expired" not in p.stdout, "rc=%d" % p.returncode),
            (sum(x[1] == "search-transit-gateway-routes" for x in c) != 1, "kept polling"))),
    lifecycle_case("teardown under --check changes nothing", ["teardown_dx"], project_assocs("associated"),
        args=["--check"], check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode), (mutations(c), "calls: %s" % mutations(c)))),
    lifecycle_case("teardown ignores failed and rejected DX attachments", ["teardown_dx"],
        failed_attachments(project_assocs("disassociated", "disassociated", dxgws=(DXGW,) * 2)),
        check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode),
            (any(x[0] != "ec2" for x in c), "calls: %s" % [x[1] for x in c]))),
    lifecycle_case("teardown does not wait on failed and rejected DX attachments", ["teardown_dx"],
        failed_attachments(project_assocs("disassociated", "disassociated", "associated", dxgws=(DXGW,) * 3)),
        check=lambda p, c, st: problems(
            (p.returncode != 0, "rc=%d" % p.returncode),
            (mutations(c) != ["delete-direct-connect-gateway-association"], "calls: %s" % mutations(c)),
            (sum(x[1] == "describe-transit-gateway-attachments" for x in c) > 3, "waited on it"))),
]


def check_job(name, steps, mutators, extra, want, appliance=False):
    """appliance: the play host is in onprem_appliances, so the preflight reads its routes."""
    def job(tmp):
        st = copy.deepcopy(BASE)
        for f in mutators:
            if f:
                f(st)
        args = []
        if appliance:
            args = ["-i", os.path.join(tmp, "hosts")]
            with open(args[1], "w") as f:
                f.write("[onprem_appliances]\nlocalhost ansible_connection=local\n")
        p, calls, _ = run(tmp, steps, st, extra, args=args)
        out = p.stdout + p.stderr
        found = problems(
            ((p.returncode == 0) != (want is None), "expected %s, rc=%d" % (want or "success", p.returncode)),
            (want is not None and want not in out, "did not fail with: %s" % want),
            (mutations(calls), "non-describe call: %s" % mutations(calls)),
            (KEY in out, "printed a VIF BGP key"))
        yield name, found + ([out[-3000:]] if found else [])
    return job


# The appliance side of the transport preflight, against fake `ip` and `cat`.
UPLINK = "Direct Connect needs tunnel.next_hop"


def host(**kw):
    return lambda s: s["host"].update(kw)


APPLIANCE = [
    ("uplink directly connected at MTU 8500", None, None),
    ("FRR's static and BGP routes within the VPC CIDRs", host(root={
        "10.100.0.0/16": [{"dst": "10.100.0.0/16", "protocol": "196"}],
        "10.200.0.0/16": [{"dst": "10.200.0.0/16", "protocol": "186"}]}), None),
    ("host route to next_hop", lambda s: s["host"]["match"].append(
        {"dst": "10.99.0.1", "dev": "eth1", "scope": "link"}), UPLINK),
    ("broader route listed first", lambda s: s["host"]["match"].insert(0, {
        "dst": "10.96.0.0/12", "gateway": "172.20.20.1", "dev": "eth0", "protocol": "4"}), None),
    ("next_hop only via the default route", lambda s: s["host"]["match"].pop(), UPLINK),
    ("no route to next_hop", host(match=[], get=None), UPLINK),
    ("next_hop is the appliance's own address", host(get={"dst": "10.99.0.1", "dev": "lo", "type": "local"}), UPLINK),
    ("next_hop is the uplink's broadcast address", host(get={"dst": "10.99.0.3", "dev": "eth1", "type": "broadcast"}),
     UPLINK),
    ("uplink is the trunk", lambda s: [s["host"]["match"][1].update(dev="eth9"), s["host"]["get"].update(dev="eth9"),
                                       s["host"]["mtu"].update(eth9=8500)], UPLINK),
    ("uplink is the trunk bridge", lambda s: [s["host"]["match"][1].update(dev="trunk-br"),
                                              s["host"]["get"].update(dev="trunk-br"),
                                              s["host"]["mtu"].update({"trunk-br": 8500})], UPLINK),
    # Deploy uses the kernel's lookup, which a policy rule can send past the main table's connected route.
    ("route get picks another 1500-byte device", lambda s: [s["host"]["get"].update(dev="eth2"),
                                                           s["host"]["mtu"].update(eth2=1500)], UPLINK),
    ("route get goes via a gateway", lambda s: s["host"]["get"].update(gateway="10.99.0.1"), UPLINK),
    ("1550-byte uplink", host(mtu={"eth1": 1550}), None),
    ("1549-byte uplink", host(mtu={"eth1": 1549}), UPLINK),
    ("boot route within a VPC CIDR", host(root={"10.100.0.0/16": [{"dst": "10.100.5.0/24"}]}),
     "10.100.5.0/24 proto boot"),
    ("kernel route within a VPC CIDR", host(root={"10.200.0.0/16": [{"dst": "10.200.0.0/16", "protocol": "2"}]}),
     "10.200.0.0/16 proto 2"),
]


# deploy.yml's checks on two appliances of the given transports; they must stop it before any host change
# (None: they pass, and deploy reaches the hosts).
ONE = "supports one on-premises appliance"
DEPLOY = [
    ("two direct-connect appliances", ["direct-connect", "direct-connect"], ONE),
    ("wireguard appliance listed before a direct-connect one", ["wireguard", "direct-connect"], ONE),
    ("two wireguard appliances", ["wireguard", "wireguard"], None),
]


def deploy_job(name, types, want):
    def job(tmp):
        tunnels = {"wireguard": {"cloud_ip": "10.44.44.2", "port": 51820}, "direct-connect": {"next_hop": "10.99.0.1"}}
        hosts = {"appliance-%d" % i: {"tunnel": dict(tunnels[t], type=t, mtu_mode="safe", onprem_ip="10.44.44.%d" % (
            1 + 128 * i), network_cidr="10.44.44.%d/25" % (128 * i))} for i, t in enumerate(types)}
        inventory = os.path.join(tmp, "hosts.json")
        with open(inventory, "w") as f:
            # become always fails, so a deploy past the checks stops there.
            json.dump({"onprem_appliances": {"hosts": hosts, "vars": {
                "ansible_connection": "local", "ansible_become_exe": "false", "trunk_interface": "eth9",
                "evpn_health_check_accept_internet_mode_limits": True}}}, f)
        p, _, _ = run(tmp, [], BASE, args=["--check", "-i", inventory],
                      play=os.path.join(ANSIBLE, "playbooks", "deploy.yml"))
        out = p.stdout + p.stderr
        found = problems((want is not None and want not in out, "did not fail with: %s" % want),
                         (("PLAY [Deploy on-prem appliance" in out) != (want is None),
                          "ran past the checks" if want else "stopped at the checks"))
        yield name, found + ([out[-3000:]] if found else [])
    return job


# What deploy renders for each transport, and the routes provisioning adds toward the on-premises network.
# (role, tasks of its main.yml run before rendering)
RENDER_STEPS = {"evpn_onprem_appliance": ["Find the Direct Connect uplink"],
                "evpn_aws_infra": ["Route the on-premises network through the TGW",
                                   "Add TGW static route for on-prem CIDR", "Add on-prem WG CIDR route to Infra RT via ENI"]}
DX_LINES = {
    "frr-onprem-appliance.conf.j2": [
        "ip route 10.100.0.0/16 10.99.0.1 eth1 onlink", "ip route 10.200.0.0/16 10.99.0.1 eth1 onlink",
        " neighbor 10.100.1.10 ebgp-multihop 255", " neighbor 10.100.1.10 update-source 10.44.44.1"],
    "nmstate.yml.j2": ["  - name: ega-vtep", "    type: dummy", "        - ip: 10.44.44.1",
                       "    - ip-to: 10.100.0.0/16", "      suppress-prefix-length: 15",
                       "    - ip-to: 10.200.0.0/16", "      action: blackhole"],
    "frr-infra-relay.conf.j2": [" neighbor 10.44.44.1 ebgp-multihop 255"]}
# Only wireguard has the appliance and the relay peer with each other for IPv4 unicast: text in that block.
IPV4 = {"frr-onprem-appliance.conf.j2": " activate", "frr-infra-relay.conf.j2": " neighbor 10.44.44.1 "}
ROUTES = {"direct-connect": [["create-route", "rtb-infra", "10.44.44.0/24", "tgw-0001"]],
          "wireguard": [["create-transit-gateway-route", "tgw-rtb-0001", "10.44.44.0/24", "tgw-attach-infra"],
                        ["create-route", "rtb-infra", "10.44.44.0/24", "eni-0001"]]}


def ipv4(lines):
    """The lines of FRR config's IPv4 unicast address family."""
    block = lines[lines.index(" address-family ipv4 unicast"):] if " address-family ipv4 unicast" in lines else []
    return block[:block.index(" exit-address-family")] if block else []


def render_job(ttype):
    def job(tmp):
        p, calls, _ = run(tmp, RENDER_STEPS, BASE, {"ttype": ttype, "out": tmp}, write=True, play="render.yml")
        out = {}
        for t in DX_LINES:
            if os.path.exists(os.path.join(tmp, t)):
                with open(os.path.join(tmp, t)) as f:
                    out[t] = f.read().split("\n")

        def opt(c, *names):
            return next((c[c.index(o) + 1] for o in names if o in c), None)
        # (command, route table, destination, target) of each route created
        routes = [[c[1], opt(c, "--route-table-id", "--transit-gateway-route-table-id"),
                   opt(c, "--destination-cidr-block"), opt(c, "--transit-gateway-id", "--transit-gateway-attachment-id",
                                                           "--network-interface-id")]
                  for c in calls if c[1].startswith("create-")]
        dx = ttype == "direct-connect"
        found = problems(
            (p.returncode != 0, "rc=%d\n%s" % (p.returncode, p.stdout[-3000:])),
            *[((line in out.get(t, [])) != dx, "%s: %s %r" % (t, "missing" if dx else "has", line))
              for t, lines in DX_LINES.items() for line in lines],
            *[(any(text in line for line in ipv4(out.get(t, []))) == dx, "%s: IPv4 unicast %s %r" % (
                t, "has" if dx else "lacks", text)) for t, text in IPV4.items()],
            (routes != ROUTES[ttype], "routes: %s" % routes))
        yield "%s renders and routes as expected" % ttype, found
    return job


JOBS = [*[check_job(n, ["dx_preflight"], [m], x, w) for n, m, x, w in CASES],
        *[check_job(n, ["preflight"], [], x, w) for n, x, w in PREFLIGHT],
        *[check_job(n, ["dx_status"], [status_base, m], FAST, w) for n, m, w in STATUS],
        check_job("dx_status rejects a wildcard project name", ["dx_status"], [status_base],
                  dict(FAST, evpn_aws_infra_project_name="ega-*"), "letters, digits"),
        *[check_job("dx_status refuses " + k, ["dx_status"], [status_base], dict(FAST, **{k: v}),
                    "require local execution") for k, v in (("ansible_become", True), ("ansible_connection", "ssh"))],
        *[check_job(n, ["preflight"], [m], {"trunk_interface": "eth9"}, w, appliance=True)
          for n, m, w in APPLIANCE],
        *[deploy_job(n, t, w) for n, t, w in DEPLOY],
        *[render_job(t) for t in ("direct-connect", "wireguard")],
        *LIFECYCLE]


def isolated(job):
    """Run a job in its own directory, holding the fake `aws`, `ip` and `cat`."""
    with tempfile.TemporaryDirectory() as tmp:
        for cmd in ("aws", "ip", "cat"):
            os.symlink(os.path.join(HERE, "run.py"), os.path.join(tmp, cmd))
        return list(job(tmp))


def main():
    failed = total = 0
    with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 1)) as pool:
        for results in pool.map(isolated, JOBS):
            for name, found in results:
                total += 1
                failed += bool(found)
                print("%s %s%s" % ("FAIL" if found else "ok  ", name, "".join("\n  " + str(m) for m in found)),
                      flush=True)
    print("%d of %d cases failed" % (failed, total))
    return 1 if failed else 0


if __name__ == "__main__":
    NAME = os.path.basename(sys.argv[0])
    if NAME in ("ip", "cat"):
        sys.exit(fake_host(NAME, sys.argv[1:]))
    sys.exit(fake_aws(sys.argv[1:]) if NAME == "aws" else main())
