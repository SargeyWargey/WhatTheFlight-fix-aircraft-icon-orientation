//
//  RouteWebChart.swift
//  WhatTheFlight
//
//  The route web on the Stats tab (iPhone, iPad, Apple TV): where the aircraft over this sky
//  were flying, as a ring of the busiest route airports with a ribbon for each route between
//  them, coloured by where it left from and pointed where it was going. Beside it (under it
//  on iPhone) a panel lists the picked airport's routes, busiest first. On iPhone and iPad
//  tap an airport or a ribbon, then follow the link to those flights. On the TV the card on
//  the page is just the picture; a click opens it full screen, where ◀ ▶ go round the
//  airports, ▼ ▲ walk down and up their routes, and a click opens the flights.
//

#if os(iOS) || os(tvOS)
import SwiftUI

struct RouteWebChart: View {
    let web: RouteWeb
    var scale: CGFloat = 1
    /// The ring's largest size, labels included, at `scale` 1.
    var diameter: CGFloat = 300
    /// The routes beside the ring (iPad, TV) rather than under it.
    var wide = false
    #if os(tvOS)
    /// TV: where a click finds the flights behind the pick (iPhone and iPad link to them).
    var logbook: Logbook? = nil
    var showPhotos = true
    #endif

    @State private var cursor: RouteWebCursor?
    #if os(tvOS)
    @State private var exploring = false
    /// The picked route's (or airport's) flights, shown over the chart.
    @State private var flights: TVSightingBrowse?
    #endif

    var body: some View {
        #if os(tvOS)
        TVExplorableCard(isExploring: $exploring) {
            content(interactive: false)
        } explorer: {
            TVChartExplorer(title: "Route web", detail: countText,
                            hint: "◀ ▶ go round the airports · ▼ ▲ through their routes · Click to see the flights · Back to return to Stats",
                            move: move, select: openPick, spoken: { picked?.spokenSummary(in: web) ?? web.summary }) {
                rings(interactive: true, side: 760)
            }
            .onAppear { cursor = web.airports.isEmpty ? nil : RouteWebCursor(airport: 0) }
            .onDisappear { cursor = nil }
            // Over the chart, so back returns to it to try another route.
            .fullScreenCover(item: $flights) { browse in
                if let logbook {
                    TVSightingDetailView(browse: browse, logbook: logbook, showTopography: true, showPhotos: showPhotos) { _ in }
                }
            }
        }
        .onChange(of: web.airports.map(\.id)) { cursor = nil }
        #else
        content(interactive: true)
            .logbookCard(padding: 18)
            .onChange(of: web.airports.map(\.id)) { cursor = nil }
        #endif
    }

    /// The cursor, if it still fits this web.
    private var picked: RouteWebCursor? {
        cursor.flatMap { web.airports.indices.contains($0.airport) ? $0 : nil }
    }

    private var countText: String { "\(RadarFormat.wholeNumber(web.total)) flights" }

