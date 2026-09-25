# Automatic Updates (Sparkle) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skills Manager checks for updates automatically and from a **Check for Updates…** menu item, asks before installing, and each tagged release publishes a signed `appcast.xml` next to the DMG.

**Architecture:** Sparkle 2.10.0 is added through XcodeGen as an SPM package. The app owns one `SPUStandardUpdaterController`, and a SwiftUI command adds the menu item. The Info.plist update keys come from build settings so that local builds default to "no automatic checks" and CI flips that on. The release workflow gains a notes guard, a Sparkle re-sign step, EdDSA signing, and appcast generation (`scripts/make-appcast.sh`). Before publishing, it verifies the signature with a CryptoKit script against the public key read from the built app.

**Tech Stack:** Swift 6 / SwiftUI (macOS 14+), XcodeGen, Sparkle 2.10.0, GitHub Actions (macos-26), zsh, CryptoKit (Ed25519), xmllint. Spec: `docs/superpowers/specs/2026-09-24-auto-updates-design.md`.

## Global Constraints

- Sparkle version **2.10.0**, pinned with `exactVersion` in `project.yml`. The workflow reads the version from `project.yml`; don't hard-code it anywhere else.
- Feed URL, exactly: `https://github.com/henrykkim/skills-manager/releases/latest/download/appcast.xml`
- Info.plist keys come from these build settings (defaults in `project.yml`):
  - `SU_FEED_URL` = the feed URL
  - `SPARKLE_PUBLIC_KEY` = `""` until Task 4 fills it
  - `SU_AUTOMATIC_CHECKS` = `NO`
