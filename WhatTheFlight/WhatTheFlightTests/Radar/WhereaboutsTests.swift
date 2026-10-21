//
//  WhereaboutsTests.swift
//  WhatTheFlightTests
//
//  "Where is it now?" lookups and the logbook's per-airframe counter.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class WhereaboutsTests: XCTestCase {
    func testLocateQueriesTheWholeWorldByRegistrationThenCallsign() throws {
        let byReg = try XCTUnwrap(FlightRadarFeed.locateURL(registration: " n302dn", callsign: "DAL1199"))
        let items = URLComponents(url: byReg, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "reg" }?.value, "N302DN")
        XCTAssertNil(items.first { $0.name == "callsign" })
        XCTAssertEqual(items.first { $0.name == "bounds" }?.value, "90,-90,-180,180")
        XCTAssertEqual(items.first { $0.name == "gnd" }?.value, "1", "parked aircraft are found too")

        let byCallsign = try XCTUnwrap(FlightRadarFeed.locateURL(registration: nil, callsign: "dal1199"))
        XCTAssertTrue(byCallsign.absoluteString.contains("callsign=DAL1199"))
        XCTAssertNil(FlightRadarFeed.locateURL(registration: "", callsign: nil))

        let radar = try XCTUnwrap(FlightRadarFeed.url(for: .around(center: TestTraffic.observer, radiusKm: 30)))
        XCTAssertTrue(radar.absoluteString.contains("gnd=0"), "the radar itself still skips ground traffic")
    }

    func testAirborneWhereaboutsSaysHowFarAndWhetherItsTheSameFlight() {
        var f = TestTraffic.flight("leg2", miles: 300, bearing: 45)
        f.flightNumber = "DL3161"
        f.originIATA = "ATL"
        f.destinationIATA = "DFW"
        let later = Whereabouts(flight: f, observer: TestTraffic.observer, seenFlightID: "leg1")
        XCTAssertEqual(later.headline, "In the air")
        XCTAssertEqual(later.detail, "Now flying DL3161 · ATL → DFW")
        XCTAssertEqual(later.distanceText, "300 mi NE of you")

        let same = Whereabouts(flight: f, observer: TestTraffic.observer, seenFlightID: "leg2")
        XCTAssertEqual(same.detail, "Still on DL3161 · ATL → DFW")
    }

    func testParkedAircraftIsPlacedAtTheNearestAirport() {
        let atl = AirportCatalog.airport(iata: "ATL")!.coordinate!
        let f = Flight(id: "p", hex: nil, latitude: atl.latitude + 0.01, longitude: atl.longitude, track: 0,
                       altitudeFeet: 0, groundSpeedKnots: 0, verticalRateFPM: 0, squawk: nil, typeCode: "A321",
                       registration: "N302DN", originIATA: nil, destinationIATA: nil, flightNumber: nil,
                       callsign: nil, airlineICAO: nil, isOnGround: true, positionTime: Date())
        let w = Whereabouts(flight: f, observer: nil)
        XCTAssertEqual(w.headline, "On the ground at ATL")
        XCTAssertNil(w.distanceText)
    }

    @MainActor
    func testAirframeSummaryCountsEveryVisitForever() {
        let book = Logbook(fileURL: nil)
        func visit(_ id: String, miles: Double, daysAgo: Double) {
            var f = TestTraffic.flight(id, miles: miles)
            f.registration = "N302DN"
            book.record([RadarContact(flight: f, observer: TestTraffic.observer, at: Date())],
                        at: Date().addingTimeInterval(-daysAgo * 86_400))
        }
        XCTAssertEqual(book.summary(airframe: "N302DN").count, 0)
        visit("a", miles: 6, daysAgo: 30)
        visit("b", miles: 2, daysAgo: 3)
        visit("c", miles: 9, daysAgo: 0)
        var other = TestTraffic.flight("z", miles: 1)
        other.registration = "N1"
        book.record([RadarContact(flight: other, observer: TestTraffic.observer, at: Date())])

        let summary = book.summary(airframe: "N302DN")
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.history.map(\.id), ["c", "b", "a"], "newest first")
        XCTAssertEqual(summary.first?.id, "a")
        XCTAssertEqual(summary.latest?.id, "c")
        XCTAssertEqual(summary.closest?.id, "b")
        XCTAssertEqual(book.summary(airframe: nil).count, 0)
    }
}
