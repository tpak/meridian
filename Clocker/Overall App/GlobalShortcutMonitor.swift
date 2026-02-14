// Copyright © 2015 Abhishek Banthia

import Cocoa
import Carbon.HIToolbox

final class GlobalShortcutMonitor {
    static let shared = GlobalShortcutMonitor()

    struct KeyCombo: Codable, Equatable {
        let keyCode: UInt16
        let modifierFlags: UInt  // NSEvent.ModifierFlags.rawValue

        var displayString: String {
            guard keyCode > 0 else {
                return "Click to Record Shortcut"
            }

            var modifierString = ""
            let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)

            if flags.contains(.control) {
                modifierString += "⌃"
            }
            if flags.contains(.option) {
                modifierString += "⌥"
            }
            if flags.contains(.shift) {
                modifierString += "⇧"
            }
            if flags.contains(.command) {
                modifierString += "⌘"
            }

            let keyString = keyCodeToString(keyCode)
            return modifierString + keyString
        }

        private func keyCodeToString(_ keyCode: UInt16) -> String {
            // Map common key codes to readable strings
            switch keyCode {
            case 0x00: return "A"
            case 0x01: return "S"
            case 0x02: return "D"
            case 0x03: return "F"
            case 0x04: return "H"
            case 0x05: return "G"
            case 0x06: return "Z"
            case 0x07: return "X"
            case 0x08: return "C"
            case 0x09: return "V"
            case 0x0B: return "B"
            case 0x0C: return "Q"
            case 0x0D: return "W"
            case 0x0E: return "E"
            case 0x0F: return "R"
            case 0x10: return "Y"
            case 0x11: return "T"
            case 0x12: return "1"
            case 0x13: return "2"
            case 0x14: return "3"
            case 0x15: return "4"
            case 0x16: return "6"
            case 0x17: return "5"
            case 0x18: return "="
            case 0x19: return "9"
            case 0x1A: return "7"
            case 0x1B: return "-"
            case 0x1C: return "8"
            case 0x1D: return "0"
            case 0x1E: return "]"
            case 0x1F: return "O"
            case 0x20: return "U"
            case 0x21: return "["
            case 0x22: return "I"
            case 0x23: return "P"
            case 0x25: return "L"
            case 0x26: return "J"
            case 0x27: return "'"
            case 0x28: return "K"
            case 0x29: return ";"
            case 0x2A: return "\\"
            case 0x2B: return ","
            case 0x2C: return "/"
            case 0x2D: return "N"
            case 0x2E: return "M"
            case 0x2F: return "."
            case 0x24: return "↩"  // Return
            case 0x30: return "⇥"  // Tab
            case 0x31: return "Space"
            case 0x33: return "⌫"  // Delete
            case 0x35: return "⎋"  // Escape
            case 0x7B: return "←"
            case 0x7C: return "→"
            case 0x7D: return "↓"
            case 0x7E: return "↑"
            case 0x72: return "Help"
            case 0x73: return "Home"
            case 0x74: return "⇞"  // Page Up
            case 0x75: return "⌦"  // Forward Delete
            case 0x77: return "End"
            case 0x79: return "⇟"  // Page Down
            case 0x7A: return "F1"
            case 0x78: return "F2"
            case 0x63: return "F3"
            case 0x76: return "F4"
            case 0x60: return "F5"
            case 0x61: return "F6"
            case 0x62: return "F7"
            case 0x64: return "F8"
            case 0x65: return "F9"
            case 0x6D: return "F10"
            case 0x67: return "F11"
            case 0x6F: return "F12"
            default: return ""
            }
        }
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    var action: (() -> Void)?

    private let userDefaultsKey = "globalPing"
    private let legacyUserDefaultsKey = "values.globalPing"

    var currentShortcut: KeyCombo? {
        get {
            // First try to read from new format
            if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
               let keyCombo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
                return keyCombo
            }

            // Try legacy format migration
            if let legacyDict = UserDefaults.standard.object(forKey: legacyUserDefaultsKey) as? [String: Any],
               let keyCode = legacyDict["keyCode"] as? NSNumber,
               let modifierFlags = legacyDict["modifierFlags"] as? NSNumber {
                let keyCombo = KeyCombo(keyCode: keyCode.uint16Value, modifierFlags: modifierFlags.uintValue)

                // Migrate to new format
                if let data = try? JSONEncoder().encode(keyCombo) {
                    UserDefaults.standard.set(data, forKey: userDefaultsKey)
                }

                return keyCombo
            }

            return nil
        }
        set {
            unregister()

            if let keyCombo = newValue {
                if let data = try? JSONEncoder().encode(keyCombo) {
                    UserDefaults.standard.set(data, forKey: userDefaultsKey)
                }
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }

            register()
        }
    }

    private init() {}

    func register() {
        unregister()

        guard let shortcut = currentShortcut, shortcut.keyCode > 0 else {
            return
        }

        let targetKeyCode = shortcut.keyCode
        let targetFlags = NSEvent.ModifierFlags(rawValue: shortcut.modifierFlags)

        // Global monitor (when app is not active)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetFlags {
                self?.action?()
            }
        }

        // Local monitor (when app IS active)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == targetKeyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetFlags {
                self?.action?()
                return nil  // Consume the event
            }
            return event
        }
    }

    func unregister() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }

        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}
