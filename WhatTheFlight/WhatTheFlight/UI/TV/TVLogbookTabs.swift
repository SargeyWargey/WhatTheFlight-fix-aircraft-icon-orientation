//
//  TVLogbookTabs.swift
//  WhatTheFlight
//
//  The Apple TV logbook's five tabs. Overview: today, the numbers, the last two weeks and
//  shelves of highlights, records, badges and regulars. Sightings: days (this week) and
//  months on the left, that period's aircraft on the right, with quick filters. Stats: the
//  charts and every ranking. Badges: next up, then every badge by group. Photos: every Sky
//  View photo. Charts are focusable cards so the remote can scroll to them.
//

#if os(tvOS)
import SwiftUI

struct TVLogbookContext {
    let logbook: Logbook
    let showPhotos: Bool
    let isLive: (String) -> Bool
    let actions: TVLogbookActions
}

// MARK: - Shared pieces

/// A titled row of cards that scrolls sideways.
private struct TVShelf<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TVSectionHeader(title: title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 32) { content }
                    .padding(.vertical, 26)
                    .padding(.horizontal, 8)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// A chart or summary on a card the remote can land on, so the page scrolls to it.
private struct TVChartCard<Content: View>: View {
    var title: String? = nil
    var detail: String? = nil
    @ViewBuilder var content: Content

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if title != nil || detail != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title { Text(title).radarCaptionTV() }
                    Spacer()
                    if let detail {
                        Text(detail).font(.mono(22, .bold)).foregroundStyle(Palette.value)
                    }
                }
            }
            content
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Palette.paperShade.opacity(focused ? 0.6 : 0.35)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Palette.ink, lineWidth: focused ? 4 : 0))
        .scaleEffect(focused ? 1.02 : 1)
        .shadow(color: .black.opacity(focused ? 0.2 : 0), radius: 20, y: 10)
        .focusable()
        .focused($focused)
        .animation(.snappy(duration: 0.18), value: focused)
    }
}

/// "See all" at the end of a shelf.
private struct TVMoreCard: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "chevron.right.circle.fill").font(.system(size: 44, weight: .semibold))
                Text(title).font(.mono(24, .bold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(Palette.ink)
            .frame(width: 220, height: 200)
        }
        .buttonStyle(TVCardButtonStyle())
    }
}

/// A ranked entry as a focusable row.
private struct TVRankRow: View {
    let rank: Int
    let entry: LogbookRank
    let top: Int
    var showsGlyph = false
    @Environment(\.tvRowFocused) private var focused

    var body: some View {
        HStack(spacing: 18) {
            Text("\(rank)")
                .font(.mono(22, .heavy))
                .foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                .frame(width: 36, alignment: .leading)
            if showsGlyph {
                AircraftGlyph(silhouette: entry.latest.silhouette, size: 36, spinsRotor: false)
                    .foregroundStyle(focused ? .white : entry.latest.tint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.mono(24, .bold)).lineLimit(1)
                if let subtitle = entry.subtitle {
                    Text(subtitle).font(.mono(17)).foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption).lineLimit(1)
                }
                GeometryReader { geo in
                    if focused {
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: max(6, geo.size.width * Double(entry.count) / Double(max(top, 1))))
                    } else {
                        LogbookShareBar(share: Double(entry.count) / Double(max(top, 1)), strength: rank == 1 ? 1 : 0.75, minWidth: 6)
                    }
                }
                .frame(height: 5)
            }
            Spacer(minLength: 10)
            Text("\(RadarFormat.wholeNumber(entry.count))×").font(.mono(26, .heavy))
        }
    }
}

private func sightingCardContent(_ s: Sighting, reason: String?, reasonColor: Color) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 14) {
            AircraftGlyph(silhouette: s.silhouette, size: 44, spinsRotor: false)
                .foregroundStyle(s.tint)
            Text(s.displayIdentifier)
                .font(.mono(34, .heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 8)
            Text(s.closestText).font(.mono(24, .bold)).foregroundStyle(Palette.value)
        }
        if let route = s.routeText {
            Text(route).font(.mono(22, .semibold)).foregroundStyle(Palette.route)
        }
        Text(s.summaryLine)
            .font(.mono(20))
            .foregroundStyle(Palette.caption)
            .lineLimit(1)
        Spacer(minLength: 0)
        if let reason {
            Text(reason).font(.mono(20, .heavy)).foregroundStyle(reasonColor).lineLimit(1)
        }
    }
    .padding(24)
    .frame(width: 420, height: 220, alignment: .topLeading)
}