- `SUAutomaticallyUpdate` is always `NO` (ask before installing).
- CI passes `SU_AUTOMATIC_CHECKS=YES` on the release `xcodebuild` line. Local and Debug builds never check on their own.
- Menu item text, exactly: `Check for Updates…` (single ellipsis character), in `CommandGroup(after: .appInfo)`.
- The private key never appears in logs, the repo, or files that outlive a step. Claude never reads its value.
- Release notes live at `release-notes/<X.Y.Z>.md`. The workflow fails before building if the file is missing or empty.
- The app target has no unit tests. Settings are verified by `scripts/check-update-settings.sh` on a built app. Scripts get shell tests in `scripts/tests/`.
- App build: from the repo root, `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build`. Core tests (`cd SkillsManagerCore && swift test`) must stay green (122).
- After an app change the owner will look at: run `scripts/install-local.sh`.
- Commit after every task. The last line of every commit message is `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Tasks 4–7 are controller- and owner-driven** (key setup, GUI rehearsal, and public releases). They are not dispatched to implementer subagents. Every outward-facing step (a secret, a tag push, a release, a tap push) needs the owner's explicit go-ahead at that moment.

---

## File map

| File | Change |
|---|---|
| `project.yml` | Sparkle package, target dependency, 3 build settings, 4 Info.plist keys |
| `App/UpdaterCommands.swift` | **new**: the Check for Updates… command view and its view model |
| `App/SkillsManagerApp.swift` | owns `SPUStandardUpdaterController`; adds the command |
| `scripts/check-update-settings.sh` | **new**: asserts the Info.plist update keys on a built app |
| `scripts/make-appcast.sh` | **new**: writes `appcast.xml` from version, build, URL, signature, notes |
| `scripts/verify-update-signature.swift` | **new**: Ed25519 verify of a file against a base64 public key |
| `scripts/tests/test-make-appcast.sh` | **new** |
| `scripts/tests/test-verify-signature.sh` | **new** |
| `.github/workflows/release.yml` | notes guard, CI setting, Sparkle re-sign, sign, appcast, verify, attach |
| `packaging/homebrew/skills-manager.rb` | `auto_updates true` |
| `release-notes/0.2.0.md` | **new** (Task 6, owner-approved) |

---

### Task 1: App — Sparkle, updater, menu item, update settings

**Files:**
- Modify: `project.yml`
- Create: `App/UpdaterCommands.swift`
- Modify: `App/SkillsManagerApp.swift`
- Create: `scripts/check-update-settings.sh`

**Interfaces:**
- Produces:
  - Build settings `SU_FEED_URL`, `SPARKLE_PUBLIC_KEY`, `SU_AUTOMATIC_CHECKS`, used by Task 3 (CI override) and Task 4 (key).
  - `scripts/check-update-settings.sh <path/to/App.app> <YES|NO>`: exit 0 if the keys match (feed URL exact, `SUAutomaticallyUpdate` false, `SUEnableAutomaticChecks` equals the argument, and `SUPublicEDKey` present, empty allowed only when the env var `ALLOW_EMPTY_KEY=1`), otherwise exit 1 with a message naming the key.

- [ ] **Step 1: Write the settings check script (the "test")**

`scripts/check-update-settings.sh`:

```zsh
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
[[ "$(pb SUEnableAutomaticChecks)" == "$EXPECT_CHECKS" ]] || fail "SUEnableAutomaticChecks is '$(pb SUEnableAutomaticChecks)' (want $EXPECT_CHECKS)"
KEY="$(pb SUPublicEDKey)"
[[ "$KEY" != "<missing>" ]] || fail "SUPublicEDKey is missing"
[[ -n "$KEY" || "${ALLOW_EMPTY_KEY:-0}" == "1" ]] || fail "SUPublicEDKey is empty"
[[ -d "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "Sparkle.framework is not embedded"
echo "✓ update settings OK ($EXPECT_CHECKS)"
```

Run: `chmod +x scripts/check-update-settings.sh`

- [ ] **Step 2: Run it against the current build to see it fail**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "BUILD" ; ALLOW_EMPTY_KEY=1 scripts/check-update-settings.sh "build/Build/Products/Debug/Skills Manager.app" NO`
Expected: `✗ SUFeedURL is '<missing>'`, exit 1.

- [ ] **Step 3: project.yml**

Add under `packages:`:

```yaml
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    exactVersion: 2.10.0
```

Add under `settings: base:`:

```yaml
    # Automatic updates (Sparkle). The release workflow sets
    # SU_AUTOMATIC_CHECKS=YES; local builds never check on their own.
    SU_FEED_URL: "https://github.com/henrykkim/skills-manager/releases/latest/download/appcast.xml"
    SPARKLE_PUBLIC_KEY: ""
    SU_AUTOMATIC_CHECKS: "NO"
```

Add to the `SkillsManager` target's `dependencies:`: `- package: Sparkle`

Add to the target's `info: properties:`:

```yaml
        SUFeedURL: "$(SU_FEED_URL)"
        SUPublicEDKey: "$(SPARKLE_PUBLIC_KEY)"
        SUEnableAutomaticChecks: "$(SU_AUTOMATIC_CHECKS)"
        SUAutomaticallyUpdate: false
```

- [ ] **Step 4: Updater command**

`App/UpdaterCommands.swift`:

```swift
import Combine
import Sparkle
import SwiftUI

/// Mirrors SPUUpdater.canCheckForUpdates so the menu item greys out while a
/// check or update is already running.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }
}

/// Skills Manager → Check for Updates…
struct CheckForUpdatesView: View {
    @ObservedObject private var model: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.model = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!model.canCheckForUpdates)
    }
}
```

- [ ] **Step 5: Wire it into the app**

In `App/SkillsManagerApp.swift` add `import Sparkle`, add the property below `store`:

```swift
    /// Sparkle's standard updater: checks on its own schedule (release builds
    /// only — see SU_AUTOMATIC_CHECKS) and always asks before installing.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
```

and add as the first item inside `.commands {`:

```swift
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
```

If Swift 6 strict concurrency rejects any of this, make the smallest change that compiles cleanly, such as marking the view model `@MainActor` or constructing the controller in `init`. Record what you changed.

- [ ] **Step 6: Build and run the check**

Run: `xcodegen generate && xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|warning: .*(Sparkle|Updater)|BUILD"`
Expected: `** BUILD SUCCEEDED **`, with no Swift errors or warnings from our files.

Run: `ALLOW_EMPTY_KEY=1 scripts/check-update-settings.sh "build/Build/Products/Debug/Skills Manager.app" NO`
Expected: `✓ update settings OK (NO)`

Run: `xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager -configuration Release -derivedDataPath build/ci-check SU_AUTOMATIC_CHECKS=YES build 2>&1 | grep BUILD && ALLOW_EMPTY_KEY=1 scripts/check-update-settings.sh "build/ci-check/Build/Products/Release/Skills Manager.app" YES`
Expected: `** BUILD SUCCEEDED **`, then `✓ update settings OK (YES)`. This proves the CI override flips the setting.

Run: `cd SkillsManagerCore && swift test 2>&1 | grep "Test run"`. Expected: 122 passed.

- [ ] **Step 7: Commit**

```bash
git add project.yml App/UpdaterCommands.swift App/SkillsManagerApp.swift scripts/check-update-settings.sh
git commit -m "app: Sparkle updater with Check for Updates… (local builds never auto-check)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Appcast writer and signature verifier (scripts + tests)

**Files:**
- Create: `scripts/make-appcast.sh`, `scripts/verify-update-signature.swift`
- Create: `scripts/tests/test-make-appcast.sh`, `scripts/tests/test-verify-signature.sh`

**Interfaces:**
- Produces (used by Task 3's workflow and Task 5's rehearsal):
  - `scripts/make-appcast.sh --version X.Y.Z --build N --url <dmg-url> --sign-output "<sign_update output>" --notes <notes.md> --out <appcast.xml>`. `--sign-output` is the exact line `sign_update` prints: `sparkle:edSignature="…" length="…"`.
  - `swift scripts/verify-update-signature.swift <file> <signature-base64> <public-key-base64>`: exit 0 and print `✓ signature valid`, or exit 1 with `✗ …`.

- [ ] **Step 1: Write the failing tests**

`scripts/tests/test-make-appcast.sh`:

```zsh
#!/bin/zsh
# Checks make-appcast.sh output is valid XML with the right Sparkle fields.
set -euo pipefail
cd "$(dirname "$0")/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cat > "$T/notes.md" <<'EOF'
- See skills from every project you use with Claude.
- Tags show where each skill works — & "quotes" <stay> safe.

Thanks for using Skills Manager.
EOF
scripts/make-appcast.sh --version 0.2.0 --build 42 \
  --url "https://github.com/henrykkim/skills-manager/releases/download/v0.2.0/SkillsManager-0.2.0.dmg" \
  --sign-output 'sparkle:edSignature="QUJD" length="12345"' \
  --notes "$T/notes.md" --out "$T/appcast.xml"
xmllint --noout "$T/appcast.xml"
x() { xmllint --xpath "$1" "$T/appcast.xml"; }
fail() { echo "✗ $1"; exit 1; }
[[ "$(x 'string(//item/*[local-name()="version"])')" == "42" ]] || fail "sparkle:version"
[[ "$(x 'string(//item/*[local-name()="shortVersionString"])')" == "0.2.0" ]] || fail "shortVersionString"
[[ "$(x 'string(//item/*[local-name()="minimumSystemVersion"])')" == "14.0" ]] || fail "minimumSystemVersion"
[[ "$(x 'string(//enclosure/@url)')" == *"/v0.2.0/SkillsManager-0.2.0.dmg" ]] || fail "enclosure url"
[[ "$(x 'string(//enclosure/@*[local-name()="edSignature"])')" == "QUJD" ]] || fail "edSignature"
[[ "$(x 'string(//enclosure/@length)')" == "12345" ]] || fail "length"
DESC="$(x 'string(//item/description)')"
[[ "$DESC" == *"<li>See skills from every project you use with Claude.</li>"* ]] || fail "first bullet: $DESC"
[[ "$DESC" == *"&amp; &quot;quotes&quot; &lt;stay&gt; safe"* ]] || fail "escaping: $DESC"
[[ "$DESC" == *"<p>Thanks for using Skills Manager.</p>"* ]] || fail "paragraph: $DESC"
# Missing notes must fail.
if scripts/make-appcast.sh --version 0.2.0 --build 1 --url u --sign-output 'sparkle:edSignature="A" length="1"' \
     --notes "$T/nope.md" --out "$T/x.xml" 2>/dev/null; then fail "missing notes accepted"; fi
echo "✓ make-appcast tests passed"
```

`scripts/tests/test-verify-signature.sh`:

```zsh
#!/bin/zsh
# Signs a file with a throwaway Ed25519 key (CryptoKit) and checks the
# verifier accepts it and rejects a tampered file and a wrong key.
set -euo pipefail
cd "$(dirname "$0")/../.."
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
echo "update payload" > "$T/update.dmg"
cat > "$T/sign.swift" <<'EOF'
import CryptoKit
import Foundation
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let key = Curve25519.Signing.PrivateKey()
let other = Curve25519.Signing.PrivateKey()
print(try key.signature(for: data).base64EncodedString())
print(key.publicKey.rawRepresentation.base64EncodedString())
print(other.publicKey.rawRepresentation.base64EncodedString())
EOF
OUT=("${(@f)$(swift "$T/sign.swift" "$T/update.dmg")}")
SIG="$OUT[1]"; PUB="$OUT[2]"; WRONG="$OUT[3]"
swift scripts/verify-update-signature.swift "$T/update.dmg" "$SIG" "$PUB"
if swift scripts/verify-update-signature.swift "$T/update.dmg" "$SIG" "$WRONG" 2>/dev/null; then echo "✗ wrong key accepted"; exit 1; fi
echo "tampered" >> "$T/update.dmg"
if swift scripts/verify-update-signature.swift "$T/update.dmg" "$SIG" "$PUB" 2>/dev/null; then echo "✗ tampered file accepted"; exit 1; fi
echo "✓ verify-signature tests passed"
```

Run: `chmod +x scripts/tests/*.sh && scripts/tests/test-make-appcast.sh; scripts/tests/test-verify-signature.sh`
Expected: both fail because the scripts don't exist yet.

- [ ] **Step 2: Implement make-appcast.sh**

`scripts/make-appcast.sh`:

```zsh
#!/bin/zsh
# Writes a single-item Sparkle appcast for one release (auto-updates spec §6.3).
# Used by .github/workflows/release.yml and the local rehearsal.
set -euo pipefail
zmodload zsh/zutil
zparseopts -D -E -F -A opt -- -version: -build: -url: -sign-output: -notes: -out:
VERSION="${opt[--version]}"; BUILD="${opt[--build]}"; URL="${opt[--url]}"
SIGN="${opt[--sign-output]}"; NOTES="${opt[--notes]}"; OUT="${opt[--out]}"

[[ -s "$NOTES" ]] || { echo "Release notes missing or empty: $NOTES" >&2; exit 1; }
SIG="$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<< "$SIGN")"
LEN="$(sed -nE 's/.*length="([0-9]+)".*/\1/p' <<< "$SIGN")"
[[ -n "$SIG" && -n "$LEN" ]] || { echo "Can't read signature/length from: $SIGN" >&2; exit 1; }

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' <<< "$1"; }
HTML=""; IN_LIST=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "- "* || "$line" == "* "* ]]; then
    (( IN_LIST )) || { HTML+="<ul>"; IN_LIST=1; }
    HTML+="<li>$(esc "${line:2}")</li>"
  else
    (( IN_LIST )) && { HTML+="</ul>"; IN_LIST=0; }
    [[ -n "${line// }" ]] && HTML+="<p>$(esc "$line")</p>"
  fi
