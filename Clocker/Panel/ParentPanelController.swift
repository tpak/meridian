// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit
import EventKit

struct PanelConstants {
    static let modernSliderPointsInADay = 96
}

class ParentPanelController: NSWindowController {
    private var futureSliderObserver: NSKeyValueObservation?
    private var userFontSizeSelectionObserver: NSKeyValueObservation?
    private var futureSliderRangeObserver: NSKeyValueObservation?
    
    private var eventStoreChangedNotification: NSObjectProtocol?
    
    var dateFormatter = DateFormatter()
    
    var futureSliderValue: Int = 0
    
    var parentTimer: Repeater?
    
    var previousPopoverRow: Int = -1
    
    var additionalOptionsPopover: NSPopover?
    
    var datasource: TimezoneDataSource?
    
    private var notePopover: NotesPopover?

    private(set) var sharingHandler: PanelSharingHandler?

    private lazy var oneWindow: OneWindowController? = {
        let preferencesStoryboard = NSStoryboard(name: "Preferences", bundle: nil)
        return preferencesStoryboard.instantiateInitialController() as? OneWindowController
    }()
    
    @IBOutlet var mainTableView: PanelTableView!
    
    @IBOutlet var stackView: NSStackView!
    
    @IBOutlet var scrollViewHeight: NSLayoutConstraint!
    
    @IBOutlet var sharingButton: NSButton!
    
    @IBOutlet var shutdownButton: NSButton!
    
    @IBOutlet var preferencesButton: NSButton!
    
    @IBOutlet var pinButton: NSButton!
    
    @IBOutlet var roundedDateView: NSView!
    
    // Modern Slider
    public var currentCenterIndexPath: Int = -1
    public var closestQuarterTimeRepresentation: Date?
    @IBOutlet var modernSlider: NSCollectionView!
    @IBOutlet var modernSliderLabel: NSTextField!
    @IBOutlet var modernContainerView: ModernSliderContainerView!
    @IBOutlet var goBackwardsButton: NSButton!
    @IBOutlet var goForwardButton: NSButton!
    @IBOutlet var resetModernSliderButton: NSButton!
    
    // Upcoming Events
    @IBOutlet var upcomingEventCollectionView: NSCollectionView!
    @IBOutlet var upcomingEventContainerView: NSView!
    public var upcomingEventsDataSource: UpcomingEventsDataSource?
    
    var defaultPreferences: [Data] {
        return DataStore.shared().timezones()
    }
    
    deinit {
        datasource = nil
        
        if let eventStoreNotif = eventStoreChangedNotification {
            NotificationCenter.default.removeObserver(eventStoreNotif)
        }
        
        [futureSliderObserver, userFontSizeSelectionObserver, futureSliderRangeObserver].forEach {
            $0?.invalidate()
        }
    }
    
