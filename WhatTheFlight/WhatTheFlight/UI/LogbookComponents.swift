//
//  LogbookComponents.swift
//  WhatTheFlight
//
//  Pieces the logbook uses on iPhone, iPad and Apple TV: the tabs, badge rings with their
//  level dots, stat tiles, day tags and the charts (aircraft per hour, per day or month, per
//  weekday, by altitude, and a compass rose of which way they fly). Each takes a `scale` for
//  the ten-foot view.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import Charts

/// Behind every logbook page: the paper with the contours turned almost all the way down, so
/// the numbers and charts carry the screen. Follows the Topography setting (`\.topographyStyle`).
struct LogbookBackdrop: View {
    var showTopography = true

    @Environment(\.topographyStyle) private var topographyStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Palette.paper
                if showTopography && topographyStyle != .off {
                    TopographyLayer(style: topographyStyle)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .opacity(colorScheme == .dark ? 0.2 : 0.14)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The logbook's sections, the same on every device.
enum LogbookTab: String, Hashable, CaseIterable {
    case overview, sightings, stats, badges, photos

    var title: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .sightings: return String(localized: "Sightings")
        case .stats: return String(localized: "Stats")
        case .badges: return String(localized: "Badges")
        case .photos: return String(localized: "Photos")
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .sightings: return "list.bullet.rectangle"
        case .stats: return "chart.bar.xaxis"
        case .badges: return "medal"
        case .photos: return "photo.on.rectangle"
        }
    }

    /// DEBUG: `-wtf.debugLogbookTab overview|sightings|stats|badges|photos` opens on a tab
    /// (`-wtf.debugBadge <id>` implies Badges).
    static var initial: LogbookTab {
        #if DEBUG
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "wtf.debugLogbookTab"), let tab = LogbookTab(rawValue: raw) { return tab }
        if defaults.string(forKey: "wtf.debugBadge") != nil { return .badges }
        #endif
        return .overview
    }
}

extension LogbookSkyScope {
    /// DEBUG: `-wtf.debugSkyScope <place>|all` opens the Stats tab on a spot (by the start of
    /// its name, "denver") or on all places.
    static func initial(in digest: LogbookDigest) -> LogbookSkyScope? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "wtf.debugSkyScope")?.lowercased() else { return nil }
        if raw == "all" { return .everywhere }
        return digest.spots.first { $0.name.lowercased().hasPrefix(raw) }.map { .spot($0.id) }
        #else
        return nil
        #endif
    }
}

// MARK: - Badges

/// A badge: its symbol inside a progress ring, greyed out until unlocked, with a dot per
/// level for badges that have them. A badge with every level earned gets a filled disc and a
/// second, outer ring, so the rare top levels stand out.
struct AchievementBadge: View {
    let achievement: Achievement
    var scale: CGFloat = 1
    var showsTitle = true

    var body: some View {
        let a = achievement
        let isTopLevel = a.hasLevels && a.isMaxed
        VStack(spacing: 6 * scale) {
            ZStack {
                if isTopLevel {
                    Circle().fill(Palette.notable.opacity(0.16))
                }
                Circle()
                    .stroke(Palette.ink.opacity(0.12), lineWidth: 4 * scale)
                Circle()
                    .trim(from: 0, to: a.fraction)
                    .stroke(a.isUnlocked ? Palette.notable : Palette.route, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: a.symbol)
                    .font(.system(size: 20 * scale, weight: .semibold))
                    .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.faint)
            }
            .frame(width: 54 * scale, height: 54 * scale)
            // Drawn outside the ring's frame, so it doesn't move anything.
            .overlay {
                if isTopLevel {
                    Circle()
                        .stroke(Palette.notable, lineWidth: 1.5 * scale)
                        .padding(-5 * scale)
                }
            }
            if showsTitle {
                Text(a.title)
                    .monoScaled(10 * scale, .bold)
                    .foregroundStyle(a.isUnlocked ? Palette.value : Palette.caption)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                footer
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityText(a))
    }

    @ViewBuilder
    private var footer: some View {
        let a = achievement
        if a.hasLevels {
            TierDots(earned: a.level, total: a.tiers.count, scale: scale)
        } else if !a.isUnlocked && a.target > 1 {
            Text(a.progressLabel ?? "\(RadarFormat.wholeNumber(min(a.progress, a.target)))/\(RadarFormat.wholeNumber(a.target))")
                .monoScaled(9 * scale)
                .foregroundStyle(Palette.faint)
        }
    }

    static func accessibilityText(_ a: Achievement) -> String {
        let state: String
        if a.hasLevels {
            state = a.isMaxed ? "every level unlocked" : "level \(a.level) of \(a.tiers.count), " + (a.progressLabel ?? "\(a.progress) of \(a.target) for the next")
        } else {
            state = a.isUnlocked ? "unlocked" : a.progressLabel ?? "\(a.progress) of \(a.target)"
        }
        return "\(a.title), \(state). \(a.detail)"
    }
}

/// ●●○ — levels earned of a badge's levels.
struct TierDots: View {
    let earned: Int
    let total: Int
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 3 * scale) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < earned ? Palette.notable : Color.clear)
                    .overlay(Circle().stroke(i < earned ? Palette.notable : Palette.faint, lineWidth: 1.2 * scale))
                    .frame(width: 6 * scale, height: 6 * scale)
            }
        }
        .accessibilityHidden(true)
    }
}

