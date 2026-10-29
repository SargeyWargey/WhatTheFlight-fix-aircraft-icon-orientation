//
//  SkyVisibilityTests.swift
//  WhatTheFlightTests
//
//  "Can I see it?": the sun, the weather report and the judgement.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class SkyVisibilityTests: XCTestCase {
    private let atl = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)

    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testTheSunAtMiddayAndMidnight() {
        // Solar noon in Atlanta near the June solstice: about 80° up, due south.
        let noon = SunPosition.at(utc(2026, 6, 21, 17, 39), latitude: atl.latitude, longitude: atl.longitude)
        XCTAssertEqual(noon.elevation, 79.7, accuracy: 1.5)
        XCTAssertEqual(noon.azimuth, 180, accuracy: 8)
        let night = SunPosition.at(utc(2026, 6, 22, 5, 39), latitude: atl.latitude, longitude: atl.longitude)
        XCTAssertLessThan(night.elevation, -20)
        // Sunrise is in the east.
        let morning = SunPosition.at(utc(2026, 3, 20, 11, 30), latitude: atl.latitude, longitude: atl.longitude)
        XCTAssertEqual(morning.azimuth, 90, accuracy: 15)
    }

    func testParsesTheNearestFreshReport() throws {
        let now = Date(timeIntervalSince1970: 1_793_055_600)
        let json = """
        [{"icaoId":"KMGE","name":"Marietta/Dobbins AFB, GA, US","lat":33.9189,"lon":-84.5267,"elev":326,"obsTime":1793051700,"visib":"10+",
          "clouds":[{"cover":"BKN","base":2000},{"cover":"OVC","base":25000}],"wxString":null},
         {"icaoId":"KATL","name":"Atlanta","lat":33.63,"lon":-84.44,"elev":313,"obsTime":1793055000,"visib":4,"clouds":[{"cover":"SCT","base":4500}],"wxString":"BR"},
         {"icaoId":"KOLD","lat":33.75,"lon":-84.39,"elev":300,"obsTime":1790000000,"visib":1,"clouds":[]}]
        """
        let report = try XCTUnwrap(SkyConditions.parseMetars(Data(json.utf8), near: atl, now: now))
        XCTAssertEqual(report.station, "KATL", "the stale report on top of us is skipped")
        XCTAssertEqual(report.visibilityMiles, 4)
        XCTAssertNil(report.ceiling, "scattered isn't a ceiling")
        XCTAssertEqual(report.elevationFeet, 1027)
        let dobbins = try XCTUnwrap(SkyConditions.parseMetars(Data(json.utf8), near: CLLocationCoordinate2D(latitude: 33.92, longitude: -84.52), now: now))
        XCTAssertEqual(dobbins.ceiling?.baseFeet, 2000)
        XCTAssertEqual(dobbins.visibilityMiles, 10)
    }

    private let clear = SkyConditions(station: "K", stationName: nil, latitude: 0, longitude: 0, elevationFeet: 1000, observedAt: Date(),
                                      visibilityMiles: 10, layers: [], weather: nil)
    private let day = SunPosition.Position(azimuth: 180, elevation: 50)

    func testJudgement() {
        func assess(_ el: Double, az: Double = 0, miles: Double, feet: Int, shape: AircraftSilhouette = .airliner,
                    conditions: SkyConditions? = nil, sun: SunPosition.Position? = nil) -> SkyVisibility {
            SkyVisibility.assess(elevation: el, azimuth: az, groundMiles: miles, altitudeFeet: feet, silhouette: shape,
                                 conditions: conditions ?? clear, sun: sun ?? day)
        }
        XCTAssertEqual(assess(30, miles: 5, feet: 15_000), .visible)
        XCTAssertEqual(assess(2, miles: 40, feet: 8_000), .lowOnHorizon)
        let overcast = SkyConditions(station: "K", stationName: nil, latitude: 0, longitude: 0, elevationFeet: 1000, observedAt: Date(),
                                     visibilityMiles: 10, layers: [.init(cover: "OVC", baseFeet: 2500)], weather: nil)
        XCTAssertEqual(assess(30, miles: 5, feet: 15_000, conditions: overcast), .aboveClouds(.init(cover: "OVC", baseFeet: 2500)))
        XCTAssertEqual(assess(30, miles: 1, feet: 3_000, conditions: overcast), .visible, "under the cloud base")
        let hazy = SkyConditions(station: "K", stationName: nil, latitude: 0, longitude: 0, elevationFeet: 0, observedAt: Date(),
                                 visibilityMiles: 3, layers: [], weather: "HZ")
        XCTAssertEqual(assess(10, miles: 8, feet: 9_000, conditions: hazy), .haze(visibilityMiles: 3))
        XCTAssertEqual(assess(20, miles: 8, feet: 3_000, shape: .light), .tooFar, "a Cessna 8 mi out is a speck")
        XCTAssertEqual(assess(48, az: 175, miles: 3, feet: 20_000), .nearSun)
        XCTAssertEqual(assess(30, miles: 5, feet: 15_000, sun: .init(azimuth: 0, elevation: -20)), .lights)
    }

    func testOnlySeeableStatesCount() {
        XCTAssertTrue(SkyVisibility.visible.canSee)
        XCTAssertTrue(SkyVisibility.lights.canSee)
        XCTAssertFalse(SkyVisibility.tooFar.canSee)
        XCTAssertNil(SkyVisibility.visible.text)
    }
}
