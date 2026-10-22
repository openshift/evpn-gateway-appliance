from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import yaml

sys.path.insert(0, str(Path(__file__).parent))

import payload

ROOT = Path(__file__).parents[1]


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def write_blob(directory: Path, data: bytes) -> str:
    value = digest(data)
    (directory / value.removeprefix("sha256:")).write_bytes(data)
    return value


def make_dir_fixture(directory: Path, architectures=("amd64", "arm64")) -> str:
    directory.mkdir(parents=True)
    children = []
    for architecture in architectures:
        archive = io.BytesIO()
        with tarfile.open(fileobj=archive, mode="w") as tar:
            content = f"fixture-{architecture}".encode()
            entry = tarfile.TarInfo("fixture")
            entry.size = len(content)
            tar.addfile(entry, io.BytesIO(content))
        layer = gzip.compress(archive.getvalue(), mtime=0)
        config = json.dumps({
            "architecture": architecture,
            "os": "linux",
            "config": {"Entrypoint": ["/fixture"], "Cmd": ["argument"], "Env": ["FIXTURE=present"]},
            "rootfs": {"type": "layers", "diff_ids": [digest(archive.getvalue())]},
        }).encode()
        config_digest = write_blob(directory, config)
        layer_digest = write_blob(directory, layer)
        child = json.dumps(
            {
                "schemaVersion": 2,
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "config": {"mediaType": "application/vnd.oci.image.config.v1+json", "digest": config_digest, "size": len(config)},
                "layers": [{"mediaType": "application/vnd.oci.image.layer.v1.tar+gzip", "digest": layer_digest, "size": len(layer)}],
            },
            separators=(",", ":"),
        ).encode()
        child_digest = digest(child)
        (directory / f"{child_digest.removeprefix('sha256:')}.manifest.json").write_bytes(child)
        children.append(
            {
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "digest": child_digest,
                "size": len(child),
                "platform": {"architecture": architecture, "os": "linux"},
            }
        )
    root = json.dumps(
        {
            "schemaVersion": 2,
            "mediaType": "application/vnd.oci.image.index.v1+json",
            "manifests": children,
        },
        separators=(",", ":"),
    ).encode()
    (directory / "manifest.json").write_bytes(root)
    (directory / "reference").write_text("localhost/test:fixture\n")
    (directory / "version").write_text("Directory Transport Version: 1.1\n")
    return digest(root)


