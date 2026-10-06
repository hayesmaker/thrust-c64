#!/usr/bin/env bash
# Deploy a tag (or branch) on the server, as the user that runs pm2:
#   ./deploy/update.sh v0.2.0
# Builds and tests before switching; on failure the running version stays up.
set -euo pipefail

main() {
  local ref=${1:?usage: deploy/update.sh <tag or branch>}
  local root; root=$(cd "$(dirname "$0")/.." && pwd)
  local app=$root/packages/level-editor
  cd "$root"

  # pm2/node installed with nvm are not on PATH in a plain ssh command
  [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh"

  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "the checkout has local changes: not deploying"; git status --short; exit 1
  fi
  git fetch -q --tags --prune --force origin
  local target=$ref
  git rev-parse -q --verify "refs/tags/$ref" >/dev/null || target=origin/$ref
  local prev; prev=$(git rev-parse HEAD)
  echo "→ $(git describe --tags --always "$prev") -> $ref"
  git checkout -q --detach "$target"
  trap 'echo "❌ failed: checkout restored, the running version is unchanged"; git checkout -q --detach "$prev"' ERR

  cd "$app"
  echo "→ npm ci"; npm ci --no-audit --no-fund
  echo "→ build"; npx tsc --noEmit; npx vite build --outDir dist.new --emptyOutDir --logLevel warn
  echo "→ tests (KickAssembler in the sandbox)"
  KICKASS=/opt/KickAss.jar KICKASS_JAVA="$root/deploy/kickass-sandbox.sh" npx vitest run --reporter=dot

  echo "→ switch"
  rm -rf dist.old; [ -d dist ] && mv dist dist.old; mv dist.new dist
  pm2 startOrReload "$root/deploy/ecosystem.config.cjs" --update-env
  pm2 save >/dev/null
  trap - ERR

  for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl -fsS -o /dev/null http://127.0.0.1:5180/api/source && { echo "✅ $ref is live"; return; }
    sleep 1
  done
  echo "⚠️  pm2 reloaded but the server does not answer: pm2 logs thrust-level-editor"; exit 1
}

main "$@"; exit # read whole before running: git checkout may rewrite this file
