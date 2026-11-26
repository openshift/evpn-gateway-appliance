#!/usr/bin/env python3
"""Transport preflight and ping-baseline cases against canned inputs: run.py plays play.yml, deploy.yml,
provision-aws.yml or baseline.yml per case. The `ping` symlink it creates runs this file as a fake iputils ping that
prints the case's canned output, and the `aws` symlink as an AWS CLI that must not be reached.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ANSIBLE = os.path.join(HERE, "..", "..", "ansible")
ACK = {"evpn_health_check_accept_internet_mode_limits": True}
OK = "20 packets transmitted, 20 received, 0% packet loss, time 3805ms\nrtt min/avg/max/mdev = 0.512/1.234/2.001/0.300 ms"
PART = ("20 packets transmitted, 15 received, +2 duplicates, +3 errors, 25% packet loss, time 3805ms\n"
        "rtt min/avg/max/mdev = 0.512/12.500/30.001/3.300 ms, pipe 2")
FULL = "20 packets transmitted, 20 received, 0% packet loss, time 3805ms"


def vars_(**kw):
    return json.dumps(kw)


# (name, playbook, extra vars, expected: None for success, "ok:<text>" for success printing text, "stats:<a>|<b>" for
# success whose final custom statistics hold each text, else a failure message)
CASES = [
    ("ipsec without the acknowledgment", "play.yml", vars_(ttype="ipsec"), "crosses the internet"),
    # -e key=value passes strings.
    ("acknowledgment false (string)", "play.yml", "ttype=wireguard evpn_health_check_accept_internet_mode_limits=false", "crosses the internet"),
    ("acknowledgment y (string)", "play.yml", "ttype=ipsec evpn_health_check_accept_internet_mode_limits=y", None),
    ("ipsec at its budget (strings)", "play.yml", "ttype=ipsec evpn_health_check_accept_internet_mode_limits=true evpn_health_check_workload_mtu=1388",
     None),
    ("wireguard at its budget", "play.yml", vars_(ttype="wireguard", evpn_health_check_workload_mtu=1370, **ACK), None),
    ("wireguard over its budget", "play.yml", vars_(ttype="wireguard", evpn_health_check_workload_mtu=1371, **ACK), "budget of"),
    ("ipsec over its budget", "play.yml", vars_(ttype="ipsec", evpn_health_check_workload_mtu=1389, **ACK), "budget of"),
    ("negative MTU", "play.yml", vars_(ttype="ipsec", evpn_health_check_workload_mtu=-1, **ACK), "budget of"),
    ("below the CUDN minimum MTU", "play.yml", vars_(ttype="ipsec", evpn_health_check_workload_mtu=575, **ACK), "budget of"),
    # 0, the role default, means the operator did not declare it.
    ("undeclared MTU (0)", "play.yml", vars_(ttype="wireguard", evpn_health_check_workload_mtu=0, **ACK), "Set evpn_health_check_workload_mtu"),
    ("second host over the budget", "play.yml", vars_(ttype="ipsec", second_workload_mtu=1389, **ACK), "budget of"),
    ("direct-connect rejected", "play.yml", vars_(ttype="direct-connect"), "must be one of"),
    # Provisioning runs the preflight on localhost, which may not see per-appliance addresses.
    ("provisioning on localhost", "play.yml", vars_(tunnel={"type": "wireguard"}, **ACK), None),
    # The health check's loss and RTT baseline on canned iputils summaries.
    ("baseline, no loss", "baseline.yml", vars_(ping_out=OK), "ok:loss 0%, average RTT 1.234 ms"),
    ("baseline, 25% loss", "baseline.yml", vars_(ping_out=PART), "ok:loss 25%, average RTT 12.500 ms"),
    # The run's statistics keep the baseline under the appliance's name.
    ("baseline kept per host", "baseline.yml", vars_(ping_out=PART), 'stats:"appliance": {'),
    ("baseline, total loss", "baseline.yml", vars_(ping_out="20 packets transmitted, 0 received, +20 errors, 100% packet loss, time 3805ms"),
     "No reply"),
    ("baseline, no output", "baseline.yml", vars_(ping_out=""), "No reply"),
    ("baseline without RTT", "baseline.yml", vars_(ping_out=FULL), None),
    # Keyed by the appliance, not the workload VTEP host (extra vars give `first` the workload's address).
    ("baseline keyed by the appliance", "baseline.yml", vars_(ping_out=PART, workload_vtep_host="first", private_ip="10.200.1.10"),
     'stats:"appliance": {'),
    ("baseline kept for every appliance", "baseline.yml", vars_(ping_out=PART, appliances=["appliance", "appliance2"]),
     'stats:"appliance": {|"appliance2": {'),
]


def fake_ping(argv):
    """iputils ping as baseline.yml runs it: 20 pings from the VTEP address (tunnel.onprem_ip) to the workload VTEP
    (private_ip), in the C locale it parses."""
    if os.environ.get("LC_ALL") != "C":
        sys.exit("fake ping: LC_ALL is not C")
    if " -c 20 " not in " %s " % " ".join(argv) or argv[-3:] != ["-I", "10.44.44.1", "10.200.1.10"]:
        sys.exit("fake ping: unexpected arguments: %s" % " ".join(argv))
    out = os.environ.get("PING_OUT", "")
    # iputils exits 2 on an error and 1 when no reply came back.
    if out.startswith("ping:"):
        sys.exit(out)
    print(out)
    return 1 if not out or " 0 received" in out else 0


def play(tmp, playbook, extra, *args, inventory=os.path.join(HERE, "hosts.yml")):
    """Run playbook with the extra vars; return (rc, output)."""
    env = dict(os.environ, PATH=tmp + os.pathsep + os.environ["PATH"], ANSIBLE_NOCOLOR="1",
               ANSIBLE_ROLES_PATH=os.path.join(ANSIBLE, "roles"), ANSIBLE_SHOW_CUSTOM_STATS="1",
               ANSIBLE_HOME=os.path.join(tmp, "ansible"))
    p = subprocess.run(["ansible-playbook", "-v", "-i", inventory,
                        os.path.join(HERE, playbook), "-e", extra, *args], env=env, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def bad(rc, out, want):
    if want is None:
        return rc != 0
    if want.startswith("ok:"):
        return rc != 0 or want[3:] not in out
    if want.startswith("stats:"):  # Only the run's final custom statistics, not the task results -v prints.
        final = out.rsplit("CUSTOM STATS", 1)[1] if "CUSTOM STATS" in out else ""
        return rc != 0 or any(k not in final for k in want[6:].split("|"))
    return rc == 0 or want not in out


def main():
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        os.symlink(os.path.abspath(__file__), os.path.join(tmp, "ping"))
        for name, playbook, extra, want in CASES:
            rc, out = play(tmp, playbook, extra)
            results.append((name, bad(rc, out, want), want, rc, out))
        # deploy.yml runs the preflight first, and one host's failure stops every host.
        rc, out = play(tmp, os.path.join(ANSIBLE, "playbooks", "deploy.yml"),
                       vars_(tunnel={"type": "ipsec", "onprem_ip": "10.44.44.1"}, second_workload_mtu=1389, **ACK))
        results.append(("deploy.yml stops at its preflight", bad(rc, out, "budget of") or out.count("\nPLAY [") != 1,
                        "budget of, in one play", rc, out))
        # provision-aws.yml runs the preflight before any AWS call: the `aws` symlink records any call it gets.
        os.symlink(os.path.abspath(__file__), os.path.join(tmp, "aws"))
        for name, extra, want in (
                ("provisioning without the acknowledgment", vars_(tunnel={"type": "wireguard"}), "crosses the internet"),
                ("provisioning with an undeclared MTU", vars_(tunnel={"type": "wireguard"}, evpn_health_check_workload_mtu=0,
                                                          **ACK), "Set evpn_health_check_workload_mtu")):
            rc, out = play(tmp, os.path.join(ANSIBLE, "playbooks", "provision-aws.yml"), extra)
            called = os.path.exists(os.path.join(tmp, "aws.calls"))
            results.append((name, bad(rc, out, want) or called, want + ", with no AWS call", rc, out))
        # The shipped inventory and the role defaults leave both settings undeclared: no inventory hosts, so
        # provisioning runs on the implicit localhost.
        for inv in ("empty", "shipped"):
            os.mkdir(os.path.join(tmp, inv))
            with open(os.path.join(tmp, inv, "hosts.yml"), "w") as f:
                f.write("all: {}\n")
        os.symlink(os.path.join(ANSIBLE, "inventory", "group_vars"), os.path.join(tmp, "shipped", "group_vars"))
        for name, inv, extra, want in (
                ("role default MTU is undeclared", "empty", vars_(tunnel={"type": "wireguard"}, **ACK), "Set evpn_health_check_workload_mtu"),
                ("shipped inventory lacks the acknowledgment", "shipped", "{}", "crosses the internet"),
                ("shipped inventory MTU is undeclared", "shipped", vars_(**ACK), "Set evpn_health_check_workload_mtu")):
            rc, out = play(tmp, os.path.join(ANSIBLE, "playbooks", "provision-aws.yml"), extra,
                           inventory=os.path.join(tmp, inv, "hosts.yml"))
            called = os.path.exists(os.path.join(tmp, "aws.calls"))
            results.append((name, bad(rc, out, want) or called, want + ", with no AWS call", rc, out))
        # preflight.yml checks every transport, gathers no facts and changes nothing.
        rc, out = play(tmp, os.path.join(ANSIBLE, "playbooks", "preflight.yml"), vars_(tunnel={"type": "wireguard"}))
        results.append(("preflight.yml checks wireguard", bad(rc, out, "crosses the internet"), "crosses the internet", rc, out))
        rc, out = play(tmp, os.path.join(ANSIBLE, "playbooks", "preflight.yml"), vars_(tunnel={"type": "ipsec"}, **ACK))
        results.append(("preflight.yml is read-only", rc != 0 or "Gathering Facts" in out or bool(re.search(r"changed=[1-9]", out)),
                        "success, no facts, changed=0", rc, out))
        rc, out = play(tmp, "baseline.yml", vars_(ping_out=OK))
        results.append(("baseline changes nothing", rc != 0 or not re.search(r"\nappliance +: ok=\d+ +changed=0 ", out),
                        "success, changed=0 on the appliance", rc, out))
        # deploy.yml's health checks include the baseline (7501's "capture latency and loss baselines").
        rc, out = play(tmp, os.path.join(ANSIBLE, "playbooks", "deploy.yml"), "{}", "--list-tasks")
        health = out.split(": Health checks", 1)[1] if ": Health checks" in out else ""
        results.append(("deploy.yml's health checks record the baseline",
                        rc != 0 or "evpn_health_check : Record the loss and RTT baseline" not in health,
                        "the baseline task in deploy.yml's Health checks play", rc, out))
        # Under --check, ping does not run and the baseline is not judged.
        rc, out = play(tmp, "baseline.yml", vars_(ping_out=FULL + ", sentinel-ping-ran"), "--check")
        results.append(("baseline under --check", rc != 0 or "sentinel-ping-ran" in out, "success, no ping", rc, out))
    for name, failed, want, rc, out in results:
        print("%s %s" % ("FAIL" if failed else "ok  ", name))
        if failed:
            print("  want %s, rc=%d\n%s" % (want or "success", rc, out[-2000:]))
    failed = sum(r[1] for r in results)
    print("%d of %d cases failed" % (failed, len(results)))
    return 1 if failed else 0


def fake_aws(argv):
    """An AWS CLI that must not be reached: it records the call and fails."""
    with open(os.path.join(os.path.dirname(sys.argv[0]), "aws.calls"), "a") as f:
        f.write(" ".join(argv) + "\n")
    sys.exit("fake aws: called")


if __name__ == "__main__":
    NAME = os.path.basename(sys.argv[0])
    sys.exit(fake_ping(sys.argv[1:]) if NAME == "ping" else fake_aws(sys.argv[1:]) if NAME == "aws" else main())
