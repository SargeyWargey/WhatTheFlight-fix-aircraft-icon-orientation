//
//  FlightFeedParserTests.swift
//  WhatTheFlightTests
//

import XCTest
@testable import WhatTheFlight

final class FlightFeedParserTests: XCTestCase {
    /// Trimmed from a real `feed.js` response.
    let sample = """
    {
      "full_count": 21304,
      "version": 4,
      "4224b2ea": ["AAA5FF", 33.9401, -84.7762, 141, 11850, 378, "", "F-BDWY1", "B737", "N7854B", 1792120251, "BNA", "ATL", "WN2533", 0, 0, "SWA2533", 0, "SWA"],
      "4224d319": ["A3F1C2", 33.7414, -84.5813, 1, 8000, 290, "7421", "F-BDWY1", "B763", "N353UP", 1792120249, "ATL", "SDF", "5X1303", 0, 3328, "UPS1303", 0, "UPS"],
      "42240001": ["ABCDEF", 33.70, -84.40, 270, 0, 12, "", "F-KATL1", "B738", "N123AA", 1792120240, "ATL", "LAX", "AA1", 1, 0, "AAL1", 0, "AAL"],
      "42240002": ["A11111", 33.70, -84.40, 90.5, 1500.0, 110, "", "T-MLAT1", "EC45", "N145LF", 1792120240, "", "", "", 0, -256, "LIFE2", 0, ""],
      "broken": ["A0", "not-a-number", -84.0],
      "stats": {"total": {"ads-b": 1}}
    }
    """.data(using: .utf8)!

    func testParsesAircraftAndSkipsMetadata() throws {
        let flights = try FlightFeedParser.parse(sample, receivedAt: Date(timeIntervalSince1970: 1792120260))
        XCTAssertEqual(Set(flights.map(\.id)), ["4224b2ea", "4224d319", "42240001", "42240002"])
    }

    func testMapsEveryField() throws {
        let flights = try FlightFeedParser.parse(sample, receivedAt: Date(timeIntervalSince1970: 1792120260))
        let ups = try XCTUnwrap(flights.first { $0.id == "4224d319" })
        XCTAssertEqual(ups.hex, "A3F1C2")
        XCTAssertEqual(ups.latitude, 33.7414, accuracy: 1e-9)
        XCTAssertEqual(ups.longitude, -84.5813, accuracy: 1e-9)
        XCTAssertEqual(ups.track, 1)
        XCTAssertEqual(ups.altitudeFeet, 8000)
        XCTAssertEqual(ups.groundSpeedKnots, 290)
        XCTAssertEqual(ups.squawk, "7421")
        XCTAssertEqual(ups.typeCode, "B763")
        XCTAssertEqual(ups.registration, "N353UP")
        XCTAssertEqual(ups.originIATA, "ATL")
        XCTAssertEqual(ups.destinationIATA, "SDF")
        XCTAssertEqual(ups.flightNumber, "5X1303")
        XCTAssertEqual(ups.verticalRateFPM, 3328)
        XCTAssertEqual(ups.callsign, "UPS1303")
        XCTAssertEqual(ups.airlineICAO, "UPS")
        XCTAssertFalse(ups.isOnGround)
        XCTAssertEqual(ups.positionTime, Date(timeIntervalSince1970: 1792120249))
        XCTAssertEqual(ups.verticalTrend, .climbing)
    }

    func testEnrichmentFromCatalogs() throws {
        let flights = try FlightFeedParser.parse(sample)
        let ups = try XCTUnwrap(flights.first { $0.id == "4224d319" })
        XCTAssertEqual(ups.airline?.name, "UPS Airlines")
        XCTAssertEqual(ups.typeName, "Boeing 767-300")
        XCTAssertEqual(ups.origin?.city, "Atlanta")
        XCTAssertEqual(ups.destination?.city, "Louisville")
        XCTAssertEqual(ups.kind, .airplane)
        XCTAssertEqual(ups.displayIdentifier, "5X1303")
    }

    func testEmptyStringsBecomeNilAndHelicopterDetected() throws {
        let flights = try FlightFeedParser.parse(sample)
        let heli = try XCTUnwrap(flights.first { $0.id == "42240002" })
        XCTAssertNil(heli.flightNumber)
        XCTAssertNil(heli.originIATA)
        XCTAssertNil(heli.airlineICAO)
        XCTAssertFalse(heli.hasRoute)
        XCTAssertEqual(heli.displayIdentifier, "LIFE2")
        XCTAssertEqual(heli.kind, .helicopter)
        XCTAssertEqual(heli.altitudeFeet, 1500)
        XCTAssertEqual(heli.track, 90.5, accuracy: 1e-9)
    }

    func testGroundFlag() throws {
        let flights = try FlightFeedParser.parse(sample)
        XCTAssertTrue(try XCTUnwrap(flights.first { $0.id == "42240001" }).isOnGround)
    }

    func testFutureTimestampsAreClamped() {
        let received = Date(timeIntervalSince1970: 1_000)
        let flight = FlightFeedParser.flight(
            id: "x",
            fields: ["A", 1.0, 2.0, 0, 0, 0, "", "", "", "", 9_999, "", "", "", 0, 0, ""],
            receivedAt: received
        )
        XCTAssertEqual(flight?.positionTime, received)
    }

    func testRejectsNonObjectPayload() {
        XCTAssertThrowsError(try FlightFeedParser.parse("[1,2,3]".data(using: .utf8)!))
    }

    func testCallsignFallbackForAirline() {
        XCTAssertEqual(AirlineCatalog.airline(icao: nil, callsign: "DAL1589", flightNumber: nil)?.name, "Delta Air Lines")
        XCTAssertNil(AirlineCatalog.airline(icao: nil, callsign: "N172SP", flightNumber: nil))
    }
}
