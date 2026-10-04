#!/bin/sh
# Build thrusty-levels (the hand-edited mod source in thrusty-levels/src) into
# thrusty-levels/build/thrusty-levels.prg (+ .sym, .vs).
# thrusty-levels/src is NOT touched by tools/regen.sh, so edit it freely.
#   ./thrusty-levels/build.sh            build and compare with the original
#   ./thrusty-levels/build.sh run        also start it in VICE
set -e
cd "$(dirname "$0")"
KICKASS=${KICKASS:-/opt/KickAss.jar}
mkdir -p build
java -jar "$KICKASS" src/thrust.asm -odir ../build -vicesymbols -symbolfile > build/kickass.log 2>&1 || {
    cat build/kickass.log; exit 1; }
for e in prg sym vs; do mv build/thrust.$e build/thrusty-levels.$e; done
if cmp -s build/thrusty-levels.prg ../orig/thrust_unpacked.prg; then
    echo "OK: thrusty-levels/build/thrusty-levels.prg is identical to the original"
else
    echo "NOTE: thrusty-levels/build/thrusty-levels.prg differs from the original (expected if you changed the source)"
fi
if [ "$1" = "run" ]; then
    x64sc +saveres -autostartprgmode 1 -moncommands build/thrusty-levels.vs -autostart build/thrusty-levels.prg \
        > build/vice.log 2>&1 &
    echo "Started x64sc (log: thrusty-levels/build/vice.log)"
fi