done < "$NOTES"
(( IN_LIST )) && HTML+="</ul>"

cat > "$OUT" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Skills Manager</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[$HTML]]></description>
      <enclosure url="$URL" type="application/octet-stream" sparkle:edSignature="$SIG" length="$LEN"/>
    </item>
  </channel>
</rss>
EOF
echo "wrote $OUT"
```

Note: `]]>` inside notes would break CDATA. The escaping of `>` to `&gt;` prevents that. Keep it.

- [ ] **Step 3: Implement verify-update-signature.swift**

`scripts/verify-update-signature.swift`:

```swift
// Verifies a Sparkle EdDSA (Ed25519) update signature against a public key,
// so the release fails if the GitHub secret doesn't match the key built into
// the app. Usage: swift verify-update-signature.swift <file> <sig-b64> <pubkey-b64>
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("usage: verify-update-signature <file> <signature-b64> <public-key-b64>\n".utf8))
    exit(2)
}
do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    guard let sig = Data(base64Encoded: args[2]), let pub = Data(base64Encoded: args[3]) else {
        print("✗ signature or public key isn't valid base64"); exit(1)
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: pub)
    if key.isValidSignature(sig, for: data) {
        print("✓ signature valid")
    } else {
        print("✗ signature does not match this public key"); exit(1)
    }
} catch {
    print("✗ \(error.localizedDescription)"); exit(1)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `chmod +x scripts/make-appcast.sh && scripts/tests/test-make-appcast.sh && scripts/tests/test-verify-signature.sh`
Expected: `✓ make-appcast tests passed` and `✓ verify-signature tests passed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/make-appcast.sh scripts/verify-update-signature.swift scripts/tests
git commit -m "scripts: appcast writer and Ed25519 update-signature verifier, with tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Release workflow and Homebrew template

**Files:**
- Modify: `.github/workflows/release.yml`
- Modify: `packaging/homebrew/skills-manager.rb`

**Interfaces:**
- Consumes: the `SU_AUTOMATIC_CHECKS` build setting (Task 1); `scripts/check-update-settings.sh` (Task 1); `scripts/make-appcast.sh` and `scripts/verify-update-signature.swift` (Task 2); `exactVersion` in `project.yml`.
- Produces: releases with `appcast.xml` attached, and the secret name `SPARKLE_PRIVATE_KEY` (set in Task 4).

- [ ] **Step 1: Notes guard (new first step after checkout)**

Insert after `- uses: actions/checkout@v4`:

```yaml
      - name: Check release notes
        run: |
          VERSION="${GITHUB_REF_NAME#v}"
          NOTES="release-notes/$VERSION.md"
          if [ ! -s "$NOTES" ]; then
            echo "::error::$NOTES is missing or empty. Add plain-English release notes before tagging."
            exit 1
          fi
```

- [ ] **Step 2: Turn on automatic checks for release builds**

In the `Build` step's `xcodebuild` command, add `SU_AUTOMATIC_CHECKS=YES \` on the line after `MARKETING_VERSION=… CURRENT_PROJECT_VERSION=… \`. After the existing `codesign --verify` line, add:

```yaml
          scripts/check-update-settings.sh "build/Build/Products/Release/Skills Manager.app" YES
```

- [ ] **Step 3: Re-sign Sparkle's nested helpers with Developer ID**

Plain `xcodebuild build` doesn't re-sign Sparkle's pre-signed helpers with the team identity, and notarization rejects them otherwise. Insert a new step after `Build` and before `Package DMG`:

```yaml
      - name: Re-sign Sparkle for notarization
        run: |
          APP="build/Build/Products/Release/Skills Manager.app"
          FW="$APP/Contents/Frameworks/Sparkle.framework"
          ID="Developer ID Application"
          SIGN=(codesign -f -s "$ID" -o runtime --timestamp)
          "${SIGN[@]}" "$FW/Versions/B/XPCServices/Installer.xpc"
          "${SIGN[@]}" --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
          "${SIGN[@]}" "$FW/Versions/B/Autoupdate"
          "${SIGN[@]}" "$FW/Versions/B/Updater.app"
          "${SIGN[@]}" "$FW"
          "${SIGN[@]}" --preserve-metadata=entitlements "$APP"
          codesign --verify --deep --strict --verbose=2 "$APP"
```

- [ ] **Step 4: Sign the update, write and verify the appcast**

Insert after `Notarize and staple` and before `Publish release`:

```yaml
      - name: Sign update and write appcast
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          SPARKLE_VERSION=$(sed -nE '/sparkle-project\/Sparkle/,/exactVersion/ s/.*exactVersion: *([0-9.]+).*/\1/p' project.yml)
          curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" -o "$RUNNER_TEMP/sparkle.tar.xz"
          mkdir -p "$RUNNER_TEMP/sparkle" && tar -xJf "$RUNNER_TEMP/sparkle.tar.xz" -C "$RUNNER_TEMP/sparkle"
          DMG="SkillsManager-$VERSION.dmg"
          SIGN_OUT=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$RUNNER_TEMP/sparkle/bin/sign_update" --ed-key-file - "$DMG")
          scripts/make-appcast.sh --version "$VERSION" --build "$GITHUB_RUN_NUMBER" \
            --url "https://github.com/${GITHUB_REPOSITORY}/releases/download/${GITHUB_REF_NAME}/$DMG" \
            --sign-output "$SIGN_OUT" --notes "release-notes/$VERSION.md" --out appcast.xml
          xmllint --noout appcast.xml
          PUB=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "build/Build/Products/Release/Skills Manager.app/Contents/Info.plist")
          SIG=$(sed -nE 's/.*sparkle:edSignature="([^"]+)".*/\1/p' <<< "$SIGN_OUT")
          swift scripts/verify-update-signature.swift "$DMG" "$SIG" "$PUB"
