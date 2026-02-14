// Copyright © 2015 Abhishek Banthia

import Cocoa
import CoreLoggerKit
import CoreModelKit

/// Shared timezone search logic used by both PreferencesViewController and OnboardingSearchController.
/// Eliminates ~120 lines of duplicated search code.
enum TimezoneSearchService {
    /// Parse Google Geocoding API results into TimezoneData objects and add to the data source.
    static func parseAndAddGeocodingResults(_ results: [SearchResult.Result], to dataSource: SearchDataSource) {
        let timezones: [TimezoneData] = results.map { result in
            let location = result.geometry.location
            let totalPackage: [String: Any] = [
                "latitude": location.lat,
                "longitude": location.lng,
                UserDefaultKeys.timezoneName: result.formattedAddress,
                UserDefaultKeys.customLabel: result.formattedAddress,
                UserDefaultKeys.timezoneID: UserDefaultKeys.emptyString,
                UserDefaultKeys.placeIdentifier: result.placeId
            ]
            return TimezoneData(with: totalPackage)
        }
        dataSource.setFilteredArrayValue(timezones)
    }

    /// Search local timezones matching the given query.
    static func searchLocalTimezones(_ query: String, in dataSource: SearchDataSource) {
        dataSource.searchTimezones(query.lowercased())
    }

    /// Perform a geocoding search via the Google Maps API.
    /// Returns the data task so callers can cancel it if needed.
    @discardableResult
    static func performGeocodingSearch(
        for searchString: String,
        geocodingKey: String,
        dataSource: SearchDataSource,
        completion: @escaping (Result<[SearchResult.Result], SearchError>) -> Void
    ) -> URLSessionDataTask? {
        let userPreferredLanguage = Locale.preferredLanguages.first ?? "en-US"

        let words = searchString.components(separatedBy: .whitespacesAndNewlines)
        let compactSearch = words.joined(separator: "")

        guard compactSearch.count >= 3 else {
            completion(.failure(.queryTooShort))
            return nil
        }

        guard let url = NetworkManager.geocodeURL(for: compactSearch, key: geocodingKey, language: userPreferredLanguage) else {
            completion(.failure(.urlConstruction))
            return nil
        }

        let task = NetworkManager.task(with: url) { response, error in
            OperationQueue.main.addOperation {
                if let error = error {
                    completion(.failure(.network(error.localizedDescription)))
                    return
                }

                guard let data = response, let searchResults = data.decode() else {
                    completion(.failure(.parsing))
                    return
                }

                if searchResults.status == ResultStatus.zeroResults {
                    completion(.failure(.zeroResults))
                    return
                }

                if searchResults.status == ResultStatus.requestDenied && searchResults.results.isEmpty {
                    completion(.failure(.requestDenied))
                    return
                }

                completion(.success(searchResults.results))
            }
        }

        return task
    }

    /// Fetch timezone data for the given coordinates via the Google Maps Timezone API.
    @discardableResult
    static func fetchTimezone(
        for latitude: Double,
        longitude: Double,
        geocodingKey: String,
        completion: @escaping (Result<Timezone, SearchError>) -> Void
    ) -> URLSessionDataTask? {
        if !NetworkManager.isConnected() || ProcessInfo.processInfo.arguments.contains("mockTimezoneDown") {
            completion(.failure(.offline))
            return nil
        }

        let timestamp = Date().timeIntervalSince1970

        guard let url = NetworkManager.timezoneURL(for: latitude, longitude: longitude, timestamp: timestamp, key: geocodingKey) else {
            completion(.failure(.urlConstruction))
            return nil
        }

        let task = NetworkManager.task(with: url) { response, error in
            OperationQueue.main.addOperation {
                if let error = error {
                    if error.localizedDescription == "The Internet connection appears to be offline." {
                        completion(.failure(.offline))
                    } else {
                        completion(.failure(.network(error.localizedDescription)))
                    }
                    return
                }

                guard let json = response else {
                    completion(.failure(.parsing))
                    return
                }

                // Check for edge cases (zero results from timezone API)
                if let jsonUnserialized = try? JSONSerialization.jsonObject(with: json, options: .allowFragments),
                   let unwrapped = jsonUnserialized as? [String: Any],
                   let status = unwrapped["status"] as? String,
                   status == ResultStatus.zeroResults {
                    completion(.failure(.zeroResults))
                    return
                }

                guard let timezone = json.decodeTimezone() else {
                    completion(.failure(.parsing))
                    return
                }

                completion(.success(timezone))
            }
        }

        return task
    }

    /// Errors that can occur during timezone search operations.
    enum SearchError: LocalizedError {
        case queryTooShort
        case urlConstruction
        case offline
        case network(String)
        case parsing
        case zeroResults
        case requestDenied

        var errorDescription: String? {
            switch self {
            case .queryTooShort: return "Search query too short"
            case .urlConstruction: return "Unable to construct search URL"
            case .offline: return PreferencesConstants.noInternetConnectivityError
            case .network(let message): return message
            case .parsing: return PreferencesConstants.tryAgainMessage
            case .zeroResults: return "No results! 😔 Try entering the exact name."
            case .requestDenied: return "Update Clocker to get a faster experience 😃"
            }
        }
    }
}