// MARK: - Overview

struct TVLogbookOverview: View {
    let ctx: TVLogbookContext

    var body: some View {
        let digest = ctx.logbook.digest
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if ctx.logbook.isEmpty {
                    Text("Every aircraft that comes inside your radius is logged here automatically, with stats, records and badges.")
                        .font(.mono(28))
                        .foregroundStyle(Palette.caption)
                        .padding(.top, 80)
                } else {
                    today(digest)
                    activity(digest)
                    highlights(digest)
                    records(digest)
                    badges(digest)
                    regulars(digest)

                    TVSectionHeader(title: "Start over")
                    TVValueRow(title: "Clear Logbook", subtitle: "Remove every sighting and badge on this Apple TV", value: "", symbol: "trash",
                               action: ctx.actions.clear)
                        .focusSection()
                }
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 40)
        }
    }

    private func today(_ digest: LogbookDigest) -> some View {
        let recap = digest.today
        let stats = digest.stats
        return HStack(alignment: .bottom, spacing: 50) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today · \(recap.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))\(recap.places.first.map { " · \($0)" } ?? "")")
                    .radarCaptionTV()
                Text("\(RadarFormat.wholeNumber(recap.total)) aircraft")
                    .font(.mono(72, .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(recap.isEmpty ? "Nothing logged yet today" :
                        "\(recap.notable.count) notable · \(recap.newTypes.count) new type\(recap.newTypes.count == 1 ? "" : "s") · closest \(recap.closest?.closestPreciseText ?? "—")")
                    .font(.mono(26, .semibold))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(minWidth: 600, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                LogbookStatTile(title: "Spotted", value: RadarFormat.wholeNumber(stats.total), scale: 1.7).frame(width: 200)
                LogbookStatTile(title: "Airframes", value: RadarFormat.wholeNumber(stats.uniqueAirframes), scale: 1.7, tint: ChartTone.sky.color).frame(width: 200)
                LogbookStatTile(title: "Types", value: RadarFormat.wholeNumber(stats.uniqueTypes), scale: 1.7, tint: ChartTone.teal.color).frame(width: 160)
                LogbookStatTile(title: "Airlines", value: RadarFormat.wholeNumber(stats.uniqueAirlines), scale: 1.7, tint: ChartTone.pink.color).frame(width: 160)
                LogbookStatTile(title: "Streak", value: "\(digest.streak.current)d", scale: 1.7, symbol: "flame.fill", tint: ChartTone.coral.color).frame(width: 160)
            }
        }
    }

    private func activity(_ digest: LogbookDigest) -> some View {
        TVChartCard(title: "Last 14 days",
                    detail: "\(digest.streak.current)-day streak · best \(digest.streak.best)\(digest.busiestDay.map { " · best day \($0.count)" } ?? "")") {
            LogbookActivityChart(points: digest.recentDays(14), scale: 2, height: 90)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func highlights(_ digest: LogbookDigest) -> some View {
        let recap = digest.today
        let items = recap.notable.map { ($0, $0.notableReason ?? "Notable", Palette.color(for: $0.tags.first ?? .rare)) }
            + recap.newTypes.filter { s in !recap.notable.contains { $0.id == s.id } }
                .map { ($0, "First \($0.typeName ?? $0.typeCode ?? "of its type")", Palette.ink) }
        if !items.isEmpty {
            TVShelf(title: "Today's highlights") {
                ForEach(Array(items.enumerated()), id: \.element.0.id) { i, item in
                    Button {
                        ctx.actions.open(TVSightingBrowse(items.map { .init(sighting: $0.0, label: $0.1) }, start: i))
                    } label: {
                        sightingCardContent(item.0, reason: item.1, reasonColor: item.2)
                    }
                    .buttonStyle(TVCardButtonStyle())
                }
                TVMoreCard(title: "All of today") { ctx.actions.showTab(.sightings) }
            }
        }
    }

    private func records(_ digest: LogbookDigest) -> some View {
        let records = digest.records
        return TVShelf(title: "Records") {
            ForEach(Array(records.enumerated()), id: \.element.id) { i, r in
                Button {
                    ctx.actions.open(TVSightingBrowse(records.map { .init(sighting: $0.sighting, label: "\($0.title) · \($0.value)") }, start: i))
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        TVSightingPhoto(sighting: r.sighting, enabled: ctx.showPhotos, height: 190)
                            .padding(.bottom, 8)
                        Label(r.title, systemImage: r.symbol)
                            .labelStyle(TVLabelStyle())
                            .font(.mono(20, .bold))
                            .foregroundStyle(Palette.caption)
                        Text(r.value)
                            .font(.mono(40, .bold))
                            .foregroundStyle(r.tint)
                        Text([r.sighting.displayIdentifier, r.sighting.typeName ?? r.sighting.typeCode].compactMap { $0 }.joined(separator: " · "))
                            .font(.mono(20))
                            .foregroundStyle(Palette.caption)
                            .lineLimit(1)
                    }
                    .padding(22)
                    .frame(width: 400, alignment: .leading)
                }
                .buttonStyle(TVCardButtonStyle())
            }
        }
    }

    private func badges(_ digest: LogbookDigest) -> some View {
        let next = digest.nextUp(5)
        return TVShelf(title: next.isEmpty ? "Badges" : "Badges · next up · \(digest.unlockedCount) of \(digest.achievements.count) unlocked") {
            ForEach(next.isEmpty ? digest.recentlyUnlocked(5) : next) { a in
                Button { ctx.actions.badge(a) } label: {
                    TVBadgeCard(achievement: a)
                }
                .buttonStyle(TVCardButtonStyle())
            }
            TVMoreCard(title: "All badges") { ctx.actions.showTab(.badges) }
        }
    }

    @ViewBuilder
    private func regulars(_ digest: LogbookDigest) -> some View {
        let regulars = digest.rankings[.aircraft] ?? []
        if !regulars.isEmpty {
            TVShelf(title: "Your regulars") {
                ForEach(regulars.prefix(8)) { entry in
                    Button { ctx.actions.airframe(entry.id) } label: {
                        HStack(spacing: 20) {
                            AircraftGlyph(silhouette: entry.latest.silhouette, size: 52, spinsRotor: false)
                                .foregroundStyle(entry.latest.tint)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title).font(.mono(32, .heavy)).foregroundStyle(Palette.ink)
                                Text(entry.subtitle ?? "").font(.mono(19)).foregroundStyle(Palette.caption).lineLimit(1)
                            }
                            Spacer(minLength: 10)
                            Text("\(entry.count)×").font(.mono(36, .heavy)).foregroundStyle(Palette.value)
                        }
                        .padding(24)
                        .frame(width: 460, height: 150)
                    }
                    .buttonStyle(TVCardButtonStyle())
                }
                TVMoreCard(title: "Most seen") { ctx.actions.showTab(.stats) }
            }
        }
    }
}

