#!/usr/bin/env bash
# From your own machine: deploy a pushed tag (or branch) to the server.
#   ./deploy/deploy.sh v0.2.0
# DEPLOY_HOST is an ssh host, best an alias in ~/.ssh/config (default: thrust-host),
# so no address or user name lives in this repo.
set -euo pipefail
REF=${1:?usage: deploy/deploy.sh <tag or branch>}
HOST=${DEPLOY_HOST:-thrust-host}
DIR=${DEPLOY_DIR:-/srv/thrust-c64}

git ls-remote --exit-code origin "refs/tags/$REF" "refs/heads/$REF" >/dev/null ||
  { echo "$REF is not on GitHub: git push origin $REF"; exit 1; }
echo "🚀 Deploying $REF to $HOST"
ssh "$HOST" "$DIR/deploy/update.sh '$REF'"
