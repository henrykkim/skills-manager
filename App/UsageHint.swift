import Foundation

/// The row hint text for a skill's usage recency. Pure so the format lives
/// in one place and is trivial to test.
enum UsageHint {
    static func text(lastUsed: Date?, now: Date = Date()) -> String {
        guard let lastUsed else { return "Not used yet" }
        return "Used \(relativeDay(lastUsed: lastUsed, now: now))"
    }

    /// The bare relative-day phrase, without the leading "Used " — for
    /// contexts (like a stat tile) that already supply their own label.
    static func relativeDay(lastUsed: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let dayCount = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastUsed),
                                                to: calendar.startOfDay(for: now)).day ?? 0
        switch dayCount {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2...21: return "\(dayCount) days ago"
        default:
            return lastUsed.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