    /// `interactive` is off for the TV's card on the page: it's only a picture until it's opened.
    private func content(interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            header
            Text(note)
                .routeWebFont(11, scale: scale)
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
            rings(interactive: interactive, side: diameter * scale)
        }
    }

    /// The ring and the routes, side by side when `wide`.
    private func rings(interactive: Bool, side: CGFloat) -> some View {
        let cursor = interactive ? picked : nil
        let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 32 * scale))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 16 * scale))
        return layout {
            RouteWebDiagram(web: web, cursor: cursor, scale: scale) { self.cursor = $0 }
                .frame(maxWidth: side, maxHeight: side)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: wide ? nil : .infinity)
            RouteWebPanel(web: web, cursor: cursor, scale: scale) { self.cursor = $0 }
        }
    }

    @ViewBuilder
    private var header: some View {
        let count = countText
        #if os(tvOS)
        HStack(alignment: .firstTextBaseline) {
            Text("Route web").radarCaptionTV()
            Spacer()
            Text(count).font(.mono(22, .bold)).foregroundStyle(Palette.value)
        }
        #else
        LogbookHeader(title: "Route web") { Text(count) }
        #endif
    }

    private var note: String {
        let what = "Where they were going: flights between the \(web.airports.count) busiest route airports, coloured by where they left from and pointing where they were headed."
        #if os(tvOS)
        return what + " Click to explore it airport by airport."
        #else
        return what + " Tap an airport or a ribbon."
        #endif
    }

    #if os(tvOS)
    private func move(_ direction: ChartDirection) {
        guard let next = (picked ?? RouteWebCursor(airport: 0)).moved(direction, in: web) else { return }
        cursor = next
    }

    /// Every flight on the picked route, or to and from the picked airport, newest first.
    private func openPick() {
        guard let picked, let logbook else { return }
        let matches = logbook.digest.sightings(matching: picked.filter(in: web), in: logbook.recent)
        if let first = matches.first { flights = TVSightingBrowse(matches, showing: first) }
    }
    #endif
}

// MARK: - The ring

/// Airport colours round the ring, busiest first: the logbook's tones in an order whose
/// neighbours stay apart for colour-blind eyes too (each arc is also named).
private let airportTones: [Color] = [ChartTone.sky.color, ChartTone.coral.color, ChartTone.teal.color, ChartTone.amber.color,
                                     ChartTone.pink.color, ChartTone.green.color, ChartTone.violet.color, Palette.signal]

private func airportTone(_ index: Int) -> Color { airportTones[index % airportTones.count] }

/// Sizes and paths for a ring of `side` points: arcs round the outside, labels beyond them,
/// ribbons inside ending in arrowheads at the ring.
private struct RouteWebGeometry {
    let web: RouteWeb
    let layout: RouteWeb.Layout
    let center: CGPoint
    let outer: CGFloat
    let ringWidth: CGFloat
    let head: CGFloat
    let labelRadius: CGFloat

    init(web: RouteWeb, side: CGFloat, scale: CGFloat) {
        self.web = web
        layout = web.layout()
        center = CGPoint(x: side / 2, y: side / 2)
        // Room for a three-letter code at 9 and 3 o'clock.
        labelRadius = side / 2 - 26 * scale
        outer = labelRadius - 8 * scale
        ringWidth = 8 * scale
        head = min(9 * scale, outer * 0.08)
    }

    var inner: CGFloat { outer - ringWidth }
    /// Where ribbons meet the ring, a hair inside it.
    var ribbonRadius: CGFloat { inner - 2 }

    /// Clockwise from the top.
    func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * sin(angle), y: center.y - radius * cos(angle))
    }

    /// Follows the circle from `start` to `end` (drawn as short straight steps).
    private func trace(_ path: inout Path, from start: Double, to end: Double, radius: CGFloat) {
        let steps = max(2, Int(abs(end - start) / 0.02))
        for i in 1...steps {
            path.addLine(to: point(start + (end - start) * Double(i) / Double(steps), radius))
        }
    }

    func arc(_ airport: Int) -> Path {
        let span = layout.arcs[airport]
        var path = Path()
        path.move(to: point(span.start, outer))
        trace(&path, from: span.start, to: span.end, radius: outer)
        path.addLine(to: point(span.end, inner))
        trace(&path, from: span.end, to: span.start, radius: inner)
        path.closeSubpath()
        return path
    }

    /// From the origin's end of the arc, through the middle, to an arrowhead at the destination.
    func ribbon(_ flow: Int) -> Path {
        let source = layout.sources[flow], target = layout.targets[flow]
        let r = ribbonRadius, h = min(head, r * 0.15)
        var path = Path()
        path.move(to: point(source.start, r))
        trace(&path, from: source.start, to: source.end, radius: r)
        path.addQuadCurve(to: point(target.start, r - h), control: center)
        path.addLine(to: point(target.mid, r))
        path.addLine(to: point(target.end, r - h))
        path.addQuadCurve(to: point(source.start, r), control: center)
        path.closeSubpath()
        return path
    }

    /// What a touch lands on: an airport (on the ring or its name), a ribbon, or nothing.
    func pick(at location: CGPoint) -> RouteWebCursor? {
        let dx = location.x - center.x, dy = location.y - center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance >= inner - 6 {
            return distance <= labelRadius + 24 ? layout.airport(at: atan2(dx, -dy)).map { RouteWebCursor(airport: $0) } : nil
        }
        // Smaller ribbons are drawn on top, so they're checked first.
        for flow in web.flows.indices.reversed() where ribbon(flow).contains(location) {
            return RouteWebCursor(flow: flow, in: web)
        }
        return nil
    }
}

