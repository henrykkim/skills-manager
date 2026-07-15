# Skills Manager — Design Spec

**Date:** 2026-07-14
**Status:** Approved in brainstorming; pending user review of this document
**Working title:** Skills Manager (used throughout; the final name is the owner's call and doesn't affect this design)

## 1. Problem

AI agents (Claude Code and others) are configured through "skills" — folders of
instruction files scattered across hidden directories, plugins, and per-project
folders. Today there is no way for a non-terminal user to answer basic questions:

- What skills do I actually have installed?
- What do I type to use each one?
- Which of my AI tools can actually see a given skill — and why is it invisible elsewhere?
- What updated, when, and to what version?
- How do I install a skill from a website without copying commands into a terminal?

The owner (a UX designer) hit all five problems personally: skills installed via
terminal that Claude Code could use but that never appeared in any visible list,
opaque auto-updates, and install instructions that assume terminal fluency.

## 2. Goals and non-goals

### Goals (v1)

1. **See & understand** (the #1 job): one clear inventory of every skill and
   plugin on the Mac, with plain-English descriptions, provenance, and status.
2. **Cheat sheet**: for every skill/plugin, the exact invocation to type, its
   arguments, and every command a plugin provides.
3. **Visibility map & per-agent control**: per skill, which agent surfaces can
   see it and whether it is enabled there — with a toggle to enable/disable it
   per agent right from the map. Where it is *not* visible, a one-sentence
   reason and a suggested fix. Easy visibility *and* control.
4. **No-terminal install**: paste a command snippet or a website link; the app
   resolves it, previews it, and installs it.
5. **Update transparency**: installed version, last-update time, auto-update
   status, link to upstream changes. The app never auto-updates anything itself.
6. Light, free, native. A simple utility, not a platform.

### Non-goals (v1)

- Skill authoring or editing (owner will design this later if wanted).
- Multi-device sync.
- Writing/uploading to claude.ai cloud skills (no API exists; hard boundary).
- Automated security scanning (v2 candidate; v1 shows full skill text instead).
- Managing MCP servers, hooks, or subagents.
- Windows/Linux (SwiftUI implies macOS-only).

## 3. Users

Primary: the owner — designer, Mac user, Claude Code user, limited terminal
comfort. Secondary (later): similar non-terminal users. All copy in the app is
written for someone who has never opened `~/.claude` in a terminal.

## 4. Research summary (July 2026)

- Skills follow an **open standard** (agentskills.io): a skill is a directory
  with `SKILL.md` (YAML frontmatter: `name`, `description`, plus optional and
  vendor-specific fields). ~40 products adopted it.
- **Shared location**: `~/.agents/skills/` is read natively by Codex, Cursor,
  Gemini CLI, GitHub Copilot, and VS Code. Claude Code reads only
  `~/.claude/skills/` (and project `.claude/skills/`) but **follows symlinks**.
- **Claude Code plugins** have a fully scriptable CLI (`claude plugin list
  --json`, `install`, `enable`, `disable`, `update`, `marketplace …`) designed
  for automation.
- **claude.ai/Desktop cloud skills** are a separate system: ZIP upload via web
  UI only, no API. The desktop app syncs them down to a local cache that can be
  read but must never be written.
- **Competitive landscape**: several skills-manager GUIs exist (skills-manager
  ~3k stars, chops, SkillDeck, and others), plus Anthropic's own growing GUI
  surface. None explain visibility, none are designed for non-terminal users.
  As a personal tool this app doesn't compete on features; its differentiator
  is clarity.
- Full research reports with URLs: see §12.

## 5. Product design

A single-window macOS app with three core surfaces.

### 5.1 Library

The inventory. One searchable, filterable list of every skill and plugin found
on the machine, aggregated from all sources in §6.2. Each row shows:

- Name (human form) and one-line description
- Kind: personal skill · plugin (with N skills inside) · project skill ·
  cloud skill (read-only) · other-agent skill
- Source/provenance (e.g., "Anthropic official marketplace", "GitHub: owner/repo")
- Per-agent status chips: one chip per detected agent showing enabled /
  disabled / not connected at a glance (the Library answers "which skills are
  on for which agent" without opening anything)
- Enabled/disabled toggle (per-agent toggles live in the visibility map)
- Last updated

Grouping/filtering by kind, source, and agent. Plugins expand to show their
bundled skills. Search matches names, descriptions, and command names.

### 5.2 Skill Detail

Selecting any item opens its detail view with two key blocks:

**Cheat sheet.** Extracted from the skill's own files:

- The exact invocation string (e.g. `/superpowers:brainstorming`) with a copy
  button. Naming rules: personal skills → `/<name>`; plugin skills →
  `/<plugin-name>:<skill-name>`.
- Argument hints where declared (`argument-hint` frontmatter).
- What it does (description + "when to use" where present).
- For plugins: the complete list of commands/skills the plugin provides.
- Invocability flags translated to plain English: model-invoked only ("Claude
  uses this automatically; you won't see it in the / menu"), user-invoked, etc.

**Visibility map.** One row per *relevant* surface, auto-detected (§6.3):

- **Claude Code** — one row (terminal and desktop app see identical skills; do
  not split them).
- **Claude web/desktop apps (cloud)** — one row, read-only.
- One row per detected other agent (Codex, Cursor, Gemini CLI, Copilot, …).
  Agents not installed on this Mac never appear.

Each row is a control, not just an indicator: a toggle showing whether the
skill is enabled for that agent, plus the name it appears under there.
Toggling off disables the skill for that agent only; toggling on enables or
connects it (mechanics in §6.4). Rows that cannot be toggled (the read-only
claude.ai row) say why. Every off/not-visible state carries a reason and
remediation from the catalog in §6.5, e.g.:

> ✗ Cursor — Cursor doesn't read this folder. **[Connect]** to make it
> available there.
> ✗ Claude web — Skills on your Mac aren't visible to claude.ai. **[Package
> for upload…]** prepares a ZIP and opens the right settings page; the final
> drag-and-drop is yours (Anthropic provides no automated path).

**Connect** creates a symlink from the target agent's skills directory to the
skill's canonical folder (copy as fallback if a target doesn't resolve
symlinks). Also available: enable/disable toggle, Reveal in Finder, Uninstall
(moves to Trash).

### 5.3 Install box

A single paste target (also accepts drag-and-drop of text/URLs) that resolves
any of:

- `claude plugin install <plugin>@<marketplace>` snippets
- `npx skills add <ref>` snippets (skills.sh)
- GitHub repository / subfolder URLs containing `SKILL.md` or a plugin manifest
- skills.sh and marketplace page URLs

Flow: paste → the app identifies what it is → **preview card** (name,
description, publisher/provenance, list of files and commands it will add, and
the full `SKILL.md` text one click away) → Install → success state shows where
it landed and what to type to use it.

Install destinations:

- Claude Code plugins → via `claude plugin install` (official CLI).
- Standalone skills → written to `~/.agents/skills/<name>/` (the shared
  standard location, so any other detected agents get it for free) **plus** a
  symlink into `~/.claude/skills/<name>` so Claude Code sees it. This is the
  app's canonical layout for skills it installs; skills installed by other
  means are never moved.

Unresolvable input produces a friendly diagnosis ("This looks like a Homebrew
command, which isn't a skill"), never a raw error.

### 5.4 Updates view

A list of everything versioned, showing: current version, last-updated
timestamp, auto-update on/off (per marketplace, as configured in Claude Code),
and a link to the upstream repo/changelog. Personal skills (unversioned) show
file-modification dates. The app displays what Claude Code's auto-updater did;
it does not perform updates itself in v1 beyond a per-item "Update now" that
shells to `claude plugin update`.

## 6. Technical architecture

### 6.1 Platform

- Swift + SwiftUI, macOS 14 (Sonoma) minimum.
- No database. The filesystem is the single source of truth; the app builds an
  in-memory model on launch and keeps it fresh via FSEvents. App preferences
  only in `UserDefaults`.
- Distribution: direct download, Developer ID-signed and notarized. **Not**
  Mac App Store (sandboxing blocks both dotfile access and spawning CLIs).
  For personal use during development, an unsigned local build suffices.

### 6.2 Data sources (readers)

| Source | Path | Access |
|---|---|---|
| Personal skills | `~/.claude/skills/*/SKILL.md` | read/write |
| Shared-standard skills | `~/.agents/skills/` | read/write (app's canonical install target) |
| Plugin registry | `~/.claude/plugins/installed_plugins.json` (v2 schema) | read |
| Plugin contents | `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | read |
| Marketplaces | `~/.claude/plugins/known_marketplaces.json`, `marketplaces/` | read |
| Enable/disable | `enabledPlugins` in `~/.claude/settings.json` | read; write via CLI |
| Project skills | `.claude/skills/` inside projects known to Claude Code (project list derived from `~/.claude.json` / `~/.claude/projects/`) | read |
| Other agents | `~/.cursor/skills/`, `~/.codex/skills/`, `~/.gemini/skills/`, `~/.copilot/skills/` | read; write only via Connect |
| Cloud skills cache | `~/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin/…/skills/` + `manifest.json` | **strictly read-only** (undocumented format) |

Parsing: YAML frontmatter parsed leniently; unknown fields preserved and
ignored, malformed files surfaced as "needs attention" items (§8).

### 6.3 Agent detection

An agent surface appears in the app only if detected: config directory exists
(`~/.cursor`, `~/.codex`, `~/.gemini`, `~/.copilot`) or its CLI resolves on the
user's login-shell `PATH`. Claude Code detected via `~/.claude` + the `claude`
binary. The claude.ai row appears only if the cloud cache exists.

### 6.4 Actions (writers)

- **Plugin operations** (install/uninstall/enable/disable/update/marketplace):
  shell out to `claude plugin … --json`, resolving the binary through a login
  shell. Never hand-edit plugin JSON while the CLI can do it.
- **Skill file operations**: atomic (write-temp-then-rename); deletions move
  to Trash via `NSWorkspace`; never write while holding locks Claude Code uses
  (`.claude.json.lock`).
- **Connect**: symlink into target agent's skills dir; fallback copy with a
  "copies don't auto-update together" note.
- **Per-agent toggle**: uses each agent's native mechanism where one exists —
  Claude Code plugins via `claude plugin enable/disable`, Claude Code skill
  visibility via `skillOverrides` in `settings.json`, Codex via
  `[[skills.config]]` entries in `~/.codex/config.toml`, Gemini CLI via
  `gemini skills enable/disable`. For agents with no native disable switch
  (Cursor, Copilot), off = remove the symlink, on = restore it — same end
  result, and the UI says so plainly.
- Every writer shows a preview of the exact change before executing (§8).

### 6.5 Visibility-reason catalog

The visibility map's explanations come from a fixed, testable rule set:

| Condition | Explanation shown | Remedy offered |
|---|---|---|
| Skill lives in a project folder | "Only available inside <project>" | Connect (symlinks it into the personal skills folder, same mechanics as §5.2) |
| Plugin disabled | "Its plugin <name> is turned off" | Enable toggle |
| Disabled for this agent | "Turned off for <agent>" | Toggle on |
| `disable-model-invocation: true` | "Only runs when you type its command" | none (informational) |
| Not user-invocable | "Claude uses it automatically; it won't appear in the / menu" | none (informational) |
| Agent doesn't read the skill's folder | "<Agent> doesn't look in this location" | Connect |
| Local skill vs claude.ai web | "claude.ai can't see skills on your Mac" | Package for upload |
| Cloud skill vs local agents | "This lives in your claude.ai account, not on this Mac" | none (read-only) |
| Malformed `SKILL.md` | "Has a formatting problem: <detail>" | Reveal in Finder |
| Duplicate names across sources | "Also installed at <other location>; Claude Code uses <which>" | Reveal both |

### 6.6 Live updates

FSEvents watchers on all §6.2 directories, debounced (~1 s), triggering
incremental re-scan of the changed source. A change made in the terminal or by
Claude Code's auto-updater appears in the app within seconds. Watcher failure
degrades to a visible manual Refresh button.

## 7. Error handling

- `claude` CLI absent/old → plugin actions disabled with explanation and a
  pointer to install docs; all read-only features still work.
- Malformed skill/plugin files → "needs attention" list with the specific
  parse problem; never crash, never silently hide.
- Undocumented formats (cloud cache) changed by Anthropic → that surface hides
  itself; a subtle notice explains reduced visibility. Wrong info is worse
  than missing info.
- Install failures → show the underlying tool's message translated to plain
  English, with the raw output expandable.
- All shelled commands run with timeouts; hung tools surface as retryable
  failures.

## 8. Safety and trust rules

1. Preview before every change: exact files/commands shown before execution.
2. No silent writes, ever. No background mutation of user config.
3. Deletes are Trash moves, recoverable in Finder.
4. Undocumented locations are read-only (enforced in the data layer, not by
   convention: the cloud-cache reader has no write path).
5. Install preview always offers the full skill text; copy explains that a
   skill is instructions the agent will follow, and to install only from
   trusted sources. (Ecosystem audits found ~36% of unvetted public skills
   contain prompt-injection content — v1's mitigation is transparency;
   automated scanning is v2.)
6. The app never uploads, phones home, or collects analytics. Fully local.

## 9. Testing

- **Unit**: frontmatter parser, `installed_plugins.json` (v2) parser,
  snippet/URL resolver (every input class in §5.3, plus garbage), visibility
  rule set (§6.5) as a pure-function truth table.
- **Fixtures**: replica directory trees of real-world layouts (including a
  sanitized copy of the owner's actual `~/.claude`) exercised end-to-end.
- **Sandbox mode**: a launch flag redirects all root paths (`~/.claude`,
  `~/.agents`, etc.) to a fixture folder so development and demos never touch
  the real setup; install flows are tested there first.
- **Manual smoke checklist** per release: paste-install each input type,
  toggle, connect, uninstall→Trash, terminal-side change appears live.

## 10. Build phases (sizing, not a plan)

1. Read-only Library + Skill Detail cheat sheet (immediately useful).
2. Visibility map + agent detection + Connect.
3. Enable/disable + Updates view.
4. Install box.
Detailed task breakdown belongs to the implementation plan, not this spec.

## 11. Future ideas (explicitly deferred)

Skill authoring/editing UI · automated security scanning · multi-device sync ·
MCP/hooks/subagents coverage · menubar quick-switcher · team sharing.

## 12. References

- Agent Skills standard: https://agentskills.io / https://agentskills.io/specification
- Claude Code skills: https://code.claude.com/docs/en/skills
- Claude Code plugins reference & CLI: https://code.claude.com/docs/en/plugins-reference
- Plugin discovery/auto-update: https://code.claude.com/docs/en/discover-plugins
- Skills in claude.ai (upload, no API): https://support.claude.com/en/articles/12512180-use-skills-in-claude
- Cross-surface non-sync statement: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview
- Other agents' skills docs: https://developers.openai.com/codex/skills · https://cursor.com/docs/context/skills · https://geminicli.com/docs/cli/skills/ · https://docs.github.com/en/copilot/concepts/agents/about-agent-skills
- Registry/directory: https://www.skills.sh
- Comparable apps: https://github.com/xingkongliang/skills-manager · https://github.com/Shpigford/chops · https://github.com/crossoverJie/SkillDeck
