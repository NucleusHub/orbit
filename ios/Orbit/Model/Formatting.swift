import Foundation

/// The web client's `formatSize`, `formatRelativeDate` and `formatEta`.
enum Formatting {
    static func size(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if bytes == 0 { return "0 B" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", b / 1024) }
        if bytes < 1024 * 1024 * 1024 { return String(format: "%.1f MB", b / 1_048_576) }
        return String(format: "%.2f GB", b / 1_073_741_824)
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let diff = now.timeIntervalSince(date)
        let mins = Int(diff / 60), hours = Int(diff / 3600), days = Int(diff / 86400)
        if mins < 1 { return String(localized: "Just now") }
        if mins < 60 { return String(localized: "\(mins)m ago") }
        if hours < 24 { return String(localized: "\(hours)h ago") }
        if days < 7 { return String(localized: "\(days)d ago") }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func eta(_ seconds: Double?) -> String? {
        guard let s = seconds, s.isFinite, s >= 0 else { return nil }
        if s < 60 { return "\(max(1, Int(s.rounded())))s" }
        let m = Int(s / 60), rest = Int(s.truncatingRemainder(dividingBy: 60).rounded())
        return rest > 0 ? "\(m)m \(rest)s" : "\(m)m"
    }
}