/// "Level 2 of 3", a bar toward the next level, and who unlocked the latest one.
struct AchievementProgress: View {
    let achievement: Achievement
    var scale: CGFloat = 1

    var body: some View {
        let a = achievement
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack {
                Text(a.levelText ?? "Progress").monoScaled(11 * scale, .semibold).textCase(.uppercase).foregroundStyle(Palette.caption)
                Spacer()
                Text(a.isMaxed && a.hasLevels ? "Every level" : a.progressText)
                    .monoScaled(13 * scale, .bold)
                    .foregroundStyle(a.isUnlocked ? Palette.notable : Palette.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.12))
                    Capsule().fill(a.isUnlocked ? Palette.notable : Palette.route)
                        .frame(width: max(6 * scale, geo.size.width * a.fraction))
                }
            }
            .frame(height: 8 * scale)
            if a.hasLevels {
                TierLadder(achievement: a, scale: scale)
            }
            if let by = a.unlockedBy {
                Text("\(a.hasLevels ? "Level \(a.level) unlocked" : "Unlocked") \((a.unlockedAt ?? by.firstSeen).formatted(date: .abbreviated, time: .shortened)) by \(by.displayIdentifier)\(by.typeName.map { " · \($0)" } ?? "")")
                    .monoScaled(12 * scale)
                    .foregroundStyle(Palette.value)
            }
            if !a.isMaxed {
                Text(a.tierLabels != nil
                     ? "\(a.level == 0 ? "Unlocks at" : "Next level:") \(a.targetLabel)"
                     : "\(RadarFormat.wholeNumber(a.remaining)) to go\(a.hasLevels ? " for level \(a.level + 1)" : "")")
                    .monoScaled(12 * scale)
                    .foregroundStyle(Palette.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Each level's target, ticked once reached: "✓ 100  ✓ 1,000  ○ 10K  ○ 100K  ○ 1M". Wraps onto
/// more lines when the levels don't fit across.
private struct TierLadder: View {
    let achievement: Achievement
    var scale: CGFloat = 1

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14 * scale) { steps }
            HStack(spacing: 8 * scale) { steps }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96 * scale), spacing: 8 * scale, alignment: .leading)],
                      alignment: .leading, spacing: 6 * scale) { steps }
        }
    }

    private var steps: some View {
        ForEach(Array(achievement.tiers.enumerated()), id: \.offset) { i, target in
            let done = i < achievement.level
            HStack(spacing: 4 * scale) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11 * scale, weight: .bold))
                Text(achievement.tierLabels?[i] ?? Self.label(target))
                    .monoScaled(11 * scale, done ? .bold : .regular)
                    .fixedSize()
            }
            .foregroundStyle(done ? Palette.notable : Palette.caption)
        }
    }

    /// "1,000", then "10K", "100K", "1M" so five levels fit across a phone.
    private static func label(_ n: Int) -> String {
        n < 10_000 ? RadarFormat.wholeNumber(n) : n.formatted(.number.notation(.compactName))
    }
}

// MARK: - Tiles and tags

struct LogbookStatTile: View {
    let title: LocalizedStringKey
    let value: String
    var scale: CGFloat = 1
    var symbol: String? = nil
    /// The number and its symbol (`ChartTone`).
    var tint: Color = Palette.ink

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack(spacing: 4 * scale) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 9 * scale, weight: .bold))
                        .foregroundStyle(tint)
                }
                Text(title)
                    .monoScaled(10 * scale, .semibold)
                    .tracking(1.4 * scale)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(Palette.caption)
            Text(value)
                .monoScaled(22 * scale, .bold)
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12 * scale)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 14 * scale, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// What made a day (or month) stand out: "★ 2 notable  ✦ 3 new types  📷 1  📍 Atlanta, GA".
struct LogbookDayTags: View {
    var notable = 0
    var newTypes = 0
    var photos = 0
    var place: String? = nil
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 10 * scale) {
            if notable > 0 { tag("star.fill", "\(notable) notable", Palette.notable) }
            if newTypes > 0 { tag("sparkles", "\(newTypes) new type\(newTypes == 1 ? "" : "s")", Palette.ink) }
            if photos > 0 { tag("camera.fill", "\(photos)", Palette.signal) }
            if let place { tag("mappin", place, Palette.caption) }
        }
        .lineLimit(1)
    }

    private func tag(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: symbol).font(.system(size: 9 * scale, weight: .bold))
            Text(text).monoScaled(10 * scale, .semibold)
        }
        .foregroundStyle(color)
    }
}

/// An uppercase heading in the compass's red, so sections stand out over the contours, with
/// an optional link or note on the right.
struct LogbookHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var scale: CGFloat = 1
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .monoScaled(11 * scale, .bold)
                .tracking(1.4 * scale)
                .textCase(.uppercase)
                .foregroundStyle(Palette.signal)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
                .monoScaled(12 * scale, .bold)
                .foregroundStyle(Palette.ink)
        }
    }
}

extension LogbookHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey, scale: CGFloat = 1) {
        self.init(title: title, scale: scale) { EmptyView() }
    }
}

