#!/bin/sh
# Assemble src/thrust.asm with KickAssembler into build/ and compare the
# result with the unpacked original.
#   KICKASS=/path/to/KickAss.jar ./build.sh      (default /opt/KickAss.jar)
#   ./build.sh run                                 also start it in VICE
set -e
cd "$(dirname "$0")"
KICKASS=${KICKASS:-/opt/KickAss.jar}
mkdir -p build
java -jar "$KICKASS" src/thrust.asm -odir ../build -vicesymbols -symbolfile > build/kickass.log 2>&1 || {
    cat build/kickass.log; exit 1; }
if cmp -s build/thrust.prg orig/thrust_unpacked.prg; then
    echo "OK: build/thrust.prg is identical to orig/thrust_unpacked.prg"
else
    echo "NOTE: build/thrust.prg differs from the original (expected if you changed the source)"
fi
if [ "$1" = "run" ]; then
    # -autostartprgmode 1 injects the PRG straight into RAM, so it works without
    # a disk drive; +saveres keeps this session from changing your vicerc
    x64sc +saveres -autostartprgmode 1 -moncommands build/thrust.vs -autostart build/thrust.prg \
        > build/vice.log 2>&1 &
    echo "Started x64sc (log: build/vice.log)"
fi
