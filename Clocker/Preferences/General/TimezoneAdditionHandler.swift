// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

protocol TimezoneAdditionHost: AnyObject {
    var searchField: NSSearchField! { get }
    var placeholderLabel: NSTextField! { get }
    var availableTimezoneTableView: NSTableView! { get }
    var timezonePanel: Panelr! { get }
    var timezoneTableView: NSTableView! { get }
    var messageLabel: NSTextField! { get }
    var addTimezoneButton: NSButton! { get }
    var progressIndicator: NSProgressIndicator! { get }
    var addButton: NSButton! { get }
    var searchResultsDataSource: SearchDataSource! { get }

    func refreshTimezoneTableView(_ shouldSelectNewlyInsertedTimezone: Bool)
    func refreshMainTable()
}

@MainActor
class TimezoneAdditionHandler: NSObject {
    private weak var host: TimezoneAdditionHost?

    private var searchTask: Task<Void, Never>?

    private var isActivityInProgress = false {
        didSet {
            guard let host = host else { return }
            isActivityInProgress ? host.progressIndicator.startAnimation(nil) : host.progressIndicator.stopAnimation(nil)
            host.availableTimezoneTableView.isEnabled = !isActivityInProgress
            host.addButton.isEnabled = !isActivityInProgress
        }
    }

    private lazy var geocodingKey: String = {
        guard let apiKey = Bundle.main.infoDictionary?["GeocodingKey"] as? String,
              !apiKey.isEmpty
        else {
            Logger.info("Unable to find the API key")
            return ""
        }
        return apiKey
    }()

    init(host: TimezoneAdditionHost) {
        self.host = host
    }

    // MARK: - Search

    @objc func search() {
        guard let host = host else { return }
        let searchString = host.searchField.stringValue

        if searchString.isEmpty {
            searchTask?.cancel()
            resetSearchView()
            return
        }

        searchTask?.cancel()

        if host.availableTimezoneTableView.isHidden {
            host.availableTimezoneTableView.isHidden = false
        }

        host.placeholderLabel.isHidden = false
        isActivityInProgress = true
        host.placeholderLabel.placeholderString = "Searching for \(searchString)"

        Logger.info(host.placeholderLabel.placeholderString ?? "")

        guard let searchURL = generateSearchURL() else {
            presentError("Unable to construct search URL.")
            return
        }

        searchTask = Task { @MainActor in
            do {
                let data = try await NetworkManager.data(from: searchURL)

                guard let searchResults: SearchResult = data.decode() else {
                    Logger.info("Data was unexpectedly nil")
                    return
                }

                if searchResults.status == ResultStatus.zeroResults {
                    Logger.info("Zero Results returned")
                    findLocalSearchResultsForTimezones()
                    let noResults = host.searchResultsDataSource.timezoneFilteredArray.isEmpty
                    host.placeholderLabel.placeholderString = noResults
                        ? "No results! 😔 Try entering the exact name." : UserDefaultKeys.emptyString
                    reloadSearchResults()
                    isActivityInProgress = false
                    return
                } else if searchResults.status == ResultStatus.requestDenied && searchResults.results.isEmpty {
                    Logger.info("Request denied!")
                    findLocalSearchResultsForTimezones()
                    let noResults = host.searchResultsDataSource.timezoneFilteredArray.isEmpty
                    host.placeholderLabel.placeholderString = noResults
                        ? "Update Clocker to get a faster experience 😃" : UserDefaultKeys.emptyString
                    reloadSearchResults()
                    isActivityInProgress = false
                    return
                }

                appendResultsToFilteredArray(searchResults.results)
                findLocalSearchResultsForTimezones()
                prepareUIForPresentingResults()
            } catch {
                findLocalSearchResultsForTimezones()
                if host.searchResultsDataSource.timezoneFilteredArray.isEmpty {
                    presentError(error.localizedDescription)
                    return
                }
                prepareUIForPresentingResults()
            }
        }
    }

    private func findLocalSearchResultsForTimezones() {
        guard let host = host else { return }
        TimezoneSearchService.searchLocalTimezones(host.searchField.stringValue, in: host.searchResultsDataSource)
    }

    private func generateSearchURL() -> URL? {
        guard let host = host else { return nil }
        let userPreferredLanguage = Locale.preferredLanguages.first ?? "en-US"

        var searchString = host.searchField.stringValue
        let words = searchString.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        searchString = words.joined(separator: UserDefaultKeys.emptyString)

        return NetworkManager.geocodeURL(for: searchString, key: geocodingKey, language: userPreferredLanguage)
    }

    private func presentError(_ errorMessage: String) {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = errorMessage == PreferencesConstants.offlineErrorMessage ? PreferencesConstants.noInternetConnectivityError : PreferencesConstants.tryAgainMessage
        isActivityInProgress = false
    }

