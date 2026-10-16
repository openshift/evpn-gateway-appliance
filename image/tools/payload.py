"""Render, cache, and load the payloads bound to the appliance image."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

STREAM_SERVICES: dict[str, dict[str, str]] = {
    "rhel10": {"frr": "frr.container", "node_exporter": "node-exporter.container"}
}
SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")
KNOWN_ARCHITECTURES = {"amd64", "arm64", "ppc64le", "s390x", "riscv64", "386"}
RUNNER = Callable[..., subprocess.CompletedProcess[str]]


@dataclass(frozen=True)
class Payload:
    name: str
    repository: str
    tag: str
    digest: str

    @property
    def reference(self) -> str:
        return f"{self.repository}@{self.digest}"


@dataclass(frozen=True)
class UnitImage:
    unit: str
    reference: str
    digest: str


def _mapping(value: Any, where: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise TypeError(f"{where} must be a mapping")
    return value


def load_inventory(path: Path, stream: str) -> dict[str, Payload]:
    try:
        import yaml
    except ModuleNotFoundError as exc:
        raise ValueError("render requires PyYAML (python3-pyyaml)") from exc
    try:
        document = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        raise ValueError(f"invalid inventory YAML: {exc}") from exc
    root = _mapping(document, "inventory")
    if stream not in root:
        raise ValueError(f"inventory has no stream {stream!r}")
    expected = STREAM_SERVICES.get(stream)
    if expected is None:
        raise ValueError(f"unsupported stream {stream!r}")
    entries = _mapping(root[stream], f"inventory.{stream}")
    unknown = set(entries) - set(expected)
    missing = set(expected) - set(entries)
    if unknown:
        raise ValueError(f"inventory.{stream} has unknown services: {sorted(unknown)}")
    if missing:
        raise ValueError(f"inventory.{stream} is missing services: {sorted(missing)}")

    result: dict[str, Payload] = {}
    for name in expected:
        fields = _mapping(entries[name], f"inventory.{stream}.{name}")
        required = {"repository", "tag", "digest"}
        if set(fields) != required:
            raise ValueError(
                f"inventory.{stream}.{name} must contain exactly {sorted(required)}"
            )
        repository, tag, digest = (fields[key] for key in ("repository", "tag", "digest"))
        if not all(isinstance(item, str) and item for item in (repository, tag, digest)):
            raise ValueError(f"inventory.{stream}.{name} fields must be non-empty strings")
        if not re.fullmatch(r"[a-z0-9][a-z0-9.-]*(?::[0-9]+)?/[a-z0-9]+(?:[._/-][a-z0-9]+)*", repository):
            raise ValueError(f"inventory.{stream}.{name}.repository must be an untagged registry path")
        if not re.fullmatch(r"[\w][\w.-]{0,127}", tag, re.ASCII):
            raise ValueError(f"inventory.{stream}.{name}.tag is not a container tag")
        if not SHA256.fullmatch(digest):
            raise ValueError(f"inventory.{stream}.{name}.digest is not a sha256 digest")
        result[name] = Payload(name, repository, tag, digest)
    return result


def render_units(inventory: Path, stream: str, templates: Path, destination: Path) -> list[Path]:
    payloads = load_inventory(inventory, stream)
    destination.mkdir(parents=True, exist_ok=True)
    outputs: list[Path] = []
    for name, filename in STREAM_SERVICES[stream].items():
        template = templates / f"{filename}.in"
        text = template.read_text()
        if text.count("@PAYLOAD_IMAGE@") != 1:
            raise ValueError(f"{template} must contain exactly one @PAYLOAD_IMAGE@ token")
        rendered = text.replace("@PAYLOAD_IMAGE@", payloads[name].reference)
        if re.search(r"@[A-Z][A-Z0-9_]*@", rendered):
            raise ValueError(f"{template} contains an unknown template token")
        image_lines = [line for line in rendered.splitlines() if line.startswith("Image=")]
        if image_lines != [f"Image={payloads[name].reference}"]:
            raise ValueError(f"{template} does not render the expected Image= line")
        output = destination / filename
        output.write_text(rendered)
        outputs.append(output)
    return outputs


def parse_unit_images(units: Path) -> list[UnitImage]:
    if not units.is_dir():
        raise ValueError(f"unit directory does not exist: {units}")
    result: list[UnitImage] = []
    seen: set[str] = set()
    for path in sorted(units.glob("*.container")):
        matches = re.findall(r"^Image=([^\s]+)$", path.read_text(), re.MULTILINE)
        if len(matches) != 1:
            raise ValueError(f"{path} must contain exactly one Image= line")
        reference = matches[0]
        repository, separator, digest = reference.rpartition("@")
        if not separator or not repository or not SHA256.fullmatch(digest):
            raise ValueError(f"{path} has an invalid digest reference: {reference}")
        if reference in seen:
            raise ValueError(f"duplicate payload reference in {units}: {reference}")
        seen.add(reference)
        result.append(UnitImage(path.name, reference, digest))
    if not result:
        raise ValueError(f"no .container units in {units}")
    return result


def _digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _descriptor_digest(value: Any, where: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        raise ValueError(f"{where} is not a sha256 digest")
    return value


def _blob(cache: Path, digest: str, where: str) -> Path:
    path = cache / digest.removeprefix("sha256:")
    if not path.is_file():
        raise ValueError(f"{where} is missing blob {digest}")
    checksum = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            checksum.update(chunk)
    if "sha256:" + checksum.hexdigest() != digest:
        raise ValueError(f"{where} blob {digest} has the wrong digest")
    return path


def _manifest_file(cache: Path, digest: str) -> Path:
    return cache / f"{digest.removeprefix('sha256:')}.manifest.json"


def _validate_manifest(
    cache: Path,
    data: bytes,
    where: str,
    architectures: set[str],
    expected_architecture: str | None = None,
    expected_os: str | None = None,
) -> None:
    manifest = _mapping(json.loads(data), where)
    descriptors = manifest.get("manifests")
    if descriptors is not None:
        if not isinstance(descriptors, list) or not descriptors:
            raise ValueError(f"{where}.manifests must be a non-empty list")
        for index, descriptor in enumerate(descriptors):
            descriptor = _mapping(descriptor, f"{where}.manifests[{index}]")
            digest = _descriptor_digest(descriptor.get("digest"), f"{where}.manifests[{index}].digest")
            platform_data = _mapping(
                descriptor.get("platform"), f"{where}.manifests[{index}].platform"
            )
            architecture = platform_data.get("architecture")
            if architecture not in KNOWN_ARCHITECTURES:
                raise ValueError(f"{where} has unknown architecture {architecture!r}")
            if platform_data.get("os") != "linux":
                raise ValueError(f"{where} has unsupported operating system {platform_data.get('os')!r}")
            architectures.add(architecture)
            child = _manifest_file(cache, digest)
            if not child.is_file():
                raise ValueError(f"{where} is missing child manifest {digest}")
            child_data = child.read_bytes()
            if _digest(child_data) != digest:
                raise ValueError(f"child manifest {digest} has the wrong digest")
            _validate_manifest(
                cache,
                child_data,
                f"{where} child {digest}",
                architectures,
                architecture,
                platform_data["os"],
            )
        return

    config = _mapping(manifest.get("config"), f"{where}.config")
    config_digest = _descriptor_digest(config.get("digest"), f"{where}.config.digest")
    config_data = _blob(cache, config_digest, f"{where}.config").read_bytes()
    config_json = _mapping(json.loads(config_data), f"{where}.config blob")
    architecture = config_json.get("architecture")
    if architecture not in KNOWN_ARCHITECTURES:
        raise ValueError(f"{where} config has unknown architecture {architecture!r}")
    if config_json.get("os") != "linux":
        raise ValueError(f"{where} config has unsupported operating system {config_json.get('os')!r}")
    if expected_architecture is not None and architecture != expected_architecture:
        raise ValueError(f"{where} config architecture does not match its index descriptor")
    if expected_os is not None and config_json.get("os") != expected_os:
        raise ValueError(f"{where} config operating system does not match its index descriptor")
    architectures.add(architecture)
    layers = manifest.get("layers", [])
    if not isinstance(layers, list):
        raise TypeError(f"{where}.layers must be a list")
    for index, layer in enumerate(layers):
        layer = _mapping(layer, f"{where}.layers[{index}]")
        _blob(
            cache,
            _descriptor_digest(layer.get("digest"), f"{where}.layers[{index}].digest"),
            f"{where}.layers[{index}]",
        )


def validate_cache(cache: Path, expected_digest: str) -> dict[str, Any]:
    if not SHA256.fullmatch(expected_digest):
        raise ValueError(f"invalid expected cache digest: {expected_digest}")
    manifest_path = cache / "manifest.json"
    if not manifest_path.is_file():
        raise ValueError(f"cache is missing {manifest_path}")
    manifest_data = manifest_path.read_bytes()
    if _digest(manifest_data) != expected_digest:
        raise ValueError(f"cache root manifest does not match {expected_digest}")
    architectures: set[str] = set()
    _validate_manifest(cache, manifest_data, "cache manifest", architectures)
    host_arch = _normalize_architecture(platform.machine())
    if host_arch not in architectures:
        raise ValueError(f"cache has no image for host architecture {host_arch}")
    return {"digest": expected_digest, "architectures": sorted(architectures)}


def _normalize_architecture(value: str) -> str:
    return {"x86_64": "amd64", "aarch64": "arm64"}.get(value, value)


def _run(command: list[str], runner: RUNNER = subprocess.run) -> subprocess.CompletedProcess[str]:
    return runner(command, check=True, text=True, capture_output=True)


def _copy_command(skopeo: str, source: str, destination: str, authfile: Path | None = None, all_images: bool = False) -> list[str]:
    command = [skopeo, "copy", "--preserve-digests"]
    if all_images:
        command.append("--all")
    if authfile is not None:
        command.extend(["--src-authfile", str(authfile)])
    command.extend([source, destination])
    return command


def _native_inspect(cache: Path, skopeo: str, runner: RUNNER) -> dict[str, Any]:
    result = _run(
        [skopeo, "inspect", "--format", "{{json .}}", f"dir:{cache}"], runner
    )
    try:
        return _mapping(json.loads(result.stdout), "skopeo inspect")
    except json.JSONDecodeError as exc:
        raise ValueError(f"skopeo inspect returned invalid JSON: {exc}") from exc


def cache_images(
    units: Path,
    destination: Path,
    authfile: Path | None,
    skopeo: str = "skopeo",
    runner: RUNNER = subprocess.run,
) -> None:
    images = parse_unit_images(units)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "index.json").unlink(missing_ok=True)
    index: list[dict[str, Any]] = []
    for image in images:
        cache_path = destination / image.unit.removesuffix(".container")
        if cache_path.exists():
            shutil.rmtree(cache_path)
        cache_path.mkdir()
        _run(
            _copy_command(
                skopeo,
                f"docker://{image.reference}",
                f"dir:{cache_path}",
                authfile,
                all_images=True,
            ),
            runner,
        )
        details = validate_cache(cache_path, image.digest)
        inspected = _native_inspect(cache_path, skopeo, runner)
        architecture = inspected.get("Architecture")
        operating_system = inspected.get("Os")
        if architecture not in KNOWN_ARCHITECTURES or operating_system != "linux":
            raise ValueError(f"native cache selection is invalid for {image.reference}")
        index.append(
            {
                "unit": image.unit,
                "reference": image.reference,
                "cache_path": cache_path.name,
                "digest": image.digest,
                "architectures": details["architectures"],
                "native_architecture": architecture,
                "os": operating_system,
            }
        )
    (destination / "index.json").write_text(json.dumps({"version": 1, "images": index}, indent=2) + "\n")


def _read_cache_index(cache: Path, units: Path) -> list[dict[str, Any]]:
    try:
        index = _mapping(json.loads((cache / "index.json").read_text()), "cache index")
    except FileNotFoundError as exc:
        raise ValueError("cache is missing index.json") from exc
    if index.get("version") != 1 or not isinstance(index.get("images"), list):
        raise ValueError("cache index has unsupported shape")
    installed = {image.unit: image for image in parse_unit_images(units)}
    entries: list[dict[str, Any]] = []
    seen_units: set[str] = set()
    for raw in index["images"]:
        entry = _mapping(raw, "cache index image")
        unit = entry.get("unit")
        reference = entry.get("reference")
        cache_path_name = entry.get("cache_path")
        if not all(isinstance(item, str) for item in (unit, reference, cache_path_name)):
            raise ValueError("cache index image has invalid string fields")
        if unit in seen_units:
            raise ValueError(f"cache index repeats unit {unit}")
        seen_units.add(unit)
        current = installed.get(unit)
        if current is None or current.reference != reference:
            raise ValueError(f"cache index does not match installed unit {unit}")
        if entry.get("digest") != current.digest:
            raise ValueError(f"cache index digest does not match installed unit {unit}")
        cache_path = cache / cache_path_name
        if cache_path.parent != cache:
            raise ValueError(f"cache path escapes cache directory: {cache_path_name}")
        validate_cache(cache_path, current.digest)
        entries.append({**entry, "path": cache_path})
    if {entry["unit"] for entry in entries} != set(installed):
        raise ValueError("cache index does not cover every installed payload unit")
    return entries


def _inspect_loaded(reference: str, expected: Mapping[str, Any], podman: str, runner: RUNNER) -> None:
    result = _run([podman, "image", "inspect", "--format", "json", reference], runner)
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ValueError(f"podman image inspect returned invalid JSON: {exc}") from exc
    records = value if isinstance(value, list) else [value]
    if not records:
        raise ValueError(f"podman did not inspect loaded image {reference}")
    record = _mapping(records[0], "podman image inspect")
    expected_arch = expected.get("native_architecture")
    if record.get("Architecture") != expected_arch or record.get("Os") != expected.get("os"):
        raise ValueError(f"loaded image platform does not match {reference}")
    repo_digests = record.get("RepoDigests", [])
    digest = record.get("Digest")
    if reference not in repo_digests and digest != expected.get("digest"):
        raise ValueError(f"podman cannot resolve the expected digest for {reference}")


def load_images(
    cache: Path,
    units: Path,
    skopeo: str = "skopeo",
    podman: str = "podman",
    runner: RUNNER = subprocess.run,
) -> None:
    entries = _read_cache_index(cache, units)
    for entry in entries:
        _run(
            _copy_command(
                skopeo,
                f"dir:{entry['path']}",
                f"containers-storage:{entry['reference']}",
            ),
            runner,
        )
        _inspect_loaded(entry["reference"], entry, podman, runner)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    render = subparsers.add_parser("render")
    render.add_argument("--inventory", type=Path, required=True)
    render.add_argument("--stream", required=True)
    render.add_argument("--templates", type=Path, required=True)
    render.add_argument("--output", type=Path, required=True)
    cache = subparsers.add_parser("cache")
    cache.add_argument("--units", type=Path, required=True)
    cache.add_argument("--output", type=Path, required=True)
    cache.add_argument("--authfile", type=Path)
    load = subparsers.add_parser("load")
    load.add_argument("--units", type=Path, required=True)
    load.add_argument("--cache", type=Path, required=True)
    load.add_argument("--skopeo", default="skopeo")
    load.add_argument("--podman", default="podman")
    return parser


def main(argv: Iterable[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.command == "render":
            render_units(args.inventory, args.stream, args.templates, args.output)
        elif args.command == "cache":
            cache_images(args.units, args.output, args.authfile)
        else:
            load_images(args.cache, args.units, args.skopeo, args.podman)
    except (OSError, ValueError, TypeError, subprocess.CalledProcessError) as exc:
        print(f"payload: {exc}", file=sys.stderr)
        if isinstance(exc, subprocess.CalledProcessError) and exc.stderr:
            print(exc.stderr.strip(), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
