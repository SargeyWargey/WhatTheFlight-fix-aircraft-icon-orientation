//
//  FlightPhaseTests.swift
//  WhatTheFlightTests
//
//  The hero's phase-of-flight line (Enhancements Spec C3).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class FlightPhaseTests: XCTestCase {
    private let atl = AirportCatalog.airport(iata: "ATL")!.coordinate!
    private let dfw = AirportCatalog.airport(iata: "DFW")!.coordinate!

    override func setUp() {
        super.setUp()
        Units.current = .imperial
    }

    /// An aircraft `miles` from `from` along `bearing`.
    private func flight(from: String = "DFW", to: String = "ATL", near point: CLLocationCoordinate2D, miles: Double, bearing: Double = 270,
                        feet: Int, vs: Int, knots: Int = 300, type: String? = "B738", ground: Bool = false) -> (Flight, CLLocationCoordinate2D) {
        let position = GeoMath.extrapolate(point, trackDegrees: bearing, speedKnots: miles / GeoMath.milesPerKnotHour, seconds: 3600)
        let f = Flight(id: "x", hex: nil, latitude: position.latitude, longitude: position.longitude, track: 90, altitudeFeet: feet,
                       groundSpeedKnots: knots, verticalRateFPM: vs, squawk: nil, typeCode: type, registration: "N1",
                       originIATA: from.isEmpty ? nil : from, destinationIATA: to.isEmpty ? nil : to, flightNumber: "DL1",
                       callsign: "DAL1", airlineICAO: "DAL", isOnGround: ground, positionTime: Date())
        return (f, position)
    }

    private func phase(_ pair: (Flight, CLLocationCoordinate2D)) -> FlightPhase? {
        FlightPhase(flight: pair.0, position: pair.1, altitudeFeet: pair.0.altitudeFeet)
    }

    func testDescendingNearTheDestinationIsAnApproach() {
        let p = phase(flight(near: atl, miles: 20, feet: 8_000, vs: -900))
        guard case .approaching(let dest, let miles) = p else { return XCTFail("\(String(describing: p))") }
        XCTAssertEqual(dest, "ATL")
        XCTAssertEqual(miles, 20, accuracy: 0.5)
        XCTAssertEqual(p?.text, "On approach to ATL · 20 mi out")
        XCTAssertEqual(p?.short, "Approach ATL")
    }

    func testLowAndLevelCloseInIsStillAnApproach() {
        guard case .approaching = phase(flight(near: atl, miles: 15, feet: 4_000, vs: 0)) else { return XCTFail() }
    }

    func testClimbingCloseToTheOriginIsADeparture() {
        let p = phase(flight(from: "ATL", to: "DFW", near: atl, miles: 10, feet: 6_000, vs: 2_000))
        XCTAssertEqual(p, .departing(origin: "ATL"))
        XCTAssertEqual(p?.text, "Climbing out of ATL")
    }

    func testFarFromBothEndsFollowsTheTrend() {
        // Halfway-ish: 300 mi east of Dallas.
        XCTAssertEqual(phase(flight(near: dfw, miles: 300, bearing: 90, feet: 20_000, vs: 1_500)), .climbing(toward: "ATL"))
        XCTAssertEqual(phase(flight(near: dfw, miles: 300, bearing: 90, feet: 30_000, vs: -1_500)), .descending(toward: "ATL"))
    }

    func testCruisingCountsDownToTheDestination() {
        let p = phase(flight(near: dfw, miles: 300, bearing: 90, feet: 36_000, vs: 0, knots: 450))
        guard case .cruising(let dest, let remaining?) = p else { return XCTFail("\(String(describing: p))") }
        XCTAssertEqual(dest, "ATL")
        XCTAssertGreaterThan(remaining, 30 * 60)
        XCTAssertTrue(p!.text.hasPrefix("Cruising · "), p!.text)
        XCTAssertTrue(p!.text.hasSuffix(" to ATL"), p!.text)
    }

    func testWithoutARouteOnlyTheTrend() {
        XCTAssertEqual(phase(flight(from: "", to: "", near: atl, miles: 5, feet: 3_000, vs: 800, type: "C172")), .climbing(toward: nil))
        XCTAssertNil(phase(flight(from: "", to: "", near: atl, miles: 5, feet: 3_000, vs: 0, type: "C172")),
                     "low level flight without a route says nothing")
        XCTAssertEqual(phase(flight(from: "", to: "", near: atl, miles: 5, feet: 38_000, vs: 0)), .cruising(destination: nil, remaining: nil))
    }

    func testNeverForHelicoptersWithoutARouteOrOnTheGround() {
        XCTAssertNil(phase(flight(from: "", to: "", near: atl, miles: 3, feet: 1_200, vs: 500, type: "EC45")))
        XCTAssertNil(phase(flight(near: atl, miles: 1, feet: 0, vs: 0, ground: true)))
    }

    func testIdentificationSaysTheApproach() {
        var (f, _) = flight(from: "SFO", near: atl, miles: 20, feet: 8_000, vs: -900)
        f.flightNumber = "DL570"
        let observer = GeoMath.extrapolate(atl, trackDegrees: 270, speedKnots: 18 / GeoMath.milesPerKnotHour, seconds: 3600)
        let sentence = SpokenTraffic.identification(for: RadarContact(flight: f, observer: observer, at: Date()))
        XCTAssertTrue(sentence.hasPrefix("Delta Air Lines flight 570, San Francisco to Atlanta, on approach to Atlanta."), sentence)
    }

    func testSpokenFormUsesCities() {
        let p = phase(flight(near: atl, miles: 20, feet: 8_000, vs: -900))
        XCTAssertEqual(p?.spoken(origin: AirportCatalog.airport(iata: "DFW"), destination: AirportCatalog.airport(iata: "ATL")),
                       "on approach to Atlanta")
    }
}
