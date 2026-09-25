# Automatic Updates (Sparkle) — Design Spec

**Date:** 2026-09-24
**Status:** Approved in brainstorming; pending owner review of this document
**Roadmap note:** completes step 3 of the distribution plan
(`2026-09-22-distribution-design.md`: "Sparkle in-app updates deferred to a
follow-up once the first release exists"). Ships **before** v0.2.0, so 0.2.0 is
the last version anyone updates by hand.

## 1. Problem

Skills Manager v0.1.0 has no way to learn about new versions. People have to
notice a GitHub release or run `brew upgrade`. The owner wants the standard Mac
experience: a **Check for Updates…** menu item, automatic background checks,
and a window that offers new versions.

## 2. Goals and non-goals

### Goals

1. The app checks for updates automatically (about once a day) and on demand
   from **Skills Manager → Check for Updates…**.
2. **Ask first:** a new version shows the standard update window with
   plain-English release notes, **Install Update**, **Remind Me Later**, and
   **Skip This Version**. Nothing installs without a click.
3. Updates are cryptographically signed. The app installs only updates signed
   with the owner's key, on top of Apple's Developer ID signature and
   notarization.
4. Releasing stays one action: push a `vX.Y.Z` tag. The release workflow
   produces and publishes everything the updater needs.
5. The owner's own local builds never offer to replace themselves with the
   public release.

### Non-goals

- Silent installs or a Settings toggle for them (option B/C in brainstorming).
- A Settings window. The menu item is the only UI added.
- Delta updates, beta or pre-release channels, and feed history.
- Automating the Homebrew tap bump (still manual per release).
- Updating v0.1.0 users automatically. That's impossible, because v0.1.0 has
  no updater. They update once by hand to 0.2.0.

## 3. Decisions (owner, 2026-09-24)

| Topic | Decision |
|---|---|
| Updater | Sparkle 2 (Swift Package Manager) |
| Behavior | Check automatically; ask before installing (A) |
| First-run permission prompt | Skipped. Automatic checks on from the start, since checking never installs |
| Release notes | A short plain-English "What's new" per release, drafted by Claude and edited by the owner, stored in the repo (B) |
| Feed hosting | `appcast.xml` attached to each GitHub Release; the app reads the "latest release" download URL (option 1) |

## 4. User experience

- **Menu:** **Skills Manager → Check for Updates…**, placed directly after
  **About Skills Manager**. It's disabled while a check or update is already
  in progress.
- **Background checks:** Sparkle's default schedule (every 24 hours), starting
  from the first launch with no permission prompt.
- **Update available:** Sparkle's standard window, showing the version, the
  release notes rendered as formatted text, and the three buttons.
- **Install Update:** download, verify the EdDSA signature and Apple code
  signature, replace the app, relaunch.
- **Up to date (manual check):** Sparkle's standard "You're up to date"
  message.
- **Offline or feed unreachable:** a background check fails silently. A manual
  check shows Sparkle's standard error message.

## 5. App changes

- **Dependency:** Sparkle 2 via SPM in `project.yml`
  (`https://github.com/sparkle-project/Sparkle`, pinned with
  `exactVersion 2.10.0`), linked to the app target. Xcode embeds and signs
  `Sparkle.framework`. The app isn't sandboxed, so no installer XPC services
  or extra entitlements are needed.
- **Updater object:** one `SPUStandardUpdaterController` owned by the app,
  created at launch with `startingUpdater: true`.
- **Menu:** a `CommandGroup(after: .appInfo)` button bound to
  `updater.checkForUpdates()`. Its disabled state follows
  `updater.canCheckForUpdates` (observed via KVO/Combine).
- **Info.plist keys** (through `project.yml` `info.properties`):

| Key | Value |
|---|---|
| `SUFeedURL` | `https://github.com/henrykkim/skills-manager/releases/latest/download/appcast.xml` |
| `SUPublicEDKey` | the owner's public EdDSA key (base64) |
| `SUEnableAutomaticChecks` | `$(SU_AUTOMATIC_CHECKS)` |
| `SUAutomaticallyUpdate` | `NO` |
| `SUAllowsAutomaticUpdates` | `NO` |

- **Local builds have checks off:** `project.yml` defines the build setting
  `SU_AUTOMATIC_CHECKS: NO`. The release workflow passes
  `SU_AUTOMATIC_CHECKS=YES` on its `xcodebuild` line (as it already does for
  the version and signing settings). Debug builds and `install-local.sh`
  builds never check on their own, but **Check for Updates…** still works for
  testing.

## 6. Release process changes

### 6.1 One-time key setup (owner + Claude)

1. Run Sparkle's `generate_keys` tool on the owner's Mac. It creates an
   EdDSA key pair and stores the private key in the login Keychain, then
   prints the public key.
2. The owner exports the private key (`generate_keys -x <file>`) and adds its
   contents as GitHub secret **`SPARKLE_PRIVATE_KEY`**. Claude never reads the
   value.
3. The owner keeps a backup of the exported private key with the existing
   Apple signing files (Dropbox), then deletes the exported file from the Mac.
4. The public key goes into `SUPublicEDKey` (it's safe to commit).

If the private key is lost, no further updates can be signed for existing
installs. Users would need one manual update to a build that trusts a new key.

### 6.2 Release notes per version

- File: `release-notes/<version>.md` (for example `release-notes/0.2.0.md`).
- Content: 2–5 short plain-English bullet lines, written for someone who has
  never opened a terminal. Sentence case, no jargon, no PR numbers.
- It's committed to `main` before the tag is pushed. Claude drafts it from the
  merged PRs since the last tag; the owner edits and approves it.
- **Guard:** the workflow fails before building if the file for the tag's
  version is missing or empty.

### 6.3 Workflow steps added to `release.yml`

In order, after the existing "Notarize and staple" step and before "Publish
release":

1. **Use the SwiftPM Sparkle tools:** Build already resolved and
   checksum-verified Sparkle 2.10.0 via SPM (Build uses
   `-derivedDataPath build`), so `sign_update` is already on disk at
   `build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update`. No
   separate download.
2. **Sign the DMG:** run that `sign_update` on the stapled DMG with the
   private key from `SPARKLE_PRIVATE_KEY` (passed through stdin, never a
   file). Capture `sparkle:edSignature` and `length`.
3. **Write `appcast.xml`:** a single-item RSS feed with:
   - `sparkle:version` = the build number (`GITHUB_RUN_NUMBER`)
   - `sparkle:shortVersionString` = `X.Y.Z`
   - `sparkle:minimumSystemVersion` = `14.0`
   - `pubDate`
   - `enclosure` url = the release DMG download URL, with type
     `application/octet-stream`, plus the signature and length
   - `description` = the release notes converted from markdown bullets to
     simple HTML (`<ul><li>…</li></ul>`), wrapped in CDATA
4. **Verify before publishing:**
   - `xmllint --noout appcast.xml` succeeds.
   - The DMG's signature verifies against the public key taken from the built
     app's `Info.plist` `SUPublicEDKey`, using
     `scripts/verify-update-signature.swift` (CryptoKit). This catches a
     secret or key mismatch.

   If either check fails, the release stops and nothing is published.
5. **Publish:** `gh release create` also attaches `appcast.xml`. The existing
   GitHub-generated notes stay on the release page for developers.

Before packaging, a "Re-sign Sparkle for notarization" step re-signs
`Sparkle.framework`'s nested executables (Installer.xpc, Downloader.xpc,
Autoupdate, Updater.app) and the framework itself with the Developer ID
identity, then re-verifies the whole app — Xcode's own signature on the SPM
framework doesn't survive notarization's stricter checks otherwise.

The build number stays `GITHUB_RUN_NUMBER`, which only increases, so Sparkle's
version comparison always sees newer releases as newer.

### 6.4 Homebrew

The tap's `Casks/skills-manager.rb` (and the template in
`packaging/homebrew/`) gains `auto_updates true`. The version and sha256 are
still bumped by hand each release.