/// The ring and its ribbons. Everything to do with the pick is drawn in the same pass: the
/// picked airport's (or route's) ribbons come forward, the rest fade back.
private struct RouteWebDiagram: View {
    let web: RouteWeb
    let cursor: RouteWebCursor?
    let scale: CGFloat
    let pick: (RouteWebCursor?) -> Void

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let geometry = RouteWebGeometry(web: web, side: side, scale: scale)
            let pickedFlow = cursor?.flow(in: web)
            Canvas { context, _ in
                for (i, flow) in web.flows.enumerated() {
                    let touches = cursor.map { flow.from == $0.airport || flow.to == $0.airport } ?? true
                    let strength: Double
                    switch (cursor, pickedFlow) {
                    case (nil, _): strength = 0.6
                    case (_, let picked?): strength = picked == i ? 0.95 : touches ? 0.2 : 0.06
                    default: strength = touches ? 0.85 : 0.08
                    }
                    let path = geometry.ribbon(i)
                    context.fill(path, with: .color(airportTone(flow.from).opacity(strength)))
                    context.stroke(path, with: .color(Palette.paper.opacity(0.5 * strength)), lineWidth: 0.6 * scale)
                }
                for (i, airport) in web.airports.enumerated() {
                    let lit = isLit(i, pickedFlow: pickedFlow)
                    context.fill(geometry.arc(i), with: .color(airportTone(i).opacity(lit ? 1 : 0.3)))
                    let mid = geometry.layout.arcs[i].mid
                    // Anchored on the side facing the ring, so names never overlap it.
                    let anchor = UnitPoint(x: 0.5 - 0.5 * sin(mid), y: 0.5 + 0.5 * cos(mid))
                    let label = Text(airport.id)
                        .font(.mono(11 * scale, cursor?.airport == i ? .heavy : .bold))
                        .foregroundStyle(lit ? Palette.value : Palette.faint)
                    context.draw(label, at: geometry.point(mid, geometry.labelRadius), anchor: anchor)
                }
            }
            .frame(width: side, height: side)
            #if os(iOS)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                let hit = geometry.pick(at: location)
                pick(hit == cursor ? nil : hit)
            }
            #endif
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route web")
        .accessibilityValue(cursor?.spokenSummary(in: web) ?? web.summary)
        #if os(iOS)
        .accessibilityHint("Swipe up or down to go round the airports.")
        .accessibilityAdjustableAction { direction in
            let forward = direction == .increment
            guard let cursor else {
                pick(RouteWebCursor(airport: forward ? 0 : web.airports.count - 1))
                return
            }
            pick(RouteWebCursor(airport: cursor.airport).moved(forward ? .right : .left, in: web))
        }
        #endif
    }

    /// Full colour unless something else is picked: the picked airport, and the airports at
    /// the other end of its routes (or of the picked route).
    private func isLit(_ airport: Int, pickedFlow: Int?) -> Bool {
        guard let cursor else { return true }
        if let pickedFlow { return web.flows[pickedFlow].from == airport || web.flows[pickedFlow].to == airport }
        return airport == cursor.airport || web.routes(of: cursor.airport).contains {
            web.flows[$0].from == airport || web.flows[$0].to == airport
        }
    }
}

