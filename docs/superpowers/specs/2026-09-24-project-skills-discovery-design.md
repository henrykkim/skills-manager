# Project Skills Discovery — Design Spec

**Date:** 2026-09-24
**Status:** Approved in brainstorming; pending owner review of this document
**Roadmap note:** this is the "project skills" slice of Plan 3 (visibility
map). It also pulls in Claude-account skills (the read-only cloud cache) and a
first version of user-added markdown folders. Agent detection, Connect, and
per-agent toggles stay in later plans.

## 1. Problem

The app only shows skills and plugins installed globally (`~/.claude/skills`,
`~/.agents/skills`, user-scope plugins). The owner's coworkers mostly work in
the Claude desktop app and install skills per project, so the app shows them
little or nothing of what they actually use. Two more gaps came up:

- Custom skills people create in their Claude account (Settings → Skills) are
  invisible to the app.
- Some people keep their own prompt library as loose markdown files (a
  coworker's `brain/skills/*.md`). Claude doesn't treat these as skills, but
  users want to see them next to their skills.

The hard part is less finding these items than making clear **where each one
works**.

## 2. Goals and non-goals

### Goals

1. Find every skill and plugin Claude can use on this Mac, whatever the scope:
   global, any project Claude has been given access to (terminal, desktop Code
   tab, Cowork), and the user's Claude account.
2. Tag every library row with where it works, so "where can I use this?" is
   answered without opening anything.
3. Explain precedence honestly: when a project copy is ignored because a Global
   copy wins, say so.
4. Let users add a folder by hand, either a project Claude has never opened or
   a folder of markdown notes.
5. Never break the whole library because one of Claude's internal files changed
   format.

### Non-goals (this plan)

- Scanning the whole disk. The app only looks where Claude has been given
  access, plus folders the user adds.
- A "Working in <project>" picker (option C in brainstorming). Search on
  project names covers the main need. The picker can be layered on later
  without rework.
- Editing, enabling, disabling, or deleting anything, including Claude-account
  skills. Everything here is read-only.
- Auto-detecting markdown prompt libraries. Users add those folders by hand.
- Legacy `.claude/commands/*.md` files (their loading behavior isn't
  documented; revisit separately).

## 3. Background facts this design relies on

Sourced from the Claude Code docs (skills, plugins-reference) and from
inspecting the owner's Mac on 2026-09-24.

- **Skill locations:** personal `~/.claude/skills/<name>/SKILL.md`; project
  `<project>/.claude/skills/<name>/SKILL.md`; nested
  `<project>/<subdir>/.claude/skills/<name>/SKILL.md` (loads for sessions in
  that subdirectory and below); plugin `<plugin>/skills/<name>/SKILL.md`.
- **Precedence on name conflicts:** enterprise > personal > project. A project
  copy of a skill that also exists globally is ignored.
- **Plugin scopes:** user (`~/.claude/settings.json` `enabledPlugins`), project
  (`<project>/.claude/settings.json`), local
  (`<project>/.claude/settings.local.json`, not committed).
- **Invocation name** comes from the skill's folder name (already relied on by
  the app).
- **Where Claude records folder access:**
  - Terminal Claude Code: keys of `projects` in `~/.claude.json`.
  - Desktop Code tab: `~/Library/Application Support/Claude/claude-code-sessions/<a>/<b>/local_*.json`,
    fields `cwd` and `originCwd`.
  - Cowork: `~/Library/Application Support/Claude/local-agent-mode-sessions/<a>/<b>/local_*.json`,
    field `userSelectedFolders` (array of paths).
  - Cowork keeps its own plugin set in the same `<a>/<b>/` folder:
    `cowork_plugins/installed_plugins.json` plus `cowork_settings.json`
    (`enabledPlugins`).
- **Claude-account skills:**
  `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/<a>/<b>/`
  holds `skills/<name>/SKILL.md` and `manifest.json` with `lastUpdated` (epoch
  ms) and `skills[]` entries `{skillId, name, creatorType: "user"|"anthropic",
  enabled, updatedAt}`. These also load in desktop Code sessions as
  `anthropic-skills:<name>`.
- On the owner's Mac: 22 terminal projects, 11 of them deleted; 23 Code-tab
  folders, mostly worktrees; 15 Claude-account skills, 2 user-made.

All of the desktop app's files are internal formats, not a public API.

## 4. Discovery

### 4.1 Sources

Each source is its own reader with one job, and each can fail on its own
(§6.2).

