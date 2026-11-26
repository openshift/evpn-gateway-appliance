#!/usr/bin/env python3
from __future__ import annotations

import ctypes
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NamedTuple


class BinaryReport(NamedTuple):
    container: str
    name: str
    args: tuple[str, ...]


REPORTS = (
    BinaryReport("frr", "/usr/lib/frr/bgpd", ("--version",)),
    BinaryReport("frr", "/usr/lib/frr/bfdd", ("--version",)),
    BinaryReport("node_exporter", "node_exporter", ("--version",)),
    BinaryReport("frr", "/frr-metrics", ()),
)
UNITS = (
    "payload-load.service",
    "frr-container.service",
    "frr-metrics.service",
    "node-exporter.service",
)

FRR_CONF = """hostname ega-smoke
frr defaults traditional
service integrated-vtysh-config
log stdout
router bgp 65000
 bgp router-id 192.0.2.1
"""

REPORT_SHELL = """name=$1
shift
binary=$(command -v "$name") || {
  echo "missing binary: $name" >&2
  exit 1
}
test -x "$binary" || {
  echo "binary is not executable: $binary" >&2
  exit 1
}
TZ=UTC stat -L --printf='path=%n\\nsize_bytes=%s\\nmodified=%y\\nmode=%A\\n' "$binary"
sha256sum "$binary"
if [ "$#" -gt 0 ]; then
  "$binary" "$@" 2>&1
fi
"""

METRICS_PY = (
    'import urllib.request; print(urllib.request.urlopen("http://127.0.0.1:9100/metrics",'
    ' timeout=5).read().decode())'
)
# urlopen raises on an HTTP error status. The smoke config has no BGP peers, so no
# particular frrk8s_ series is required.
FRR_METRICS_PY = (
    'import urllib.request; urllib.request.urlopen("http://127.0.0.1:7573/metrics", timeout=5)'
)


def exec_in(
    container_id: str,
    args: list[str],
    *,
    stdout_capture: list[str] | None = None,
) -> int:
    proc = subprocess.run(
        ["podman", "exec", container_id, *args],
        stderr=subprocess.PIPE,
        stdout=subprocess.PIPE if stdout_capture is not None else None,
    )
    if proc.returncode == 0:
        if stdout_capture is not None and proc.stdout is not None:
            stdout_capture.append(proc.stdout.decode())
        return 0
    stderr_text = proc.stderr.decode() if proc.stderr else ""
    if "state improper" in stderr_text:
        sys.stderr.write(stderr_text)
        return 2
    return 1


def wait_driver(container_id: str) -> int:
    driver = ""
    for _ in range(60):
        proc = subprocess.run(
            [
                "podman",
                "exec",
                container_id,
                "podman",
                "info",
                "--format",
                "{{.Store.GraphDriverName}}",
            ],
            stderr=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
        )
        if proc.returncode == 0 and proc.stdout:
            driver = proc.stdout.decode().strip()
        else:
            driver = ""
        if driver == "vfs":
            return 0
        time.sleep(1)
    label = driver if driver else "unknown"
    print(f"podman graph driver is {label}, want vfs", file=sys.stderr)
    return 1


def ready(container_id: str) -> int:
    for unit in UNITS:
        rc = exec_in(container_id, ["systemctl", "is-active", "--quiet", unit])
        if rc != 0:
            return rc
    rc = exec_in(
        container_id,
        ["podman", "exec", "frr", "vtysh", "-c", "show bgp summary"],
    )
    if rc != 0:
        return rc
    metrics: list[str] = []
    rc = exec_in(
        container_id,
        ["python3", "-c", METRICS_PY],
        stdout_capture=metrics,
    )
    if rc != 0:
        return rc
    body = metrics[0] if metrics else ""
    if not any(
        line.startswith("node_exporter_build_info{") for line in body.splitlines()
    ):
        return 1
    return exec_in(container_id, ["python3", "-c", FRR_METRICS_PY])


def wait_ready(container_id: str) -> int:
    for _ in range(60):
        rc = ready(container_id)
        if rc == 0:
            return 0
        if rc == 2:
            print(
                "container exited before FRR, frr-metrics and node-exporter were ready",
                file=sys.stderr,
            )
            return 1
        time.sleep(1)
    print("FRR, frr-metrics and node-exporter did not become ready", file=sys.stderr)
    return 1


def report(container_id: str, entry: BinaryReport) -> int:
    print(f"Binary inventory for container {entry.container}:")
    proc = subprocess.run(
        [
            "podman",
            "exec",
            "-i",
            container_id,
            "podman",
            "exec",
            "-i",
            entry.container,
            "sh",
            "-es",
            "--",
            entry.name,
            *entry.args,
        ],
        input=REPORT_SHELL,
        text=True,
    )
    return proc.returncode