## 7. Testing

- **Settings check (`scripts/check-update-settings.sh`, run on a built app; the app target has no unit tests):**
  - `SUFeedURL` equals the latest-release appcast URL.
  - `SUPublicEDKey` is present.
  - `SUAutomaticallyUpdate` is `NO`.
  - `SUEnableAutomaticChecks` is `NO` in local builds and `YES` when built
    with `SU_AUTOMATIC_CHECKS=YES`.
- **Local rehearsal (before any real release)** uses a throwaway key pair and
  a local HTTP server:
  1. Build version A (lower build number) with the test public key and a
     `SUFeedURL` pointing at `http://localhost:<port>/appcast.xml`, using a
     temporary override that is never committed.
  2. Build and sign version B (higher build number) as a DMG with the test
     private key. Write its appcast with the same script logic the workflow
     uses.
  3. **Check for Updates…** in A shows B's notes. Install replaces and
     relaunches as B.
  4. Break B's signature → A refuses the update.
- **Workflow script check:** the appcast-writing logic lives in one script
  (`scripts/make-appcast.sh`) used by both the workflow and the rehearsal, so
  the rehearsal exercises the real code.
- **Live end to end:**
  1. Release 0.2.0 (the one manual update).
  2. Release a small 0.2.1 (a notes-only change).
  3. The owner confirms 0.2.0 offers 0.2.1 and updates itself.

## 8. Order of work

1. App: Sparkle dependency, updater, menu item, Info.plist keys, the local
   checks-off setting, and tests.
2. Release pipeline: `scripts/make-appcast.sh`, the notes guard, the signing,
   verification, and publish steps in `release.yml`, and the Homebrew
   `auto_updates true`.
3. Local rehearsal with a throwaway key.
4. One-time real key setup (owner adds the secret).
5. Write `release-notes/0.2.0.md` (owner approves), bump
   `MARKETING_VERSION` to 0.2.0, tag v0.2.0, and bump the Homebrew tap.
6. Release 0.2.1 as the live update test.

## 9. Risks

- **Private key loss** means existing installs can't receive signed updates.
  Mitigated by the Dropbox backup (§6.1).
- **GitHub "latest" semantics:** only a published, non-pre-release release
  counts as latest, so a failed or draft release is never offered. The
  appcast lists only the newest version, which is fine because Sparkle
  updates from any older version straight to it.
- **Sparkle version drift:** the CI `sign_update` tool comes from the same
  SwiftPM artifact as the embedded `Sparkle.framework`, so the two can never
  drift apart. Both are pinned by the single `exactVersion` in `project.yml`.