/// A badge with its name and how far along it is.
private struct TVBadgeCard: View {
    let achievement: Achievement

    var body: some View {
        let a = achievement
        VStack(spacing: 12) {
            AchievementBadge(achievement: a, scale: 1.7, showsTitle: false)
            Text(a.title).font(.mono(24, .heavy)).foregroundStyle(Palette.value).lineLimit(1).minimumScaleFactor(0.7)
            if a.hasLevels { TierDots(earned: a.level, total: a.tiers.count, scale: 2) }
            Text(a.isMaxed ? "Done" : "\(RadarFormat.wholeNumber(min(a.progress, a.target))) of \(RadarFormat.wholeNumber(a.target))")
                .font(.mono(20, .semibold))
                .foregroundStyle(Palette.caption)
        }
        .padding(22)
        .frame(width: 280, height: 270)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AchievementBadge.accessibilityText(a))
    }
}

// MARK: - Sightings

/// A day this week, or an older month, and its sightings.
struct TVLogbookPeriod: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// Newest first.
    let sightings: [Sighting]
    let notable: Int
    let newTypes: Int
    let photos: Int
    let isDay: Bool

    /// Days within the last week, then months; `sightings` newest first.
    static func build(_ sightings: [Sighting], firstOfType: Set<String>, now: Date = Date(), calendar: Calendar = .current) -> [TVLogbookPeriod] {
        let weekStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        func make(_ id: String, _ title: String, _ subtitle: String, _ items: [Sighting], isDay: Bool) -> TVLogbookPeriod {
            TVLogbookPeriod(id: id, title: title, subtitle: subtitle, sightings: items,
                            notable: items.filter { !$0.tags.isEmpty }.count,
                            newTypes: items.filter { firstOfType.contains($0.id) }.count,
                            photos: items.reduce(0) { $0 + $1.spotPhotos.count }, isDay: isDay)
        }
        let recent = sightings.filter { $0.firstSeen >= weekStart }
        let older = sightings.filter { $0.firstSeen < weekStart }
        let days = LogbookGrouping.byDay(recent, calendar: calendar).map { group in
            make("d\(group.day.timeIntervalSince1970)", LogbookGrouping.shortTitle(for: group.day, calendar: calendar),
                 group.day.formatted(.dateTime.month(.abbreviated).day()), group.items, isDay: true)
        }
        let byMonth = Dictionary(grouping: older) { calendar.dateInterval(of: .month, for: $0.firstSeen)?.start ?? $0.firstSeen }
        let months = byMonth.keys.sorted(by: >).map { month in
            let items = byMonth[month]!.sorted { $0.firstSeen > $1.firstSeen }
            let dayCount = Set(items.map { calendar.startOfDay(for: $0.firstSeen) }).count
            return make("m\(month.timeIntervalSince1970)", month.formatted(.dateTime.month(.wide)),
                        "\(month.formatted(.dateTime.year())) · \(dayCount) day\(dayCount == 1 ? "" : "s")", items, isDay: false)
        }
        return days + months
    }
}

