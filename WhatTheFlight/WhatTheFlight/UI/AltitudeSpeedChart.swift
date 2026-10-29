//
//  AltitudeSpeedChart.swift
//  WhatTheFlight
//
//  The Stats tab's headline chart on iPhone, iPad and Apple TV: every aircraft of the chosen
//  sky as a dot at its closest pass, speed across and altitude up, coloured by the kind of
//  flight. Airliners make a cruising band up top; light aircraft and helicopters crowd the
//  bottom left. On iPhone and iPad tap a dot, or drag sideways (or press and drag) to run
//  along them. On the TV the card on the page is just the chart; a click opens it full
//  screen, where the remote steps from dot to dot and a click opens the full card. The dots are one vectorized `PointPlot` that picking never redraws:
//  the ring and callout sit in an overlay that reads `AltitudeSpeedSelection`, and the plot
//  under it is Equatable, so the views around it can read the selection too.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import Charts
import Accessibility

struct AltitudeSpeedChart: View {
    enum Phase {
        case loading
        case failed
        case ready(AltitudeSpeedSet)
    }

    let phase: Phase
    var scale: CGFloat = 1
    /// The chart's height, legend included, at `scale` 1. The same in every phase.
    var height: CGFloat = 300
    /// About six ticks along the speed axis when there's room, four on a phone.
    var wide = false
    /// TV: the whole sighting, for the card a click opens.
    var sighting: @MainActor (String) -> Sighting? = { _ in nil }

    @LazyState private var selection = AltitudeSpeedSelection()
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    #if os(tvOS)
    @State private var exploring = false
    #endif

    var body: some View {
        #if os(tvOS)
        TVExplorableCard(isExploring: $exploring) {
            content(interactive: false)
        } explorer: {
            TVChartExplorer(title: "Altitude vs speed", detail: countText,
                            hint: "◀ ▶ ▲ ▼ step from dot to dot · Click for the full card · Back to return to Stats",
                            move: move, select: toggleCard, back: closeCard, spoken: spokenPick) {
                chart(interactive: true)
            }
            .onAppear { focusChanged(true) }
            .onDisappear { focusChanged(false) }
        }
        #else
        content(interactive: true)
            .logbookCard(padding: 18)
        #endif
    }

    private var set: AltitudeSpeedSet? {
        if case .ready(let set) = phase { return set }
        return nil
    }

    private var countText: String? { self.set.map { "\(RadarFormat.wholeNumber($0.count)) aircraft" } }

