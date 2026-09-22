# Install Box — Design Spec (Plan 2)

**Date:** 2026-09-22
**Status:** Approved in brainstorming; pending owner review of this document
**Roadmap note:** the owner moved the install box ahead of the visibility map
(now Plan 3); per-agent toggles and the Updates view are Plan 4.

## 1. Problem

Installing a skill today means copying a command from a website into a
terminal. The owner wants to paste the thing they are holding — a GitHub link,
a skills.sh link, or the install command a README shows — into the app, see
what it is, and install it with one click. Everything else in the app stays
read-only.

## 2. Goals and non-goals

### Goals

1. Paste any accepted input (§4) and have the app identify it within about a
   second.
2. Show a preview — what it is, who made it, what it will add, the skill text —
   before anything runs.
3. Install with one click into Claude Code only, by driving the same tools a
   terminal user would (§6), so nothing the app does is hidden or undoable.
4. On success, show the cheat sheet (where it landed, what to type). The
   library updates itself.
5. On any failure or unrecognized input, a plain-English sentence, never a raw
   error; the raw tool output is available behind a disclosure.

### Non-goals (this plan)

- Uninstall, update, or per-agent targets (Cursor, Codex, …). Skills still land
  in the shared `~/.agents/skills` folder so later plans can connect them.
- ZIP files, Notion pages, arbitrary web pages.
- Project-scoped installs. Everything is user scope.
- Any write the app performs itself into skill or plugin folders.

## 3. User experience

### 3.1 Entry points

- Toolbar button **Install** (`plus` symbol), keyboard shortcut ⌘N, and a
  matching item in the File menu.
- Dropping text or a URL anywhere on the window opens the sheet with that
  content already in the field.

### 3.2 The sheet — three states

**Paste.** A single multi-line text field, placeholder: *Paste a GitHub link,
a skills.sh link, or an install command.* The field is focused on open. No
other controls except Cancel. Recognition starts automatically when the text
changes, debounced ~400 ms; a subtle "Looking…" caption appears while it runs.

**Preview.** Appears below the field (the pasted text stays visible and
editable above). Contents:

- Kind badge: **Skill repository** or **Claude Code plugin**.
- Name (repo `owner/name` or plugin name), author with `SourceLink` when known,
  one-line description (repo description from GitHub, or plugin manifest
  description).
- **Skills it will add**: one row per discovered skill with a checkbox, the
  skill's frontmatter name and description, and the future invocation
  (`/<folder>` for skills, `/<plugin>:<skill>` for plugin skills). All checked
  by default; if the input named one skill (skills.sh link path, GitHub folder
  link, or `--skill` flag), only that one is checked. Plugins have no
  checkboxes — a plugin is all-or-nothing.
- **View skill text** disclosure per row: the full `SKILL.md` body, monospaced,
  read-only, selectable.
- **Command** disclosure: the exact command line(s) the app will run.
- Primary button **Install** (disabled until ≥1 skill checked), secondary
  **Cancel**.

**Result.** Success: checkmark, "Installed", then the same cheat-sheet layout
as the detail views: invocation chips (copyable) and Location with Reveal in
Finder. Button **Done**. Failure: one sentence from the catalog in §7, a
**Show details** disclosure with the raw stdout/stderr, and buttons **Try
again** and **Cancel**.

### 3.3 Already installed

If a checked skill's folder already exists in `~/.agents/skills` or
`~/.claude/skills`, or the plugin id is already in the registry, the preview
shows a caption "Already installed" beside that row (unchecked by default) and
the Install button is disabled when nothing new remains. No update path in
this plan.

## 4. Accepted inputs and recognition

Recognition has two tiers. Tier 1 is deterministic and always available. Tier
2 runs only when tier 1 finds nothing and only on Macs where Apple's on-device
model is available. Both tiers produce the same `InstallIntent` value, and
**every intent is verified (§5) before a preview appears** — recognition alone
never triggers an install.

### 4.1 Tier 1 — deterministic parser (`InstallIntentParser`)

Scans the pasted text (trimmed; multi-line allowed) for the first match of
these shapes, in this order:

| Shape | Example | Intent |
|---|---|---|
| Slash plugin pair | `/plugin marketplace add o/r` + `/plugin install p@m` | `.plugin(name: p, marketplace: m, marketplaceSource: "o/r")` |
| Slash plugin single | `/plugin install p@m` | `.plugin(name: p, marketplace: m, marketplaceSource: nil)` |
| CLI plugin | `claude plugin install p@m` (optionally preceded by `claude plugin marketplace add src`) | same as above |
| npx skills | `npx skills add <ref> [--skill a,b] [-s a]` where `<ref>` is `o/r`, `github.com/o/r`, or a GitHub URL | `.skillsRepo(owner, repo, subpath: nil, onlySkills: [a,b])` |
| skills.sh link | `https://[www.]skills.sh/o/r[/skill]` | `.skillsRepo(o, r, subpath: nil, onlySkills: [skill]?)` |
| GitHub link | `https://github.com/o/r[/tree/<ref>/<path>]` (`.git` suffix tolerated) | `.skillsRepo(o, r, subpath: path?, onlySkills: [lastComponent]? when path given)` |
| Bare shorthand | `o/r` alone on a line, both parts `[A-Za-z0-9_.-]+` | `.skillsRepo(o, r, nil, nil)` |

