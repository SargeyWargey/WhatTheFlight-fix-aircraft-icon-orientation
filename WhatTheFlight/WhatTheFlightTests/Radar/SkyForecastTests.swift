//
//  SkyForecastTests.swift
//  WhatTheFlightTests
//
//  Sky View's predicted path and "rising soon" (Enhancements Spec C7).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class SkyForecastTests: XCTestCase {
    private let observer = TestTraffic.observer

    /// 30 mi north, heading straight for the observer at 420 kts and 8,000 ft.
    private func inbound(track: Double = 180, feet: Int = 8_000) -> Flight {
        var f = TestTraffic.flight("a", miles: 30, bearing: 0, track: track, speed: 420)
        f.altitudeFeet = feet
        return f
    }

    func testThePathClimbsTowardTheZenithAsItApproaches() {
        let points = SkyForecast.path(of: inbound(), observer: observer, from: Date(), horizon: 240, step: 60)
        XCTAssertEqual(points.count, 5)
        XCTAssertLessThan(points[0].elevation, points[4].elevation)
        XCTAssertEqual(points[0].azimuth, 0, accuracy: 1)
    }

    func testALowInboundAircraftRisesSoon() throws {
        let rise = try XCTUnwrap(SkyForecast.rise(of: inbound(), observer: observer, from: Date()))
        // 8,000 ft is 5° up at about 17 mi: 13 mi at 420 kts is just under two minutes.
        XCTAssertEqual(rise.seconds, 110, accuracy: 25)
        XCTAssertEqual(rise.azimuth, 0, accuracy: 2)
    }

    func testOutboundOrAlreadyUpDoesntRise() {
        XCTAssertNil(SkyForecast.rise(of: inbound(track: 0), observer: observer, from: Date()), "flying away")
        var near = TestTraffic.flight("b", miles: 3, bearing: 0, track: 180, speed: 300)
        near.altitudeFeet = 10_000
        XCTAssertNil(SkyForecast.rise(of: near, observer: observer, from: Date()), "already well up")
    }
}