    private func setupObservers() {
        futureSliderObserver = UserDefaults.standard.observe(\.displayFutureSlider, options: [.new]) { _, change in
            if let changedValue = change.newValue {
                if changedValue == 0 {
                    if self.modernContainerView != nil {
                        self.modernContainerView.isHidden = false
                    }
                } else if changedValue == 1 {
                    if self.modernContainerView != nil {
                        self.modernContainerView.isHidden = true
                    }
                    
                } else {
                    if self.modernContainerView != nil {
                        self.modernContainerView.isHidden = true
                    }
                }
            }
        }
        
        userFontSizeSelectionObserver = UserDefaults.standard.observe(\.userFontSize, options: [.new]) { _, change in
            if let newFontSize = change.newValue {
                Logger.log(object: ["FontSize": newFontSize], for: "User Font Size Preference")
                self.mainTableView.reloadData()
                self.setScrollViewConstraint()
            }
        }
        
        futureSliderRangeObserver = UserDefaults.standard.observe(\.sliderDayRange, options: [.new]) { _, change in
            if change.newValue != nil {
                self.adjustFutureSliderBasedOnPreferences()
                if self.modernSlider != nil {
                    self.modernSlider.reloadData()
                }
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Setup table
        mainTableView.backgroundColor = NSColor.clear
        mainTableView.selectionHighlightStyle = .none
        mainTableView.enclosingScrollView?.hasVerticalScroller = false
        mainTableView.style = .plain
        
        // Setup images
        let sharedThemer = Themer.shared()
        shutdownButton.image = sharedThemer.shutdownImage()
        preferencesButton.image = sharedThemer.preferenceImage()
        pinButton.image = sharedThemer.pinImage()
        sharingButton.image = sharedThemer.sharingImage()
        sharingButton.alternateImage = sharedThemer.sharingImageAlternate()
        
        // Setup KVO observers for user default changes
        setupObservers()

        // Set the background color of the bottom buttons view to something different to indicate we're not in a release candidate
#if DEBUG
        stackView.arrangedSubviews.last?.layer?.backgroundColor = NSColor(deviceRed: 255.0 / 255.0,
                                                                          green: 150.0 / 255.0,
                                                                          blue: 122.0 / 255.0,
                                                                          alpha: 0.5).cgColor
        stackView.arrangedSubviews.last?.toolTip = "Debug Mode"
#endif
        
        // Setup notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeChanged),
                                               name: Notification.Name.themeDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(systemTimezoneDidChange),
                                               name: NSNotification.Name.NSSystemTimeZoneDidChange,
                                               object: nil)
        
        NotificationCenter.default.addObserver(forName: DataStore.didSyncFromExternalSourceNotification,
                                               object: self,
                                               queue: OperationQueue.main)
        { [weak self] _ in
            if let sSelf = self {
                sSelf.mainTableView.reloadData()
                sSelf.setScrollViewConstraint()
            }
        }
        
        // Setup upcoming events view
        upcomingEventContainerView.setAccessibility("UpcomingEventView")
        determineUpcomingViewVisibility()
        setupUpcomingEventViewCollectionViewIfNeccesary()
        
        // Setup colors based on the curren theme
        themeChanged()
        
        // UI adjustments based on user preferences
        if DataStore.shared().timezones().isEmpty || DataStore.shared().shouldDisplay(.futureSlider) == false {
            
            if modernContainerView != nil {
                modernContainerView.isHidden = true
            }
        } else if let value = DataStore.shared().retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber {
            if value.intValue == 1 {
                if modernContainerView != nil {
                    modernContainerView.isHidden = true
                }
            } else if value.intValue == 0 {
                // Floating Window doesn't support modern slider yet!
                if modernContainerView != nil {
                    modernContainerView.isHidden = false
                }
            }
        }
        
        // Setup sharing handler
        sharingHandler = PanelSharingHandler(store: DataStore.shared(), datasource: datasource)

        // More UI adjustments
        sharingButton.sendAction(on: .leftMouseDown)
        adjustFutureSliderBasedOnPreferences()
        setupModernSliderIfNeccessary()
        if roundedDateView != nil {
            setupRoundedDateView()
        }
    }
    
    private func setupRoundedDateView() {
        roundedDateView.wantsLayer = true
        roundedDateView.layer?.cornerRadius = 12.0
        roundedDateView.layer?.masksToBounds = false
        roundedDateView.layer?.backgroundColor = Themer.shared().textBackgroundColor().cgColor
    }
    
    @objc func systemTimezoneDidChange() {
        OperationQueue.main.addOperation {
            /*
             let locationController = LocationController.sharedController()
             locationController.determineAndRequestLocationAuthorization()*/
            
            self.updateHomeObject(with: TimeZone.autoupdatingCurrent.identifier,
                                  coordinates: nil)
        }
    }
    
    private func updateHomeObject(with customLabel: String, coordinates: CLLocationCoordinate2D?) {
        let timezones = DataStore.shared().timezones()
        
        var timezoneObjects: [TimezoneData] = []
        
        for timezone in timezones {
            if let model = TimezoneData.customObject(from: timezone) {
                timezoneObjects.append(model)
            }
        }
        
        for timezoneObject in timezoneObjects where timezoneObject.isSystemTimezone == true {
            timezoneObject.setLabel(customLabel)
            timezoneObject.formattedAddress = customLabel
            if let latlong = coordinates {
                timezoneObject.longitude = latlong.longitude
                timezoneObject.latitude = latlong.latitude
            }
        }
        
        var datas: [Data] = []
        
        for updatedObject in timezoneObjects {
            guard let dataObject = NSKeyedArchiver.clocker_archive(with: updatedObject) else {
                continue
            }
            datas.append(dataObject)
        }
        
        DataStore.shared().setTimezones(datas)
        
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            appDelegate.setupMenubarTimer()
        }
    }
    
