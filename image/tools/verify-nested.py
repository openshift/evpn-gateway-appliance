#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SMOKE_DIR = Path("/tmp/ega-verify-nested-smoke")


def main() -> None:
    if len(sys.argv) > 1:
        auth = sys.argv[1]
    else:
        auth = os.environ.get(
            "CONTAINER_AUTH_FILE", str(Path.home() / ".docker/config.json")
        )

    if not Path(auth).is_file():
        print(f"prerequisite unavailable: registry auth file {auth}", file=sys.stderr)
        raise SystemExit(2)

    payloads = {}
    for name in ("FRR_IMAGE", "NODE_EXPORTER_IMAGE"):
        value = os.environ.get(name)
        if not value:
            print(
                f"prerequisite unavailable: set {name} to the pinned payload pullspec",
                file=sys.stderr,
            )
            raise SystemExit(2)
        payloads[name] = value

    base: str | None = None
    for line in (ROOT / "image/streams.yaml").read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("bootcImageCi:"):
            base = stripped.split(":", 1)[1].strip()
            break
    if base is None:
        raise SystemExit(1)

    builds = [
        [
            "make",
            "nested-ci-appliance-image",
            f"BOOTC_BASE={base}",
            f"FRR_IMAGE={payloads['FRR_IMAGE']}",
            f"NODE_EXPORTER_IMAGE={payloads['NODE_EXPORTER_IMAGE']}",
            f"CONTAINER_AUTH_FILE={auth}",
        ],
    ]
    for cmd in builds:
        rc = subprocess.run(cmd, cwd=ROOT).returncode
        if rc != 0:
            raise SystemExit(rc)

    grep_rc = subprocess.run(
        [
            "podman",
            "run",
            "--rm",
            "--pull=never",
            "--entrypoint",
            "grep",
            "localhost/evpn-appliance-rhel10:nested-ci",
            "--",
            "--no-collector.accelerator",
            "/etc/systemd/system/node-exporter.service",
        ],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
    ).returncode
    if grep_rc != 0:
        print(
            "built image is missing --no-collector.accelerator in node-exporter.service",
            file=sys.stderr,
        )
        raise SystemExit(1)

    vfs_rc = subprocess.run(
        [
            "podman",
            "run",
            "--rm",
            "--pull=never",
            "--entrypoint",
            "grep",
            "localhost/evpn-appliance-rhel10:nested-ci",
            "--",
            'driver = "vfs"',
            "/etc/containers/storage.conf.d/99-evpn-vfs.conf",
        ],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
    ).returncode
    if vfs_rc != 0:
        print(
            'built image is missing driver = "vfs" in /etc/containers/storage.conf.d/99-evpn-vfs.conf',
            file=sys.stderr,
        )
        raise SystemExit(1)

    SMOKE_DIR.mkdir(parents=True, exist_ok=True)
    with (
        open(SMOKE_DIR / "smoke.stdout", "w") as out,
        open(SMOKE_DIR / "smoke.stderr", "w") as err,
    ):
        smoke_rc = subprocess.run(
            [
                "python3",
                "image/tools/smoke-nested.py",
                "localhost/evpn-appliance-rhel10:nested-ci",
            ],
            cwd=ROOT,
            stdout=out,
            stderr=err,
        ).returncode
    (SMOKE_DIR / "smoke.exit").write_text(f"{smoke_rc}\n")
    raise SystemExit(smoke_rc)


if __name__ == "__main__":
    main()
