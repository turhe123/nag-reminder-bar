import Foundation
import UserNotifications

/// UserDefaults keys, defaults and typed accessors shared by `@AppStorage` views and non-UI services.
enum Prefs {
    static let nagKey = "defaultNagMinutes"
    static let maxRepeatsKey = "maxRepeats"
    static let snoozeKey = "snoozeMinutes"
    static let soundKey = "soundName"
    static let hotkeyEnabledKey = "hotkeyEnabled"
    static let hotkeyLetterKey = "hotkeyLetter"
    static let hotkeyModsKey = "hotkeyModifiers"

    /// Modifier bit flags stored in `hotkeyModsKey`.
    static let control = 1, option = 2, command = 4, shift = 8

    static let nagChoices = [1, 5, 10, 15, 30, 60]
    static let donateURL = URL(string: "https://ko-fi.com/leodavidai")
    static let notificationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.turhe123.nagreminderbar")

    static func register() {
        UserDefaults.standard.register(defaults: [
            nagKey: 5, maxRepeatsKey: 10, snoozeKey: 10, soundKey: "Default",
            hotkeyEnabledKey: true, hotkeyLetterKey: "R", hotkeyModsKey: control | option,
        ])
    }

    private static var d: UserDefaults { .standard }
    static var nagMinutes: Int { max(1, d.integer(forKey: nagKey)) }
    static var maxRepeats: Int { max(0, d.integer(forKey: maxRepeatsKey)) }
    static var snoozeMinutes: Int { max(1, d.integer(forKey: snoozeKey)) }

    static var sound: UNNotificationSound? {
        switch d.string(forKey: soundKey) ?? "Default" {
        case "None": return nil
        case "Default": return .default
        case let name: return UNNotificationSound(named: UNNotificationSoundName(name + ".aiff"))
        }
    }

    /// Names of the built-in alert sounds in /System/Library/Sounds.
    static let systemSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.filter { $0.hasSuffix(".aiff") }.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()
}
