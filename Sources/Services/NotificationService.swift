import AppKit
import UserNotifications

/// Wraps UNUserNotificationCenter: permission, the Done / Snooze / Tomorrow category,
/// pre-scheduling the nearest nag deliveries (below the 64-request limit) and handling responses.
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    @Published private(set) var denied = false
    /// True while the Mac sleeps, so nothing queues up into a burst on wake.
    var suspended = false

    private let center = UNUserNotificationCenter.current()
    private let maxPending = 60
    private let category = "NAG"

    func setup() {
        center.delegate = self
        registerCategory()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            if let error { NSLog("NagReminderBar: notification permission error: \(error)") }
            DispatchQueue.main.async {
                self.refreshStatus()
                ReminderStore.shared.tick()
            }
        }
    }

    func refreshStatus() {
        center.getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async { if self.denied != denied { self.denied = denied } }
        }
    }

    /// Registered again whenever the default snooze length changes so the button title stays accurate.
    func registerCategory() {
        let actions = [
            UNNotificationAction(identifier: "DONE", title: "Done", options: []),
            UNNotificationAction(identifier: "SNOOZE", title: "Snooze \(Prefs.snoozeMinutes) minutes", options: []),
            UNNotificationAction(identifier: "TOMORROW", title: "Tomorrow", options: []),
        ]
        center.setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [], options: []),
        ])
    }

    /// Schedules the nearest nag deliveries. `force` replaces everything (after edits);
    /// otherwise only the difference is applied so imminent requests are never dropped.
    func reschedule(_ reminders: [Reminder], force: Bool = false, from: Date = Date()) {
        guard !suspended else { return center.removeAllPendingNotificationRequests() }
        let now = Date()
        let maxRepeats = Prefs.maxRepeats
        let wanted = reminders.filter { !$0.isDone }
            .flatMap { r in r.nagTimes(after: from, maxRepeats: maxRepeats, limit: maxPending).map { (r, $0) } }
            .sorted { $0.1 < $1.1 }
            .prefix(maxPending)
            .map { r, date in (id: "\(r.id.uuidString)|\(Int(date.timeIntervalSince1970))|\(r.nagMinutes)", r: r, date: date) }

        center.getPendingNotificationRequests { pending in
            let pendingIDs = Set(pending.map(\.identifier))
            let wantedIDs = Set(wanted.map(\.id))
            let stale = force ? Array(pendingIDs) : pendingIDs.subtracting(wantedIDs).map { $0 }
            self.center.removePendingNotificationRequests(withIdentifiers: stale)
            for item in wanted where force || !pendingIDs.contains(item.id) {
                let content = UNMutableNotificationContent()
                content.title = item.r.title
                content.body = item.date.timeIntervalSince(item.r.due) < 30
                    ? "Due now."
                    : "Overdue since \(Fmt.when(item.r.due)). Still nagging until you mark it done."
                content.categoryIdentifier = self.category
                content.sound = Prefs.sound
                content.userInfo = ["id": item.r.id.uuidString]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.date.timeIntervalSince(now)), repeats: false)
                self.center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }

    /// One summary notification instead of a burst after the Mac wakes.
    func postCatchUp(_ overdue: [Reminder]) {
        let content = UNMutableNotificationContent()
        content.title = overdue.count == 1 ? "1 reminder is overdue" : "\(overdue.count) reminders are overdue"
        content.body = overdue.prefix(4).map(\.title).joined(separator: ", ")
        content.sound = Prefs.sound
        center.add(UNNotificationRequest(identifier: "catch-up", content: content, trigger: nil))
    }

    func clearDelivered(for id: UUID) {
        let prefix = id.uuidString
        center.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            self.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let idString = response.notification.request.content.userInfo["id"] as? String
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            let store = ReminderStore.shared
            if let idString, let id = UUID(uuidString: idString) {
                switch action {
                case "DONE": store.complete(id)
                case "SNOOZE": store.snooze(id, minutes: Prefs.snoozeMinutes)
                case "TOMORROW": store.tomorrow(id)
                default: break
                }
            }
            completionHandler()
        }
    }
}
