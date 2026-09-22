# Skills Manager

A native macOS app that answers: **what AI-agent skills do I have, what do I
type to use them, and where do they work?** Read-only in v1 — it never
modifies your configuration.

Design: `docs/superpowers/specs/2026-07-14-skills-manager-design.md`

## Build

Requires Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project SkillsManager.xcodeproj -scheme SkillsManager \
  -configuration Debug -derivedDataPath build build
open "build/Build/Products/Debug/Skills Manager.app"
```

## Test

```bash
cd SkillsManagerCore && swift test
```

## Sandbox mode

Point the whole app at a fake home directory (nothing real is read):

```bash
SKILLS_MANAGER_HOME=/path/to/fake/home \
  "build/Build/Products/Debug/Skills Manager.app/Contents/MacOS/Skills Manager"
```

## Reloading

The library reloads itself whenever a skill or plugin folder changes. If it
ever looks stale, press ⌘R to re-scan by hand.