struct TVLogbookSightings: View {
    let ctx: TVLogbookContext

    @State private var filter: LogbookFilter?
    @State private var selected: String?
    @FocusState private var focusedPeriod: String?

    var body: some View {
        let digest = ctx.logbook.digest
        let all = filter.map { f in ctx.logbook.recent.filter { f.matches($0, firstOfType: digest.firstOfType) } } ?? ctx.logbook.recent
        let periods = TVLogbookPeriod.build(all, firstOfType: digest.firstOfType)
        let current = periods.first { $0.id == selected } ?? periods.first
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                Button("All") { filter = nil }
                    .buttonStyle(TVChipButtonStyle(isSelected: filter == nil))
                ForEach(LogbookFilter.quick, id: \.self) { f in
                    Button(f.title) { filter = filter == f ? nil : f }
                        .buttonStyle(TVChipButtonStyle(isSelected: filter == f))
                }
            }
            .focusSection()

            HStack(alignment: .top, spacing: 50) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(periods) { p in
                            Button { selected = p.id } label: {
                                TVPeriodRow(period: p, isSelected: p.id == current?.id)
                            }
                            .buttonStyle(TVRowButtonStyle())
                            .focused($focusedPeriod, equals: p.id)
                        }
                        if periods.isEmpty {
                            Text(filter == nil ? "Nothing logged yet." : "Nothing matches \(filter!.title.lowercased()).")
                                .font(.mono(24))
                                .foregroundStyle(Palette.caption)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 10)
                }
                .scrollClipDisabled()
                .frame(width: 560)
                .focusSection()

                if let current {
                    TVPeriodDetail(period: current, ctx: ctx)
                        .id(current.id)
                        .focusSection()
                }
            }
        }
        .padding(.horizontal, 100)
        .padding(.top, 40)
        .onChange(of: focusedPeriod) { _, id in
            if let id { selected = id }
        }
        .onChange(of: filter) { _, _ in selected = nil }
    }
}

