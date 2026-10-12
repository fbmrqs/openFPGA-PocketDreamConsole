#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"
root="$PWD"
kind="${1:-template}"
if [ "$kind" != template ] && [ "$kind" != native ]; then echo 'Expected template or native.' >&2;exit 2;fi
revision=da3a021b1eaf742604d86d8dc9b33a6666263e6a
if [ ! -d .deps/core-template/.git ]; then
    git clone https://github.com/open-fpga/core-template.git .deps/core-template
fi
if [ "$(git -C .deps/core-template rev-parse HEAD)" != "$revision" ]; then
    echo "Expected official template revision $revision" >&2
    exit 1
fi
mkdir -p "build/fpga/$kind"
if [ "$kind" = native ]; then python3 tools/fpga/evidence.py begin fpga;fi
cp -R .deps/core-template/src/. "build/fpga/$kind/"
python3 - "$kind" <<'PY_CLEAN'
from pathlib import Path
import shutil, sys
outputs = Path('build/fpga') / sys.argv[1] / 'fpga/output_files'
if outputs.exists():
    shutil.rmtree(outputs)
PY_CLEAN
if [ "$kind" = native ]; then python3 tools/fpga/prepare-native.py;fi
if command -v quartus_sh >/dev/null; then
    cd "build/fpga/$kind/fpga"
    quartus_sh --flow compile ap_core
    if [ "$kind" = native ]; then quartus_sta -t validate-timing.tcl;fi
elif [ -n "${PDC_QUARTUS_VOLUME:-}" ]; then
    if [ "${PDC_QUARTUS_EMULATOR:-rosetta}" = qemu ]; then
        docker run --rm --platform linux/amd64 \
            -v "$PDC_QUARTUS_VOLUME:/opt/altera:ro" \
            -v "$root/build/fpga/$kind:/work" -w /work/fpga \
            -v "$root/tools/fpga/run-qemu.sh:/run-quartus.sh:ro" \
            pdc-quartus-qemu bash /run-quartus.sh
    else
    docker run --rm --platform linux/amd64 -e QUARTUS_CPUID_BYPASS=1 \
        -v "$PDC_QUARTUS_VOLUME:/opt/altera:ro" \
        -v "$root/build/fpga/$kind:/work" -w /work/fpga \
        pdc-quartus-runtime bash -c '
          set -e
          /opt/altera/quartus/bin/quartus_sh --flow compile ap_core
          if [ -e validate-timing.tcl ]; then /opt/altera/quartus/bin/quartus_sta -t validate-timing.tcl;fi
        '

    fi
elif [ -n "${PDC_QUARTUS_INSTALL:-}" ]; then
    docker run --rm --platform linux/amd64 -e QUARTUS_CPUID_BYPASS=1 \
        -v "$PDC_QUARTUS_INSTALL:/opt/altera:ro" \
        -v "$root/build/fpga/$kind:/work" -w /work/fpga \
        pdc-quartus-runtime bash -c '
          set -e
          /opt/altera/quartus/bin/quartus_sh --flow compile ap_core
          if [ -e validate-timing.tcl ]; then /opt/altera/quartus/bin/quartus_sta -t validate-timing.tcl;fi
        '

elif [ -n "${PDC_QUARTUS_IMAGE:-}" ]; then
    docker run --rm --platform linux/amd64 \
        -v "$root/build/fpga/$kind:/work" -w /work/fpga \
        "$PDC_QUARTUS_IMAGE" bash -c '
          set -e
          quartus_sh --flow compile ap_core
          if [ -e validate-timing.tcl ]; then quartus_sta -t validate-timing.tcl;fi
        '

else
    cat >&2 <<'MESSAGE'
Quartus Prime Lite 25.1 with Cyclone V support is required.
The official download currently requires Altera account sign-in:
https://www.altera.com/downloads/fpga-development-tools/quartus-prime-lite-edition-design-software-version-25-1-linux
Required components:
  QuartusLiteSetup-25.1std.0.1129-linux.run (SHA1 ce0773469eacab5b7035c175484625f4ec3737d1)
  cyclonev-25.1std.0.1129.qdz (SHA1 a7225ec1bd36ccfd6826ea6273df5d21dd95633b)
Place them together in a local directory, then run:
  bash tools/fpga/install-quartus.sh /absolute/path/to/downloads /absolute/path/to/install
Use the external drive for installation if internal disk space is still low.
MESSAGE
    exit 1
fi
cd "$root"
if [ "$kind" = native ]; then python3 tools/fpga/evidence.py end fpga;fi
