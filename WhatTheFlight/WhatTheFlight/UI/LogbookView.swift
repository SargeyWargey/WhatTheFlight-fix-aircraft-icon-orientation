//
//  LogbookView.swift
//  WhatTheFlight
//
//  The logbook on iPhone and iPad: five tabs (Overview, Sightings, Stats, Badges, Photos).
//  The tab bar sits at the bottom on iPhone and floats along the top on iPad (no sidebar, so
//  the pages get the whole width). Every tab has its own navigation stack; pages push by
//  `LogbookRoute`, so a day, a badge or an aircraft opens the same way from anywhere. All the
//  numbers come from `Logbook.digest`.
//

#if os(iOS)
import SwiftUI

/// What the logbook's pages need from whoever opened it.
struct LogbookContext {
    let logbook: Logbook
    /// Sends a sighting that's still on the radar to the centre.
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }
    /// Switches tab (the Overview's "See all" links).
    var showTab: (LogbookTab) -> Void = { _ in }
}

/// A page inside the logbook.
enum LogbookRoute: Hashable {
    case sighting(String)
    case day(Date)
    case month(Date)
    case filter(LogbookFilter)
    case airframe(String)
    case badge(String)
    case ranking(LogbookRanking)
    case records

    /// A ranked entry's page: an aircraft's history, or the sightings it stands for.
    static func entry(_ kind: LogbookRanking, _ id: String) -> LogbookRoute {
        kind == .aircraft ? .airframe(id) : .filter(kind.filter(for: id))
    }
}

struct LogbookView: View {
    let logbook: Logbook
    var onTrack: ((String) -> Void)?
    var isLive: (String) -> Bool = { _ in false }
    /// Shows a Done button that calls this.
    var onDone: (() -> Void)?

    @State private var tab = LogbookTab.initial

    var body: some View {
        let ctx = LogbookContext(logbook: logbook, onTrack: onTrack, isLive: isLive, showTab: { tab = $0 })
        TabView(selection: $tab) {
            Tab(LogbookTab.overview.title, systemImage: LogbookTab.overview.symbol, value: LogbookTab.overview) {
                stack(.overview, ctx) { LogbookOverview(ctx: ctx) }
            }
            Tab(LogbookTab.sightings.title, systemImage: LogbookTab.sightings.symbol, value: LogbookTab.sightings) {
                stack(.sightings, ctx) { LogbookSightingsTab(ctx: ctx) }
            }
            Tab(LogbookTab.stats.title, systemImage: LogbookTab.stats.symbol, value: LogbookTab.stats) {
                stack(.stats, ctx) { LogbookStatsTab(ctx: ctx) }
            }
            Tab(LogbookTab.badges.title, systemImage: LogbookTab.badges.symbol, value: LogbookTab.badges) {
                stack(.badges, ctx) { LogbookBadgesTab(ctx: ctx) }
            }
            Tab(LogbookTab.photos.title, systemImage: LogbookTab.photos.symbol, value: LogbookTab.photos) {
                stack(.photos, ctx) { SpotPhotoGallery(logbook: logbook) }
            }
        }
        .tabViewStyle(.tabBarOnly)
        .tint(Palette.ink)
    }

    private func stack<Content: View>(_ tab: LogbookTab, _ ctx: LogbookContext, @ViewBuilder _ content: () -> Content) -> some View {
        LogbookTabStack(tab: tab, ctx: ctx) {
            content()
                .toolbar {
                    if let onDone {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done", action: onDone).font(.mono(15, .semibold))
                        }
                    }
                }
        }
    }
}

/// One tab's navigation stack, with every logbook page as a destination.
private struct LogbookTabStack<Content: View>: View {
    let tab: LogbookTab
    let ctx: LogbookContext
    @ViewBuilder var content: Content

    @State private var path: [LogbookRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle(tab == .overview ? "Logbook" : tab.title)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: LogbookRoute.self) { LogbookDestination(route: $0, ctx: ctx) }
        }
        .fontDesign(.monospaced)
        #if DEBUG
        .task { path = Self.debugPath(for: tab, digest: ctx.logbook.digest) }
        #endif
    }

    #if DEBUG
    /// `-wtf.debugBadge <id>` opens a badge's page; `-wtf.debugLogbookPage day|month|records|
    /// mostseen|regular` opens a page on its tab (screenshots).
    static func debugPath(for tab: LogbookTab, digest: LogbookDigest) -> [LogbookRoute] {
        let defaults = UserDefaults.standard
        if tab == .badges, let id = defaults.string(forKey: "wtf.debugBadge") { return [.badge(id)] }
        switch (tab, defaults.string(forKey: "wtf.debugLogbookPage")) {
        case (.sightings, "day"): return digest.days.first.map { [.day($0.day)] } ?? []
        case (.sightings, "month"): return digest.allMonths().first.map { [.month($0.month)] } ?? []
        case (.stats, "records"): return [.records]
        case (.stats, "mostseen"): return [.ranking(.aircraft)]
        case (.stats, "regular"): return [.ranking(.aircraft)] + (digest.rankings[.aircraft]?.first.map { [.airframe($0.id)] } ?? [])
        default: return []
        }
    }
    #endif
}

