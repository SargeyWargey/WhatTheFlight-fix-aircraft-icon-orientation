//
//  AltitudeSpeedTests.swift
//  WhatTheFlightTests
//
//  The altitude-vs-speed chart's data: what kind of flight each sighting was, the points and
//  their callout text, and picking a dot by finger or by Siri Remote.
//

import XCTest
import CoreGraphics
@testable import WhatTheFlight

final class AltitudeSpeedTests: XCTestCase {
    private var savedUnits: UnitSystem = .imperial

    override func setUp() {
        super.setUp()
        savedUnits = Units.current
        Units.current = .imperial
    }

    override func tearDown() {
        Units.current = savedUnits
        super.tearDown()
    }

    private func sighting(_ id: String, flight: String? = nil, callsign: String? = nil, registration: String? = nil,
                          type: String? = "B738", operatorName: String = "American Airlines", from: String? = "CLT",
                          to: String? = "OKC", altitude: Int = 36_000, speed: Int = 426, tags: [NotableTag] = [],
                          kind: AircraftKind = .airplane, seen: Date = Date(timeIntervalSince1970: 0)) -> Sighting {
        let display = [flight, callsign, registration, type].compactMap { $0 }.first ?? "UNKNOWN"
        return Sighting(id: id, firstSeen: seen, lastSeen: seen.addingTimeInterval(300), displayIdentifier: display,
                        callsign: callsign, registration: registration, hex: nil, typeCode: type, kind: kind,
                        operatorName: operatorName, isAirline: true, originIATA: from, destinationIATA: to,
                        closestMiles: 2, altitudeAtClosestFeet: altitude, speedKnots: speed, tags: tags, placeName: nil)
    }