extension View {
    /// The logbook's card: paper shade, rounded.
    func logbookCard(padding: CGFloat = 14, scale: CGFloat = 1) -> some View {
        self.padding(padding * scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 18 * scale, style: .continuous))
    }
}

// MARK: - Sighting text

extension Sighting {
    var summaryLine: String {
        [operatorName, typeName ?? typeCode].compactMap { $0 }.joined(separator: " · ")
    }

    var closestText: String { "\(RadarFormat.distanceText(closestMiles))" }

    /// "iPhone, Apple TV".
    var devicesText: String? {
        loggedOn.isEmpty ? nil : loggedOn.map(\.title).joined(separator: ", ")
    }

    /// Icon colour at rest: military olive, otherwise the standard blip.
    var tint: Color {
        Palette.blip(isMilitary: tags.contains(.military))
    }

    /// "6 min", "Under a min".
    var inRangeText: String { LogbookFormat.duration(timeInRange) }

    /// "Military", "Rare aircraft"…: why it stood out.
    var notableReason: String? {
        tags.first.map { tag in
            switch tag {
            case .hijack, .emergency, .radioFailure: return "Emergency squawk"
            case .medical: return "Air ambulance"
            case .military: return "Military"
            case .government: return "Government"
            case .rare: return "Rare aircraft"
            }
        }
    }
}

extension LogbookRecord {
    /// Each record keeps its colour wherever it's shown: altitude ones match the altitude chart.
    var tint: Color {
        switch id {
        case "closest": return ChartTone.coral.color
        case "highest": return ChartTone.teal.color
        case "fastest": return ChartTone.pink.color
        case "lowest": return ChartTone.amber.color
        case "route": return ChartTone.sky.color
        default: return Palette.ink
        }
    }
}

enum LogbookGrouping {
    /// Sightings newest first, grouped by calendar day.
    static func byDay(_ sightings: [Sighting], calendar: Calendar = .current) -> [(day: Date, items: [Sighting])] {
        let groups = Dictionary(grouping: sightings) { calendar.startOfDay(for: $0.firstSeen) }
        return groups.keys.sorted(by: >).map { day in
            (day, groups[day]!.sorted { $0.firstSeen > $1.firstSeen })
        }
    }

    /// "Atlanta, GA" or "Atlanta, GA + 2 more": where you watched from that day.
    static func places(in items: [Sighting]) -> String? {
        var seen = Set<String>()
        let places = items.reversed().compactMap(\.placeName).filter { seen.insert($0).inserted }
        guard let first = places.first else { return nil }
        return places.count == 1 ? first : "\(first) + \(places.count - 1) more"
    }

    /// "Today", "Yesterday", "Wednesday, Oct 22".
    static func title(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// "Today", "Yesterday", "Tuesday" this week; "Oct 14" before that.
    static func shortTitle(for day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: Date())).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "October 2026".
    static func monthTitle(_ month: Date) -> String {
        month.formatted(.dateTime.month(.wide).year())
    }

    /// "Oct 1 – 16 · 16 days".
    static func monthSpan(_ month: LogbookMonth) -> String {
        guard let first = month.days.last?.day, let last = month.days.first?.day else { return "" }
        let days = "\(month.days.count) day\(month.days.count == 1 ? "" : "s")"
        if first == last { return "\(first.formatted(.dateTime.month(.abbreviated).day())) · \(days)" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.day())) · \(days)"
    }
}

// MARK: - Charts

/// Aircraft per hour of the day, midnight to midnight, each bar the colour of the sky at
/// that hour (`ChartTone.timeOfDay`). With `onPick`, touch a bar to read it (iPhone and iPad).
struct LogbookHourlyChart: View {
    let counts: [Int]
    /// Marked with a dot: the current hour, or the busiest. (Fading the others would turn
    /// the amber bars brown on the night paper.)
    var highlight: Int? = nil
    var scale: CGFloat = 1
    var height: CGFloat = 110
    /// A column behind its bar and a callout with its count.
    var picked: Int? = nil
    /// Touching a bar picks it; a tap on the picked one lets it go.
    var onPick: ((Int?) -> Void)? = nil

