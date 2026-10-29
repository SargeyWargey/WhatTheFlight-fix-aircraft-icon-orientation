//
//  OpenFeedTests.swift
//  WhatTheFlightTests
//
//  The readsb parser and the Flightradar24 → adsb.lol fallback (Enhancements Spec C1).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class ReadsbParserTests: XCTestCase {
    /// Trimmed from a real adsb.lol point query over Atlanta, 2026-10-26.
    private let sample = """
    {"msg":"No error","now":1793053483001,"total":4,"ctime":1793053483001,"ptime":0,"ac":[
     {"hex":"a7e509","type":"adsb_icao","flight":"DAL1751 ","r":"N608AT","t":"B712","alt_baro":2900,"alt_geom":3200,"gs":175.7,"track":67.23,"baro_rate":-512,"squawk":"5251","category":"A3","lat":33.626816,"lon":-84.625668,"seen_pos":0.155,"seen":0.1},
     {"hex":"a988f0","flight":"BAW29G  ","r":"G-XLEI","t":"A388","alt_baro":36000,"gs":480,"true_heading":91.5,"geom_rate":64,"lat":33.7,"lon":-84.5,"seen_pos":2.5},
     {"hex":"ab1234","flight":"DAL2001","r":"N123DN","t":"A321","alt_baro":"ground","gs":12,"track":10,"lat":33.64,"lon":-84.43,"seen_pos":1},
     {"hex":"~2d1e01","flight":"","alt_baro":1500,"gs":90,"track":180,"seen":3},
     {"hex":"c0ffee","alt_baro":1200,"gs":95,"track":300,"lat":33.8,"lon":-84.3,"seen_pos":0.5,"squawk":"7700"}
    ]}
    """

    private var receivedAt: Date { Date(timeIntervalSince1970: 1793053483.5) }

    func testAirborneAircraftParse() throws {
        let flights = try ReadsbParser.parse(Data(sample.utf8), receivedAt: receivedAt)
        XCTAssertEqual(flights.count, 3, "no ground, no position-less record")
        let delta = try XCTUnwrap(flights.first { $0.registration == "N608AT" })
        XCTAssertEqual(delta.id, "ac-a7e509")
        XCTAssertEqual(delta.hex, "A7E509")
        XCTAssertEqual(delta.callsign, "DAL1751")
        XCTAssertEqual(delta.flightNumber, "DL1751")
        XCTAssertEqual(delta.typeCode, "B712")
        XCTAssertEqual(delta.altitudeFeet, 2900)
        XCTAssertEqual(delta.groundSpeedKnots, 176)
        XCTAssertEqual(delta.verticalRateFPM, -512)
        XCTAssertEqual(delta.track, 67.23, accuracy: 0.001)
        XCTAssertNil(delta.originIATA)
        // The server's clock minus how old the position is.
        XCTAssertEqual(delta.positionTime.timeIntervalSince1970, 1793053483.001 - 0.155, accuracy: 0.01)
        XCTAssertEqual(delta.airline?.icao, "DAL")
    }

    func testFallbacksForHeadingAndRate() throws {
        let flights = try ReadsbParser.parse(Data(sample.utf8), receivedAt: receivedAt)
        let ba = try XCTUnwrap(flights.first { $0.registration == "G-XLEI" })
        XCTAssertEqual(ba.track, 91.5, accuracy: 0.001)
        XCTAssertEqual(ba.verticalRateFPM, 64)
        XCTAssertNil(ba.flightNumber, "BAW29G is sold as BA238: no guessing")
        let emergency = try XCTUnwrap(flights.first { $0.squawk == "7700" })
        XCTAssertNil(emergency.callsign)
        XCTAssertEqual(emergency.displayIdentifier, "UNKNOWN")
    }

    func testGroundTrafficOnlyWhenAskedFor() throws {
        let flights = try ReadsbParser.parse(Data(sample.utf8), receivedAt: receivedAt, includeGround: true)
        let parked = try XCTUnwrap(flights.first { $0.registration == "N123DN" })
        XCTAssertTrue(parked.isOnGround)
        XCTAssertEqual(parked.altitudeFeet, 0)
    }

    func testFlightNumbers() {
        XCTAssertEqual(ReadsbParser.flightNumber(callsign: "UAL0012"), "UA12")
        XCTAssertNil(ReadsbParser.flightNumber(callsign: "N172SP"))
        XCTAssertNil(ReadsbParser.flightNumber(callsign: "LIFE2"))
    }

    func testRejectsNonObjects() {
        XCTAssertThrowsError(try ReadsbParser.parse(Data("[1,2]".utf8)))
    }

    func testPointQueryReachesTheBoxCorners() {
        let atl = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
        let bounds = GeographicBounds.around(center: atl, radiusMiles: 33)
        let url = ReadsbFeed.pointURL(for: bounds)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://api.adsb.lol/v2/point/33.7490/-84.3880/"), url.absoluteString)
        let nm = Int(url.lastPathComponent)!
        // The corner is 33 × √2 ≈ 47 mi ≈ 41 nm out.
        XCTAssertGreaterThanOrEqual(nm, 40)
        XCTAssertLessThanOrEqual(nm, 43)
        XCTAssertEqual(ReadsbFeed.listURL("reg", values: ["n1", " N2 "])?.absoluteString, "https://api.adsb.lol/v2/reg/N1,N2")
    }
}

