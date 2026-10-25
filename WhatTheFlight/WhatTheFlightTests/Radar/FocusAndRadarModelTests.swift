//
//  FocusAndRadarModelTests.swift
//  WhatTheFlightTests
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

/// Builds flights at a given distance / bearing from an observer.
enum TestTraffic {
    static let observer = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)

    static func flight(_ id: String, miles: Double, bearing: Double = 0, track: Double = 90, speed: Int = 0,
                       type: String = "B738", ground: Bool = false, at date: Date = Date()) -> Flight {
        let p = GeoMath.destination(from: observer, bearingDegrees: bearing, distanceMiles: miles)
        return Flight(id: id, hex: nil, latitude: p.latitude, longitude: p.longitude, track: track,
                      altitudeFeet: 10_000, groundSpeedKnots: speed, verticalRateFPM: 0, squawk: nil,
                      typeCode: type, registration: nil, originIATA: nil, destinationIATA: nil,
                      flightNumber: id.uppercased(), callsign: nil, airlineICAO: nil, isOnGround: ground,
                      positionTime: date)
    }

    static func contacts(_ flights: [Flight], radius: Double = 20) -> [RadarContact] {
        flights.map { RadarContact(flight: $0, observer: observer, at: Date()) }
            .filter { $0.distanceMiles <= radius }
            .sorted { $0.distanceMiles < $1.distanceMiles }
    }
}

final class FocusPolicyTests: XCTestCase {
    func testFirstFocusIsNearest() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("far", miles: 9), TestTraffic.flight("near", miles: 2)])
        let (state, change) = FocusPolicy.resolve(RadarFocus(), inRange: inRange, available: ["far", "near"])
        XCTAssertEqual(state.focusedID, "near")
        XCTAssertEqual(change, .initial)
    }

    func testFocusIsStickyWhileInRangeEvenIfSomethingCloserAppears() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("current", miles: 8), TestTraffic.flight("closer", miles: 1)])
        let (state, change) = FocusPolicy.resolve(RadarFocus(focusedID: "current"), inRange: inRange, available: ["current", "closer"])
        XCTAssertEqual(state.focusedID, "current")
        XCTAssertEqual(change, .none)
    }

    func testLeavingTheRadiusHandsOverToTheNearest() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("b", miles: 5), TestTraffic.flight("a", miles: 3)])
        let (state, change) = FocusPolicy.resolve(RadarFocus(focusedID: "gone"), inRange: inRange, available: ["a", "b", "gone"])
        XCTAssertEqual(state.focusedID, "a")
        XCTAssertEqual(change, .leftRange(previous: "gone"))
    }

    func testDisappearingFromTheFeedIsReportedAsLost() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 3)])
        let (_, change) = FocusPolicy.resolve(RadarFocus(focusedID: "gone"), inRange: inRange, available: ["a"])
        XCTAssertEqual(change, .lost(previous: "gone"))
    }

    func testPinnedAircraftSurvivesOutsideTheRadius() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 3)])
        let pinned = RadarFocus(focusedID: "outside", isPinned: true)
        let (state, change) = FocusPolicy.resolve(pinned, inRange: inRange, available: ["a", "outside"])
        XCTAssertEqual(state, pinned)
        XCTAssertEqual(change, .none)
    }

    func testPinnedAircraftIsReleasedWhenTheFeedLosesIt() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 3)])
        let (state, _) = FocusPolicy.resolve(RadarFocus(focusedID: "outside", isPinned: true), inRange: inRange, available: ["a"])
        XCTAssertEqual(state, RadarFocus(focusedID: "a", isPinned: false))
    }

    func testHeldAircraftKeepsTheCentreWhileTheMapStillDrawsIt() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 3)])
        let held = RadarFocus(focusedID: "outside", isHeld: true)
        let (state, change) = FocusPolicy.resolve(held, inRange: inRange, nearby: ["outside"], available: ["a", "outside"])
        XCTAssertEqual(state, held)
        XCTAssertEqual(change, .none)
    }

    func testHeldAircraftIsReleasedPastTheFringe() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 3)])
        let held = RadarFocus(focusedID: "outside", isHeld: true)
        let (state, change) = FocusPolicy.resolve(held, inRange: inRange, nearby: [], available: ["a", "outside"])
        XCTAssertEqual(state, RadarFocus(focusedID: "a"))
        XCTAssertEqual(change, .leftRange(previous: "outside"))
    }

    func testHeldAircraftFlyingIntoTheRadiusBecomesAnOrdinaryFocus() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 3), TestTraffic.flight("held", miles: 9)])
        let (state, change) = FocusPolicy.resolve(RadarFocus(focusedID: "held", isHeld: true), inRange: inRange,
                                                  nearby: [], available: ["a", "held"])
        XCTAssertEqual(state, RadarFocus(focusedID: "held"))
        XCTAssertEqual(change, .none)
    }

    func testNextWrapsAround() {
        let inRange = TestTraffic.contacts([TestTraffic.flight("a", miles: 1), TestTraffic.flight("b", miles: 2), TestTraffic.flight("c", miles: 3)])
        XCTAssertEqual(FocusPolicy.next(after: RadarFocus(focusedID: "a"), inRange: inRange).focusedID, "b")
        XCTAssertEqual(FocusPolicy.next(after: RadarFocus(focusedID: "c"), inRange: inRange).focusedID, "a")
        XCTAssertEqual(FocusPolicy.next(after: RadarFocus(focusedID: "zzz"), inRange: inRange).focusedID, "a")
    }
}