    var body: some View {
        Chart {
            ForEach(Array(counts.enumerated()), id: \.offset) { hour, count in
                BarMark(x: .value("Hour", String(hour)), y: .value("Aircraft", count), width: .ratio(0.72))
                    .foregroundStyle(ChartTone.timeOfDay(hour))
                    .clipShape(RoundedRectangle(cornerRadius: 2 * scale))
                    .annotation(position: .top, spacing: 2 * scale) {
                        if hour == highlight {
                            Circle().fill(Palette.value).frame(width: 5 * scale, height: 5 * scale)
                        }
                    }
            }
            if let picked, counts.indices.contains(picked) {
                LogbookChartStyle.callout(x: String(picked), count: counts[picked], label: LogbookFormat.hourRange(picked), scale: scale)
            }
        }
        .chartBackground { proxy in
            if let picked { LogbookPickedColumn(proxy: proxy, x: String(picked), bars: counts.count, scale: scale) }
        }
        #if os(iOS)
        .modifier(LogbookBarPicking(picked: picked.map(String.init),
                                    onPick: { label in onPick?(label.flatMap(Int.init)) },
                                    enabled: onPick != nil))
        #endif
        .chartXAxis {
            // A band axis labels every category; only every sixth hour gets one.
            AxisMarks { value in
                if let hour = value.as(String.self).flatMap(Int.init), hour % 6 == 0 {
                    AxisValueLabel(anchor: .topLeading, collisionResolution: .disabled) {
                        Text(LogbookFormat.hour(hour)).font(.mono(9 * scale, .semibold)).foregroundStyle(Palette.caption)
                    }
                }
            }
        }
        .chartYAxis { LogbookChartStyle.countAxis(scale: scale) }
        .frame(height: height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft by hour of the day")
        .accessibilityValue(picked.map { "\(LogbookFormat.hourRange($0)): \(counts[$0]) picked" }
                            ?? LogbookChartStyle.peakDescription(counts) { LogbookFormat.hour($0) })
        #if os(iOS)
        .accessibilityAdjustableAction { direction in
            guard let onPick else { return }
            let next = direction == .increment ? (picked.map { $0 + 1 } ?? 0) : (picked.map { $0 - 1 } ?? counts.count - 1)
            if counts.indices.contains(next) { onPick(next) }
        }
        #endif
    }
}

/// Aircraft per weekday, starting on the calendar's first day of the week. With `onPick`,
/// touch a bar to read it (iPhone and iPad).
struct LogbookWeekdayChart: View {
    /// Sunday first.
    let counts: [Int]
    var scale: CGFloat = 1
    var height: CGFloat = 110
    /// 0 = Sunday: a column behind its bar and a callout with its count.
    var picked: Int? = nil
    /// Touching a bar picks it; a tap on the picked one lets it go.
    var onPick: ((Int?) -> Void)? = nil

    /// The weekdays left to right, Sunday = 0, from the calendar's first day of the week.
    static func order(_ calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
    }

    var body: some View {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        let busiest = counts.max().flatMap { max in max > 0 ? counts.firstIndex(of: max) : nil }
        Chart {
            ForEach(Self.order(calendar), id: \.self) { i in
                BarMark(x: .value("Day", symbols[i]), y: .value("Aircraft", counts[i]), width: .ratio(0.62))
                    .foregroundStyle(LinearGradient(gradient: ChartTone.heat, startPoint: .bottom, endPoint: .top))
                    .alignsMarkStylesWithPlotArea()
                    .opacity(i == busiest ? 1 : 0.85)
                    .clipShape(RoundedRectangle(cornerRadius: 3 * scale))
            }
            if let picked, counts.indices.contains(picked) {
                LogbookChartStyle.callout(x: symbols[picked], count: counts[picked], label: "\(calendar.weekdaySymbols[picked])s", scale: scale)
            }
        }
        .chartBackground { proxy in
            if let picked { LogbookPickedColumn(proxy: proxy, x: symbols[picked], bars: 7, scale: scale) }
        }
        #if os(iOS)
        .modifier(LogbookBarPicking(picked: picked.map { symbols[$0] },
                                    onPick: { label in onPick?(label.flatMap { symbols.firstIndex(of: $0) }) },
                                    enabled: onPick != nil))
        #endif
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.mono(9 * scale, .semibold)).foregroundStyle(Palette.caption)
            }
        }
        .chartYAxis { LogbookChartStyle.countAxis(scale: scale) }
        .frame(height: height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aircraft by day of the week")
        .accessibilityValue(picked.map { "\(calendar.weekdaySymbols[$0]): \(counts[$0]) picked" }
                            ?? LogbookChartStyle.peakDescription(counts) { calendar.weekdaySymbols[$0] })
        #if os(iOS)
        .accessibilityAdjustableAction { direction in
            guard let onPick else { return }
            let order = Self.order(calendar)
            let at = picked.flatMap { order.firstIndex(of: $0) }
            let next = direction == .increment ? (at.map { $0 + 1 } ?? 0) : (at.map { $0 - 1 } ?? order.count - 1)
            if order.indices.contains(next) { onPick(order[next]) }
        }
        #endif
    }
}

/// Aircraft per day (or per month), oldest first, with the average as a dashed line. Taller
/// bars run warmer (`ChartTone.heat`); the current day or month is teal. On iPhone and iPad,
/// touch a bar to read it.
struct LogbookActivityChart: View {
    let points: [(day: Date, count: Int)]
    var unit: Calendar.Component = .day
    var scale: CGFloat = 1
    var height: CGFloat = 130
    /// Read out as if touched (the TV's full-screen chart, which the remote steps through).
    var picked: Date? = nil

    @State private var selected: Date?