private struct TVPeriodRow: View {
    let period: TVLogbookPeriod
    let isSelected: Bool
    @Environment(\.tvRowFocused) private var focused

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(period.title).font(.mono(28, .heavy))
                    Text(period.subtitle).font(.mono(18)).foregroundStyle(focused ? .white.opacity(0.8) : Palette.caption)
                }
                .lineLimit(1)
                tags
            }
            Spacer(minLength: 10)
            Text(RadarFormat.wholeNumber(period.sightings.count)).font(.mono(32, .heavy))
        }
        .overlay(alignment: .leading) {
            if isSelected && !focused {
                Capsule().fill(Palette.ink).frame(width: 5).padding(.vertical, 4).offset(x: -18)
            }
        }
    }

    private var tags: some View {
        HStack(spacing: 16) {
            if period.notable > 0 { tag("star.fill", "\(period.notable)", Palette.notable) }
            if period.newTypes > 0 { tag("sparkles", "\(period.newTypes) new", Palette.ink) }
            if period.photos > 0 { tag("camera.fill", "\(period.photos)", Palette.signal) }
        }
        .font(.mono(17, .bold))
    }

    private func tag(_ symbol: String, _ text: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(TVLabelStyle())
            .foregroundStyle(focused ? .white : color)
    }
}

private struct TVPeriodDetail: View {
    let period: TVLogbookPeriod
    let ctx: TVLogbookContext

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(period.isDay ? "\(period.title) · \(period.subtitle)" : "\(period.title) \(period.subtitle)")
                        .font(.mono(44, .heavy))
                        .foregroundStyle(Palette.ink)
                    Text("\(RadarFormat.wholeNumber(period.sightings.count)) aircraft\(LogbookGrouping.places(in: period.sightings).map { " · \($0)" } ?? "")")
                        .font(.mono(22))
                        .foregroundStyle(Palette.caption)
                }
                .padding(.bottom, 4)
                if period.isDay && period.sightings.count > 2 {
                    LogbookHourlyChart(counts: Self.hourly(period.sightings), scale: 1.8, height: 50)
                        .padding(.bottom, 10)
                }
                ForEach(period.sightings) { s in
                    Button {
                        ctx.actions.open(TVSightingBrowse(period.sightings, showing: s))
                    } label: {
                        TVSightingRow(sighting: s, isLive: ctx.isLive(s.id))
                    }
                    .buttonStyle(TVRowButtonStyle())
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
        }
        .scrollClipDisabled()
    }

    static func hourly(_ sightings: [Sighting]) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        for s in sightings { counts[Calendar.current.component(.hour, from: s.firstSeen)] += 1 }
        return counts
    }
}

// MARK: - Stats

struct TVLogbookStats: View {
    let ctx: TVLogbookContext

