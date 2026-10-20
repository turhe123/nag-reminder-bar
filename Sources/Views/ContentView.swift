import SwiftUI

/// The menu bar window: entry field, permission banner, grouped reminder list, history and footer.
struct ContentView: View {
    @ObservedObject private var store = ReminderStore.shared
    @ObservedObject private var notifications = NotificationService.shared
    @State private var editing: Reminder?
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let editing {
                EditView(reminder: editing) { self.editing = nil }
            } else {
                EntryView()
                if notifications.denied { DeniedBanner() }
                if store.active.isEmpty { emptyState } else { list }
                if !store.history.isEmpty { historySection }
            }
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 360)
        .onAppear { store.tick() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                section("Overdue", store.overdue, color: .red)
                section("Today", store.today, color: .primary)
                section("Later", store.later, color: .secondary)
            }
        }
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func section(_ name: String, _ items: [Reminder], color: Color) -> some View {
        if !items.isEmpty {
            Text(name.uppercased()).font(.caption2.bold()).foregroundStyle(color).padding(.top, 4)
            ForEach(items) { r in
                ReminderRow(reminder: r, overdue: name == "Overdue") { editing = r }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing is due. Enjoy the quiet! 🌤").font(.callout)
            Text("Try typing:").font(.caption).foregroundStyle(.secondary)
            ForEach(["call the dentist in 20 minutes", "submit report tomorrow 9am", "stretch every 2 hours"], id: \.self) {
                Text("• \($0)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var historySection: some View {
        DisclosureGroup("Done (\(store.history.count))", isExpanded: $showHistory) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(store.history.prefix(8)) { r in
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(r.title).strikethrough().foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button { store.delete(r.id) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }
                    .font(.caption)
                }
                Button("Clear history") { store.clearHistory() }.font(.caption).buttonStyle(.link)
            }
        }
        .font(.caption)
    }

    private var footer: some View {
        HStack {
            SettingsLink { Text("Settings…") }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Spacer()
            Button("Support / Donate ❤️") {
                if let url = Prefs.donateURL { NSWorkspace.shared.open(url) }
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .font(.caption)
    }
}

/// The plain-language text field with a live "Will remind you…" preview and a date-picker fallback.
struct EntryView: View {
    var onAdd: () -> Void = {}
    @ObservedObject private var store = ReminderStore.shared
    @State private var text = ""
    @State private var pickedDate = Date().addingTimeInterval(3600)
    @FocusState private var focused: Bool

    private var parsed: ReminderParser.Result { ReminderParser.parse(text) }
    private var hasText: Bool { !text.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("e.g. call the dentist in 20 minutes", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($focused)
                .onSubmit { if parsed.due != nil { add() } }
            if hasText {
                if let due = parsed.due {
                    Label(preview(due), systemImage: "bell").font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("When?").font(.caption).foregroundStyle(.orange)
                        DatePicker("", selection: $pickedDate, in: Date()...).labelsHidden()
                        Button("Add", action: add)
                    }
                }
            }
        }
        .onAppear { focused = true }
    }

    private func preview(_ due: Date) -> String {
        var s = "Will remind you \(Fmt.when(due))"
        if let r = parsed.repeatInterval { s += ", then every \(Fmt.duration(r))" }
        return s
    }

    private func add() {
        let p = parsed
        guard hasText else { return }
        store.add(title: p.title.isEmpty ? "Reminder" : p.title, due: p.due ?? pickedDate, repeatInterval: p.repeatInterval)
        text = ""
        pickedDate = Date().addingTimeInterval(3600)
        onAdd()
    }
}

/// One reminder line with a check button, due time and the Edit / Snooze / Nag interval / Delete menu.
struct ReminderRow: View {
    let reminder: Reminder
    let overdue: Bool
    let onEdit: () -> Void
    @ObservedObject private var store = ReminderStore.shared

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Button { store.complete(reminder.id) } label: {
                Image(systemName: "circle").foregroundStyle(overdue ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .help("Mark done")
            VStack(alignment: .leading, spacing: 1) {
                Text(reminder.title).lineLimit(2)
                HStack(spacing: 4) {
                    Text(Fmt.when(reminder.due))
                    if reminder.repeatInterval != nil { Image(systemName: "repeat") }
                    Text("· nags every \(reminder.nagMinutes)m")
                }
                .font(.caption)
                .foregroundStyle(overdue ? .red : .secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit…", action: onEdit)
            Menu("Snooze") {
                ForEach([5, 10, 15, 30, 60], id: \.self) { m in
                    Button("\(m) minutes") { store.snooze(reminder.id, minutes: m) }
                }
                Button("Tomorrow") { store.tomorrow(reminder.id) }
            }
            Menu("Change nag interval") {
                ForEach(Prefs.nagChoices, id: \.self) { m in
                    Button { store.setNag(reminder.id, minutes: m) } label: {
                        Text(m == reminder.nagMinutes ? "✓ \(m) min" : "\(m) min")
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { store.delete(reminder.id) }
        }
    }
}

/// Inline editor for a reminder's title, due date, repeat and nag interval.
struct EditView: View {
    @State var reminder: Reminder
    let onClose: () -> Void
    private let repeats: [(String, TimeInterval)] = [
        ("Never", 0), ("Every 30 minutes", 1800), ("Every hour", 3600), ("Every 2 hours", 7200),
        ("Every day", 86_400), ("Every week", 604_800),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit reminder").font(.headline)
            TextField("Title", text: $reminder.title).textFieldStyle(.roundedBorder)
            DatePicker("Due", selection: $reminder.due)
            Picker("Nag every", selection: $reminder.nagMinutes) {
                ForEach(Prefs.nagChoices, id: \.self) { Text("\($0) min").tag($0) }
            }
            Picker("Repeat", selection: Binding(
                get: { reminder.repeatInterval ?? 0 },
                set: { reminder.repeatInterval = $0 > 0 ? $0 : nil })) {
                ForEach(repeats, id: \.1) { Text($0.0).tag($0.1) }
                if let r = reminder.repeatInterval, !repeats.contains(where: { $0.1 == r }) {
                    Text("Every \(Fmt.duration(r))").tag(r)
                }
            }
            HStack {
                Button("Delete", role: .destructive) { ReminderStore.shared.delete(reminder.id); onClose() }
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Save") {
                    if reminder.title.trimmingCharacters(in: .whitespaces).isEmpty { reminder.title = "Reminder" }
                    ReminderStore.shared.update(reminder)
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Inline warning shown when notifications are turned off, with a shortcut to System Settings.
struct DeniedBanner: View {
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off, so nags will appear as a floating panel instead.").font(.caption)
                Button("Open Notification Settings") {
                    if let url = Prefs.notificationSettingsURL { NSWorkspace.shared.open(url) }
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
