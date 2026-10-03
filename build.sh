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
    x64sc -moncommands build/thrust.vs -autostart build/thrust.prg >/dev/null 2>&1 &
fi