    var body: some View {
        let average = points.isEmpty ? 0 : Double(points.reduce(0) { $0 + $1.count }) / Double(points.count)
        let calendar = Calendar.current
        let pick = (selected ?? picked).flatMap { s in points.first { calendar.isDate($0.day, equalTo: s, toGranularity: unit) } }
        Chart {
            ForEach(points, id: \.day) { p in
                BarMark(x: .value("Date", p.day, unit: unit), y: .value("Aircraft", p.count))
                    .foregroundStyle(barStyle(p, calendar: calendar))
                    .alignsMarkStylesWithPlotArea()
                    .opacity(pick == nil || pick?.day == p.day ? 1 : 0.35)
                    .clipShape(RoundedRectangle(cornerRadius: 2 * scale))
            }
            if average > 0 {
                RuleMark(y: .value("Average", average))
                    .lineStyle(StrokeStyle(lineWidth: 1 * scale, dash: [4 * scale, 3 * scale]))
                    .foregroundStyle(Palette.caption.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(Int(average.rounded()))")
                            .font(.mono(9 * scale, .bold))
                            .foregroundStyle(Palette.caption)
                    }
            }
            if let pick {
                RuleMark(x: .value("Date", pick.day, unit: unit))
                    .foregroundStyle(Palette.ink.opacity(0.25))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text("\(pick.count)").font(.mono(13 * scale, .heavy)).foregroundStyle(Palette.ink)
                            Text(pick.day.formatted(unit == .month ? .dateTime.month(.abbreviated).year() : .dateTime.month(.abbreviated).day()))
                                .font(.mono(9 * scale, .semibold)).foregroundStyle(Palette.caption)
                        }
                        .padding(.horizontal, 6 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 6 * scale))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: unit, count: unit == .month ? 1 : max(1, points.count / 4))) { _ in
                AxisValueLabel(format: unit == .month ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
                    .font(.mono(9 * scale, .semibold))
                    .foregroundStyle(Palette.caption)
            }
        }
        .chartYAxis { LogbookChartStyle.countAxis(scale: scale) }
        #if os(iOS)
        .chartXSelection(value: $selected)
        #endif
        .frame(height: height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit == .month ? "Aircraft per month" : "Aircraft per day")
        .accessibilityValue("Average \(Int(average.rounded())); most \(points.map(\.count).max() ?? 0)")
    }

    private func barStyle(_ p: (day: Date, count: Int), calendar: Calendar) -> AnyShapeStyle {
        if calendar.isDate(p.day, equalTo: Date(), toGranularity: unit) { return AnyShapeStyle(ChartTone.teal.color) }
        return AnyShapeStyle(LinearGradient(gradient: ChartTone.heat, startPoint: .bottom, endPoint: .top))
    }
}

/// Altitude at the closest pass in 5,000 ft (1,500 m) bands, highest at the top: a row per band, its
/// label in a column of its own so it never touches the bar. Warm near the ground, cool up
/// high (`ChartTone.altitude`).
struct LogbookAltitudeChart: View {
    let bins: [Int]
    var scale: CGFloat = 1
    var height: CGFloat = 180
    /// A band behind its row (the TV's full-screen chart).
    var picked: Int? = nil