| Source | Reads | Produces |
|---|---|---|
| Global (existing) | `~/.claude/skills`, `~/.agents/skills`, user plugins | Global items |
| Terminal projects | `~/.claude.json` → `projects` keys | Project folders |
| Code-tab sessions | `claude-code-sessions/**/local_*.json` → `cwd`, `originCwd` | Project folders |
| Cowork sessions | `local-agent-mode-sessions/<a>/<b>/local_*.json` → `userSelectedFolders` | Project folders |
| Cowork plugins | `cowork_plugins/installed_plugins.json` + `cowork_settings.json` | Cowork plugins |
| Claude account | `skills-plugin/<a>/<b>/manifest.json` + `skills/` | Claude-account skills |
| Added folders | App preferences | Project folders or note folders |

From session files the app decodes **only** the path fields named above.
Emails, prompts, and conversation content are never decoded, stored, or
logged.

### 4.2 Project list

1. Union the folders from all project sources and added folders.
2. Drop folders that don't exist, silently.
3. Fold worktrees into their parent: a path containing
   `/.claude/worktrees/<name>` maps to the folder before `/.claude/worktrees`.
4. Drop the home folder itself as a project (its `.claude/skills` *is* the
   personal skills folder).
5. De-duplicate by canonical path (realpath).
6. Project display name = the folder's last path component. If two projects
   share a name, append the parent folder ("Portfolio (Work)").

### 4.3 What's scanned in each project

- `<project>/.claude/skills/` using the existing `SkillScanner`.
- Nested `.claude/skills/` folders: a bounded walk, at most 4 levels deep,
  skipping `node_modules`, `.git`, `.build`, `DerivedData`, `Pods`, `vendor`,
  and any hidden folder other than `.claude`. The walk only checks folder names
  and never reads file contents. The subfolder path is kept for the detail
  page.
- Project plugins: `enabledPlugins` in `<project>/.claude/settings.json` and
  `<project>/.claude/settings.local.json`, resolved against the plugin cache the
  same way user plugins are.
- **Online-only files:** in cloud-synced folders (`~/Library/CloudStorage/…`,
  iCloud Drive), the app skips any file that isn't downloaded locally
  (`URLResourceKey.ubiquitousItemDownloadingStatus` / file-provider placeholder
  check), so a scan never triggers a download.

### 4.4 Claude-account skills

- Read every `skills-plugin/<a>/<b>/manifest.json` (one per account and
  organization).
- `creatorType == "user"` → a regular library row tagged **Claude account**.
- `creatorType == "anthropic"` → the collapsed **Built into Claude** group.
- `enabled == false` → keep the row with an **Off** label and the hint "Turn it
  back on in Claude → Settings → Skills."
- Content comes from the matching `skills/<name>/SKILL.md`. "Last synced" comes
  from `lastUpdated`.

### 4.5 Merging and tags

A library row is one **skill identity**. For skills that's the folder name (the
invocation name). For plugins it's the `name@marketplace` ID. Every place the
item was found becomes a **location** on that row.

| Location kind | Tag |
|---|---|
| Personal skill folder, user-scope plugin | **Global** |
| Project (skill folder, nested folder, or project plugin) | project display name |
| Cowork plugin | **Cowork** |
| Claude-account skill | **Claude account** |

Rules:

- Tag order: Global, Claude account, Cowork, then projects alphabetically.
- Show at most 2 project tags, then **+N**. Hovering over or clicking +N shows
  the full list (a popover that's reachable by keyboard and has a VoiceOver
  label listing every project).
- **Copies differ:** if the skill locations' `SKILL.md` contents aren't
  byte-identical, the row shows a small "Copies differ" note.
- **Ignored copies:** when a Global copy exists, the project copies of the same
  skill are marked as ignored (§3 precedence). Their tags still show so the user
  can find them.
- Plugin skills stay namespaced (`plugin:skill`) and never merge with standalone
  skills.
- Shared `~/.agents/skills` items that aren't connected to Claude Code keep
  their current group and behavior.

## 5. User experience

### 5.1 Library

- Rows as today, with tags right-aligned. Everything is on one list, with no
  filter mode.
- Sidebar groups: **Plugins**, **Skills** (personal, project, and
  Claude-account together), **Your notes** (one entry per added folder),
  **Built into Claude** (collapsed by default), **Needs attention**. Shared
  skills that aren't connected keep their existing group.
- Search matches project names as well as skill names and descriptions.
- A Mac with only global items looks the same as today, plus **Global** tags.
  No empty project UI appears.

### 5.2 Detail page: "Where it works"

A new section on skill and plugin detail pages, with one line per location:

