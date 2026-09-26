# Skill Usage Tracking — Design Spec

**Date:** 2026-09-25
**Status:** Approved in brainstorming; pending owner review of this document
**Roadmap note:** first feature after the 0.2.x launch, driven by coworker
feedback ("knowing when a skill was last used and how often it gets used").
A project-filtered library view (cluster and filter skills by the project you
are working in) was discussed in the same session and deliberately deferred to
its own spec; the per-project data this spec collects is meant to feed it.
Visual design of every surface named here is decided in a separate design
review session with the owner; this spec fixes behavior and data only.

## 1. Problem

The library shows what is installed but nothing about whether it is ever used.
Users who collect skills cannot tell a skill they lean on daily from one they
tried once, so pruning and prioritizing is guesswork. Nothing surfaces "last
used" or "how often", and no other tool on the Mac does either.

## 2. Goals and non-goals

### Goals

1. For every skill, answer: when was it last used, how often in the last 30
   days, how often ever, and in which projects.
2. Need nothing installed and nothing changed in the user's Claude setup.
   History from before the app was installed counts.
3. Be honest about coverage: say plainly where usage cannot be known.
4. Let users see and stop what the app reads, from Settings.
5. Never break the library because a session log is malformed or a log
   format changes.

### Non-goals

- Counting skills Claude loaded by reading `SKILL.md` after a description
  match. Only explicit invocations count ("used" means invoked).
- Live, per-keystroke updates while a session runs.
- Usage from claude.ai in the browser, which leaves nothing on disk.
- Any cloud sync, sharing, or telemetry. All data stays in the app's own
  Application Support folder.
- Deciding how the numbers look. That is the follow-up design session.

## 3. What is on disk (verified 2026-09-25)

Claude Code writes each session as JSONL under
`~/.claude/projects/<escaped-cwd>/<session-id>.jsonl`. Every explicit skill
invocation is an `assistant` line whose `message.content` contains a
`tool_use` block with `name == "Skill"` and `input.skill` set to the invoked
name, either plugin-qualified (`superpowers:brainstorming`) or bare
(`make-interfaces-feel-better`). Each such line also carries `timestamp`
(ISO 8601), `cwd`, `sessionId`, and the Claude Code `version`.

Cowork sessions keep the same format inside their own session folders:
`~/Library/Application Support/Claude/local-agent-mode-sessions/<a>/<b>/<local_id>/.claude/projects/<escaped>/<session>.jsonl`.
Their `cwd` is a synthetic sandbox path, not a user project folder. On the
owner's Mac these files exist but hold no skill invocations yet, so Cowork
coverage is designed for but unverified.

The desktop app's Code tab uses the Claude Code log location, so it is
covered by the first root.

Scale on the owner's Mac: 154 Claude Code session files, 194 MB total. A
full first scan is well under a second; later scans touch only files that
grew.

## 4. Approach

Scan on demand, cache the events (the approach chosen over live FSEvents
tailing and over a Claude Code hook). The app scans on launch and on the
existing refresh path (⌘R and window activation). Each scan walks the log
roots, skips files whose size is unchanged since the last cursor, reads new
bytes from the recorded offset, extracts `Skill` tool-use lines, and appends
events to a local store. Every surface is a query over that store.

## 5. Data model (Core)

```swift
public struct SkillUsageEvent: Codable, Hashable {
    public let skillName: String        // exactly as logged, e.g. "superpowers:brainstorming"
    public let timestamp: Date          // from the log line, never from file dates
    public let projectRoot: URL?        // `cwd`, nil for Cowork sandbox paths
    public let sessionID: String
    public let source: UsageSource      // .claudeCode or .cowork
}

public enum UsageSource: String, Codable { case claudeCode, cowork }

public struct UsageFileCursor: Codable {
    public let path: String
    public let byteOffset: Int
    public let fileSize: Int
}
```

