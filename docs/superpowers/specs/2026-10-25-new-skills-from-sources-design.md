# New Skills From Your Sources — Design Spec

**Date:** 2026-10-25
**Status:** Approved in brainstorming; pending owner review of this document
**Builds on:** `2026-09-22-install-box-design.md` (install pipeline: `GitHubClient`,
`InstallResolver`, `Installer`), `2026-09-21-detail-provenance-design.md`
(`SkillLock`, the skills.sh lock file), `2026-10-11-recommendations-and-home-depot-build-design.md`
(the pattern of an install-capable sheet driven from the library).

## 1. Problem

The owner installs skill *sets* from a handful of GitHub repos (today: 41 skills
from 6 repos, e.g. `jakubkrehel/skills`, `emilkowalski/skills`). When an author
adds a new skill to a repo the owner already installed from, nothing in the app
notices. The owner learns about it from the author's newsletter, then has to
open a terminal or the install box and re-run the install for that repo.

Skills already installed are kept current by the installer's own update path,
so this is strictly about skills the owner **does not have yet** from repos
they **already trust**.

## 2. Goals, non-goals, anti-goals

### Goals

1. Once a day, and on every manual Refresh, the app checks each source repo
   for skill folders that are not installed locally.
2. Findings surface in a dedicated **What's new** toolbar button that exists
   only while there is something to show, plus a macOS notification when a
   check finds something new.
3. Each finding installs with one click, no confirmation, through the existing
   skills.sh installer. The library then updates by itself.

### Non-goals

- Flagging installed skills whose upstream content changed. The installer
  handles updates; the owner explicitly excluded this.
- Discovering repos the owner has never installed from. No recommendations,
  trending, or "other skills by this author" from other repos.
- Plugins (Claude Code marketplaces). The lock file only covers skills.sh
  installs; plugins have their own update path.
- Any change to the **+** (Install) button or sheet. The owner was explicit
  that overloading **+** would confuse users.

### Anti-goals (would make this a failure even if it works)

- A toolbar that looks different from today when there is nothing new.
- A check that runs so often it hits GitHub's unauthenticated rate limit and
  breaks the install box, which shares the same limit.
- A notification for anything other than "new skills found": no notifications
  for "checked, nothing new", for offline, or for rate limiting.
- The check blocking or slowing the local reload that Refresh does today.

## 3. What the app already knows

- `~/.agents/.skill-lock.json` (parsed by `SkillLock`) records, per installed
  skill folder: `source` ("owner/repo"), `sourceUrl`, `skillPath` inside the
  repo, install and update timestamps. This is the authoritative list of
  **source repos** and of which folders came from each.
- `InstallResolver.resolveRepo` already turns "owner/repo" into an
  `InstallPreview` by calling the repo endpoint, the recursive tree endpoint,
  and then `raw.githubusercontent.com` once per `SKILL.md`. It marks each
  `PreviewSkill.isInstalled` by checking the two local skills directories.
- `Installer.plan` builds `npx -y skills add owner/repo -g -y -a claude-code -s <folders>`.
- `InventoryStore.reload()` is the Refresh action; the file watcher
  (`FileWatcher`) re-runs it when the skills directories change, so a
  successful install appears in the library without further work.
- `InstallError.rateLimited` and `.network` already distinguish a GitHub
  outage from a bad repo.

## 4. The check (Core)

New type in `SkillsManagerCore`: **`SourceCheck`** (name is the builder's call).

**Input:** the `SkillLock`, the set of locally present skill folder names
(same two directories `InstallResolver` uses), and a `GitHubClient`.

**Sources:** the distinct `source` values in the lock whose entries parse as
`owner/repo`. Entries with no source, or a non-GitHub `sourceType`, are
skipped. A repo is a source even if only one skill from it is installed.

**Per source:**

1. List `SKILL.md` paths in the repo's default branch (the recursive tree
   endpoint, as `resolveRepo` does). Builder may use `git/trees/HEAD` to skip
   the separate repo-info call; one request per repo is the target.
2. Derive each skill's folder name exactly as `resolveRepo` does (parent
   folder of `SKILL.md`; the repo name when `SKILL.md` is at the root).
3. A folder is **new** when it is not present locally **and** not in the
   lock. There is no ignore list (§7).
4. For new folders only, download that `SKILL.md` and parse frontmatter for
   `name` and `description`. Skills already installed are never downloaded
   again; this keeps the per-day cost near one API request per repo.
5. A skill whose frontmatter is missing or malformed is still reported, with
   the folder name and no description, so the owner can decide. (Matches how
   the install box shows invalid skills.)