    func determineUpcomingViewVisibility() {
        let showUpcomingEventView = DataStore.shared().shouldDisplay(ViewType.upcomingEventView)
        
        if showUpcomingEventView == false {
            upcomingEventContainerView?.isHidden = true
        } else {
            upcomingEventContainerView?.isHidden = false
            setupUpcomingEventView()
            eventStoreChangedNotification = NotificationCenter.default.addObserver(forName: NSNotification.Name.EKEventStoreChanged, object: self, queue: OperationQueue.main) { _ in
                self.fetchCalendarEvents()
            }
        }
    }
    
    private func adjustFutureSliderBasedOnPreferences() {
        setTimezoneDatasourceSlider(sliderValue: 0)
        updateTableContent()
    }
    
    private func setupUpcomingEventView() {
        let eventCenter = EventCenter.sharedCenter()
        
        if eventCenter.calendarAccessGranted() {
            // Nice. Events will be retrieved when we open the panel
        } else if eventCenter.calendarAccessNotDetermined() {
            upcomingEventCollectionView.reloadData()
        } else {
            removeUpcomingEventView()
        }
        
        themeChanged()
    }
    
    @objc func themeChanged() {
        let sharedThemer = Themer.shared()
        
        if upcomingEventContainerView?.isHidden == false {
            upcomingEventContainerView?.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        shutdownButton.image = sharedThemer.shutdownImage()
        preferencesButton.image = sharedThemer.preferenceImage()
        pinButton.image = sharedThemer.pinImage()
        sharingButton.image = sharedThemer.sharingImage()
        sharingButton.alternateImage = sharedThemer.sharingImageAlternate()
        
        if roundedDateView != nil {
            roundedDateView.layer?.backgroundColor = Themer.shared().textBackgroundColor().cgColor
        }
    }
    
    override func windowDidLoad() {
        super.windowDidLoad()
        additionalOptionsPopover = NSPopover()
    }
    
    func screenHeight() -> CGFloat {
        guard let main = NSScreen.main else { return 100 }
        
        let mouseLocation = NSEvent.mouseLocation
        
        var current = main.frame.height
        
        let activeScreens = NSScreen.screens.filter { current -> Bool in
            NSMouseInRect(mouseLocation, current.frame, false)
        }
        
        if let main = activeScreens.first {
            current = main.frame.height
        }
        
        return current
    }
    
    func invalidateMenubarTimer() {
        parentTimer = nil
    }
    
    private func getAdjustedRowHeight(for object: TimezoneData?, _ currentHeight: CGFloat) -> CGFloat {
        let userFontSize: NSNumber = DataStore.shared().retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber ?? 4
        let shouldShowSunrise = DataStore.shared().shouldDisplay(.sunrise)
        
        var newHeight = currentHeight
        
        if newHeight <= 68.0 {
            newHeight = 60.0
        }
        
        if newHeight >= 68.0 {
            newHeight = userFontSize == 4 ? 68.0 : 68.0
            if let note = object?.note, note.isEmpty == false {
                newHeight += 20
            } else if let obj = object,
                      TimezoneDataOperations(with: obj, store: DataStore.shared()).nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) != nil
            {
                newHeight += 20
            }
        }
        
        if newHeight >= 88.0 {
            // Set it to 90 expicity in case the row height is calculated be higher.
            newHeight = 88.0
            
            if let note = object?.note, note.isEmpty, let obj = object, TimezoneDataOperations(with: obj, store: DataStore.shared()).nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) == nil {
                newHeight -= 20.0
            }
        }
        