struct LogbookDestination: View {
    let route: LogbookRoute
    let ctx: LogbookContext

    var body: some View {
        switch route {
        case .sighting(let id):
            if let s = ctx.logbook.sighting(id: id) {
                SightingDetailView(sighting: s, logbook: ctx.logbook, onTrack: ctx.onTrack, isLive: ctx.isLive(id))
            } else {
                ContentUnavailableView("No longer in the logbook", systemImage: "book.closed")
            }
        case .day(let day): LogbookDayView(date: day, ctx: ctx)
        case .month(let month): LogbookMonthView(date: month, ctx: ctx)
        case .filter(let filter): LogbookFilteredView(filter: filter, ctx: ctx)
        case .airframe(let airframe): AirframeHistoryView(airframe: airframe, logbook: ctx.logbook, onTrack: ctx.onTrack, isLive: ctx.isLive)
        case .badge(let id): AchievementPager(achievements: ctx.logbook.digest.achievements, selection: id, logbook: ctx.logbook, onTrack: ctx.onTrack, isLive: ctx.isLive)
        case .ranking(let kind): LogbookMostSeenView(kind: kind, ctx: ctx)
        case .records: LogbookRecordsView(ctx: ctx)
        }
    }
}

// MARK: - Overview

/// The logbook at a glance: today, the headline numbers, the last two weeks, records,
/// the next badges, what you see most and your latest photos. Two columns on iPad.
struct LogbookOverview: View {
    let ctx: LogbookContext

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        let digest = ctx.logbook.digest
        ScrollView {
            if ctx.logbook.isEmpty {
                ContentUnavailableView("No sightings yet", systemImage: "book.closed",
                                       description: Text("Every aircraft that comes inside your radius is logged here automatically, with stats, records and badges."))
                    .padding(.top, 80)
            } else if sizeClass == .regular {
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 22) {
                        LogbookTodayCard(recap: digest.today, digest: digest, ctx: ctx)
                        LogbookActivityCard(digest: digest, ctx: ctx)
                        LogbookRecordsStrip(records: digest.records, columns: 2)
                    }
                    VStack(spacing: 22) {
                        LogbookNumbersGrid(digest: digest)
                        LogbookNextUpCard(digest: digest, ctx: ctx)
                        LogbookMostSeenCard(digest: digest)
                        LogbookPhotosStrip(logbook: ctx.logbook, ctx: ctx)
                    }
                }
                .padding(24)
            } else {
                VStack(spacing: 22) {
                    LogbookTodayCard(recap: digest.today, digest: digest, ctx: ctx)
                    LogbookNumbersGrid(digest: digest)
                    LogbookActivityCard(digest: digest, ctx: ctx)
                    LogbookRecordsStrip(records: digest.records)
                    LogbookNextUpCard(digest: digest, ctx: ctx)
                    LogbookMostSeenCard(digest: digest)
                    LogbookPhotosStrip(logbook: ctx.logbook, ctx: ctx)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(LogbookBackdrop())
    }
}

