#!/bin/bash
set -euo pipefail
for executable in /opt/altera/quartus/linux64/quartus_*; do
    if [ ! -f "$executable" ] || [ ! -x "$executable" ] || [[ "$executable" == *.pdc-elf ]]; then continue;fi
    if [ -e "$executable.pdc-elf" ]; then continue;fi
    signature="$(head -c 4 "$executable" | od -An -tx1 | tr -d ' \n')"
    if [ "$signature" != 7f454c46 ]; then continue;fi
    mv "$executable" "$executable.pdc-elf"
    printf '#!/bin/sh\nexec /usr/local/bin/qemu-x86_64-static -0 "%s" "%s.pdc-elf" "$@"\n' "$executable" "$executable" > "$executable"
    chmod +x "$executable"
done
