//
//  PerformanceTests.swift
//  WhatTheFlightTests
//
//  The caches behind the radar's per-tick work: flight profiles, perimeter track samples,
//  the logbook's airframe index, and adaptive polling.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

private func flight(_ id: String, miles: Double = 3, squawk: String? = nil, type: String = "B738",
                    registration: String? = nil, hex: String? = nil, callsign: String? = nil,
                    airline: String? = nil) -> Flight {
    var f = TestTraffic.flight(id, miles: miles, type: type)
    f.squawk = squawk
    f.registration = registration
    f.hex = hex
    f.callsign = callsign
    f.airlineICAO = airline
    return f
}

// MARK: - Flight profiles

@MainActor
final class FlightProfileTests: XCTestCase {
    func testProfileMatchesTheFlightsOwnLookups() {
        let flights = [
            flight("dl", callsign: "DAL570", airline: "DAL"),
            flight("ga", type: "C172", registration: "N5404T", callsign: "N5404T"),
            flight("mil", type: "C17", callsign: "RCH123"),
            flight("sq", squawk: "7700", callsign: "UAL1"),
            flight("heli", type: "EC35", callsign: "LIFE2"),
        ]
        for f in flights {
            let p = FlightProfile(f)
            XCTAssertEqual(p.operatorInfo, f.operatorInfo, f.id)
            XCTAssertEqual(p.notable, f.notable, f.id)
            XCTAssertEqual(p.kind, f.kind, f.id)
            XCTAssertEqual(p.silhouette, f.silhouette, f.id)
            XCTAssertEqual(p.typeName, f.typeName, f.id)
            XCTAssertEqual(p.airline, f.airline, f.id)
        }
    }

    func testContactUsesAPassedProfileOnlyWhileItIsCurrent() {
        let quiet = flight("a", squawk: "1200", callsign: "UAL1")
        let profile = FlightProfile(quiet)
        var moved = quiet
        moved.latitude += 0.01
        XCTAssertTrue(profile.isCurrent(for: moved), "position changes don't change who it is")

        var emergency = quiet
        emergency.squawk = "7700"
        XCTAssertFalse(profile.isCurrent(for: emergency))
        let contact = RadarContact(flight: emergency, observer: TestTraffic.observer, at: Date(), profile: profile)
        XCTAssertEqual(contact.profile.notable.first?.tag, .emergency, "a stale profile is rebuilt")
    }

    func testModelPicksUpASquawkChangeOnTheNextFeed() async {
        let defaults = UserDefaults(suiteName: "FlightProfileTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        settings.radiusMiles = 20
        let feed = StubFeed()
        let model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.setObserver(TestTraffic.observer)

        feed.flights = [flight("a", squawk: "1200", callsign: "UAL1")]
        await model.pollOnce()
        XCTAssertEqual(model.contacts.first?.profile.notable, [])

        model.advanceClock(to: Date().addingTimeInterval(1))
        XCTAssertEqual(model.contacts.first?.profile.notable, [], "ticks keep the profile")

        feed.flights = [flight("a", squawk: "7700", callsign: "UAL1")]
        await model.pollOnce()
        XCTAssertEqual(model.contacts.first?.profile.notable.first?.tag, .emergency)
    }

    func testProjectedSnapshotsCarryProfiles() {
        let flights = [flight("a", miles: 2, type: "A388", callsign: "UAE1")]
        let snapshots = NearbyTraffic.projectedSnapshots(flights, observer: TestTraffic.observer, radiusMiles: 10,
                                                         placeName: nil, start: Date(), count: 3, step: 60)
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertTrue(snapshots.allSatisfy { $0.flights.first?.notableTag == .rare })
    }
}

// MARK: - Perimeter track samples

final class PerimeterTrackCacheTests: XCTestCase {
    func testSamplesAreBuiltOncePerRect() {
        // An odd size no other test uses.
        let rect = CGRect(x: 0, y: 0, width: 311.25, height: 677.5)
        let before = PerimeterTrack.sampleBuilds
        let first = PerimeterTrack(rect: rect, cornerRadius: 33)
        let second = PerimeterTrack(rect: rect, cornerRadius: 33)
        XCTAssertEqual(PerimeterTrack.sampleBuilds, before + 1)
        for angle in stride(from: 0.0, to: 360, by: 7.5) {
            XCTAssertEqual(first.arcLength(forScreenAngle: angle), second.arcLength(forScreenAngle: angle))
        }

        _ = PerimeterTrack(rect: rect, cornerRadius: 34)
        XCTAssertEqual(PerimeterTrack.sampleBuilds, before + 2, "a different corner is a different track")
    }
}

// MARK: - Logbook airframe index

@MainActor
final class LogbookAirframeIndexTests: XCTestCase {
    private func contact(_ f: Flight, at date: Date) -> RadarContact {
        RadarContact(flight: f, observer: TestTraffic.observer, at: date)
    }

