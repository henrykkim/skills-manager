# Detail Provenance & Cleanup — Design Spec

**Date:** 2026-09-21
**Status:** Approved in conversation with the owner
**Scope:** Small follow-up to Plan 1. Sidebar structure is unchanged (the owner
will brainstorm sidebar navigation separately).

## 1. Problem

After using the Plan 1 build, the owner found:

- "Updated" timestamps clutter the sidebar rows; they belong in the detail view.
- The toolbar Refresh button is confusing. Reloading already happens
  automatically via FSEvents, so the button implies work the user must do.
- The detail views show provenance as plain text ("GitHub: owner/repo") with no
  way to reach the source. The owner wants to click through to the marketplace,
  repository, or author to learn more, and to see when an item was last updated
  in the detail header.

## 2. Changes

### 2.1 Sidebar rows (`LibraryRows.swift`)

- `SkillRow`: remove the "Updated …" caption line.
- `PluginRow` caption: remove the "updated …" part. Keep provenance, version,
  skill count, command count, and the `StatusDot`.
- Nothing else changes: `DisclosureGroup` chevrons and sticky expansion stay.

### 2.2 Toolbar (`LibraryView.swift`)

- Remove the visible Refresh toolbar item.
- Keep ⌘R as a hidden keyboard shortcut (a `Button` inside `.toolbar` with
  `.hidden()`, or a `.keyboardShortcut` on an invisible view — whichever XcodeGen
  build verifies works) so a manual re-scan remains possible.

### 2.3 Plugin detail (`PluginDetailView.swift`)

Header line: name · `KindBadge("Plugin")` · `StatusDot` · muted
"Updated <abbreviated date>" (omitted when unknown).

Details card rows, in order, each omitted when its value is unknown:

| Row | Value |
|---|---|
| Author | `author.name`; clickable when `author.url` exists |
| Source | link to `homepage`, else `repository`, else the marketplace repo URL |
| Marketplace | marketplace display name, linked to the marketplace repo URL |
| Version | as today |
| Installed | `installedAt` from `installed_plugins.json` |

"Status" moves out of the card (the dot in the header carries it).
"From" (plain provenance text) is replaced by the Source/Marketplace links.

### 2.4 Skill detail (`SkillDetailView.swift`)

Header line gains muted "Updated <date>": for skills with a lock record use
`updatedAt`; otherwise the folder's modification date.

Details card rows:

| Row | Personal / shared skill | Plugin skill |
|---|---|---|
| Location | path + Reveal in Finder (as today) | same |
| Source | link to lock-file `sourceUrl` (shown as `owner/repo`), else plain folder label as today | link to parent plugin's Source, labelled "Plugin <name>" |
| Installed | lock `installedAt` if present | plugin `installedAt` |

"Last modified" leaves the card (it is now in the header).

### 2.5 Link presentation (`DesignSystem.swift`)

One new component, `SourceLink(label:url:)`: accent-colored text, trailing
`arrow.up.right` SF Symbol at caption size, `.link` button style, opens via
`NSWorkspace.shared.open`. Hover shows the full URL in `.help`. Used for every
outbound link so they look identical.

## 3. Data (`SkillsManagerCore`)

All reads are lenient: missing or malformed files yield `nil` fields, never a
`ParseIssue`, because the item itself is still valid.

### 3.1 Plugin manifest fields

Extend `PluginRegistry` to read from `.claude-plugin/plugin.json`:
`author.name`, `author.url`, `homepage`, `repository`. Add to `Plugin`:

```swift
public let authorName: String?
public let authorURL: URL?
public let homepageURL: URL?      // homepage ?? repository
public let marketplaceURL: URL?   // from known_marketplaces.json
public let installedAt: Date?
```

`marketplaceURL` derives from `known_marketplaces.json`:
`source.repo` → `https://github.com/<repo>`; `source.url` → that URL with a
trailing `.git` stripped. Existing `provenance` string stays for the sidebar.

`installedAt` comes from the same `installed_plugins.json` record as
`lastUpdated`.

### 3.2 Skill lock file

New reader `SkillLockReader` for `~/.agents/.skill-lock.json`
(`ClaudePaths` gains `agentsLockFile`). Schema observed on the owner's machine:

```json
{ "version": 1, "skills": { "<folderName>": {
    "source": "owner/repo", "sourceType": "github",
    "sourceUrl": "https://github.com/owner/repo.git",
    "installedAt": "ISO-8601", "updatedAt": "ISO-8601" } } }
```

Keyed by folder name. Applied to `.shared` skills and to `.personal` skills
whose directory resolves (realpath) into `~/.agents/skills`. Add to `Skill`:

```swift
public let sourceURL: URL?        // sourceUrl with trailing .git stripped
public let sourceLabel: String?   // "owner/repo"
public let installedAt: Date?
public let updatedAt: Date?       // lock updatedAt; view falls back to lastModified
```

Inventory wiring: `Inventory.load` reads the lock file once and passes the
lookup to `SkillScanner`.

## 4. Design skills to apply during UI work

The owner asked that design skills be used when reworking UI elements. The
implementation plan must invoke, for the view tasks: `apple-design`,
`make-interfaces-feel-better`, `emil-design-eng`, and `better-ui`. Concrete
expectations: tabular figures for dates and versions, optical alignment of the
dot and badge with the title baseline, comfortable hit area on links, no
layout shift when optional rows are absent.

## 5. Testing

- `PluginRegistryTests`: fixture plugin with full author/homepage/repository;
  fixture without them yields `nil`s; marketplace URL derivation for `repo` and
  `url` (with `.git`) forms.
- `SkillLockReaderTests`: parses the observed schema; missing file → empty
  lookup; malformed JSON → empty lookup; skill lookup by folder name.
- `InventoryTests`: shared skill in fixture home gets `sourceURL`; a personal
  symlink into `~/.agents/skills` gets it too; a plain personal skill does not.
- Owner-verified visual checkpoint: build, open Figma plugin and a shared skill,
  confirm links open the browser, Updated appears in the header, sidebar rows no
  longer show dates, and no Refresh button is visible while ⌘R still reloads.

## 6. Out of scope

Sidebar navigation model (owner brainstorming), visibility map, per-agent
toggles, cloud skills, Updates view, install box (Plans 2–4).
