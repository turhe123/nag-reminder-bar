import Carbon
import Foundation

/// Registers one system-wide hotkey via Carbon's RegisterEventHotKey (needs no Accessibility permission).
final class HotKeyManager {
    static let shared = HotKeyManager()
    var action: () -> Void = {}

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    static let letters = (65...90).compactMap { UnicodeScalar($0).map { String(Character($0)) } }
    private static let keyCodes: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
        "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
    ]

    /// Re-reads the hotkey preferences and (re)registers the shortcut.
    func reload() {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKeyManager.shared.action() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil

        let d = UserDefaults.standard
        guard d.bool(forKey: Prefs.hotkeyEnabledKey),
              let code = Self.keyCodes[d.string(forKey: Prefs.hotkeyLetterKey) ?? "R"] else { return }
        let mods = d.integer(forKey: Prefs.hotkeyModsKey)
        guard mods != 0 else { return }
        var carbon = 0
        if mods & Prefs.control != 0 { carbon |= controlKey }
        if mods & Prefs.option != 0 { carbon |= optionKey }
        if mods & Prefs.command != 0 { carbon |= cmdKey }
        if mods & Prefs.shift != 0 { carbon |= shiftKey }
        let id = EventHotKeyID(signature: OSType(0x4E41_4752), id: 1) // "NAGR"
        let status = RegisterEventHotKey(UInt32(code), UInt32(carbon), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("NagReminderBar: hotkey registration failed (\(status))") }
    }

    static func describe(mods: Int, letter: String) -> String {
        var s = ""
        if mods & Prefs.control != 0 { s += "⌃" }
        if mods & Prefs.option != 0 { s += "⌥" }
        if mods & Prefs.shift != 0 { s += "⇧" }
        if mods & Prefs.command != 0 { s += "⌘" }
        return s + letter
    }
}
