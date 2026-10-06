#!/usr/bin/env bash
# One-time (re-runnable) server setup for the level editor. On the server, from the checkout:
#   sudo ./deploy/provision.sh
# Installs Java, bubblewrap and KickAssembler, and the nginx site. Touches nothing else.
set -euo pipefail

KICKASS_VERSION=5.25
KICKASS_SHA256=9592a39336e73a1db8b4a7749256d62d29b113b1c7f0f6c86ea43870ebd9ae1f # KickAss.jar 5.25
KICKASS_DIR=/opt/kickass/$KICKASS_VERSION
SITE=thrust.hayesmaker64.com
ROOT=$(cd "$(dirname "$0")/.." && pwd)

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

echo "→ Java, bubblewrap"
apt-get update -qq
apt-get install -y -qq openjdk-21-jre-headless bubblewrap unzip curl

echo "→ KickAssembler $KICKASS_VERSION"
if [ "$(sha256sum "$KICKASS_DIR/KickAss.jar" 2>/dev/null | cut -d' ' -f1)" != "$KICKASS_SHA256" ]; then
  if [ -n "${1:-}" ]; then
    jar=$1 # a KickAss.jar you copied up: sudo ./deploy/provision.sh /tmp/KickAss.jar
  else
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/ka.zip" https://theweb.dk/KickAssembler/KickAssembler.zip
    unzip -q -o "$tmp/ka.zip" -d "$tmp"
    jar=$(find "$tmp" -name KickAss.jar | head -1)
  fi
  got=$(sha256sum "$jar" | cut -d' ' -f1)
  if [ "$got" != "$KICKASS_SHA256" ]; then
    echo "KickAss.jar is not version $KICKASS_VERSION (sha256 $got)."
    echo "Copy the one you build with: scp /opt/KickAss.jar <host>:/tmp/ && sudo ./deploy/provision.sh /tmp/KickAss.jar"
    exit 1
  fi
  install -D -m 644 "$jar" "$KICKASS_DIR/KickAss.jar"
fi
ln -sfn "$KICKASS_DIR/KickAss.jar" /opt/KickAss.jar

echo "→ sandbox check"
tmp=$(mktemp -d)
printf '*=$1000\n.byte 1\n' > "$tmp/t.asm"
chmod -R a+rwX "$tmp"
if ! (cd "$tmp" && sudo -u "${SUDO_USER:-nobody}" KICKASS=/opt/KickAss.jar "$ROOT/deploy/kickass-sandbox.sh" -jar /opt/KickAss.jar t.asm >/dev/null 2>&1); then
  echo "KickAssembler does not run inside bubblewrap. Output:"
  (cd "$tmp" && sudo -u "${SUDO_USER:-nobody}" "$ROOT/deploy/kickass-sandbox.sh" -jar /opt/KickAss.jar t.asm) || true
  echo "On Ubuntu 23.10+ AppArmor may block it: see deploy/README.md, 'Sandbox fails'."
  exit 1
fi
rm -rf "$tmp"

echo "→ nginx site $SITE"
conf=/etc/nginx/sites-available/$SITE
if [ -e "$conf" ]; then
  echo "  $conf exists: left alone (certbot edits it). Compare with deploy/nginx/ by hand."
else
  cp "$ROOT/deploy/nginx/$SITE.conf" "$conf"
  ln -sfn "$conf" "/etc/nginx/sites-enabled/$SITE"
  nginx -t
  systemctl reload nginx
fi

echo "✅ Provisioned. Next, as ${SUDO_USER:-your user}: ./deploy/update.sh <tag or branch>"
