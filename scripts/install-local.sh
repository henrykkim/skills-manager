#!/bin/zsh
# Build the current checkout as Release and make it THE Skills Manager on this
# Mac: quit any running copy, replace /Applications/Skills Manager.app, and
# delete stray Debug builds under the repo and its worktrees so Spotlight and
# Launchpad only ever show one copy.
#
# Usage: scripts/install-local.sh            (run from anywhere in the repo)
#
# Note: /Applications is also where the Homebrew cask (henrykkim/tap/skills-manager)
# installs. Overwriting it here is fine; the next `brew upgrade` replaces it
# with the next tagged release.
set -euo pipefail
setopt null_glob

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Skills Manager"
DEST="/Applications/$APP_NAME.app"
DD="$(mktemp -d /tmp/skills-manager-dd.XXXXXX)"
trap 'rm -rf "$DD"' EXIT

cd "$REPO"
[[ -d SkillsManager.xcodeproj ]] || xcodegen generate >/dev/null

echo "▸ Building Release from $(git rev-parse --short HEAD) ($(git branch --show-current))"
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager \
  -configuration Release -derivedDataPath "$DD" build 2>&1 \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
BUILT="$DD/Build/Products/Release/$APP_NAME.app"
[[ -d "$BUILT" ]] || { echo "build failed"; exit 1; }

echo "▸ Quitting running copies"
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

echo "▸ Installing to $DEST"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"

echo "▸ Removing stray Debug builds"
find "$REPO" -path "*/Build/Products/*/$APP_NAME.app" -prune -print -exec rm -rf {} + 2>/dev/null || true
# DerivedData folders left behind by earlier builds (repo root and worktrees).
rm -rf "$REPO/build" "$REPO"/.claude/worktrees/*/build 2>/dev/null || true
[[ "$REPO" == */.claude/worktrees/* ]] && rm -rf "${REPO%%/.claude/worktrees/*}/build" 2>/dev/null || true

echo "▸ Installed $(defaults read "$DEST/Contents/Info.plist" CFBundleShortVersionString) — launching"
open "$DEST"