    func testCountsAndHistoryFollowNewVisits() {
        let book = Logbook(fileURL: nil)
        let t0 = Date()
        book.record([contact(flight("leg1", registration: "N1DL"), at: t0)], at: t0)
        book.record([contact(flight("other", registration: "N2DL"), at: t0)], at: t0.addingTimeInterval(10))
        book.record([contact(flight("leg2", registration: "N1DL"), at: t0)], at: t0.addingTimeInterval(20))

        XCTAssertEqual(book.timesSeen(airframe: "N1DL"), 2)
        XCTAssertEqual(book.history(airframe: "N1DL").map(\.id), ["leg2", "leg1"], "newest first")
        XCTAssertEqual(book.firstSighting(airframe: "N1DL")?.id, "leg1")
        XCTAssertEqual(book.summary(airframe: "N2DL").count, 1)
        XCTAssertEqual(book.timesSeen(airframe: "N9XX"), 0)
        XCTAssertEqual(book.seenBeforeSummary(for: flight("leg2", registration: "N1DL"))?.hasPrefix("Seen once before"), true)
    }

    func testDeletingAndTrimmingKeepTheIndexRight() {
        let book = Logbook(fileURL: nil, maxEntries: 3)
        let t0 = Date()
        for i in 0..<4 {
            let f = flight("leg\(i)", registration: i.isMultiple(of: 2) ? "N1DL" : "N2DL")
            book.record([contact(f, at: t0)], at: t0.addingTimeInterval(Double(i)))
        }
        // leg0 was trimmed.
        XCTAssertEqual(book.history(airframe: "N1DL").map(\.id), ["leg2"])
        XCTAssertEqual(book.history(airframe: "N2DL").map(\.id), ["leg3", "leg1"])
        book.delete(["leg3"])
        XCTAssertEqual(book.history(airframe: "N2DL").map(\.id), ["leg1"])
    }

    func testAMergeThatFillsInTheRegistrationMovesTheSighting() {
        let t0 = Date()
        let local = Logbook(fileURL: nil, device: .iPhone)
        local.record([contact(flight("x", hex: "A1B2C3"), at: t0)], at: t0)
        XCTAssertEqual(local.timesSeen(airframe: "A1B2C3"), 1)

        let remote = Logbook(fileURL: nil, device: .appleTV)
        remote.record([contact(flight("x", registration: "N1DL", hex: "A1B2C3"), at: t0)], at: t0)
        local.merge(remote: remote.sightings)

        XCTAssertEqual(local.timesSeen(airframe: "N1DL"), 1)
        XCTAssertEqual(local.timesSeen(airframe: "A1B2C3"), 0)
    }
}

// MARK: - Adaptive polling

final class PollingPolicyTests: XCTestCase {
    private func contacts(_ flights: [Flight]) -> [RadarContact] {
        flights.map { RadarContact(flight: $0, observer: TestTraffic.observer, at: Date()) }
    }

    func testPollsFasterWhileSomethingIsPassingClose() {
        let overhead = contacts([TestTraffic.flight("a", miles: 0.5)])
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: overhead, outside: []), 5)

        // 3 mi out, heading straight for us at 300 kt: over the top in about 30 s.
        let inbound = contacts([TestTraffic.flight("b", miles: 3, bearing: 0, track: 180, speed: 300)])
        XCTAssertTrue(PollingPolicy.isPassingClose(inbound[0]))
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: inbound, outside: []), 5)
    }

    func testKeepsTheSettingForOrdinaryTraffic() {
        // Inbound, but more than 90 s away.
        let distant = contacts([TestTraffic.flight("a", miles: 18, bearing: 0, track: 180, speed: 300)])
        XCTAssertFalse(PollingPolicy.isPassingClose(distant[0]))
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: distant, outside: []), 10)

        // Passing 4 mi abeam soon still isn't overhead.
        let abeam = contacts([TestTraffic.flight("b", miles: 4, bearing: 90, track: 0, speed: 300)])
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: abeam, outside: []), 10)

        let onlyOutside = contacts([TestTraffic.flight("c", miles: 30)])
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: [], outside: onlyOutside), 10)
    }

    func testSlowsDownWhenTheSkyIsEmpty() {
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: [], outside: []), 30)
        XCTAssertEqual(PollingPolicy.interval(base: 30, contacts: [], outside: []), 60, "capped at a minute")
    }

    func testTheFloorWins() {
        let overhead = contacts([TestTraffic.flight("a", miles: 0.5)])
        XCTAssertEqual(PollingPolicy.interval(base: 10, contacts: overhead, outside: [], floor: 10), 10)
    }
}

@MainActor
final class AdaptivePollingModelTests: XCTestCase {
    func testPollOnceReturnsTheAdaptiveInterval() async {
        let defaults = UserDefaults(suiteName: "AdaptivePollingModelTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        settings.radiusMiles = 20
        settings.refreshSeconds = 10
        let feed = StubFeed()
        let model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.setObserver(TestTraffic.observer)

        feed.flights = []
        let empty = await model.pollOnce()
        XCTAssertEqual(empty, 30)

        feed.flights = [TestTraffic.flight("a", miles: 0.4)]
        let overhead = await model.pollOnce()
        XCTAssertEqual(overhead, 5)

        feed.flights = [TestTraffic.flight("a", miles: 8)]
        let ordinary = await model.pollOnce()
        XCTAssertEqual(ordinary, 10)
    }
}