def cleanup(
    container_id: str,
    config_dir: str | None,
    status: int,
) -> None:
    if container_id:
        if status != 0:
            subprocess.run(
                ["podman", "logs", container_id],
                stdout=sys.stderr,
                stderr=sys.stderr,
            )
            subprocess.run(
                [
                    "podman",
                    "exec",
                    container_id,
                    "journalctl",
                    "--no-pager",
                    "-n",
                    "80",
                    "-u",
                    "payload-load.service",
                    "-u",
                    "frr-container.service",
                    "-u",
                    "frr-metrics.service",
                    "-u",
                    "node-exporter.service",
                ],
                stdout=sys.stderr,
                stderr=sys.stderr,
            )
        subprocess.run(
            ["podman", "rm", "-f", container_id],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    if config_dir and os.path.isdir(config_dir):
        shutil.rmtree(config_dir)


def main() -> None:
    sys.stdout.reconfigure(line_buffering=True)
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} IMAGE", file=sys.stderr)
        sys.exit(2)

    image = sys.argv[1]

    if shutil.which("podman") is None:
        print("prerequisite unavailable: podman", file=sys.stderr)
        sys.exit(2)

    proc = subprocess.run(
        [
            "podman",
            "info",
            "--format",
            "{{.Host.CgroupsVersion}} {{.Host.Security.Rootless}}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        print(
            "prerequisite unavailable: podman cannot inspect the runtime",
            file=sys.stderr,
        )
        for line in proc.stderr.decode().splitlines()[:12]:
            print(line, file=sys.stderr)
        sys.exit(2)
    cgroup_version = proc.stdout.decode().split(None, 1)[0] if proc.stdout else ""
    if cgroup_version != "v2":
        print(
            f"prerequisite unavailable: nested smoke requires cgroup v2 (got {cgroup_version})",
            file=sys.stderr,
        )
        sys.exit(2)

    libc = ctypes.CDLL(None, use_errno=True)
    fd = libc.inotify_init1(0)
    if fd < 0:
        limit_path = Path("/proc/sys/fs/inotify/max_user_instances")
        try:
            limit = limit_path.read_text().strip()
        except OSError:
            limit = "unknown"
        print(
            "prerequisite unavailable: this user cannot create an inotify instance "
            f"(fs.inotify.max_user_instances={limit}). systemd needs one to stay up as PID 1.",
            file=sys.stderr,
        )
        sys.exit(2)
    os.close(fd)

    config_dir = tempfile.mkdtemp()
    container_id = ""
    status = 0

    try:
        config_path = Path(config_dir)
        config_path.joinpath("daemons").write_text("bgpd=yes\nbfdd=yes\n")
        config_path.joinpath("frr.conf").write_text(FRR_CONF)

        run_proc = subprocess.run(
            [
                "podman",
                "run",
                "-d",
                "-t",
                "--pull=never",
                "--privileged",
                "--network",
                "none",
                "--cgroupns=host",
                "--systemd=always",
                "-v",
                f"{config_dir}:/etc/frr:Z",
                image,
                "/sbin/init",
            ],
            stdout=subprocess.PIPE,
            stderr=None,
        )
        if run_proc.returncode != 0:
            status = run_proc.returncode
            raise SystemExit(status)
        container_id = run_proc.stdout.decode().strip()

        if wait_driver(container_id) != 0 or wait_ready(container_id) != 0:
            status = 1
            raise SystemExit(status)
        for entry in REPORTS:
            rc = report(container_id, entry)
            if rc != 0:
                status = rc
                raise SystemExit(status)
        # Stop and start rather than restart: a restart hides a unit that an unclean
        # stop leaves failed.
        container_units = [unit for unit in UNITS if unit != "payload-load.service"]
        stop = subprocess.run(
            ["podman", "exec", container_id, "systemctl", "stop", *container_units],
        )
        if stop.returncode != 0:
            status = stop.returncode
            raise SystemExit(status)
        for unit in container_units:
            state: list[str] = []
            rc = exec_in(
                container_id,
                ["systemctl", "show", "-p", "ActiveState", "--value", unit],
                stdout_capture=state,
            )
            if rc != 0 or state[0].strip() != "inactive":
                print(f"{unit} did not stop cleanly", file=sys.stderr)
                status = 1
                raise SystemExit(status)
        start = subprocess.run(
            ["podman", "exec", container_id, "systemctl", "start", *container_units],
        )
        if start.returncode != 0:
            status = start.returncode
            raise SystemExit(status)
        if wait_ready(container_id) != 0:
            status = 1
            raise SystemExit(status)
        print(
            f"nested offline smoke passed for {image} "
            "(this does not qualify bootc install, upgrade, rollback, or VM boot)"
        )
    finally:
        cleanup(container_id, config_dir, status)

    sys.exit(status)


if __name__ == "__main__":
    main()
