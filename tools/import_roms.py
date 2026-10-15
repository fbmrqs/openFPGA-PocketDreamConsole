#!/usr/bin/env python3
"""Prepare supported ROMs from the user's local dumps or ZIP archives."""
import argparse
import hashlib
from pathlib import Path
import zipfile

from package import ROMS
from rom_library import NATIVE_ROMS, verified_write


def identify(data):
    sha1 = hashlib.sha1(data).hexdigest()
    for _, stem, _, size, used, expected in ROMS:
        if len(data) == size and sha1 == expected:
            return stem, data[:used]
    for rom in NATIVE_ROMS:
        if len(data) == rom.size and sha1 == rom.sha1:
            return rom.key, data + bytes(rom.native_size - rom.size)
    raise ValueError('Unrecognized dump: size and SHA-1 must match a supported profile.')


def import_file(path, output):
    results = []
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            # Read members in memory; never extract archive paths to disk.
            for entry in archive.infolist():
                if entry.is_dir() or entry.file_size not in {r[3] for r in ROMS} | {r.size for r in NATIVE_ROMS}:
                    continue
                try:
                    stem, data = identify(archive.read(entry))
                except ValueError:
                    continue
                verified_write(output / (stem + '.rom'), data)
                results.append(stem)
    else:
        stem, data = identify(path.read_bytes())
        verified_write(output / (stem + '.rom'), data)
        results.append(stem)
    if not results:
        raise ValueError(f'No supported dump found in {path.name}.')
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', type=Path, nargs='+')
    parser.add_argument('--output', type=Path, required=True,
                        help='Assets/pdc/common on your card, or a local staging directory.')
    args = parser.parse_args()
    for path in args.files:
        for stem in import_file(path, args.output):
            print(f'Verified {stem}.rom')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
