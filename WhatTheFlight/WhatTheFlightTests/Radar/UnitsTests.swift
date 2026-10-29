//
//  UnitsTests.swift
//  WhatTheFlightTests
//
//  Metric and imperial formatting (Enhancements Spec C10).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class UnitsTests: XCTestCase {
    private var saved: UnitSystem = .imperial

    override func setUp() {
        super.setUp()
        saved = Units.current
    }

    override func tearDown() {
        Units.current = saved
        super.tearDown()
    }

    func testImperialKeepsMilesFeetAndKnots() {
        XCTAssertEqual(RadarFormat.distanceText(12.4, in: .imperial), "12 mi")
        XCTAssertEqual(RadarFormat.altitudeText(35_000, in: .imperial), "35,000 ft")
        XCTAssertEqual(RadarFormat.speedText(450, in: .imperial), "450 kts")
        XCTAssertEqual(RadarFormat.radius(20, in: .imperial), "20 mi")
        XCTAssertEqual(RadarFormat.preciseDistance(1.5, in: .imperial), "1.5 mi")
    }

    func testMetricConverts() {
        XCTAssertEqual(RadarFormat.distanceText(12.4, in: .metric), "20 km")
        XCTAssertEqual(RadarFormat.altitudeText(35_000, in: .metric), "10,670 m")
        XCTAssertEqual(RadarFormat.speedText(450, in: .metric), "833 km/h")
        XCTAssertEqual(RadarFormat.radius(20, in: .metric), "32 km")
        XCTAssertEqual(RadarFormat.preciseDistance(1.5, in: .metric), "2.4 km")
        XCTAssertEqual(RadarFormat.wholeDistance(8_400, in: .metric), "13,518 km")
    }

    func testUnderHalfAUnitReadsLessThanOne() {
        XCTAssertEqual(RadarFormat.distance(0.25, in: .imperial), "<1")
        // 0.25 mi is 0.4 km: still under half a kilometer.
        XCTAssertEqual(RadarFormat.distance(0.25, in: .metric), "<1")
        // 0.4 mi is 0.64 km: rounds to 1 km.
        XCTAssertEqual(RadarFormat.distance(0.4, in: .metric), "1")
    }

    func testShortDistancesUseMetersBelowAKilometer() {
        XCTAssertEqual(RadarFormat.shortDistance(0.25, in: .metric), "400 m")
        XCTAssertEqual(RadarFormat.shortDistance(0.05, in: .metric), "80 m")
        XCTAssertEqual(RadarFormat.shortDistance(0.25, in: .imperial), "0.25 mi")
    }

    func testSpokenFormsRoundForTheEar() {
        XCTAssertEqual(RadarFormat.spokenDistance(1.2, in: .imperial), "1 mile")
        XCTAssertEqual(RadarFormat.spokenDistance(3, in: .imperial), "3 miles")
        XCTAssertEqual(RadarFormat.spokenDistance(3, in: .metric), "5 kilometers")
        XCTAssertEqual(RadarFormat.spokenAltitude(9_480, in: .imperial), "9,500 feet")
        XCTAssertEqual(RadarFormat.spokenAltitude(30_000, in: .metric), "9,150 meters")
    }

    func testAlertsFollowTheCurrentUnits() {
        Units.current = .metric
        let observer = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
        let north = GeoMath.extrapolate(observer, trackDegrees: 0, speedKnots: 3600 / GeoMath.milesPerKnotHour, seconds: 3)
        let flight = Flight(id: "a", hex: nil, latitude: north.latitude, longitude: north.longitude, track: 0, altitudeFeet: 30_000,
                            groundSpeedKnots: 450, verticalRateFPM: 0, squawk: "7700", typeCode: "B738", registration: "N1",
                            originIATA: nil, destinationIATA: nil, flightNumber: "DL1", callsign: "DAL1", airlineICAO: "DAL",
                            isOnGround: false, positionTime: Date())
        let contact = RadarContact(flight: flight, observer: observer, at: Date())
        let sentence = SpokenTraffic.sentence(for: contact, reason: .notable)
        XCTAssertTrue(sentence.contains("kilometers"), sentence)
        XCTAssertTrue(sentence.contains("meters"), sentence)
        XCTAssertFalse(sentence.contains("feet"), sentence)
    }

    func testAltitudeBandsFollowTheUnits() {
        XCTAssertEqual(LogbookSky.altitudeBandLabel(2, units: .imperial), "10–15k")
        XCTAssertEqual(LogbookSky.altitudeBandLabel(8, units: .imperial), "40k+ ft")
        XCTAssertEqual(LogbookSky.altitudeBandLabel(2, units: .metric), "3–4.5")
        XCTAssertEqual(LogbookSky.altitudeBandLabel(8, units: .metric), "12+ km")
    }
}
