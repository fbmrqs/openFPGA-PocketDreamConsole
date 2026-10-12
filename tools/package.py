#!/usr/bin/env python3
"""Validate local dumps and assemble a private Pocket SD-card package."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / ".deps/openfpga-sdk"
SDK_REVISION = "a408ddc12aed0dfaa4aa22c06af82f829db77126"
CORE_ID = "Local.PocketDreamConsole"
OUT = ROOT / "dist/pocket-dc"
ROMS = (
    ("pdc100.bin", "pdc100", "PDC100", 0x8000000, 0x4000000,
     "cfb4be7877ec263d24063a004c56985db5c0f4e2"),
    ("pdc_pink.u2", "pdc30", "PDC30 Pink", 0x1000000, 0x1000000,
     "5b423d589358dd53a2e5765bcb94da2d44200e56"),
)


def digest(path, algorithm):
    with path.open("rb") as file:
        return hashlib.file_digest(file, algorithm).hexdigest()


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=4) + "\n")


def validate_input(definition):
    # Analogue input.json: controller mapping names have a 19-character limit.
    for controller in definition["input"]["controllers"]:
        for mapping in controller["mappings"]:
            if len(mapping["name"]) > 19:
                raise ValueError(f"input.json: {mapping['key']} label exceeds 19 characters")


def validate_core_identity(core):
    metadata = json.loads((core / "core.json").read_text())["core"]["metadata"]
    identity = f"{metadata['author']}.{metadata['shortname']}"
    if core.name != identity:
        raise ValueError(f"core.json: identity {identity!r} differs from folder {core.name!r}")


def validate_inputs():
    revision = subprocess.check_output(
        ["git", "-C", str(SDK), "rev-parse", "HEAD"], text=True).strip()
    if revision != SDK_REVISION:
        raise ValueError("SDK revision differs from the tested runtime.")
    elf = (ROOT / "build/pocket/app.elf").read_bytes()
    if elf[:7] != b"\x7fELF\x01\x01\x01" or struct.unpack_from("<H", elf, 18)[0] != 243:
        raise ValueError("Application must be a little-endian ELF32 RISC-V executable.")
    runtime = SDK / "runtime"
    manifest = dict(line.split()[::-1] for line in (runtime / "MANIFEST").read_text().splitlines()
                    if line and not line.startswith("#"))
    for name in ("os25.rbf_r", "os.bin", "loader.bin"):
        relative = f"./pocket/{name}"
        if digest(runtime / "pocket" / name, "md5") != manifest[relative]:
            raise ValueError(f"Runtime integrity mismatch: {name}")
    for filename, _, _, size, _, expected in ROMS:
        path = ROOT / filename
        if path.stat().st_size != size or digest(path, "sha1") != expected:
            raise ValueError(f"ROM size/hash mismatch: {filename}; originals were not modified.")


def main():
    validate_inputs()
    if OUT.exists():
        shutil.rmtree(OUT)
    core = OUT / "Cores" / CORE_ID
    assets = OUT / "Assets/pdc/common"
    instances = OUT / "Assets/pdc" / CORE_ID
    core.mkdir(parents=True)
    assets.mkdir(parents=True)
    template = SDK / "dist/sdk/Cores/ThinkElastic.openfpgaOS"
    for name in ("audio.json", "video.json", "data.json", "interact.json", "icon.bin", "variants.json"):
        shutil.copy2(template / name, core / name)
    definition = json.loads((template / "core.json").read_text())
    definition["core"]["metadata"].update(
        platform_ids=["pdc"], shortname="PocketDreamConsole",
        description="Experimental PDC30 / PDC100 emulator on openfpgaOS",
        author="Local", url="", version="0.1.3-experimental", date_release="2026-10-10")
    write_json(core / "core.json", definition)
    write_json(OUT / "Platforms/pdc.json", {"platform": {
        "category": "Handheld", "name": "Pocket Dream Console", "year": 2008,
        "manufacturer": "Conny / VideoJet / Anncia"}})
    image = OUT / "Platforms/_images/pdc.bin"
    image.parent.mkdir(parents=True)
    shutil.copy2(SDK / "dist/sdk/Platforms/_images/openfpgaos.bin", image)
    write_json(core / "input.json", {"input": {"magic": "APF_VER_1", "controllers": [{
        "type": "default", "mappings": [
            {"id": 0, "name": "A", "key": "pad_btn_a"},
            {"id": 1, "name": "B", "key": "pad_btn_b"},
            {"id": 10, "name": "Left Trigger", "key": "pad_trig_l"},
            {"id": 11, "name": "Right Trigger", "key": "pad_trig_r"},
            {"id": 20, "name": "Pause", "key": "pad_btn_start"},
            {"id": 21, "name": "Select+Start: Reset", "key": "pad_btn_select"}]}]}})
    for name in ("os25.rbf_r", "loader.bin"):
        shutil.copy2(SDK / "runtime/pocket" / name, core / name)
    shutil.copy2(SDK / "runtime/pocket/os.bin", assets / "os.bin")
    shutil.copy2(ROOT / "build/pocket/app.elf", assets / "pdc.elf")
    for filename, stem, label, _, used, _ in ROMS:
        with (ROOT / filename).open("rb") as source, (assets / f"{stem}.rom").open("wb") as dest:
            remaining = used
            while remaining:
                block = source.read(min(remaining, 1024 * 1024))
                if not block:
                    raise ValueError(f"Short ROM read: {filename}")
                dest.write(block)
                remaining -= len(block)
        (assets / f"{stem}.ini").write_text(f"[os]\nELF=pdc.elf\nARGS={stem}.rom\nVARIANT=os25\n")
        write_json(instances / f"{label}.json", {"instance": {"magic": "APF_VER_1", "data_slots": [
            {"id": 1, "filename": "os.bin"}, {"id": 2, "filename": f"{stem}.ini"},
            {"id": 3, "filename": "pdc.elf"}, {"id": 4, "filename": f"{stem}.rom"}]}})
    shutil.copy2(ROOT / "README.md", OUT / "README.md")
    notices = OUT / "Licenses/PocketDreamConsole"
    notices.mkdir(parents=True)
    shutil.copy2(ROOT / "third_party/veesem/LICENSE", notices / "veesem-ISC.txt")
    shutil.copy2(SDK / "LICENSE", notices / "openfpgaSDK-Apache-2.0.txt")
    shutil.copy2(SDK / "NOTICE", notices / "openfpgaSDK-NOTICE.txt")
    shutil.copy2(SDK / "LICENSES/MIT.txt", notices / "musl-MIT.txt")
    for file in (ROOT / "third_party/runtime").iterdir():
        shutil.copy2(file, notices / file.name)
    shutil.copy2(ROOT / "third_party/veesem/README.md", notices / "veesem-changes.md")
    validate_input(json.loads((core / "input.json").read_text()))
    validate_core_identity(core)
    manifest = {p.relative_to(OUT).as_posix(): digest(p, "sha256")
                for p in sorted(OUT.rglob("*")) if p.is_file()}
    write_json(OUT / "manifest.json", {"sdk_revision": SDK_REVISION, "files": manifest})
    archive = OUT.parent / "pocket-dc-experimental.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zip:
        for file in sorted(OUT.rglob("*")):
            if file.is_file():
                zip.write(file, file.relative_to(OUT))
    print(f"Pocket SD tree: {OUT}")
    print(f"Private ROM-inclusive ZIP: {archive}")
    print("Hardware testing and Pocket performance are unverified.")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
