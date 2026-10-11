# Recommendations Catalog and the Home Depot Build — Design Spec

**Date:** 2026-10-11
**Status:** Approved in brainstorming; pending owner review of this document
**Builds on:** `2026-09-22-install-box-design.md` (install pipeline),
`2026-09-24-auto-updates-design.md` (Sparkle feed), `2026-09-22-distribution-design.md`
(release workflow and Homebrew cask).

## 1. Problem

The owner wants to hand Skills Manager to Home Depot associates with a curated
starting point: on first launch, the app shows a short list of recommended
plugins and skills that can be installed instantly. Today the app opens to an
empty library and expects the user to find and paste links themselves.

At the same time, the open source project must stay general. Home Depot
specifics should not leak into the experience of other users, and the owner
does not want to maintain two codebases.

## 2. Goals and non-goals

### Goals

1. The open source app gains one generic capability: a bundled **recommendations
   catalog** that, when non-empty, is offered on first launch and remains
   reachable from the menu.
2. A second build, **Skills Manager for Home Depot**, is the same code with a
   different catalog, name, icon label, bundle ID, and update feed.
3. Every general release ships both apps. Associates receive general
   improvements automatically through their own Sparkle feed.
4. Home Depot-specific content lives in the public repo. Every recommended item
   is open source, so nothing private is involved.

### Non-goals

- Recommending anything that lives on Home Depot's internal GitHub (the Eux
  plugins). Those are installable from Claude directly, and the owner wants
  this list to cover only what cannot be installed from inside Claude.
- A remote or user-editable catalog. The catalog is bundled and changes ship
  as releases.
- Compile-time behavior differences between the two targets. The first version
  differs only in bundled content and build settings.
- Separate codebases or a private repo.

## 3. Decisions (owner, 2026-10-11)

| Topic | Decision |
|---|---|
| Separation model | One repo, one codebase, second XcodeGen target (option 1) |
| Catalog source | JSON file bundled per target |
| Home Depot content | Public, in the open source repo |
| Updates | Each build has its own appcast in the same GitHub release |
| Catalog contents | Superpowers plugin; Agentation, Emil's Skills, Jakub's Skills |

## 4. The catalog

Each target bundles `Recommendations.json`. The general target ships an empty
list, so existing behavior is unchanged for open source users.

```json
{
  "title": "Recommended at Home Depot",
  "intro": "A starting set our team uses. Install any or all; you can add more later.",
  "items": [
    { "name": "Superpowers",    "source": "https://github.com/obra/superpowers",
      "blurb": "Workflow skills for Claude Code: brainstorming, planning, TDD, debugging." },
    { "name": "Agentation",     "source": "https://github.com/benjitaylor/agentation",
      "blurb": "Visual feedback toolbar so you can annotate a page for Claude." },
    { "name": "Emil's Skills",  "source": "https://github.com/emilkowalski/skills",
      "blurb": "Design engineering and animation skills." },
    { "name": "Jakub's Skills", "source": "https://github.com/jakubkrehel/skills",
      "blurb": "Accessibility, layout, typography, color and UI polish reviews." }
  ]
}
```

- `source` is any string the Install box already accepts. It goes through
  `InstallIntentParser.parse` and `InstallResolver.resolve`, so plugins and
  skills repos both work without new install code.
- `name` and `blurb` are display-only and come from the catalog, not from
  GitHub, so the sheet renders instantly before any network work.
- `title` and `intro` are optional. Defaults: "Recommended" and no intro.

Core gains `RecommendationsCatalog` (Codable, `load(from:)` for a `Data` blob,
`isEmpty`). Malformed JSON is a programmer error caught by tests, not a user
state; at runtime a decode failure behaves as an empty catalog and logs once.

## 5. User experience

### First launch

When the catalog is non-empty and `UserDefaults` key
`recommendationsDismissed` is false, the main window presents the
**Recommended** sheet after the library has loaded, in the same slot the
Install sheet uses. It is shown once; dismissing it in any way sets the flag.

### The sheet

- Header: catalog `title` and `intro`.
- One row per item: checkbox (on by default), `name`, `blurb`, and a status
  line. Status starts as "Checking…", then becomes the resolved summary
  ("3 skills", "Plugin from the superpowers marketplace"), "Already installed"
  (checkbox off and disabled), or a one-line error from the existing
  `InstallSheetModel.sentence(for:)` copy.
