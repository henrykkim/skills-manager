import Foundation

/// The row hint text for a skill's usage recency. Pure so the format lives
/// in one place and is trivial to test.
enum UsageHint {
    static func text(lastUsed: Date?, now: Date = Date()) -> String {
        guard let lastUsed else { return "Not used yet" }
        let calendar = Calendar.current
        let dayCount = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastUsed),
                                                to: calendar.startOfDay(for: now)).day ?? 0
        switch dayCount {
        case 0: return "Used today"
        case 1: return "Used yesterday"
        case 2...21: return "Used \(dayCount) days ago"
        default:
            let formatted = lastUsed.formatted(.dateTime.month(.abbreviated).day())
            return "Used \(formatted)"
        }
    }
}