// MARK: - The routes

/// Beside the ring: the picked airport and its routes, busiest first, or with nothing picked
/// the busiest routes of all.
private struct RouteWebPanel: View {
    let web: RouteWeb
    let cursor: RouteWebCursor?
    let scale: CGFloat
    let pick: (RouteWebCursor?) -> Void

    /// Rows shown at once; a long list scrolls to keep the picked route in view.
    private static let visibleRows = 9

    var body: some View {
        let flows = cursor.map { web.routes(of: $0.airport) } ?? Array(web.flows.indices.prefix(6))
        let picked = cursor?.route
        let first = max(0, min((picked ?? 0) - Self.visibleRows / 2, flows.count - Self.visibleRows))
        let shown = Array(flows.enumerated()).dropFirst(first).prefix(Self.visibleRows)
        let top = flows.map { web.flows[$0].count }.max() ?? 1
        VStack(alignment: .leading, spacing: 6 * scale) {
            heading
            if first > 0 { more("\(first) busier above") }
            ForEach(Array(shown), id: \.element) { row, flow in
                routeRow(flow, top: top, isPicked: row == picked) {
                    pick(cursor.map { RouteWebCursor(airport: $0.airport, route: row == picked ? nil : row) } ?? RouteWebCursor(flow: flow, in: web))
                }
            }
            let below = flows.count - first - shown.count
            if below > 0 { more("\(below) more below") }
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var heading: some View {
        if let cursor {
            let airport = web.airports[cursor.airport]
            VStack(alignment: .leading, spacing: 2 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                    Circle().fill(airportTone(cursor.airport)).frame(width: 10 * scale, height: 10 * scale)
                    Text(airport.id).routeWebFont(22, .heavy, scale: scale).foregroundStyle(Palette.ink)
                    if let city = airport.city {
                        Text(city).routeWebFont(13, .semibold, scale: scale).foregroundStyle(Palette.value).lineLimit(1)
                    }
                }
                Text("\(RadarFormat.wholeNumber(airport.total)) flights · \(RadarFormat.wholeNumber(airport.outbound)) out · \(RadarFormat.wholeNumber(airport.inbound)) in")
                    .routeWebFont(11, scale: scale)
                    .foregroundStyle(Palette.caption)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, 4 * scale)
        } else {
            Text("Busiest routes")
                .routeWebFont(11, .semibold, scale: scale)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
        }
    }

    /// "XNA → ATL", a bar for its share of the busiest, and how many.
    private func routeRow(_ index: Int, top: Int, isPicked: Bool, action: @escaping () -> Void) -> some View {
        let flow = web.flows[index]
        let label = HStack(spacing: 8 * scale) {
            Circle().fill(airportTone(flow.from)).frame(width: 8 * scale, height: 8 * scale)
            Text(web.title(flow))
                .routeWebFont(13, isPicked ? .heavy : .semibold, scale: scale)
                .foregroundStyle(isPicked ? Palette.ink : Palette.value)
                .lineLimit(1)
                .fixedSize()
            Capsule()
                .fill(airportTone(flow.from).opacity(isPicked ? 1 : 0.7))
                .frame(height: 4 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaleEffect(x: max(0.04, Double(flow.count) / Double(max(1, top))), anchor: .leading)
            Text(RadarFormat.wholeNumber(flow.count))
                .routeWebFont(13, .heavy, scale: scale)
                .foregroundStyle(Palette.value)
                .monospacedDigit()
        }
        .padding(.horizontal, 8 * scale)
        .padding(.vertical, 5 * scale)
        .background(isPicked ? Palette.ink.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(web.airports[flow.from].id) to \(web.airports[flow.to].id), \(flow.count) flights")
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        #if os(iOS)
        return Button(action: action) { label }.buttonStyle(.plain)
        #else
        return label
        #endif
    }

    private func more(_ text: String) -> some View {
        Text(text)
            .routeWebFont(10, scale: scale)
            .foregroundStyle(Palette.faint)
            .padding(.leading, 8 * scale)
    }

    @ViewBuilder
    private var footer: some View {
        #if os(iOS)
        if let cursor {
            let link: String = {
                if let f = cursor.flow(in: web) { return "Flights \(web.title(web.flows[f]))" }
                return "All flights to and from \(web.airports[cursor.airport].id)"
            }()
            NavigationLink(value: LogbookRoute.filter(cursor.filter(in: web))) {
                Text("\(link) ›")
            }
            .monoScaled(12, .bold)
            .foregroundStyle(Palette.ink)
            .padding(.top, 6)
        } else {
            Text("Tap an airport to see its routes.")
                .monoScaled(10)
                .foregroundStyle(Palette.caption)
                .padding(.top, 4)
        }
        #else
        Text(cursor == nil ? "Click to explore" : "Click to see these flights")
            .font(.mono(10 * scale))
            .foregroundStyle(Palette.caption)
            .padding(.top, 4 * scale)
        #endif
    }
}

private extension View {
    /// SF Mono: fixed on the TV, following Dynamic Type on iPhone and iPad.
    @ViewBuilder
    func routeWebFont(_ size: CGFloat, _ weight: Font.Weight = .regular, scale: CGFloat) -> some View {
        #if os(tvOS)
        font(.mono(size * scale, weight))
        #else
        monoScaled(size * scale, weight)
        #endif
    }
}

// MARK: - Previews

#if DEBUG
extension RouteWeb {
    /// Made-up flights round a home airport and its busiest neighbours, for previews.
    static func sample(seed: UInt64 = 3) -> RouteWeb {
        var state = seed
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        let airports = ["XNA", "ATL", "DEN", "ORD", "DFW", "SLC", "SFO", "LAX", "CLT", "MEM"]
        let weights = [9.0, 6, 4, 4, 5, 2, 2, 2, 1, 1]
        func draw() -> String {
            var x = random() * weights.reduce(0, +)
            for (code, w) in zip(airports, weights) { x -= w; if x < 0 { return code } }
            return airports[0]
        }
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let sightings = (0..<700).compactMap { i -> Sighting? in
            let from = draw(), to = draw()
            guard from != to else { return nil }
            let seen = start.addingTimeInterval(Double(i) * 900)
            return Sighting(id: "route-\(i)", firstSeen: seen, lastSeen: seen.addingTimeInterval(300), displayIdentifier: "DL\(i)",
                            callsign: "DAL\(i)", registration: nil, hex: nil, typeCode: "B738", kind: .airplane,
                            operatorName: "Delta Air Lines", isAirline: true, originIATA: from, destinationIATA: to,
                            closestMiles: 3, altitudeAtClosestFeet: 30_000, speedKnots: 440, tags: [], placeName: nil)
        }
        return RouteWeb(sightings)
    }
}

#if os(tvOS)
#Preview("Apple TV · dark") {
    ScrollView {
        RouteWebChart(web: .sample(), scale: 1.8, diameter: 300, wide: true)
            .padding(.horizontal, 100)
            .padding(.vertical, 60)
    }
    .background(LogbookBackdrop())
    .preferredColorScheme(.dark)
}
#else
#Preview("iPhone · light", traits: .fixedLayout(width: 393, height: 820)) {
    NavigationStack {
        ScrollView {
            RouteWebChart(web: .sample())
                .padding(16)
        }
        .background(LogbookBackdrop())
    }
    .preferredColorScheme(.light)
}

#Preview("iPad · dark", traits: .fixedLayout(width: 820, height: 560)) {
    NavigationStack {
        RouteWebChart(web: .sample(), diameter: 340, wide: true)
            .padding(24)
            .background(LogbookBackdrop())
    }
    .preferredColorScheme(.dark)
}
#endif
#endif
#endif