**Output:** `[SourceFinding]`, one per repo, each holding `owner`, `repo`,
`sourceURL`, and `[NewSkill]` (`folder`, `name`, `summary`, `skillURL` on
GitHub). Repos with no new skills produce no finding.

**Failure handling:** per repo, not global. A repo that 404s (deleted,
renamed, private) is skipped silently and logged. A `.rateLimited` or
`.network` error aborts the remaining repos for this run (the next ones will
fail too), the run is recorded as *not completed*, and the previous findings
stay on screen. Nothing is shown to the owner for a failed run except the
"Checked …" footer not advancing.

**Testability:** `SourceCheck` takes `GitHubClient` and the installed-folder
set as parameters so tests use a stub client over fixture trees, as
`InstallResolverTests` do today.

## 5. Scheduling (App)

Owned by a new `@Observable` **`SourceUpdatesModel`** (name is the builder's
call) created alongside `InventoryStore` in the app and injected into the
library view.

Runs a check when **any** of these is true:

- **Daily:** the last *completed* check was not today (local calendar day).
  Evaluated on launch, and while the app is open by a timer that fires
  hourly and re-evaluates (so an app left open overnight checks the next
  morning without a relaunch). Opening the app a second time on the same
  day does not re-check.
- **Manual Refresh:** every `store.reload()` triggered by the Refresh button
  or ⌘R, **subject to a 10-minute cooldown**: if a check completed (or
  started) less than 10 minutes ago, Refresh only rescans the disk and the
  popover footer keeps showing when GitHub was last checked. Owner's
  decision, to protect the 60/h GitHub limit the install box shares. The
  automatic FSEvents-driven reloads do **not** trigger a check
  (otherwise installing a skill would trigger a network round trip). Builder
  adds a way to tell the two apart; the simplest is for the toolbar button
  and ⌘R to call a new `store.refresh()` that calls `reload()` and then the
  model, leaving `reload()` as is.
- **After a successful install from the popover:** no new check. The
  installed row is removed locally and the lock file is re-read on the next
  reload, which the file watcher triggers.

Only one check runs at a time; a request while one is in flight is dropped.

The check runs off the main actor and never delays `reload()`. Results are
merged on the main actor.

**Persistence (UserDefaults):**

- `sourceCheckLastCompleted: Date` — set only when a run finishes without a
  network or rate-limit abort.
- `sourceCheckDismissedUntilNew: Bool` — set when the owner dismisses the
  findings (§7); cleared when a check finds a skill not yet in
  `sourceCheckNotifiedSkills`.
- `sourceCheckLastFindings: Data` — the last findings, JSON-encoded, so the
  button and popover are correct immediately on launch, before the day's
  check runs or when offline.
- `sourceCheckNotifiedSkills: [String]` — keys already announced in a
  notification (§8), so a skill is announced once, not daily.

## 6. Toolbar button

In `LibraryView`'s detail toolbar, **left of the + (Install) button**, a
`ToolbarItem` that renders **only when `findings` is non-empty**. When there
is nothing new the toolbar is pixel-identical to today.

- Icon: `bell.badge` (SF Symbol). Label "What's new". Help text:
  "New skills from sources you've installed from".
- A count badge showing the total number of new skills across repos.
  `.badge()` on the button if the toolbar honours it on the deployed macOS
  versions (the app supports macOS 26 and 27; see the earlier sidebar-title
  fix for 27-specific toolbar quirks); otherwise an overlay capsule drawn by
  hand, as the mockup showed.
- Clicking toggles the popover (§7). It is a `.popover` anchored to the
  button, not a sheet, so it never fights the install / recommendations /
  project-access sheet arbitration in `LibraryView`.
- **No new menu item.** The existing **View → Refresh** (⌘R) already runs
  the check; the popover opens only from the toolbar button or from a
  notification. Owner's decision: one more menu line next to Refresh would
  be clutter.

## 7. The popover

Width about 380pt. Content, top to bottom:

- Title "New from your sources".
- One **section per repo**, header "owner/repo" as a link that opens the
  repo on GitHub. Repos sorted by owner then name; skills within a repo
  sorted by folder name.
- One **row per new skill**: name (frontmatter `name`, else folder) in body
  weight, the description beneath in secondary colour, one line, truncated.
  Trailing **Install** button (default style, filled). No per-row ignore.
- When a repo has two or more new skills, a trailing **Install all** text
  button in its section header.
- Footer in caption style: "Checked 2 hours ago" using the relative date
  formatter, or "Not checked yet". When the last run aborted on network or
  rate limit, the footer reads "Couldn't reach GitHub · checked 2 hours ago".