    /// `interactive` is off for the TV's card on the page: it's only a picture until it's opened.
    private func content(interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            header
            Text(Self.note)
                .chartFont(11, scale: scale)
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
            chart(interactive: interactive)
                .frame(height: height * scale)
        }
    }

    #if os(tvOS)
    private static var note: LocalizedStringKey { "Each dot is one sighting at its closest point. Click to explore it dot by dot." }
    #else
    private static var note: LocalizedStringKey { "Each dot is one sighting at its closest point. Tap a dot, or drag sideways to run along them." }
    #endif

    @ViewBuilder
    private var header: some View {
        let count = countText
        #if os(tvOS)
        HStack(alignment: .firstTextBaseline) {
            Text("Altitude vs speed").radarCaptionTV()
            Spacer()
            if let count {
                Text(count).font(.mono(22, .bold)).foregroundStyle(Palette.value)
            }
        }
        #else
        LogbookHeader(title: "Altitude vs speed") {
            if let count { Text(count) }
        }
        #endif
    }

    @ViewBuilder
    private func chart(interactive: Bool) -> some View {
        switch phase {
        case .loading:
            AltitudeSpeedPlot(set: .placeholder, scale: scale, wide: wide, isPlaceholder: true)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Loading altitude and speed")
        case .failed:
            HStack(spacing: 8 * scale) {
                Circle()
                    .fill(Palette.signal)
                    .frame(width: 7 * scale, height: 7 * scale)
                Text("Failed to load")
                    .chartFont(13, .semibold, scale: scale)
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .ready(let set):
            AltitudeSpeedPlot(set: set, scale: scale, wide: wide, shapes: differentiateWithoutColor,
                              selection: interactive ? selection : nil, sighting: sighting)
                .equatable()
            #if os(iOS)
                .overlay {
                    AltitudeSpeedReadout(set: set, selection: selection)
                        .allowsHitTesting(false)
                }
            #endif
        }
    }

    #if os(tvOS)
    private func toggleCard() {
        guard selection.id != nil else { return }
        withAnimation(.snappy(duration: 0.2)) { selection.isExpanded.toggle() }
    }

    /// Back closes the full card first.
    private func closeCard() -> Bool {
        guard selection.isExpanded else { return false }
        withAnimation(.snappy(duration: 0.2)) { selection.isExpanded = false }
        return true
    }

    /// Opening the chart starts on the airliner nearest the middle; closing it clears the pick.
    private func focusChanged(_ exploring: Bool) {
        guard let set else { return }
        selection.isExpanded = false
        selection.select(exploring ? set.startIndex : nil, in: set)
    }

    private func spokenPick() -> String {
        guard let set, let index = selection.index(in: set) else { return "" }
        return set.points[index].spokenSummary
    }

    /// Moves the pick to the nearest dot that way. At the edge of the data nothing moves.
    private func move(_ direction: ChartDirection) {
        guard let set, let current = selection.index(in: set) ?? set.startIndex,
              let next = neighbor(of: current, toward: direction, in: set) else { return }
        selection.isExpanded = false
        selection.select(next, in: set)
    }

    /// Dots within a couple of points of each other read as one, so a step goes to the next place.
    private func neighbor(of index: Int, toward direction: ChartDirection, in set: AltitudeSpeedSet) -> Int? {
        let size = selection.plotSize
        guard size.width > 0, size.height > 0 else { return nil }
        return ScatterPicking.step(from: index, toward: direction, in: set.positions(in: size), minimumDistance: 2 * scale)
    }
    #endif
}

// MARK: - Selection

/// Which dot is picked. The overlay reads it (and VoiceOver's readout); the plot under them
/// is Equatable, so a pick never redraws the dots.
@MainActor
@Observable
final class AltitudeSpeedSelection {
    /// The picked sighting. An id, not an index, so it survives the logbook changing.
    private(set) var id: String?
    /// TV: the full card is open.
    var isExpanded = false
    /// The plot's size, for the remote's moves.
    @ObservationIgnored var plotSize: CGSize = .zero
    /// Where `id` was last found, so the lookup is usually free.
    @ObservationIgnored private var hint = 0

    func index(in set: AltitudeSpeedSet) -> Int? {
        guard let id else { return nil }
        if set.points.indices.contains(hint), set.points[hint].id == id { return hint }
        guard let found = set.points.firstIndex(where: { $0.id == id }) else { return nil }
        hint = found
        return found
    }

    func select(_ index: Int?, in set: AltitudeSpeedSet) {
        let picked = index.map { set.points[$0].id }
        if picked == nil { isExpanded = false }
        guard picked != id else { return }
        id = picked
        hint = index ?? 0
    }
}

// MARK: - The dots