/// Today so far: four numbers, the highlights (notable aircraft, first-of-type) and new airlines.
struct LogbookTodayCard: View {
    let recap: DailyRecap
    let digest: LogbookDigest
    let ctx: LogbookContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogbookHeader(title: "Today · \(recap.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))") {
                if !recap.isEmpty {
                    NavigationLink(value: LogbookRoute.day(recap.day)) { Text("See today ›") }
                }
            }
            if recap.isEmpty {
                Text("Nothing logged yet today.")
                    .monoScaled(14, .semibold)
                    .foregroundStyle(Palette.value)
                if let last = digest.days.first?.sightings.first {
                    NavigationLink(value: LogbookRoute.sighting(last.id)) {
                        Text("Last: \(last.displayIdentifier) · \(LogbookGrouping.shortTitle(for: last.firstSeen)) \(last.firstSeen.formatted(date: .omitted, time: .shortened)) ›")
                            .monoScaled(12)
                            .foregroundStyle(Palette.ink)
                    }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    LogbookChip(value: RadarFormat.wholeNumber(recap.total), label: "Spotted")
                    LogbookChip(value: "\(recap.notable.count)", label: "Notable", tint: Palette.notable)
                    LogbookChip(value: "\(recap.newTypes.count)", label: recap.newTypes.count == 1 ? "New type" : "New types", tint: ChartTone.teal.color)
                    LogbookChip(value: recap.closest?.closestPreciseText ?? "—", label: "Closest", tint: ChartTone.coral.color)
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

                let highlights = Self.highlights(recap)
                ForEach(highlights.prefix(3), id: \.sighting.id) { item in
                    NavigationLink(value: LogbookRoute.sighting(item.sighting.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            SightingRowLabel(sighting: item.sighting, isLive: ctx.isLive(item.sighting.id))
                            Text(item.reason)
                                .monoScaled(10, .semibold)
                                .foregroundStyle(item.color)
                                .padding(.leading, 42)
                        }
                    }
                    .buttonStyle(.plain)
                }
                let extra = highlights.count - min(3, highlights.count)
                if extra > 0 || !recap.newAirlines.isEmpty {
                    Divider()
                    Text([extra > 0 ? "+ \(extra) more highlight\(extra == 1 ? "" : "s")" : nil,
                          recap.newAirlines.isEmpty ? nil : "New airline\(recap.newAirlines.count == 1 ? "" : "s"): \(recap.newAirlines.joined(separator: ", "))"]
                        .compactMap { $0 }.joined(separator: " · "))
                        .monoScaled(11)
                        .foregroundStyle(Palette.caption)
                }
            }
        }
        .logbookCard()
    }

    /// Notable aircraft first, then the first of each new type.
    static func highlights(_ recap: DailyRecap) -> [(sighting: Sighting, reason: String, color: Color)] {
        let notable = recap.notable.map { s in (s, s.notableReason ?? "Notable", s.tags.first.map(Palette.color(for:)) ?? Palette.notable) }
        let types = recap.newTypes.filter { s in !recap.notable.contains { $0.id == s.id } }
            .map { s in (s, "First \(s.typeName ?? s.typeCode ?? "of its type") in your logbook", Palette.ink) }
        return notable + types
    }
}

/// A number over a small caption, on paper.
struct LogbookChip: View {
    let value: String
    let label: String
    var tint: Color = Palette.ink

