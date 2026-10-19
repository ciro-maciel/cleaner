import Foundation

/// Byte and date formatting in the interface language (L10n.locale), decimal units like Finder
/// (1 GB = 1000³ bytes). "MB" and the other units read the same in both languages.
enum Format {
    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = L10n.locale
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        return f
    }()

    static func bytes(_ value: Int64) -> String {
        let (amount, unit) = split(value)
        return "\(amount) \(unit)"
    }

    /// The number and the unit apart, for the big metric (number huge, unit small).
    static func split(_ value: Int64) -> (String, String) {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var v = Double(max(value, 0))
        var i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        number.maximumFractionDigits = (i <= 1 || v >= 100) ? 0 : 1
        return (number.string(from: NSNumber(value: v)) ?? "0", units[i])
    }

    static func count(_ value: Int) -> String {
        number.maximumFractionDigits = 0
        return number.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func percent(_ part: Int64, of whole: Int64) -> String {
        guard whole > 0 else { return "0%" }
        let p = Double(part) / Double(whole) * 100
        if p > 0 && p < 1 { return "<1%" }
        return "\(Int(p.rounded()))%"
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = L10n.locale
        // Portuguese keeps its reviewed "12 de out., 14:30"; English asks the locale ("Oct 12, 2:30 PM").
        if L10n.isPortuguese { f.dateFormat = "d 'de' MMM, HH:mm" } else { f.setLocalizedDateFormatFromTemplate("MMMdjmm") }
        return f
    }()

    static func date(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        switch days {
        case ..<1: return L("today")
        case 1: return L("yesterday")
        case 2..<60: return L("%@ days ago", String(days))
        case 60..<730: return L("%@ months ago", String(days / 30))
        default: return L("%@ years ago", String(days / 365))
        }
    }

    /// A path with the home folder written as ~.
    static func path(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// Bytes per second. Compact drops the "/s", for the menu bar.
    static func rate(_ value: Int64, compact: Bool = false) -> String {
        let (n, unit) = split(value)
        let u = unit == "bytes" ? "B" : unit
        return compact ? "\(n) \(u)" : "\(n) \(u)/s"
    }

    /// "145G" style, for the menu bar.
    static func compactBytes(_ value: Int64) -> String {
        let (n, unit) = split(value)
        return n + (unit == "bytes" ? "B" : String(unit.prefix(1)))
    }

    /// 135 → "2 h 15 min"
    static func minutes(_ value: Int) -> String {
        let h = value / 60, m = value % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// Seconds since boot → "3 d 4 h" / "5 h 12 min"
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds) / 60
        let d = total / 1440, h = (total % 1440) / 60, m = total % 60
        if d > 0 { return "\(d) d \(h) h" }
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    static func plural(_ n: Int, _ one: String, _ many: String) -> String {
        "\(count(n)) \(n == 1 ? one : many)"
    }
}