/// The dots, axes and legend, plus the selection overlay (none without a `selection`).
/// Equatable on what it draws, so a parent redrawing (a new GPS fix, the TV card taking
/// focus) doesn't redraw thousands of dots.
private struct AltitudeSpeedPlot: View, Equatable {
    let set: AltitudeSpeedSet
    let scale: CGFloat
    let wide: Bool
    var shapes = false
    var isPlaceholder = false
    var selection: AltitudeSpeedSelection?
    var sighting: (@MainActor (String) -> Sighting?)?

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.set.fingerprint == b.set.fingerprint && a.set.speedDomain == b.set.speedDomain
            && a.set.altitudeDomain == b.set.altitudeDomain && a.scale == b.scale && a.wide == b.wide
            && a.shapes == b.shapes && a.isPlaceholder == b.isPlaceholder && a.selection === b.selection
    }

    var body: some View {
        Chart { dots }
            .chartForegroundStyleScale(domain: set.kinds, range: set.kinds.map(\.tone))
            .chartSymbolScale(domain: set.kinds, range: set.kinds.map(\.symbol))
            .chartXScale(domain: set.speedDomain)
            .chartYScale(domain: set.altitudeDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: wide ? 6 : 4)) { value in
                    AxisValueLabel {
                        if let speed = value.as(Double.self) {
                            Text(AltitudeSpeed.speedAxisLabel(speed, isLast: value.index == value.count - 1))
                                .font(.mono(10 * scale, .semibold))
                                .foregroundStyle(Palette.caption)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1 * scale))
                        .foregroundStyle(Palette.ink.opacity(0.08))
                    AxisValueLabel {
                        if let altitude = value.as(Double.self) {
                            Text(AltitudeSpeed.altitudeAxisLabel(altitude))
                                .font(.mono(10 * scale, .semibold))
                                .foregroundStyle(Palette.caption)
                        }
                    }
                }
            }
            .chartLegend(isPlaceholder ? .hidden : .automatic)
            #if os(tvOS)
            .chartLegend(position: .top, alignment: .leading, spacing: 12 * scale) {
                AltitudeSpeedLegend(kinds: set.kinds, shapes: shapes, scale: scale)
            }
            #else
            .chartLegend(position: .top, alignment: .leading, spacing: 12 * scale)
            #endif
            .chartOverlay { proxy in
                if let selection {
                    GeometryReader { geo in
                        if let frame = proxy.plotFrame {
                            let plot = geo[frame]
                            AltitudeSpeedOverlay(set: set, selection: selection, size: plot.size, scale: scale, sighting: sighting)
                                .frame(width: plot.width, height: plot.height)
                                .offset(x: plot.minX, y: plot.minY)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Altitude versus speed")
            .accessibilityValue(isPlaceholder ? "" : set.summary)
            .accessibilityChartDescriptor(AltitudeSpeedDescriptor(set: set))
    }

    /// Small, so the busy bands read as darker patches; larger on the TV.
    private var dotArea: CGFloat {
        let diameter = 5 * scale
        return diameter * diameter
    }

    @ChartContentBuilder
    private var dots: some ChartContent {
        if isPlaceholder {
            PointPlot(set.points, x: .value("Speed", \.speed), y: .value("Altitude", \.altitude))
                .foregroundStyle(Palette.faint)
                .symbolSize(dotArea)
                .opacity(0.5)
        } else if shapes {
            // Differentiate Without Color: a shape per kind too, a little bigger to read.
            PointPlot(set.points, x: .value("Speed", \.speed), y: .value("Altitude", \.altitude))
                .foregroundStyle(by: .value("Kind", \.kind))
                .symbol(by: .value("Kind", \.kind))
                .symbolSize(dotArea * 1.8)
                .opacity(0.55)
        } else {
            PointPlot(set.points, x: .value("Speed", \.speed), y: .value("Altitude", \.altitude))
                .foregroundStyle(by: .value("Kind", \.kind))
                .symbolSize(dotArea)
                .opacity(0.55)
        }
    }
}

extension FlightKind: Plottable {
    /// The legend shows it.
    var primitivePlottable: String { title }

    init?(primitivePlottable: String) {
        guard let kind = Self.allCases.first(where: { $0.title == primitivePlottable }) else { return nil }
        self = kind
    }

    /// The logbook's tones; military keeps the olive it has on the radar.
    var tone: Color {
        switch self {
        case .airline: return ChartTone.sky.color
        case .cargo: return ChartTone.coral.color
        case .businessJet: return ChartTone.teal.color
        case .generalAviation: return ChartTone.amber.color
        case .helicopter: return ChartTone.pink.color
        case .military: return Palette.military
        }
    }

    /// The shape each kind takes with Differentiate Without Color on, the same whichever
    /// kinds are present.
    var symbol: BasicChartSymbolShape {
        switch self {
        case .airline: return .circle
        case .cargo: return .square
        case .businessJet: return .diamond
        case .generalAviation: return .triangle
        case .helicopter: return .pentagon
        case .military: return .cross
        }
    }
}

#if os(tvOS)
/// TV: the legend at ten-foot size (Swift Charts' own has pinhead swatches there), drawn from
/// the same kinds, colours and shapes as the chart's scales.
private struct AltitudeSpeedLegend: View {
    let kinds: [FlightKind]
    let shapes: Bool
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 22 * scale) {
            ForEach(kinds, id: \.self) { kind in
                HStack(spacing: 7 * scale) {
                    (shapes ? AnyShape(kind.symbol) : AnyShape(Circle()))
                        .fill(kind.tone)
                        .frame(width: 8 * scale, height: 8 * scale)
                    Text(kind.title)
                        .font(.mono(11 * scale, .semibold))
                        .foregroundStyle(Palette.caption)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
#endif

// MARK: - Picking

/// Over the plot: the ring and callout on the picked dot and, on iPhone and iPad, the touch
/// handling. Re-renders on every pick; the dots underneath don't.
private struct AltitudeSpeedOverlay: View {
    let set: AltitudeSpeedSet
    let selection: AltitudeSpeedSelection
    let size: CGSize
    let scale: CGFloat
    let sighting: (@MainActor (String) -> Sighting?)?

    /// How close a finger has to be to pick a dot.
    private static let reach: CGFloat = 24

    var body: some View {
        let index = selection.index(in: set)
        ZStack(alignment: .topLeading) {
            #if os(iOS)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { pick(at: $0, clearsWhenMissed: true) }
                .gesture(SidewaysScrub { pick(at: $0) })
                .gesture(PressAndScrub { pick(at: $0) })
            #endif
            if let index {
                let point = set.points[index]
                let anchor = set.position(of: index, in: size)
                Circle()
                    .stroke(Palette.value, lineWidth: 1.5 * scale)
                    .frame(width: 11 * scale, height: 11 * scale)
                    .position(anchor)
                CalloutPlacement(anchor: anchor, gap: 10 * scale) {
                    if selection.isExpanded {
                        AltitudeSpeedDetailCard(point: point, sighting: sighting?(point.id), scale: scale)
                    } else {
                        AltitudeSpeedCallout(point: point, scale: scale)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: size, initial: true) { selection.plotSize = size }
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: selection.id) { _, picked in picked != nil }
        #endif
    }

    #if os(iOS)
    private func pick(at location: CGPoint, clearsWhenMissed: Bool = false) {
        if let i = ScatterPicking.nearest(to: location, in: set.positions(in: size), within: Self.reach) {
            selection.select(i, in: set)
        } else if clearsWhenMissed {
            selection.select(nil, in: set)
        }
    }
    #endif
}

/// Places one callout beside the picked dot, inside the plot (`ScatterPicking.calloutOrigin`):
/// above it, else beside it, else below, so it moves rather than clips.
private struct CalloutPlacement: Layout {
    let anchor: CGPoint
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            let origin = ScatterPicking.calloutOrigin(size: size, anchor: anchor, in: bounds.size, gap: gap)
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: ProposedViewSize(size))
        }
    }
}

/// "AA768 · Oct 19, 10:20 PM CT", then the type with its colour, altitude, speed and route.
private struct AltitudeSpeedCallout: View {
    let point: AltitudeSpeedPoint
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(point.headline())
                .chartFont(12, .bold, scale: scale)
                .foregroundStyle(Palette.ink)
            HStack(spacing: 5 * scale) {
                Circle()
                    .fill(point.kind.tone)
                    .frame(width: 8 * scale, height: 8 * scale)
                Text(point.model)
                    .chartFont(11, .semibold, scale: scale)
                    .foregroundStyle(Palette.value)
                Text(point.kind.title)
                    .chartFont(10, scale: scale)
                    .foregroundStyle(Palette.caption)
            }
            CalloutRow(label: "Altitude", value: point.altitudeText, scale: scale)
            CalloutRow(label: "Speed", value: point.speedText, scale: scale)
            CalloutRow(label: "Route", value: point.route, scale: scale)
        }
        .lineLimit(1)
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 7 * scale)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 9 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).stroke(Palette.ink.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 6 * scale, y: 2 * scale)
        .fixedSize()
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct CalloutRow: View {
    let label: LocalizedStringKey
    let value: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text(label).foregroundStyle(Palette.caption)
            Text(": ").foregroundStyle(Palette.caption)
            Text(value).foregroundStyle(Palette.value)
        }
        .chartFont(11, scale: scale)
    }
}