- Footer: **Not now** and **Install Selected** (disabled until at least one
  resolvable item is checked and the needed tools are present; the existing
  `missingTool` copy is reused).
- During install, rows show "Installing…", then "Installed" or the failure
  sentence. Items run sequentially in catalog order so logs stay readable.
  A failure does not stop later items.
- When finished, the footer becomes **Done**. The library reloads through the
  existing file watcher, so new skills appear behind the sheet.

### Later access

**File → Recommended…** opens the same sheet whenever the catalog is
non-empty. The menu item does not exist in the general build because its
catalog is empty. Opening it later shows installed items as already installed.

## 6. Architecture

### Core (`SkillsManagerCore`)

- `Recommendations/RecommendationsCatalog.swift`: the model and loader.
- `Recommendations/RecommendationPlan.swift`: given resolved previews and the
  user's selection, produce the ordered list of `(item, preview, folders)` to
  install. For skills repos, all valid skills in the repo are selected; the
  sheet does not offer per-skill selection in this version.

### App

- `App/Recommendations/RecommendationsModel.swift` (`@Observable`,
  `@MainActor`): holds per-item state (`checking`, `ready(InstallPreview)`,
  `installed`, `unavailable(String)`, `installing`, `done`, `failed(String)`),
  runs resolution concurrently on appear with the same cancellation discipline
  as `InstallSheetModel`, and runs installs sequentially through `Installer`.
- `App/Recommendations/RecommendationsSheet.swift`: the SwiftUI sheet.
- `LibraryView` presents it on first launch and on a new
  `.showRecommendations` notification; `SkillsManagerApp` adds the menu item.
- The catalog is read from `Bundle.main` at startup by `InventoryStore` (it
  already owns first-launch flags) and exposed as `recommendations`.

### Targets (`project.yml`)

| Setting | SkillsManager | SkillsManagerHomeDepot |
|---|---|---|
| Display name | Skills Manager | Skills Manager for Home Depot |
| Bundle ID | com.henrykkim.SkillsManager | com.henrykkim.SkillsManagerHomeDepot |
| Sources | `App` | `App` |
| Catalog | `Catalogs/General/Recommendations.json` | `Catalogs/HomeDepot/Recommendations.json` |
| Feed | `.../releases/latest/download/appcast.xml` | `.../releases/latest/download/appcast-homedepot.xml` |

Both targets depend on the same packages and share the scheme layout. The
icon is unchanged in this version; the display name is the only visible brand
difference. `scripts/install-local.sh` keeps installing the general target
unless passed `--home-depot`.

## 7. Release and distribution

- The release workflow builds both targets from the tag, signs and notarizes
  both, and produces `SkillsManager-X.Y.Z.dmg` and
  `SkillsManagerHomeDepot-X.Y.Z.dmg`.
- `make-appcast.sh` runs twice and writes `appcast.xml` and
  `appcast-homedepot.xml`. Both attach to the same GitHub release.
- A second cask, `skills-manager-home-depot.rb`, is added to the Homebrew
  template directory and the tap.
- Release notes stay one file per version; both apps show the same notes.

## 8. Error handling

- Catalog missing or undecodable: behave as empty, log once. Never crash.
- Network failure while checking items: the row shows the existing network
  sentence and its checkbox is disabled; other rows are unaffected.
- `npx` or `claude` missing: the footer shows the existing `missingTool` copy
  and the Install button is disabled, same as the Install box.
- One item fails to install: its row shows the failure sentence with the log
  available by disclosure; the run continues.

## 9. Testing

Core unit tests:

- Catalog decodes the documented shape; unknown keys are ignored; missing
  optional fields take defaults; invalid JSON yields an empty catalog.
- `RecommendationPlan` orders items by catalog order, skips unchecked and
  installed items, and selects all valid skills of a skills repo.
- The bundled Home Depot catalog file decodes and contains exactly the four
  agreed sources (a fixture test that reads the file from the repo).

App checks (manual, both targets):

- General build: no sheet, no menu item.
- Home Depot build: sheet on first launch; **Not now** suppresses it on the
  next launch; **File → Recommended…** reopens it; installing all four
  produces the expected entries in the library; relaunch shows them as
  already installed.

## 10. Open items

None. Icon branding and a remote catalog are deliberately out of scope and can
be separate specs later.
