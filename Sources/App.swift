import AppKit
import SwiftUI

/// App entry point: the menu bar extra (with overdue badge) and the Settings window.
@main
struct NagReminderBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ReminderStore.shared

    init() { Prefs.register() }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
        } label: {
            let count = store.overdue.count
            Image(systemName: count > 0 ? "bell.badge.fill" : "bell")
            if count > 0 { Text("\(count)") }
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView() }
    }
}

/// Wires up notifications, the global hotkey and sleep/wake handling at launch.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.register()
        NotificationService.shared.setup()
        HotKeyManager.shared.action = { FloatingPanel.showQuickEntry() }
        HotKeyManager.shared.reload()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            NotificationService.shared.suspended = true
            NotificationService.shared.reschedule([])
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            NotificationService.shared.suspended = false
            ReminderStore.shared.handleWake()
        }
    }
}