/// TV: the full card for the picked sighting, opened with a click.
private struct AltitudeSpeedDetailCard: View {
    let point: AltitudeSpeedPoint
    let sighting: Sighting?
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack(spacing: 12 * scale) {
                AircraftGlyph(silhouette: AircraftTypeCatalog.silhouette(forTypeCode: point.typeCode), size: 34 * scale, spinsRotor: false)
                    .foregroundStyle(point.kind.tone)
                VStack(alignment: .leading, spacing: 2 * scale) {
                    Text(point.flight)
                        .chartFont(20, .heavy, scale: scale)
                        .foregroundStyle(Palette.ink)
                    Text(point.model)
                        .chartFont(12, .semibold, scale: scale)
                        .foregroundStyle(Palette.value)
                }
            }
            HStack(spacing: 6 * scale) {
                Circle()
                    .fill(point.kind.tone)
                    .frame(width: 9 * scale, height: 9 * scale)
                Text([point.kind.title, sighting?.operatorName].compactMap { $0 }.joined(separator: " · "))
                    .chartFont(11, .semibold, scale: scale)
                    .foregroundStyle(Palette.value)
            }
            Divider()
            CalloutRow(label: "Seen", value: AltitudeSpeed.timeText(point.firstSeen), scale: scale)
            CalloutRow(label: "Altitude", value: point.altitudeText, scale: scale)
            CalloutRow(label: "Speed", value: point.speedText, scale: scale)
            CalloutRow(label: "Route", value: point.route, scale: scale)
            if let sighting {
                CalloutRow(label: "Closest", value: RadarFormat.preciseDistance(sighting.closestMiles), scale: scale)
                if let registration = sighting.registration {
                    CalloutRow(label: "Registration", value: registration, scale: scale)
                }
                if let place = sighting.placeName {
                    CalloutRow(label: "Watched from", value: place, scale: scale)
                }
            }
            Text("Click or press Back to close")
                .chartFont(10, scale: scale)
                .foregroundStyle(Palette.caption)
                .padding(.top, 2 * scale)
        }
        .lineLimit(1)
        .padding(12 * scale)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous).stroke(Palette.ink.opacity(0.18), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.2), radius: 12 * scale, y: 4 * scale)
        .fixedSize()
    }
}

