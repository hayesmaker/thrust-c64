#!/bin/sh
# Regenerate src/thrust.asm from the annotations and verify the build.
set -e
cd "$(dirname "$0")/.."
python3 tools/bbcmatch.py >/dev/null
python3 tools/apply_bbc.py | tail -1
python3 tools/disasm.py
./build.sh | tee /dev/stderr | grep -q '^OK'