    var body: some View {
        let labels = bins.indices.map { LogbookSky.altitudeBandLabel($0) }
        let peak = max(1, bins.max() ?? 1)
        let busiest = bins.max().flatMap { max in max > 0 ? bins.firstIndex(of: max) : nil }
        VStack(spacing: 4 * scale) {
            ForEach(bins.indices.reversed(), id: \.self) { i in
                let tint = ChartTone.altitude(Double(i) / Double(max(1, bins.count - 1)))
                HStack(spacing: 12 * scale) {
                    Text(labels[i])
                        .font(.mono(10 * scale, i == busiest ? .heavy : .semibold))
                        .foregroundStyle(i == busiest ? tint : Palette.caption)
                        .lineLimit(1)
                        .frame(width: 64 * scale, alignment: .trailing)
                    GeometryReader { geo in
                        let countWidth = 44 * scale
                        let barWidth = (geo.size.width - countWidth) * Double(bins[i]) / Double(peak)
                        HStack(spacing: 6 * scale) {
                            RoundedRectangle(cornerRadius: 3 * scale)
                                .fill(tint.opacity(i == busiest ? 1 : 0.8))
                                .frame(width: bins[i] > 0 ? max(3 * scale, barWidth) : 0)
                            if bins[i] > 0 {
                                Text(RadarFormat.wholeNumber(bins[i]))
                                    .font(.mono(9 * scale, .semibold))
                                    .foregroundStyle(Palette.caption)
                                    .fixedSize()
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
                .background {
                    if i == picked {
                        RoundedRectangle(cornerRadius: 4 * scale, style: .continuous)
                            .fill(Palette.ink.opacity(0.12))
                            .padding(.horizontal, -6 * scale)
                            .padding(.vertical, -1 * scale)
                    }
                }
            }
        }
        .frame(height: height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Altitude at the closest pass")
        .accessibilityValue(LogbookChartStyle.peakDescription(bins) { i in
            let label = labels[i].replacingOccurrences(of: " km", with: "").replacingOccurrences(of: " ft", with: "")
            return "\(label) \(Units.isMetric ? "kilometers" : "feet")"
        })
    }
}

/// Which way aircraft were heading at their closest pass: 16 petals, longer for more
/// traffic, each the colour of its direction (`ChartTone.heading`) and the busiest strongest,
/// around a dot for you. With a petal picked, the others turn grey (fading them would turn the
/// warm ones brown on the night paper). With `onPick`, tap a petal to pick it (iPhone, iPad).
struct LogbookHeadingRose: View {
    /// 16 sectors, north first.
    let sectors: [Int]
    var size: CGFloat = 180
    var scale: CGFloat = 1
    var picked: Int? = nil
    /// A tap on a petal picks it; on the picked one, or off the petals, lets it go.
    var onPick: ((Int?) -> Void)? = nil

    var body: some View {
        let peak = max(1, sectors.max() ?? 1)
        let busiest = sectors.firstIndex(of: peak)
        let picked = picked.flatMap { sectors.indices.contains($0) ? $0 : nil }
        ZStack {
            ForEach([0.33, 0.66, 1.0], id: \.self) { r in
                Circle().stroke(Palette.ink.opacity(r == 1 ? 0.16 : 0.09), lineWidth: r == 1 ? 1.5 * scale : 1)
                    .frame(width: size * 0.78 * r, height: size * 0.78 * r)
            }
            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let outer = min(canvasSize.width, canvasSize.height) * 0.39
                // Ticks every 45° on the outer ring.
                for k in 0..<8 {
                    let a = Angle.degrees(Double(k) * 45 - 90)
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + cos(a.radians) * outer * 0.94, y: center.y + sin(a.radians) * outer * 0.94))
                    tick.addLine(to: CGPoint(x: center.x + cos(a.radians) * outer * 1.04, y: center.y + sin(a.radians) * outer * 1.04))
                    context.stroke(tick, with: .color(Palette.caption.opacity(0.6)), lineWidth: k % 2 == 0 ? 1.5 * scale : 1)
                }
                for (i, count) in sectors.enumerated() where count > 0 {
                    // Area-true: radius grows with the square root of the count.
                    let radius = outer * sqrt(Double(count) / Double(peak))
                    let mid = Angle.degrees(Double(i) * 22.5 - 90)
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius, startAngle: mid - .degrees(9.5), endAngle: mid + .degrees(9.5), clockwise: false)
                    path.closeSubpath()
                    if let picked, picked != i {
                        context.fill(path, with: .color(Palette.faint.opacity(0.55)))
                        continue
                    }
                    let tint = ChartTone.heading(Double(i) * 22.5)
                    let strength = i == busiest || i == picked ? 1.0 : 0.85
                    context.fill(path, with: .radialGradient(Gradient(colors: [tint.opacity(0.6 * strength), tint.opacity(strength)]),
                                                             center: center, startRadius: 0, endRadius: radius))
                    if i == picked {
                        context.stroke(path, with: .color(Palette.value), lineWidth: 1.5 * scale)
                    }
                }
                let dot = max(3, 3.5 * scale)
                context.fill(Path(ellipseIn: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(Palette.signal))
            }
            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { i, label in
                let angle = Double(i) * .pi / 2
                Text(label)
                    .font(.mono(10 * scale, .heavy))
                    .foregroundStyle(i == 0 ? Palette.signal : Palette.caption)
                    .position(x: size / 2 + sin(angle) * size * 0.46, y: size / 2 - cos(angle) * size * 0.46)
            }
        }
        .frame(width: size, height: size)
        #if os(iOS)
        .contentShape(Circle())
        .onTapGesture(coordinateSpace: .local) { location in
            guard let onPick else { return }
            let hit = sector(at: location)
            onPick(hit == picked ? nil : hit)
        }
        .sensoryFeedback(.selection, trigger: picked) { _, new in new != nil && onPick != nil }
        #endif
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Directions aircraft were heading")
        .accessibilityValue(picked.map { "\(LogbookFormat.sectorWords[$0]): \(sectors[$0]) picked" }
                            ?? LogbookChartStyle.peakDescription(sectors) { LogbookFormat.sectorNames[$0] })
        #if os(iOS)
        .accessibilityAdjustableAction { direction in
            guard let onPick else { return }
            onPick(Self.step(from: picked, by: direction == .increment ? 1 : -1, in: sectors))
        }
        #endif
    }

    /// The petal with traffic under a touch, by its angle from the middle; nil off the rose.
    private func sector(at location: CGPoint) -> Int? {
        let dx = location.x - size / 2, dy = location.y - size / 2
        guard (dx * dx + dy * dy).squareRoot() <= size / 2 else { return nil }
        let degrees = GeoMath.normalize(atan2(dx, -dy) * 180 / .pi)
        let sector = Int(((degrees + 11.25) / 22.5).rounded(.down)) % 16
        return sectors.indices.contains(sector) && sectors[sector] > 0 ? sector : nil
    }

    /// The next petal with traffic clockwise (`by` 1) or anticlockwise (-1), round the rose;
    /// with none picked, the busiest.
    static func step(from sector: Int?, by delta: Int, in sectors: [Int]) -> Int? {
        guard let sector else {
            guard let max = sectors.max(), max > 0 else { return nil }
            return sectors.firstIndex(of: max)
        }
        for k in 1...sectors.count {
            let next = ((sector + delta * k) % sectors.count + sectors.count) % sectors.count
            if sectors[next] > 0 { return next }
        }
        return sector
    }
}

enum LogbookChartStyle {
    static func countAxis(scale: CGFloat) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine().foregroundStyle(Palette.ink.opacity(0.08))
            AxisValueLabel().font(.mono(9 * scale)).foregroundStyle(Palette.caption)
        }
    }

    /// "Most at 8 AM: 21".
    static func peakDescription(_ counts: [Int], name: (Int) -> String) -> String {
        guard let max = counts.max(), max > 0, let i = counts.firstIndex(of: max) else { return "No aircraft yet" }
        return "Most at \(name(i)): \(max)"
    }

