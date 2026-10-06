#!/usr/bin/env bash
# Deploy a tag (or branch) on the server, as the user that runs pm2:
#   ./deploy/update.sh v0.2.0      (or 0.2.0)
# Builds and tests before switching; on failure the running version stays up.
set -euo pipefail

main() {
  local ref=${1:?usage: deploy/update.sh <tag or branch>}
  [[ $ref =~ ^[0-9]+\.[0-9] ]] && ref=v$ref # 0.2.0 means the tag v0.2.0
  local root; root=$(cd "$(dirname "$0")/.." && pwd)
  local app=$root/packages/level-editor
  cd "$root"

  # node from fnm (or nvm) is not on PATH in a plain ssh command
  local fnm; fnm=$(command -v fnm || ls "$HOME/.local/share/fnm/fnm" "$HOME/.fnm/fnm" 2>/dev/null | head -1 || true)
  if [ -n "$fnm" ]; then eval "$("$fnm" env --shell bash)"
  elif [ -s "$HOME/.nvm/nvm.sh" ]; then . "$HOME/.nvm/nvm.sh"
  fi
  # pm2 may belong to any Node (nvm, fnm, system): find it before switching to the
  # editor's Node, and run it with the Node it was installed with
  local pm2bin pm2node
  pm2bin=$(command -v pm2 || ls -d "$HOME"/.nvm/versions/node/*/bin/pm2 \
    "$HOME"/.local/share/fnm/node-versions/*/installation/bin/pm2 2>/dev/null | tail -1 || true)
  [ -n "$pm2bin" ] || { echo "pm2 not found (looked on PATH, in ~/.nvm and in fnm's Node versions)"; exit 1; }
  pm2node=$(readlink -f "$(dirname "$pm2bin")/node" || true)
  [ -x "$pm2node" ] || pm2node=$(command -v node)
  pm2bin=$(readlink -f "$pm2bin")
  pm2() { "$pm2node" "$pm2bin" "$@"; }

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
  # the editor's own Node (.node-version), whatever the other pm2 apps use
  if [ -n "$fnm" ]; then "$fnm" use --install-if-missing --silent-if-unchanged
  elif command -v nvm >/dev/null; then nvm install "$(cat .node-version)" >/dev/null
  fi
  # pm2 gets the real path: fnm's per-shell links are temporary
  export THRUST_NODE; THRUST_NODE=$(readlink -f "$(command -v node)")
  node -e 'const [a,b]=process.versions.node.split(".").map(Number); if (a<22||(a===22&&b<18)) { console.error("Node "+process.version+" is too old (needs 22.18+)"); process.exit(1) }'
  echo "→ node $(node -v) ($THRUST_NODE)"
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
    curl -fs -o /dev/null http://127.0.0.1:5180/api/source && { echo "✅ $ref is live"; return; }
    sleep 1
  done
  echo "⚠️  pm2 reloaded but the server does not answer: pm2 logs thrust-level-editor"; exit 1
}

main "$@"; exit # read whole before running: git checkout may rewrite this file
