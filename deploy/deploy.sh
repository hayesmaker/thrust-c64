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
# Runs the update.sh of the version being deployed (not the server's current
# copy), so a fix to it applies on the same deploy.
ssh "$HOST" bash -s -- "$(printf %q "$REF")" "$(printf %q "$DIR")" <<'REMOTE'
set -euo pipefail
ref=$1 dir=$2
cd "$dir"
git fetch -q --tags --prune --force origin
target=$ref
git rev-parse -q --verify "refs/tags/$ref" >/dev/null || target=origin/$ref
script=$(git show "$target:deploy/update.sh")
exec bash -c "$script" "$dir/deploy/update.sh" "$ref"
REMOTE
