//
//  RouteWebTests.swift
//  WhatTheFlightTests
//
//  The route web: which airports make the ring, the routes between them, where each sits
//  round the ring, and the Siri Remote's steps through it.
//

import XCTest
@testable import WhatTheFlight

final class RouteWebTests: XCTestCase {
    private var serial = 0

    private func flights(_ origin: String?, _ destination: String?, _ count: Int = 1) -> [Sighting] {
        (0..<count).map { _ in
            serial += 1
            let date = Date(timeIntervalSince1970: Double(serial) * 600)
            return Sighting(id: "f\(serial)", firstSeen: date, lastSeen: date.addingTimeInterval(300), displayIdentifier: "F\(serial)",
                            callsign: nil, registration: nil, hex: nil, typeCode: "B738", kind: .airplane,
                            operatorName: "Delta Air Lines", isAirline: true, originIATA: origin, destinationIATA: destination,
                            closestMiles: 2, altitudeAtClosestFeet: 10_000, speedKnots: 300, tags: [], placeName: nil)
        }
    }

    /// XNA 13 ends, ATL 9, DFW 5, ORD 3; plus a route off the ring, a round trip to nowhere
    /// and a flight with no origin.
    private func sample(limit: Int = 4) -> RouteWeb {
        RouteWeb(flights("XNA", "ATL", 5) + flights("ATL", "XNA", 4) + flights("XNA", "DFW", 3)
                 + flights("DFW", "ORD", 2) + flights("ORD", "XNA") + flights("AAA", "BBB")
                 + flights("XNA", "XNA", 2) + flights(nil, "ATL"), limit: limit)
    }

    // MARK: The ring

    func testBusiestAirportsMakeTheRingBusiestFirst() {
        let web = sample()
        XCTAssertEqual(web.airports.map(\.id), ["XNA", "ATL", "DFW", "ORD"])
        XCTAssertEqual(web.airports.map(\.outbound), [8, 4, 2, 1])
        XCTAssertEqual(web.airports.map(\.inbound), [5, 5, 3, 2])
        XCTAssertEqual(web.routed, 16, "the off-ring route counts; a round trip and a missing origin don't")
        XCTAssertEqual(web.total, 15)
        XCTAssertEqual(web.flows.map { web.title($0) }, ["XNA → ATL", "ATL → XNA", "XNA → DFW", "DFW → ORD", "ORD → XNA"])
        XCTAssertEqual(web.flows.map(\.count), [5, 4, 3, 2, 1])
        XCTAssertEqual(web.routeKey(web.flows[0]), "XNA-ATL")
        XCTAssertEqual(web.routes(of: 0), [0, 1, 2, 4])
        XCTAssertEqual(web.routes(of: 3), [3, 4])
    }

    func testTheLimitCapsTheRing() {
        let web = sample(limit: 2)
        XCTAssertEqual(web.airports.map(\.id), ["ATL", "XNA"], "9 flights each on the ring: a tie goes alphabetically")
        XCTAssertEqual(web.total, 9)
    }

    func testAnAirportWithNoRoutesOnTheRingIsLeftOff() {
        let web = RouteWeb(flights("AAA", "BBB", 5) + flights("BBB", "AAA", 5) + flights("CCC", "DDD", 4), limit: 3)
        XCTAssertEqual(web.airports.map(\.id), ["AAA", "BBB"], "CCC only flew to DDD, which missed the cut")
        XCTAssertEqual(web.total, 10)
    }

    func testNoRoutesMakesAnEmptyWeb() {
        let web = RouteWeb(flights(nil, nil, 3))
        XCTAssertTrue(web.isEmpty)
        XCTAssertTrue(web.airports.isEmpty)
        XCTAssertTrue(web.layout().arcs.isEmpty)
        XCTAssertNil(RouteWebCursor(airport: 0).moved(.right, in: web))
    }

    func testSkyShowsTheWebOnceEnoughFlightsHaveARoute() {
        let few = LogbookSky(flights("XNA", "ATL", 30) + flights("ATL", "XNA", 19) + flights(nil, nil, 10))
        XCTAssertEqual(few.routeWeb.routed, 49)
        XCTAssertFalse(few.showsRouteWeb)
        let enough = LogbookSky(flights("XNA", "ATL", 30) + flights("ATL", "XNA", 20))
        XCTAssertTrue(enough.showsRouteWeb)
        let oneWay = LogbookSky(flights("XNA", "ATL", 60))
        XCTAssertTrue(oneWay.showsRouteWeb, "two airports, one route")
        let nowhere = LogbookSky(flights("XNA", "XNA", 60))
        XCTAssertFalse(nowhere.showsRouteWeb)
    }

    // MARK: Layout

