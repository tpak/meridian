// Copyright © 2015 Abhishek Banthia

import Cocoa
import Combine
import CoreLoggerKit

class FloatingWindowController: ParentPanelController {
    private var repeater: Repeater?

    static var sharedWindow = FloatingWindowController(windowNibName: NSNib.Name.floatingWindowIdentifier)

    override func windowDidLoad() {
        super.windowDidLoad()
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
    }

    class func shared() -> FloatingWindowController {
        return sharedWindow
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        setup()
        windowFrameAutosaveName = NSWindow.FrameAutosaveName("FloatingWindowAutoSave")
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US")

        NotificationCenter.default.publisher(for: .themeDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.themeChanges() }
            .store(in: &cancellables)

        updateTheme()

        updateDefaultPreferences()

        mainTableView.registerForDraggedTypes([.dragSession])

        mainTableView.setAccessibility("FloatingTableView")
    }

    override func updatePanelColor() {
        super.updatePanelColor()
        updateTheme()
    }

    override func showNotesPopover(forRow row: Int, relativeTo positioningRect: NSRect, andButton target: NSButton!) -> Bool {
        guard let popover = additionalOptionsPopover else {
            return false
        }

        target.image = Themer.shared().extraOptionsHighlightedImage()

        if popover.isShown, row == previousPopoverRow {
            popover.close()
            target.image = Themer.shared().extraOptionsImage()
            previousPopoverRow = -1
            return false
        }

        previousPopoverRow = row

        super.showNotesPopover(forRow: row, relativeTo: positioningRect, andButton: target)

        guard let contentView = window?.contentView else {
            Logger.info("Window was unexpectedly nil")
            return false
        }

        popover.show(relativeTo: positioningRect,
                     of: contentView,
                     preferredEdge: .minX)
        return true
    }

    private func updateTheme() {
        let shared = Themer.shared()

        if let panel = window {
            panel.acceptsMouseMovedEvents = true
            panel.level = .popUpMenu
            panel.isOpaque = false
        }

        shutdownButton.image = shared.shutdownImage()
        preferencesButton.image = shared.preferenceImage()
        pinButton.image = shared.pinImage()
        sharingButton.image = shared.sharingImage()
        sharingButton.alternateImage = shared.sharingImageAlternate()
        mainTableView.backgroundColor = shared.mainBackgroundColor()
        window?.backgroundColor = shared.mainBackgroundColor()
    }

    @objc override func updateDefaultPreferences() {
        super.updateDefaultPreferences()

        updateTime()

        mainTableView.backgroundColor = Themer.shared().mainBackgroundColor()
    }

    @objc override func updateTime() {
        retrieveCalendarEvents()
        super.updateTime()
    }

    @objc func themeChanges() {
        updateTheme()
        super.updatePanelColor()
        mainTableView.reloadData()
    }

    private func setup() {
        window?.contentView?.wantsLayer = true
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.contentView?.layer?.cornerRadius = 20
        window?.contentView?.layer?.masksToBounds = true
        window?.isOpaque = false
        window?.backgroundColor = NSColor.clear
        window?.collectionBehavior = .canJoinAllSpaces
    }

    func startWindowTimer() {
        repeater = Repeater(interval: .seconds(1), mode: .infinite) { _ in
            OperationQueue.main.addOperation {
                self.updateTime()
            }
        }
        repeater?.start()

        super.dismissRowActions()
    }

    override func showWindow(_: Any?) {
        super.showWindow(nil)
        determineUpcomingViewVisibility()
    }
}

extension NSView {
    func setAccessibility(_ identifier: String) {
        setAccessibilityEnabled(true)
        setAccessibilityIdentifier(identifier)
    }
}

extension FloatingWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        setTimezoneDatasourceSlider(sliderValue: 0)

        if let timer = repeater {
            timer.pause()
            repeater = nil
        }
    }
}