> **Where it works**
> Global · ~/.claude/skills/code-review-checklist — Show in Finder
> Portfolio · ignored, Claude uses the Global copy — Show in Finder
> Ring, Skills Manager · copies differ from Global — Show in Finder
> Portfolio › website · only in this subfolder — Show in Finder
> Claude account · last synced 2 hours ago

### 5.3 Add folder…

- In the File menu and at the bottom of the sidebar. It opens a folder picker.
- A folder that has `.claude/skills`, or that is a skills folder itself (child
  folders contain `SKILL.md`), is added as a **project**.
- Otherwise, a folder with `.md` files is added as a **note folder** under
  **Your notes**.
- Neither → the plain sentence "This folder doesn't have Claude skills or
  markdown files."
- Added folders persist in app preferences as paths (the app is not
  sandboxed). Right-click → **Remove from Skills Manager** forgets the folder
  and never touches the disk.

### 5.4 Notes

- A note folder lists its `.md` files (top level only for v1).
- The detail page renders the markdown read-only, with **Open in editor** and
  the line: "This is a markdown file, not a Claude skill. Claude won't run it
  automatically."
- Rows carry a dashed **Not a skill** tag.

### 5.5 First run and permissions

Projects in Documents, Desktop, Downloads, or iCloud Drive trigger macOS's
one-time folder-access prompt. Before the first scan that would trigger one, a
short note explains: "Skills Manager looks for skills inside folders you use
with Claude. macOS will ask for access." If access is denied, those projects
appear in Needs attention with how to grant it in System Settings.

## 6. Behavior

### 6.1 Live updates

The existing home-rooted FSEvents watcher gains these targets:

- `~/.claude.json`
- the two desktop-app session folders
- the Claude-account `skills-plugin` folder
- each project's `.claude` folder

A newly opened project appears on its own. Projects outside the home folder
refresh on ⌘R.

### 6.2 Failure isolation

Each reader in §4.1 returns its results plus issues, never throws past its
boundary. If a source can't be read or decoded, only that source's items are
missing and Needs attention shows one plain sentence, for example: "Couldn't
read Cowork's folder list. Cowork items may be missing." Decoders accept
unknown fields and treat missing optional fields as absent.

### 6.3 Performance

Discovery runs off the main thread, like `Inventory.load` today. The nested
walk is bounded (§4.3). The target is a full load under 1 second for about 30
projects on the owner's Mac.

## 7. Architecture

- `ClaudePaths` gains the new locations: `claudeJSON`, `desktopSupportDir`,
  `codeSessionsDir`, `coworkSessionsDir`, `accountSkillsDir`.
- New readers in `SkillsManagerCore`, one file each: `ProjectSources`
  (terminal, Code tab, Cowork → folder list), `ProjectScanner` (one project →
  skills and plugins, including the nested walk), `CoworkPlugins`,
  `AccountSkills`, `NoteFolders`.
- `SkillSource` gains `.project(root: URL, subpath: String?)` and `.account`.
  Plugins gain a scope (`user`, `project(root:)`, `cowork`).
- A new `LibraryItem` merge step turns raw skills and plugins into rows with
  `locations`, `copiesDiffer`, and `ignoredLocations` (§4.5). Views read rows,
  never raw sources.
- `Inventory.load` composes the readers. Added-folder paths are passed in, so
  Core stays free of UserDefaults.

## 8. Testing

- Extend the fixture home with:
  - `~/.claude.json` projects, including deleted folders and worktrees
  - Code-tab and Cowork session files, with decoy private fields that must be
    ignored
  - a Cowork plugin set
  - a Claude-account manifest mixing `user` and `anthropic` skills, one of
    them disabled
  - projects with nested skills, a `node_modules` decoy, project and local
    plugins, a skill that's both Global and in a project, and differing copies
  - a note folder
- Unit tests per reader, for the project-list rules (§4.2), the merge and tag
  rules (§4.5), failure isolation (a corrupt file in each source), and the
  private-field test.
- Owner checkpoints (GUI, can't be automated here):
  - tags and +N on hover and click
  - the "Where it works" section
  - Add folder… with a project and with a note folder
  - the macOS permission prompt and the note before it
  - Claude-account skills and the Built into Claude group
  - a coworker-style setup (desktop-only, OneDrive folder)

## 9. Open risks

- Desktop-app file formats can change in any update. This is mitigated by
  failure isolation and tolerant decoders, and fixtures should be refreshed
  when Claude updates.
- Cowork's skill visibility isn't documented. The app shows only what Cowork
  records itself and never claims Global skills work in Cowork.
- Claude-account skills require the desktop app to be installed and signed
  in. Web-only users won't see them.