    func testArcsFillTheRingInProportion() {
        let web = sample()
        let gap = 0.05
        let layout = web.layout(gap: gap)
        XCTAssertEqual(layout.arcs.count, 4)
        XCTAssertEqual(layout.arcs[0].start, gap / 2, accuracy: 1e-9)
        XCTAssertEqual(layout.arcs.reduce(0) { $0 + $1.width } + 4 * gap, 2 * .pi, accuracy: 1e-9)
        let perFlight = layout.arcs[0].width / Double(web.airports[0].total)
        for (arc, airport) in zip(layout.arcs, web.airports) {
            XCTAssertEqual(arc.width, Double(airport.total) * perFlight, accuracy: 1e-9)
        }
        for (i, flow) in web.flows.enumerated() {
            XCTAssertEqual(layout.sources[i].width, Double(flow.count) * perFlight, accuracy: 1e-9)
            XCTAssertEqual(layout.targets[i].width, Double(flow.count) * perFlight, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(layout.sources[i].start, layout.arcs[flow.from].start - 1e-9)
            XCTAssertLessThanOrEqual(layout.sources[i].end, layout.arcs[flow.from].end + 1e-9)
            XCTAssertGreaterThanOrEqual(layout.targets[i].start, layout.arcs[flow.to].start - 1e-9)
            XCTAssertLessThanOrEqual(layout.targets[i].end, layout.arcs[flow.to].end + 1e-9)
        }
    }

    func testEndsFaceTheirOtherAirportAndPairsNest() {
        let web = sample()
        let layout = web.layout()
        // On XNA's arc: ORD (furthest clockwise) first, then DFW, then ATL out and ATL back.
        XCTAssertEqual(layout.targets[4].start, layout.arcs[0].start, accuracy: 1e-9, "from ORD")
        XCTAssertEqual(layout.sources[2].start, layout.targets[4].end, accuracy: 1e-9, "to DFW")
        XCTAssertEqual(layout.sources[0].start, layout.sources[2].end, accuracy: 1e-9, "to ATL")
        XCTAssertEqual(layout.targets[1].start, layout.sources[0].end, accuracy: 1e-9, "back from ATL")
        XCTAssertEqual(layout.targets[1].end, layout.arcs[0].end, accuracy: 1e-9)
        // On ATL's arc the same pair goes out first too, so the two ribbons nest.
        XCTAssertLessThanOrEqual(layout.sources[1].end, layout.targets[0].start + 1e-9)
    }

    func testAnglesFindTheirAirport() {
        let web = sample()
        let layout = web.layout(gap: 0.05)
        XCTAssertEqual(layout.airport(at: layout.arcs[2].mid), 2)
        XCTAssertEqual(layout.airport(at: 0.01), 0, "just past the top")
        XCTAssertEqual(layout.airport(at: -0.01), 3, "just before it")
        XCTAssertEqual(layout.airport(at: 2 * .pi + layout.arcs[1].mid), 1)
    }

    // MARK: The remote

    func testLeftAndRightGoRoundTheRing() {
        let web = sample()
        XCTAssertEqual(RouteWebCursor(airport: 0).moved(.right, in: web), RouteWebCursor(airport: 1))
        XCTAssertEqual(RouteWebCursor(airport: 3).moved(.right, in: web), RouteWebCursor(airport: 0), "wraps")
        XCTAssertEqual(RouteWebCursor(airport: 0).moved(.left, in: web), RouteWebCursor(airport: 3), "wraps back")
        XCTAssertEqual(RouteWebCursor(airport: 0, route: 2).moved(.right, in: web), RouteWebCursor(airport: 1),
                       "a new airport starts on the airport, not a route")
    }

    func testDownWalksTheRoutesAndUpWalksBack() {
        let web = sample()
        var cursor = RouteWebCursor(airport: 0)
        var flows: [Int] = []
        while let next = cursor.moved(.down, in: web) {
            cursor = next
            flows.append(cursor.flow(in: web)!)
        }
        XCTAssertEqual(flows, [0, 1, 2, 4], "XNA's routes, busiest first")
        XCTAssertEqual(cursor, RouteWebCursor(airport: 0, route: 3))
        XCTAssertNil(cursor.moved(.down, in: web), "the last route is the edge")

        XCTAssertEqual(RouteWebCursor(airport: 0, route: 1).moved(.up, in: web), RouteWebCursor(airport: 0, route: 0))
        XCTAssertEqual(RouteWebCursor(airport: 0, route: 0).moved(.up, in: web), RouteWebCursor(airport: 0), "back to the airport")
        XCTAssertNil(RouteWebCursor(airport: 0).moved(.up, in: web), "the airport is the top edge")
    }

    func testCursorFromARibbonAndWhatItOpens() {
        let web = sample()
        let onRibbon = RouteWebCursor(flow: 3, in: web)
        XCTAssertEqual(onRibbon, RouteWebCursor(airport: 2, route: 1), "DFW → ORD, from DFW's side")
        XCTAssertEqual(onRibbon.flow(in: web), 3)
        XCTAssertEqual(onRibbon.filter(in: web), .route("DFW-ORD"))
        XCTAssertEqual(RouteWebCursor(airport: 0).filter(in: web), .airport("XNA"))
        XCTAssertEqual(RouteWebCursor(airport: 1, route: 0).spokenSummary(in: web), "XNA to ATL, 5 flights")
        XCTAssertTrue(RouteWebCursor(airport: 0).spokenSummary(in: web).hasSuffix("13 flights, 8 out, 5 in"))
    }
}
