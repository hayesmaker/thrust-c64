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
  --ro-bind-try /etc/ld.so.cache /etc/ld.so.cache
  --ro-bind "$(readlink -f "$KICKASS")" "$KICKASS"
  --proc /proc --dev /dev --tmpfs /tmp
  --bind "$HERE" "$HERE" --chdir "$HERE"
  --unshare-all --die-with-parent --new-session
  --clearenv --setenv PATH /usr/bin --setenv HOME /tmp
)
# merged /usr (links) or not (real folders, older upgraded Debian)
for d in lib lib64 lib32 bin; do
  if [ -L "/$d" ]; then args+=(--symlink "$(readlink "/$d")" "/$d")
  elif [ -d "/$d" ]; then args+=(--ro-bind "/$d" "/$d")
  fi
done
# the JDK's conf/ links into /etc/java-NN-openjdk on Debian/Ubuntu
for d in /etc/java-*; do [ -d "$d" ] && args+=(--ro-bind "$d" "$d"); done

exec bwrap "${args[@]}" -- "$JAVA" -Xmx256m "$@"