    private func appendResultsToFilteredArray(_ results: [SearchResult.Result]) {
        guard let host = host else { return }
        TimezoneSearchService.parseAndAddGeocodingResults(results, to: host.searchResultsDataSource)
    }

    private func prepareUIForPresentingResults() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        isActivityInProgress = false
        reloadSearchResults()
    }

    private func reloadSearchResults() {
        guard let host = host else { return }
        if host.searchResultsDataSource.calculateChangesets() {
            Logger.info("Reloading Search Results")
            host.availableTimezoneTableView.reloadData()
        }
    }

    private func resetSearchView() {
        searchTask?.cancel()

        guard let host = host else { return }
        isActivityInProgress = false
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
    }

    // MARK: - Timezone Fetching

    private func getTimezone(for latitude: Double, and longitude: Double) {
        guard let host = host else { return }

        if host.placeholderLabel.isHidden {
            host.placeholderLabel.isHidden = false
        }

        host.searchField.placeholderString = "Fetching data might take some time!"
        host.placeholderLabel.placeholderString = "Retrieving timezone data"
        host.availableTimezoneTableView.isHidden = true

        let timeStamp = Date().timeIntervalSince1970

        guard let url = NetworkManager.timezoneURL(for: latitude, longitude: longitude, timestamp: timeStamp, key: geocodingKey) else {
            presentError("Unable to construct timezone URL.")
            return
        }

        Task { @MainActor in
            do {
                let json = try await NetworkManager.data(from: url)

                if handleEdgeCase(for: json) == true {
                    reloadSearchResults()
                    return
                }

                guard let timezone = json.decodeTimezone() else {
                    host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
                    isActivityInProgress = false
                    return
                }

                if host.availableTimezoneTableView.selectedRow >= 0 {
                    installTimezone(timezone)
                }
                updateViewState()
            } catch {
                if error.localizedDescription == "The Internet connection appears to be offline." {
                    host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
                } else {
                    host.placeholderLabel.placeholderString = PreferencesConstants.tryAgainMessage
                }

                isActivityInProgress = false
            }
        }
    }

    private func installTimezone(_ timezone: Timezone) {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.info("Data was unexpectedly nil")
            return
        }

        var filteredAddress = "Error"

        if let address = dataObject.formattedAddress {
            filteredAddress = address.filteredName()
        }

        let newTimeZone = [
            UserDefaultKeys.timezoneID: timezone.timeZoneId,
            UserDefaultKeys.timezoneName: filteredAddress,
            UserDefaultKeys.placeIdentifier: dataObject.placeID ?? "",
            "latitude": dataObject.latitude ?? 0.0,
            "longitude": dataObject.longitude ?? 0.0,
            "nextUpdate": UserDefaultKeys.emptyString,
            UserDefaultKeys.customLabel: filteredAddress
        ] as [String: Any]

        let timezoneObject = TimezoneData(with: newTimeZone)

        let operationsObject = TimezoneDataOperations(with: timezoneObject, store: DataStore.shared())
        operationsObject.saveObject()

        Logger.log(object: ["PlaceName": filteredAddress, "Timezone": timezone.timeZoneId], for: "Filtered Address")
    }

    private func handleEdgeCase(for response: Data?) -> Bool {
        guard let json = response, let jsonUnserialized = try? JSONSerialization.jsonObject(with: json, options: .allowFragments), let unwrapped = jsonUnserialized as? [String: Any] else {
            setErrorPlaceholders()
            return false
        }

        if let status = unwrapped["status"] as? String, status == ResultStatus.zeroResults {
            setErrorPlaceholders()
            return true
        }
        return false
    }

    private func setErrorPlaceholders() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = "No timezone found! Try entering an exact name."
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")
        isActivityInProgress = false
    }

    private func updateViewState() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        reloadSearchResults()
        host.refreshTimezoneTableView(true)
        host.refreshMainTable()
        host.timezonePanel.close()
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")
        host.availableTimezoneTableView.isHidden = false
        isActivityInProgress = false
    }

    private func showMessage() {
        guard let host = host else { return }
        host.placeholderLabel.placeholderString = PreferencesConstants.noInternetConnectivityError
        isActivityInProgress = false
        host.searchResultsDataSource.cleanupFilterArray()
        reloadSearchResults()
    }

    // MARK: - Add to Favorites

    func addToFavorites() {
        guard let host = host else { return }
        isActivityInProgress = true

        if host.availableTimezoneTableView.selectedRow == -1 {
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.noTimezoneSelectedErrorMessage)
            isActivityInProgress = false
            return
        }

        let selectedTimeZones = DataStore.shared().timezones()
        if selectedTimeZones.count >= 100 {
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxTimezonesErrorMessage)
            isActivityInProgress = false
            return
        }

        if host.searchField.stringValue.isEmpty {
            addTimezoneIfSearchStringIsEmpty()
        } else {
            addTimezoneIfSearchStringIsNotEmpty()
        }
    }

    private func addTimezoneIfSearchStringIsEmpty() {
        guard let host = host else { return }
        let currentRowType = host.searchResultsDataSource.placeForRow(host.availableTimezoneTableView.selectedRow)

        switch currentRowType {
        case .timezone:
            cleanupAfterInstallingTimezone()
        default:
            return
        }
    }

    private func addTimezoneIfSearchStringIsNotEmpty() {
        guard let host = host else { return }
        let currentRowType = host.searchResultsDataSource.placeForRow(host.availableTimezoneTableView.selectedRow)

        switch currentRowType {
        case .timezone:
            cleanupAfterInstallingTimezone()
            return
        case .city:
            cleanupAfterInstallingCity()
        }
    }

    private func cleanupAfterInstallingCity() {
        guard let host = host else { return }
        guard let dataObject = host.searchResultsDataSource.retrieveFilteredResultFromGoogleAPI(host.availableTimezoneTableView.selectedRow) else {
            Logger.info("Data was unexpectedly nil")
            return
        }

        if host.messageLabel.stringValue.isEmpty {
            host.searchField.stringValue = UserDefaultKeys.emptyString

            guard let latitude = dataObject.latitude, let longitude = dataObject.longitude else {
                Logger.info("Data was unexpectedly nil")
                return
            }

            getTimezone(for: latitude, and: longitude)
        }
    }

    private func cleanupAfterInstallingTimezone() {
        guard let host = host else { return }
        let data = TimezoneData()
        data.setLabel(UserDefaultKeys.emptyString)

        let currentSelection = host.searchResultsDataSource.retrieveSelectedTimezone(host.availableTimezoneTableView.selectedRow)

        let metaInfo = metadata(for: currentSelection)
        data.timezoneID = metaInfo.0.name
        data.formattedAddress = metaInfo.1.formattedName
        data.selectionType = .timezone
        data.isSystemTimezone = metaInfo.0.name == NSTimeZone.system.identifier

        let operationObject = TimezoneDataOperations(with: data, store: DataStore.shared())
        operationObject.saveObject()

        host.searchResultsDataSource.cleanupFilterArray()
        host.searchResultsDataSource.timezoneFilteredArray = []
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.stringValue = UserDefaultKeys.emptyString

        reloadSearchResults()
        host.refreshTimezoneTableView(true)
        host.refreshMainTable()

        host.timezonePanel.close()
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")
        host.availableTimezoneTableView.isHidden = false
        isActivityInProgress = false
    }

    private func metadata(for selection: TimezoneMetadata) -> (NSTimeZone, TimezoneMetadata) {
        if selection.formattedName == "Anywhere on Earth" {
            return (NSTimeZone(name: "GMT-1200") ?? NSTimeZone.default as NSTimeZone, selection)
        } else if selection.formattedName == "UTC" {
            return (NSTimeZone(name: "GMT") ?? NSTimeZone.default as NSTimeZone, selection)
        } else {
            return (selection.timezone, selection)
        }
    }

    // MARK: - Close Panel

    func closePanel() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()
        host.searchResultsDataSource.timezoneFilteredArray = []
        host.searchField.stringValue = UserDefaultKeys.emptyString
        host.placeholderLabel.placeholderString = UserDefaultKeys.emptyString
        host.searchField.placeholderString = NSLocalizedString("Search Field Placeholder",
                                                               comment: "Search Field Placeholder")

        reloadSearchResults()

        host.timezonePanel.close()
        isActivityInProgress = false
        host.addTimezoneButton.state = .off

        host.availableTimezoneTableView.isHidden = false
    }

    // MARK: - Filter

    func filterArray() {
        guard let host = host else { return }
        host.searchResultsDataSource.cleanupFilterArray()

        if host.searchField.stringValue.count > 50 {
            isActivityInProgress = false
            reloadSearchResults()
            host.timezonePanel.contentView?.makeToast(PreferencesConstants.maxCharactersAllowed)
            return
        }

        if host.searchField.stringValue.isEmpty == false {
            searchTask?.cancel()
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            perform(#selector(search), with: nil, afterDelay: 0.5)
        } else {
            resetSearchView()
        }

        reloadSearchResults()
    }

    // MARK: - Select Newly Inserted

    func selectNewlyInsertedTimezone() {
        guard let host = host else { return }
        if host.timezoneTableView.numberOfRows > 6 {
            host.timezoneTableView.scrollRowToVisible(host.timezoneTableView.numberOfRows - 1)
        }

        let indexSet = IndexSet(integer: IndexSet.Element(host.timezoneTableView.numberOfRows - 1))
        host.timezoneTableView.selectRowIndexes(indexSet, byExtendingSelection: false)
    }
}