```

- [ ] **Step 5: Attach the appcast**

In `Publish release`, add `appcast.xml` to the `gh release create` asset list, after the `.sha256` file.

- [ ] **Step 6: Homebrew template**

In `packaging/homebrew/skills-manager.rb`, add `auto_updates true` on its own line after `depends_on macos: ">= :sonoma"`, preceded by the comment `# Sparkle updates the app in place; brew shouldn't fight it.`

- [ ] **Step 7: Validate**

Run: `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "yaml ok"'`
Expected: `yaml ok`.

Run: `ruby -c packaging/homebrew/skills-manager.rb`
Expected: `Syntax OK`.

Dry-run the new shell logic locally. Extract the `SPARKLE_VERSION` sed line and run it against `project.yml`.
Expected: `2.10.0`.

- [ ] **Step 8: Commit**

```bash
git add .github/workflows/release.yml packaging/homebrew/skills-manager.rb
git commit -m "release: notes guard, Sparkle re-sign, signed appcast attached to each release

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: One-time update key setup (controller + owner)

Not dispatched to a subagent. The controller runs the commands; the owner handles the secret.

- [ ] **Step 1:** Download Sparkle 2.10.0 tools to the scratchpad (`Sparkle-2.10.0.tar.xz`) and run `bin/generate_keys`. It stores the private key in the login Keychain (item "Private key for signing Sparkle updates") and prints the public key. If a key already exists, it prints the existing public key; that's fine.
- [ ] **Step 2:** Set `SPARKLE_PUBLIC_KEY` in `project.yml` to the printed public key. Commit (`app: add Sparkle public update key`).
- [ ] **Step 3 (owner):** In Terminal, run `generate_keys -x ~/Desktop/sparkle-private-key.txt`, then `gh secret set SPARKLE_PRIVATE_KEY < ~/Desktop/sparkle-private-key.txt`. Then move the file to the Dropbox folder with the Apple signing files. Claude never reads this file.
- [ ] **Step 4:** Confirm with `gh secret list` that `SPARKLE_PRIVATE_KEY` exists (the name only). Rebuild and run `scripts/check-update-settings.sh … NO` without `ALLOW_EMPTY_KEY`.

### Task 5: Local rehearsal (controller + owner GUI)

Not dispatched. It proves the update window, signature rejection, and install before a real release.

- [ ] **Step 1:** Generate a throwaway key: `generate_keys --account skills-manager-rehearsal` (prints the test public key).
- [ ] **Step 2:** Build **A** to a scratch folder with `MARKETING_VERSION=0.0.1 CURRENT_PROJECT_VERSION=1 SPARKLE_PUBLIC_KEY=<test pub> SU_FEED_URL=http://127.0.0.1:8765/appcast.xml`, and copy it to `~/Applications/Skills Manager Rehearsal A.app`.
- [ ] **Step 3:** Build **B** with `MARKETING_VERSION=0.0.2 CURRENT_PROJECT_VERSION=2` and the same key and feed. DMG it with `scripts/make-dmg.sh`, and sign it with `sign_update --account skills-manager-rehearsal`. Write the appcast with `scripts/make-appcast.sh` using test notes and a URL `http://127.0.0.1:8765/B.dmg`. Serve the folder with `python3 -m http.server 8765 --bind 127.0.0.1`.
- [ ] **Step 4 (owner):** Open A, choose **Check for Updates…**, and confirm the window shows B's notes. Install; the app relaunches as 0.0.2 (check About).
- [ ] **Step 5 (owner):** Rebuild A, corrupt the signature in the appcast, and check again. Sparkle must refuse the update with an error.
- [ ] **Step 6:** Clean up: remove the rehearsal apps, stop the server, and delete the test key (`security delete-generic-password -a skills-manager-rehearsal`).

