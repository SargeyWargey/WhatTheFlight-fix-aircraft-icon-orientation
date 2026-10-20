//
//  GeoMathTests.swift
//  WhatTheFlightTests
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class GeoMathTests: XCTestCase {
    let atl = CLLocationCoordinate2D(latitude: 33.6407, longitude: -84.4277)
    let jfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)

    func testDistanceAtlantaToNewYork() {
        // Published great-circle distance ATL–JFK ≈ 760 statute miles.
        XCTAssertEqual(GeoMath.distanceMiles(from: atl, to: jfk), 760, accuracy: 5)
    }

    func testDistanceIsZeroToSelf() {
        XCTAssertEqual(GeoMath.distanceMiles(from: atl, to: atl), 0, accuracy: 1e-9)
    }

    func testBearingCardinalDirections() {
        let origin = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: .init(latitude: 1, longitude: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: .init(latitude: 0, longitude: 1)), 90, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: .init(latitude: -1, longitude: 0)), 180, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: origin, to: .init(latitude: 0, longitude: -1)), 270, accuracy: 0.01)
    }

    func testDestinationRoundTrip() {
        let out = GeoMath.destination(from: atl, bearingDegrees: 63, distanceMiles: 12)
        XCTAssertEqual(GeoMath.distanceMiles(from: atl, to: out), 12, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: atl, to: out), 63, accuracy: 0.1)
    }

    func testExtrapolateMovesAtGroundSpeed() {
        // 480 kts for 60 s ≈ 9.2 statute miles.
        let moved = GeoMath.extrapolate(atl, trackDegrees: 90, speedKnots: 480, seconds: 60)
        XCTAssertEqual(GeoMath.distanceMiles(from: atl, to: moved), 480 * GeoMath.milesPerKnotHour / 60, accuracy: 0.02)
    }

    func testNormalizeAndShortestDelta() {
        XCTAssertEqual(GeoMath.normalize(-30), 330)
        XCTAssertEqual(GeoMath.normalize(725), 5)
        XCTAssertEqual(GeoMath.shortestDelta(from: 350, to: 10), 20)
        XCTAssertEqual(GeoMath.shortestDelta(from: 10, to: 350), -20)
    }

    func testCardinalLabels() {
        XCTAssertEqual(GeoMath.cardinal(0), "N")
        XCTAssertEqual(GeoMath.cardinal(44), "NE")
        XCTAssertEqual(GeoMath.cardinal(181), "S")
        XCTAssertEqual(GeoMath.cardinal(359), "N")
    }

    func testClosestApproachHeadOn() {
        // Aircraft 10 mi due north flying due south passes straight overhead.
        let aircraft = GeoMath.destination(from: atl, bearingDegrees: 0, distanceMiles: 10)
        let cpa = GeoMath.closestApproach(observer: atl, aircraft: aircraft, trackDegrees: 180, speedKnots: 300)
        XCTAssertTrue(cpa.isAhead)
        XCTAssertEqual(cpa.distanceMiles, 0, accuracy: 0.05)
        let expectedSeconds = 10 / (300 * GeoMath.milesPerKnotHour) * 3600
        XCTAssertEqual(cpa.secondsFromNow, expectedSeconds, accuracy: 1)
    }

    func testClosestApproachOffset() {
        // 10 mi north, flying due west (track 270), 3 mi east of the observer's meridian:
        // passes 10 mi north at closest.
        let north = GeoMath.destination(from: atl, bearingDegrees: 0, distanceMiles: 10)
        let aircraft = GeoMath.destination(from: north, bearingDegrees: 90, distanceMiles: 3)
        let cpa = GeoMath.closestApproach(observer: atl, aircraft: aircraft, trackDegrees: 270, speedKnots: 200)
        XCTAssertTrue(cpa.isAhead)
        XCTAssertEqual(cpa.distanceMiles, 10, accuracy: 0.1)
    }

    func testClosestApproachWhenMovingAway() {
        let aircraft = GeoMath.destination(from: atl, bearingDegrees: 0, distanceMiles: 10)
        let cpa = GeoMath.closestApproach(observer: atl, aircraft: aircraft, trackDegrees: 0, speedKnots: 300)
        XCTAssertFalse(cpa.isAhead)
        XCTAssertEqual(cpa.distanceMiles, 10, accuracy: 0.01)
    }

    func testBoundsAroundCoverRadius() {
        let bounds = GeographicBounds.around(center: atl, radiusMiles: 20)
        XCTAssertTrue(bounds.isValid)
        let north = CLLocationCoordinate2D(latitude: bounds.northLatitude, longitude: atl.longitude)
        let east = CLLocationCoordinate2D(latitude: atl.latitude, longitude: bounds.eastLongitude)
        XCTAssertEqual(GeoMath.distanceMiles(from: atl, to: north), 20, accuracy: 0.3)
        XCTAssertEqual(GeoMath.distanceMiles(from: atl, to: east), 20, accuracy: 0.3)
    }

    func testMilesFormattingRoundsToWholeNumbers() {
        XCTAssertEqual(RadarFormat.miles(0.2), "<1")
        XCTAssertEqual(RadarFormat.miles(0.5), "1")
        XCTAssertEqual(RadarFormat.miles(14.49), "14")
        XCTAssertEqual(RadarFormat.miles(14.5), "15")
        XCTAssertEqual(RadarFormat.countdown(72), "1:12")
        XCTAssertEqual(RadarFormat.countdown(3725), "1:02:05")
    }
}
