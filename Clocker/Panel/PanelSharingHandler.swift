// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

class PanelSharingHandler: NSObject, NSSharingServicePickerDelegate {
    private let store: DataStore
    private weak var datasource: TimezoneDataSource?

    init(store: DataStore, datasource: TimezoneDataSource?) {
        self.store = store
        self.datasource = datasource
    }

    func updateDatasource(_ datasource: TimezoneDataSource?) {
        self.datasource = datasource
    }

    func sharingServicePicker(_: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        Logger.log(object: ["Service Title": sharingService.title],
                   for: "Sharing Service Executed")
        return nil
    }

    func sharingServicePicker(_: NSSharingServicePicker, sharingServicesForItems _: [Any], proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        let themer = Themer.shared()
        let copySharingService = NSSharingService(title: "Copy All Times",
                                                  image: themer.copyImage(),
                                                  alternateImage: themer.highlightedCopyImage()) { [weak self] in
            guard let strongSelf = self else { return }
            let clipboardCopy = strongSelf.retrieveAllTimes()
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([.string], owner: nil)
            pasteboard.setString(clipboardCopy, forType: .string)
        }
        let allowedServices: Set<String> = Set(["Messages", "Notes"])
        let filteredServices = proposed.filter { service in
            allowedServices.contains(service.title)
        }

        var newProposedServices: [NSSharingService] = [copySharingService]
        newProposedServices.append(contentsOf: filteredServices)
        return newProposedServices
    }

    /// Retrieves all the times from user's added timezones. Times are sorted by date. For eg:
    /// Feb 5
    /// California - 17:17:01
    /// Feb 6
    /// London - 01:17:01
    func retrieveAllTimes() -> String {
        var clipboardCopy = String()

        // Get all timezones
        let timezones = store.timezones()

        if timezones.isEmpty {
            return clipboardCopy
        }

        // Sort them in ascending order
        let sortedByTime = timezones.sorted { obj1, obj2 -> Bool in
            let system = NSTimeZone.system
            guard let object1 = TimezoneData.customObject(from: obj1),
                  let object2 = TimezoneData.customObject(from: obj2)
            else {
                Logger.info("Data was unexpectedly nil")
                return false
            }

            let timezone1 = NSTimeZone(name: object1.timezone())
            let timezone2 = NSTimeZone(name: object2.timezone())

            let difference1 = system.secondsFromGMT() - (timezone1?.secondsFromGMT ?? 0)
            let difference2 = system.secondsFromGMT() - (timezone2?.secondsFromGMT ?? 0)

            return difference1 > difference2
        }

        // Grab date in first place and store it as local variable
        guard let earliestTimezone = TimezoneData.customObject(from: sortedByTime.first) else {
            return clipboardCopy
        }

        let timezoneOperations = TimezoneDataOperations(with: earliestTimezone, store: store)
        let futureSliderValue = datasource?.sliderValue ?? 0
        var sectionTitle = timezoneOperations.todaysDate(with: futureSliderValue)
        clipboardCopy.append("\(sectionTitle)\n")

        stride(from: 0, to: sortedByTime.count, by: 1).forEach {
            if $0 < sortedByTime.count,
               let dataModel = TimezoneData.customObject(from: sortedByTime[$0])
            {
                let dataOperations = TimezoneDataOperations(with: dataModel, store: store)
                let date = dataOperations.todaysDate(with: futureSliderValue)
                let time = dataOperations.time(with: futureSliderValue)
                if date != sectionTitle {
                    sectionTitle = date
                    clipboardCopy.append("\n\(sectionTitle)\n")
                }

                clipboardCopy.append("\(dataModel.formattedTimezoneLabel()) - \(time)\n")
            }
        }
        return clipboardCopy
    }
}