    /// The picked bar's count and name over the top of the plot, like the activity chart's.
    static func callout(x: String, count: Int, label: String, scale: CGFloat) -> some ChartContent {
        RuleMark(x: .value("Picked", x))
            .foregroundStyle(.clear)
            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                VStack(spacing: 1) {
                    Text(RadarFormat.wholeNumber(count)).font(.mono(13 * scale, .heavy)).foregroundStyle(Palette.ink)
                    Text(label).font(.mono(9 * scale, .semibold)).foregroundStyle(Palette.caption)
                }
                .padding(.horizontal, 6 * scale)
                .padding(.vertical, 3 * scale)
                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 6 * scale))
            }
    }
}

/// Behind a picked bar: a soft column the full height of the plot, so the bar keeps its own
/// colour (fading the others would turn warm bars brown on the night paper).
struct LogbookPickedColumn: View {
    let proxy: ChartProxy
    let x: String
    /// Bars across the plot, for the column's width.
    let bars: Int
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            if let frame = proxy.plotFrame, let center = proxy.position(forX: x) {
                let plot = geo[frame]
                RoundedRectangle(cornerRadius: 4 * scale, style: .continuous)
                    .fill(Palette.ink.opacity(0.12))
                    .frame(width: plot.width / CGFloat(max(1, bars)), height: plot.height)
                    .position(x: plot.minX + center, y: plot.midY)
            }
        }
    }
}

#if os(iOS)
/// Tap a bar to pick it, or drag sideways (or press and drag) to run along them reading each
/// one, as on the altitude-vs-speed chart; up-and-down swipes still scroll the page. The pick
/// stays when the finger lifts (so its aircraft are a tap away), and a tap on the picked bar
/// lets it go.
struct LogbookBarPicking: ViewModifier {
    /// The picked bar's x label.
    let picked: String?
    let onPick: (String?) -> Void
    var enabled = true

    func body(content: Content) -> some View {
        if enabled {
            content
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let label = { (location: CGPoint) -> String? in
                            guard let frame = proxy.plotFrame else { return nil }
                            return proxy.value(atX: location.x - geo[frame].minX, as: String.self)
                        }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(coordinateSpace: .local) { location in
                                guard let hit = label(location) else { return }
                                onPick(hit == picked ? nil : hit)
                            }
                            .gesture(SidewaysScrub { location in scrub(to: label(location)) })
                            .gesture(PressAndScrub { location in scrub(to: label(location)) })
                    }
                }
                .sensoryFeedback(.selection, trigger: picked) { _, new in new != nil }
        } else {
            content
        }
    }

    private func scrub(to label: String?) {
        if let label, label != picked { onPick(label) }
    }
}
#endif

extension LogbookSkySlice {
    /// The colour its bar or petal has on the chart.
    var tint: Color {
        switch self {
        case .heading(let i): return ChartTone.heading(Double(i) * 22.5)
        case .hour(let h): return ChartTone.timeOfDay(h)
        case .weekday: return ChartTone.amber.color
        case .altitude(let b): return ChartTone.altitude(Double(b) / Double(max(1, LogbookSky.altitudeBands - 1)))
        }
    }
}

/// What a picked petal or bar is made of: its share in big type and how it ranks, then who
/// flies it (airlines, types, routes, each with its share) and how (typical altitude, usual
/// hour, main direction). `compact` puts it in three lines, under a chart.
struct LogbookSliceOverview: View {
    let summary: LogbookSliceSummary
    var scale: CGFloat = 1
    var compact = false
    /// Compact: a button to let the pick go.
    var onClose: (() -> Void)? = nil

