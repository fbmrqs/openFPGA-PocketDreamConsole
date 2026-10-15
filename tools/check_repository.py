#!/usr/bin/env python3
"""Reject private artifacts and credential patterns in tracked source files."""
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PRIVATE_SUFFIXES = {'.bin', '.rom', '.wav', '.mp3', '.flac', '.zip', '.7z', '.rar',
                    '.rbf', '.rbf_r', '.sof', '.run', '.log', '.pem', '.key', '.vcd', '.fst'}
SECRETS = re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|'
                     rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----)')


def private_path(name):
    path = Path(name)
    if not path.parts:
        return False
    return (path.parts[0] in {'.deps', 'build', 'dist'} or
            path.name == '.env' or path.name.startswith('.env.') or
            path.suffix.lower() in PRIVATE_SUFFIXES or
            re.fullmatch(r'\.u\d+', path.suffix.lower()) is not None)


def main():
    names = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode().split('\0')
    issues = []
    for name in filter(None, names):
        if private_path(name):
            issues.append(f'Private artifact tracked: {name}')
        path = ROOT / name
        if path.is_file() and SECRETS.search(path.read_bytes()):
            issues.append(f'Credential pattern in {name} (value suppressed)')
    if issues:
        raise SystemExit('\n'.join(issues))
    print('Tracked source contains no private artifact paths or recognized credential patterns.')


if __name__ == '__main__':
    main()