The store is one JSON file per install under the app's Application Support
folder: `usage-events.json` holding the events plus the cursors. No message
text, arguments, or any other transcript content is ever stored. (The
`Skill` tool's `args` field is discarded.)

Aggregations are computed on read, not stored:

- `lastUsed(skill)`: max timestamp.
- `count(skill, window)`: events within the window; windows are "last 30
  days" and "all time".
- `byProject(skill)`: events grouped by `projectRoot`, each with count and
  last used; Cowork events group under a "Cowork" bucket.

## 6. Attribution (log name → library row)

Only skill rows receive usage. Plugins and note rows never do.

1. **Plugin-qualified** (`plugin:skill`): matches the skill inside the
   plugin whose invocation prefix the app already computes. Marketplace
   suffixes are not part of the logged name, so match on plugin name.
2. **Bare name**: the app resolves in the same order Claude Code does for
   that event's `projectRoot`: personal (`~/.claude/skills`), then shared
   (`~/.agents/skills`), then the project skill under that root. A bare name
   with no match in any scope stays unattributed.
3. Events are stored by logged name, never by row identity. A skill removed
   and reinstalled under the same directory name recovers its history; a
   renamed directory starts fresh. Unmatched events are kept so a skill
   installed later inherits its earlier history.

Matching uses the invocation name derived from the directory name, which is
how Claude Code addresses skills (frontmatter `name` is display-only).

## 7. Surfaces (behavior; visuals decided later)

- **Library row.** Skill rows may show a compact hint (last used, relative).
  Plugin and note rows show nothing.
- **Sorting.** Library sort gains "Last used" and "Most used" alongside the
  current order. A window control switches "Most used" between last 30 days
  and all time. Skills with no events always sort after every used skill,
  never as a zero among them.
- **Skill detail.** A Usage section shows last used, count in the selected
  window, all-time count, and a per-project breakdown: each project folder
  with count and last used, using the project names the location tags
  already use; a "Cowork" row when Cowork events exist.
- **Never used.** Reads "Not used yet", not a zero. Account skills add
  "Usage in claude.ai isn't tracked."
- **Tracking off.** Every surface above disappears; sort options revert to
  the default order.

## 8. Settings

A Usage entry in Settings, on by default:

> Skills Manager reads skill invocation records from Claude Code and Cowork
> session logs to show when and how often each skill is used. Message text
> is never stored.

A switch turns tracking off. Turning it off deletes `usage-events.json` and
hides all usage surfaces. Turning it on again rescans from scratch.

## 9. Error handling

- A line that is not valid JSON, or whose `tool_use` shape is unrecognized,
  is skipped. The file's cursor still advances so the line is never retried.
- A file that cannot be opened is skipped for this scan and retried next
  scan from its last good cursor.
- A missing root (no Cowork install, no `~/.claude/projects`) is silently
  absent.
- A file that shrank (rotated or rewritten) is rescanned from byte 0.
- A store file that fails to decode is discarded and rebuilt by a full scan.
- A future Claude Code format change degrades to "no new events", never to a
  crash or an empty library.

## 10. Testing

Core tests with fixture logs in the temp-tree style already used:

- Plugin-qualified invocation attributed to the plugin skill.
- Bare invocation resolved to a project skill for the event's `cwd`, and
  personal/shared precedence over a project copy.
- Cowork session file counted with `source == .cowork` and nil project.
- Malformed line skipped, cursor advanced, later valid line still counted.
- A file that grows between two scans yields only the new events (cursor).
- A file that shrinks is rescanned from the start without duplicates.
- 30-day window boundary: an event 29 days old counts, 31 days old does not.
- Sorting: last used, most used, never-used last.
- Settings off clears the store; on triggers a full rescan.

Owner checkpoints (GUI, not automatable here): usage hint on rows, Usage
section in detail, sort menu, Settings copy and switch behavior, "Not used
yet" and account-skill wording.

## 11. Deferred and open

- Project-filtered library view (own spec). This spec's `byProject` data is
  its input.
- Counting description-matched skill loads (reads of `SKILL.md`).
- Verifying Cowork logs actually record `Skill` tool-use once a heavy Cowork
  user runs the build.
- Deferred install-box owner checkpoints from 2026-09-22 remain outstanding
  and should be run before the next install-box change.
