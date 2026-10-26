import Foundation

/// Scheduling, notification and dismissal arithmetic for the "new skills from your sources" check.
/// Pure functions only; timers, persistence and UserDefaults live in the app model.
public enum SourceUpdatesRules {
    /// Minimum gap between manual checks, measured from the start of the previous check.
    public static let manualCooldown: TimeInterval = 600

    /// Daily rule: no completed check on `now`'s calendar day.
    public static func isDailyDue(lastCompleted: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastCompleted else { return true }
        return !calendar.isDate(lastCompleted, inSameDayAs: now)
    }

    /// Manual rule: no check *started* within the cooldown.
    public static func isManualAllowed(lastStarted: Date?, now: Date) -> Bool {
        guard let lastStarted else { return true }
        return now.timeIntervalSince(lastStarted) >= manualCooldown
    }

    /// Keys in `findings` not yet in `notified`, in findings order.
    public static func unannouncedKeys(findings: [SourceFinding], notified: Set<String>) -> [String] {
        findings.flatMap { finding in
            finding.skills.map { finding.key($0) }
        }.filter { !notified.contains($0) }
    }

    /// Notification copy. nil when nothing to announce.
    public static func notificationText(
        findings: [SourceFinding],
        unannounced: [String]
    ) -> (title: String, body: String)? {
        let resolved: [(owner: String, skill: NewSkill)] = unannounced.compactMap { key in
            for finding in findings {
                if let skill = finding.skills.first(where: { finding.key($0) == key }) {
                    return (finding.owner, skill)
                }
            }
            return nil
        }
        guard let first = resolved.first else { return nil }

        if resolved.count == 1 {
            let body = first.skill.summary.map { "\(first.skill.name) — \($0)" } ?? first.skill.name
            return ("New skill from \(first.owner)", body)
        }

        let shown = resolved.prefix(3).map { $0.skill.name }
        let remaining = resolved.count - shown.count
        var body = shown.joined(separator: ", ")
        if remaining > 0 { body += " and \(remaining) more" }
        return ("\(resolved.count) new skills from your sources", body)
    }

    /// Whether the toolbar button shows.
    public static func isVisible(findings: [SourceFinding], dismissedUntilNew: Bool) -> Bool {
        !findings.isEmpty && !dismissedUntilNew
    }

    /// Dismissal survives a check only if it found nothing unannounced.
    public static func dismissedAfterCheck(previouslyDismissed: Bool, unannounced: [String]) -> Bool {
        previouslyDismissed && unannounced.isEmpty
    }

    /// `now` when the run completed, else `previous` unchanged.
    public static func nextLastCompleted(previous: Date?, result: SourceCheckResult, now: Date) -> Date? {
        result.completed ? now : previous
    }
}