/// Feed that returns whatever the test sets.
final class StubFeed: FlightFeed, @unchecked Sendable {
    var flights: [Flight] = []
    var error: Error?
    private(set) var requests: [GeographicBounds] = []

    func flights(in bounds: GeographicBounds) async throws -> [Flight] {
        requests.append(bounds)
        if let error { throw error }
        return flights
    }
}

@MainActor
final class RadarModelTests: XCTestCase {
    var defaults: UserDefaults!
    var settings: RadarSettings!
    var feed: StubFeed!
    var model: RadarModel!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "RadarModelTests-\(UUID().uuidString)")
        settings = RadarSettings(defaults: defaults)
        settings.radiusMiles = 20
        feed = StubFeed()
        model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.isLowPowerMode = { false }
        model.setObserver(TestTraffic.observer)
    }

    func testPollFiltersByRadiusSortsAndFocusesNearest() async {
        feed.flights = [
            TestTraffic.flight("mid", miles: 8, bearing: 90),
            TestTraffic.flight("near", miles: 2, bearing: 200),
            TestTraffic.flight("out", miles: 26, bearing: 10),
        ]
        let delay = await model.pollOnce()
        XCTAssertEqual(delay, 7, accuracy: 0.01, "the nearest is 2 mi away")
        XCTAssertEqual(model.status, .live)
        XCTAssertEqual(model.contacts.map(\.id), ["near", "mid"])
        XCTAssertEqual(model.outsideContacts.map(\.id), ["out"])
        XCTAssertEqual(model.focus.focusedID, "near")
        XCTAssertEqual(model.contacts.first?.bearing ?? 0, 200, accuracy: 0.5)
    }

    func testStaleWhenTheFeedFailsOrGoesQuiet() async {
        feed.flights = [TestTraffic.flight("a", miles: 2)]
        XCTAssertFalse(model.isStale) // nothing loaded yet: nothing to be stale
        await model.pollOnce()
        XCTAssertFalse(model.isStale)
        XCTAssertEqual(model.sinceLastUpdate, 0, accuracy: 1)

        model.advanceClock(to: Date().addingTimeInterval(RadarModel.staleAfter + 1))
        XCTAssertTrue(model.isStale)
        XCTAssertGreaterThan(model.sinceLastUpdate, RadarModel.staleAfter)
        XCTAssertEqual(model.contacts.map(\.id), ["a"]) // still shown, dead-reckoned

        feed.error = FeedError.rateLimited
        await model.pollOnce()
        XCTAssertTrue(model.isStale) // a failed poll says so at once
        feed.error = nil
        await model.pollOnce()
        XCTAssertFalse(model.isStale)
    }

    func testRestartGetsAGraceBeforeCountingAsStale() async {
        feed.flights = [TestTraffic.flight("a", miles: 2)]
        await model.pollOnce()
        model.advanceClock(to: Date().addingTimeInterval(RadarModel.staleAfter + 1))
        XCTAssertTrue(model.isStale)
        // Wrist raised: the model restarts and a poll is on its way.
        model.start()
        model.advanceClock(to: Date().addingTimeInterval(10))
        XCTAssertFalse(model.isStale)
        model.stop()
    }

    func testLogsLiveTrafficWithWhereItPassed() async {
        let book = Logbook(fileURL: nil)
        model.logbook = book
        settings.locationMode = .device
        feed.flights = [TestTraffic.flight("near", miles: 2, bearing: 200)]
        await model.pollOnce()
        let sighting = try? XCTUnwrap(book.sightings.first)
        XCTAssertEqual(book.sightings.map(\.id), ["near"])
        XCTAssertNotNil(sighting?.closestCoordinate)
        XCTAssertEqual(sighting?.observerCoordinate?.latitude ?? 0, TestTraffic.observer.latitude, accuracy: 1e-9)
    }

    func testDemoTrafficAndCustomSpotsAreNotLogged() async {
        let book = Logbook(fileURL: nil)
        model.logbook = book
        feed.flights = [TestTraffic.flight("near", miles: 2)]

        settings.locationMode = .device
        settings.demoTraffic = true
        await model.pollOnce()
        XCTAssertTrue(book.isEmpty, "demo traffic")

        settings.demoTraffic = false
        settings.locationMode = .custom
        await model.pollOnce()
        XCTAssertTrue(book.isEmpty, "browsing a custom spot on the iPhone")

        // The Apple TV's set place is where it really is.
        model.logsCustomSpot = true
        await model.pollOnce()
        XCTAssertEqual(book.sightings.count, 1)
    }

    func testQueryBoxReachesBeyondTheRadius() async {
        await model.pollOnce()
        let bounds = try? XCTUnwrap(feed.requests.last)
        let north = CLLocationCoordinate2D(latitude: bounds?.northLatitude ?? 0, longitude: TestTraffic.observer.longitude)
        XCTAssertGreaterThan(GeoMath.distanceMiles(from: TestTraffic.observer, to: north), settings.radiusMiles)
    }

    func testGroundTrafficAndOptionalHelicoptersAreHidden() async {
        feed.flights = [
            TestTraffic.flight("parked", miles: 1, ground: true),
            TestTraffic.flight("heli", miles: 2, type: "EC45"),
            TestTraffic.flight("jet", miles: 3),
        ]
        await model.pollOnce()
        XCTAssertEqual(model.contacts.map(\.id), ["heli", "jet"])

        settings.showHelicopters = false
        model.settingsDidChange(refetch: false)
        XCTAssertEqual(model.contacts.map(\.id), ["jet"])
    }

    func testFocusStaysPutUntilTheAircraftLeavesThenNotices() async {
        feed.flights = [TestTraffic.flight("first", miles: 3), TestTraffic.flight("second", miles: 6, bearing: 180)]
        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "first")

        // Something closer shows up — the centre doesn't jump.
        feed.flights.append(TestTraffic.flight("closer", miles: 1, bearing: 90))
        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "first")
        XCTAssertNil(model.notice)

        // "first" flies out of the radius → nearest takes over, with a notice.
        feed.flights[0] = TestTraffic.flight("first", miles: 25)
        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "closer")
        XCTAssertNotNil(model.notice)
    }

    func testSwipeActions() async {
        feed.flights = [TestTraffic.flight("a", miles: 1), TestTraffic.flight("b", miles: 2, bearing: 90), TestTraffic.flight("c", miles: 3, bearing: 180)]
        await model.pollOnce()
        model.focusNext()
        XCTAssertEqual(model.focus.focusedID, "b")
        model.focusNext()
        XCTAssertEqual(model.focus.focusedID, "c")
        model.focusNearest()
        XCTAssertEqual(model.focus.focusedID, "a")
    }

    func testFocusNeighboursAreWhereTheRemoteStepsNext() async {
        feed.flights = [TestTraffic.flight("a", miles: 1), TestTraffic.flight("b", miles: 2, bearing: 90), TestTraffic.flight("c", miles: 3, bearing: 180)]
        await model.pollOnce()
        // On the nearest ◀ goes nowhere, so only ▶'s aircraft.
        XCTAssertEqual(model.focusNeighbours.map(\.id), ["b"])
        model.focusNext()
        XCTAssertEqual(Set(model.focusNeighbours.map(\.id)), ["a", "c"])
        model.focusNext()
        // On the farthest ▶ wraps round to the nearest.
        XCTAssertEqual(Set(model.focusNeighbours.map(\.id)), ["b", "a"])
    }

    func testFocusingAnOutOfRangeAircraftPinsIt() async {
        feed.flights = [TestTraffic.flight("in", miles: 2), TestTraffic.flight("out", miles: 25)]
        await model.pollOnce()
        model.focus(on: "out")
        XCTAssertTrue(model.focus.isPinned)
        model.recompute()
        XCTAssertEqual(model.focus.focusedID, "out")
        XCTAssertEqual(model.focusedContact?.id, "out")
    }

    func testPickingAnOutOfRangeAircraftOnTheMapHoldsItWithoutPinning() async {
        feed.flights = [TestTraffic.flight("in", miles: 2), TestTraffic.flight("out", miles: 25, bearing: 90)]
        await model.pollOnce()
        model.focus(on: "out", pinning: false)
        XCTAssertFalse(model.focus.isPinned)
        XCTAssertTrue(model.focus.isHeld)
        XCTAssertTrue(settings.pinnedAircraft.isEmpty)
        XCTAssertEqual(model.perimeterContacts.map(\.id), ["out", "in"], "held aircraft ride the radar edge")

        // Still inside the map's fringe (1.5 × 20 mi): it keeps the centre.
        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "out")
        XCTAssertNil(model.notice)

        // Past the fringe the nearest takes over.
        feed.flights[1] = TestTraffic.flight("out", miles: 32, bearing: 90)
        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "in")
        XCTAssertFalse(model.focus.isHeld)
        XCTAssertEqual(model.notice?.text, "OUT flew out of range")
    }

    func testPinningAHeldAircraftDropsTheHold() async {
        feed.flights = [TestTraffic.flight("in", miles: 2), TestTraffic.flight("out", miles: 25, bearing: 90)]
        await model.pollOnce()
        model.focus(on: "out", pinning: false)
        model.togglePin()
        XCTAssertTrue(model.focus.isPinned)
        XCTAssertFalse(model.focus.isHeld)
        XCTAssertEqual(model.perimeterContacts.map(\.id), ["out", "in"], "on the edge once, as a pin")
    }

    func testTappingAnInRangeAircraftOnTheMapIsAnOrdinaryFocus() async {
        feed.flights = [TestTraffic.flight("a", miles: 2), TestTraffic.flight("b", miles: 5, bearing: 90)]
        await model.pollOnce()
        model.focus(on: "b", pinning: false)
        XCTAssertEqual(model.focus, RadarFocus(focusedID: "b"))
    }

    func testErrorsReportStatusAndBackOff() async {
        feed.error = FeedError.rateLimited
        let delay = await model.pollOnce()
        XCTAssertEqual(model.status, .error(FeedError.rateLimited.errorDescription!))
        XCTAssertGreaterThanOrEqual(delay, 30)
    }

    func testJumpingToAFarAwaySpotResetsQuietly() async {
        feed.flights = [TestTraffic.flight("a", miles: 2)]
        await model.pollOnce()
        XCTAssertEqual(model.focus.focusedID, "a")
        model.setObserver(CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781))
        XCTAssertNil(model.focus.focusedID)
        XCTAssertNil(model.notice)
        XCTAssertTrue(model.contacts.isEmpty)
    }

    func testNoObserverMeansNoRequest() async {
        model.setObserver(nil)
        let before = feed.requests.count
        await model.pollOnce()
        XCTAssertEqual(feed.requests.count, before)
        XCTAssertTrue(model.contacts.isEmpty)
    }

    func testDeadReckoningMovesContactsBetweenPolls() {
        let start = Date()
        let flight = TestTraffic.flight("mover", miles: 10, bearing: 0, track: 180, speed: 360, at: start)
        let now = RadarContact(flight: flight, observer: TestTraffic.observer, at: start)
        let later = RadarContact(flight: flight, observer: TestTraffic.observer, at: start.addingTimeInterval(30))
        // 360 kts ≈ 3.45 statute miles in 30 s, flying straight at the observer.
        XCTAssertEqual(now.distanceMiles - later.distanceMiles, 360 * GeoMath.milesPerKnotHour / 120, accuracy: 0.05)
        XCTAssertTrue(later.isApproaching)
    }
}