Anything else → `.unrecognized(diagnosis)`. Extra words around a match are
ignored (a README sentence containing a command still parses).

### 4.2 Tier 2 — on-device model (`IntentGuesser`)

- Uses `FoundationModels` (`SystemLanguageModel.default`), gated by
  `#available(macOS 26, *)` and `availability == .available`. The app's minimum
  target stays macOS 14; the framework is weak-linked.
- One `LanguageModelSession` with fixed instructions; `respond(to:generating:)`
  into a `@Generable` struct `{ kind: "skills-repo"|"plugin"|"unknown", repo,
  marketplace, plugin, skills: [String] }`. 5-second timeout.
- Output maps to `InstallIntent` **only if** the fields form a valid shape
  (`repo` matches `o/r`, or `plugin` and `marketplace` both non-empty).
  Otherwise `.unrecognized`.
- Verified 2026-09-22 on the owner's Mac: ~1–1.3 s per call; correct on npx,
  skills.sh, README-paragraph and Homebrew inputs; dropped the marketplace on
  the two-line slash paste — which tier 1 handles, so tier 2 never sees it.

### 4.3 Diagnosis copy for unrecognized input

Fixed sentences chosen by cheap heuristics (no model needed):

- Contains `brew install` / `npm install` / `pip install` → "That looks like a
  Homebrew/npm/pip command, not a skill or plugin."
- Contains a URL that is not GitHub or skills.sh → "Only GitHub and skills.sh
  links are supported right now."
- Otherwise → "Couldn't find a skill or plugin in that. Try pasting just the
  link or the install command."

## 5. Verification and preview data (`InstallResolver`)

Runs after recognition, off the main thread, cancelled when the text changes.

**Skill repositories**

1. `GET https://api.github.com/repos/{o}/{r}` → description, default branch.
   404 → "That GitHub repository doesn't exist or is private."
2. `GET https://api.github.com/repos/{o}/{r}/git/trees/{branch}?recursive=1` →
   every path ending in `SKILL.md`. Restricted to `subpath` when given. Zero
   results → "That repository doesn't contain any skills (no SKILL.md files)."
3. For each candidate (cap 50), `GET https://raw.githubusercontent.com/{o}/{r}/{branch}/{path}`;
   parse with the existing `FrontmatterParser`. Skills whose frontmatter fails
   are listed greyed with "Has a formatting problem", unchecked, unselectable.
4. Unauthenticated GitHub API limit is 60 requests/hour; on 403 rate-limit →
   "GitHub is rate-limiting requests from this Mac. Try again in a few
   minutes." No token handling in this plan.

**Plugins**

1. If `marketplaceSource` is given and the marketplace is not in
   `known_marketplaces.json`, the preview notes "Will add marketplace <m> from
   <source> first."
2. If the marketplace is known, read its `marketplace.json` under
   `~/.claude/plugins/marketplaces/<m>/.claude-plugin/` for the plugin entry
   (description, homepage). If unknown, the preview shows only the ids and
   says details will be available after the marketplace is added.
3. Plugin id already in `installed_plugins.json` → "Already installed".

Result type: `InstallPreview { kind, title, summary, authorName?, authorURL?,
sourceURL?, skills: [PreviewSkill{folder, name, summary, body, invocation,
isInstalled, isValid}], commands: [String], marketplaceNote? }`.

## 6. Execution (`Installer`)

All commands run via `Process` through the user's login shell
(`/bin/zsh -lic`) so `npx` and `claude` resolve as they do in Terminal, with a
120 s timeout, stdout/stderr captured, and `NO_COLOR=1`, `CI=1`, `TERM=dumb`
in the environment to suppress spinners.

**Skill repository** — one invocation:

```
npx -y skills add <o>/<r> -g -y -a claude-code -s <skill1>,<skill2>
```

This writes the canonical copy to `~/.agents/skills/<skill>` and symlinks it
into `~/.claude/skills/<skill>` — the layout the app's readers already
understand — and records `~/.agents/.skill-lock.json`, which feeds the
provenance links from the 2026-09-21 spec.

**Plugin** — one or two invocations:

```
claude plugin marketplace add <source>        # only when marketplaceSource given and marketplace unknown
claude plugin install <name>@<marketplace> -y
```

