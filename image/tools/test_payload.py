from __future__ import annotations

import gzip
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
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
    def test_renderer_is_the_single_digest_source(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            temporary_path = Path(temporary)
            inventory = temporary_path / "payload.yaml"
            shutil.copy(ROOT / "payload-images.yaml", inventory)
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
            reference = "example/frr@sha256:" + "a" * 64
            (units / "frr.container").write_text(f"Image={reference}\n")
            cache = temporary_path / "cache"
            cache.mkdir()
            (cache / "index.json").write_text(
                json.dumps(
                    {
                        "version": 1,
                        "images": [
                            {
                                "unit": "frr.container",
                                "reference": reference,
                                "cache_path": "frr",
                                "digest": "sha256:" + "a" * 64,
                            }
                        ],
                    }
                )
            )
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

    def test_smoke_checks_both_workloads_inside_their_containers(self) -> None:
        fake_podman = '''#!/usr/bin/env python3
import os, sys
args = sys.argv[1:]
if args[0] == "info":
    print("v2 false")
elif args[0] == "run":
    assert "--pull=never" in args and args[args.index("--network") + 1] == "none"
    print("test-container")
elif args[0] == "exec":
    cmd = args[2:]
    if cmd[:2] == ["systemctl", "is-active"]:
        assert len(cmd) == 4, "must check one service at a time"
        sys.exit(1 if os.environ["TEST_SMOKE_MODE"] == "failed-service" and cmd[-1] == "frr.service" else 0)
    elif cmd[:4] == ["podman", "exec", "frr", "vtysh"]:
        sys.exit(1 if os.environ["TEST_SMOKE_MODE"] == "failed-frr" else 0)
    elif cmd[0] == "curl":
        print('node_exporter_build_info{version="fixture"} 1')
    elif cmd[0] not in ("journalctl", "systemctl"):
        sys.exit(3)
'''
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "podman").write_text(fake_podman)
            (directory / "podman").chmod(0o755)
            (directory / "sleep").write_text("#!/bin/sh\nexit 0\n")
            (directory / "sleep").chmod(0o755)
            for mode in ("success", "failed-service", "failed-frr"):
                with self.subTest(mode=mode):
                    result = subprocess.run(
                        ["bash", str(ROOT / "tools/smoke-nested.sh"), "localhost/fixture"],
                        env={**os.environ, "PATH": f"{directory}:{os.environ['PATH']}", "TEST_SMOKE_MODE": mode},
                        text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(result.returncode == 0, mode == "success", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