    var body: some View {
        let digest = ctx.logbook.digest
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 34) {
                if ctx.logbook.isEmpty {
                    Text("Charts fill in as aircraft are logged.")
                        .font(.mono(28))
                        .foregroundStyle(Palette.caption)
                        .padding(.top, 80)
                } else {
                    summary(digest)
                    directions(digest)
                    HStack(alignment: .top, spacing: 30) {
                        TVChartCard(title: "Last 30 days") {
                            LogbookActivityChart(points: digest.recentDays(30), scale: 2, height: 110)
                        }
                        TVChartCard(title: "By month") {
                            LogbookActivityChart(points: digest.monthlyCounts().map { (day: $0.month, count: $0.count) }, unit: .month, scale: 2, height: 110)
                        }
                        .frame(width: 560)
                    }
                    HStack(alignment: .top, spacing: 30) {
                        TVChartCard(title: "By hour", detail: digest.busiestHourOfDay.map { "Busiest \(LogbookFormat.hourRange($0))" }) {
                            LogbookHourlyChart(counts: digest.hourly, highlight: digest.busiestHourOfDay, scale: 2, height: 120)
                        }
                        TVChartCard(title: "By weekday") {
                            LogbookWeekdayChart(counts: digest.weekdays, scale: 2, height: 120)
                        }
                        .frame(width: 520)
                    }
                    TVChartCard(title: "How high they pass", detail: "Altitude at the closest pass") {
                        LogbookAltitudeChart(bins: digest.altitudes, scale: 2, height: 160)
                    }
                    records(digest)
                    ForEach([[LogbookRanking.aircraft, .airlines, .types], [.routes, .airports, .countries]], id: \.self) { row in
                        HStack(alignment: .top, spacing: 30) {
                            ForEach(row) { kind in ranking(kind, digest: digest) }
                        }
                        .focusSection()
                    }
                }
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 40)
        }
    }

    /// The big one: a compass rose of where aircraft head over you, the main direction and
    /// the top three, right under the summary.
    @ViewBuilder
    private func directions(_ digest: LogbookDigest) -> some View {
        if digest.headings.contains(where: { $0 > 0 }) {
            TVChartCard(title: "Which way they fly") {
                HStack(alignment: .center, spacing: 80) {
                    LogbookHeadingRose(sectors: digest.headings, size: 460, scale: 2.4)
                    VStack(alignment: .leading, spacing: 28) {
                        if let main = digest.mainHeading {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Int((main.share * 100).rounded()))%")
                                    .font(.mono(110, .heavy))
                                    .foregroundStyle(ChartTone.heading(main.degrees))
                                Text("heading \(LogbookFormat.direction(main.degrees))")
                                    .font(.mono(36, .bold))
                                    .foregroundStyle(Palette.value)
                            }
                        }
                        HStack(spacing: 18) {
                            ForEach(digest.topHeadings(), id: \.sector) { entry in
                                VStack(spacing: 6) {
                                    Text(LogbookFormat.sectorNames[entry.sector])
                                        .font(.mono(40, .heavy))
                                        .foregroundStyle(ChartTone.heading(Double(entry.sector) * 22.5))
                                    Text("\(Int((entry.share * 100).rounded()))%")
                                        .font(.mono(22, .semibold))
                                        .foregroundStyle(Palette.caption)
                                }
                                .frame(width: 170)
                                .padding(.vertical, 18)
                                .background(Palette.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                        Text("Each petal is the share of aircraft on that heading at their closest pass; the red dot is you. A strong lean usually means you're under an approach or departure path.")
                            .font(.mono(22))
                            .foregroundStyle(Palette.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 820, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func summary(_ digest: LogbookDigest) -> some View {
        HStack(spacing: 18) {
            LogbookStatTile(title: "Per day", value: RadarFormat.wholeNumber(Int((Double(digest.stats.total) / Double(max(1, digest.days.count))).rounded())), scale: 1.8, tint: ChartTone.teal.color)
            LogbookStatTile(title: "Best day", value: digest.busiestDay.map { RadarFormat.wholeNumber($0.count) } ?? "—", scale: 1.8, tint: ChartTone.amber.color)
            LogbookStatTile(title: "Best hour", value: digest.busiestHour.map { RadarFormat.wholeNumber($0.count) } ?? "—", scale: 1.8, tint: ChartTone.pink.color)
            LogbookStatTile(title: "Best streak", value: "\(digest.streak.best)d", scale: 1.8, tint: ChartTone.coral.color)
            LogbookStatTile(title: "Countries", value: RadarFormat.wholeNumber(digest.countryCount), scale: 1.8, tint: ChartTone.sky.color)
            LogbookStatTile(title: "Photos", value: RadarFormat.wholeNumber(digest.photoCount), scale: 1.8)
        }
    }

    private func records(_ digest: LogbookDigest) -> some View {
        let records = digest.records
        return VStack(alignment: .leading, spacing: 14) {
            TVSectionHeader(title: "Records")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)], spacing: 16) {
                ForEach(Array(records.enumerated()), id: \.element.id) { i, r in
                    TVValueRow(title: r.title, subtitle: "\(r.sighting.displayIdentifier) · \(r.sighting.typeName ?? r.sighting.typeCode ?? "Aircraft")",
                               value: r.value, symbol: r.symbol, tint: r.tint) {
                        ctx.actions.open(TVSightingBrowse(records.map { .init(sighting: $0.sighting, label: "\($0.title) · \($0.value)") }, start: i))
                    }
                }
            }
        }
        .focusSection()
    }

    private func ranking(_ kind: LogbookRanking, digest: LogbookDigest) -> some View {
        let entries = digest.rankings[kind] ?? []
        return VStack(alignment: .leading, spacing: 14) {
            TVSectionHeader(title: "Most seen \(kind.title.lowercased()) · \(entries.count)")
            if entries.isEmpty {
                Text(kind == .aircraft ? "No repeat visitors yet." : "Nothing yet.")
                    .font(.mono(22))
                    .foregroundStyle(Palette.caption)
            }
            ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { i, entry in
                Button {
                    if kind == .aircraft {
                        ctx.actions.airframe(entry.id)
                    } else {
                        let matches = digest.sightings(matching: kind.filter(for: entry.id), in: ctx.logbook.recent)
                        if let first = matches.first { ctx.actions.open(TVSightingBrowse(matches, showing: first)) }
                    }
                } label: {
                    TVRankRow(rank: i + 1, entry: entry, top: entries[0].count, showsGlyph: kind == .aircraft)
                }
                .buttonStyle(TVRowButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Badges

struct TVLogbookBadges: View {
    let ctx: TVLogbookContext

    var body: some View {
        let digest = ctx.logbook.digest
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(digest.unlockedCount) of \(digest.achievements.count) unlocked")
                        .font(.mono(48, .heavy))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if digest.levelsToGo > 0 {
                        Text("\(digest.levelsToGo) levels to go").font(.mono(24, .semibold)).foregroundStyle(Palette.caption)
                    }
                }
                let next = digest.nextUp(5)
                if !next.isEmpty {
                    TVShelf(title: "Next up") {
                        ForEach(next) { a in
                            Button { ctx.actions.badge(a) } label: { TVBadgeCard(achievement: a) }
                                .buttonStyle(TVCardButtonStyle())
                        }
                    }
                }
                ForEach(Achievement.Group.allCases, id: \.self) { group in
                    let badges = digest.achievements.filter { $0.group == group }
                    TVSectionHeader(title: "\(group.title) · \(badges.filter(\.isUnlocked).count) of \(badges.count)")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: 7), spacing: 28) {
                        ForEach(badges) { a in
                            Button { ctx.actions.badge(a) } label: {
                                AchievementBadge(achievement: a, scale: 1.8)
                                    .frame(maxWidth: .infinity, minHeight: 230)
                            }
                            .buttonStyle(TVCardButtonStyle())
                        }
                    }
                    .focusSection()
                }
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 40)
        }
    }
}

// MARK: - Photos

struct TVLogbookPhotos: View {
    let ctx: TVLogbookContext

    var body: some View {
        let photos = ctx.logbook.allPhotos
        ScrollView {
            if photos.isEmpty {
                Text("No photos yet. Take one in Sky View on your iPhone; with the logbook in iCloud, it shows up here too.")
                    .font(.mono(28))
                    .foregroundStyle(Palette.caption)
                    .padding(.horizontal, 100)
                    .padding(.top, 120)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 34)], spacing: 40) {
                    ForEach(photos) { photo in
                        Button {
                            open(photo, all: photos)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                SpotPhotoThumbnail(photo: photo, store: ctx.logbook.photoStore, size: 300)
                                Text(photo.displayIdentifier).font(.mono(26, .heavy)).foregroundStyle(Palette.ink)
                                Text(photo.takenAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.mono(18))
                                    .foregroundStyle(Palette.caption)
                            }
                            .padding(16)
                        }
                        .buttonStyle(TVCardButtonStyle())
                    }
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 40)
            }
        }
    }

    /// Opens the photo's sighting, paging through every photographed aircraft.
    private func open(_ photo: SpotPhoto, all: [SpotPhoto]) {
        var seen = Set<String>()
        let sightings = all.compactMap { p in seen.insert(p.flightID).inserted ? ctx.logbook.sighting(id: p.flightID) : nil }
        guard let sighting = ctx.logbook.sighting(id: photo.flightID) else { return }
        ctx.actions.open(TVSightingBrowse(sightings, showing: sighting))
    }
}
#endif
