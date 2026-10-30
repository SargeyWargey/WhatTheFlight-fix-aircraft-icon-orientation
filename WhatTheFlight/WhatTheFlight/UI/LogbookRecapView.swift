//
//  LogbookRecapView.swift
//  WhatTheFlight
//
//  "Your 2026 in the sky": a month or a year of the logbook as a stack of story cards to
//  swipe through and share, as pictures (each renders at 1080 × 1920) or as one video of
//  them all (`RecapVideo`). The entry card sits on the
//  Overview tab. The numbers come from `LogbookRecap`; every card leads with a picture of
//  them: a heat calendar, a 24-hour clock and heading rose, a waffle of the mix, ranking
//  bars and silhouettes, the altitude-speed cloud with the records ringed, and the new types.
//

#if os(iOS) || os(tvOS)
import SwiftUI

/// The fixed colours of a shareable card: they're pictures, so they ignore light and dark.
private enum RecapInk {
    static let text = Color.white
    static let soft = Color.white.opacity(0.72)
    static let faint = Color.white.opacity(0.45)
    /// Empty cells, tracks and tiles.
    static let wash = Color.white.opacity(0.11)
    /// What a chart rings or calls out: a pale gold that reads on every card's colour.
    static let highlight = Color(UIColor(rgb: 0xFFE27A))
    /// Text on a light fill (a heat cell, the highlight).
    static let onLight = Color(UIColor(rgb: 0x16123F))
    static let backgrounds: [(UInt32, UInt32)] = [
        (0x1B1F6B, 0x3A33D6), // indigo
        (0x0B4D52, 0x0B8573), // teal
        (0x5C2A0B, 0xB47200), // amber
        (0x5A1235, 0xC2347E), // pink
        (0x10325C, 0x2A78C8), // sky
        (0x5A1D10, 0xC9502A), // coral
    ]

    static func gradient(_ i: Int) -> LinearGradient {
        let pair = backgrounds[i % backgrounds.count]
        return LinearGradient(colors: [Color(UIColor(rgb: pair.0)), Color(UIColor(rgb: pair.1))], startPoint: .top, endPoint: .bottomTrailing)
    }

    /// Busier is warmer, as on the logbook's count bars: violet, pink, then amber.
    static func heat(_ fraction: Double) -> Color {
        ChartTone.blend([(0, .violet), (0.5, .pink), (0.9, .amber)], fraction)
    }
}

/// One card: a 360 × 640 story to share from iPhone and iPad, or a 720 × 405 landscape card
/// on the TV, with the headline on one side and the chart on the other.
struct RecapSlide: View {
    enum Kind: Int, CaseIterable, Identifiable {
        case cover, clock, variety, favorites, records, firsts
        var id: Int { rawValue }

        /// Which of `RecapInk.backgrounds`: night blue for the clock, warm for the records.
        fileprivate var background: Int {
            switch self {
            case .cover: return 0
            case .clock: return 4
            case .variety: return 1
            case .favorites: return 2
            case .records: return 5
            case .firsts: return 3
            }
        }
    }

    enum Format {
        /// Portrait, what Share sends.
        case story
        /// Landscape, for the TV.
        case wide

        var size: CGSize { self == .story ? CGSize(width: 360, height: 640) : CGSize(width: 720, height: 405) }
        var padding: CGFloat { self == .story ? 28 : 32 }
        /// What the charts lay themselves out in.
        var contentWidth: CGFloat { size.width - 2 * padding }
    }

    let kind: Kind
    let recap: LogbookRecap
    var format = Format.story

    private var isWide: Bool { format == .wide }
    private var width: CGFloat { format.contentWidth }
    /// Between the wide card's two columns.
    private static let columnGap: CGFloat = 28
    /// The tallest a wide card's chart can be.
    private static let wideChartHeight: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(recap.period.isYear ? "YOUR \(recap.period.shortTitle()) IN THE SKY" : "\(recap.period.title().uppercased()) IN THE SKY")
                    .font(.mono(11, .heavy))
                    .tracking(1.4)
                Spacer()
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(RecapInk.soft)
            .padding(.bottom, isWide ? 16 : 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.bottom, isWide ? 12 : 0)

