#!/usr/bin/env bash
# Runs KickAssembler inside bubblewrap for the build API (KICKASS_JAVA points here).
# Called like java: kickass-sandbox.sh -jar <KickAss.jar> <args>, from the build folder.
# KickAssembler scripts can read and write files (LoadBinary, .import, .file), so the
# sandbox sees only /usr (read-only), the jar and the build folder; no network, no home.
# Fails closed: if bwrap does not work, the build fails.
set -euo pipefail

JAVA=$(readlink -f "$(command -v java)")
KICKASS=${KICKASS:-/opt/KickAss.jar}
HERE=$(pwd -P)

args=(
  --ro-bind /usr /usr
  --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/bin /bin
  --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache
  --ro-bind "$(readlink -f "$KICKASS")" "$KICKASS"
  --proc /proc --dev /dev --tmpfs /tmp
  --bind "$HERE" "$HERE" --chdir "$HERE"
  --unshare-all --die-with-parent --new-session
  --clearenv --setenv PATH /usr/bin --setenv HOME /tmp
)
# the JDK's conf/ links into /etc/java-NN-openjdk on Debian/Ubuntu
for d in /etc/java-*; do [ -d "$d" ] && args+=(--ro-bind "$d" "$d"); done

exec bwrap "${args[@]}" -- "$JAVA" -Xmx256m "$@"