#if os(iOS)
/// VoiceOver's way in: the picked sighting, read out, and swipe up or down to step through
/// them by speed.
private struct AltitudeSpeedReadout: View {
    let set: AltitudeSpeedSet
    let selection: AltitudeSpeedSelection

    var body: some View {
        let index = selection.index(in: set)
        Color.clear
            .accessibilityElement()
            .accessibilityLabel("Picked sighting")
            .accessibilityValue(index.map { set.points[$0].spokenSummary } ?? String(localized: "None"))
            .accessibilityHint("Swipe up or down to step through the sightings by speed.")
            .accessibilityAdjustableAction { direction in
                let next: Int?
                switch direction {
                case .increment: next = index.map { set.step(from: $0, by: 1) } ?? set.startIndex
                case .decrement: next = index.map { set.step(from: $0, by: -1) } ?? set.startIndex
                @unknown default: next = nil
                }
                if let next { selection.select(next, in: set) }
            }
    }
}

/// A drag that only starts sideways, so a swipe up or down over the chart still scrolls the
/// page. The page's scroll waits for it to decide, which an up-or-down swipe does at once.
private struct SidewaysScrub: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if recognizer.state == .began || recognizer.state == .changed {
            onChange(context.converter.localLocation)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView
        }
    }
}

/// Hold still for a moment, then drag in any direction. Moving first scrolls the page instead.
private struct PressAndScrub: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.2
        return press
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        if recognizer.state == .began || recognizer.state == .changed {
            onChange(context.converter.localLocation)
        }
    }
}
#endif