            Text("WHAT THE FLIGHT?")
                .font(.mono(10, .heavy))
                .tracking(1.6)
                .foregroundStyle(RecapInk.faint)
        }
        .padding(format.padding)
        .frame(width: format.size.width, height: format.size.height)
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// The card's colour, lit from the top corner, with a radar's rings spreading from the
    /// bottom one.
    private var backdrop: some View {
        ZStack {
            RecapInk.gradient(kind.background)
            RadialGradient(colors: [Color.white.opacity(0.18), .clear], center: UnitPoint(x: 0.95, y: 0), startRadius: 0,
                           endRadius: isWide ? 520 : 380)
            Canvas { context, size in
                let center = CGPoint(x: size.width, y: size.height)
                for i in 1...10 {
                    let r = CGFloat(i) * 76
                    context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                   with: .color(.white.opacity(i % 3 == 0 ? 0.07 : 0.04)), lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .cover: cover
        case .clock: clock
        case .variety: variety
        case .favorites: favorites
        case .records: records
        case .firsts: firsts
        }
    }

    /// Story: one column. Wide: `left` at `leftWidth`, `right` in the rest, both from the top.
    @ViewBuilder
    private func columns<Left: View, Right: View>(leftWidth: CGFloat, @ViewBuilder left: (CGFloat) -> Left, @ViewBuilder right: (CGFloat) -> Right) -> some View {
        if isWide {
            HStack(alignment: .top, spacing: Self.columnGap) {
                left(leftWidth)
                    .frame(width: leftWidth, alignment: .topLeading)
                right(width - leftWidth - Self.columnGap)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                left(width)
                right(width)
            }
        }
    }

    // MARK: Cards

    private var cover: some View {
        Group {
            if isWide {
                HStack(alignment: .top, spacing: Self.columnGap) {
                    VStack(alignment: .leading, spacing: 0) {
                        coverHeadline
                        Spacer(minLength: 12)
                        busiestDay
                    }
                    .frame(width: 250, alignment: .topLeading)
                    activity(width: width - 250 - Self.columnGap, height: Self.wideChartHeight)
                        .frame(maxHeight: .infinity)
                }
            } else {
                // The headline up top, the calendar along the bottom: a poster, not a list.
                VStack(alignment: .leading, spacing: 0) {
                    coverHeadline
                    Spacer(minLength: 18)
                    activity(width: width, height: nil)
                    busiestDay
                        .padding(.top, 16)
                }
                .padding(.bottom, 18)
            }
        }
    }

    private var coverHeadline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RadarFormat.wholeNumber(recap.total))
                .font(.mono(isWide ? 72 : 84, .heavy))
                .foregroundStyle(RecapInk.text)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
            Text("aircraft logged")
                .font(.mono(22, .bold))
                .foregroundStyle(RecapInk.text)
            Text("on \(recap.daysWatched) \(recap.daysWatched == 1 ? "day" : "days")")
                .font(.mono(15, .semibold))
                .foregroundStyle(RecapInk.soft)
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var busiestDay: some View {
        if let busiest = recap.busiestDay, recap.daysWatched > 1 {
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(RecapInk.highlight, lineWidth: 2)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    label("Busiest day")
                    Text("\(busiest.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(RadarFormat.wholeNumber(busiest.count)) aircraft")
                        .font(.mono(14, .bold))
                        .foregroundStyle(RecapInk.text)
                        .lineLimit(isWide ? 2 : 1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func activity(width: CGFloat, height: CGFloat?) -> some View {
        if recap.period.isYear {
            RecapYearGrid(recap: recap, width: width, height: height)
        } else {
            RecapMonthCalendar(recap: recap, width: width, height: height)
        }
    }

    private var clock: some View {
        columns(leftWidth: 290) { _ in
            VStack(alignment: .leading, spacing: 0) {
                title("Around the clock")
                if let hour = recap.sky.busiestHourOfDay {
                    Text("Busiest between \(LogbookFormat.hourRange(hour))")
                        .font(.mono(13, .semibold))
                        .foregroundStyle(RecapInk.soft)
                        .padding(.top, 4)
                }
                if isWide {
                    Spacer(minLength: 12)
                    heading
                }
            }
        } right: { width in
            VStack(alignment: .leading, spacing: 0) {
                RecapClock(hourly: recap.sky.hourly, width: width)
                    .padding(.top, isWide ? 0 : 12)
                if !isWide {
                    heading
                        .padding(.top, 14)
                }
            }
        }
    }

    /// The heading rose and which way most were going.
    @ViewBuilder
    private var heading: some View {
        if recap.sky.headed >= 3, let top = recap.sky.topHeadings(1).first {
            HStack(spacing: 18) {
                RecapRose(sectors: recap.sky.headings)
                VStack(alignment: .leading, spacing: 3) {
                    label("Mostly heading")
                    // Two-part names ("West-northwest") break after the hyphen.
                    Text(LogbookFormat.sectorWords[top.sector])
                        .font(.mono(28, .heavy))
                        .foregroundStyle(RecapInk.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Int((top.share * 100).rounded()))% of aircraft")
                        .font(.mono(12, .semibold))
                        .foregroundStyle(RecapInk.soft)
                }
            }
        }
    }

    private var variety: some View {
        columns(leftWidth: 290) { _ in
            VStack(alignment: .leading, spacing: 0) {
                title("All sorts")
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                    GridRow {
                        number(recap.airframes, "different aircraft")
                        number(recap.airlines, recap.airlines == 1 ? "airline" : "airlines")
                    }
                    GridRow {
                        number(recap.types, recap.types == 1 ? "aircraft type" : "aircraft types")
                        number(recap.countries, recap.countries == 1 ? "country" : "countries")
                    }
                    GridRow {
                        number(recap.notable, "notable")
                        number(recap.photos, recap.photos == 1 ? "photo" : "photos")
                    }
                }
                .padding(.top, 16)
            }
        } right: { _ in
            if !recap.kinds.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    label("The mix · each square 1%")
                        .padding(.top, isWide ? 10 : 24)
                        .padding(.bottom, 10)
                    HStack(alignment: .top, spacing: 16) {
                        RecapWaffle(cells: recap.mixCells(), side: isWide ? 196 : 158)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recap.kinds, id: \.kind) { item in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(item.kind.tone)
                                        .frame(width: 10, height: 10)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(item.kind.title)
                                            .font(.mono(11, .bold))
                                            .foregroundStyle(RecapInk.text)
                                        Text(RadarFormat.wholeNumber(item.count))
                                            .font(.mono(10, .medium))
                                            .foregroundStyle(RecapInk.soft)
                                    }
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var favorites: some View {
        columns(leftWidth: 300) { width in
            VStack(alignment: .leading, spacing: 0) {
                title("Most seen")
                if recap.topAirline != nil {
                    label("Airlines")
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                    RecapRanking(items: recap.airlineRanking, width: width)
                }
                if recap.topAirline == nil && recap.topType == nil && recap.topAircraft == nil {
                    Text("Nothing twice yet. Next time.")
                        .font(.mono(16, .semibold))
                        .foregroundStyle(RecapInk.soft)
                        .padding(.top, 18)
                }
            }
        } right: { _ in
            VStack(alignment: .leading, spacing: 0) {
                if recap.topType != nil || recap.topAircraft != nil {
                    HStack(alignment: .top, spacing: 12) {
                        if let t = recap.topType {
                            favoriteTile("Type", silhouette: t.example.silhouette, title: t.title, detail: "\(RadarFormat.wholeNumber(t.count))× seen")
                        }
                        if let a = recap.topAircraft {
                            favoriteTile("Aircraft", silhouette: a.example.silhouette, title: a.title,
                                         detail: [a.example.typeCode, "\(a.count)× seen"].compactMap { $0 }.joined(separator: " · "))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, isWide ? 0 : 20)
                }
                if let r = recap.topRoute {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(RecapInk.highlight)
                        VStack(alignment: .leading, spacing: 1) {
                            label("Route")
                            Text("\(r.title)  ·  \(r.count)×")
                                .font(.mono(18, .heavy))
                                .foregroundStyle(RecapInk.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .padding(.top, 18)
                }
            }
        }
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Records")
            columns(leftWidth: 330) { width in
                if recap.sky.altitudeSpeed.count >= 2 {
                    RecapScatter(set: recap.sky.altitudeSpeed, highest: recap.highest?.id, fastest: recap.fastest?.id)
                        .frame(width: width, height: isWide ? 222 : 196)
                        .padding(.top, 16)
                }
            } right: { _ in
                Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        if let s = recap.closest {
                            recordTile("Closest pass", RadarFormat.preciseDistance(s.closestMiles), s, symbol: "scope")
                        }
                        if let s = recap.highest {
                            recordTile("Highest", RadarFormat.altitudeText(s.altitudeAtClosestFeet), s, symbol: "arrow.up.to.line")
                        }
                    }
                    GridRow {
                        if let s = recap.fastest {
                            recordTile("Fastest", RadarFormat.speedText(s.speedKnots), s, symbol: "gauge.with.dots.needle.67percent")
                        }
                        if let l = recap.longest {
                            recordTile("Longest route", RadarFormat.wholeDistance(l.miles), l.sighting, detail: l.sighting.routeText, symbol: "globe.americas.fill")
                        }
                    }
                }
                .padding(.top, isWide ? 16 : 18)
            }
        }
    }

    private var firsts: some View {
        // Story: three rows of three at most, types first and badges in what's left. Wide: two
        // rows each, side by side (three across), or one of them six across.
        let both = !recap.newTypes.isEmpty && !recap.badges.isEmpty
        let across = isWide && !both ? 6 : 3
        let typeRows = isWide ? 2 : min((recap.newTypes.count + 2) / 3, recap.badges.isEmpty ? 3 : 2)
        let badgeRows = isWide ? 2 : min((recap.badges.count + 2) / 3, 3 - typeRows)
        let sectionWidth = isWide && both ? (width - Self.columnGap) / 2 : width
        return VStack(alignment: .leading, spacing: 0) {
            title("Firsts")
            if recap.newTypes.isEmpty && recap.badges.isEmpty {
                Text("No new types or badges this time. The sky has more.")
                    .font(.mono(16, .semibold))
                    .foregroundStyle(RecapInk.soft)
                    .padding(.top, 18)
            }
            let sections = Group {
                if !recap.newTypes.isEmpty && typeRows > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        label("\(recap.newTypes.count) new \(recap.newTypes.count == 1 ? "type" : "types")")
                            .padding(.bottom, 12)
                        grid(Array(recap.newTypes.prefix(typeRows * across)), more: recap.newTypes.count,
                             across: across, width: sectionWidth, cell: newType)
                    }
                    .padding(.top, 18)
                }
                if !recap.badges.isEmpty && badgeRows > 0 {
                    VStack(alignment: .leading, spacing: 0) {
                        label("\(recap.badges.count) \(recap.badges.count == 1 ? "badge" : "badges")")
                            .padding(.bottom, 12)
                        grid(Array(recap.badges.prefix(badgeRows * across)), more: recap.badges.count,
                             across: across, width: sectionWidth, cell: medallion)
                    }
                    .padding(.top, isWide ? 18 : 22)
                }
            }
            if isWide {
                HStack(alignment: .top, spacing: Self.columnGap) { sections }
            } else {
                VStack(alignment: .leading, spacing: 0) { sections }
            }
        }
    }

    // MARK: Pieces

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.mono(30, .heavy))
            .foregroundStyle(RecapInk.text)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.mono(10, .heavy))
            .tracking(1.4)
            .foregroundStyle(RecapInk.soft)
    }

    private func number(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(RadarFormat.wholeNumber(value))
                .font(.mono(32, .heavy))
                .foregroundStyle(RecapInk.text)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(label)
                .font(.mono(11, .semibold))
                .foregroundStyle(RecapInk.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A favourite type or airframe: its silhouette climbing away, the name under it.
    private func favoriteTile(_ heading: String, silhouette: AircraftSilhouette, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(heading)
            AircraftGlyph(silhouette: silhouette, size: 58, spinsRotor: false)
                .foregroundStyle(RecapInk.text)
                .rotationEffect(.degrees(40))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            Text(title)
                .font(.mono(15, .heavy))
                .foregroundStyle(RecapInk.text)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.mono(11, .semibold))
                .foregroundStyle(RecapInk.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RecapInk.wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func recordTile(_ heading: String, _ value: String, _ s: Sighting, detail: String? = nil, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(RecapInk.highlight)
                label(heading)
            }
            Text(value)
                .font(.mono(22, .heavy))
                .foregroundStyle(RecapInk.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(s.displayIdentifier)
                .font(.mono(11, .bold))
                .foregroundStyle(RecapInk.text)
                .lineLimit(1)
            Text(detail ?? s.typeName ?? s.typeCode ?? " ")
                .font(.mono(10, .medium))
                .foregroundStyle(RecapInk.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RecapInk.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func newType(_ s: Sighting) -> some View {
        VStack(spacing: 6) {
            AircraftGlyph(silhouette: s.silhouette, size: 44, spinsRotor: false)
                .foregroundStyle(RecapInk.text)
            Text(s.typeName ?? s.typeCode ?? "")
                .font(.mono(10.5, .bold))
                .foregroundStyle(RecapInk.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    /// Rows of `across`, then "and 4 more".
    private func grid<Item, Cell: View>(_ items: [Item], more total: Int, across: Int, width: CGFloat,
                                        cell: @escaping (Item) -> Cell) -> some View {
        let spacing: CGFloat = 10
        return VStack(alignment: .leading, spacing: isWide ? 8 : 10) {
            VStack(alignment: .leading, spacing: isWide ? 10 : 14) {
                ForEach(0..<(items.count + across - 1) / across, id: \.self) { row in
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(row * across..<min(items.count, row * across + across), id: \.self) { i in
                            cell(items[i])
                                .frame(width: (width - CGFloat(across - 1) * spacing) / CGFloat(across))
                        }
                    }
                }
            }
            if total > items.count {
                Text("and \(total - items.count) more")
                    .font(.mono(12, .semibold))
                    .foregroundStyle(RecapInk.soft)
            }
        }
    }

    /// A badge as a medal: its symbol in a ring filled as far as the level reached.
    private func medallion(_ badge: LogbookRecap.Badge) -> some View {
        let side: CGFloat = isWide ? 46 : 56
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(RecapInk.wash)
                Circle().stroke(Color.white.opacity(0.14), lineWidth: 3.5)
                Circle()
                    .trim(from: 0, to: CGFloat(badge.level) / CGFloat(max(1, badge.levels)))
                    .stroke(RecapInk.highlight, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: badge.symbol)
                    .font(.system(size: side * 0.37, weight: .semibold))
                    .foregroundStyle(RecapInk.highlight)
            }
            .frame(width: side, height: side)
            Text(badge.title)
                .font(.mono(10.5, .bold))
                .foregroundStyle(RecapInk.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(badge.levels > 1 ? "LEVEL \(badge.level)" : " ")
                .font(.mono(8.5, .heavy))
                .tracking(1)
                .foregroundStyle(RecapInk.soft)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - Charts

/// A month as a calendar, each day filled by how many aircraft it brought (busier is
/// warmer), the busiest ringed and days still to come dashed. `first` is the month's first
/// day in the recap's `perDay`. It fills `width`, or less when it would be taller than
/// `height`, and sits in the middle of `width`.
private struct RecapMonthCalendar: View {
    let recap: LogbookRecap
    var first = 0
    var length: Int?
    let width: CGFloat
    var height: CGFloat?
    /// A name over the weekdays, when the year shows its months as calendars.
    var title: String?

    private var gap: CGFloat { width > 200 ? 5 : 3 }
    private var days: Int { length ?? recap.perDay.count - first }
    private var blanks: Int { (first + recap.leadingBlanks) % 7 }
    private var rows: Int { (blanks + days + 6) / 7 }

    private var cell: CGFloat {
        let across = (width - 6 * gap) / 7
        guard let height else { return across }
        let chrome = 12 + gap + (title == nil ? 0 : 16 + gap)
        return min(across, (height - chrome - CGFloat(rows - 1) * gap) / CGFloat(rows))
    }

    var body: some View {
        let days = days, blanks = blanks
        VStack(alignment: .leading, spacing: gap) {
            if let title {
                Text(title.uppercased())
                    .font(.mono(10, .heavy))
                    .tracking(1.2)
                    .foregroundStyle(RecapInk.soft)
                    .padding(.bottom, 2)
            }
            HStack(spacing: gap) {
                ForEach(Array(RecapCalendar.weekdayInitials().enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(.mono(9, .heavy))
                        .foregroundStyle(RecapInk.faint)
                        .frame(width: cell)
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { col in
                        let i = row * 7 + col - blanks
                        day(i >= 0 && i < days ? first + i : nil)
                    }
                }
            }
        }
        .frame(width: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft each day")
    }

    @ViewBuilder
    private func day(_ i: Int?) -> some View {
        let shape = RoundedRectangle(cornerRadius: cell * 0.2, style: .continuous)
        let peak = max(1, recap.perDay.max() ?? 1)
        Group {
            if let i, recap.perDay.indices.contains(i) {
                let count = recap.perDay[i]
                ZStack {
                    if i >= recap.daysSoFar {
                        shape.strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    } else if count == 0 {
                        shape.fill(RecapInk.wash)
                    } else {
                        shape.fill(RecapInk.heat(Double(count) / Double(peak)))
                    }
                    if count == peak && recap.perDay.count > 1 {
                        shape.strokeBorder(RecapInk.highlight, lineWidth: cell > 24 ? 2.5 : 1.5)
                    }
                    if cell > 24 {
                        Text("\(i - first + 1)")
                            .font(.mono(10, .bold))
                            .foregroundStyle(count > 0 ? RecapInk.onLight.opacity(0.8) : RecapInk.faint)
                    }
                }
            } else {
                Color.clear
            }
        }
        .frame(width: cell, height: cell)
    }
}

/// A year whose sightings span a month or two: those months as calendars, so a logbook
/// started this autumn isn't a sliver of a year-long grid.
private struct RecapYearMonths: View {
    let recap: LogbookRecap
    let months: [(day: Int, length: Int, name: String)]
    let width: CGFloat
    var height: CGFloat?

    var body: some View {
        if months.count == 1, let m = months.first {
            RecapMonthCalendar(recap: recap, first: m.day, length: m.length, width: width, height: height, title: m.name)
        } else {
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(months.enumerated()), id: \.offset) { _, m in
                    RecapMonthCalendar(recap: recap, first: m.day, length: m.length,
                                       width: (width - 16) / 2, height: height, title: m.name)
                }
            }
        }
    }
}

/// A year as weeks (a column a week, the calendar's first weekday at the top), filled like
/// the month calendar. Only the months from the first sighting to the latest month begun are
/// drawn, so a logbook started in the summer isn't mostly empty squares; two months or fewer
/// are drawn as calendars instead, and past half a year the weeks split into two strips.
private struct RecapYearGrid: View {
    let recap: LogbookRecap
    let width: CGFloat
    var height: CGFloat?

    private static let gap: CGFloat = 2.5
    private static let labels: CGFloat = 14
    private static let largest: CGFloat = 20

    var body: some View {
        let active = activeMonths
        if active.count <= 2 {
            RecapYearMonths(recap: recap, months: active, width: width, height: height)
        } else {
            weeks
        }
    }

    /// The months from the first sighting's to the latest begun, each with where it starts
    /// in `perDay` and how long it is.
    private var activeMonths: [(day: Int, length: Int, name: String)] {
        let months = RecapCalendar.monthStarts(recap)
        let first = recap.perDay.firstIndex { $0 > 0 } ?? 0
        let latest = max(first, recap.daysSoFar - 1)
        return months.indices.compactMap { k in
            let start = months[k].day
            let end = k + 1 < months.count ? months[k + 1].day : recap.perDay.count
            guard end > first, start <= latest else { return nil }
            return (start, end - start, months[k].name)
        }
    }

    private var weeks: some View {
        let shown = columns
        let split = shown.count > 27
        let perStrip = split ? (shown.count + 1) / 2 : shown.count
        var cell = min(Self.largest, (width - Self.labels - CGFloat(perStrip - 1) * Self.gap) / CGFloat(perStrip))
        if let height {
            // Each strip is its month names and seven rows; strips are 12 apart.
            let strips: CGFloat = split ? 2 : 1
            cell = min(cell, ((height - (strips - 1) * 12) / strips - 14 + Self.gap) / 7 - Self.gap)
        }
        return VStack(alignment: .leading, spacing: 12) {
            if split {
                strip(shown.lowerBound..<(shown.lowerBound + perStrip), cell: cell)
                strip((shown.lowerBound + perStrip)..<shown.upperBound, cell: cell)
            } else {
                strip(shown, cell: cell)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft each day")
    }

    /// Week columns covering the active months.
    private var columns: Range<Int> {
        let active = activeMonths
        let start = active.first?.day ?? 0
        let end = active.last.map { $0.day + $0.length - 1 } ?? recap.perDay.count - 1
        return (start + recap.leadingBlanks) / 7..<((end + recap.leadingBlanks) / 7 + 1)
    }

    private func strip(_ columns: Range<Int>, cell: CGFloat) -> some View {
        let months = RecapCalendar.monthStarts(recap)
        let initials = RecapCalendar.weekdayInitials()
        let peak = max(1, recap.perDay.max() ?? 1)
        let step = cell + Self.gap
        return Canvas { context, _ in
            let top: CGFloat = 13
            for month in months {
                let column = (month.day + recap.leadingBlanks) / 7
                guard columns.contains(column) else { continue }
                context.draw(Text(month.name).font(.mono(8.5, .heavy)).foregroundStyle(RecapInk.faint),
                             at: CGPoint(x: Self.labels + CGFloat(column - columns.lowerBound) * step, y: 5), anchor: .leading)
            }
            for row in [1, 3, 5] {
                context.draw(Text(initials[row]).font(.mono(7.5, .heavy)).foregroundStyle(RecapInk.faint),
                             at: CGPoint(x: 0, y: top + CGFloat(row) * step + cell / 2), anchor: .leading)
            }
            for column in columns {
                for row in 0..<7 {
                    let i = column * 7 + row - recap.leadingBlanks
                    guard recap.perDay.indices.contains(i) else { continue }
                    let rect = CGRect(x: Self.labels + CGFloat(column - columns.lowerBound) * step, y: top + CGFloat(row) * step, width: cell, height: cell)
                    let path = Path(roundedRect: rect, cornerRadius: cell * 0.25, style: .continuous)
                    let count = recap.perDay[i]
                    if i >= recap.daysSoFar {
                        context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 0.75)
                    } else if count == 0 {
                        context.fill(path, with: .color(RecapInk.wash))
                    } else {
                        context.fill(path, with: .color(RecapInk.heat(Double(count) / Double(peak))))
                    }
                    if count == peak {
                        context.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: cell * 0.3, style: .continuous),
                                       with: .color(RecapInk.highlight), lineWidth: 2)
                    }
                }
            }
        }
        .frame(width: width, height: 13 + 7 * step - Self.gap + 1)
    }
}

private enum RecapCalendar {
    /// "S", "M", "T"… from the calendar's first weekday.
    static func weekdayInitials(_ calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Where each month of the period starts, as a day index, with its short name.
    static func monthStarts(_ recap: LogbookRecap, calendar: Calendar = .current) -> [(day: Int, name: String)] {
        guard let interval = recap.period.interval(calendar: calendar) else { return [] }
        let names = calendar.shortStandaloneMonthSymbols
        return (0..<12).compactMap { m in
            guard let start = calendar.date(byAdding: .month, value: m, to: interval.start), start < interval.end,
                  let day = calendar.dateComponents([.day], from: interval.start, to: start).day else { return nil }
            return (day, names[(calendar.component(.month, from: start) - 1) % names.count])
        }
    }
}

/// The day as a 24-hour dial, midnight at the top: a bar per hour, as long as the aircraft
/// it brought and coloured like the sky at that hour.
private struct RecapClock: View {
    let hourly: [Int]
    let width: CGFloat

    private static let outer: CGFloat = 118
    private static let inner: CGFloat = 54
    static let height = 2 * (outer + 16)

    var body: some View {
        let peak = max(1, hourly.max() ?? 0)
        let busiest = (hourly.max() ?? 0) > 0 ? hourly.firstIndex(of: peak) : nil
        ZStack {
            Canvas { context, canvas in
                let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
                let inner = Self.inner, outer = Self.outer
                let ring = inner - 7
                context.stroke(Path(ellipseIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)),
                               with: .color(.white.opacity(0.2)), lineWidth: 1)
                for (h, count) in hourly.enumerated() {
                    let mid = Double(h) * 15 + 7.5 - 90
                    let a0 = Angle.degrees(mid - 6.3), a1 = Angle.degrees(mid + 6.3)
                    let length = count == 0 ? 3 : max(6, (outer - inner) * CGFloat(count) / CGFloat(peak))
                    var bar = Path()
                    bar.addArc(center: c, radius: inner + length, startAngle: a0, endAngle: a1, clockwise: false)
                    bar.addArc(center: c, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
                    bar.closeSubpath()
                    context.fill(bar, with: .color(count == 0 ? RecapInk.wash : ChartTone.timeOfDay(h)))
                    if h == busiest {
                        context.stroke(bar, with: .color(RecapInk.highlight), lineWidth: 2)
                    }
                }
                // The quarters, just outside the longest bar.
                let labels: [(LocalizedStringKey, CGPoint, UnitPoint)] = [
                    ("MIDNIGHT", CGPoint(x: c.x, y: c.y - outer - 6), .bottom),
                    ("6 AM", CGPoint(x: c.x + outer + 6, y: c.y), .leading),
                    ("NOON", CGPoint(x: c.x, y: c.y + outer + 6), .top),
                    ("6 PM", CGPoint(x: c.x - outer - 6, y: c.y), .trailing),
                ]
                for (text, at, anchor) in labels {
                    context.draw(Text(text).font(.mono(8.5, .heavy)).foregroundStyle(RecapInk.faint), at: at, anchor: anchor)
                }
            }
            if let busiest {
                VStack(spacing: 2) {
                    Text(LogbookFormat.hour(busiest))
                        .font(.mono(22, .heavy))
                        .foregroundStyle(RecapInk.text)
                    Text("BUSIEST")
                        .font(.mono(8, .heavy))
                        .tracking(1.2)
                        .foregroundStyle(RecapInk.soft)
                }
            }
        }
        .frame(width: width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft by hour")
        .accessibilityValue(busiest.map { "Busiest at \(LogbookFormat.hour($0))" } ?? "")
    }
}

/// Which way they were heading: 16 petals, area-true, coloured round the compass.
private struct RecapRose: View {
    let sectors: [Int]
    var size: CGFloat = 112

    var body: some View {
        Canvas { context, canvas in
            let c = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let outer = canvas.width * 0.42
            let peak = Double(max(1, sectors.max() ?? 1))
            for r in [0.5, 1.0] {
                let radius = outer * r
                context.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                               with: .color(.white.opacity(r == 1 ? 0.22 : 0.12)), lineWidth: 1)
            }
            for (i, count) in sectors.enumerated() where count > 0 {
                let radius = outer * sqrt(Double(count) / peak)
                let mid = Angle.degrees(Double(i) * 22.5 - 90)
                var petal = Path()
                petal.move(to: c)
                petal.addArc(center: c, radius: radius, startAngle: mid - .degrees(9.5), endAngle: mid + .degrees(9.5), clockwise: false)
                petal.closeSubpath()
                context.fill(petal, with: .color(ChartTone.heading(Double(i) * 22.5)))
            }
            context.draw(Text("N").font(.mono(9, .heavy)).foregroundStyle(RecapInk.highlight),
                         at: CGPoint(x: c.x, y: c.y - outer - 7))
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Directions aircraft were heading")
    }
}

/// The mix as a ten-by-ten waffle, read like text: airlines first, the rarer kinds last.
private struct RecapWaffle: View {
    let cells: [FlightKind]
    var side: CGFloat = 158

    var body: some View {
        Canvas { context, canvas in
            let gap: CGFloat = 2.5
            let cell = (canvas.width - 9 * gap) / 10
            for (i, kind) in cells.enumerated() {
                let rect = CGRect(x: CGFloat(i % 10) * (cell + gap), y: CGFloat(i / 10) * (cell + gap), width: cell, height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: 3, style: .continuous), with: .color(kind.tone))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

/// The top five as bars under their names, the leader in full white.
private struct RecapRanking: View {
    let items: [LogbookRecap.Favorite]
    let width: CGFloat

    var body: some View {
        let peak = Double(max(1, items.first?.count ?? 1))
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.mono(i == 0 ? 14 : 12, i == 0 ? .heavy : .bold))
                            .foregroundStyle(RecapInk.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(RadarFormat.wholeNumber(item.count))
                            .font(.mono(12, .heavy))
                            .foregroundStyle(i == 0 ? RecapInk.text : RecapInk.soft)
                    }
                    Capsule()
                        .fill(i == 0 ? RecapInk.highlight : Color.white.opacity(0.5))
                        .frame(width: max(8, width * CGFloat(Double(item.count) / peak)), height: i == 0 ? 10 : 7)
                }
            }
        }
    }
}

/// Every aircraft by altitude against speed, a faint cloud with the highest and fastest ringed.
private struct RecapScatter: View {
    let set: AltitudeSpeedSet
    let highest: String?
    let fastest: String?

    var body: some View {
        Canvas { context, canvas in
            let axis: CGFloat = 34, foot: CGFloat = 16
            let plot = CGRect(x: axis, y: 6, width: canvas.width - axis - 4, height: canvas.height - foot - 6)
            let altitudeTicks = Self.ticks(set.altitudeDomain.upperBound)
            for value in altitudeTicks {
                let y = plot.maxY - plot.height * value / set.altitudeDomain.upperBound
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y))
                line.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(line, with: .color(.white.opacity(value == 0 ? 0.3 : 0.1)), lineWidth: 1)
                context.draw(Text(AltitudeSpeed.altitudeAxisLabel(value)).font(.mono(8, .bold)).foregroundStyle(RecapInk.faint),
                             at: CGPoint(x: plot.minX - 5, y: y), anchor: .trailing)
            }
            let speedTicks = Self.ticks(set.speedDomain.upperBound)
            for (i, value) in speedTicks.enumerated() where value > 0 {
                let x = plot.minX + plot.width * value / set.speedDomain.upperBound
                context.draw(Text(AltitudeSpeed.speedAxisLabel(value, isLast: i == speedTicks.count - 1)).font(.mono(8, .bold)).foregroundStyle(RecapInk.faint),
                             at: CGPoint(x: x, y: plot.maxY + 4), anchor: i == speedTicks.count - 1 ? .topTrailing : .top)
            }
            var cloud = Path()
            let dot: CGFloat = set.count > 2_000 ? 1.3 : 1.8
            var marked: [(CGPoint, String)] = []
            for i in set.points.indices {
                let p = set.position(of: i, in: plot.size)
                let at = CGPoint(x: plot.minX + p.x, y: plot.minY + p.y)
                cloud.addEllipse(in: CGRect(x: at.x - dot, y: at.y - dot, width: dot * 2, height: dot * 2))
                let id = set.points[i].id
                if id == highest { marked.append((at, String(localized: "HIGHEST"))) }
                if id == fastest && id != highest { marked.append((at, String(localized: "FASTEST"))) }
                if id == fastest && id == highest { marked[marked.count - 1].1 = String(localized: "HIGHEST · FASTEST") }
            }
            context.fill(cloud, with: .color(.white.opacity(set.count > 2_000 ? 0.28 : 0.42)))
            // Two records side by side get their labels one above the other.
            marked.sort { $0.0.y < $1.0.y }
            var labelY = marked.map { min(max($0.0.y, plot.minY + 6), plot.maxY - 6) }
            if labelY.count == 2, labelY[1] - labelY[0] < 13 {
                let mid = (labelY[0] + labelY[1]) / 2
                labelY = [max(plot.minY + 6, mid - 7), mid + 7]
            }
            for (n, (at, name)) in marked.enumerated() {
                let r: CGFloat = 5.5
                context.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)), with: .color(RecapInk.highlight))
                context.stroke(Path(ellipseIn: CGRect(x: at.x - r - 3, y: at.y - r - 3, width: (r + 3) * 2, height: (r + 3) * 2)),
                               with: .color(RecapInk.highlight.opacity(0.6)), lineWidth: 1.5)
                // Label towards the middle of the plot so it never runs off the card.
                let leftward = at.x > plot.midX
                let label = context.resolve(Text(name).font(.mono(8.5, .heavy)).foregroundStyle(RecapInk.highlight))
                context.draw(label, at: CGPoint(x: at.x + (leftward ? -13 : 13), y: labelY[n]), anchor: leftward ? .trailing : .leading)
            }
            context.draw(Text("ALTITUDE × SPEED").font(.mono(8, .heavy)).foregroundStyle(RecapInk.faint),
                         at: CGPoint(x: plot.minX + 4, y: plot.minY + 2), anchor: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Every aircraft by altitude and speed, with the highest and fastest ringed")
    }

    /// Round steps from zero, about four of them, below `upper`.
    static func ticks(_ upper: Double) -> [Double] {
        guard upper > 0 else { return [0] }
        let raw = upper / 4
        let magnitude = pow(10, floor(log10(raw)))
        let step = [1.0, 2, 2.5, 5, 10].map { $0 * magnitude }.first { $0 >= raw } ?? raw
        return stride(from: 0, through: upper * 0.97, by: step).map { $0 }
    }
}

/// The cards to swipe through, with Share on iPhone and iPad. The TV shows the wide cards
/// one at a time: ◀ ▶ step through them, a click moves on (back to the start after the last),
/// MENU closes.
struct LogbookRecapView: View {
    let period: LogbookRecap.Period
    let logbook: Logbook

    @State private var recap: LogbookRecap?
    @State private var page = RecapSlide.Kind.cover
    #if os(tvOS)
    /// Which way the last step went, so the cards slide the way the remote was pressed.
    @State private var forward = true
    @Environment(\.dismiss) private var dismiss

    private static let format = RecapSlide.Format.wide
    private static let largest: CGFloat = 2.4
    /// The page dots and the hint under the card.
    private static let chrome: CGFloat = 150
    #else
    private static let format = RecapSlide.Format.story
    private static let largest: CGFloat = 1.6
    private static let chrome: CGFloat = 90
    /// How far the video has got while it's being made.
    @State private var videoProgress: Double?
    @State private var videoTask: Task<Void, Never>?
    @State private var videoFailed = false
    #endif

    var body: some View {
        GeometryReader { geo in
            let size = Self.format.size
            let scale = min(Self.largest, (geo.size.width - 40) / size.width, (geo.size.height - Self.chrome) / size.height)
            Group {
                if let recap {
                    pages(recap, scale: scale)
                } else {
                    ProgressView("Adding it up…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(LogbookBackdrop())
        .navigationTitle(period.isYear ? "\(period.shortTitle()) in the Sky" : "\(period.title()) in the Sky")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let recap {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            shareVideo(recap)
                        } label: {
                            Label("Share as Video", systemImage: "play.rectangle")
                        }
                        ShareLink(items: RecapSlide.Kind.allCases.compactMap { RecapRenderer.share(kind: $0, recap: recap) },
                                  subject: Text("My \(period.title()) in the sky")) { slides in
                            SharePreview("\(period.title()) in the sky", image: Image(uiImage: slides.image))
                        } label: {
                            Label("Share as Pictures", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(videoProgress != nil)
                }
            }
        }
        .overlay {
            if let videoProgress {
                VStack(spacing: 10) {
                    ProgressView(value: videoProgress)
                        .tint(Palette.ink)
                        .frame(width: 180)
                    Text("Making your video…")
                        .monoScaled(13, .semibold)
                        .foregroundStyle(Palette.value)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .glassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.2), value: videoProgress == nil)
        .alert("Couldn't make the video", isPresented: $videoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again, or share the cards as pictures.")
        }
        .onDisappear { videoTask?.cancel() }
        #endif
        #if os(tvOS)
        .onExitCommand { dismiss() }
        #endif
        .task(id: logbook.sightings.count) {
            let sightings = logbook.sightings
            let period = period
            recap = await Task.detached(priority: .userInitiated) { LogbookRecap(sightings, period: period) }.value
        }
    }

    private func card(_ kind: RecapSlide.Kind, _ recap: LogbookRecap, scale: CGFloat) -> some View {
        RecapSlide(kind: kind, recap: recap, format: Self.format)
            .scaleEffect(scale)
            .frame(width: Self.format.size.width * scale, height: Self.format.size.height * scale)
    }

    #if os(tvOS)
    /// A page view has nothing the remote can focus, so the card is one quiet button that
    /// takes the arrows itself.
    private func pages(_ recap: LogbookRecap, scale: CGFloat) -> some View {
        VStack(spacing: 30) {
            Button {
                step(1, wrapping: true)
            } label: {
                card(page, recap, scale: scale)
                    .id(page)
                    .transition(.push(from: forward ? .trailing : .leading))
            }
            .buttonStyle(TVQuietButtonStyle())
            .onMoveCommand { direction in
                switch direction {
                case .left: step(-1)
                case .right: step(1)
                default: break
                }
            }
            .accessibilityHint("Swipe left or right for the other cards")
            HStack(spacing: 14) {
                ForEach(RecapSlide.Kind.allCases) { kind in
                    Circle()
                        .fill(kind == page ? Palette.ink : Palette.ink.opacity(0.22))
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
            Text("◀ ▶ to flip through the cards")
                .font(.mono(22))
                .foregroundStyle(Palette.caption)
        }
    }

    private func step(_ delta: Int, wrapping: Bool = false) {
        let count = RecapSlide.Kind.allCases.count
        let target = wrapping ? (page.rawValue + delta + count) % count : page.rawValue + delta
        guard let next = RecapSlide.Kind(rawValue: target), next != page else { return }
        // Turn the transition first, so the card leaving goes the same way as the one arriving.
        forward = delta > 0
        Task { @MainActor in
            withAnimation(.snappy(duration: 0.35)) { page = next }
        }
    }
    #else
    /// Makes the cards into a video, then opens the share sheet with it.
    private func shareVideo(_ recap: LogbookRecap) {
        videoProgress = 0
        videoTask = Task {
            do {
                let url = try await RecapRenderer.video(recap: recap) { fraction in
                    Task { @MainActor in if videoProgress != nil { videoProgress = fraction } }
                }
                videoProgress = nil
                RecapVideo.presentShareSheet(for: url)
            } catch {
                videoProgress = nil
                if !(error is CancellationError) { videoFailed = true }
            }
        }
    }

    private func pages(_ recap: LogbookRecap, scale: CGFloat) -> some View {
        TabView(selection: $page) {
            ForEach(RecapSlide.Kind.allCases) { kind in
                card(kind, recap, scale: scale)
                    .tag(kind)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }
    #endif
}

#if os(iOS)
@MainActor
enum RecapRenderer {
    /// A card as a picture at three times its size: a story is 1080 × 1920.
    static func image(kind: RecapSlide.Kind, recap: LogbookRecap, format: RecapSlide.Format = .story) -> UIImage? {
        let renderer = ImageRenderer(content: RecapSlide(kind: kind, recap: recap, format: format).background(Color.black))
        renderer.proposedSize = ProposedViewSize(format.size)
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    static func share(kind: RecapSlide.Kind, recap: LogbookRecap, format: RecapSlide.Format = .story) -> SpotCardShare? {
        image(kind: kind, recap: recap, format: format)
            .map { SpotCardShare(image: $0, name: "\(recap.period.title()) in the sky \(kind.rawValue + 1)") }
    }

    /// Every story card, one after another, as a video (`RecapVideo`).
    static func video(recap: LogbookRecap, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        var cards: [CGImage] = []
        for kind in RecapSlide.Kind.allCases {
            if let card = image(kind: kind, recap: recap)?.cgImage { cards.append(card) }
            // Let the progress show between cards.
            await Task.yield()
        }
        let name = "\(recap.period.title()) in the sky"
        return try await Task.detached(priority: .userInitiated) {
            try await RecapVideo.make(cards: cards, name: name, progress: progress)
        }.value
    }
}
#endif

#if os(iOS)
/// The Overview's way in: this year and this month, each a tappable tile.
struct LogbookRecapEntry: View {
    let logbook: Logbook

    @State private var offered: [(period: LogbookRecap.Period, total: Int)] = []

    var body: some View {
        // A container that's always there, so the task runs before there's anything to show.
        VStack(alignment: .leading, spacing: 0) {
            if !offered.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    LogbookHeader("In the sky")
                    HStack(spacing: 12) {
                        ForEach(Array(offered.prefix(2).enumerated()), id: \.offset) { i, item in
                            NavigationLink(value: LogbookRoute.recap(item.period)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.period.isYear ? "Your \(item.period.shortTitle())" : item.period.shortTitle())
                                        .font(.mono(16, .heavy))
                                        .foregroundStyle(.white)
                                    Text("\(RadarFormat.wholeNumber(item.total)) aircraft ›")
                                        .font(.mono(12, .semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .padding(14)
                                .background(RecapInk.gradient(i == 0 ? 0 : 4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: logbook.sightings.count / 25) {
            let sightings = logbook.sightings
            offered = await Task.detached(priority: .utility) {
                LogbookRecap.periods().compactMap { period in
                    let total = LogbookRecap.total(sightings, period: period)
                    return total > 0 ? (period, total) : nil
                }
            }.value
        }
    }
}
#endif
#endif
