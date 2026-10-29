//
//  RouteWeb.swift
//  WhatTheFlight
//
//  The data behind the Stats tab's route web: where the aircraft over one sky were flying
//  from and to, as a directed chord diagram of the busiest route airports. Each airport gets
//  an arc of a ring, as long as its flights in the web; each route a ribbon from its origin's
//  arc to an arrowhead at its destination's. Also the ring's angles, which airport a touch
//  lands on, and where the Siri Remote goes next. Built with each `LogbookSky`, so it follows
//  the Stats tab's choice of place. Kept free of SwiftUI so it's unit-tested.
//

import Foundation

struct RouteWeb: Sendable {
    /// Airports on the ring: more and the arcs get too thin to name.
    static let airportLimit = 8

    struct Airport: Identifiable, Hashable, Sendable {
        /// IATA code.
        let id: String
        /// Flights in the web from it, and to it.
        let outbound: Int
        let inbound: Int

        var total: Int { outbound + inbound }
        /// "Bentonville", when the catalog knows it.
        var city: String? { AirportCatalog.airport(iata: id)?.city }
    }

    /// A route: flights from one airport on the ring to another.
    struct Flow: Identifiable, Hashable, Sendable {
        /// Indices into `airports`.
        let from: Int
        let to: Int
        let count: Int

        var id: Int { from * RouteWeb.airportLimit + to }
    }

    /// Busiest first, clockwise from the top.
    let airports: [Airport]
    /// Busiest first.
    let flows: [Flow]
    /// Flights in the web: both ends on the ring.
    let total: Int
    /// Flights with both ends known, on the ring or not.
    let routed: Int

    static let empty = RouteWeb([])

    var isEmpty: Bool { flows.isEmpty }

    /// The `limit` airports that turn up most as an origin or a destination, and the flights
    /// between them. One that only flew to airports off the ring is left off it.
    init(_ sightings: [Sighting], limit: Int = airportLimit) {
        var ends: [String: Int] = [:]
        var routes: [(origin: String, destination: String)] = []
        for s in sightings {
            guard let origin = s.originIATA, let destination = s.destinationIATA,
                  !origin.isEmpty, !destination.isEmpty, origin != destination else { continue }
            routes.append((origin, destination))
            ends[origin, default: 0] += 1
            ends[destination, default: 0] += 1
        }
        routed = routes.count

        let busiest = ends.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(limit).map(\.key)
        let n = busiest.count
        let indexOf = Dictionary(uniqueKeysWithValues: busiest.enumerated().map { ($1, $0) })
        var counts: [Int: Int] = [:]
        for route in routes {
            guard let i = indexOf[route.origin], let j = indexOf[route.destination] else { continue }
            counts[i * n + j, default: 0] += 1
        }
        var outbound = Array(repeating: 0, count: n), inbound = Array(repeating: 0, count: n)
        for (key, count) in counts {
            outbound[key / n] += count
            inbound[key % n] += count
        }

        let kept = (0..<n).filter { outbound[$0] + inbound[$0] > 0 }
            .sorted { (outbound[$0] + inbound[$0], busiest[$1]) > (outbound[$1] + inbound[$1], busiest[$0]) }
        let ring = Dictionary(uniqueKeysWithValues: kept.enumerated().map { ($1, $0) })
        airports = kept.map { Airport(id: busiest[$0], outbound: outbound[$0], inbound: inbound[$0]) }
        flows = counts.compactMap { key, count in
            guard let from = ring[key / n], let to = ring[key % n] else { return nil }
            return Flow(from: from, to: to, count: count)
        }
        .sorted { ($0.count, $1.from, $1.to) > ($1.count, $0.from, $0.to) }
        total = flows.reduce(0) { $0 + $1.count }
    }

    /// "XNA-ATL", the logbook's key for a route (`LogbookFilter.route`).
    func routeKey(_ flow: Flow) -> String { "\(airports[flow.from].id)-\(airports[flow.to].id)" }

    /// "XNA → ATL".
    func title(_ flow: Flow) -> String { "\(airports[flow.from].id) → \(airports[flow.to].id)" }

    /// The routes to and from an airport (indices into `flows`), busiest first.
    func routes(of airport: Int) -> [Int] {
        flows.indices.filter { flows[$0].from == airport || flows[$0].to == airport }
    }

    /// "8 airports, 640 flights. Busiest: XNA to ATL, 86.", for VoiceOver.
    var summary: String {
        var text = "\(airports.count) airports, \(RadarFormat.wholeNumber(total)) flights."
        if let top = flows.first {
            text += " Busiest: \(airports[top.from].id) to \(airports[top.to].id), \(RadarFormat.wholeNumber(top.count))."
        }
        return text
    }

    // MARK: Layout

    /// Where everything sits round the ring, in radians clockwise from the top.
    struct Layout: Sendable {
        struct Span: Equatable, Sendable {
            var start: Double
            var end: Double
            var mid: Double { (start + end) / 2 }
            var width: Double { end - start }
        }

        /// Each airport's arc.
        let arcs: [Span]
        /// Each flow's end on its origin's arc, and on its destination's.
        let sources: [Span]
        let targets: [Span]
        let gap: Double

