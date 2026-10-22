//
//  TrafficMapGeometryTests.swift
//  WhatTheFlightTests
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class TrafficMapGeometryTests: XCTestCase {
    private let observer = TestTraffic.observer

    // MARK: Frame

    func testFrameIsCentredOnTheObserverAndFitsTheRing() {
        let frame = TrafficMapGeometry.frame(observer: observer, radiusMiles: 20, padding: 1.1)
        XCTAssertEqual(frame.center.latitude, observer.latitude, accuracy: 1e-9)
        XCTAssertEqual(frame.center.longitude, observer.longitude, accuracy: 1e-9)
        XCTAssertEqual(frame.radiusMiles, 20)
        // 44 miles of latitude, and the same ground distance east–west at Atlanta's latitude.
        XCTAssertEqual(frame.latitudeDelta * TrafficMapGeometry.milesPerDegreeLatitude, 44, accuracy: 0.01)
        let eastEdge = CLLocationCoordinate2D(latitude: observer.latitude, longitude: observer.longitude + frame.longitudeDelta / 2)
        XCTAssertEqual(GeoMath.distanceMiles(from: observer, to: eastEdge), 22, accuracy: 0.1)
    }

    func testFrameIgnoresExtraPointsInsideTheRing() {
        let inside = GeoMath.destination(from: observer, bearingDegrees: 45, distanceMiles: 12)
        XCTAssertEqual(TrafficMapGeometry.frame(observer: observer, radiusMiles: 20, extra: [inside]),
                       TrafficMapGeometry.frame(observer: observer, radiusMiles: 20))
    }

    func testFrameWidensToHoldAPinnedAircraftOutsideTheRing() {
        let far = GeoMath.destination(from: observer, bearingDegrees: 90, distanceMiles: 40)
        let frame = TrafficMapGeometry.frame(observer: observer, radiusMiles: 20, extra: [far], padding: 1)
        // Spans from the ring's west edge (20 mi W) to the aircraft (40 mi E): 60 mi across.
        XCTAssertEqual(frame.radiusMiles, 30, accuracy: 0.01)
        XCTAssertEqual(GeoMath.distanceMiles(from: observer, to: frame.center), 10, accuracy: 0.05)
        XCTAssertEqual(GeoMath.bearing(from: observer, to: frame.center), 90, accuracy: 0.5)
        XCTAssertTrue(frame.encloses(far, margin: 1.001))
        let westEdge = GeoMath.destination(from: observer, bearingDegrees: 270, distanceMiles: 20)
        XCTAssertTrue(frame.encloses(westEdge, margin: 1.001))
    }

    func testFittingFramesTheShortWayAcrossTheDateLine() {
        let tokyo = CLLocationCoordinate2D(latitude: 35.55, longitude: 139.78)
        let sfo = CLLocationCoordinate2D(latitude: 37.62, longitude: -122.38)
        let frame = TrafficMapGeometry.frame(fitting: [tokyo, sfo], padding: 1, minimumSpan: 0.5)
        XCTAssertEqual(frame.longitudeDelta, 360 - 139.78 - 122.38, accuracy: 0.01)
        XCTAssertGreaterThan(abs(frame.center.longitude), 170)
    }

    func testFittingHonoursTheMinimumSpan() {
        let frame = TrafficMapGeometry.frame(fitting: [observer], padding: 1.6, minimumSpan: 0.05)
        XCTAssertEqual(frame.latitudeDelta, 0.05)
        XCTAssertEqual(frame.longitudeDelta, 0.05)
    }

    // MARK: Trails

    private func point(minutesAgo: Double, now: Date, east miles: Double) -> RadarModel.TrailPoint {
        let c = GeoMath.destination(from: observer, bearingDegrees: 90, distanceMiles: miles)
        return RadarModel.TrailPoint(latitude: c.latitude, longitude: c.longitude, altitudeFeet: 10_000,
                                     time: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testTrailSplitsByAgeOldestFirstAndJoinsUp() {
        let now = Date()
        let trail = [20.0, 14, 12, 8, 6, 4, 2, 0].enumerated().map { point(minutesAgo: $1, now: now, east: Double($0)) }
        let segments = TrafficMapGeometry.segments(trail, now: now)
        XCTAssertEqual(segments.map(\.opacity), [0.25, 0.5, 0.9])
        // The 20-minute point is dropped; 14 and 12 are the faint tail, ending where the next begins.
        XCTAssertEqual(segments[0].coordinates.count, 3)
        XCTAssertEqual(segments[1].coordinates.count, 3)
        XCTAssertEqual(segments[2].coordinates.count, 3)
        XCTAssertEqual(segments[0].coordinates.last?.latitude, segments[1].coordinates.first?.latitude)
        XCTAssertEqual(segments[1].coordinates.last?.longitude, segments[2].coordinates.first?.longitude)
        XCTAssertEqual(segments[2].coordinates.last?.longitude ?? 0, trail.last!.longitude, accuracy: 1e-12)
    }

    func testTrailWithOnePointDrawsNothing() {
        let now = Date()
        XCTAssertTrue(TrafficMapGeometry.segments([point(minutesAgo: 1, now: now, east: 1)], now: now).isEmpty)
        XCTAssertTrue(TrafficMapGeometry.segments([], now: now).isEmpty)
    }

    func testRecentTrailIsOneBrightSegment() {
        let now = Date()
        let trail = [3.0, 2, 1, 0].enumerated().map { point(minutesAgo: $1, now: now, east: Double($0)) }
        let segments = TrafficMapGeometry.segments(trail, now: now)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].opacity, 0.9)
        XCTAssertEqual(segments[0].coordinates.count, 4)
    }

    // MARK: Airports

    func testOnlyOriginsAndDestinationsInsideTheBoundsGetAPin() {
        var inbound = TestTraffic.flight("a", miles: 5)
        inbound.originIATA = "SFO"
        inbound.destinationIATA = "ATL"
        var shuttle = TestTraffic.flight("b", miles: 8)
        shuttle.originIATA = "atl"
        shuttle.destinationIATA = "PDK"
        let bounds = TrafficMapGeometry.frame(observer: observer, radiusMiles: 20).bounds
        let airports = TrafficMapGeometry.relevantAirports(for: [inbound, shuttle, TestTraffic.flight("c", miles: 3)], in: bounds)
        // SFO is far away; ATL appears once although two flights use it.
        XCTAssertEqual(airports.map(\.iata), ["ATL", "PDK"])
    }

    // MARK: Model

    @MainActor
    func testTrailVersionMovesWithTheFeedNotTheTick() async {
        let settings = RadarSettings(defaults: UserDefaults(suiteName: "TrafficMapGeometryTests-\(UUID().uuidString)")!)
        let feed = StubFeed()
        let model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.setObserver(observer)
        feed.flights = [TestTraffic.flight("a", miles: 5, speed: 300)]
        let before = model.trailVersion
        await model.pollOnce()
        XCTAssertEqual(model.trailVersion, before + 1)
        model.advanceClock(to: Date().addingTimeInterval(1))
        model.recompute()
        XCTAssertEqual(model.trailVersion, before + 1)
    }

    // MARK: Settings

    @MainActor
    func testMapSettingsPersistAndTheTVFallsBackToTheRadarWhenTheMapIsOff() {
        let defaults = UserDefaults(suiteName: "TrafficMapGeometryTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        XCTAssertTrue(settings.mapView)
        XCTAssertEqual(settings.tvView, .radar)
        XCTAssertFalse(settings.mapNorthUp)

        settings.tvView = .map
        settings.mapNorthUp = true
        let reloaded = RadarSettings(defaults: defaults)
        XCTAssertEqual(reloaded.tvView, .map)
        XCTAssertEqual(reloaded.effectiveTVView, .map)
        XCTAssertTrue(reloaded.mapNorthUp)

        reloaded.mapView = false
        XCTAssertEqual(RadarSettings(defaults: defaults).effectiveTVView, .radar)

        reloaded.resetToDefaults()
        XCTAssertTrue(reloaded.mapView)
        XCTAssertEqual(reloaded.tvView, .radar)
        XCTAssertFalse(reloaded.mapNorthUp)
    }

    func testMapLabelReadsNameOperatorDistanceAndAltitude() {
        let contact = TestTraffic.contacts([TestTraffic.flight("dl570", miles: 3, bearing: 45)])[0]
        let label = SpokenTraffic.mapLabel(for: contact)
        XCTAssertTrue(label.hasPrefix("DL570, "), label)
        XCTAssertTrue(label.hasSuffix(", 3 miles northeast, 10,000 feet"), label)
    }
}