    private func iso(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: text)!
    }

    /// Times put a narrow no-break space before AM/PM.
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    // MARK: Kind of flight

    func testMilitaryByTagOrOperator() {
        XCTAssertEqual(FlightKind.classify(operatorName: "Delta Air Lines", tags: [.military]), .military)
        XCTAssertEqual(FlightKind.classify(operatorName: "US Air Force · Air Mobility Command"), .military)
        XCTAssertEqual(FlightKind.classify(operatorName: "US Army"), .military)
        XCTAssertEqual(FlightKind.classify(operatorName: "US Navy"), .military)
        XCTAssertEqual(FlightKind.classify(operatorName: "Former US Navy Museum"), .airline, "only a prefix counts")
    }

    func testHelicoptersByOperatorOrAirframe() {
        XCTAssertEqual(FlightKind.classify(operatorName: "Private helicopter"), .helicopter)
        XCTAssertEqual(FlightKind.classify(operatorName: "Helicopter"), .helicopter)
        XCTAssertEqual(FlightKind.classify(operatorName: "Air Methods", isHelicopter: true), .helicopter)
    }

    func testGeneralAviation() {
        XCTAssertEqual(FlightKind.classify(operatorName: "Private aircraft"), .generalAviation)
        XCTAssertEqual(FlightKind.classify(operatorName: "Unlisted operator BPX"), .generalAviation)
        XCTAssertEqual(FlightKind.classify(operatorName: "Private / Unlisted"), .generalAviation)
    }

    func testCargoOperators() {
        for name in ["FedEx Express", "UPS Airlines", "DHL Aviation", "Kalitta Air", "Atlas Air", "Amazon Prime Air",
                     "Air Transport International", "Western Global Freight", "USA Jet Airlines", "Air Contractors Fret"] {
            XCTAssertEqual(FlightKind.classify(operatorName: name), .cargo, name)
        }
    }

    func testBusinessJetOperators() {
        for name in ["NetJets", "Flexjet", "Wheels Up", "Jet Linx Aviation", "Executive Jet Management", "Jet Suite",
                     "Jetex", "Gulfstream Aerospace"] {
            XCTAssertEqual(FlightKind.classify(operatorName: name), .businessJet, name)
        }
    }

    func testEverythingElseIsAnAirline() {
        XCTAssertEqual(FlightKind.classify(operatorName: "American Airlines"), .airline)
        XCTAssertEqual(FlightKind.classify(operatorName: ""), .airline)
    }

    func testMatchingIgnoresCase() {
        XCTAssertEqual(FlightKind.classify(operatorName: "FEDEX"), .cargo)
        XCTAssertEqual(FlightKind.classify(operatorName: "netjets"), .businessJet)
        XCTAssertEqual(FlightKind.classify(operatorName: "PRIVATE AIRCRAFT"), .generalAviation)
        XCTAssertEqual(FlightKind.classify(operatorName: "us navy"), .military)
    }

    func testRulesApplyInOrder() {
        // Military before helicopter.
        XCTAssertEqual(FlightKind.classify(operatorName: "US Army", isHelicopter: true), .military)
        XCTAssertEqual(FlightKind.classify(operatorName: "Private helicopter", tags: [.military]), .military)
        // Helicopter before general aviation.
        XCTAssertEqual(FlightKind.classify(operatorName: "Private aircraft", isHelicopter: true), .helicopter)
        // General aviation before cargo.
        XCTAssertEqual(FlightKind.classify(operatorName: "Private Freight Co"), .generalAviation)
        // Cargo before business jet.
        XCTAssertEqual(FlightKind.classify(operatorName: "Executive Freight"), .cargo)
        // Business jet before airline.
        XCTAssertEqual(FlightKind.classify(operatorName: "Executive Airlines"), .businessJet)
        // Other tags don't make it military.
        XCTAssertEqual(FlightKind.classify(operatorName: "Delta Air Lines", tags: [.rare, .government]), .airline)
    }

    func testResolveMatchesClassify() {
        for name in ["US Navy", "Private helicopter", "Private aircraft", "FedEx", "NetJets", "Delta Air Lines"] {
            for tags in [[], [NotableTag.military]] {
                for helicopter in [false, true] {
                    XCTAssertEqual(FlightKind.resolve(FlightKind.classify(operatorName: name), tags: tags, isHelicopter: helicopter),
                                   FlightKind.classify(operatorName: name, tags: tags, isHelicopter: helicopter))
                }
            }
        }
    }

    // MARK: Points

    func testPointLeavesOutZeroSpeed() {
        XCTAssertNil(AltitudeSpeedPoint(sighting("a", speed: 0), kind: .airline))
        XCTAssertNotNil(AltitudeSpeedPoint(sighting("a", altitude: 0, speed: 12), kind: .airline), "taxiing still counts")
    }

    func testFlightFallsBackToCallsignRegistrationThenQuestionMark() {
        XCTAssertEqual(AltitudeSpeedPoint(sighting("a", flight: "AA768", callsign: "AAL768"), kind: .airline)?.flight, "AA768")
        XCTAssertEqual(AltitudeSpeedPoint(sighting("a", callsign: "AAL768"), kind: .airline)?.flight, "AAL768")
        XCTAssertEqual(AltitudeSpeedPoint(sighting("a", registration: "N123AB"), kind: .airline)?.flight, "N123AB")
        XCTAssertEqual(AltitudeSpeedPoint(sighting("a"), kind: .airline)?.flight, "?", "the type code isn't a flight")
        XCTAssertEqual(AltitudeSpeedPoint(sighting("a", type: nil), kind: .airline)?.flight, "?")
    }

    func testCalloutText() throws {
        let p = try XCTUnwrap(AltitudeSpeedPoint(sighting("a", flight: "AA768", seen: iso("2026-10-20T03:20:57Z")), kind: .airline))
        // 2026-10-19T21:20:57-06:00 is 10:20 PM in Chicago (CDT, UTC−5).
        XCTAssertEqual(plain(p.headline(locale: Locale(identifier: "en_US"))), "AA768 · Oct 19, 10:20 PM CT")
        XCTAssertEqual(p.model, "Boeing 737-800")
        XCTAssertEqual(p.altitudeText, "36,000 ft")
        XCTAssertEqual(p.speedText, "426 kts")
        XCTAssertEqual(p.route, "CLT → OKC")

        let bare = try XCTUnwrap(AltitudeSpeedPoint(sighting("b", type: "ZZZZ", from: nil, to: "OKC"), kind: .airline))
        XCTAssertEqual(bare.model, "ZZZZ")
        XCTAssertEqual(bare.route, "? → OKC")
        XCTAssertEqual(AltitudeSpeedPoint(sighting("c", type: nil), kind: .airline)?.model, "Unknown")
    }

    func testTimesAreCentralWhateverTheOffset() {
        let en = Locale(identifier: "en_US")
        // Winter: CST, UTC−6.
        XCTAssertEqual(plain(AltitudeSpeed.timeText(iso("2026-01-15T12:00:00Z"), locale: en)), "Jan 15, 6:00 AM CT")
        // Seen in London, still shown in Central.
        XCTAssertEqual(plain(AltitudeSpeed.timeText(iso("2026-07-04T18:30:00+01:00"), locale: en)), "Jul 4, 12:30 PM CT")
    }

    func testAxisLabels() {
        XCTAssertEqual(AltitudeSpeed.speedAxisLabel(100, isLast: false, units: .imperial), "100")
        XCTAssertEqual(AltitudeSpeed.speedAxisLabel(500, isLast: true, units: .imperial), "500 kts")
        XCTAssertEqual(AltitudeSpeed.speedAxisLabel(800, isLast: true, units: .metric), "800 km/h")
        XCTAssertEqual(AltitudeSpeed.altitudeAxisLabel(0, units: .imperial), "0")
        XCTAssertEqual(AltitudeSpeed.altitudeAxisLabel(10_000, units: .imperial), "10k ft")
        XCTAssertEqual(AltitudeSpeed.altitudeAxisLabel(2_500, units: .imperial), "2.5k ft")
        XCTAssertEqual(AltitudeSpeed.altitudeAxisLabel(3_000, units: .metric), "3 km")
    }

    // MARK: The set

    func testSetListsPresentKindsInOrderAndStartsAxesAtZero() {
        let set = AltitudeSpeedSet(sightings: [
            sighting("heli", operatorName: "Private helicopter", altitude: 1_000, speed: 90),
            sighting("ground", speed: 0),
            sighting("fedex", operatorName: "FedEx", altitude: 38_000, speed: 520),
            sighting("delta", operatorName: "Delta Air Lines"),
            sighting("reach", operatorName: "Delta Air Lines", tags: [.military]),
        ])
        XCTAssertEqual(set.count, 4)
        XCTAssertEqual(set.kinds, [.airline, .cargo, .helicopter, .military])
        XCTAssertEqual(set.points.map(\.kind), [.helicopter, .cargo, .airline, .military])
        XCTAssertEqual(set.speedDomain.lowerBound, 0)
        XCTAssertGreaterThan(set.speedDomain.upperBound, 520)
        XCTAssertEqual(set.altitudeDomain.lowerBound, 0)
        XCTAssertGreaterThan(set.altitudeDomain.upperBound, 38_000)
    }

    func testFingerprintFollowsTheDots() {
        let a = AltitudeSpeedSet(sightings: [sighting("a"), sighting("b", speed: 300)])
        let same = AltitudeSpeedSet(sightings: [sighting("a"), sighting("b", speed: 300)])
        let moved = AltitudeSpeedSet(sightings: [sighting("a"), sighting("b", speed: 310)])
        XCTAssertEqual(a.fingerprint, same.fingerprint)
        XCTAssertNotEqual(a.fingerprint, moved.fingerprint)
    }

    func testPositionsPutZeroBottomLeft() {
        let set = AltitudeSpeedSet(sightings: [sighting("slow", altitude: 0, speed: 1), sighting("fast", altitude: 40_000, speed: 500)])
        let size = CGSize(width: 300, height: 200)
        let slow = set.position(of: 0, in: size), fast = set.position(of: 1, in: size)
        XCTAssertEqual(slow.y, 200, accuracy: 0.001)
        XCTAssertLessThan(slow.x, 2)
        XCTAssertEqual(fast.x, 300 * 500 / set.speedDomain.upperBound, accuracy: 0.001)
        XCTAssertEqual(fast.y, 200 - 200 * 40_000 / set.altitudeDomain.upperBound, accuracy: 0.001)
        XCTAssertEqual(set.positions(in: size), [slow, fast])
    }

    func testStartsOnTheAirlinerNearestTheMiddle() {
        let set = AltitudeSpeedSet(sightings: [
            sighting("cruise", altitude: 37_000, speed: 480),
            sighting("climb", altitude: 15_000, speed: 300),
            sighting("cessna", operatorName: "Private aircraft", altitude: 15_500, speed: 310),
            sighting("approach", altitude: 3_000, speed: 160),
            sighting("heli", operatorName: "Private helicopter", altitude: 900, speed: 100),
        ])
        XCTAssertEqual(set.startIndex, 1, "the climbing airliner nearest the middle, not the Cessna beside it")
        let noAirliners = AltitudeSpeedSet(sightings: [sighting("a", operatorName: "Private aircraft"), sighting("b", operatorName: "FedEx")])
        XCTAssertEqual(noAirliners.startIndex, 0)
        XCTAssertNil(AltitudeSpeedSet.empty.startIndex)
    }

    func testStepsBySpeed() {
        let set = AltitudeSpeedSet(sightings: [sighting("b", speed: 300), sighting("a", speed: 100), sighting("c", speed: 500)])
        XCTAssertEqual(set.step(from: 1, by: 1), 0)
        XCTAssertEqual(set.step(from: 0, by: 1), 2)
        XCTAssertNil(set.step(from: 2, by: 1), "fastest is the end")
        XCTAssertEqual(set.step(from: 2, by: -1), 0)
        XCTAssertNil(set.step(from: 1, by: -1), "slowest is the start")
    }

    func testSkyBuildsTheChartAndWaitsForEnough() {
        let few = LogbookSky((0..<10).map { sighting("s\($0)", speed: 200 + $0) })
        XCTAssertEqual(few.altitudeSpeed.count, 10)
        XCTAssertFalse(few.showsAltitudeSpeed)
        let enough = LogbookSky((0..<LogbookSky.minimum).map { sighting("s\($0)", speed: 200 + $0) } + [sighting("ground", speed: 0)])
        XCTAssertEqual(enough.altitudeSpeed.count, LogbookSky.minimum)
        XCTAssertTrue(enough.showsAltitudeSpeed)
    }

    // MARK: Picking

    func testNearestDotWithinReach() {
        let dots = [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 104)]
        XCTAssertEqual(ScatterPicking.nearest(to: CGPoint(x: 107, y: 103), in: dots, within: 24), 2)
        XCTAssertEqual(ScatterPicking.nearest(to: CGPoint(x: 30, y: 10), in: dots, within: 24), 0, "20 pt away")
        XCTAssertEqual(ScatterPicking.nearest(to: CGPoint(x: 34, y: 10), in: dots, within: 24), 0, "exactly 24 pt away")
        XCTAssertNil(ScatterPicking.nearest(to: CGPoint(x: 35, y: 10), in: dots, within: 24), "25 pt away")
        XCTAssertNil(ScatterPicking.nearest(to: .zero, in: [], within: 24))
    }

    /// ·  ·  ·
    /// ·  ●  ·   with a far dot straight right and a near one 30° off it.
    func testNeighborMovesWithinTheCone() {
        let dots = [
            CGPoint(x: 100, y: 100),  // 0: start
            CGPoint(x: 200, y: 100),  // 1: straight right, far
            CGPoint(x: 140, y: 77),   // 2: right and up 30°, near
            CGPoint(x: 100, y: 60),   // 3: straight up (screen y falls)
            CGPoint(x: 100, y: 130),  // 4: straight down
            CGPoint(x: 40, y: 165),   // 5: down-left, 47° off left
        ]
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .right, in: dots), 2, "nearest inside the cone wins")
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .right, in: dots, cone: 20), 1, "a narrower cone skips it")
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .up, in: dots), 3)
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .down, in: dots), 4)
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .left, in: dots), nil, "47° off is outside the cone")
    }

    func testNeighborIncludesExactDiagonals() {
        let dots = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .right, in: dots), 1)
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .down, in: dots), 1)
    }

    func testNeighborStopsAtTheEdgesOfTheData() {
        let dots = [CGPoint(x: 0, y: 100), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)]
        XCTAssertNil(ScatterPicking.neighbor(of: 2, toward: .right, in: dots), "fastest")
        XCTAssertNil(ScatterPicking.neighbor(of: 2, toward: .up, in: dots), "highest")
        XCTAssertNil(ScatterPicking.neighbor(of: 0, toward: .left, in: dots), "slowest")
        XCTAssertNil(ScatterPicking.neighbor(of: 0, toward: .down, in: dots), "lowest")
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .right, in: dots), 1)
        XCTAssertNil(ScatterPicking.neighbor(of: 5, toward: .right, in: dots), "no such dot")
        XCTAssertNil(ScatterPicking.neighbor(of: 0, toward: .right, in: [CGPoint(x: 0, y: 0)]), "a lone dot")
    }

    func testStepWidensTheConeBeforeGivingUp() {
        // A wide, shallow plot: the next dot up is well off to the side.
        let dots = [CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 80), CGPoint(x: 400, y: 100), CGPoint(x: 100, y: 99.9)]
        XCTAssertNil(ScatterPicking.neighbor(of: 0, toward: .up, in: dots, minimumDistance: 1), "72° off up")
        XCTAssertEqual(ScatterPicking.step(from: 0, toward: .up, in: dots, minimumDistance: 1), 1)
        XCTAssertEqual(ScatterPicking.step(from: 0, toward: .right, in: dots), 1, "the 45° cone still comes first")
        XCTAssertNil(ScatterPicking.step(from: 1, toward: .up, in: dots), "the highest dot is the edge")
        XCTAssertNil(ScatterPicking.step(from: 2, toward: .right, in: dots), "so is the fastest")
    }

    func testNeighborSkipsDotsDrawnOnTopOfEachOther() {
        let dots = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)]
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .right, in: dots), 1)
        XCTAssertEqual(ScatterPicking.neighbor(of: 0, toward: .right, in: dots, minimumDistance: 4), 3)
        XCTAssertNil(ScatterPicking.neighbor(of: 0, toward: .left, in: dots), "an identical dot has no direction")
    }

    // MARK: Callout

    func testCalloutSitsAboveThenBesideThenBelow() {
        let plot = CGSize(width: 300, height: 200)
        let size = CGSize(width: 120, height: 60)
        // Room above: centred over the dot.
        XCTAssertEqual(ScatterPicking.calloutOrigin(size: size, anchor: CGPoint(x: 150, y: 150), in: plot, gap: 10),
                       CGPoint(x: 90, y: 80))
        // Near the left edge: slides right to stay inside.
        XCTAssertEqual(ScatterPicking.calloutOrigin(size: size, anchor: CGPoint(x: 20, y: 150), in: plot, gap: 10),
                       CGPoint(x: 0, y: 80))
        // Near the top: beside it, on the right.
        XCTAssertEqual(ScatterPicking.calloutOrigin(size: size, anchor: CGPoint(x: 100, y: 40), in: plot, gap: 10),
                       CGPoint(x: 110, y: 10))
        // Near the top right: beside it, on the left.
        XCTAssertEqual(ScatterPicking.calloutOrigin(size: size, anchor: CGPoint(x: 280, y: 10), in: plot, gap: 10),
                       CGPoint(x: 150, y: 0))
        // Too narrow for either side: below.
        let narrow = CGSize(width: 200, height: 200)
        XCTAssertEqual(ScatterPicking.calloutOrigin(size: size, anchor: CGPoint(x: 100, y: 30), in: narrow, gap: 10),
                       CGPoint(x: 40, y: 40))
    }

    func testCalloutNeverLeavesThePlot() {
        let plot = CGSize(width: 260, height: 180)
        let size = CGSize(width: 150, height: 90)
        for x in stride(from: 0.0, through: 260, by: 13) {
            for y in stride(from: 0.0, through: 180, by: 9) {
                let o = ScatterPicking.calloutOrigin(size: size, anchor: CGPoint(x: x, y: y), in: plot, gap: 10)
                XCTAssertGreaterThanOrEqual(o.x, 0)
                XCTAssertGreaterThanOrEqual(o.y, 0)
                XCTAssertLessThanOrEqual(o.x + size.width, plot.width)
                XCTAssertLessThanOrEqual(o.y + size.height, plot.height)
            }
        }
    }
}