        /// The airport whose arc (or the half gap either side of it) holds `angle`.
        func airport(at angle: Double) -> Int? {
            let a = angle.truncatingRemainder(dividingBy: 2 * .pi)
            let angle = a < 0 ? a + 2 * .pi : a
            return arcs.indices.first { i in
                let start = arcs[i].start - gap / 2, end = arcs[i].end + gap / 2
                return (start...end).contains(angle) || (start...end).contains(angle - 2 * .pi) || (start...end).contains(angle + 2 * .pi)
            }
        }
    }

    /// The ring with `gap` radians between arcs, the first arc starting half a gap after the
    /// top. Inside an arc, each route's end sits on the side facing the airport at its other
    /// end, the flights out before the flights back, so a pair of ribbons nests rather than
    /// crosses.
    func layout(gap: Double = 0.05) -> Layout {
        let n = airports.count
        guard n > 1, total > 0 else { return Layout(arcs: [], sources: [], targets: [], gap: gap) }
        let perFlight = max(0, 2 * .pi - Double(n) * gap) / Double(2 * total)
        var arcs: [Layout.Span] = []
        var sources = Array(repeating: Layout.Span(start: 0, end: 0), count: flows.count)
        var targets = sources
        var angle = gap / 2
        for a in 0..<n {
            let start = angle
            // (flow, outbound?) ordered by how far clockwise the other end is, furthest first.
            let ends = routes(of: a).flatMap { f -> [(flow: Int, out: Bool)] in
                var list: [(flow: Int, out: Bool)] = []
                if flows[f].from == a { list.append((f, true)) }
                if flows[f].to == a { list.append((f, false)) }
                return list
            }
            .sorted { x, y in
                func reach(_ e: (flow: Int, out: Bool)) -> Int {
                    let other = e.out ? flows[e.flow].to : flows[e.flow].from
                    return (other - a + n) % n
                }
                if reach(x) != reach(y) { return reach(x) > reach(y) }
                if x.out != y.out { return x.out }
                return x.flow < y.flow
            }
            for end in ends {
                let span = Layout.Span(start: angle, end: angle + Double(flows[end.flow].count) * perFlight)
                if end.out { sources[end.flow] = span } else { targets[end.flow] = span }
                angle = span.end
            }
            arcs.append(Layout.Span(start: start, end: angle))
            angle += gap
        }
        return Layout(arcs: arcs, sources: sources, targets: targets, gap: gap)
    }
}

/// Where the Siri Remote is on the web: an airport and, after a step down, one of its routes.
/// ◀ ▶ go round the ring; ▼ walks down the airport's routes, busiest first; ▲ walks back up
/// to the airport. nil when a step would leave the chart.
struct RouteWebCursor: Hashable, Sendable {
    var airport: Int
    /// Index into `web.routes(of: airport)`; nil for the whole airport.
    var route: Int?

    /// The cursor on a flow, from its origin's side.
    init(flow: Int, in web: RouteWeb) {
        airport = web.flows[flow].from
        route = web.routes(of: airport).firstIndex(of: flow)
    }

    init(airport: Int, route: Int? = nil) {
        self.airport = airport
        self.route = route
    }

    func moved(_ direction: ChartDirection, in web: RouteWeb) -> RouteWebCursor? {
        let n = web.airports.count
        guard n > 0 else { return nil }
        switch direction {
        case .right:
            return RouteWebCursor(airport: (airport + 1) % n)
        case .left:
            return RouteWebCursor(airport: (airport - 1 + n) % n)
        case .down:
            let next = route.map { $0 + 1 } ?? 0
            return next < web.routes(of: airport).count ? RouteWebCursor(airport: airport, route: next) : nil
        case .up:
            guard let route else { return nil }
            return RouteWebCursor(airport: airport, route: route > 0 ? route - 1 : nil)
        }
    }

    /// The picked flow (an index into `web.flows`), when a route is picked.
    func flow(in web: RouteWeb) -> Int? {
        guard let route else { return nil }
        let routes = web.routes(of: airport)
        return routes.indices.contains(route) ? routes[route] : nil
    }

    /// The sightings behind it: the route, or every flight to or from the airport.
    func filter(in web: RouteWeb) -> LogbookFilter {
        if let flow = flow(in: web) { return .route(web.routeKey(web.flows[flow])) }
        return .airport(web.airports[airport].id)
    }

    /// For VoiceOver: "XNA to ATL, 86 flights", or "XNA, Bentonville: 212 flights, 110 out,
    /// 102 in".
    func spokenSummary(in web: RouteWeb) -> String {
        if let f = flow(in: web) {
            let flow = web.flows[f]
            return "\(web.airports[flow.from].id) to \(web.airports[flow.to].id), \(RadarFormat.wholeNumber(flow.count)) flights"
        }
        let a = web.airports[airport]
        return "\(a.id)\(a.city.map { ", \($0)" } ?? ""): \(RadarFormat.wholeNumber(a.total)) flights, \(RadarFormat.wholeNumber(a.outbound)) out, \(RadarFormat.wholeNumber(a.inbound)) in"
    }
}
