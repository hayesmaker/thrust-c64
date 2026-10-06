#!/usr/bin/env bash
# Make a release: set the editor's version, commit, tag. Pushing and deploying stay manual.
#   ./deploy/release.sh 0.2.0
set -euo pipefail
V=${1:?usage: deploy/release.sh <version, e.g. 0.2.0>}
cd "$(dirname "$0")/.."

[ "$(git branch --show-current)" = master ] || { echo "release from master"; exit 1; }
# only the changelog may have changes: it goes into the release commit
[ -z "$(git status --porcelain | grep -v ' packages/level-editor/CHANGELOG.md$')" ] ||
  { echo "commit or stash your changes first (the changelog may stay uncommitted)"; exit 1; }
grep -q "^## $V" packages/level-editor/CHANGELOG.md ||
  { echo "add a '## $V' section to packages/level-editor/CHANGELOG.md first"; exit 1; }

(cd packages/level-editor && npm test --silent)
(cd packages/level-editor && npm pkg set version="$V" && npm install --package-lock-only --silent)
git commit -qam "release: level editor v$V"
git tag -a "v$V" -m "Thrust level editor v$V"
echo "Tagged v$V. Next:"
echo "  git push origin master v$V"
echo "  ./deploy/deploy.sh v$V"
