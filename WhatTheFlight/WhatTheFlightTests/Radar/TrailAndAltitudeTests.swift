//
//  TrailAndAltitudeTests.swift
//  WhatTheFlightTests
//
//  Altitude carried along between polls, and trails kept only where a map draws them.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class PredictedAltitudeTests: XCTestCase {
    private func flight(altitude: Int, rate: Int, at fix: Date, ground: Bool = false) -> Flight {
        var f = TestTraffic.flight("a", miles: 3, ground: ground, at: fix)
        f.altitudeFeet = altitude
        f.verticalRateFPM = rate
        return f
    }

    func testClimbsWithTheVerticalRate() {
        let fix = Date()
        let f = flight(altitude: 10_000, rate: 1200, at: fix)
        XCTAssertEqual(f.predictedAltitudeFeet(at: fix), 10_000, "the reported altitude at the fix")
        XCTAssertEqual(f.predictedAltitudeFeet(at: fix.addingTimeInterval(30)), 10_600)
    }

    func testStopsAfterNinetySeconds() {
        let fix = Date()
        let f = flight(altitude: 10_000, rate: 1200, at: fix)
        XCTAssertEqual(f.predictedAltitudeFeet(at: fix.addingTimeInterval(300)), 11_800)
    }

    func testNeverGoesBelowTheGround() {
        let fix = Date()
        let f = flight(altitude: 300, rate: -1500, at: fix)
        XCTAssertEqual(f.predictedAltitudeFeet(at: fix.addingTimeInterval(60)), 0)
    }

    func testRoundsToTenFeetAndLeavesLevelAndGroundTrafficAlone() {
        let fix = Date()
        XCTAssertEqual(flight(altitude: 5_325, rate: 1536, at: fix).predictedAltitudeFeet(at: fix.addingTimeInterval(1)), 5_350)
        XCTAssertEqual(flight(altitude: 37_000, rate: 0, at: fix).predictedAltitudeFeet(at: fix.addingTimeInterval(60)), 37_000)
        XCTAssertEqual(flight(altitude: 0, rate: 500, at: fix, ground: true).predictedAltitudeFeet(at: fix.addingTimeInterval(60)), 0)
    }

    func testContactsCarryTheEstimate() {
        let fix = Date()
        let contact = RadarContact(flight: flight(altitude: 8_000, rate: -600, at: fix), observer: TestTraffic.observer,
                                   at: fix.addingTimeInterval(20))
        XCTAssertEqual(contact.altitudeFeet, 7_800)
        XCTAssertEqual(contact.flight.altitudeFeet, 8_000, "the reported value is still there")
    }
}

@MainActor
final class TrailReachTests: XCTestCase {
    var settings: RadarSettings!
    var feed: StubFeed!
    var model: RadarModel!

    override func setUp() async throws {
        settings = RadarSettings(defaults: UserDefaults(suiteName: "TrailReachTests-\(UUID().uuidString)")!)
        settings.radiusMiles = 20
        feed = StubFeed()
        model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.setObserver(TestTraffic.observer)
    }

    func testTrailsStopAtOneAndAHalfTimesTheRadius() async {
        feed.flights = [TestTraffic.flight("near", miles: 5), TestTraffic.flight("fringe", miles: 28), TestTraffic.flight("far", miles: 45)]
        await model.pollOnce()
        XCTAssertEqual(model.trail(for: "near").count, 1)
        XCTAssertEqual(model.trail(for: "fringe").count, 1, "the map draws fringe traffic to 1.5× the ring")
        XCTAssertTrue(model.trail(for: "far").isEmpty)
    }

    func testPinnedAircraftKeepTheirTrailsAnywhere() async {
        let far = TestTraffic.flight("far", miles: 45)
        feed.flights = [far]
        model.pin(far)
        await model.pollOnce()
        XCTAssertEqual(model.trail(for: "far").count, 1)
    }

    func testAWiderMapKeepsTrailsFurtherOut() async {
        model.trailRadiusFloor = 40
        feed.flights = [TestTraffic.flight("far", miles: 45)]
        await model.pollOnce()
        XCTAssertEqual(model.trail(for: "far").count, 1)
    }

    func testATrailIsDroppedOnceItsAircraftIsOutOfReach() async {
        let start = Date()
        // The nearest takes the focus; focused aircraft keep their trails wherever they go.
        let nearest = TestTraffic.flight("nearest", miles: 2, at: start)
        feed.flights = [nearest, TestTraffic.flight("a", miles: 10, at: start)]
        await model.pollOnce()
        XCTAssertEqual(model.trail(for: "a").count, 1)

        feed.flights = [nearest, TestTraffic.flight("a", miles: 40, at: start.addingTimeInterval(10))]
        await model.pollOnce()
        XCTAssertTrue(model.trail(for: "a").isEmpty)
    }
}
