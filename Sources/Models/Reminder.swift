import Foundation

/// A single nagging reminder: what to do, when it is due, and how persistently to nag about it.
struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var due: Date
    var repeatInterval: TimeInterval?
    var nagMinutes: Int
    var completedAt: Date?

    var isDone: Bool { completedAt != nil }

    /// Nag fire times strictly after `from`, stepping from `due` by the nag interval.
    /// `maxRepeats` caps the re-deliveries after the first one (0 means unlimited).
    func nagTimes(after from: Date, maxRepeats: Int, limit: Int) -> [Date] {
        let step = TimeInterval(max(1, nagMinutes) * 60)
        var k = due > from ? 0 : Int(from.timeIntervalSince(due) / step) + 1
        var out: [Date] = []
        while out.count < limit, maxRepeats == 0 || k <= maxRepeats {
            out.append(due.addingTimeInterval(Double(k) * step))
            k += 1
        }
        return out
    }
}

/// Turns phrases like "call the dentist in 20 minutes", "submit report tomorrow 9am"
/// or "stretch every 2 hours" into a title, a due date and an optional repeat interval.
enum ReminderParser {
    struct Result {
        var title: String
        var due: Date?
        var repeatInterval: TimeInterval?
    }

    private static let unit = #"(minutes?|mins?|m|hours?|hrs?|h|days?|d)\b"#

    static func parse(_ text: String, now: Date = Date()) -> Result {
        var s = text
        var due: Date?
        var repeatInterval: TimeInterval?

        if let m = match(#"\bevery\s+(\d+)?\s*"# + unit, in: s) {
            repeatInterval = (Double(m.groups[0] ?? "") ?? 1) * seconds(m.groups[1])
            s.removeSubrange(m.range)
        }
        if let m = match(#"\bin\s+(\d+|an?)\s*"# + unit, in: s) {
            due = now.addingTimeInterval((Double(m.groups[0] ?? "") ?? 1) * seconds(m.groups[1]))
            s.removeSubrange(m.range)
        } else if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
                  let m = detector.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  var date = m.date, let r = Range(m.range, in: s) {
            // A bare time of day that already passed means the next occurrence.
            while date <= now, now.timeIntervalSince(date) < 86_400 * 7 {
                date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? now
            }
            due = date
            s.removeSubrange(r)
        }
        if due == nil, let repeatInterval { due = now.addingTimeInterval(repeatInterval) }

        var title = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        title = title.replacingOccurrences(of: #"^remind me( to)?\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        title = title.replacingOccurrences(of: #"(\s+(at|on|by|for|in|next|this))+$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return Result(title: title, due: due, repeatInterval: repeatInterval)
    }

    private static func seconds(_ unit: String?) -> TimeInterval {
        switch unit?.lowercased().first {
        case "h": return 3600
        case "d": return 86_400
        default: return 60
        }
    }

    private static func match(_ pattern: String, in s: String) -> (range: Range<String.Index>, groups: [String?])? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range, in: s) else { return nil }
        let groups = (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
        return (r, groups)
    }
}

/// Human-friendly date and duration strings used by previews, rows and notifications.
enum Fmt {
    static func when(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "today \(time)" }
        if cal.isDateInTomorrow(date) { return "tomorrow \(time)" }
        if cal.isDateInYesterday(date) { return "yesterday \(time)" }
        if date > now, date.timeIntervalSince(now) < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.wide)) + " \(time)"
        }
        return date.formatted(.dateTime.month(.abbreviated).day()) + ", \(time)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = [.day, .hour, .minute]
        f.maximumUnitCount = 2
        return f.string(from: seconds) ?? "\(Int(seconds / 60)) minutes"
    }
}
