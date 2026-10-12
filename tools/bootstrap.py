#!/usr/bin/env python3
"""Fetch the exact SDK revision used by this experimental Pocket build."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SDK = ROOT / ".deps/openfpga-sdk"
REVISION = "a408ddc12aed0dfaa4aa22c06af82f829db77126"
URL = "https://github.com/openfpgaOS/openfpgaSDK.git"


def git(*args):
    return subprocess.check_output(["git", "-C", str(SDK), *args], text=True).strip()


def main():
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
