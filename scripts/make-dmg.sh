#!/bin/zsh
# Package a built Skills Manager.app into a drag-to-Applications DMG.
# Usage: scripts/make-dmg.sh <path/to/Skills Manager.app> <out.dmg> [volume name]
set -euo pipefail
APP="$1"; OUT="$2"; VOLNAME="${3:-Skills Manager}"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO -quiet "$OUT"
rm -rf "$STAGE"
echo "wrote $OUT"