class PayloadTests(unittest.TestCase):
    def setUp(self) -> None:
        self.enterContext(mock.patch.dict(os.environ, {
            key: value for key, value in os.environ.items() if not key.startswith("EGA_PAYLOAD_")
        }, clear=True))

    def test_renderer_is_the_single_digest_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            inventory = temporary_path / "payload.yaml"
            inventory.write_bytes((ROOT / "payload-images.yaml").read_bytes())
            first = temporary_path / "first"
            payload.render_units(inventory, "rhel10", ROOT / "rhel10", first)
            original = (first / "frr.container").read_text()
            changed = "sha256:" + "a" * 64
            document = yaml.safe_load(inventory.read_text())
            document["rhel10"]["frr"]["digest"] = changed
            document["rhel10"]["node_exporter"]["digest"] = "sha256:" + "b" * 64
            inventory.write_text(yaml.safe_dump(document))
            second = temporary_path / "second"
            payload.render_units(inventory, "rhel10", ROOT / "rhel10", second)
            self.assertIn(changed, (second / "frr.container").read_text())
            self.assertNotEqual(original, (second / "frr.container").read_text())
            self.assertIn("sha256:" + "b" * 64, (second / "node-exporter.container").read_text())
            self.assertIn("GlobalArgs=--storage-opt=additionalimagestore=/usr/lib/bootc/storage", original)

    def test_renderer_uses_complete_ci_overrides(self) -> None:
        overrides = {
            "EGA_PAYLOAD_RHEL10_FRR_REPOSITORY": "registry.example.com/frr",
            "EGA_PAYLOAD_RHEL10_FRR_TAG": "fixture",
            "EGA_PAYLOAD_RHEL10_FRR_DIGEST": "sha256:" + "c" * 64,
        }
        with tempfile.TemporaryDirectory() as temporary, mock.patch.dict(os.environ, overrides):
            destination = Path(temporary)
            payload.render_units(ROOT / "payload-images.yaml", "rhel10", ROOT / "rhel10", destination)
            self.assertIn("Image=registry.example.com/frr@sha256:" + "c" * 64,
                          (destination / "frr.container").read_text())
            with mock.patch.dict(os.environ, {"EGA_PAYLOAD_RHEL10_FRR_TAG": ""}):
                with self.assertRaisesRegex(ValueError, "incomplete"):
                    payload.render_units(ROOT / "payload-images.yaml", "rhel10", ROOT / "rhel10", destination)

    def test_renderer_rejects_missing_service_and_unresolved_token(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            inventory = temporary_path / "payload.yaml"
            inventory.write_text(
                "rhel10:\n  frr:\n    repository: example/frr\n    tag: latest\n    digest: sha256:" + "a" * 64 + "\n"
            )
            with self.assertRaisesRegex(ValueError, "missing services"):
                payload.render_units(inventory, "rhel10", ROOT / "rhel10", temporary_path / "out")
            template = temporary_path / "templates"
            template.mkdir()
            for name in ("frr.container.in", "node-exporter.container.in"):
                (template / name).write_text("Image=@UNKNOWN@\n")
            inventory.write_text(
                "rhel10:\n"
                "  frr:\n    repository: example/frr\n    tag: latest\n    digest: sha256:"
                + "a" * 64
                + "\n"
                "  node_exporter:\n    repository: example/node\n    tag: latest\n    digest: sha256:"
                + "b" * 64
                + "\n"
            )
            with self.assertRaisesRegex(ValueError, "PAYLOAD_IMAGE"):
                payload.render_units(inventory, "rhel10", template, temporary_path / "out")

    def test_cache_validation_checks_root_blobs_and_architecture(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "cache"
            root_digest = make_dir_fixture(directory)
            details = payload.validate_cache(directory, root_digest)
            self.assertEqual(details["architectures"], ["amd64", "arm64"])
            (directory / next(path.name for path in directory.iterdir() if path.name.endswith(".manifest.json"))).unlink()
            with self.assertRaisesRegex(ValueError, "missing child manifest"):
                payload.validate_cache(directory, root_digest)

    def test_cache_rejects_unknown_architecture(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "cache"
            root_digest = make_dir_fixture(directory, ("mips64",))
            with self.assertRaisesRegex(ValueError, "unknown architecture"):
                payload.validate_cache(directory, root_digest)

    def test_load_validates_everything_before_running_skopeo(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            units = temporary_path / "units"
            units.mkdir()
            cache = temporary_path / "cache"
            root_digest = make_dir_fixture(cache / "frr")
            # A valid first payload must not load before the missing second cache is rejected.
            images = []
            for name, value in (("frr", root_digest), ("node-exporter", "sha256:" + "a" * 64)):
                reference = f"registry.example.com/{name}@{value}"
                (units / f"{name}.container").write_text(f"Image={reference}\n")
                images.append({
                    "unit": f"{name}.container", "reference": reference,
                    "cache_path": name, "digest": value,
                    "native_architecture": "amd64", "os": "linux",
                })
            (cache / "index.json").write_text(json.dumps({"version": 1, "images": images}))
            runner = mock.Mock(side_effect=AssertionError("loader ran before validation"))
            with self.assertRaisesRegex(ValueError, "missing .*manifest"):
                payload.load_images(cache, units, runner=runner)
            runner.assert_not_called()

    def test_loader_keeps_index_reference_and_rejects_unresolved_digest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            cache = directory / "cache"
            root_digest = make_dir_fixture(cache / "frr")
            reference = "registry.example.com/frr@" + root_digest
            units = directory / "units"
            units.mkdir()
            (units / "frr.container").write_text(f"[Container]\nImage={reference}\n")
            (cache / "index.json").write_text(json.dumps({
                "version": 1,
                "images": [{"unit": "frr.container", "reference": reference, "digest": root_digest,
                            "cache_path": "frr", "native_architecture": "amd64", "os": "linux"}],
            }))
            record = {"Architecture": "amd64", "Os": "linux", "RepoDigests": [reference],
                      "Digest": "sha256:" + "0" * 64}
            runner = mock.Mock(return_value=subprocess.CompletedProcess([], 0, json.dumps([record])))
            payload.load_images(cache, units, runner=runner)
            copy = runner.call_args_list[0].args[0]
            inspect = runner.call_args_list[1].args[0]
            self.assertEqual(copy[-2:], [f"dir:{cache / 'frr'}", f"containers-storage:{reference}"])
            self.assertEqual(inspect[-1], reference)
            record["RepoDigests"] = []
            runner.return_value.stdout = json.dumps([record])
            with self.assertRaisesRegex(ValueError, "expected digest"):
                payload.load_images(cache, units, runner=runner)

    @unittest.skipUnless(shutil.which("skopeo"), "skopeo is required for the transport proof")
    def test_skopeo_preserves_index_and_child_manifests(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            destination = Path(temporary) / "destination"
            root_digest = make_dir_fixture(source)
            subprocess.run(
                [
                    "skopeo",
                    "--insecure-policy",
                    "copy",
                    "--all",
                    "--preserve-digests",
                    f"dir:{source}",
                    f"dir:{destination}",
                ],
                check=True,
                text=True,
                capture_output=True,
            )
            self.assertEqual(digest((destination / "manifest.json").read_bytes()), root_digest)
            self.assertEqual(
                sorted(path.name for path in source.glob("*.manifest.json")),
                sorted(path.name for path in destination.glob("*.manifest.json")),
            )
            for architecture in ("amd64", "arm64"):
                result = subprocess.run(
                    ["skopeo", "--override-arch", architecture, "inspect", "--config", f"dir:{destination}"],
                    check=True, text=True, capture_output=True,
                )
                config = json.loads(result.stdout)
                self.assertEqual(config["architecture"], architecture)
                self.assertEqual(config["config"]["Entrypoint"], ["/fixture"])
                self.assertEqual(config["config"]["Cmd"], ["argument"])
                self.assertEqual(config["config"]["Env"], ["FIXTURE=present"])

    def test_cache_rejects_corrupt_layer(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "cache"
            root_digest = make_dir_fixture(directory)
            child = json.loads(next(directory.glob("*.manifest.json")).read_text())
            layer = directory / child["layers"][0]["digest"].removeprefix("sha256:")
            layer.write_bytes(b"corrupted")
            with self.assertRaisesRegex(ValueError, "wrong digest"):
                payload.validate_cache(directory, root_digest)

    def test_renderer_rejects_tagged_repository_and_missing_digest(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            inventory = Path(temporary) / "inventory.yaml"
            document = yaml.safe_load((ROOT / "payload-images.yaml").read_text())
            document["rhel10"]["frr"]["repository"] += ":latest"
            inventory.write_text(yaml.safe_dump(document))
            with self.assertRaisesRegex(ValueError, "untagged registry path"):
                payload.load_inventory(inventory, "rhel10")
            document["rhel10"]["frr"]["repository"] = "registry.example.com/frr"
            document["rhel10"]["frr"]["digest"] = ""
            inventory.write_text(yaml.safe_dump(document))
            with self.assertRaisesRegex(ValueError, "non-empty"):
                payload.load_inventory(inventory, "rhel10")

    @unittest.skipUnless(Path("/usr/libexec/podman/quadlet").exists(), "quadlet is required")
    def test_ci_dropins_remove_bootc_store_from_generated_start(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            units = temporary_path / "units"
            units.mkdir()
            payload.render_units(ROOT / "payload-images.yaml", "rhel10", ROOT / "rhel10", units)
            system_units = temporary_path / "system"
            for unit in ("frr", "node-exporter"):
                dropin = system_units / f"{unit}.container.d"
                dropin.mkdir(parents=True)
                shutil.copy(ROOT / "ci/ega-payload-dropin.conf", dropin / "ci.conf")
            result = subprocess.run(
                ["/usr/libexec/podman/quadlet", "-dryrun"],
                env={**os.environ, "QUADLET_UNIT_DIRS": f"{system_units}:{units}"},
                check=True,
                text=True,
                capture_output=True,
            )
            starts = [line for line in result.stdout.splitlines() if line.startswith("ExecStart=")]
            self.assertEqual(len(starts), 2)
            self.assertTrue(all("--pull never" in line for line in starts))
            self.assertTrue(all("additionalimagestore" not in line for line in starts))
            self.assertEqual(result.stdout.count("Requires=ega-payload-load.service"), 2)
            self.assertEqual(result.stdout.count("After=ega-payload-load.service"), 2)

    def test_smoke_lifecycle_and_failure_reporting(self) -> None:
        fake_podman = '''#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path
args = sys.argv[1:]
mode = os.environ["TEST_SMOKE_MODE"]
with open(os.environ["TEST_SMOKE_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
state = Path(os.environ["TEST_SMOKE_STATE"])
restarted = state.with_suffix(".restarted")
if args[0] == "info":
    print("v1 false" if mode == "old-cgroups" else "v2 true" if mode == "rootless" else "v2 false")
elif args[0] == "run":
    assert "--pull=never" in args and args[args.index("--network") + 1] == "none"
    state.write_text(args[args.index("--name") + 1])
    if mode in ("signal", "interrupt"):
        os.kill(os.getppid(), signal.SIGTERM if mode == "signal" else signal.SIGINT)
    if mode.startswith("cancelled-output"):
        time.sleep(30)
    sys.exit(17 if mode.startswith("failed-run") else 0)
elif args[0] == "rm":
    assert args[-1] == state.read_text()
    # Native Podman can raise SIGPIPE when a stop warning reaches a closed reader.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)
    os.write(2, b"stopping smoke container\\n")
    if mode in ("failed-cleanup", "failed-run-and-cleanup", "cancelled-output-failed-cleanup"):
        sys.exit(19)
    if mode == "hung-cleanup":
        time.sleep(30)
    state.unlink()
    print(args[-1])
elif args[0] == "inspect" and mode == "cancelled-diagnostics":
    time.sleep(30)
elif args[0] == "exec":
    cmd = args[3:] if args[1] == "-i" else args[2:]
    if cmd[:2] == ["systemctl", "is-active"]:
        assert len(cmd) == 4, "must check one service at a time"
        if mode == "cancelled-probe":
            time.sleep(30)
        sys.exit(1 if mode in ("failed-service", "cancelled-diagnostics") and cmd[-1] == "frr.service" else 0)
    elif cmd[:4] == ["podman", "exec", "frr", "vtysh"]:
        assert cmd[4:] == ["-c", "show bgp ipv4 unicast json"]
        if mode == "failed-frr":
            sys.exit(1)
        if mode == "hung-frr":
            time.sleep(30)
        bgp = {"localAS": 65000, "routerId": "192.0.2.1"}
        if mode == "unconfigured-frr":
            bgp = {"warning": "Default BGP instance not found"}
        elif mode == "wrong-frr-asn":
            bgp["localAS"] = 65001
        elif mode == "wrong-frr-router-id":
            bgp["routerId"] = "192.0.2.2"
        print("invalid JSON" if mode == "malformed-frr" else json.dumps(bgp))
    elif cmd[0] == "python3":
        os.execv(sys.executable, [sys.executable, *cmd[1:]])
    elif cmd[:2] == ["podman", "info"]:
        print("overlay" if mode == "wrong-driver" else "vfs", 2 if mode == "inherited-store" else 0)
    elif cmd[:2] == ["systemctl", "restart"]:
        if mode == "hung-restart":
            time.sleep(30)
        restarted.touch()
    elif cmd[0] == "curl":
        assert cmd[1:3] == ["--noproxy", "*"], "loopback metrics must bypass inherited proxies"
        print('unrelated_metric 1' if mode == "failed-restart-metrics" and restarted.exists()
              else 'node_exporter_build_info{version="fixture"} 1')
    elif cmd[0] not in ("journalctl", "systemctl"):
        sys.exit(3)
'''
        expected = {
            "success": 0, "failed-service": 1, "failed-frr": 1,
            "unconfigured-frr": 1, "wrong-frr-asn": 1, "wrong-frr-router-id": 1, "malformed-frr": 1,
            "failed-run": 17, "failed-cleanup": 1, "failed-run-and-cleanup": 17,
            "failed-artifact-open": 1, "failed-artifact-write": 1,
            "failed-run-and-artifact-open": 17, "failed-run-and-artifact-write": 17,
            "failed-restart-metrics": 1,
            "rootless": 2, "old-cgroups": 2, "wrong-driver": 1, "inherited-store": 1, "signal": 143, "interrupt": 130,
            "hung-frr": 1, "hung-cleanup": 1, "hung-restart": 124,
            "cancelled-output": 143, "cancelled-output-failed-cleanup": 143,
            "cancelled-probe": 143, "cancelled-diagnostics": 1,
        }
        # Cancelled modes are terminated as a process group once this call starts.
        cancel_after = {
            "cancelled-output": lambda call: call[0] == "run" and state.exists(),
            "cancelled-output-failed-cleanup": lambda call: call[0] == "run" and state.exists(),
            "cancelled-probe": lambda call: "is-active" in call,
            "cancelled-diagnostics": lambda call: call[0] == "inspect",
        }
        with tempfile.TemporaryDirectory(prefix="ega smoke ") as temporary:
            directory = Path(temporary)
            (directory / "podman").write_text(fake_podman)
            (directory / "podman").chmod(0o755)
            (directory / "sleep").write_text("#!/bin/sh\nexit 0\n")
            (directory / "sleep").chmod(0o755)
            # Each clock reading advances 120s, so a 300s poll deadline allows two polls.
            (directory / "date").write_text(
                '#!/bin/sh\nnow=$(cat "$TEST_SMOKE_CLOCK" 2>/dev/null || echo 0)\n'
                'echo $((now + 120)) >"$TEST_SMOKE_CLOCK"\necho "$now"\n'
            )
            (directory / "date").chmod(0o755)
            # Shorten every deadline so a hung command fails quickly, unless a mode needs the real one.
            real_timeout = shutil.which("timeout")
            (directory / "timeout").write_text(
                f'#!/usr/bin/env bash\n[[ -z ${{TEST_SMOKE_REAL_TIMEOUT:-}} ]] || exec {real_timeout} "$@"\n'
                'options=()\nwhile [[ $1 == -* ]]; do options+=("$1"); shift; done\n'
                f'shift\nexec {real_timeout} "${{options[@]}}" 3 "$@"\n'
            )
            (directory / "timeout").chmod(0o755)
            for mode, status in expected.items():
                with self.subTest(mode=mode):
                    log, state = directory / f"{mode}.jsonl", directory / f"{mode}.state"
                    artifacts, scratch = directory / f"{mode} artifacts", directory / f"{mode} tmp"
                    scratch.mkdir()
                    if "artifact" in mode:
                        artifacts.mkdir()
                        if "open" in mode:
                            (artifacts / "runtime.txt").mkdir()
                        else:
                            (artifacts / "runtime.txt").symlink_to("/dev/full")
                    command = ["bash", str(ROOT / "tools/smoke-nested.sh"), "localhost/fixture"]
                    environment = {**os.environ, "PATH": f"{directory}:{os.environ['PATH']}",
                                   "TEST_SMOKE_MODE": mode, "TEST_SMOKE_LOG": str(log),
                                   "TEST_SMOKE_STATE": str(state), "ARTIFACT_DIR": str(artifacts),
                                   "TMPDIR": str(scratch), "TEST_SMOKE_CLOCK": str(state.with_suffix(".clock"))}
                    if mode == "cancelled-probe":
                        environment["TEST_SMOKE_REAL_TIMEOUT"] = "1"
                    # Bash cannot trap a signal that was ignored when it started, as in `make verify &`.
                    def default_sigint() -> None:
                        signal.signal(signal.SIGINT, signal.SIG_DFL)
                    if mode in cancel_after:
                        # Like a remote timeout: the output reader is gone when the group is terminated.
                        process = subprocess.Popen(command, env=environment, stdout=subprocess.PIPE,
                                                   stderr=subprocess.STDOUT, start_new_session=True,
                                                   preexec_fn=default_sigint)
                        try:
                            deadline = time.monotonic() + 10
                            while time.monotonic() < deadline and not (log.exists() and any(
                                    cancel_after[mode](json.loads(line)) for line in log.read_text().splitlines())):
                                time.sleep(0.05)
                            self.assertTrue(log.exists() and any(
                                cancel_after[mode](json.loads(line)) for line in log.read_text().splitlines()),
                                "smoke did not reach the cancellation point")
                            process.stdout.close()
                            os.killpg(process.pid, signal.SIGTERM)
                            cancelled = time.monotonic()
                            result = subprocess.CompletedProcess(command, process.wait(timeout=30), "", "")
                            self.assertLess(time.monotonic() - cancelled, 10)
                        finally:
                            if process.poll() is None:
                                os.killpg(process.pid, signal.SIGKILL)
                                process.wait()
                            process.stdout.close()
                    else:
                        result = subprocess.run(command, env=environment, text=True, capture_output=True,
                                                check=False, timeout=30, preexec_fn=default_sigint)
                    self.assertEqual(result.returncode, status, result.stderr)
                    if mode == "failed-service":
                        self.assertIn("during startup", result.stderr)
                    if mode == "failed-restart-metrics":
                        self.assertIn("during restart", result.stderr)
                    self.assertEqual(list(scratch.iterdir()), [])
                    calls = [json.loads(line) for line in log.read_text().splitlines()]
                    if mode in ("rootless", "old-cgroups"):
                        self.assertEqual([call[0] for call in calls], ["info"])
                        continue
                    self.assertEqual(calls[-1][0], "rm")
                    name = next(call for call in calls if call[0] == "run")
                    name = name[name.index("--name") + 1]
                    # Full inspection can contain credentials; only these fields are recorded.
                    self.assertIn(["inspect", "--format", "{{.Id}} {{.State.Status}} {{.State.ExitCode}}", name],
                                  calls[:-1])
                    self.assertIn(["logs", "--tail", "200", name], calls[:-1])
                    if "artifact" not in mode:
                        self.assertTrue((artifacts / "runtime.txt").is_file())
                    self.assertEqual(state.exists(), "cleanup" in mode)
                    if mode in ("success", "failed-restart-metrics"):
                        restarts = [call for call in calls if call[0] == "exec"
                                    and call[2:4] == ["systemctl", "restart"]]
                        self.assertEqual(len(restarts), 1)
                        self.assertEqual(restarts[0][-2:], ["frr.service", "node-exporter.service"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