Exit code 0 → success; the existing FSEvents watcher reloads the library. The
Result state lists the installed skills by reading the freshly reloaded
inventory (matching folder names from the intent), so the cheat sheet is real,
not predicted; if a folder has not appeared within 3 s the result falls back to
the predicted invocation with the caption "Reloading…".

Non-zero exit or timeout → failure state with the catalog sentence (§7) and
the raw output.

Preconditions checked when the sheet opens, shown as an inline note with the
Install button disabled if unmet: `npx` resolvable (skills) or `claude`
resolvable (plugins). Messages: "Node.js is needed to install skills. Install
it from nodejs.org, then try again." / "Claude Code's command-line tool wasn't
found."

## 7. Failure copy catalog

| Detected in output / condition | Sentence |
|---|---|
| Timeout | "The installer didn't finish in two minutes. Check your connection and try again." |
| `ENOTFOUND` / `Could not resolve host` | "Couldn't reach GitHub. Check your connection." |
| `Repository not found` / `404` | "That repository doesn't exist or is private." |
| `EACCES` / `Permission denied` | "macOS blocked writing to your skills folder." |
| `not found in marketplace` | "That plugin isn't in the <m> marketplace." |
| anything else | "The installer reported a problem. Show details for what it said." |

## 8. Architecture

Everything new lives in `SkillsManagerCore` except the SwiftUI sheet and the
FoundationModels guesser (framework is only linkable from the app target on
macOS 26+).

| Unit | Responsibility |
|---|---|
| `InstallIntent` (enum) | `.skillsRepo(owner, repo, subpath?, onlySkills?)`, `.plugin(name, marketplace, marketplaceSource?)`, `.unrecognized(String)` |
| `InstallIntentParser` | pure `parse(_ text: String) -> InstallIntent` (tier 1 + §4.3 diagnosis) |
| `IntentGuesser` | protocol `func guess(_ text: String) async -> InstallIntent`; `NoopGuesser` in Core; `FoundationModelsGuesser` in App |
| `GitHubClient` | protocol with `repo`, `tree`, `raw` methods; `URLSessionGitHubClient` + `StubGitHubClient` (tests) |
| `InstallResolver` | `resolve(intent, github:, paths:) async throws -> InstallPreview` |
| `CommandRunner` | protocol `run(_ argv: [String], timeout:) async -> CommandResult{status, stdout, stderr, timedOut}`; `ShellCommandRunner` + `FakeCommandRunner` |
| `Installer` | `plan(preview, selectedFolders) -> [[String]]`, `install(...) async -> InstallOutcome` mapping output to §7 |
| `InstallSheet` (App) | the three states; `InstallSheetModel` (`@Observable`) orchestrates parser → guesser → resolver → installer with cancellation |

## 9. Design requirements (owner mandate)

UI tasks must invoke `apple-design`, `make-interfaces-feel-better`,
`emil-design-eng`, and the `better-*` series (`better-ui`, `better-layout`,
`better-typography`, `better-accessibility`, `better-writing`). Expectations:
a standard macOS sheet (not a window); the paste field is the only thing on
screen at first; state changes animate with critically damped motion and
respect reduced motion; the preview reuses `InvocationChip`, `SourceLink`,
`KindBadge`, `SectionCard`; progress is an indeterminate bar with the current
step's plain-English label; errors are never red walls of text.

## 10. Safety and trust

- No command runs without a click on Install. Model output never triggers a
  command.
- The exact command is visible in the preview before install.
- Network: GitHub API, raw.githubusercontent.com, and whatever the two
  installers themselves fetch. No app telemetry.
- The app still never edits skill/plugin folders or Claude Code's JSON files
  directly.

## 11. Testing

- `InstallIntentParserTests`: one test per accepted shape (§4.1, incl. README
  noise and the two-line slash paste); rejections (Homebrew, npm, prose,
  non-GitHub URL) with the expected diagnosis sentence.
- `InstallResolverTests`: `StubGitHubClient` fixtures — repo with 3 skills, one
  malformed; subpath narrowing; `onlySkills` preselection; 404; rate limit;
  plugin known / unknown marketplace / already installed.
- `InstallerTests`: `FakeCommandRunner` — exact argv for skills (with `-s`
  list) and plugins (with and without marketplace add); exit-code and output →
  §7 mapping; timeout.
- `IntentGuesser`: unit-tested via `NoopGuesser`; the FoundationModels path is
  verified manually (nondeterministic).
- Owner checkpoint: paste the npx line, the skills.sh link, the slash-plugin
  pair and a plain GitHub link; confirm previews; install one skill and one
  plugin; confirm both appear in the library with correct cheat sheets; paste
  `brew install ripgrep` and see the diagnosis.

## 12. Deferred

- Update / uninstall (Plan 4 Updates view).
- Other-agent targets (Plan 3 visibility map / Connect).
- GitHub token for higher rate limits.
- Using the on-device model to phrase diagnoses (fixed sentences suffice).