/// The chart for VoiceOver's Audio Graph: speed across, altitude up, a series per kind.
private struct AltitudeSpeedDescriptor: AXChartDescriptorRepresentable {
    let set: AltitudeSpeedSet

    func makeChartDescriptor() -> AXChartDescriptor {
        let speed = AXNumericDataAxisDescriptor(title: "Speed", range: set.speedDomain, gridlinePositions: []) { value in
            "\(RadarFormat.wholeNumber(Int(value.rounded()))) \(RadarFormat.speedUnit())"
        }
        let altitude = AXNumericDataAxisDescriptor(title: "Altitude", range: set.altitudeDomain, gridlinePositions: []) { value in
            "\(RadarFormat.wholeNumber(Int(value.rounded()))) \(RadarFormat.altitudeUnit())"
        }
        let series = set.kinds.map { kind in
            AXDataSeriesDescriptor(name: kind.title, isContinuous: false, dataPoints: set.points.filter { $0.kind == kind }.map {
                AXDataPoint(x: $0.speed, y: $0.altitude, label: $0.flight)
            })
        }
        return AXChartDescriptor(title: "Altitude versus speed", summary: set.summary,
                                 xAxis: speed, yAxis: altitude, additionalAxes: [], series: series)
    }
}

private extension View {
    /// SF Mono: fixed on the TV, following Dynamic Type on iPhone and iPad.
    @ViewBuilder
    func chartFont(_ size: CGFloat, _ weight: Font.Weight = .regular, scale: CGFloat) -> some View {
        #if os(tvOS)
        font(.mono(size * scale, weight))
        #else
        monoScaled(size * scale, weight)
        #endif
    }
}

// MARK: - Sample data

extension AltitudeSpeedSet {
    /// Grey dots behind the loading skeleton.
    static let placeholder = sample(count: 160, seed: 7)

