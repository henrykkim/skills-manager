# Project Scope — Design Spec

**Date:** 2026-09-26
**Status:** Approved in brainstorming; pending owner review of this document
**Roadmap note:** the "project-based view" deferred from the usage-tracking
session (spec `2026-09-25-skill-usage-tracking-design.md`). Builds on the
location tags from project skills discovery and the per-project usage data
from usage tracking. Visual design of the scope bar is decided with the owner
before the UI task runs.

## 1. Problem

Coworkers install skills per project and want to glance at what is available
in the project they are working in. Today the library lists everything, and
"what can I use here?" means reading tags row by row or searching.

## 2. Goals and non-goals

### Goals

1. Let the user pick a project and see only what works there: global skills,
   that project's own skills, plugins enabled there, and their Claude-account
   skills.
2. Reuse what the app already knows. No new discovery; the location tags on
   every row decide membership.
3. Make usage follow the scope, so "Most used" and the row hints mean "in this
   project".
4. Keep the choice visible and reversible: the scope is always shown, and one
   click returns to Everywhere.

### Non-goals

- Guessing the current project from Claude's activity.
- Projects as a second navigation layer in the sidebar.
- Showing out-of-scope rows dimmed. They are hidden, with a count.
- Changing the skill detail page beyond the Usage card's numbers.
- Any new Settings.

## 3. Scope model

A `LibraryScope` is one of:

- `everywhere` (default, current behavior)
- `project(root: URL)` for each project the inventory knows: discovered
  (terminal, desktop Code tab, Cowork) and hand-added folders
- `cowork` (Cowork has its own plugin store)

Membership uses the `LocationTag`s already on each entry:

| Scope | Row is shown when any of its tags is |
|---|---|
| everywhere | anything |
| project(root) | `.global`, `.account`, or `.project(name)` for that root |
| cowork | `.cowork` or `.account` |

Tags are matched by project root, not display name, so two projects with the
same folder name never collide (the tag carries the name; the entry's
locations carry the root, and membership reads the location).

Unconnected shared skills (the `Shared Skills` section, `~/.agents/skills`
not linked into Claude Code) are not usable in any project, so they show only
in `everywhere` and count toward the hidden total otherwise.

Notes folders and Built-in skills: notes are not scoped (they are the user's
own files and show in every scope); built-in Claude-account skills count as
`.account`.

The chosen scope persists in `UserDefaults` by root path. On load, a scope
whose project is no longer in the inventory falls back to `everywhere`.

## 4. Usage follows the scope

When the scope is a project, `UsageStats` is built from only the events whose
`projectRoot` equals that root. For `cowork`, from events with
`source == .cowork`. For `everywhere`, from all events (today's behavior).

Consequences: the sort orders, the row hints, the Usage card's tiles (last
used, count in window, all time, first used) and its rate caption all reflect
the scope. The Usage card's By project list is unchanged; it always shows
every project, since it is the one place to compare.

Turning usage tracking off leaves scoping fully functional; only the
usage-dependent surfaces disappear, as they do today.

## 5. Surfaces

- **Scope bar.** The bar under the search field reads `Showing` followed by a
  popup labelled with the current scope (`Everywhere`, the project's display
  name, or `Cowork`), then the existing `Sorted by` popups. The popup lists
  `Everywhere`, then projects sorted by display name, then `Cowork`; the
  current one is checked. The bar shows even when usage tracking is off (the
  sort popups hide, the scope popup stays).
- **List.** Sections keep their names. Out-of-scope rows are hidden. Rows keep
  their location tags, so a project-only skill remains visibly different from
  a global one. Search filters within the scope. Dividers between used and
  never-used groups follow the scoped stats.
- **Footer note.** In a project or Cowork scope, one line at the end of the
  list: `N items not available in <name>` followed by a `Show Everywhere`
  link that resets the scope. N counts hidden plugins, skills, shared skills
  and built-in skills. When N is 0 the line is omitted.
- **Empty scope.** A project with nothing usable (only possible if global is
  empty too) shows the existing empty state with its Install button.
- **Detail.** Unchanged, except the Usage card's numbers follow the scope
  (§4). The card's caption gains the scope when not Everywhere: `Counts from
  Claude Code and Cowork sessions in <name>`.
- **Remove project.** The existing right-click "Remove X from Skills Manager"
  keeps working; if the removed project was the scope, scope resets to
  `everywhere`.

## 6. Error handling

- A persisted scope path that no longer resolves → `everywhere`, silently.
- A project renamed on disk → its root changes, so the persisted scope no
  longer matches → `everywhere`.
- No events for the scoped project → every row reads `Not used yet` and sorts
  by name within the never-used group, exactly as a fresh install does.

## 7. Testing

Core tests:

- `LibraryScope` membership for each tag/scope pair in the table above,
  including two projects with the same display name and different roots.
- Scoped `UsageStats`: only matching events counted; `cowork` uses source;
  `everywhere` equals unscoped.
- Hidden-count computation across all four row kinds.
- Persistence round trip and fallback to `everywhere` for a missing root.

Owner checkpoints (GUI): scope popup contents and order, list filtering,
footer note and its link, tags still visible, Usage card caption, scope
survives relaunch, removal of the scoped project resets to Everywhere.

## 8. Deferred

- Auto-following Claude's most recent project.
- A scope for "Shared skills folder" (`~/.agents/skills`), since those are
  not Claude Code items until connected.