If Sparkle refuses the plain-HTTP localhost feed, record that. The 0.2.1 live test (Task 7) becomes the only end-to-end proof; don't weaken the app's settings to force the rehearsal.

### Task 6: Release v0.2.0 (controller + owner go-ahead)

- [ ] **Step 1:** Draft `release-notes/0.2.0.md` from the merged PRs since v0.1.0 (#9, #10, #11), in 2–5 plain-English bullets. The owner edits and approves it.
- [ ] **Step 2:** Set `MARKETING_VERSION: "0.2.0"` in `project.yml`, commit the notes too, open the PR, and merge after owner approval.
- [ ] **Step 3 (owner go-ahead):** Tag `v0.2.0` on the merged `main` and push the tag. Watch the Release workflow with `gh run watch`.
- [ ] **Step 4:** Check that the release has the DMG, `.sha256`, and `appcast.xml`. Run `curl -sL …/releases/latest/download/appcast.xml | xmllint --noout -` to confirm the stable URL serves it.
- [ ] **Step 5 (owner go-ahead):** In `henrykkim/homebrew-tap`, update `Casks/skills-manager.rb` with version 0.2.0, the new sha256, and `auto_updates true`, then push.
- [ ] **Step 6 (owner):** Install 0.2.0 by hand (DMG or `brew upgrade --cask skills-manager`). **Check for Updates…** should say you're up to date.

### Task 7: Release v0.2.1 as the live update test (controller + owner go-ahead)

- [ ] **Step 1:** Add `release-notes/0.2.1.md` (for example "Skills Manager now updates itself."), set `MARKETING_VERSION: "0.2.1"`, PR, and merge.
- [ ] **Step 2 (owner go-ahead):** Tag `v0.2.1`, push, watch the run, and bump the tap.
- [ ] **Step 3 (owner):** In the installed 0.2.0, choose **Check for Updates…**. The window shows the 0.2.1 notes; Install; the app relaunches as 0.2.1.
