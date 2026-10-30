"""Collect license texts for the locked dependency graph, including test tools."""
import json
from pathlib import Path
import subprocess
import sys

crate = Path(__file__).resolve().parent
metadata = json.loads(subprocess.check_output([
    'cargo', 'metadata', '--manifest-path', str(crate / 'Cargo.toml'), '--locked',
    '--format-version', '1', '--filter-platform', 'wasm32-wasip1'], text=True))
parts = ['Third-party notices for the locked dependency graph.\n'
         'This inventory may include build/test dependencies absent from plugin.wasm.\n']
for package in sorted(metadata['packages'], key=lambda p: (p['name'], p['version'])):
    if package['name'] == 'pdc-rom-preparation':
        continue
    root = Path(package['manifest_path']).parent
    files = {p for p in root.iterdir() if p.is_file() and
             p.name.upper().startswith(('LICENSE', 'LICENCE', 'COPYING', 'COPYRIGHT', 'UNLICENSE', 'NOTICE'))}
    if package.get('license_file'):
        files.add(root / package['license_file'])
    if not files and package['name'] in {'extism-convert', 'extism-convert-macros', 'extism-manifest'} and package['version'] == '1.41.0':
        files.add(crate / 'licenses/extism-1.41.0.txt')
    if not files:
        raise SystemExit(f'Missing license text: {package["name"]} {package["version"]}')
    parts.append(f'\n{"=" * 72}\n{package["name"]} {package["version"]}\n'
                 f'License: {package.get("license")}\nRepository: {package.get("repository")}\n')
    for path in sorted(files):
        parts.append(f'\n--- {path.name} ---\n{path.read_text(encoding="utf-8")}\n')
Path(sys.argv[1]).write_text(''.join(parts), encoding='utf-8')
