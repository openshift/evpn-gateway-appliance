"""Tests for the overlay path probe (ansible/roles/evpn_monitoring/files/ega-path-probe.py)."""
import importlib.util
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "ansible", "roles",
                      "evpn_monitoring", "files", "ega-path-probe.py")
_spec = importlib.util.spec_from_file_location("ega_path_probe", SCRIPT)
probe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(probe)

SUMMARY = "3 packets transmitted, 3 received, 0% packet loss, time 2003ms\n"
RTT_LINE = "rtt min/avg/max/mdev = 0.100/1.250/2.000/0.300 ms\n"
# iputils prints the rtt line whenever any reply arrived, even when the run fails.
PARTIAL = "5 packets transmitted, 1 received, 80% packet loss, time 4005ms\n" \
          "rtt min/avg/max/mdev = 0.900/0.900/0.900/0.000 ms\n"
PROMTOOL = shutil.which(os.environ.get("PROMTOOL", "promtool"))


class PathProbeTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        self.out = os.path.join(self.dir, "out.prom")
        self.sleeps = []

    def run_probe(self, rc, stdout="", target="192.0.2.1", elapsed=2.0):
        def sleep(seconds):
            self.sleeps.append(seconds)
            self.written_before_pace = os.path.exists(self.out)

        reply = subprocess.CompletedProcess([], rc, stdout=stdout)
        with mock.patch.object(probe.subprocess, "run", return_value=reply) as run, \
                mock.patch.object(probe.time, "monotonic", side_effect=[100.0, 100.0 + elapsed]), \
                mock.patch.object(probe.time, "sleep", side_effect=sleep):
            rc = probe.main(["ega-path-probe.py", target, self.out])
        self.ping = run
        return rc

    def lines(self):
        with open(self.out) as f:
            return f.read().splitlines()

    def assert_valid_metrics(self):
        if PROMTOOL:
            with open(self.out) as f:
                subprocess.run([PROMTOOL, "check", "metrics"], stdin=f, check=True)

    def assert_no_temporary_file(self):
        self.assertEqual(sorted(os.listdir(self.dir)), ["out.prom"] if os.path.exists(self.out) else [])

    def test_success_reports_rtt_after_the_pace(self):
        self.assertEqual(self.run_probe(0, SUMMARY + RTT_LINE), 0)
        self.assertIn('ega_path_probe_success{target="192.0.2.1"} 1', self.lines())
        self.assertIn('ega_path_probe_rtt_seconds{target="192.0.2.1"} 0.001250000', self.lines())
        self.assertIn("# TYPE ega_path_probe_success gauge", self.lines())
        self.assertEqual(self.ping.call_args.args[0], ["ping", "-n", "-q", "-c", "3", "-w", "5", "192.0.2.1"])
        self.assertEqual(self.ping.call_args.kwargs["env"]["LC_ALL"], "C")
        self.assertEqual(self.ping.call_args.kwargs["stdout"], subprocess.PIPE)
        self.assertIs(self.ping.call_args.kwargs["text"], True)
        self.assertIs(self.ping.call_args.kwargs["check"], False)
        self.assertEqual(self.sleeps, [3.0])
        self.assertFalse(self.written_before_pace)
        self.assertEqual(os.stat(self.out).st_mode & 0o777, 0o644)
        self.assert_no_temporary_file()
        self.assert_valid_metrics()

    def test_failure_and_partial_loss_report_no_rtt(self):
        for stdout in ("", PARTIAL):
            with self.subTest(stdout=stdout):
                self.assertEqual(self.run_probe(1, stdout, elapsed=5.2), 0)
                self.assertIn('ega_path_probe_success{target="192.0.2.1"} 0', self.lines())
                self.assertFalse(any(line.startswith("ega_path_probe_rtt_seconds") for line in self.lines()))
                self.assertEqual(self.sleeps[-1], 0.0)
                self.assert_valid_metrics()

    def test_success_without_rtt_line_writes_no_rtt(self):
        self.assertEqual(self.run_probe(0, SUMMARY), 0)
        self.assertIn('ega_path_probe_success{target="192.0.2.1"} 1', self.lines())
        self.assertFalse(any(line.startswith("ega_path_probe_rtt_seconds") for line in self.lines()))
        self.assert_valid_metrics()

    def test_empty_target_is_rejected(self):
        self.assertNotEqual(self.run_probe(0, SUMMARY, target=""), 0)
        self.assertFalse(os.path.exists(self.out))

    # The stale-file alert reads the textfile's mtime, so a local error must not touch it.
    def test_local_ping_error_keeps_the_old_textfile(self):
        self.run_probe(0, SUMMARY + RTT_LINE)
        os.utime(self.out, (946684800, 946684800))
        before = self.lines()
        self.assertEqual(self.run_probe(2), 2)
        self.assertEqual(self.lines(), before)
        self.assertEqual(os.stat(self.out).st_mtime, 946684800)

    def test_write_error_keeps_the_old_textfile_and_cleans_up(self):
        self.run_probe(1)
        before = self.lines()
        with mock.patch.object(probe.os, "chmod", side_effect=OSError("chmod failed")), \
                self.assertRaises(OSError):
            self.run_probe(0, SUMMARY + RTT_LINE)
        self.assertEqual(self.lines(), before)
        self.assert_no_temporary_file()

    # SIGTERM and SIGHUP become SystemExit (below), which must still remove a partly written file.
    def test_exit_during_write_keeps_the_old_textfile_and_cleans_up(self):
        self.run_probe(1)
        before = self.lines()
        with mock.patch.object(probe.os, "chmod", side_effect=SystemExit(1)), \
                self.assertRaises(SystemExit):
            self.run_probe(0, SUMMARY + RTT_LINE)
        self.assertEqual(self.lines(), before)
        self.assert_no_temporary_file()

    def test_sigterm_and_sighup_exit_through_python_rather_than_dying(self):
        bin_dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, bin_dir)
        started = os.path.join(bin_dir, "started")
        with open(os.path.join(bin_dir, "ping"), "w") as f:
            f.write(f"#!/bin/sh\ntouch {started}\nexec sleep 30\n")
        os.chmod(os.path.join(bin_dir, "ping"), 0o755)
        env = {**os.environ, "PATH": bin_dir + os.pathsep + os.environ["PATH"]}
        for signum in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=signum.name):
                if os.path.exists(started):
                    os.unlink(started)
                proc = subprocess.Popen([sys.executable, "-I", SCRIPT, "192.0.2.1", self.out], env=env)
                self.addCleanup(proc.kill)
                deadline = time.monotonic() + 10
                while not os.path.exists(started) and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertTrue(os.path.exists(started), "the probe never ran ping")
                proc.send_signal(signum)
                self.assertEqual(proc.wait(timeout=10), 1)
                self.assertFalse(os.path.exists(self.out))
                self.assert_no_temporary_file()

    def test_temporary_file_is_beside_the_output(self):
        replaced = []
        real_replace = os.replace

        def replace(src, dst):
            replaced.append(os.path.dirname(src))
            self.assertFalse(src.endswith(".prom"), "the collector would read the temporary file")
            real_replace(src, dst)

        with mock.patch.object(probe.os, "replace", side_effect=replace), \
                mock.patch.dict(os.environ, {"TMPDIR": os.path.join(self.dir, "missing")}):
            self.run_probe(0, SUMMARY + RTT_LINE)
        self.assertEqual(replaced, [self.dir])


if __name__ == "__main__":
    unittest.main()
