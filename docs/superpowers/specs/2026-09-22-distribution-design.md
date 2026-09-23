# Distribution design — 2026-09-22

## Goal
Anyone with a Mac can install Skills Manager without Xcode: download a DMG from
GitHub Releases or `brew install --cask henrykkim/tap/skills-manager`.

## Decisions (Henry, 2026-09-22)
- Format: DMG with drag-to-Applications (hdiutil, no background image for now).
- Versioning: semver from git tags `vX.Y.Z`, starting at 0.1.0. Build number = workflow run number.
- Signing: Developer ID Application + hardened runtime + notarization (paid account exists).
- Icon: temporary placeholder (`scripts/make-icon.swift` → `App/Resources/AppIcon.icns`); real icon comes with the design pass.
- Homebrew: own tap `henrykkim/homebrew-tap`; cask template kept in `packaging/homebrew/`.
- Sparkle in-app updates: deferred to a follow-up once the first release exists.

## Pieces
- `project.yml`: ad-hoc signing in both configs; CI overrides `CODE_SIGN_IDENTITY`/`DEVELOPMENT_TEAM` on the xcodebuild line, hardened runtime, version keys, icon.
- `scripts/make-dmg.sh`: stage app + Applications symlink → UDZO DMG.
- `.github/workflows/release.yml`: on tag push → import cert into temp keychain → build Release → DMG → notarytool submit + staple → GitHub Release with sha256.
- README: Install section first, Build from source for contributors.

## Secrets required (GitHub → Settings → Secrets → Actions)
`DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_TEAM_ID`,
`NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`.
