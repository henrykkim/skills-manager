#!/bin/zsh
# Asserts a built Skills Manager.app carries the update settings from the
# auto-updates spec. Usage: scripts/check-update-settings.sh <App.app> <YES|NO>
# Set ALLOW_EMPTY_KEY=1 to accept an empty SUPublicEDKey (before key setup).
set -euo pipefail
APP="$1"; EXPECT_CHECKS="$2"
PLIST="$APP/Contents/Info.plist"
FEED="https://github.com/henrykkim/skills-manager/releases/latest/download/appcast.xml"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || echo "<missing>"; }
fail() { echo "✗ $1"; exit 1; }

[[ "$(pb SUFeedURL)" == "$FEED" ]] || fail "SUFeedURL is '$(pb SUFeedURL)'"
[[ "$(pb SUAutomaticallyUpdate)" == "false" ]] || fail "SUAutomaticallyUpdate is '$(pb SUAutomaticallyUpdate)' (want false)"
[[ "$(pb SUAllowsAutomaticUpdates)" == "false" ]] || fail "SUAllowsAutomaticUpdates is '$(pb SUAllowsAutomaticUpdates)' (want false)"
[[ "$(pb SUEnableAutomaticChecks)" == "$EXPECT_CHECKS" ]] || fail "SUEnableAutomaticChecks is '$(pb SUEnableAutomaticChecks)' (want $EXPECT_CHECKS)"
KEY="$(pb SUPublicEDKey)"
[[ "$KEY" != "<missing>" ]] || fail "SUPublicEDKey is missing"
[[ -n "$KEY" || "${ALLOW_EMPTY_KEY:-0}" == "1" ]] || fail "SUPublicEDKey is empty"
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework is not embedded"
echo "✓ update settings OK ($EXPECT_CHECKS)"
