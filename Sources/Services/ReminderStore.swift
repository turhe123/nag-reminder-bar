import Foundation
import AppKit

/// Owns the reminder list: JSON persistence in Application Support, grouping for the UI,
/// every user action (add, done, snooze, delete) and the once-a-minute reconcile loop.
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published private(set) var reminders: [Reminder] = []
    @Published private(set) var now = Date()
    private var timer: Timer?
    private var lastFallbackAlert = Date.distantPast
    private let historyLimit = 20

    private init() {
        load()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Grouping

    var active: [Reminder] { reminders.filter { !$0.isDone }.sorted { $0.due < $1.due } }
    var overdue: [Reminder] { active.filter { $0.due <= now } }
    var today: [Reminder] { active.filter { $0.due > now && Calendar.current.isDateInToday($0.due) } }
    var later: [Reminder] { active.filter { $0.due > now && !Calendar.current.isDateInToday($0.due) } }
    var history: [Reminder] {
        reminders.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: Actions

    func add(title: String, due: Date, repeatInterval: TimeInterval?) {
        reminders.append(Reminder(title: title, due: due, repeatInterval: repeatInterval, nagMinutes: Prefs.nagMinutes))
        commit()
    }

    func update(_ reminder: Reminder) {
        guard let i = index(reminder.id) else { return }
        reminders[i] = reminder
        commit()
    }

    func complete(_ id: UUID) {
        guard let i = index(id) else { return }
        let date = Date()
        if let step = reminders[i].repeatInterval, step >= 60 {
            while reminders[i].due <= date { reminders[i].due.addTimeInterval(step) }
        } else {
            reminders[i].completedAt = date
        }
        trimHistory()
        NotificationService.shared.clearDelivered(for: id)
        commit()
    }

    func snooze(_ id: UUID, minutes: Int) {
        mutate(id) { $0.due = Date().addingTimeInterval(TimeInterval(minutes * 60)) }
    }

    /// Moves a reminder to tomorrow, keeping its time of day.
    func tomorrow(_ id: UUID) {
        mutate(id) { r in
            let cal = Calendar.current
            let parts = cal.dateComponents([.hour, .minute], from: r.due)
            let base = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
            r.due = cal.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: base) ?? base
        }
    }

    func setNag(_ id: UUID, minutes: Int) { mutate(id) { $0.nagMinutes = minutes } }

    func delete(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        NotificationService.shared.clearDelivered(for: id)
        commit()
    }

    func clearHistory() {
        reminders.removeAll(where: \.isDone)
        commit()
    }

    // MARK: Reconcile

    /// Refreshes the clock, tops up pending notifications and shows the fallback panel if needed.
    func tick() {
        now = Date()
        NotificationService.shared.refreshStatus()
        NotificationService.shared.reschedule(reminders)
        showFallbackIfNeeded()
    }

    /// After sleep: one catch-up notification for everything that went overdue, then resume nagging later.
    func handleWake() {
        now = Date()
        let late = overdue
        if !late.isEmpty { NotificationService.shared.postCatchUp(late) }
        NotificationService.shared.reschedule(reminders, force: true, from: now.addingTimeInterval(60))
        showFallbackIfNeeded()
    }

    private func showFallbackIfNeeded() {
        guard NotificationService.shared.denied, let first = overdue.first else { return }
        let gap = TimeInterval((overdue.map(\.nagMinutes).min() ?? first.nagMinutes) * 60)
        guard now.timeIntervalSince(lastFallbackAlert) >= gap else { return }
        lastFallbackAlert = now
        FloatingPanel.alert.show(title: "Overdue reminders", FallbackAlertView())
    }

    // MARK: Persistence

    private func index(_ id: UUID) -> Int? { reminders.firstIndex { $0.id == id } }

    private func mutate(_ id: UUID, _ change: (inout Reminder) -> Void) {
        guard let i = index(id) else { return }
        change(&reminders[i])
        NotificationService.shared.clearDelivered(for: id)
        commit()
    }

    private func trimHistory() {
        let old = history.dropFirst(historyLimit).map(\.id)
        reminders.removeAll { old.contains($0.id) }
    }

    private func commit() {
        now = Date()
        save()
        NotificationService.shared.reschedule(reminders, force: true)
    }

    private var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("NagReminderBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("reminders.json")
    }

    private func load() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do { reminders = try decoder.decode([Reminder].self, from: data) } catch {
            NSLog("NagReminderBar: could not read reminders: \(error)")
        }
    }

    private func save() {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        do { try encoder.encode(reminders).write(to: url, options: .atomic) } catch {
            NSLog("NagReminderBar: could not save reminders: \(error)")
        }
    }
}
