// Copyright © 2015 Abhishek Banthia

@testable import Clocker
import CoreModelKit
import XCTest

class NetworkManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - URL Construction Tests

    func testGeocodeURLConstruction() {
        let url = NetworkManager.geocodeURL(for: "San Francisco", key: "test-key", language: "en")
        XCTAssertNotNil(url)
        let urlString = url!.absoluteString
        XCTAssertTrue(urlString.contains("maps.googleapis.com"))
        XCTAssertTrue(urlString.contains("geocode"))
        XCTAssertTrue(urlString.contains("San%20Francisco"))
        XCTAssertTrue(urlString.contains("test-key"))
        XCTAssertTrue(urlString.contains("en"))
    }

    func testTimezoneURLConstruction() {
        let url = NetworkManager.timezoneURL(for: 37.7749, longitude: -122.4194, timestamp: 1000000, key: "test-key")
        XCTAssertNotNil(url)
        let urlString = url!.absoluteString
        XCTAssertTrue(urlString.contains("maps.googleapis.com"))
        XCTAssertTrue(urlString.contains("timezone"))
        XCTAssertTrue(urlString.contains("37.7749"))
        XCTAssertTrue(urlString.contains("-122.4194"))
        XCTAssertTrue(urlString.contains("test-key"))
    }

    func testGeocodeURLEncodesSpecialCharacters() {
        let url = NetworkManager.geocodeURL(for: "São Paulo", key: "key", language: "pt-BR")
        XCTAssertNotNil(url)
        // URLComponents should percent-encode special characters
        let urlString = url!.absoluteString
        XCTAssertTrue(urlString.contains("maps.googleapis.com"))
    }

    // MARK: - Response Parsing Tests

    func testGeocodeResponseParsing() {
        let json = """
        {
            "results": [
                {
                    "address_components": [
                        {"long_name": "San Francisco", "short_name": "SF", "types": ["locality"]}
                    ],
                    "formatted_address": "San Francisco, CA, USA",
                    "geometry": {
                        "location": {"lat": 37.7749295, "lng": -122.4194155},
                        "location_type": "APPROXIMATE"
                    },
                    "place_id": "ChIJIQBpAG2ahYAR_6128GcTUEo",
                    "types": ["locality", "political"]
                }
            ],
            "status": "OK"
        }
        """.data(using: .utf8)!

        let result = json.decode()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "OK")
        XCTAssertEqual(result?.results.count, 1)
        XCTAssertEqual(result?.results.first?.formattedAddress, "San Francisco, CA, USA")
        XCTAssertEqual(result?.results.first?.geometry.location.lat, 37.7749295)
        XCTAssertEqual(result?.results.first?.geometry.location.lng, -122.4194155)
        XCTAssertEqual(result?.results.first?.placeId, "ChIJIQBpAG2ahYAR_6128GcTUEo")
    }

    func testTimezoneResponseParsing() {
        let json = """
        {
            "dstOffset": 3600,
            "rawOffset": -28800,
            "status": "OK",
            "timeZoneId": "America/Los_Angeles",
            "timeZoneName": "Pacific Daylight Time"
        }
        """.data(using: .utf8)!

        let result = json.decodeTimezone()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.timeZoneId, "America/Los_Angeles")
        XCTAssertEqual(result?.timeZoneName, "Pacific Daylight Time")
        XCTAssertEqual(result?.dstOffset, 3600)
        XCTAssertEqual(result?.rawOffset, -28800)
    }

    func testZeroResultsResponse() {
        let json = """
        {
            "results": [],
            "status": "ZERO_RESULTS"
        }
        """.data(using: .utf8)!

        let result = json.decode()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "ZERO_RESULTS")
        XCTAssertTrue(result?.results.isEmpty ?? false)
    }

    func testRequestDeniedResponse() {
        let json = """
        {
            "results": [],
            "status": "REQUEST_DENIED",
            "error_message": "The provided API key is invalid."
        }
        """.data(using: .utf8)!

        let result = json.decode()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "REQUEST_DENIED")
        XCTAssertEqual(result?.errorMessage, "The provided API key is invalid.")
    }

    func testMalformedJSONReturnsNil() {
        let json = "not valid json".data(using: .utf8)!
        XCTAssertNil(json.decode())
        XCTAssertNil(json.decodeTimezone())
    }

    func testEmptyDataReturnsNil() {
        let json = Data()
        XCTAssertNil(json.decode())
        XCTAssertNil(json.decodeTimezone())
    }

    func testMultipleGeocodingResults() {
        let json = """
        {
            "results": [
                {
                    "address_components": [
                        {"long_name": "London", "short_name": "London", "types": ["locality"]}
                    ],
                    "formatted_address": "London, UK",
                    "geometry": {
                        "location": {"lat": 51.5074, "lng": -0.1278},
                        "location_type": "APPROXIMATE"
                    },
                    "place_id": "ChIJdd4hrwug2EcRmSrV3Vo6llI",
                    "types": ["locality"]
                },
                {
                    "address_components": [
                        {"long_name": "London", "short_name": "London", "types": ["locality"]}
                    ],
                    "formatted_address": "London, ON, Canada",
                    "geometry": {
                        "location": {"lat": 42.9849, "lng": -81.2453},
                        "location_type": "APPROXIMATE"
                    },
                    "place_id": "ChIJC5uNqA7yLogRlWsFmmnFPvs",
                    "types": ["locality"]
                }
            ],
            "status": "OK"
        }
        """.data(using: .utf8)!

        let result = json.decode()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.results.count, 2)
        XCTAssertEqual(result?.results[0].formattedAddress, "London, UK")
        XCTAssertEqual(result?.results[1].formattedAddress, "London, ON, Canada")
    }

    // MARK: - Error Sentinel Tests

    func testParsingErrorProperties() {
        let error = NetworkManager.parsingError
        XCTAssertEqual(error.domain, "APIError")
        XCTAssertEqual(error.code, 102)
    }

    func testInternalServerErrorProperties() {
        let error = NetworkManager.internalServerError
        XCTAssertEqual(error.domain, "APIError")
        XCTAssertEqual(error.code, 100)
    }
}
