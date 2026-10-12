#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
if [ "$#" != 2 ]; then echo "Usage: $0 INSTALLER_OR_DOWNLOAD_DIRECTORY INSTALL_DIRECTORY_OR_volume:NAME" >&2;exit 2;fi
source_path="$1"
target="$2"
if [[ "$target" == volume:* ]]; then
    volume="${target#volume:}"
    if [[ ! "$volume" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]+$ ]]; then echo 'Invalid Docker volume name.' >&2;exit 2;fi
    install_mount="$volume"
else
    mkdir -p "$target"
    install_mount="$(cd "$target" && pwd)"
    if [ -e "$install_mount/quartus" ]; then echo 'Installation directory already contains Quartus.' >&2;exit 1;fi
fi
docker build --platform linux/amd64 -t pdc-quartus-runtime tools/fpga
if [ -f "$source_path" ]; then
    installer="$(cd "$(dirname "$source_path")" && pwd)/$(basename "$source_path")"
    workspace="$PWD/build/quartus-installer"
    mkdir -p "$workspace/downloads" "$workspace/extracted"
    python3 - "$installer" <<'PY'
import hashlib,sys
from pathlib import Path
with Path(sys.argv[1]).open('rb') as file:
    digest=hashlib.file_digest(file,'sha256').hexdigest()
if digest!='5c422347f33929cd85d7c99a0adf9925ee743834a05bdfe5ffe3e27fdcb01342':
    raise SystemExit('Expected the official qinst Lite Linux 25.1std-1129 bootstrap installer.')
PY
    docker run --rm --platform linux/amd64 -v "$installer:/qinst.run:ro" -v "$workspace:/work" \
        pdc-quartus-runtime bash /qinst.run --noexec --target /work/extracted
    docker run --rm --platform linux/amd64 -e QUARTUS_CPUID_BYPASS=1 -v "$workspace:/work" \
        pdc-quartus-runtime bash /work/extracted/qinst.sh --cli \
        --download-dir /work/downloads --components quartus,cyclonev --accept-eula
    downloads="$workspace/downloads"
else
    downloads="$(cd "$source_path" && pwd)"
fi
python3 - "$downloads" <<'PY'
import hashlib,sys
from pathlib import Path
for name,expected in (
    ('QuartusLiteSetup-25.1std.0.1129-linux.run','ce0773469eacab5b7035c175484625f4ec3737d1'),
    ('cyclonev-25.1std.0.1129.qdz','a7225ec1bd36ccfd6826ea6273df5d21dd95633b')):
    with (Path(sys.argv[1])/name).open('rb') as file:
        if hashlib.file_digest(file,'sha1').hexdigest()!=expected:
            raise SystemExit(f'Official checksum mismatch: {name}')
PY
docker run --rm --platform linux/amd64 -e QUARTUS_CPUID_BYPASS=1 \
    -v "$downloads:/downloads:ro" -v "$install_mount:/opt/altera" \
    pdc-quartus-runtime /downloads/QuartusLiteSetup-25.1std.0.1129-linux.run \
    --mode unattended --unattendedmodeui none --accept_eula 1 --installdir /opt/altera \
    --enable-components cyclonev \
    --disable-components questa_fse,arria_lite,cyclone,cyclone10lp,max,max10,quartus_help,riscfree \
    --create_desktop_shortcuts 0
# Docker exposes ARM /proc/cpuinfo even when the executable runs in an x86 emulator.
docker run --rm --platform linux/amd64 -v "$install_mount:/opt/altera" pdc-quartus-runtime \
    perl -i.pdc-original -pe 's/if test \$\? != 0 ; then/if test \$? != 0 \&\& test "\${QUARTUS_CPUID_BYPASS:-0}" != 1 ; then/' \
    /opt/altera/quartus/adm/qenv.sh
docker build --platform linux/amd64 -f tools/fpga/Dockerfile.qemu -t pdc-quartus-qemu .
if [[ "$target" == volume:* ]]; then
    docker run --rm --platform linux/amd64 -v "$install_mount:/opt/altera" \
        -v "$PWD/tools/fpga/enable-qemu.sh:/enable-qemu.sh:ro" pdc-quartus-qemu bash /enable-qemu.sh
    printf 'Run with: PDC_QUARTUS_VOLUME=%q PDC_QUARTUS_EMULATOR=qemu make fpga-template\n' "$volume"
else
    printf 'Installed at %s\n' "$install_mount"
    printf 'Run with: PDC_QUARTUS_INSTALL=%q make fpga-template\n' "$install_mount"
fi
