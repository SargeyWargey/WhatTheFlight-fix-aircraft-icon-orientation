//
//  WatchlistAlertTests.swift
//  WhatTheFlightTests
//
//  Watchlist rules, favourites and pins coming back, and firsts for the logbook
//  (Enhancements Spec C2).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class WatchlistAlertTests: XCTestCase {
    private let observer = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)

    override func setUp() {
        super.setUp()
        Units.current = .imperial
    }

    private func flight(_ id: String, reg: String? = "N685DA", type: String? = "B752", airline: String? = "DAL",
                        callsign: String? = "DAL570", miles: Double = 5) -> Flight {
        let p = GeoMath.extrapolate(observer, trackDegrees: 45, speedKnots: miles / GeoMath.milesPerKnotHour, seconds: 3600)
        return Flight(id: id, hex: "A1B2C3", latitude: p.latitude, longitude: p.longitude, track: 45, altitudeFeet: 12_000,
                      groundSpeedKnots: 300, verticalRateFPM: 0, squawk: nil, typeCode: type, registration: reg,
                      originIATA: nil, destinationIATA: nil, flightNumber: nil, callsign: callsign, airlineICAO: airline,
                      isOnGround: false, positionTime: Date())
    }

    private func contact(_ f: Flight) -> RadarContact { RadarContact(flight: f, observer: observer, at: Date()) }

    private let quiet = TrafficAlertRules(overhead: false, notable: false, favorites: false, firstSeen: false)

    // MARK: Rules

    func testEachRuleKindMatches() {
        let f = flight("a")
        let airline = AirlineCatalog.airline(icao: "DAL")
        XCTAssertTrue(WatchlistRule(kind: .registration, value: "n685da").matches(f, airline: airline))
        XCTAssertTrue(WatchlistRule(kind: .registration, value: "A1B2C3").matches(f, airline: airline), "hex counts too")
        XCTAssertTrue(WatchlistRule(kind: .type, value: "B752").matches(f, airline: airline))
        XCTAssertFalse(WatchlistRule(kind: .type, value: "B753").matches(f, airline: airline))
        XCTAssertTrue(WatchlistRule(kind: .airline, value: "DAL").matches(f, airline: airline))
        XCTAssertTrue(WatchlistRule(kind: .callsign, value: "DAL5").matches(f, airline: airline))
        XCTAssertFalse(WatchlistRule(kind: .callsign, value: "RCH").matches(f, airline: airline))
    }

    func testRegistrationsMatchWithOrWithoutTheirHyphen() {
        let f = flight("a", reg: "G-XLEI")
        XCTAssertTrue(WatchlistRule(kind: .registration, value: "GXLEI").matches(f, airline: nil))
        XCTAssertTrue(WatchlistRule(kind: .registration, value: "g-xlei").matches(f, airline: nil))
    }

    func testNamesResolveThroughTheCatalogs() {
        XCTAssertEqual(WatchlistRule.resolve("Qatar", kind: .airline)?.value, "QTR")
        XCTAssertEqual(WatchlistRule.resolve("QTR", kind: .airline)?.value, "QTR")
        XCTAssertEqual(WatchlistRule.resolve("B744", kind: .type)?.value, "B744")
        XCTAssertNotNil(WatchlistRule.resolve("747", kind: .type))
        XCTAssertNil(WatchlistRule.resolve("Zzzzzzzz Airways", kind: .airline))
    }

    func testRulesSurviveARoundTrip() throws {
        let rules = [WatchlistRule(kind: .type, value: "B748"), WatchlistRule(kind: .airline, value: "QTR")]
        let decoded = try JSONDecoder().decode([WatchlistRule].self, from: JSONEncoder().encode(rules))
        XCTAssertEqual(decoded, rules)
    }

    // MARK: Engine

    func testAWatchlistMatchAlertsOnce() {
        var engine = TrafficAlertEngine()
        var rules = quiet
        rules.watchlist = [WatchlistRule(kind: .type, value: "B752")]
        let first = engine.evaluate([contact(flight("a"))], rules: rules)
        XCTAssertEqual(first.map(\.reason), [.watchlist])
        XCTAssertTrue(first[0].body.contains("Boeing 757"), first[0].body)
        XCTAssertTrue(engine.evaluate([contact(flight("a"))], rules: rules).isEmpty, "once per flight")
        XCTAssertTrue(engine.evaluate([contact(flight("b", type: "A320"))], rules: rules).isEmpty)
    }

    func testFavoritesAndPinsComingIntoRange() {
        var engine = TrafficAlertEngine()
        var rules = quiet
        rules.favorites = true
        rules.watchlist = [WatchlistRule(kind: .type, value: "B752")]
        let lookups = TrafficAlertLookups(isFavorite: { $0.registration == "N685DA" }, isPinned: { $0 == "p" })
        let alerts = engine.evaluate([contact(flight("a")), contact(flight("p", reg: "N1", type: "C172"))], rules: rules, lookups: lookups)
        XCTAssertEqual(alerts.map(\.reason), [.favorite, .favorite], "a favourite isn't announced again as a watchlist match")
        XCTAssertEqual(alerts.map(\.spokenNote), ["favorite", "pinned"])
        XCTAssertTrue(alerts[0].title.contains("is back"))
    }

    func testFirstsComeFromTheLookup() {
        var engine = TrafficAlertEngine()
        var rules = quiet
        rules.firstSeen = true
        let lookups = TrafficAlertLookups(firstSeen: { $0.id == "a" ? .airline("Qatar Airways") : nil })
        let alerts = engine.evaluate([contact(flight("a")), contact(flight("b"))], rules: rules, lookups: lookups)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.title, "First Qatar Airways in your logbook")
    }

    func testSpokenSentencesForTheNewReasons() {
        var engine = TrafficAlertEngine()
        var rules = quiet
        rules.watchlist = [WatchlistRule(kind: .airline, value: "DAL")]
        let c = contact(flight("a"))
        let alert = engine.evaluate([c], rules: rules)[0]
        let sentence = SpokenTraffic.sentence(for: c, alert: alert)
        XCTAssertTrue(sentence.hasPrefix("On your watchlist: Delta Air Lines."), sentence)
    }

    // MARK: Logbook firsts

    func testTheLogbookKnowsTheFirstOfEachTypeAndAirline() {
        let logbook = Logbook(fileURL: nil)
        // A baseline of 100 sightings of one type and airline.
        for i in 0..<Logbook.firstSeenBaseline {
            logbook.record([contact(flight("old\(i)", reg: "N\(i)", type: "B738", airline: "DAL", callsign: "DAL\(i)"))])
        }
        let newType = contact(flight("new-type", reg: "N9999", type: "B748", airline: "DAL", callsign: "DAL9"))
        let newAirline = contact(flight("new-airline", reg: "A7-ABC", type: "B738", airline: "QTR", callsign: "QTR1"))
        let repeatType = contact(flight("again", reg: "N8888", type: "B748", airline: "DAL", callsign: "DAL8"))
        logbook.record([newType, newAirline])
        logbook.record([repeatType])
        if case .type = logbook.firstSeen(newType) {} else { XCTFail("first 747-8") }
        XCTAssertEqual(logbook.firstSeen(newAirline), .airline(newAirline.profile.operatorInfo.title))
        XCTAssertNil(logbook.firstSeen(repeatType), "the second 747-8 isn't a first")
        XCTAssertNil(logbook.firstSeen(contact(flight("old5", reg: "N5", type: "B738", airline: "DAL", callsign: "DAL5"))))
    }

    func testNoFirstsBeforeTheBaseline() {
        let logbook = Logbook(fileURL: nil)
        let c = contact(flight("a", type: "B748"))
        logbook.record([c])
        XCTAssertNil(logbook.firstSeen(c))
    }
}