        if shouldShowSunrise, object?.selectionType == .city {
            newHeight += 8.0
        }
        
        if object?.isSystemTimezone == true {
            newHeight += 5
        }
        
        newHeight += mainTableView.intercellSpacing.height
        
        return newHeight
    }
    
    func setScrollViewConstraint() {
        var totalHeight: CGFloat = 0.0
        let preferences = defaultPreferences
        
        for cellIndex in 0 ..< preferences.count {
            let currentObject = TimezoneData.customObject(from: preferences[cellIndex])
            let rowRect = mainTableView.rect(ofRow: cellIndex)
            totalHeight += getAdjustedRowHeight(for: currentObject, rowRect.size.height)
        }
        
        // This is for the Add Cell View case
        if preferences.isEmpty {
            scrollViewHeight.constant = 100.0
            return
        }
        
        if let userFontSize = DataStore.shared().retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber {
            if userFontSize == 4 {
                scrollViewHeight.constant = totalHeight + CGFloat(userFontSize.intValue * 2)
            } else {
                scrollViewHeight.constant = totalHeight + CGFloat(userFontSize.intValue * 2) * 3.0
            }
        }
        
        if DataStore.shared().shouldDisplay(ViewType.upcomingEventView) {
            if scrollViewHeight.constant > (screenHeight() - 160) {
                scrollViewHeight.constant = (screenHeight() - 160)
            }
        } else {
            if scrollViewHeight.constant > (screenHeight() - 100) {
                scrollViewHeight.constant = (screenHeight() - 100)
            }
        }
        
        if DataStore.shared().shouldDisplay(.futureSlider) {
            let isModernSliderDisplayed = DataStore.shared().retrieve(key: UserDefaultKeys.displayFutureSliderKey) as? NSNumber ?? 0
            if isModernSliderDisplayed == 0 {
                if scrollViewHeight.constant >= (screenHeight() - 200) {
                    scrollViewHeight.constant = (screenHeight() - 300)
                }
            } else {
                if scrollViewHeight.constant >= (screenHeight() - 200) {
                    scrollViewHeight.constant = (screenHeight() - 200)
                }
            }
        }
    }
    
    func updateDefaultPreferences() {
        PerfLogger.startMarker("Update Default Preferences")
        
        updatePanelColor()
        
        let store = DataStore.shared()
        let defaults = store.timezones()
        let convertedTimezones = defaults.map { data -> TimezoneData in
            TimezoneData.customObject(from: data)!
        }
        
        datasource = TimezoneDataSource(items: convertedTimezones, store: store)
        mainTableView.dataSource = datasource
        mainTableView.delegate = datasource
        mainTableView.panelDelegate = datasource
        sharingHandler?.updateDatasource(datasource)

        updateDatasource(with: convertedTimezones)
        
        PerfLogger.endMarker("Update Default Preferences")
    }
    
    func updateDatasource(with timezones: [TimezoneData]) {
        datasource?.setItems(items: timezones)
        datasource?.setSlider(value: futureSliderValue)
        
        if let userFontSize = DataStore.shared().retrieve(key: UserDefaultKeys.userFontSizePreference) as? NSNumber {
            scrollViewHeight.constant = CGFloat(timezones.count) * (mainTableView.rowHeight + CGFloat(userFontSize.floatValue * 1.5))
            
            setScrollViewConstraint()
            
            mainTableView.reloadData()
        }
    }
    
    func updatePanelColor() {
        window?.alphaValue = 1.0
    }
    
    func setTimezoneDatasourceSlider(sliderValue: Int) {
        futureSliderValue = sliderValue
        datasource?.setSlider(value: sliderValue)
    }
    
    @IBAction func openPreferences(_: NSButton) {
        updatePopoverDisplayState() // Popover's class has access to all timezones. Need to close the popover, so that we don't have two copies of selections
        openPreferencesWindow()
    }
    
    func deleteTimezone(at row: Int) {
        var defaults = defaultPreferences
        
        // Remove from panel
        defaults.remove(at: row)
        DataStore.shared().setTimezones(defaults)
        updateDefaultPreferences()
        
        NotificationCenter.default.post(name: Notification.Name.customLabelChanged,
                                        object: nil)
        
        // Now log!
        Logger.log(object: nil, for: "Deleted Timezone Through Swipe")
    }
    
    private lazy var menubarTitleHandler = MenubarTitleProvider(with: DataStore.shared(), eventStore: EventCenter.sharedCenter())
    
    private static let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: NSFont.monospacedDigitSystemFont(ofSize: 13.0, weight: NSFont.Weight.regular),
                                                                    NSAttributedString.Key.baselineOffset: 0.1]
    
    @objc func updateTime() {
        let store = DataStore.shared()
        
        let menubarCount = store.menubarTimezones()?.count ?? 0
        
        if menubarCount >= 1 || store.shouldDisplay(.showMeetingInMenubar) == true {
            if let status = (NSApplication.shared.delegate as? AppDelegate)?.statusItemForPanel() {
                if store.shouldDisplay(.menubarCompactMode) {
                    status.updateCompactMenubar()
                } else {
                    status.statusItem.button?.attributedTitle = NSAttributedString(string: menubarTitleHandler.titleForMenubar() ?? "",
                                                                                   attributes: ParentPanelController.attributes)
                }
            }
        }
        
        let preferences = store.timezones()
        
        if modernSlider != nil, modernSlider.isHidden == false, modernContainerView.currentlyInFocus == false {
            if currentCenterIndexPath != -1, currentCenterIndexPath != modernSlider.numberOfItems(inSection: 0) / 2 {
                // User is currently scrolling, return!
                return
            }
        }
        
        let hoverRow = mainTableView.hoverRow
        stride(from: 0, to: preferences.count, by: 1).forEach {
            let current = preferences[$0]
            
            if $0 < mainTableView.numberOfRows,
               let cellView = mainTableView.view(atColumn: 0, row: $0, makeIfNecessary: false) as? TimezoneCellView,
               let model = TimezoneData.customObject(from: current)
            {
                if modernContainerView != nil, modernSlider.isHidden == false, modernContainerView.currentlyInFocus {
                    return
                }
                
                let dataOperation = TimezoneDataOperations(with: model, store: DataStore.shared())
                cellView.time.stringValue = dataOperation.time(with: futureSliderValue)
                cellView.sunriseSetTime.stringValue = dataOperation.formattedSunriseTime(with: futureSliderValue)
                cellView.sunriseSetTime.lineBreakMode = .byClipping
                
                if $0 != hoverRow {
                    cellView.relativeDate.stringValue = dataOperation.date(with: futureSliderValue, displayType: .panel)
                }
                
                cellView.currentLocationIndicator.isHidden = !model.isSystemTimezone
                cellView.sunriseImage.image = model.isSunriseOrSunset ? Themer.shared().sunriseImage() : Themer.shared().sunsetImage()
                cellView.sunriseImage.contentTintColor = model.isSunriseOrSunset ? NSColor.systemYellow : NSColor.systemOrange
                if let note = model.note, !note.isEmpty {
                    cellView.noteLabel.stringValue = note
                } else if let value = TimezoneDataOperations(with: model, store: DataStore.shared()).nextDaylightSavingsTransitionIfAvailable(with: futureSliderValue) {
                    cellView.noteLabel.stringValue = value
                } else {
                    cellView.noteLabel.stringValue = UserDefaultKeys.emptyString
                }
                cellView.layout(with: model)
                // TODO: Update modern slider
            }
        }
    }
    
    @discardableResult
    func showNotesPopover(forRow row: Int, relativeTo _: NSRect, andButton target: NSButton!) -> Bool {
        let defaults = DataStore.shared().timezones()
        
        guard let popover = additionalOptionsPopover else {
            Logger.info("Data was unexpectedly nil")
            return false
        }
        
        var correctRow = row
        
        target.image = Themer.shared().extraOptionsHighlightedImage()
        
        popover.animates = true
        
        if notePopover == nil {
            notePopover = NotesPopover(nibName: NSNib.Name.notesPopover, bundle: nil)
            popover.behavior = .applicationDefined
            popover.delegate = self
        }
        
        // Found a case where row number was 8 but we had only 2 timezones
        if correctRow >= defaults.count {
            correctRow = defaults.count - 1
        }
        
        let current = defaults[correctRow]
        
        if let model = TimezoneData.customObject(from: current) {
            notePopover?.setDataSource(data: model)
            notePopover?.setRow(row: correctRow)
            notePopover?.set(timezones: defaults)
            
            popover.contentViewController = notePopover
            notePopover?.set(with: popover)
            return true
        }
        
        return false
    }
    
    func dismissRowActions() {
        mainTableView.rowActionsVisible = false
    }
    
    @objc func updateTableContent() {
        mainTableView.reloadData()
    }
    
    @objc func openPreferencesWindow() {
        oneWindow?.openGeneralPane()
    }
    
    @IBAction func dismissNextEventLabel(_: NSButton) {
        let eventCenter = EventCenter.sharedCenter()
        let now = Date()
        if let events = eventCenter.eventsForDate[NSCalendar.autoupdatingCurrent.startOfDay(for: now)], events.isEmpty == false {
            if let upcomingEvent = eventCenter.nextOccuring(events), let meetingLink = upcomingEvent.meetingURL {
                NSWorkspace.shared.open(meetingLink)
            }
        } else {
            removeUpcomingEventView()
        }
    }
    
    func removeUpcomingEventView() {
        OperationQueue.main.addOperation {
            if self.upcomingEventCollectionView != nil, let eventContainer = self.upcomingEventContainerView {
                if self.stackView.arrangedSubviews.contains(eventContainer), eventContainer.isHidden == false {
                    eventContainer.isHidden = true
                    UserDefaults.standard.set("NO", forKey: UserDefaultKeys.showUpcomingEventView)
                    Logger.log(object: ["Removed": "YES"], for: "Removed Upcoming Event View")
                }
            }
        }
    }
    
    @IBAction func calendarButtonAction(_ sender: NSButton) {
        if sender.title == NSLocalizedString("Click here to start.",
                                             comment: "Button Title for no Calendar access")
        {
            showPermissionsWindow()
        } else {
            retrieveCalendarEvents()
        }
    }
    
    private func showPermissionsWindow() {
        oneWindow?.openPermissionsPane()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func retrieveCalendarEvents() {
            PerfLogger.startMarker("Retrieve Calendar Events")
        
        let eventCenter = EventCenter.sharedCenter()
        
        if eventCenter.calendarAccessGranted() {
            fetchCalendarEvents()
        } else if eventCenter.calendarAccessNotDetermined() {
            /* Wait till we get the thumbs up. */
        } else {
            removeUpcomingEventView()
        }
        
            PerfLogger.endMarker("Retrieve Calendar Events")
    }
    
    @IBAction func shareAction(_ sender: NSButton) {
        let copyAllTimes = sharingHandler?.retrieveAllTimes() ?? ""
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(copyAllTimes, forType: .string)

        self.window?.contentView?.makeToast("Copied to Clipboard".localized())
    }
    
    @IBAction func convertToFloatingWindow(_: NSButton) {
        guard let sharedDelegate = NSApplication.shared.delegate as? AppDelegate
        else {
            Logger.info("Data was unexpectedly nil")
            return
        }
        
        let showAppInForeground = DataStore.shared().shouldDisplay(ViewType.showAppInForeground)
        
        let inverseSelection = showAppInForeground ? NSNumber(value: 0) : NSNumber(value: 1)
        
        UserDefaults.standard.set(inverseSelection, forKey: UserDefaultKeys.showAppInForeground)
        
        close()
        
        if inverseSelection.isEqual(to: NSNumber(value: 1)) {
            sharedDelegate.setupFloatingWindow(false)
        } else {
            sharedDelegate.setupFloatingWindow(true)
            updateDefaultPreferences()
        }
        
        let mode = inverseSelection.isEqual(to: NSNumber(value: 1)) ? "Floating Mode" : "Menubar Mode"
        
        Logger.log(object: ["displayMode": mode], for: "Clocker Mode")
    }
    
    func showUpcomingEventView() {
        OperationQueue.main.addOperation {
            if let upcomingView = self.upcomingEventContainerView, upcomingView.isHidden {
                self.upcomingEventContainerView?.isHidden = false
                UserDefaults.standard.set("YES", forKey: UserDefaultKeys.showUpcomingEventView)
                Logger.log(object: ["Shown": "YES"], for: "Added Upcoming Event View")
                self.themeChanged()
            }
        }
    }
    
    private func fetchCalendarEvents() {
            PerfLogger.startMarker("Fetch Calendar Events")
        
        let eventCenter = EventCenter.sharedCenter()
        let now = Date()
        
        if let events = eventCenter.eventsForDate[NSCalendar.autoupdatingCurrent.startOfDay(for: now)], events.isEmpty == false {
            OperationQueue.main.addOperation {
                if self.upcomingEventCollectionView != nil,
                   let upcomingEvents = eventCenter.upcomingEventsForDay(events)
                {
                    self.upcomingEventsDataSource?.updateEventsDataSource(upcomingEvents)
                    self.upcomingEventCollectionView.reloadData()
                    return
                }
                
                    PerfLogger.endMarker("Fetch Calendar Events")
            }
        } else {
            if upcomingEventCollectionView != nil {
                upcomingEventsDataSource?.updateEventsDataSource([])
                upcomingEventCollectionView.reloadData()
                return
            }
                PerfLogger.endMarker("Fetch Calendar Events")
        }
    }
    
    // If the popover is displayed, close it
    // Called when preferences are going to be displayed!
    func updatePopoverDisplayState() {
        if notePopover != nil, let isShown = notePopover?.popover?.isShown, isShown {
            notePopover?.popover?.close()
        }
        additionalOptionsPopover = nil
    }
    
    // MARK: Date Picker + Slider
    
    
    func minutes(from date: Date, other: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: other).minute ?? 0
    }
    
    
    @objc dynamic func terminateClocker() {
        NSApplication.shared.terminate(nil)
    }
    
    @objc func reportIssue() {
        guard let url = URL(string: "https://github.com/nickhumbir/clocker/issues") else { return }
        NSWorkspace.shared.open(url)

        if let countryCode = Locale.autoupdatingCurrent.region?.identifier {
            let custom: [String: Any] = ["Country": countryCode]
            Logger.log(object: custom, for: "Report Issue Opened")
        }
    }
    
    @objc func openCrowdin() {
        guard let localizationURL = URL(string: AboutUsConstants.CrowdInLocalizationLink),
              let languageCode = Locale.preferredLanguages.first else { return }
        
        NSWorkspace.shared.open(localizationURL)
        
        // Log this
        let custom: [String: Any] = ["Language": languageCode]
        Logger.log(object: custom, for: "Opened Localization Link")
    }
    
    @objc func rate() {
        guard let sourceURL = URL(string: AboutUsConstants.AppStoreLink) else { return }
        
        NSWorkspace.shared.open(sourceURL)
    }
    
    @objc func openFAQs() {
        guard let sourceURL = URL(string: AboutUsConstants.FAQsLink) else { return }
        
        NSWorkspace.shared.open(sourceURL)
    }
    
    @IBAction func showMoreOptions(_ sender: NSButton) {
        guard let event = NSApp.currentEvent else { return }
        let menu = PanelContextMenu.build(target: self)
        NSMenu.popUpContextMenu(menu,
                                with: event,
                                for: sender)
    }
}

extension ParentPanelController: NSPopoverDelegate {
    func popoverShouldClose(_: NSPopover) -> Bool {
        return false
    }
}


