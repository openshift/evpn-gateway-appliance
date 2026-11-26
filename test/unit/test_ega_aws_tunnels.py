"""Exercise tunnel replacement without IPsec or containers, plus real timeout cleanup."""

import contextlib
import ctypes
import fcntl
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch


PROGRAM = (Path(__file__).resolve().parents[2] / "ansible" / "roles"
           / "evpn_onprem_appliance" / "files" / "ega_aws_tunnels.py")
SPEC = importlib.util.spec_from_file_location("ega_aws_tunnels", PROGRAM)
tunnels = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tunnels)

ARGS = ["--tunnel", "1", "169.254.10.1", "192.0.2.1",
        "--tunnel", "2", "169.254.20.1", "192.0.2.2"]
PEERS = tunnels.parse_tunnels(ARGS)
# Appliance Libreswan x86 N=2 capture (including a rekey) and trimmed FRR 10.6.2
# neighbor JSON. All addresses in the captures are documentation addresses.
FIXTURES = Path(__file__).parent / "fixtures" / "ega_aws_tunnels"
TRAFFICSTATUS = (FIXTURES / "trafficstatus.txt").read_text()
ESTABLISHED = (FIXTURES / "established.json").read_text()
RETRY = "Rerun deploy to retry."


class FakeHost:
    """Model Child SAs and BGP independently, recording every command and sleep."""

    def __init__(self, case, directory):
        self.case = case
        self.directory = directory
        self.children = {peer.number: peer.outside_ip for peer in PEERS}
        self.bgp = {peer.number: "Established" for peer in PEERS}
        self.events = []
        self.elapsed = 0
        self.failures = {}
        self.on_up = lambda number: None
        self.on_sleep = lambda: None
        self.on_reread = lambda: None

    def run(self, args):
        self.case.assertFalse((self.directory / "ega-aws.applied").exists())
        command = tuple(args)
        self.events.append(command)
        if command in self.failures:
            raise self.failures[command]
        if args == ["ipsec", "trafficstatus"]:
            return "\n".join(
                line.replace(f"192.0.2.2{number}", self.children[number])
                for line in TRAFFICSTATUS.splitlines()
                for number in self.children if f'"ega-aws-{number}"' in line
            )
        if args[:4] == ["podman", "exec", "frr", "vtysh"]:
            for peer in PEERS:
                if args == ["podman", "exec", "frr", "vtysh", "-c",
                            f"show bgp neighbors {peer.inside_ip} json"]:
                    neighbor = json.loads(ESTABLISHED)["192.0.2.2"]
                    neighbor["neighborAddr"] = peer.inside_ip
                    neighbor["bgpState"] = self.bgp[peer.number]
                    return json.dumps({peer.inside_ip: neighbor})
            self.case.fail(f"Unexpected BGP command: {args}")
        if args[:2] == ["ipsec", "replace"]:
            number = int(args[-1][-1])
            self.children.pop(number, None)
            self.bgp[number] = "Idle"
            return ""
        if args[:3] == ["ipsec", "up", "--asynchronous"]:
            number = int(args[-1][-1])
            self.children[number] = PEERS[number - 1].outside_ip
            self.bgp[number] = "Established"
            self.on_up(number)
            return ""
        self.case.assertEqual(args, ["ipsec", "rereadsecrets"])
        self.on_reread()
        return ""

    def sleep(self, seconds):
        self.case.assertEqual(seconds, 5)
        self.elapsed += seconds
        self.events.append(("sleep", seconds))
        self.on_sleep()

    def mutations(self):
        return [event for event in self.events if event[:2] in
                (("ipsec", "replace"), ("ipsec", "up")) or event[0] == "sleep"]


def load_events(number):
    return [("ipsec", "replace", f"ega-aws-{number}"),
            ("ipsec", "up", "--asynchronous", f"ega-aws-{number}")]


@contextlib.contextmanager
def failed_command(exception, *, drained=("", "")):
    """Inject a nonzero exit, timeout or launch error with group signals mocked."""
    with patch.object(tunnels.subprocess, "Popen") as popen, \
            patch.object(tunnels.os, "killpg") as killpg:
        process = popen.return_value.__enter__.return_value
        if isinstance(exception, OSError):
            popen.side_effect = exception
        elif isinstance(exception, subprocess.TimeoutExpired):
            process.communicate.side_effect = [exception, drained] * 2
        else:
            process.communicate.return_value = (exception.stdout, exception.stderr)
            process.returncode = exception.returncode
        yield process, killpg


class ReplacementTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.record = self.directory / "ega-aws.applied"
        self.record.write_text("old record\n")
        (self.directory / "ega-aws.conf").write_bytes(b"test configuration\n")
        (self.directory / "ega-aws.secrets").write_bytes(b"TEST_ONLY\n")
        self.host = FakeHost(self, self.directory)

    def deploy(self):
        output = io.StringIO()
        errors = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            result = tunnels.main(ARGS, runner=self.host.run, sleep=self.host.sleep,
                                  monotonic=lambda: self.host.elapsed,
                                  directory=self.directory)
        self.assertEqual(output.getvalue(), "")
        self.assertNotIn("TEST_ONLY", errors.getvalue())
        if result:
            self.assertFalse(self.record.exists())
        return result, errors.getvalue()

    def test_files_rewritten_during_replacement_are_not_recorded(self):
        # A concurrent deploy rewrites the keys after this one loaded its own: neither is recorded as applied.
        for name in ("ega-aws.secrets", "ega-aws.conf"):
            with self.subTest(name=name):
                self.host = FakeHost(self, self.directory)
                (self.directory / name).write_bytes(b"TEST_ONLY before\n")
                self.host.on_up = lambda number, name=name: (
                    (self.directory / name).write_bytes(b"TEST_ONLY rewritten\n") if number == 2 else None)
                result, errors = self.deploy()
                self.assertEqual(result, 1)
                self.assertEqual(errors, "ega-aws.conf or ega-aws.secrets changed while the tunnels were being "
                                 "replaced, so they are not recorded as applied. Rerun deploy.\n")
                self.assertEqual(self.host.mutations()[:2], load_events(1))

    def test_files_rewritten_during_rereadsecrets_are_not_recorded(self):
        # The hashes are taken before rereadsecrets, so a rewrite while it reads cannot publish keys it never loaded.
        for name in ("ega-aws.secrets", "ega-aws.conf"):
            with self.subTest(name=name):
                self.host = FakeHost(self, self.directory)
                (self.directory / name).write_bytes(b"TEST_ONLY before\n")
                self.host.on_reread = lambda name=name: (self.directory / name).write_bytes(b"TEST_ONLY rewritten\n")
                result, errors = self.deploy()
                self.assertEqual(result, 1)
                self.assertEqual(errors, "ega-aws.conf or ega-aws.secrets changed while the tunnels were being "
                                 "replaced, so they are not recorded as applied. Rerun deploy.\n")

    def test_unchanged_files_are_recorded_as_loaded(self):
        self.assertEqual(self.deploy(), (0, ""))
        expected = "".join(
            f"{hashlib.sha256((self.directory / name).read_bytes()).hexdigest()}  {self.directory / name}\n"
            for name in ("ega-aws.conf", "ega-aws.secrets"))
        self.assertEqual(self.record.read_text(), expected)

    def test_first_deploy_loads_both_then_waits_without_reloading(self):
        polls = {
            peer.number: [("ipsec", "trafficstatus"),
                          ("podman", "exec", "frr", "vtysh", "-c",
                           f"show bgp neighbors {peer.inside_ip} json")]
            for peer in PEERS
        }
        for first_ready, last_ready_at in ((1, 10), (2, 10), (1, 95), (2, 95)):
            with self.subTest(first_ready=first_ready, last_ready_at=last_ready_at):
                self.host = FakeHost(self, self.directory)
                self.host.children.clear()
                self.host.bgp = {1: "Idle", 2: "Idle"}

                def on_up(number):
                    self.host.bgp[number] = "Idle"

                def on_sleep():
                    if self.host.elapsed in (5, last_ready_at):
                        number = first_ready if self.host.elapsed == 5 else 3 - first_ready
                        self.host.bgp[number] = "Established"

                self.host.on_up = on_up
                self.host.on_sleep = on_sleep
                self.assertEqual(self.deploy(), (0, ""))
                self.assertEqual(self.host.events,
                                 [("ipsec", "rereadsecrets")]
                                 + [("ipsec", "trafficstatus")] * 5
                                 + load_events(1) + load_events(2)
                                 + polls[1] + polls[2] + [("sleep", 5)] + polls[1]
                                 + (polls[2] if first_ready == 2 else [])
                                 + polls[1] + polls[2]
                                 + (polls[3 - first_ready] + [("sleep", 5)])
                                 * (last_ready_at // 5 - 1) + polls[3 - first_ready])
                self.assertTrue(self.record.exists())

    def test_both_up_replace_one_then_wait_before_touching_two(self):
        def on_up(number):
            self.host.bgp[number] = "Idle"

        def on_sleep():
            self.host.bgp = {1: "Established", 2: "Established"}

        self.host.on_up = on_up
        self.host.on_sleep = on_sleep
        self.assertEqual(self.deploy(), (0, ""))
        self.assertEqual(self.host.mutations(), load_events(1) + [("sleep", 5)]
                         + load_events(2) + [("sleep", 5)])
        self.assertTrue(self.record.exists())

    def test_tunnel_two_down_is_replaced_first(self):
        self.host.children.pop(2)
        self.host.bgp[2] = "Idle"
        self.assertEqual(self.deploy(), (0, ""))
        self.assertEqual(self.host.mutations(), load_events(2) + load_events(1))

    def test_no_sa_still_probes_before_selecting_replacement_order(self):
        snapshots = []
        run = self.host.run

        def runner(args):
            if args == ["ipsec", "trafficstatus"]:
                if len(snapshots) < 2:
                    self.host.children.clear()
                elif len(snapshots) == 2:
                    self.host.children[1] = PEERS[0].outside_ip
                snapshots.append(self.host.children.copy())
            return run(args)

        with patch.object(self.host, "run", side_effect=runner):
            self.assertEqual(self.deploy(), (0, ""))
        self.assertEqual(snapshots[:3], [{}, {}, {1: PEERS[0].outside_ip}])
        self.assertEqual(self.host.mutations(), load_events(2) + load_events(1))
        first_load = self.host.events.index(load_events(2)[0])
        self.assertEqual(self.host.events[:first_load].count(("ipsec", "trafficstatus")), 6)

    def test_pre_wait_allows_bgp_to_recover_before_replacement(self):
        for recovery_time in (10, 45):
            with self.subTest(recovery_time=recovery_time):
                self.host = FakeHost(self, self.directory)
                self.host.bgp = {1: "Idle", 2: "Idle"}

                def on_sleep():
                    if self.host.elapsed == recovery_time:
                        self.host.bgp[1] = "Established"

                self.host.on_sleep = on_sleep
                self.assertEqual(self.deploy(), (0, ""))
                self.assertEqual(self.host.mutations(), [("sleep", 5)] * (recovery_time // 5)
                                 + load_events(2) + load_events(1))

    def test_tunnel_recovers_on_last_poll_before_loading_the_next(self):
        def on_up(number):
            if number == 1:
                self.host.bgp[number] = "Idle"

        def on_sleep():
            if self.host.elapsed == 90:
                self.host.bgp[1] = "Established"

        self.host.on_up = on_up
        self.host.on_sleep = on_sleep
        self.assertEqual(self.deploy(), (0, ""))
        self.assertEqual(self.host.mutations(), load_events(1) + [("sleep", 5)] * 18
                         + load_events(2))

    def test_pre_wait_expires_after_nine_sleeps(self):
        self.host.bgp = {1: "Idle", 2: "Idle"}
        self.assertEqual(self.deploy(), (0, ""))
        self.assertEqual(self.host.mutations(), [("sleep", 5)] * 9
                         + load_events(1) + load_events(2))

    def test_first_tunnel_timeout_stops_before_second(self):
        for child_present, poll_fails in ((child, fails) for child in (True, False)
                                          for fails in (True, False)):
            with self.subTest(child_present=child_present, poll_fails=poll_fails):
                self.host = FakeHost(self, self.directory)

                def on_up(number):
                    self.host.bgp[number] = "Idle"
                    if not child_present:
                        self.host.children.pop(number)
                    if poll_fails:
                        command = (("podman", "exec", "frr", "vtysh", "-c",
                                    "show bgp neighbors 169.254.10.1 json") if child_present
                                   else ("ipsec", "trafficstatus"))
                        self.host.failures[command] = tunnels.CommandError("poll failed")

                self.host.on_up = on_up
                what = ("its BGP session with 169.254.10.1" if child_present else
                        "its Child SA with 192.0.2.1")
                self.assertEqual(self.deploy(), (1, f"ega-aws-1: {what} did not come up "
                                 f"within 90 s; stopped before any further tunnel. {RETRY}\n"))
                self.assertEqual(self.host.mutations(), load_events(1) + [("sleep", 5)] * 18)

    def test_neither_ready_after_loading_both_fails(self):
        for poll_fails in (True, False):
            with self.subTest(poll_fails=poll_fails):
                self.host = FakeHost(self, self.directory)
                self.host.children.clear()

                def on_up(number):
                    self.host.bgp[number] = "Idle"
                    if poll_fails:
                        self.host.failures[("ipsec", "trafficstatus")] = tunnels.CommandError(
                            "poll failed")

                self.host.on_up = on_up
                self.assertEqual(self.deploy(), (1, "Neither ega-aws-1 nor ega-aws-2 came up with "
                                 f"its BGP session within 90 s. {RETRY}\n"))
                self.assertEqual(self.host.mutations(), load_events(1) + load_events(2)
                                 + [("sleep", 5)] * 18)

    def test_second_tunnel_timeout_after_first_recovers_leaves_no_record(self):
        def on_up(number):
            if number == 2:
                self.host.bgp[number] = "Connect"

        self.host.on_up = on_up
        self.assertEqual(self.deploy(), (1, "ega-aws-2: its BGP session with 169.254.20.1 "
                         "did not come up within 90 s; stopped before any further tunnel. "
                         f"{RETRY}\n"))
        self.assertEqual(self.host.mutations(), load_events(1) + load_events(2)
                         + [("sleep", 5)] * 18)
        self.assertFalse(self.record.exists())

    def test_first_deploy_one_tunnel_never_recovers_leaves_no_record(self):
        for first_ready in (1, 2):
            with self.subTest(first_ready=first_ready):
                self.host = FakeHost(self, self.directory)
                self.host.children.clear()

                def on_up(number):
                    if number != first_ready:
                        self.host.bgp[number] = "Connect"

                self.host.on_up = on_up
                result, error = self.deploy()
                self.assertEqual(result, 1)
                self.assertTrue(error.startswith(f"ega-aws-{3 - first_ready}: "))
                self.assertEqual(self.host.mutations(), load_events(1) + load_events(2)
                                 + [("sleep", 5)] * 18)
                self.assertFalse(self.record.exists())

    def test_held_lock_preserves_record_and_runs_no_commands(self):
        real_flock = fcntl.flock

        def nonblocking(fd, operation):
            self.assertEqual(operation, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return real_flock(fd, operation)

        with (self.directory / "ega-aws.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            errors = io.StringIO()
            with contextlib.redirect_stderr(errors), \
                    patch.object(tunnels.fcntl, "flock", side_effect=nonblocking):
                self.assertEqual(tunnels.main(ARGS, runner=self.host.run,
                                              directory=self.directory), 1)
            self.assertEqual(errors.getvalue(), "another replacement of the AWS IPsec connections "
                             "is still running (or an ipsec command it started is stuck); "
                             "rerun deploy after it finishes, or see the evpn_onprem_appliance "
                             "README if it persists\n")
            self.assertEqual(self.record.read_text(), "old record\n")
            self.assertEqual(self.host.events, [])
        self.assertEqual(self.deploy(), (0, ""))

    def test_lock_is_held_through_record_publication_and_released_on_failure(self):
        def replace(source, destination):
            with (self.directory / "ega-aws.lock").open("a") as lock:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            raise OSError("rename failed")

        with patch.object(tunnels.os, "replace", side_effect=replace):
            self.assertEqual(self.deploy(), (1, "rename failed\n"))
        self.assertEqual(self.deploy(), (0, ""))

    def test_required_command_failure_stops_immediately(self):
        for command in (("ipsec", "rereadsecrets"), *load_events(1)):
            with self.subTest(command=command):
                self.host = FakeHost(self, self.directory)
                self.host.failures[command] = tunnels.CommandError("command failed")
                self.assertEqual(self.deploy(), (1, "command failed\n"))
                self.assertEqual(self.host.events[-1], command)
                self.assertNotIn(load_events(2)[0], self.host.events)

    def test_replace_and_up_stderr_is_stripped_capped_and_reported_by_main(self):
        detail = "configuration error " + "x" * 420
        for command in map(list, load_events(1)):
            for exception in (
                    subprocess.CalledProcessError(7, command, output="UNUSED_STDOUT",
                                                  stderr=f" \n{detail}\n "),
                    subprocess.TimeoutExpired(command, 60, output=b"UNUSED_STDOUT",
                                              stderr=f" \n{detail}\n ".encode())):
                with self.subTest(command=command, exception=exception), failed_command(exception):
                    run = self.host.run

                    def runner(args):
                        return tunnels.run_command(args) if args == command else run(args)

                    with self.assertRaises(tunnels.CommandError) as caught:
                        tunnels.run_command(command)
                    expected = (f"{' '.join(command)} timed out after 60 s"
                                if isinstance(exception, subprocess.TimeoutExpired) else
                                f"{' '.join(command)} failed (exit status 7)")
                    self.assertEqual(str(caught.exception), f"{expected}: {detail[:400]}")
                    with patch.object(self.host, "run", side_effect=runner):
                        self.assertEqual(self.deploy(), (1, f"{expected}: {detail[:400]}\n"))

    def test_slow_trafficstatus_aborts_before_replacement(self):
        command = ("ipsec", "trafficstatus")
        self.host.failures[command] = tunnels.CommandError("timed out after 5 s")
        self.assertEqual(self.deploy(), (1, "ipsec trafficstatus or vtysh did not answer "
                         "within 5 s, so no connection was replaced. Rerun deploy.\n"))
        self.assertEqual(self.host.events, [("ipsec", "rereadsecrets"), command])

    def test_slow_vtysh_at_each_order_decision_aborts_before_replacement(self):
        for number, occurrence, first_bgp in ((1, 2, "Established"), (1, 3, "Established"),
                                              (2, 1, "Established"), (2, 2, "Idle")):
            with self.subTest(number=number, occurrence=occurrence, first_bgp=first_bgp):
                self.host = FakeHost(self, self.directory)
                self.host.bgp[1] = first_bgp
                command = ["podman", "exec", "frr", "vtysh", "-c",
                           f"show bgp neighbors {PEERS[number - 1].inside_ip} json"]
                run = self.host.run
                polls = 0

                def runner(args):
                    nonlocal polls
                    status = run(args)
                    if args == command:
                        polls += 1
                        if polls == occurrence:
                            return tunnels.run_command(args)
                    return status

                with failed_command(subprocess.TimeoutExpired(command, 5)), \
                        patch.object(self.host, "run", side_effect=runner):
                    self.assertEqual(self.deploy(), (1, "ipsec trafficstatus or vtysh did not "
                                     "answer within 5 s, so no connection was replaced. "
                                     "Rerun deploy.\n"))
                self.assertEqual(self.host.mutations(), [])
                self.assertEqual(self.host.events[-1], tuple(command))

    def test_unknown_pre_wait_final_state_aborts_before_replacement(self):
        for command, unknown_polls in ((command, polls) for command in ("ipsec", "podman")
                                       for polls in ((1,), (2,), (1, 2))):
            with self.subTest(command=command, unknown_polls=unknown_polls):
                self.host = FakeHost(self, self.directory)
                self.host.bgp = {1: "Idle", 2: "Idle"}
                run = self.host.run
                final_polls = 0

                def runner(args):
                    nonlocal final_polls
                    status = run(args)
                    if args[0] == command and self.host.elapsed == 45:
                        final_polls += 1
                        if final_polls in unknown_polls:
                            raise tunnels.CommandError("timed out after 5 s")
                    return status

                with patch.object(self.host, "run", side_effect=runner):
                    self.assertEqual(self.deploy(), (1, "ipsec trafficstatus or vtysh did not "
                                     "answer within 5 s, so no connection was replaced. "
                                     "Rerun deploy.\n"))
                self.assertEqual(final_polls, 2)
                self.assertEqual(self.host.mutations(), [("sleep", 5)] * 9)

    def test_early_unknown_then_not_ready_through_pre_wait_loads_both(self):
        self.host.bgp = {1: "Idle", 2: "Idle"}
        first_bgp = f"show bgp neighbors {PEERS[0].inside_ip} json"
        run = self.host.run
        polls = []

        def runner(args):
            status = run(args)
            if args[:4] == ["podman", "exec", "frr", "vtysh"]:
                polls.append((self.host.elapsed, args[-1]))
                if self.host.elapsed == 0 and args[-1] == first_bgp:
                    raise tunnels.CommandError("timed out after 5 s")
            return status

        def on_up(number):
            # Tunnel 1 cannot recover until both have been loaded.
            self.host.bgp[1] = "Idle" if number == 1 else "Established"

        self.host.on_up = on_up
        with patch.object(self.host, "run", side_effect=runner):
            self.assertEqual(self.deploy(), (0, ""))
        self.assertEqual(polls[:20], [(second, f"show bgp neighbors {peer.inside_ip} json")
                                     for second in range(0, 46, 5) for peer in PEERS])
        self.assertEqual(self.host.mutations(), [("sleep", 5)] * 9
                         + load_events(1) + load_events(2))
        self.assertTrue(self.record.exists())

    def test_pre_wait_unknown_then_ready_repolls_answered_order_decisions(self):
        for first_bgp in ("Established", "Idle"):
            with self.subTest(first_bgp=first_bgp):
                self.host = FakeHost(self, self.directory)
                self.host.bgp = {1: "Idle", 2: "Idle"}
                commands = [("podman", "exec", "frr", "vtysh", "-c",
                             f"show bgp neighbors {peer.inside_ip} json") for peer in PEERS]
                run = self.host.run
                final_polls = 0

                def runner(args):
                    nonlocal final_polls
                    status = run(args)
                    if tuple(args) == commands[0] and self.host.elapsed == 45:
                        final_polls += 1
                        if final_polls == 1:
                            self.host.bgp[1] = first_bgp
                            raise tunnels.CommandError("timed out after 5 s")
                    return status

                def on_sleep():
                    if self.host.elapsed == 45:
                        self.host.bgp[2] = "Established"

                self.host.on_sleep = on_sleep
                with patch.object(self.host, "run", side_effect=runner), \
                        patch.object(tunnels, "confirmed_ready",
                                     wraps=tunnels.confirmed_ready) as confirmed:
                    self.assertEqual(self.deploy(), (0, ""))
                ready, not_ready = tunnels.Readiness.READY, tunnels.Readiness.NOT_READY
                # The first argument is wait_ready's result; the rest are fresh decisions.
                self.assertEqual([call.args[0] for call in confirmed.call_args_list],
                                 [ready] * 4 if first_bgp == "Established"
                                 else [ready, not_ready, ready, not_ready])
                first_load = self.host.events.index(load_events(1)[0])
                polls = [event for event in self.host.events[:first_load]
                         if event[:4] == ("podman", "exec", "frr", "vtysh")]
                decision_order = (0, 0, 1) if first_bgp == "Established" else (0, 1, 0)
                self.assertEqual(polls[-5:], commands + [commands[i] for i in decision_order])
                self.assertEqual(self.host.mutations(), [("sleep", 5)] * 9
                                 + load_events(1) + load_events(2))
                self.assertTrue(self.record.exists())

    def test_pre_wait_unknown_then_ready_repolls_unknown_order_decision_and_aborts(self):
        self.host.bgp = {1: "Idle", 2: "Idle"}
        commands = [("podman", "exec", "frr", "vtysh", "-c",
                     f"show bgp neighbors {peer.inside_ip} json") for peer in PEERS]
        run = self.host.run

        def runner(args):
            status = run(args)
            if tuple(args) == commands[0] and self.host.elapsed == 45:
                raise tunnels.CommandError("timed out after 5 s")
            return status

        def on_sleep():
            if self.host.elapsed == 45:
                self.host.bgp[2] = "Established"

        self.host.on_sleep = on_sleep
        with patch.object(self.host, "run", side_effect=runner), \
                patch.object(tunnels, "confirmed_ready", wraps=tunnels.confirmed_ready) as confirmed:
            self.assertEqual(self.deploy(), (1, f"{tunnels.NO_REPLACE}\n"))
        self.assertEqual([call.args[0] for call in confirmed.call_args_list],
                         [tunnels.Readiness.READY, tunnels.Readiness.UNKNOWN])
        polls = [event for event in self.host.events
                 if event[:4] == ("podman", "exec", "frr", "vtysh")]
        self.assertEqual(polls[-3:], commands + [commands[0]])
        self.assertEqual(self.host.mutations(), [("sleep", 5)] * 9)

    def test_unknown_polls_can_recover_during_pre_wait_and_after_mutation(self):
        for before_mutation in (True, False):
            for command in (("ipsec", "trafficstatus"),
                            ("podman", "exec", "frr", "vtysh", "-c",
                             "show bgp neighbors 169.254.10.1 json")):
                with self.subTest(before_mutation=before_mutation, command=command):
                    self.host = FakeHost(self, self.directory)
                    run = self.host.run

                    def runner(args):
                        status = run(args)
                        if before_mutation and len(self.host.events) == 2:
                            self.host.bgp[2] = "Idle"
                            self.host.failures[command] = tunnels.CommandError("poll failed")
                        return status

                    def on_up(number):
                        if not before_mutation and number == 1:
                            self.host.failures[command] = tunnels.CommandError("poll failed")

                    def on_sleep():
                        self.host.failures.clear()
                        self.host.bgp[2] = "Established"

                    self.host.on_up = on_up
                    self.host.on_sleep = on_sleep
                    with patch.object(self.host, "run", side_effect=runner):
                        self.assertEqual(self.deploy(), (0, ""))
                    self.assertTrue(self.record.exists())
                    pause = [("sleep", 5)]
                    self.assertEqual(self.host.mutations(),
                                     pause + load_events(1) + load_events(2) if before_mutation
                                     else load_events(1) + pause + load_events(2))

    def test_successful_secret_and_poll_output_is_withheld(self):
        stdout = "SYNTHETIC_SECRET_STDOUT"
        stderr = "SYNTHETIC_SECRET_STDERR"
        for command in (["ipsec", "rereadsecrets"], ["ipsec", "trafficstatus"],
                        ["podman", "exec", "frr", "vtysh", "-c",
                         "show bgp neighbors 169.254.10.1 json"]):
            with self.subTest(command=command), \
                    patch.object(tunnels.subprocess, "Popen") as popen:
                process = popen.return_value.__enter__.return_value
                process.returncode = 0
                process.communicate.return_value = (stdout, stderr)
                output, errors = io.StringIO(), io.StringIO()
                with self.subTest(entrypoint="run_command"):
                    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                        self.assertEqual(tunnels.run_command(command), stdout)
                    self.assertEqual(output.getvalue(), "")
                    self.assertEqual(errors.getvalue(), "")
                self.host = FakeHost(self, self.directory)
                run = self.host.run

                def runner(args):
                    status = run(args)
                    if args != command:
                        return status
                    if args[0] == "podman":
                        status = json.dumps({**json.loads(status), "sentinel": stdout})
                    else:
                        status += f"\n{stdout}"
                    process.communicate.return_value = (status, stderr)
                    return tunnels.run_command(args)

                with self.subTest(entrypoint="main"), \
                        patch.object(self.host, "run", side_effect=runner):
                    self.assertEqual(self.deploy(), (0, ""))

    def test_slow_commands_and_flapping_tunnels_stay_below_handler_timeout(self):
        # Each readiness result specifies trafficstatus time, vtysh time, and
        # BGP state (None means vtysh times out: 5 s plus 5 s cleanup).
        down = (5, 5, "Connect")
        quick_down = (0, 5, "Connect")
        timeout = (5, 10, None)
        up = (5, 5, "Established")
        outcomes = iter([down] * 3 + [quick_down] + [down] * 4  # pre-wait, then load-both
                        + [down] * 6 + [quick_down] * 2 + [timeout, up]  # either-ready wait
                        + [timeout] * 2  # both flap down before selecting remaining tunnels
                        + [down] * 6 + [up]  # first recovers
                        + [down] * 6 + [timeout])  # second times out
        self.host.bgp = {1: "Connect", 2: "Connect"}
        run = self.host.run
        starts = []
        current = None

        def runner(args):
            nonlocal current
            starts.append(self.host.elapsed)
            if args == ["ipsec", "trafficstatus"]:
                if len(starts) == 2:  # initial snapshot after rereadsecrets
                    self.host.elapsed += 5
                else:
                    current = next(outcomes, None)
                    if current is None:  # failure diagnostic after the final wait
                        self.host.elapsed += 10
                        raise tunnels.CommandError("trafficstatus timed out")
                    self.host.elapsed += current[0]
            elif args[:4] == ["podman", "exec", "frr", "vtysh"]:
                self.host.elapsed += current[1]
                if current[2] is None:
                    raise tunnels.CommandError("vtysh timed out")
                number = next(peer.number for peer in PEERS if peer.inside_ip in args[-1])
                self.host.bgp[number] = current[2]
            else:
                self.host.elapsed += 60
            return run(args)

        with patch.object(self.host, "run", side_effect=runner):
            result = self.deploy()
        self.assertEqual(self.host.elapsed, 750)  # decision polls must now answer
        self.assertLessEqual(self.host.elapsed, 770)
        self.assertEqual(result, (1, "ega-aws-2: its Child SA with 192.0.2.2 did not come up "
                         f"within 90 s; stopped before any further tunnel. {RETRY}\n"))
        self.assertFalse(self.record.exists())

    def test_record_format_mode_and_atomic_write_last(self):
        real_replace = os.replace
        real_fsync = os.fsync
        events = []

        def fsync(fd):
            events.append("fsync")
            self.assertFalse(self.record.exists())
            return real_fsync(fd)

        def replace(source, destination):
            events.append("replace")
            self.assertEqual(self.host.mutations(), load_events(1) + load_events(2))
            self.assertEqual(Path(source).parent, self.directory)
            self.assertEqual(destination, self.record)
            self.assertEqual(stat.S_IMODE(Path(source).stat().st_mode), 0o600)
            return real_replace(source, destination)

        with patch.object(tunnels.os, "fsync", side_effect=fsync), \
                patch.object(tunnels.os, "replace", side_effect=replace):
            self.assertEqual(self.deploy(), (0, ""))
        expected = "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path}\n"
            for path in (self.directory / "ega-aws.conf", self.directory / "ega-aws.secrets")
        )
        self.assertEqual(self.record.read_text(), expected)
        self.assertEqual(stat.S_IMODE(self.record.stat().st_mode), 0o600)
        self.assertEqual(events, ["fsync", "replace"])
        self.assertEqual(self.host.events[0], ("ipsec", "rereadsecrets"))

    def test_failed_record_write_leaves_no_record_or_temporary_file(self):
        with patch.object(tunnels.os, "replace", side_effect=OSError("rename failed")):
            result, error = self.deploy()
        self.assertEqual(result, 1)
        self.assertIn("rename failed", error)
        self.assertEqual(sorted(path.name for path in self.directory.iterdir()),
                         ["ega-aws.conf", "ega-aws.lock", "ega-aws.secrets"])


class ReadinessTests(unittest.TestCase):
    def ready(self, status, bgp, peer=PEERS[0]):
        def runner(args):
            if args == ["ipsec", "trafficstatus"]:
                return status
            self.assertEqual(args, ["podman", "exec", "frr", "vtysh", "-c",
                                   f"show bgp neighbors {peer.inside_ip} json"])
            return bgp

        return tunnels.Replacer(PEERS, runner=runner).ready(peer)

    def test_real_trafficstatus_and_bgp_captures(self):
        for number in (1, 2):
            peer = tunnels.Tunnel(number, "192.0.2.2", f"192.0.2.2{number}")
            for fixture, expected in (("established.json", tunnels.Readiness.READY),
                                      ("down.json", tunnels.Readiness.NOT_READY),
                                      ("missing.json", tunnels.Readiness.NOT_READY)):
                with self.subTest(number=number, fixture=fixture):
                    self.assertEqual(self.ready(TRAFFICSTATUS,
                                                (FIXTURES / fixture).read_text(), peer), expected)

    def test_trafficstatus_accepts_reply_codes_and_instance_suffixes(self):
        peer = tunnels.Tunnel(2, "192.0.2.2", "192.0.2.22")
        for prefix in ("", "006 "):
            for suffix in ("", "[1]"):
                with self.subTest(prefix=prefix, suffix=suffix):
                    status = "\n".join(prefix + line.replace('"ega-aws-2"',
                                                            f'"ega-aws-2"{suffix}')
                                       for line in TRAFFICSTATUS.splitlines())
                    self.assertEqual(self.ready(status, ESTABLISHED, peer), tunnels.Readiness.READY)

    def test_rekey_accepts_current_endpoint_before_or_after_stale_sa(self):
        peer = tunnels.Tunnel(2, "192.0.2.2", "192.0.2.22")
        old, current = [line for line in TRAFFICSTATUS.splitlines() if '"ega-aws-2"' in line]
        stale = old.replace("192.0.2.22", "192.0.2.99")
        for lines in ((stale, current), (current, stale)):
            with self.subTest(lines=lines):
                self.assertEqual(self.ready("\n".join(lines), ESTABLISHED, peer),
                                 tunnels.Readiness.READY)

    def test_child_sa_requires_exact_connection_and_endpoint_id(self):
        bgp = json.dumps({PEERS[0].inside_ip: {"bgpState": "Established"}})
        for connection, outside, expected in (
                ("ega-aws-1", "192.0.2.1", True),
                ("ega-aws-1", "192.0.2.10", False),
                ("ega-aws-1", "192x0x2x1", False),
                ("ega-aws-1", "192.0.2.9", False),
                ("ega-aws-10", "192.0.2.1", False),
                ("ega-aws-2", "192.0.2.1", False)):
            with self.subTest(connection=connection, outside=outside):
                status = f'006 #1: "{connection}", type=ESP, id=\'{outside}\''
                self.assertEqual(self.ready(status, bgp), tunnels.Readiness.READY if expected
                                 else tunnels.Readiness.NOT_READY)
        self.assertEqual(self.ready('"ega-aws-1", id=\'192.0.2.9\'\n'
                                    '"ega-aws-2", id=\'192.0.2.1\'', bgp),
                         tunnels.Readiness.NOT_READY)

    def test_bgp_requires_expected_neighbor_and_established_json_state(self):
        status = '006 #1: "ega-aws-1", type=ESP, id=\'192.0.2.1\''
        for bgp in ("BGP state = Established", "{", "{}", "[]", "null", "42",
                    '{"169.254.10.1": null}', '{"169.254.10.1": []}',
                    '{"169.254.10.1": {}}',
                    '{"169.254.10.1": {"bgpState": "Idle"}}',
                    '{"169.254.10.1": {"bgpState": "Active"}}',
                    '{"169.254.10.1": {"bgpState": "Connect"}}',
                    '{"169.254.10.1": {"bgpState": "OpenSent"}}',
                    '{"169.254.10.1": {"bgpState": "OpenConfirm"}}',
                    '{"169.254.20.1": {"bgpState": "Established"}}'):
            with self.subTest(bgp=bgp):
                self.assertEqual(self.ready(status, bgp), tunnels.Readiness.NOT_READY)

    def test_poll_command_failures_are_unknown(self):
        for command in (["ipsec", "trafficstatus"],
                        ["podman", "exec", "frr", "vtysh", "-c",
                         "show bgp neighbors 192.0.2.2 json"]):
            for exception in (subprocess.TimeoutExpired(command, 5),
                              subprocess.CalledProcessError(7, command, output="", stderr=""),
                              FileNotFoundError("missing executable")):
                with self.subTest(command=command, exception=exception), failed_command(exception):
                    def runner(args):
                        if args == command:
                            return tunnels.run_command(args)
                        self.assertEqual(args, ["ipsec", "trafficstatus"])
                        return TRAFFICSTATUS

                    peer = tunnels.Tunnel(1, "192.0.2.2", "192.0.2.21")
                    self.assertEqual(tunnels.Replacer(PEERS, runner=runner).ready(peer),
                                     tunnels.Readiness.UNKNOWN)

    def test_wait_ready_observes_every_poll_through_each_deadline(self):
        for peers, timeout in ((PEERS, 45), ([PEERS[0]], 90)):
            with self.subTest(timeout=timeout):
                observations = []
                elapsed = 0

                def ready(peer):
                    observations.append((elapsed, peer.number))
                    return tunnels.Readiness.NOT_READY

                def sleep(seconds):
                    nonlocal elapsed
                    self.assertEqual(seconds, 5)
                    elapsed += seconds

                replacer = tunnels.Replacer(PEERS, sleep=sleep, monotonic=lambda: elapsed)
                with patch.object(replacer, "ready", side_effect=ready):
                    self.assertEqual(replacer.wait_ready(peers, timeout), tunnels.Readiness.NOT_READY)
                self.assertEqual(observations, [(second, peer.number)
                                 for second in range(0, timeout + 1, 5)
                                 for peer in peers])

    def test_wait_deadlines_include_poll_time_and_shorten_the_last_sleep(self):
        for peers, timeout, starts, sleeps, end in (
                (PEERS, 45, list(range(0, 46, 9)), [5] * 5, 49),
                ([PEERS[0]], 90, [*range(0, 85, 7), 90], [5] * 12 + [4], 92)):
            with self.subTest(timeout=timeout):
                elapsed = 1000  # monotonic need not start at zero
                observations = []
                pauses = []

                def ready(peer):
                    nonlocal elapsed
                    observations.append((elapsed - 1000, peer.number))
                    elapsed += 2
                    return tunnels.Readiness.NOT_READY

                def sleep(seconds):
                    nonlocal elapsed
                    pauses.append(seconds)
                    elapsed += seconds

                replacer = tunnels.Replacer(PEERS, sleep=sleep, monotonic=lambda: elapsed)
                with patch.object(replacer, "ready", side_effect=ready):
                    self.assertEqual(replacer.wait_ready(peers, timeout), tunnels.Readiness.NOT_READY)
                self.assertEqual(observations, [(start + index * 2, peer.number)
                                 for start in starts for index, peer in enumerate(peers)])
                self.assertEqual(pauses, sleeps)
                self.assertEqual(elapsed, 1000 + end)


class CommandAndArgumentTests(unittest.TestCase):
    def test_signal_killed_command_fails_without_blank_detail(self):
        # A replace killed by a signal (negative status) is a failure, and blank stderr adds no ": ".
        command = ["ipsec", "replace", "ega-aws-1"]
        with failed_command(subprocess.CalledProcessError(-9, command, stderr=" \n")):
            with self.assertRaises(tunnels.CommandError) as caught:
                tunnels.run_command(command)
        self.assertEqual(str(caught.exception), "ipsec replace ega-aws-1 failed (exit status -9)")

    def test_timeout_reports_stderr_drained_after_kill(self):
        command = ["ipsec", "up", "--asynchronous", "ega-aws-1"]
        with failed_command(subprocess.TimeoutExpired(command, 60), drained=("", " late detail\n")):
            with self.assertRaises(tunnels.CommandError) as caught:
                tunnels.run_command(command)
        self.assertEqual(str(caught.exception),
                         "ipsec up --asynchronous ega-aws-1 timed out after 60 s: late detail")

    def test_commands_capture_output_with_poll_or_mutation_timeout(self):
        # Polls neither keep the lock nor get the mutation timeout.
        for command, timeout, fds in ((["ipsec", "trafficstatus"], 5, ()),
                                      (["podman", "exec", "frr", "vtysh", "-c",
                                        "show bgp neighbors 192.0.2.2 json"], 5, ()),
                                      (["ipsec", "rereadsecrets"], 60, (42,)),
                                      *((list(command), 60, (42,)) for command in load_events(1))):
            for returncode in (0, 7):
                with self.subTest(command=command, returncode=returncode), \
                        patch.object(tunnels.subprocess, "Popen") as popen:
                    process = popen.return_value.__enter__.return_value
                    process.communicate.return_value = ("status", "ignored stderr")
                    process.returncode = returncode
                    if returncode:
                        with self.assertRaisesRegex(tunnels.CommandError, "exit status 7"):
                            tunnels.run_command(command, lock_fd=42)
                    else:
                        self.assertEqual(tunnels.run_command(command, lock_fd=42), "status")
                    popen.assert_called_once_with(command, stdout=subprocess.PIPE,
                                                  stderr=subprocess.PIPE, text=True, errors="replace",
                                                  start_new_session=True, pass_fds=fds)
                    process.communicate.assert_called_once_with(timeout=timeout)

    def test_required_command_errors_include_command(self):
        command = ["ipsec", "rereadsecrets"]
        for exception, message in (
                (subprocess.TimeoutExpired(command, 60),
                 "ipsec rereadsecrets timed out after 60 s"),
                (subprocess.CalledProcessError(7, command),
                 "ipsec rereadsecrets failed (exit status 7)"),
                (FileNotFoundError("missing executable"), "ipsec rereadsecrets")):
            with self.subTest(exception=exception), \
                    failed_command(exception) as (process, killpg):
                with self.assertRaises(tunnels.CommandError) as caught:
                    tunnels.run_command(command)
                self.assertIn(message, str(caught.exception))
                self.assertNotIn("TEST_ONLY", str(caught.exception))
                if isinstance(exception, subprocess.TimeoutExpired):
                    killpg.assert_called_once_with(process.pid, signal.SIGKILL)
                    self.assertEqual(process.communicate.call_args_list, [
                        unittest.mock.call(timeout=60), unittest.mock.call(timeout=5)])

    def test_cleanup_timeout_preserves_original_command_timeout(self):
        command = ["ipsec", "rereadsecrets"]
        original = subprocess.TimeoutExpired(command, 60)
        drain = subprocess.TimeoutExpired(command, 5)
        with failed_command(original, drained=drain) as (process, killpg):
            with self.assertRaisesRegex(tunnels.CommandError, "timed out after 60 s") as caught:
                tunnels.run_command(command)
            self.assertIs(caught.exception.__cause__, original)
            killpg.assert_called_once_with(process.pid, signal.SIGKILL)
            self.assertEqual(process.communicate.call_args_list, [
                unittest.mock.call(timeout=60), unittest.mock.call(timeout=5)])

    def test_command_output_secrets_never_reach_errors_or_main_output(self):
        sentinel = "SYNTHETIC_SECRET_MUST_STAY_PRIVATE"
        drained = (f"{sentinel}_DRAIN_STDOUT", f"{sentinel}_DRAIN_STDERR")
        command = ["ipsec", "rereadsecrets"]
        for payload in (sentinel, sentinel.encode()):
            for stdout, stderr in ((payload, None), (None, payload), (payload, payload)):
                for exception in (
                        subprocess.CalledProcessError(7, command, output=stdout, stderr=stderr),
                        subprocess.TimeoutExpired(command, 60, output=stdout, stderr=stderr)):
                    with self.subTest(stdout=stdout, exception=exception), \
                            tempfile.TemporaryDirectory() as directory, \
                            failed_command(exception, drained=drained):
                        output = io.StringIO()
                        errors = io.StringIO()
                        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                            with self.assertRaises(tunnels.CommandError) as caught:
                                tunnels.run_command(command)
                            self.assertNotIn(sentinel, str(caught.exception))
                            self.assertIn("; its output is withheld, see journalctl -u ipsec",
                                          str(caught.exception))
                            self.assertEqual(tunnels.main(ARGS, runner=tunnels.run_command,
                                                         directory=Path(directory)), 1)
                        self.assertNotIn(sentinel, output.getvalue())
                        self.assertNotIn(sentinel, errors.getvalue())

    def test_poll_command_errors_exclude_output(self):
        for command in (["ipsec", "trafficstatus"],
                        ["podman", "exec", "frr", "vtysh", "-c",
                         "show bgp neighbors 169.254.10.1 json"]):
            for exception in (
                    subprocess.CalledProcessError(7, command, output="POLL_OUTPUT",
                                                  stderr="POLL_ERROR"),
                    subprocess.TimeoutExpired(command, 60, output=b"POLL_OUTPUT",
                                              stderr=b"POLL_ERROR")):
                with self.subTest(command=command, exception=exception), \
                        failed_command(exception):
                    output = io.StringIO()
                    errors = io.StringIO()
                    with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                        with self.assertRaises(tunnels.CommandError) as caught:
                            tunnels.run_command(command)
                    self.assertNotIn("POLL_", str(caught.exception))
                    self.assertNotIn("output is withheld", str(caught.exception))
                    self.assertNotIn("POLL_", output.getvalue())
                    self.assertNotIn("POLL_", errors.getvalue())

    # prctl (child subreaper) is Linux-only, like the appliance this program runs on.
    @unittest.skipUnless(sys.platform == "linux", "needs Linux prctl")
    def test_command_holds_lock_after_parent_dies(self):
        libc = ctypes.CDLL(None)
        was_subreaper = ctypes.c_int()
        self.assertEqual(libc.prctl(37, ctypes.byref(was_subreaper), 0, 0, 0), 0)
        self.assertEqual(libc.prctl(36, 1, 0, 0, 0), 0)
        self.addCleanup(libc.prctl, 36, was_subreaper.value, 0, 0, 0)
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            (directory / "ega-aws.conf").write_bytes(b"test configuration\n")
            (directory / "ega-aws.secrets").write_bytes(b"TEST_ONLY\n")
            pidfile = directory / "command.pid"
            wrapper = directory / "ipsec"
            wrapper.write_text(
                '#!/bin/sh\n[ "$1" = replace ] || exit 0\n'
                'exec "$EGA_TEST_PYTHON" -c \'import os, sys, time; from pathlib import Path; '
                'Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)\' "$EGA_TEST_PIDFILE"\n'
            )
            wrapper.chmod(0o700)
            parent_code = (
                "import importlib.util, sys; from pathlib import Path; "
                "spec = importlib.util.spec_from_file_location('ega_aws_tunnels', sys.argv[1]); "
                "module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); "
                "sys.exit(module.main(sys.argv[3:], directory=Path(sys.argv[2])))"
            )
            with subprocess.Popen([sys.executable, "-c", parent_code, str(PROGRAM),
                                   str(directory), *ARGS],
                                  env={**os.environ, "PATH": f"{directory}:{os.environ['PATH']}",
                                       "EGA_TEST_PYTHON": sys.executable,
                                       "EGA_TEST_PIDFILE": str(pidfile)}) as parent:
                try:
                    deadline = time.monotonic() + 5
                    pid = ""
                    while time.monotonic() < deadline and parent.poll() is None:
                        if pidfile.exists():
                            pid = pidfile.read_text()
                            if pid:
                                break
                        time.sleep(0.01)
                    self.assertTrue(pid, "replacement command did not start")
                    parent.send_signal(signal.SIGHUP)
                    self.assertEqual(parent.wait(timeout=5), -signal.SIGHUP)
                    child_pid = int(pid)
                    os.kill(child_pid, 0)
                    with (directory / "ega-aws.lock").open("a") as lock:
                        with self.assertRaises(BlockingIOError):
                            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                        os.kill(child_pid, signal.SIGTERM)
                        reaped, status = os.waitpid(child_pid, 0)
                        self.assertEqual(reaped, child_pid)
                        self.assertEqual(os.waitstatus_to_exitcode(status), -signal.SIGTERM)
                        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                finally:
                    if parent.poll() is None:
                        parent.kill()
                    parent.wait(timeout=5)
                    if pidfile.exists():
                        pid = pidfile.read_text()
                        if pid:
                            try:
                                os.kill(int(pid), signal.SIGKILL)
                                os.waitpid(int(pid), 0)
                            except (ProcessLookupError, ChildProcessError):
                                pass

    # prctl (child subreaper) is Linux-only, like the appliance this program runs on.
    @unittest.skipUnless(sys.platform == "linux", "needs Linux prctl")
    def test_timeout_kills_command_descendants(self):
        # Adopt and reap grandchildren even when the CI container's PID 1 does not.
        libc = ctypes.CDLL(None)
        was_subreaper = ctypes.c_int()
        self.assertEqual(libc.prctl(37, ctypes.byref(was_subreaper), 0, 0, 0), 0)
        self.assertEqual(libc.prctl(36, 1, 0, 0, 0), 0)  # PR_SET_CHILD_SUBREAPER
        self.addCleanup(libc.prctl, 36, was_subreaper.value, 0, 0, 0)
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory) / "children.pid"
            command = ["sh", "-c", 'sleep 30 & first=$!; sleep 30 & second=$!; '
                       'printf "%s\\n%s\\n" "$first" "$second" > "$1"; wait',
                       "timeout-test", str(pidfile)]
            try:
                with patch.object(tunnels, "COMMAND_TIMEOUT", 0.5):
                    with self.assertRaisesRegex(tunnels.CommandError, "timed out after 0.5 s"):
                        tunnels.run_command(command)
                pids = [int(pid) for pid in pidfile.read_text().splitlines()]
                self.assertEqual(len(pids), 2)
                for pid in pids:
                    deadline = time.monotonic() + 2
                    while time.monotonic() < deadline:
                        try:
                            reaped, status = os.waitpid(pid, os.WNOHANG)
                        except ChildProcessError:
                            break
                        if reaped:
                            self.assertEqual(os.waitstatus_to_exitcode(status), -signal.SIGKILL)
                            break
                        time.sleep(0.01)
                    with self.assertRaises(ProcessLookupError):
                        os.kill(pid, 0)
            finally:
                if pidfile.exists():
                    for pid in map(int, pidfile.read_text().splitlines()):
                        try:
                            os.kill(pid, signal.SIGKILL)
                            os.waitpid(pid, 0)
                        except (ProcessLookupError, ChildProcessError):
                            pass

    def test_arguments_accept_each_tunnel_once_and_normalize_order(self):
        self.assertEqual(tunnels.parse_tunnels(ARGS[4:] + ARGS[:4]), PEERS)

    def test_invalid_arguments_exit_one_without_running_commands(self):
        invalid = [[], ARGS[:4], ARGS[:4] * 2, ARGS + ARGS[:4],
                   ["--tunnel", "3", *ARGS[2:]],
                   [*ARGS[:2], "::1", *ARGS[3:]],
                   [*ARGS[:3], "192.0.2.999", *ARGS[4:]],
                   [*ARGS[:2], "169.254.10.1/30", *ARGS[3:]]]
        for args in invalid:
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()), \
                    tempfile.TemporaryDirectory() as directory, \
                    patch.object(Path, "open") as open_lock, \
                    patch.object(tunnels, "run_command") as runner:
                with self.assertRaises(SystemExit) as caught:
                    tunnels.parse_tunnels(args)
                self.assertEqual(caught.exception.code, 2)
                unused_directory = Path(directory) / "absent"
                self.assertEqual(tunnels.main(args, runner=runner,
                                              directory=unused_directory), 1)
                runner.assert_not_called()
                open_lock.assert_not_called()
                self.assertFalse((unused_directory / "ega-aws.lock").exists())


POLICY_LIST = ("ip", "-s", "xfrm", "policy")
STATE_LIST = ("ip", "xfrm", "state")
LINK_LIST = ("ip", "-d", "link", "show", "type", "xfrm")
POLICY_DELETES = [
    ("ip", "xfrm", "policy", "delete", "index", index, "dir", direction,
     "ptype", "main", "if_id", if_id)
    for index, direction, if_id in (("9", "out", "0x1"), ("18", "fwd", "0x1"),
                                     ("24", "in", "0x1"), ("33", "out", "0x2"),
                                     ("42", "fwd", "0x2"), ("48", "in", "0x2"))
]
STATE_DELETES = [
    ("ip", "xfrm", "state", "delete", "src", src, "dst", dst, "proto", "esp", "spi", spi)
    for src, dst, spi in (("192.0.2.11", "192.0.2.21", "0x101"),
                          ("192.0.2.21", "192.0.2.11", "0x102"),
                          ("192.0.2.11", "192.0.2.22", "0x201"),
                          ("192.0.2.22", "192.0.2.11", "0x202"))
]
LINK_DELETES = [("ip", "link", "del", "ipsec1"), ("ip", "link", "del", "ipsec2")]
XFRM_KEY = "0xTEST_ONLY_EGA_XFRM_KEY"


class KernelHost:
    """Keep captured records until their explicitly expected delete succeeds."""

    def __init__(self, case):
        self.case = case
        self.events = []
        self.failures = set()
        self.elapsed = 0
        self.acquire_expires_at = None
        self.tables = {}
        for command, fixture, prefix, deletes in (
                (POLICY_LIST, "policy", "src ", POLICY_DELETES),
                (STATE_LIST, "state", "src ", STATE_DELETES),
                (LINK_LIST, "links", "", LINK_DELETES)):
            output = (FIXTURES / f"xfrm-{fixture}.txt").read_text()
            records = ([prefix + record for record in output.removeprefix(prefix).split("\n" + prefix)]
                       if prefix else ["21: " + output.split("21: ", 1)[1].split("22: ")[0],
                                       "22: " + output.split("22: ", 1)[1].split("27: ")[0],
                                       "27: " + output.split("27: ", 1)[1]])
            self.tables[command] = [(record, deletes[i] if i < len(deletes) else None)
                                    for i, record in enumerate(records)]

    def run(self, args):
        command = tuple(args)
        self.events.append(command)
        self.case.assertEqual(args[0], "ip", "--remove must work without pluto or ipsec")
        if command in self.failures:
            with failed_command(subprocess.CalledProcessError(
                    7, args, output=XFRM_KEY, stderr=XFRM_KEY)):
                return tunnels.run_command(args)
        if command in self.tables:
            return "\n".join(record for record, _ in self.tables[command])
        for records in self.tables.values():
            for i, (_, delete) in enumerate(records):
                if command == delete:
                    records.pop(i)
                    return ""
        self.case.fail(f"Unexpected kernel command: {args}")

    def deletes(self):
        return [event for event in self.events if event not in self.tables]

    def add_acquire(self, dst, if_id, expires_after):
        # Test-only ACQUIRE state: no keys, SPI 0, and no delete the kernel would accept.
        self.tables[STATE_LIST].append((f"src 192.0.2.11 dst {dst}\n"
                                        "\tproto esp spi 0x00000000 reqid 16392 mode transport\n"
                                        "\treplay-window 0 \n"
                                        f"\tif_id {if_id}\n\tdir out\n"
                                        f"\tsel src 192.0.2.11/32 dst {dst}/32 proto icmp type 8 code 0 \n",
                                        None))
        self.acquire_expires_at = expires_after

    def sleep(self, seconds):
        self.case.assertEqual(seconds, 1)
        self.elapsed += seconds
        if self.acquire_expires_at is not None and self.elapsed >= self.acquire_expires_at:
            self.tables[STATE_LIST] = [entry for entry in self.tables[STATE_LIST]
                                       if "spi 0x00000000" not in entry[0]]


class RemovalTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        self.host = KernelHost(self)

    def remove(self, runner=None):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            with patch.object(tunnels, "acquire_expiry", return_value=30):
                result = tunnels.main(["--remove"], runner=runner or self.host.run,
                                      sleep=self.host.sleep, monotonic=lambda: self.host.elapsed,
                                      directory=self.directory)
        self.assertNotIn(XFRM_KEY, output.getvalue() + errors.getvalue())
        return result, output.getvalue(), errors.getvalue()

    def test_busy_lock_runs_no_listing_or_deletion(self):
        real_flock = fcntl.flock

        def nonblocking(fd, operation):
            self.assertEqual(operation, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return real_flock(fd, operation)

        with (self.directory / "ega-aws.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with patch.object(tunnels.fcntl, "flock", side_effect=nonblocking):
                self.assertEqual(self.remove(), (1, "", "another replacement of the AWS IPsec "
                                 "connections is still running (or an ip command it started is "
                                 "stuck); rerun teardown after it finishes\n"))
            self.assertEqual(self.host.events, [])
        self.assertEqual(self.remove(), (0, "changed\n", ""))

    def test_deletes_inherit_lock_and_keep_its_inode(self):
        lock_path = self.directory / "ega-aws.lock"
        lock_inode = None

        def popen(args, **kwargs):
            nonlocal lock_inode
            inode = lock_path.stat().st_ino
            if lock_inode is None:
                lock_inode = inode
            self.assertEqual(inode, lock_inode)
            with lock_path.open("a") as contender:
                with self.assertRaises(BlockingIOError):
                    fcntl.flock(contender, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if tuple(args) not in self.host.tables:
                self.assertEqual(len(kwargs["pass_fds"]), 1)
                self.assertEqual(os.fstat(kwargs["pass_fds"][0]).st_ino, inode)
            else:
                self.assertEqual(kwargs["pass_fds"], ())
            process = fake_popen.return_value.__enter__.return_value
            process.returncode = 0
            process.communicate.return_value = (self.host.run(args), XFRM_KEY)
            return fake_popen.return_value

        output, errors = io.StringIO(), io.StringIO()
        with patch.object(tunnels.subprocess, "Popen", side_effect=popen) as fake_popen, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            self.assertEqual(tunnels.main(["--remove"], directory=self.directory), 0)
        self.assertEqual((output.getvalue(), errors.getvalue()), ("changed\n", ""))
        self.assertEqual(lock_path.stat().st_ino, lock_inode)
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_marked_policy_and_state_keep_lookup_mark(self):
        for listing, delete in ((POLICY_LIST, POLICY_DELETES[0]), (STATE_LIST, STATE_DELETES[0])):
            with self.subTest(listing=listing):
                self.host = KernelHost(self)
                record, _ = self.host.tables[listing][0]
                marked = (*delete, "mark", "0x100", "mask", "0xffffff00")
                self.host.tables[listing][0] = (record + "\tmark 0x100/0xffffff00\n", marked)
                self.assertEqual(self.remove(), (0, "changed\n", ""))
                self.assertIn(marked, self.host.deletes())

    def test_colliding_state_is_refused_and_other_deletes_continue(self):
        for if_id in ("\tif_id 0x7\n", "", "\tif_id 0x2\n"):
            for marked in (False, True):
                with self.subTest(if_id=if_id, marked=marked):
                    self.host = KernelHost(self)
                    record, delete = self.host.tables[STATE_LIST][0]
                    mark = "\tmark 0x100/0xffffffff\n" if marked else ""
                    self.host.tables[STATE_LIST][0] = (record + mark, delete)
                    # Source and if_id do not participate in the kernel's ESP delete lookup.
                    foreign = ("src 192.0.2.99 dst 192.0.2.21\n"
                               "\tproto esp spi 0x101 reqid 17000 mode tunnel\n"
                               f"\taead rfc4106(gcm(aes)) {XFRM_KEY} 128\n" + if_id + mark)
                    self.host.tables[STATE_LIST].append((foreign, None))
                    self.assertEqual(self.remove(), (1, "changed\n",
                                     "ip xfrm state delete: ambiguous state identity\n"))
                    self.assertEqual(self.host.deletes(),
                                     POLICY_DELETES + STATE_DELETES[1:] + LINK_DELETES)

    def test_output_mark_alone_is_not_a_lookup_mark(self):
        for listing, delete in ((POLICY_LIST, POLICY_DELETES[0]), (STATE_LIST, STATE_DELETES[0])):
            with self.subTest(listing=listing):
                self.host = KernelHost(self)
                record, _ = self.host.tables[listing][0]
                record = record.replace("\toutput-mark 0x1/0xffffffff\n", "")
                self.host.tables[listing][0] = (record + "\toutput-mark 0x100/0xffffffff\n", delete)
                self.assertEqual(self.remove(), (0, "changed\n", ""))
                self.assertIn(delete, self.host.deletes())

    def test_state_lookup_marks_control_collisions(self):
        for other_mark, ambiguous in (("0x200/0xffffffff", False),
                                      ("0x100/0xff00", True), (None, True)):
            with self.subTest(other_mark=other_mark):
                self.host = KernelHost(self)
                record, delete = self.host.tables[STATE_LIST][0]
                marked_delete = (*delete, "mark", "0x100", "mask", "0xffffff00")
                self.host.tables[STATE_LIST][0] = (record + "\tmark 0x100/0xffffff00\n", marked_delete)
                foreign = record.replace("if_id 0x1", "if_id 0x7")
                if other_mark:
                    foreign += f"\tmark {other_mark}\n"
                self.host.tables[STATE_LIST].append((foreign, None))
                self.assertEqual(self.remove(), (1, "changed\n",
                                 "ip xfrm state delete: ambiguous state identity\n") if ambiguous
                                 else (0, "changed\n", ""))
                self.assertEqual(self.host.deletes(), POLICY_DELETES
                                 + ([] if ambiguous else [marked_delete])
                                 + STATE_DELETES[1:] + LINK_DELETES)

    def test_if_id_prefix_is_not_owned(self):
        for listing, deletes in ((POLICY_LIST, POLICY_DELETES), (STATE_LIST, STATE_DELETES),
                                  (LINK_LIST, LINK_DELETES)):
            for if_id in ("0x10", "0x11"):
                with self.subTest(listing=listing, if_id=if_id):
                    self.host = KernelHost(self)
                    record, _ = self.host.tables[listing][0]
                    self.host.tables[listing][0] = (record.replace("if_id 0x1", f"if_id {if_id}"), None)
                    self.assertEqual(self.remove(), (0, "changed\n", ""))
                    self.assertEqual(self.host.deletes(), [command for command in
                                     POLICY_DELETES + STATE_DELETES + LINK_DELETES
                                     if command != deletes[0]])

    def test_real_leftovers_preserve_foreign_and_pluto_defaults(self):
        defaults = self.host.tables[POLICY_LIST][6:]
        foreign_state = self.host.tables[STATE_LIST][-1:]
        foreign_link = self.host.tables[LINK_LIST][-1:]
        self.assertEqual(self.remove(), (0, "changed\n", ""))
        self.assertEqual(self.host.deletes(), POLICY_DELETES + STATE_DELETES + LINK_DELETES)
        self.assertEqual(self.host.tables[POLICY_LIST], defaults)
        self.assertEqual(self.host.tables[STATE_LIST], foreign_state)
        self.assertEqual(self.host.tables[LINK_LIST], foreign_link)
        self.assertGreaterEqual(sum("socket " in record for record, _ in defaults), 8)
        self.assertEqual(sum("proto ipv6-icmp" in record for record, _ in defaults), 6)

    def test_second_removal_is_unchanged(self):
        self.assertEqual(self.remove(), (0, "changed\n", ""))
        self.host.events.clear()
        self.assertEqual(self.remove(), (0, "unchanged\n", ""))
        self.assertEqual(self.host.deletes(), [])

    def test_partial_leftovers_without_pluto(self):
        for listing, deletes in ((POLICY_LIST, POLICY_DELETES), (STATE_LIST, STATE_DELETES),
                                  (LINK_LIST, LINK_DELETES)):
            with self.subTest(listing=listing):
                self.host = KernelHost(self)
                for command in self.host.tables:
                    if command != listing:
                        self.host.tables[command] = []
                self.assertEqual(self.remove(), (0, "changed\n", ""))
                self.assertEqual(self.host.deletes(), deletes)

    def test_link_requires_reserved_name_xfrm_type_and_matching_id(self):
        for before, after in (("ipsec1@NONE", "ipsec11@NONE"), ("xfrm if_id", "dummy if_id"),
                              ("if_id 0x1", "if_id 0x2"), ("ipsec1@NONE", "ipsec10@NONE")):
            with self.subTest(after=after):
                self.host = KernelHost(self)
                record, _ = self.host.tables[LINK_LIST][0]
                self.host.tables[LINK_LIST][0] = (record.replace(before, after), None)
                self.assertEqual(self.remove(), (0, "changed\n", ""))
                self.assertNotIn(LINK_DELETES[0], self.host.deletes())
                self.assertIn(LINK_DELETES[1], self.host.deletes())

    def test_policy_index_and_type_disambiguate_identical_selectors(self):
        record, _ = self.host.tables[POLICY_LIST][0]
        record = record.replace("index 9", "index 65").replace("ptype main", "ptype sub")
        extra = list(POLICY_DELETES[0])
        extra[5], extra[9] = "65", "sub"
        self.host.tables[POLICY_LIST].append((record, tuple(extra)))
        self.assertEqual(self.remove(), (0, "changed\n", ""))
        self.assertEqual(self.host.deletes()[:7], POLICY_DELETES + [tuple(extra)])

    def test_delete_failures_attempt_later_items_and_return_nonzero(self):
        failures = [POLICY_DELETES[1], STATE_DELETES[1], LINK_DELETES[0]]
        self.host.failures.update(failures)
        result, output, errors = self.remove()
        self.assertEqual((result, output), (1, "changed\n"))
        self.assertEqual(self.host.deletes(), POLICY_DELETES + STATE_DELETES + LINK_DELETES)
        self.assertEqual(errors, "ip xfrm policy delete failed (exit status 7); "
                         "ip xfrm state delete failed (exit status 7); "
                         "ip link del failed (exit status 7)\n")
        self.host.failures.clear()
        self.assertEqual(self.remove(), (0, "changed\n", ""))
        self.assertEqual(self.remove(), (0, "unchanged\n", ""))

    def test_acquire_states_are_not_deleted_and_are_waited_out(self):
        # Pings hit an if_id policy after `ipsec delete` removed its SAs: two ACQUIRE states for one tunnel.
        self.host.add_acquire("192.0.2.31", "0x2", expires_after=12)
        self.host.add_acquire("192.0.2.32", "0x2", expires_after=12)
        self.assertEqual(self.remove(), (0, "changed\n", ""))
        self.assertEqual(self.host.deletes(), POLICY_DELETES + STATE_DELETES + LINK_DELETES)
        self.assertEqual(self.host.elapsed, 12)

    def test_acquire_states_that_outlive_the_kernel_expiry_fail(self):
        self.host.add_acquire("192.0.2.31", "0x1", expires_after=None)
        self.assertEqual(self.remove(), (1, "changed\n", "1 IPsec ACQUIRE states with if_id 1 or 2 "
                                         "did not expire within 35 s\n"))
        self.assertEqual(self.host.elapsed, 35)

    def test_foreign_acquire_states_are_not_waited_for(self):
        self.host.add_acquire("192.0.2.31", "0x7", expires_after=None)
        self.assertEqual(self.remove(), (0, "changed\n", ""))
        self.assertEqual(self.host.elapsed, 0)

    def test_listing_failure_still_attempts_other_kinds(self):
        for listing, skipped in ((POLICY_LIST, POLICY_DELETES), (STATE_LIST, STATE_DELETES),
                                  (LINK_LIST, LINK_DELETES)):
            with self.subTest(listing=listing):
                self.host = KernelHost(self)
                self.host.failures.add(listing)
                result, output, errors = self.remove()
                self.assertEqual((result, output), (1, "changed\n"))
                self.assertIn("exit status 7", errors)
                self.assertEqual(self.host.deletes(), [command for command in
                                 POLICY_DELETES + STATE_DELETES + LINK_DELETES if command not in skipped])

    def test_successful_state_listing_never_prints_keys(self):
        real_run = tunnels.run_command
        with patch.object(tunnels.subprocess, "Popen") as popen:
            process = popen.return_value.__enter__.return_value
            process.returncode = 0

            def runner(args, **kwargs):
                process.communicate.return_value = (self.host.run(args), XFRM_KEY)
                return real_run(args, **kwargs)

            output, errors = io.StringIO(), io.StringIO()
            with patch.object(tunnels, "run_command", side_effect=runner), \
                    patch.object(sys, "argv", [str(PROGRAM), "--remove"]), \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                self.assertEqual(tunnels.main(directory=self.directory), 0)
            self.assertEqual(output.getvalue(), "changed\n")
            self.assertEqual(errors.getvalue(), "")

    def check_secret_failure(self, command):
        for exception in (subprocess.CalledProcessError(7, command,
                                                       output=XFRM_KEY, stderr=XFRM_KEY),
                          subprocess.TimeoutExpired(command, 60,
                                                    output=XFRM_KEY.encode(), stderr=XFRM_KEY.encode())):
            with self.subTest(exception=exception), failed_command(exception):
                output, errors = io.StringIO(), io.StringIO()
                with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
                    with self.assertRaises(tunnels.CommandError) as caught:
                        tunnels.run_command(list(command))
                self.assertNotIn(XFRM_KEY, str(caught.exception) + output.getvalue() + errors.getvalue())
                self.host = KernelHost(self)

                def runner(args):
                    if tuple(args) == command:
                        return tunnels.run_command(args)
                    return self.host.run(args)

                result, stdout, stderr = self.remove(runner)
                self.assertEqual((result, stdout), (1, "changed\n"))
                self.assertIn("ip xfrm state", stderr)

    def test_state_delete_failure_never_exposes_keys(self):
        self.check_secret_failure(STATE_DELETES[1])

    def test_state_listing_failure_never_exposes_keys(self):
        self.check_secret_failure(STATE_LIST)


if __name__ == "__main__":
    unittest.main()
