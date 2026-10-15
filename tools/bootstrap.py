#!/usr/bin/env python3
"""Fetch pinned native framework or historical software SDK dependencies."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / ".deps/openfpga-sdk"
REVISION = "a408ddc12aed0dfaa4aa22c06af82f829db77126"
URL = "https://github.com/openfpgaOS/openfpgaSDK.git"


def git(*args):
    return subprocess.check_output(["git", "-C", str(SDK), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true', help='Fetch only the native Analogue core template.')
    args = parser.parse_args()
    if args.native:
        destination = ROOT / '.deps/core-template'
        revision = 'da3a021b1eaf742604d86d8dc9b33a6666263e6a'
        if not destination.exists():
            destination.mkdir(parents=True)
            subprocess.run(['git', 'init', str(destination)], check=True)
            subprocess.run(['git', '-C', str(destination), 'fetch', '--depth=1',
                            'https://github.com/open-fpga/core-template.git', revision], check=True)
            subprocess.run(['git', '-C', str(destination), 'checkout', '--detach', 'FETCH_HEAD'], check=True)
        actual = subprocess.check_output(['git', '-C', str(destination), 'rev-parse', 'HEAD'], text=True).strip()
        dirty = subprocess.check_output(['git', '-C', str(destination), 'status', '--porcelain',
                                         '--untracked-files=no'], text=True).strip()
        if actual != revision or dirty:
            raise SystemExit('Native framework differs from the pinned clean revision; preserve it and use a separate .deps directory.')
        print(f'Native framework ready: {revision}. Install Quartus separately; see docs/building.md.')
        return
    if SDK.exists():
        if git("rev-parse", "HEAD") != REVISION:
            raise SystemExit("SDK revision differs; keep the checkout and use a separate .deps directory.")
        if git("status", "--porcelain", "--untracked-files=no"):
            raise SystemExit("SDK contains modified tracked files; restore them before building.")
    else:
        SDK.mkdir(parents=True)
        git("init")
        git("remote", "add", "origin", URL)
        git("fetch", "--depth=1", "origin", REVISION)
        git("checkout", "--detach", "FETCH_HEAD")
    print(f"SDK ready: {REVISION}")
    print("Install riscv64-elf-gcc, then run make package. No Quartus build is needed.")


if __name__ == "__main__":
    main()