/// A feed that fails or answers on command, counting calls.
private final class ScriptedFeed: FlightFeed, @unchecked Sendable {
    var error: FeedError?
    var calls = 0
    let flights: [Flight]
    init(_ ids: [String]) {
        flights = ids.map { TestTraffic.flight($0, miles: 3) }
    }
    func flights(in bounds: GeographicBounds) async throws -> [Flight] {
        calls += 1
        if let error { throw error }
        return flights
    }
}

final class LayeredFeedTests: XCTestCase {
    private let bounds = GeographicBounds.around(center: TestTraffic.observer, radiusMiles: 20)

    func testStaysOnThePrimaryWhileItAnswers() async throws {
        let fr24 = ScriptedFeed(["fr"]), open = ScriptedFeed(["ac-1"])
        let feed = LayeredFeed(primary: fr24, secondary: open)
        let result = try await feed.flights(in: bounds)
        XCTAssertEqual(result.map(\.id), ["fr"])
        let source = await feed.lastSource()
        XCTAssertEqual(source, .flightradar24)
        XCTAssertEqual(open.calls, 0)
    }

    func testStepsDownAfterTwoFailuresAndBackAfterFiveMinutes() async throws {
        let fr24 = ScriptedFeed(["fr"]), open = ScriptedFeed(["ac-1"])
        var now = Date(timeIntervalSince1970: 0)
        let clock = Clock(now)
        let feed = LayeredFeed(primary: fr24, secondary: open, clock: { clock.now })
        fr24.error = .unreachable
        do { _ = try await feed.flights(in: bounds); XCTFail("the first failure is the radar's to retry") } catch {}
        XCTAssertEqual(open.calls, 0)
        let second = try await feed.flights(in: bounds)
        XCTAssertEqual(second.map(\.id), ["ac-1"], "the second failure steps down")
        let source = await feed.lastSource()
        XCTAssertEqual(source, .adsbLol)

        // Stays down without asking Flightradar24 again for five minutes…
        fr24.error = nil
        let before = fr24.calls
        now = now.addingTimeInterval(60); clock.now = now
        _ = try await feed.flights(in: bounds)
        XCTAssertEqual(fr24.calls, before)
        // …then tries it, and it's back.
        now = now.addingTimeInterval(LayeredFeed.retryPrimaryAfter); clock.now = now
        let back = try await feed.flights(in: bounds)
        XCTAssertEqual(back.map(\.id), ["fr"])
        let backSource = await feed.lastSource()
        XCTAssertEqual(backSource, .flightradar24)
    }

    func testARateLimitStepsDownAtOnce() async throws {
        let fr24 = ScriptedFeed(["fr"]), open = ScriptedFeed(["ac-1"])
        fr24.error = .rateLimited
        let feed = LayeredFeed(primary: fr24, secondary: open)
        let result = try await feed.flights(in: bounds)
        XCTAssertEqual(result.map(\.id), ["ac-1"])
    }

    func testBeingOfflineNeverStepsDown() async {
        let fr24 = ScriptedFeed(["fr"]), open = ScriptedFeed(["ac-1"])
        fr24.error = .offline
        let feed = LayeredFeed(primary: fr24, secondary: open)
        for _ in 0..<3 { _ = try? await feed.flights(in: bounds) }
        XCTAssertEqual(open.calls, 0)
    }

    func testPreferencesPinOneSource() async throws {
        let fr24 = ScriptedFeed(["fr"]), open = ScriptedFeed(["ac-1"])
        let feed = LayeredFeed(primary: fr24, secondary: open, preference: .openData)
        let open1 = try await feed.flights(in: bounds)
        XCTAssertEqual(open1.map(\.id), ["ac-1"])
        await feed.setPreference(.flightradar24)
        fr24.error = .unreachable
        for _ in 0..<3 { _ = try? await feed.flights(in: bounds) }
        XCTAssertEqual(open.calls, 1, "Flightradar24 only never falls back")
    }
}

private final class Clock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

final class BatterySaverPollingTests: XCTestCase {
    func testSaverDoublesTheIntervalWithAFloor() {
        let far = [RadarContact(flight: TestTraffic.flight("a", miles: 8), observer: TestTraffic.observer, at: Date())]
        let normal = PollingPolicy.interval(contacts: far, outside: [], floor: 10)
        let saver = PollingPolicy.interval(contacts: far, outside: [], floor: 10, saver: true)
        XCTAssertEqual(saver, max(PollingPolicy.saverFloor, normal * PollingPolicy.saverStretch))
        XCTAssertEqual(PollingPolicy.interval(contacts: far, outside: [], floor: 10, fastest: true, saver: true), 10, "Identify and Find still poll fastest")
    }
}