- A **Dismiss** text button in the footer. Dismiss hides the button (and
  closes the popover) until the next check finds a skill not seen before.
  When that happens, the popover comes back showing **every** uninstalled
  skill from the sources, including previously dismissed ones. Owner's
  decision: they always want the full picture of what they have and have
  not installed; nothing is permanently hidden.
- When the owner installs the last row, the popover closes and the button
  disappears.

**Install behaviour:** clicking Install on a row runs
`Installer.install` for a preview built for that repo with
`selectedFolders: [folder]`. The builder may construct a minimal
`InstallPreview(kind: .skillsRepo, owner:, repo:, …)` directly rather than
re-resolve the repo over the network. "Install all" passes every folder of
that repo in one command. While running, the row shows a progress spinner in
place of the button and **every other Install button in the popover is
disabled**, across repos: the app runs one installer process at a time,
because two `npx skills add` processes could both rewrite the lock file.
(Builder's call, made here: a single install queue, not per-repo state.) On success, the row is removed and
the key is added to `sourceCheckNotifiedSkills` so it won't be announced
again if the folder disappears later. On failure, the row shows the
`FailureCopy` sentence in red beneath the description with a "Try again"
button; the log is available via a "Show Details" disclosure, as in the
install box.

No confirmation step. The owner has already installed from this repo; that
is the trust signal.

**Closing the popover** (clicking away) does not clear findings; only
**Dismiss** does, and only until something new appears. The button stays
until every row is installed or the findings are dismissed.

## 8. Notification

Uses `UserNotifications`. On the first run that needs it, request
`.alert` + `.badge` authorization. If denied, the feature works without
notifications; the toolbar button is sufficient.

After a **completed** check, compute the set of new-skill keys not in
`sourceCheckNotifiedSkills`. If non-empty, post one notification:

- One skill: title "New skill from jakubkrehel", body "teardown — <description>".
- Several: title "3 new skills from your sources", body lists up to three
  names then "and 2 more".

Add all announced keys to `sourceCheckNotifiedSkills`.

**Day one:** the first completed check announces everything it finds,
including skills that have existed for months and were skipped on purpose
when the repo was first installed. Owner's decision: they would rather hear
about them once and ignore them than have the first run be silent. Clicking the
notification brings the app forward and opens the popover (post a
`NotificationCenter` name like `.showSourceUpdates`, matching the existing
`.showInstallSheet` pattern).

No notification when the app is in the foreground **and** the library window
is key; the button appearing is enough there. (Owner asked not to be too
quiet; this still fires whenever the app is in the background or hidden.)

Dismissal never affects notifications: a skill is announced exactly once,
the first time any check sees it.

## 9. Edge cases

- **Lock file missing or empty** (user installed nothing via skills.sh):
  no sources, no check, no button. Nothing else changes.
- **Skill installed manually** (folder exists, not in lock): treated as
  installed; not reported. Presence on disk wins.
- **Skill uninstalled by the owner** (in lock, folder gone): the lock entry
  usually goes with it, but if it lingers, "in the lock" still counts as
  not-new. The owner removed it on purpose; don't nag.
- **Repo moved or renamed:** 404; skipped and logged. If the owner later
  installs from the new name, that becomes a source.
- **Repo with a root `SKILL.md` only** (single-skill repo like
  `jakubkrehel/make-interfaces-feel-better`): folder name is the repo name;
  it is installed, so never new. Works with no special case.
- **Home Depot flavour:** same behaviour. The feature depends only on the
  lock file, not on the bundled catalog.
- **Rate limit shared with the install box:** the daily cost is about one
  request per source repo plus one raw download per genuinely new skill, so
  under ten requests a day for the owner's setup. Manual Refresh is the only
  way to multiply that, and each run is still under ten.

## 10. Builder's calls (not decided by the owner)

- Type and property names, file layout within Core and App.
- Whether to use `git/trees/HEAD` or keep the two-call repo+tree sequence.
- Timer implementation for the hourly day-rollover check.
- Whether `.badge()` or a hand-drawn capsule renders the count, after
  checking both macOS versions.
- Exact notification wording beyond the examples above.
- Anything about tests beyond: `SourceCheck` is covered by unit tests with a
  stub `GitHubClient`; the day-rollover rule and the dismissed flag and notified set are
  covered by tests on the model with an injected clock and defaults.

## 11. Out of scope for this spec, noted for later

- Checking plugin marketplaces for new plugins.
- Authenticated GitHub access to raise the rate limit.
- A Settings toggle to turn the daily check or notifications off. The macOS
  notification settings pane already covers notifications; a toggle for the
  check itself can be added if anyone asks.
