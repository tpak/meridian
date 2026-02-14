// Copyright © 2015 Abhishek Banthia

import Cocoa
import ServiceManagement

struct StartupManager {
    func toggleLogin(_ shouldStartAtLogin: Bool) {
        if !SMLoginItemSetEnabled("com.tpak.MeridianHelper" as CFString, shouldStartAtLogin) {
            Logger.log(object: ["Successful": "NO"], for: "Start Meridian Login")
            addMeridianToLoginItemsManually()
        } else {
            Logger.log(object: ["Successful": "YES"], for: "Start Meridian Login")
        }
    }

    private func addMeridianToLoginItemsManually() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Meridian is unable to set to start at login. 😅"
        alert.informativeText = "You can manually set it to start at startup by adding Meridian to your login items."
        alert.addButton(withTitle: "Add Manually")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        if response.rawValue == 1000 {
            OperationQueue.main.addOperation {
                let prefPane = "/System/Library/PreferencePanes/Accounts.prefPane"
                NSWorkspace.shared.openFile(prefPane)
            }
        }
    }
}