    /// Made-up traffic shaped like a real sky (airliners cruising high and fast, climbing and
    /// descending through the middle; light aircraft and helicopters low and slow), for the
    /// skeleton and previews. The same every time for a given seed.
    static func sample(count: Int, seed: UInt64 = 1) -> AltitudeSpeedSet {
        var state = seed
        func random() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        func between(_ low: Double, _ high: Double) -> Double { low + (high - low) * random() }
        let airports = ["CLT", "OKC", "DFW", "ATL", "ORD", "DEN", "XNA", "MEM", "LAX", "MCO"]
        let start = Date(timeIntervalSince1970: 1_792_000_000)
        let sightings = (0..<count).map { i -> Sighting in
            let roll = random()
            let operatorName: String, type: String, flight: String?, kind: AircraftKind
            var tags: [NotableTag] = []
            let speed: Double, altitude: Double
            switch roll {
            case ..<0.70:
                operatorName = ["American Airlines", "Delta Air Lines", "Southwest Airlines", "United Airlines"][i % 4]
                type = ["B738", "A321", "E75L", "B39M"][i % 4]
                flight = "\(["AA", "DL", "WN", "UA"][i % 4])\(100 + i)"
                kind = .airplane
                switch random() {
                case ..<0.45: speed = between(420, 520); altitude = between(30_000, 40_000)
                case ..<0.8: speed = between(200, 420); altitude = max(2_000, (speed - 150) * 100 + between(-4_000, 4_000))
                default: speed = between(130, 200); altitude = between(800, 6_000)
                }
            case ..<0.75:
                operatorName = ["FedEx", "UPS Airlines"][i % 2]
                type = ["B763", "B77L"][i % 2]
                flight = "\(["FX", "5X"][i % 2])\(1_000 + i)"
                kind = .airplane
                speed = between(380, 540); altitude = between(24_000, 39_000)
            case ..<0.80:
                operatorName = ["NetJets", "Flexjet"][i % 2]
                type = ["C68A", "GLF5"][i % 2]
                flight = nil
                kind = .airplane
                speed = between(250, 480); altitude = between(12_000, 45_000)
            case ..<0.93:
                operatorName = "Private aircraft"
                type = ["C172", "PA28", "SR22"][i % 3]
                flight = nil
                kind = .airplane
                speed = between(60, 170); altitude = between(1_000, 10_000)
            case ..<0.97:
                operatorName = "Private helicopter"
                type = ["EC35", "R44"][i % 2]
                flight = nil
                kind = .helicopter
                speed = between(20, 140); altitude = between(300, 2_000)
            default:
                operatorName = "US Air Force · Air Mobility Command"
                type = ["C17", "K35R"][i % 2]
                flight = "RCH\(200 + i)"
                kind = .airplane
                tags = [.military]
                speed = between(150, 500); altitude = between(1_000, 40_000)
            }
            let registration = flight == nil ? "N\(100 + i)\(["AB", "CD", "EF"][i % 3])" : nil
            let seen = start.addingTimeInterval(Double(i) * 1_700)
            return Sighting(id: "sample-\(i)", firstSeen: seen, lastSeen: seen.addingTimeInterval(300),
                            displayIdentifier: flight ?? registration ?? type, callsign: flight, registration: registration,
                            hex: nil, typeCode: type, kind: kind, operatorName: operatorName, isAirline: flight != nil,
                            originIATA: flight == nil ? nil : airports[i % airports.count],
                            destinationIATA: flight == nil ? nil : airports[(i * 7 + 3) % airports.count],
                            closestMiles: between(0.3, 9), altitudeAtClosestFeet: Int(altitude), speedKnots: Int(speed),
                            tags: tags, placeName: "Bentonville, AR")
        }
        return AltitudeSpeedSet(sightings: sightings)
    }
}

#if DEBUG
#if os(tvOS)
#Preview("Apple TV · light") {
    ScrollView {
        AltitudeSpeedChart(phase: .ready(.sample(count: 2_400)), scale: 1.8, height: 300, wide: true)
            .padding(.horizontal, 100)
            .padding(.vertical, 60)
    }
    .background(LogbookBackdrop())
    .preferredColorScheme(.light)
}

#Preview("Apple TV · dark") {
    ScrollView {
        AltitudeSpeedChart(phase: .ready(.sample(count: 2_400)), scale: 1.8, height: 300, wide: true)
            .padding(.horizontal, 100)
            .padding(.vertical, 60)
    }
    .background(LogbookBackdrop())
    .preferredColorScheme(.dark)
}
#else
#Preview("iPhone · light", traits: .fixedLayout(width: 393, height: 520)) {
    AltitudeSpeedChart(phase: .ready(.sample(count: 2_400)))
        .padding(16)
        .background(LogbookBackdrop())
        .preferredColorScheme(.light)
}

#Preview("iPhone · dark", traits: .fixedLayout(width: 393, height: 520)) {
    AltitudeSpeedChart(phase: .ready(.sample(count: 2_400)))
        .padding(16)
        .background(LogbookBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("iPad · light", traits: .fixedLayout(width: 820, height: 560)) {
    AltitudeSpeedChart(phase: .ready(.sample(count: 2_400)), height: 340, wide: true)
        .padding(24)
        .background(LogbookBackdrop())
        .preferredColorScheme(.light)
}

#Preview("iPad · dark", traits: .fixedLayout(width: 820, height: 560)) {
    AltitudeSpeedChart(phase: .ready(.sample(count: 2_400)), height: 340, wide: true)
        .padding(24)
        .background(LogbookBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Loading and failed", traits: .fixedLayout(width: 393, height: 900)) {
    VStack(spacing: 16) {
        AltitudeSpeedChart(phase: .loading)
        AltitudeSpeedChart(phase: .failed)
    }
    .padding(16)
    .background(LogbookBackdrop())
}
#endif
#endif
#endif
