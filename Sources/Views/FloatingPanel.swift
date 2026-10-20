import AppKit
import SwiftUI

/// A reusable floating NSPanel that hosts SwiftUI content: the hotkey quick-entry box
/// and the fallback alert used when notifications are denied.
final class FloatingPanel {
    static let entry = FloatingPanel()
    static let alert = FloatingPanel()
    private var panel: NSPanel?

    func show<V: View>(title: String, _ view: V) {
        let p = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 120),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = title
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: view.padding(14).frame(width: 380))
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() { panel?.orderOut(nil) }

    static func showQuickEntry() {
        entry.show(title: "New Reminder", EntryView { FloatingPanel.entry.close() })
    }
}

/// Lists overdue reminders in a floating panel when system notifications are unavailable.
struct FallbackAlertView: View {
    @ObservedObject private var store = ReminderStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.overdue.prefix(6)) { r in
                HStack {
                    VStack(alignment: .leading) {
                        Text(r.title).bold().lineLimit(2)
                        Text("Due \(Fmt.when(r.due))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Done") { store.complete(r.id) }
                    Button("Snooze") { store.snooze(r.id, minutes: Prefs.snoozeMinutes) }
                }
            }
            if store.overdue.isEmpty { Text("All caught up! ✅") }
            Divider()
            DeniedBanner()
        }
        .onChange(of: store.overdue.isEmpty) { _, empty in if empty { FloatingPanel.alert.close() } }
    }
}
