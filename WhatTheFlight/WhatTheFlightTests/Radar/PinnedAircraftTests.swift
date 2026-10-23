//
//  PinnedAircraftTests.swift
//  WhatTheFlightTests
//
//  Pinning: aircraft followed wherever they are, found by worldwide search.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

/// A feed with a local box and a "rest of the world" for search and pin lookups.
final class WorldFeed: FlightFeed, @unchecked Sendable {
    var local: [Flight] = []
    var world: [Flight] = []
    private(set) var lookups: [[String]] = []

    func flights(in bounds: GeographicBounds) async throws -> [Flight] { local }

    func search(_ query: String) async throws -> [Flight] {
        (local + world).filter { f in [f.registration, f.flightNumber, f.callsign].contains { $0?.hasPrefix(query) == true } }
    }

    func lookup(registrations: [String], callsigns: [String]) async throws -> [Flight] {
        lookups.append(registrations + callsigns)
        return world.filter { f in
            registrations.contains { f.registration?.hasPrefix($0) == true } || callsigns.contains { f.callsign?.hasPrefix($0) == true }
        }
    }
}

final class PinnedAircraftTests: XCTestCase {
    func testTailNumbersTypedWithoutTheirHyphen() {
        XCTAssertTrue(RegistrationCountry.hyphenatedForms(of: "GXLEI").contains("G-XLEI"))
        XCTAssertTrue(RegistrationCountry.hyphenatedForms(of: "a6eui").contains("A6-EUI"))
        XCTAssertEqual(RegistrationCountry.hyphenatedForms(of: "N509DN"), [], "US tail numbers have no hyphen")
        XCTAssertEqual(RegistrationCountry.hyphenatedForms(of: "G-XLEI"), [])
    }

    func testAPinFollowsTheAirframeOntoItsNextLeg() {
        var first = TestTraffic.flight("leg1", miles: 5)
        first.registration = "N509DN"
        var second = TestTraffic.flight("leg2", miles: 500)
        second.registration = "N509DN"
        var other = TestTraffic.flight("other", miles: 5)
        other.registration = "N509DZ"
        let pin = PinnedAircraft(first)
        XCTAssertTrue(pin.matches(second))
        XCTAssertFalse(pin.matches(other))
    }

    func testTheMapFollowsAFarPinOnItsOwn() {
        let home = TestTraffic.observer
        let near = GeoMath.destination(from: home, bearingDegrees: 45, distanceMiles: 80)
        let far = GeoMath.destination(from: home, bearingDegrees: 45, distanceMiles: 2_000)
        XCTAssertFalse(TrafficMapGeometry.followsPinnedAlone(observer: home, aircraft: near, radiusMiles: 20))
        XCTAssertTrue(TrafficMapGeometry.followsPinnedAlone(observer: home, aircraft: far, radiusMiles: 20))
    }
}

@MainActor
final class PinnedRadarModelTests: XCTestCase {
    var defaults: UserDefaults!
    var settings: RadarSettings!
    var feed: WorldFeed!
    var model: RadarModel!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "PinnedRadarModelTests-\(UUID().uuidString)")
        settings = RadarSettings(defaults: defaults)
        settings.radiusMiles = 20
        feed = WorldFeed()
        model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.setObserver(TestTraffic.observer)
    }

    private func far(_ id: String = "far", registration: String = "G-XLEI", miles: Double = 900) -> Flight {
        var f = TestTraffic.flight(id, miles: miles, bearing: 45)
        f.registration = registration
        return f
    }

    func testAFarAwayPinIsLookedUpAndRidesTheRadarEdge() async {
        feed.local = [TestTraffic.flight("near", miles: 2)]
        feed.world = [far()]
        await model.pollOnce()
        model.pin(far())

        await model.pollOnce()
        XCTAssertEqual(feed.lookups.last, ["G-XLEI"])
        XCTAssertEqual(model.contacts.map(\.id), ["near"])
        XCTAssertEqual(model.pinnedOutside.map(\.id), ["far"])
        XCTAssertEqual(model.perimeterContacts.map(\.id), ["far", "near"])

        // Between lookups it's dead-reckoned from the last one rather than dropped.
        await model.pollOnce()
        XCTAssertEqual(feed.lookups.count, 1)
        XCTAssertEqual(model.pinnedOutside.map(\.id), ["far"])
    }

    func testAPinnedFocusHoldsAndUnpinningHandsTheCentreBackQuietly() async {
        feed.local = [TestTraffic.flight("near", miles: 2)]
        feed.world = [far()]
        await model.pollOnce()
        XCTAssertTrue(model.track(far()))
        XCTAssertEqual(model.focus, RadarFocus(focusedID: "far", isPinned: true))

        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "far")

        model.togglePin()
        XCTAssertEqual(model.focus, RadarFocus(focusedID: "near", isPinned: false))
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.pins.isEmpty)
    }

    func testSwipingOutwardsReachesFarAwayPins() async {
        feed.local = [TestTraffic.flight("a", miles: 1), TestTraffic.flight("b", miles: 3)]
        await model.pollOnce()
        model.pin(far())
        model.focusNext()
        model.focusNext()
        XCTAssertEqual(model.focus.focusedID, "far")
        XCTAssertTrue(model.focus.isPinned)
    }

    func testANewLegKeepsThePin() async {
        model.pin(far("old"))
        feed.world = [far("new")]
        await model.pollOnce()
        XCTAssertEqual(model.pins.map(\.flightID), ["new"])
        XCTAssertTrue(model.isPinned("new"))
        XCTAssertEqual(model.pinnedOutside.map(\.id), ["new"])
    }

    func testPinsAreRememberedAndCapped() {
        for i in 0..<(RadarModel.maxPins + 2) { model.pin(far("f\(i)", registration: "N\(i + 1)AB")) }
        XCTAssertEqual(model.pins.count, RadarModel.maxPins)
        XCTAssertEqual(model.pins.first?.flightID, "f2", "the oldest make way")
        XCTAssertEqual(RadarModel.maxPins, 5)
        XCTAssertEqual(model.notice?.text, "f0".uppercased() + " unpinned to make room · 5 pins max")
        XCTAssertEqual(RadarSettings(defaults: defaults).pinnedAircraft, model.pins)
    }

    func testAParkedPinIsKeptButNotDrawn() async {
        var parked = far()
        parked.isOnGround = true
        feed.world = [parked]
        XCTAssertFalse(model.track(parked))
        await model.pollOnce()
        XCTAssertTrue(model.pinnedOutside.isEmpty)
        guard case .onGround = model.state(of: model.pins[0]) else { return XCTFail("expected on the ground") }
    }

    func testWorldwideSearchPutsExactMatchesFirst() async throws {
        func flight(_ id: String, number: String, miles: Double) -> Flight {
            var f = TestTraffic.flight(id, miles: miles)
            f.flightNumber = number
            return f
        }
        feed.world = [flight("x1", number: "DL1274", miles: 50), flight("x2", number: "DL121", miles: 2_000), flight("x3", number: "DL1219", miles: 10)]
        let results = try await model.searchAnywhere("dl121")
        XCTAssertEqual(results.map(\.id), ["x2", "x3"])
        let short = try await model.searchAnywhere("DL")
        XCTAssertTrue(short.isEmpty, "too short to send")
    }
}