    var body: some View {
        let s = summary
        if compact {
            HStack(alignment: .top, spacing: 4 * scale) {
                VStack(alignment: .leading, spacing: 4 * scale) {
                    HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                        Text("\(s.percent)%")
                            .monoScaled(22 * scale, .heavy)
                            .foregroundStyle(s.slice.tint)
                        Text(s.slice.title)
                            .monoScaled(14 * scale, .bold)
                            .foregroundStyle(Palette.value)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Text(countLine)
                        .monoScaled(11 * scale)
                        .foregroundStyle(Palette.caption)
                    if s.count > 0 {
                        Text(mostlyLine)
                            .monoScaled(11 * scale, .semibold)
                            .foregroundStyle(Palette.value)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18 * scale))
                            .foregroundStyle(Palette.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the pick")
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12 * scale) {
                VStack(alignment: .leading, spacing: 2 * scale) {
                    HStack(alignment: .firstTextBaseline, spacing: 10 * scale) {
                        Text("\(s.percent)%")
                            .monoScaled(44 * scale, .heavy)
                            .foregroundStyle(s.slice.tint)
                        Text(s.slice.phrase)
                            .monoScaled(16 * scale, .bold)
                            .foregroundStyle(Palette.value)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    Text(countLine)
                        .monoScaled(11 * scale)
                        .foregroundStyle(Palette.caption)
                }
                .accessibilityElement(children: .combine)
                if s.count == 0 {
                    Text("No aircraft logged here yet.")
                        .monoScaled(12 * scale)
                        .foregroundStyle(Palette.caption)
                } else {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12 * scale, verticalSpacing: 8 * scale) {
                        fact("Airlines", shares(s.airlines))
                        fact("Types", shares(s.types))
                        fact("Routes", shares(s.routes))
                        fact("Altitude", s.typicalAltitudeFeet.map { "Typically \(RadarFormat.altitudeText($0))" })
                        fact("Time", s.busiestHour.map { "Mostly \(LogbookFormat.hourRange($0))" })
                        fact("Heading", s.mainSector.map { "Mostly \(LogbookFormat.sectorWords[$0].lowercased())" })
                    }
                }
            }
        }
    }

    /// "312 of 1,300 aircraft · the busiest direction".
    private var countLine: String {
        let s = summary
        let count = "\(RadarFormat.wholeNumber(s.count)) of \(RadarFormat.wholeNumber(s.total)) aircraft"
        return s.count > 0 ? "\(count) · \(s.rankText.prefix(1).lowercased() + s.rankText.dropFirst())" : count
    }

    /// "Mostly Delta Air Lines · Boeing 737-800 · heading west · 9,000 ft".
    private var mostlyLine: String {
        let s = summary
        let parts = [s.airlines.first?.title, s.types.first?.title,
                     s.mainSector.map { "heading \(LogbookFormat.direction(Double($0) * 22.5))" },
                     s.busiestHour.map { "usually \(LogbookFormat.hourRange($0))" },
                     s.typicalAltitudeFeet.map { RadarFormat.altitudeText($0) }]
        return "Mostly " + parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// "Delta Air Lines 41% · American Airlines 12%": each one's share of the slice.
    private func shares(_ ranks: [LogbookRank]) -> String? {
        guard !ranks.isEmpty, summary.count > 0 else { return nil }
        return ranks.map { "\($0.title) \(Int((Double($0.count) / Double(summary.count) * 100).rounded()))%" }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label)
                    .monoScaled(10 * scale, .semibold)
                    .tracking(1.2 * scale)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.caption)
                    .gridColumnAlignment(.leading)
                Text(value)
                    .monoScaled(12 * scale, .semibold)
                    .foregroundStyle(Palette.value)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// How close a sky chart is to having enough aircraft behind it: "38 of 50" and a bar.
struct LogbookSkyProgress: View {
    let count: Int
    /// After "of 50": "aircraft", "with a heading".
    var noun = "aircraft"
    var scale: CGFloat = 1

    var body: some View {
        let fraction = min(1, Double(count) / Double(LogbookSky.minimum))
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                Text(RadarFormat.wholeNumber(count))
                    .monoScaled(28 * scale, .heavy)
                    .foregroundStyle(ChartTone.teal.color)
                Text("of \(LogbookSky.minimum) \(noun)")
                    .monoScaled(13 * scale, .bold)
                    .foregroundStyle(Palette.value)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.ink.opacity(0.12))
                    Capsule().fill(ChartTone.teal.color)
                        .frame(width: max(6 * scale, geo.size.width * fraction))
                }
            }
            .frame(height: 8 * scale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of \(LogbookSky.minimum) \(noun)")
    }
}

/// A bar for a share of the top entry, coloured along the whole track by `ChartTone.heat`, so
/// the longest bars reach amber.
struct LogbookShareBar: View {
    let share: Double
    var strength: Double = 1
    var minWidth: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            LinearGradient(gradient: ChartTone.heat, startPoint: .leading, endPoint: .trailing)
                .mask(alignment: .leading) {
                    Capsule().frame(width: max(minWidth, geo.size.width * min(1, share)))
                }
                .opacity(strength)
        }
    }
}

/// A ranked entry with a bar for its share of the top one.
struct LogbookRankRow: View {
    let rank: Int
    let entry: LogbookRank
    let top: Int
    var showsGlyph = false
    /// The aircraft ranking, whose entries are airframes: favourites in yellow.
    var marksFavorites = false
    var scale: CGFloat = 1

    @Environment(\.favoriteAircraft) private var favorites

    var body: some View {
        let isFavorite = marksFavorites && favorites.contains(airframe: entry.id)
        HStack(spacing: 10 * scale) {
            Text("\(rank)")
                .monoScaled(12 * scale, .heavy)
                .foregroundStyle(Palette.caption)
                .frame(width: 22 * scale, alignment: .leading)
            if showsGlyph {
                AircraftGlyph(silhouette: entry.latest.silhouette, size: 24 * scale, spinsRotor: false)
                    .foregroundStyle(isFavorite ? Palette.favorite : entry.latest.tint)
                    .frame(width: 26 * scale)
            }
            VStack(alignment: .leading, spacing: 4 * scale) {
                HStack(alignment: .firstTextBaseline, spacing: 6 * scale) {
                    Text(entry.title)
                        .monoScaled(14 * scale, .bold)
                        .foregroundStyle(isFavorite ? Palette.favoriteText : Palette.ink)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10 * scale, weight: .bold))
                            .foregroundStyle(Palette.favorite)
                    }
                    if let subtitle = entry.subtitle {
                        Text(subtitle)
                            .monoScaled(11 * scale)
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                    }
                }
                LogbookShareBar(share: Double(entry.count) / Double(max(top, 1)), strength: rank == 1 ? 1 : 0.75, minWidth: 4 * scale)
                    .frame(height: 4 * scale)
            }
            Text("\(RadarFormat.wholeNumber(entry.count))×")
                .monoScaled(15 * scale, .heavy)
                .foregroundStyle(Palette.value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Number \(rank), \(entry.title)\(isFavorite ? ", favorite" : "")\(entry.subtitle.map { ", \($0)" } ?? ""), \(entry.count) times")
    }
}
#endif
