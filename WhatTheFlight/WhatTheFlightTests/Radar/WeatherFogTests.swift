//
//  WeatherFogTests.swift
//  WhatTheFlightTests
//
//  Clouds and fog over the radar and the map: each report's cover and fog, the blend between
//  stations, the drift, and the METAR fields they need.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class WeatherFogTests: XCTestCase {
    private let home = TestTraffic.observer

    private func layer(_ cover: String, _ feet: Int) -> SkyConditions.Layer { .init(cover: cover, baseFeet: feet) }

    private func report(_ id: String, north: Double = 0, east: Double = 0, visibility: Double = 10, layers: [SkyConditions.Layer] = [],
                        weather: String? = nil, wind: (Double, Double)? = nil, seesHigh: Bool = false, at date: Date = Date()) -> SkyConditions {
        let p = GeoMath.destination(from: GeoMath.destination(from: home, bearingDegrees: 0, distanceMiles: north),
                                    bearingDegrees: 90, distanceMiles: east)
        return SkyConditions(station: id, stationName: nil, latitude: p.latitude, longitude: p.longitude, elevationFeet: 1_000,
                             observedAt: date, visibilityMiles: visibility, layers: layers, weather: weather,
                             windFromDegrees: wind?.0, windKnots: wind?.1, seesHighCloud: seesHigh)
    }

    func testCoverStacksAndHighCloudCountsHalf() {
        XCTAssertEqual(WeatherFog.cloud(from: []), 0)
        XCTAssertEqual(WeatherFog.cloud(from: [layer("SCT", 3_500)]), 0.45, accuracy: 0.001)
        XCTAssertEqual(WeatherFog.cloud(from: [layer("OVC", 1_500)]), 1, accuracy: 0.001)
        // Two scattered layers cover more than one, but not everything.
        XCTAssertEqual(WeatherFog.cloud(from: [layer("SCT", 3_000), layer("SCT", 8_000)]), 1 - 0.55 * 0.55, accuracy: 0.001)
        XCTAssertEqual(WeatherFog.cloud(from: [layer("BKN", 25_000)]), 0.375, accuracy: 0.001, "thin cirrus")
    }

    func testFogFromWeatherCodesAndVisibility() {
        XCTAssertEqual(WeatherFog.fog(visibilityMiles: 10, weather: nil, layers: []), 0)
        XCTAssertEqual(WeatherFog.fog(visibilityMiles: 10, weather: "FG", layers: []), 0.9, accuracy: 0.001)
        XCTAssertEqual(WeatherFog.fog(visibilityMiles: 10, weather: "BCFG", layers: []), 0.5, accuracy: 0.001, "patchy")
        XCTAssertEqual(WeatherFog.fog(visibilityMiles: 10, weather: "-RA BR", layers: []), 0.45, accuracy: 0.001)
        XCTAssertEqual(WeatherFog.fog(visibilityMiles: 1, weather: nil, layers: []), 6.0 / 7 * 0.8, accuracy: 0.001)
        XCTAssertEqual(WeatherFog.fog(visibilityMiles: 0.25, weather: nil, layers: [layer("VV", 100)]), 1, "sky hidden")
    }

    func testClearReportsMakeNoFog() {
        XCTAssertNil(WeatherFog(reports: [report("A"), report("B", east: 20)]))
        XCTAssertNil(WeatherFog(reports: []))
        let stale = report("C", layers: [layer("OVC", 1_000)], at: Date().addingTimeInterval(-4 * 3600))
        XCTAssertNil(WeatherFog(reports: [stale]), "too old to trust")
    }

    func testNearerStationsCountForMore() throws {
        let fog = try XCTUnwrap(WeatherFog(reports: [report("W", east: -20, layers: [layer("OVC", 2_000)]), report("E", east: 20)]))
        let west = GeoMath.destination(from: home, bearingDegrees: 270, distanceMiles: 18)
        XCTAssertGreaterThan(fog.sample(latitude: west.latitude, longitude: west.longitude).cloud, 0.85)
        XCTAssertEqual(fog.sample(latitude: home.latitude, longitude: home.longitude).cloud, 0.5, accuracy: 0.02, "halfway")
    }

    func testHighCloudOnlyBlendsBetweenStationsThatSeeIt() throws {
        // The airport reports cirrus; its automated neighbour's "clear" only goes to 12,000 ft.
        let fog = try XCTUnwrap(WeatherFog(reports: [
            report("KATL", layers: [layer("BKN", 20_000), layer("BKN", 25_000)], seesHigh: true),
            report("KPDK", north: 15),
        ]))
        let pdk = GeoMath.destination(from: home, bearingDegrees: 0, distanceMiles: 15)
        XCTAssertEqual(fog.sample(latitude: pdk.latitude, longitude: pdk.longitude).cloud, 1 - 0.625 * 0.625, accuracy: 0.01)
    }

    func testGridRunsNorthToSouth() throws {
        let fog = try XCTUnwrap(WeatherFog(reports: [report("N", north: 30, layers: [layer("OVC", 2_000)]), report("S", north: -30)]))
        let grid = fog.grid(center: home, halfMiles: 30, count: 8)
        XCTAssertEqual(grid.cloud.count, 64)
        XCTAssertGreaterThan(grid.cloud[0], grid.cloud[63], "row 0 is the north edge")
        XCTAssertFalse(grid.isUniform)
        XCTAssertTrue(try XCTUnwrap(WeatherFog(reports: [report("X", layers: [layer("SCT", 3_000)])])).grid(center: home, halfMiles: 30, count: 4).isUniform)
    }

    func testCloudsDriftDownwind() throws {
        // Wind from the west: the clouds go east.
        let fog = try XCTUnwrap(WeatherFog(reports: [report("A", layers: [layer("SCT", 3_000)], wind: (270, 15))]))
        XCTAssertEqual(fog.driftBearing, 90, accuracy: 0.001)
        let drift = fog.drift(after: 120)
        XCTAssertEqual(drift.east, 1, accuracy: 0.001, "a tile every two minutes at 15 knots")
        XCTAssertEqual(drift.south, 0, accuracy: 0.001)
        // Calm still moves them a little.
        let calm = try XCTUnwrap(WeatherFog(reports: [report("B", layers: [layer("SCT", 3_000)])]))
        XCTAssertEqual(calm.windKnots, WeatherFog.minimumWindKnots)
    }

    func testParsesEveryStationsLatestReportWithWind() throws {
        let now = Date(timeIntervalSince1970: 1_793_058_900)
        let json = """
        [{"icaoId":"KATL","lat":33.63,"lon":-84.44,"elev":313,"obsTime":1793058720,"visib":"10+","wdir":100,"wspd":5,"cover":"BKN",
          "clouds":[{"cover":"BKN","base":20000},{"cover":"BKN","base":25000}]},
         {"icaoId":"KATL","lat":33.63,"lon":-84.44,"elev":313,"obsTime":1793055120,"visib":3,"wdir":90,"wspd":4,"clouds":[]},
         {"icaoId":"KPDK","lat":33.88,"lon":-84.30,"elev":299,"obsTime":1793058780,"visib":"10+","wdir":0,"wspd":0,"cover":"CLR","clouds":[]},
         {"icaoId":"KRYY","lat":34.01,"lon":-84.60,"elev":306,"obsTime":1793058600,"visib":"10+","wdir":"VRB","wspd":3,"cover":"SKC","clouds":[]}]
        """
        let reports = SkyConditions.parseReports(Data(json.utf8), now: now)
        XCTAssertEqual(reports.map(\.station), ["KATL", "KPDK", "KRYY"])
        let atl = try XCTUnwrap(reports.first)
        XCTAssertEqual(atl.visibilityMiles, 10, "the later of the two reports")
        XCTAssertEqual(atl.windFromDegrees, 100)
        XCTAssertEqual(atl.windKnots, 5)
        XCTAssertTrue(atl.seesHighCloud)
        XCTAssertNil(reports[1].windFromDegrees, "calm")
        XCTAssertFalse(reports[1].seesHighCloud, "automated CLR stops at 12,000 ft")
        XCTAssertNil(reports[2].windFromDegrees, "variable")
        XCTAssertTrue(reports[2].seesHighCloud, "an observer's SKC")
    }

    func testRisingSoonOnlyForecastsAircraftThatCanClearTheTrees() {
        func contact(miles: Double, track: Double, feet: Int) -> RadarContact {
            var f = TestTraffic.flight("x", miles: miles, bearing: 0, track: track, speed: 420)
            f.altitudeFeet = feet
            return RadarContact(flight: f, observer: home, at: Date())
        }
        XCTAssertTrue(SkyForecast.mightRise(contact(miles: 30, track: 180, feet: 8_000)), "low, inbound, passes overhead")
        XCTAssertFalse(SkyForecast.mightRise(contact(miles: 30, track: 0, feet: 8_000)), "flying away")
        XCTAssertFalse(SkyForecast.mightRise(contact(miles: 5, track: 180, feet: 10_000)), "already well up")
        // Crossing 40 mi off at 3,000 ft never gets above the trees.
        var crossing = TestTraffic.flight("y", miles: 45, bearing: 0, track: 260, speed: 300)
        crossing.altitudeFeet = 3_000
        XCTAssertFalse(SkyForecast.mightRise(RadarContact(flight: crossing, observer: home, at: Date())))
    }

    // MARK: Apple Weather

    private func sample(north: Double = 0, east: Double = 0, low: Double = 0, medium: Double = 0, high: Double = 0,
                        visibility: Double? = 10, condition: CloudSample.Obscuration? = nil, wind: (Double, Double)? = nil,
                        at date: Date = Date()) -> CloudSample {
        let p = GeoMath.destination(from: GeoMath.destination(from: home, bearingDegrees: 0, distanceMiles: north),
                                    bearingDegrees: 90, distanceMiles: east)
        return CloudSample(latitude: p.latitude, longitude: p.longitude, low: low, medium: medium, high: high,
                           visibilityMiles: visibility, condition: condition, windFromDegrees: wind?.0, windKnots: wind?.1, observedAt: date)
    }

    func testAppleWeatherCloudByHeight() throws {
        XCTAssertNil(WeatherFog(samples: [sample(), sample(east: 30)]), "all clear is clear")
        let fog = try XCTUnwrap(WeatherFog(samples: [sample(low: 0.5, medium: 0.4, high: 0.6, wind: (300, 12))]))
        let here = fog.sample(latitude: home.latitude, longitude: home.longitude)
        // Low and medium stack (0.7); cirrus counts half (0.3) and stacks on top.
        XCTAssertEqual(here.cloud, 1 - 0.3 * 0.7, accuracy: 0.001)
        XCTAssertEqual(fog.driftBearing, 120, accuracy: 0.001, "wind from the WNW drifts them ESE")
        XCTAssertEqual(fog.windKnots, 12)
    }

    func testAppleWeatherFogAndStaleSamples() throws {
        let foggy = try XCTUnwrap(WeatherFog(samples: [sample(visibility: 0.3, condition: .fog)]))
        XCTAssertEqual(foggy.sample(latitude: home.latitude, longitude: home.longitude).fog, 0.9, accuracy: 0.05)
        XCTAssertNil(WeatherFog(samples: [sample(low: 1, at: Date().addingTimeInterval(-3 * 3600))]), "too old")
    }

    func testFivePointsAroundTheMapsFringe() {
        let points = CloudSample.points(around: home, radiusMiles: 20)
        XCTAssertEqual(points.count, 5)
        XCTAssertEqual(points[0].latitude, home.latitude, accuracy: 0.0001, "you first")
        for p in points.dropFirst() {
            XCTAssertEqual(GeoMath.distanceMiles(from: home, to: p), 30, accuracy: 0.1)
        }
    }

    func testTheDailyBudgetResetsEachDay() {
        var budget = WeatherKitBudget()
        let morning = Date()
        XCTAssertTrue(budget.canSpend(WeatherKitBudget.dailyCap, at: morning))
        budget.spend(WeatherKitBudget.dailyCap - 5, at: morning)
        XCTAssertTrue(budget.canSpend(5, at: morning))
        XCTAssertFalse(budget.canSpend(6, at: morning))
        let tomorrow = morning.addingTimeInterval(86_400)
        XCTAssertTrue(budget.canSpend(WeatherKitBudget.dailyCap, at: tomorrow), "a new day")
        budget.spend(5, at: tomorrow)
        XCTAssertTrue(budget.canSpend(WeatherKitBudget.dailyCap - 5, at: tomorrow))
    }

    func testASampleSetIsReusedNearbyAndWhileFresh() {
        let set = CloudSampleSet(latitude: home.latitude, longitude: home.longitude, radiusMiles: 20, fetchedAt: Date(), samples: [])
        let nearby = GeoMath.destination(from: home, bearingDegrees: 45, distanceMiles: 3)
        let far = GeoMath.destination(from: home, bearingDegrees: 45, distanceMiles: 8)
        XCTAssertTrue(set.covers(nearby, radiusMiles: 22, at: Date(), refresh: 900))
        XCTAssertFalse(set.covers(far, radiusMiles: 20, at: Date(), refresh: 900), "moved on")
        XCTAssertFalse(set.covers(home, radiusMiles: 40, at: Date(), refresh: 900), "a much wider radar")
        XCTAssertFalse(set.covers(home, radiusMiles: 20, at: Date().addingTimeInterval(1_000), refresh: 900), "stale")
    }
}
