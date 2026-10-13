"""Import known local dumps without modifying the supplied archives."""
from dataclasses import dataclass
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Rom:
    key: str
    label: str
    member: str
    size: int
    sha1: str
    native_size: int = 0
    startup_crc: int = 0
    videojet: bool = False


ROMS = (
    Rom('pdc50', 'PDC50', 'pdc50_7050.u3', 0x1000000, '81d2ff5af7b6dc5e1f9277b45f259762e7d24cce', 0x1000000, 0x8d598a49),
    Rom('ouipdc', 'Oui-Oui', 'pdc_ouioui.u2', 0x1000000, 'de0695c240fdc2edc67694ceacaed093e6693767', 0x1000000, 0x9c35780a),
    Rom('tmntpdc', 'Teenage Mutant Ninja Turtles', 'pdc_turtles.bin', 0x800000, '7620f1b7aeaec8032faa8eb7552f775e8d6d14ba', 0x800000, 0xee9e70a3),
    Rom('dorapdc', 'Dora', 'pdc_dora_5030.bin', 0x800000, 'b6ac8ea186d7c624451dd6121932cecb38c1f25f', 0x800000, 0xcea549ad),
    Rom('vjpp1', 'VideoJet TV Games 1', '29lv160.u2', 0x200000, '3cf6fddcfdd1f858e775976f690b32deef1de67f', 0x800000, 0xfe00b2f0, True),
    Rom('vjpp2', 'VideoJet TV Games 2', '29lv320at.u2', 0x400000, '9b537205808c502cf872e62f9701357ef8e28f3c', 0x800000, 0x729e3b2f, True),
    Rom('vjpp3', 'VideoJet TV Games 3', '29lv320.u2', 0x400000, '59279e54e5d9ac2f956241e78dffe526b5de14fd', 0x800000, 0x8502a448, True),
    Rom('vjpp4', 'VideoJet TV Games 4', '29lv160.u2', 0x200000, '0ffb606d4ac93da27a671b369800ea71e68452f3', 0x800000, 0x833e72ab, True),
    Rom('pdc40t', 'PDC40 Touch', 'pdc_5060.bin', 0x4000000, 'fef4af00c737fab2716eef550badbbe0628f26a8'),
    Rom('pdc150t', 'PDC150 Touch', 'pdc5070.bin', 0x8000000, '551d62a9ffc18159f7ace12e4363223e0c5cf3c8'),
    Rom('pdc200', 'PDC200', 'pdc200.bin', 0x8000000, '0dda8a3deb794e493685d3d41790ee371f9b736e'),
)
NATIVE_ROMS = tuple(rom for rom in ROMS if rom.native_size)


def sha256(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def verified_write(path, data):
    expected = hashlib.sha256(data).hexdigest()
    if path.exists():
        if sha256(path) != expected:
            raise ValueError(f'Existing ROM differs: {path}')
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(path.name + '.pdc-tmp')
        temporary.write_bytes(data)
        temporary.replace(path)
    if sha256(path) != expected:
        raise ValueError(f'ROM verification failed: {path}')
    return expected


def validate_native(rom, path):
    data = path.read_bytes()
    if (len(data) != rom.native_size or
            hashlib.sha1(data[:rom.size]).hexdigest() != rom.sha1 or
            any(data[rom.size:]) or
            zlib.crc32(data[-0x800000:]) != rom.startup_crc):
        raise ValueError(f'Native ROM size/hash/padding/CRC mismatch: {rom.key}')
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive_directory', type=Path)
    parser.add_argument('--install-dumps-to', type=Path)
    args = parser.parse_args()
    directory = ROOT / 'build/rom-library'
    records = {}
    for rom in ROMS:
        with zipfile.ZipFile(args.archive_directory / (rom.key + '.zip')) as archive:
            data = archive.read(rom.member)
        if len(data) != rom.size or hashlib.sha1(data).hexdigest() != rom.sha1:
            raise ValueError(f'Original ROM size/hash mismatch: {rom.key}')
        raw = directory / 'dumps' / rom.key / rom.member
        raw_hash = verified_write(raw, data)
        record = {'label': rom.label, 'original_sha1': rom.sha1, 'original_sha256': raw_hash,
                  'native_profile_available': bool(rom.native_size)}
        if rom.native_size:
            native = directory / 'native' / (rom.key + '.rom')
            verified_write(native, data + bytes(rom.native_size - rom.size))
            record['native_sha256'] = validate_native(rom, native)
            record['startup_crc32'] = f'{rom.startup_crc:08x}'
        if args.install_dumps_to:
            folder = args.install_dumps_to / 'Assets/pdc/dumps'
            if not rom.native_size:
                folder /= 'Unsupported'
            target = folder / rom.key / rom.member
            verified_write(target, data)
            record['card_dump'] = str(target)
        records[rom.key] = record
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'import-status.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{len(records)} original dumps verified; {len(NATIVE_ROMS)} native assets prepared.')
    if args.install_dumps_to:
        shutil.copy2(directory / 'import-status.json', args.install_dumps_to / 'Assets/pdc/dumps/import-status.json')
        print('Card dump copies verified. These files alone do not enable unsupported cores.')


if __name__ == '__main__':
    main()