    var body: some View {
        VStack(spacing: 2) {
            Text(value).monoScaled(16, .bold).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).monoScaled(9, .semibold).textCase(.uppercase).foregroundStyle(Palette.caption)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct LogbookNumbersGrid: View {
    let digest: LogbookDigest

    var body: some View {
        let stats = digest.stats
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            // One hue each, cool along the top row and warm along the bottom.
            LogbookStatTile(title: "Spotted", value: RadarFormat.wholeNumber(stats.total))
            LogbookStatTile(title: "Airframes", value: RadarFormat.wholeNumber(stats.uniqueAirframes), tint: ChartTone.sky.color)
            LogbookStatTile(title: "Types", value: RadarFormat.wholeNumber(stats.uniqueTypes), tint: ChartTone.teal.color)
            LogbookStatTile(title: "Airlines", value: RadarFormat.wholeNumber(stats.uniqueAirlines), tint: ChartTone.pink.color)
            LogbookStatTile(title: "Countries", value: RadarFormat.wholeNumber(digest.countryCount), tint: ChartTone.amber.color)
            LogbookStatTile(title: "Streak", value: digest.streak.current == 1 ? "1 day" : "\(digest.streak.current) days", symbol: "flame.fill", tint: ChartTone.coral.color)
        }
        // Three tiles a row: past this the numbers no longer fit.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// Aircraft per day for the last two weeks, plus the streak and the best day.
struct LogbookActivityCard: View {
    let digest: LogbookDigest
    let ctx: LogbookContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogbookHeader(title: "Last 14 days") {
                Button("Stats ›") { ctx.showTab(.stats) }
            }
            LogbookActivityChart(points: digest.recentDays(14))
            HStack(spacing: 14) {
                Label("\(digest.streak.current)-day streak · best \(digest.streak.best)", systemImage: "flame.fill")
                    .foregroundStyle(digest.streak.current > 0 ? Palette.signal : Palette.caption)
                if let best = digest.busiestDay {
                    NavigationLink(value: LogbookRoute.day(best.day)) {
                        Text("Best \(best.day.formatted(.dateTime.month(.abbreviated).day())) · \(best.count) ›")
                            .foregroundStyle(Palette.ink)
                    }
                }
            }
            .monoScaled(11, .semibold)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .logbookCard()
    }
}

/// The records as cards, side by side (a scrolling strip, or a grid on iPad).
struct LogbookRecordsStrip: View {
    let records: [LogbookRecord]
    var columns = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LogbookHeader(title: "Records") {
                NavigationLink(value: LogbookRoute.records) { Text("All ›") }
            }
            if columns > 0 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 10) {
                    ForEach(records) { card($0) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(records) { card($0).frame(width: 196) }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private func card(_ r: LogbookRecord) -> some View {
        NavigationLink(value: LogbookRoute.sighting(r.sighting.id)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.title).monoScaled(10, .semibold).tracking(1.2).textCase(.uppercase).foregroundStyle(Palette.caption)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Image(systemName: r.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(r.tint)
                }
                Text(r.value).monoScaled(22, .heavy).foregroundStyle(r.tint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(r.sighting.displayIdentifier) · \(r.sighting.typeName ?? r.sighting.typeCode ?? "Aircraft")")
                    .monoScaled(11).foregroundStyle(Palette.value).lineLimit(1)
            }
            .logbookCard()
        }
        .buttonStyle(.plain)
    }
}

/// The badges closest to unlocking (or the next level), with progress bars.
struct LogbookNextUpCard: View {
    let digest: LogbookDigest
    let ctx: LogbookContext

    var body: some View {
        let next = digest.nextUp()
        VStack(alignment: .leading, spacing: 10) {
            LogbookHeader(title: next.isEmpty ? "Badges" : "Badges · next up") {
                Button("\(digest.unlockedCount) of \(digest.achievements.count) ›") { ctx.showTab(.badges) }
            }
            VStack(spacing: 0) {
                ForEach(Array((next.isEmpty ? digest.recentlyUnlocked() : next).enumerated()), id: \.element.id) { i, a in
                    if i > 0 { Divider() }
                    NavigationLink(value: LogbookRoute.badge(a.id)) {
                        NextUpRow(achievement: a)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// A badge's ring, its name and a bar toward the next level.
struct NextUpRow: View {
    let achievement: Achievement

    var body: some View {
        let a = achievement
        HStack(spacing: 12) {
            AchievementBadge(achievement: a, scale: 0.74, showsTitle: false)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(a.title).monoScaled(13, .bold).foregroundStyle(Palette.value)
                    if a.hasLevels {
                        TierDots(earned: a.level, total: a.tiers.count)
                    }
                    Spacer()
                    Text(a.progressLabel ?? "\(RadarFormat.wholeNumber(min(a.progress, a.target))) / \(RadarFormat.wholeNumber(a.target))")
                        .monoScaled(12, .bold).foregroundStyle(a.isMaxed ? Palette.notable : Palette.ink)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.ink.opacity(0.12))
                        Capsule().fill(a.isMaxed ? Palette.notable : Palette.route)
                            .frame(width: max(5, geo.size.width * a.fraction))
                    }
                }
                .frame(height: 6)
                Text(a.detail).monoScaled(10).foregroundStyle(Palette.caption).lineLimit(1)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AchievementBadge.accessibilityText(a))
    }
}

/// The top three aircraft, airlines or types, and a link to the full lists.
struct LogbookMostSeenCard: View {
    let digest: LogbookDigest

    @State private var kind: LogbookRanking = .aircraft

    var body: some View {
        let entries = digest.rankings[kind] ?? []
        VStack(alignment: .leading, spacing: 10) {
            LogbookHeader(title: "Most seen") {
                NavigationLink(value: LogbookRoute.ranking(kind)) { Text("All ›") }
            }
            Picker("Most seen", selection: $kind) {
                ForEach([LogbookRanking.aircraft, .airlines, .types]) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            VStack(spacing: 0) {
                if entries.isEmpty {
                    Text(kind == .aircraft ? "No repeat visitors yet. Aircraft you see more than once show up here." : "Nothing yet.")
                        .monoScaled(12)
                        .foregroundStyle(Palette.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                }
                ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { i, entry in
                    if i > 0 { Divider() }
                    NavigationLink(value: LogbookRoute.entry(kind, entry.id)) {
                        LogbookRankRow(rank: i + 1, entry: entry, top: entries[0].count, showsGlyph: kind == .aircraft)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

/// The latest Sky View photos.
struct LogbookPhotosStrip: View {
    let logbook: Logbook
    let ctx: LogbookContext

    var body: some View {
        let photos = logbook.allPhotos
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                LogbookHeader(title: "Your photos · \(photos.count)") {
                    Button("All ›") { ctx.showTab(.photos) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos.prefix(8)) { photo in
                            NavigationLink(value: LogbookRoute.sighting(photo.flightID)) {
                                SpotPhotoThumbnail(photo: photo, store: logbook.photoStore, size: 72)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}
#endif
