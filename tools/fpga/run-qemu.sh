#!/bin/bash
set -euo pipefail
export QUARTUS_ROOTDIR=/opt/altera/quartus
export QUARTUS_BINDIR="$QUARTUS_ROOTDIR/linux64"
export QUARTUS_BIT_TYPE=64
export LD_LIBRARY_PATH="$QUARTUS_BINDIR"
export PATH="$QUARTUS_BINDIR:$PATH"
"$QUARTUS_BINDIR/quartus_sh" -t apf/build_id_gen.tcl
for tool in quartus_map quartus_fit quartus_asm quartus_sta; do
    "$QUARTUS_BINDIR/$tool" ap_core -c ap_core
    if [ "$tool" = quartus_map ] && [ -e validate-mapping.tcl ]; then
        "$QUARTUS_BINDIR/quartus_sta" -t validate-mapping.tcl
    fi
done
if [ -e validate-timing.tcl ]; then
    "$QUARTUS_BINDIR/quartus_sta" -t validate-timing.tcl
fi