@MainActor
final class RadarSettingsTests: XCTestCase {
    func testPersistsAndClamps() {
        let defaults = UserDefaults(suiteName: "RadarSettingsTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        settings.radiusMiles = 42
        settings.topography = .off
        settings.customCoordinate = CLLocationCoordinate2D(latitude: 1, longitude: 2)
        let reloaded = RadarSettings(defaults: defaults)
        XCTAssertEqual(reloaded.radiusMiles, 42)
        XCTAssertFalse(reloaded.showTopography)
        XCTAssertEqual(reloaded.customCoordinate?.latitude, 1)

        defaults.set(5000.0, forKey: "wtf.radius")
        XCTAssertEqual(RadarSettings(defaults: defaults).radiusMiles, RadarSettings.radiusRange.upperBound)
    }

    func testTopographyDefaultsToSurveyAtOneTimes() {
        let defaults = UserDefaults(suiteName: "RadarSettingsTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        XCTAssertEqual(settings.topography, .survey)
        XCTAssertEqual(settings.topographyMotion, .normal)
        XCTAssertTrue(settings.showTopography)
    }

    func testTopographyStyleAndMotionPersist() {
        let defaults = UserDefaults(suiteName: "RadarSettingsTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        settings.topography = .highlands
        settings.topographyMotion = .double
        let reloaded = RadarSettings(defaults: defaults)
        XCTAssertEqual(reloaded.topography, .highlands)
        XCTAssertEqual(reloaded.topographyMotion, .double)
        XCTAssertEqual(reloaded.topographyMotion.speed, 2)
    }

    func testOldTopographySwitchCarriesOver() {
        let off = UserDefaults(suiteName: "RadarSettingsTests-\(UUID().uuidString)")!
        off.set(false, forKey: "wtf.showTopography")
        XCTAssertEqual(RadarSettings(defaults: off).topography, .off)

        let on = UserDefaults(suiteName: "RadarSettingsTests-\(UUID().uuidString)")!
        on.set(true, forKey: "wtf.showTopography")
        XCTAssertEqual(RadarSettings(defaults: on).topography, .survey)

        // A style chosen since wins over the old switch.
        off.set("relief", forKey: "wtf.topography")
        XCTAssertEqual(RadarSettings(defaults: off).topography, .relief)
    }

    func testLaunchArgumentStyleStringsAreUnderstood() {
        let defaults = UserDefaults(suiteName: "RadarSettingsTests-\(UUID().uuidString)")!
        defaults.set("YES", forKey: "wtf.demoTraffic")
        defaults.set("25", forKey: "wtf.radius")
        let settings = RadarSettings(defaults: defaults)
        XCTAssertTrue(settings.demoTraffic)
        XCTAssertEqual(settings.radiusMiles, 25)
    }
}
