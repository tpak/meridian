// Copyright © 2015 Abhishek Banthia

import Cocoa
import Combine

class CenteredTabViewController: NSTabViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup localized tab labels
        tabViewItems.forEach { item in
            if let identifier = item.identifier as? String {
                item.label = NSLocalizedString(identifier, comment: "Tab View Item Label for \(identifier)")
            }
        }
    }
}

class OneWindowController: NSWindowController {
    private var cancellables = Set<AnyCancellable>()

    override func windowDidLoad() {
        super.windowDidLoad()
        setup()

        NotificationCenter.default.publisher(for: .themeDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 1
                    context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
                    self?.window?.animator().backgroundColor = Themer.shared().mainBackgroundColor()
                }

                self?.setupToolbarImages()
            }
            .store(in: &cancellables)
    }

    private func setup() {
        setupWindow()
        setupToolbarImages()
    }

    private func setupWindow() {
        window?.titlebarAppearsTransparent = true
        window?.backgroundColor = Themer.shared().mainBackgroundColor()
        window?.identifier = NSUserInterfaceItemIdentifier("Preferences")
    }

    private func setupToolbarImages() {
        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        let themer = Themer.shared()
        var identifierTOImageMapping: [String: NSImage] = ["Appearance Tab": themer.appearanceTabImage(),
                                                           "Calendar Tab": themer.calendarTabImage(),
                                                           "Permissions Tab": themer.privacyTabImage()]

        if let prefsTabImage = themer.generalTabImage() {
            identifierTOImageMapping["Preferences Tab"] = prefsTabImage
        }

        if let aboutTabImage = themer.aboutTabImage() {
            identifierTOImageMapping["About Tab"] = aboutTabImage
        }

        tabViewController.tabViewItems.forEach { tabViewItem in
            let identity = (tabViewItem.identifier as? String) ?? ""
            if identifierTOImageMapping[identity] != nil {
                tabViewItem.image = identifierTOImageMapping[identity]
            }
        }
    }

    // MARK: Public

    func openPermissionsPane() {
        openPreferenceTab(at: 3)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Action mapped to the + button in the PanelController. We should always open the General Pane when the + button is clicked.
    func openGeneralPane() {
        openPreferenceTab(at: 0)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openPreferenceTab(at index: Int) {
        guard let window = window else {
            return
        }

        if !window.isMainWindow || !window.isVisible {
            showWindow(nil)
        }

        guard let tabViewController = contentViewController as? CenteredTabViewController else {
            return
        }

        tabViewController.selectedTabViewItemIndex = index
    }
}
