import ServiceManagement
import SwiftUI

/// Preferences: nag and snooze defaults, sound, launch at login, global hotkey and support link.
struct SettingsView: View {
    @AppStorage(Prefs.nagKey) private var nagMinutes = 5
    @AppStorage(Prefs.maxRepeatsKey) private var maxRepeats = 10
    @AppStorage(Prefs.snoozeKey) private var snoozeMinutes = 10
    @AppStorage(Prefs.soundKey) private var soundName = "Default"
    @AppStorage(Prefs.hotkeyEnabledKey) private var hotkeyEnabled = true
    @AppStorage(Prefs.hotkeyLetterKey) private var hotkeyLetter = "R"
    @AppStorage(Prefs.hotkeyModsKey) private var hotkeyMods = Prefs.control | Prefs.option
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @ObservedObject private var notifications = NotificationService.shared

    var body: some View {
        Form {
            Section("Nagging") {
                Picker("Default nag interval", selection: $nagMinutes) {
                    ForEach(Prefs.nagChoices, id: \.self) { Text("\($0) min").tag($0) }
                }
                Picker("Maximum repeats", selection: $maxRepeats) {
                    ForEach([3, 5, 10, 20, 50], id: \.self) { Text("\($0)").tag($0) }
                    Text("Unlimited").tag(0)
                }
                Picker("Default snooze length", selection: $snoozeMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                HStack {
                    Picker("Sound", selection: $soundName) {
                        Text("Default").tag("Default")
                        Text("None").tag("None")
                        ForEach(Prefs.systemSounds, id: \.self) { Text($0).tag($0) }
                    }
                    Button { NSSound(named: NSSound.Name(soundName))?.play() } label: { Image(systemName: "play.fill") }
                        .disabled(soundName == "None" || soundName == "Default")
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Global hotkey for new reminder", isOn: $hotkeyEnabled)
                if hotkeyEnabled {
                    HStack {
                        modifierToggle("⌃", Prefs.control)
                        modifierToggle("⌥", Prefs.option)
                        modifierToggle("⇧", Prefs.shift)
                        modifierToggle("⌘", Prefs.command)
                        Picker("", selection: $hotkeyLetter) {
                            ForEach(HotKeyManager.letters, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 60)
                        Spacer()
                        Text(HotKeyManager.describe(mods: hotkeyMods, letter: hotkeyLetter)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Notifications") {
                if notifications.denied { DeniedBanner() } else { Text("Notifications are enabled.").foregroundStyle(.secondary) }
            }
            Section {
                Button("Support / Donate ❤️") {
                    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
        .onChange(of: hotkeyEnabled) { HotKeyManager.shared.reload() }
        .onChange(of: hotkeyLetter) { HotKeyManager.shared.reload() }
        .onChange(of: hotkeyMods) { HotKeyManager.shared.reload() }
        .onChange(of: snoozeMinutes) { NotificationService.shared.registerCategory() }
        .onChange(of: maxRepeats) { ReminderStore.shared.tick() }
        .onChange(of: soundName) { NotificationService.shared.reschedule(ReminderStore.shared.reminders, force: true) }
        .onAppear { notifications.refreshStatus() }
    }

    private func modifierToggle(_ symbol: String, _ flag: Int) -> some View {
        Toggle(symbol, isOn: Binding(
            get: { hotkeyMods & flag != 0 },
            set: { hotkeyMods = $0 ? hotkeyMods | flag : hotkeyMods & ~flag }))
            .toggleStyle(.button)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}
