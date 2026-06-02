import Foundation

enum Formatters {
    /// "mm:ss" (or "h:mm:ss" past an hour).
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func timestamp(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }

    private static let fileStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    /// Default display name for a new recording, e.g. "Recording 2026-06-01 at 14.05.32".
    static func defaultName(_ date: Date) -> String {
        "Recording \(fileStamp.string(from: date))"
    }
}
