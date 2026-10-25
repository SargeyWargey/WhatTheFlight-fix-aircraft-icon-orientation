//
//  LogbookStatsTab.swift
//  WhatTheFlight
//
//  The numbers behind the logbook on iPhone and iPad, in two halves. "Your sky" is one spot
//  you watch from (where you are once its charts are ready, else home; a menu picks another,
//  or all places): which way aircraft fly over it, when it's busiest (hour and weekday) and
//  how high they pass, each shown once `LogbookSky.minimum` aircraft back it up.
//  "Everywhere" counts every sighting: activity by day and month, records, what you see most
//  (aircraft, airlines, types, routes, airports, countries), where you watch from and which
//  devices log. Two columns on iPad.
//

#if os(iOS)
import SwiftUI
import CoreLocation

struct LogbookStatsTab: View {
    let ctx: LogbookContext

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.radarObserver) private var observer
    /// Whose sky the charts show; nil until one's picked (then where you are, or home).
    @State private var scope: LogbookSkyScope?

    var body: some View {
        let digest = ctx.logbook.digest
        let choice = digest.sky(scope ?? LogbookSkyScope.initial(in: digest), near: observer)
        ScrollView {
            if ctx.logbook.isEmpty {
                ContentUnavailableView("No stats yet", systemImage: "chart.bar.xaxis",
                                       description: Text("Charts fill in as aircraft are logged: when your sky is busiest, which way they fly, how high they pass."))
                    .padding(.top, 80)
            } else if sizeClass == .regular {
                VStack(spacing: 22) {
                    StatsSkyHeader(digest: digest, choice: choice, here: digest.spot(near: observer), scope: $scope)
                    if choice.sky.isFillingIn {
                        StatsSkyFillingCard(choice: choice)
                    } else {
                        StatsDirectionsCard(sky: choice.sky, wide: true)
                        HStack(alignment: .top, spacing: 20) {
                            StatsWhenCard(sky: choice.sky)
                            StatsAltitudeCard(sky: choice.sky)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    StatsEverywhereHeader(digest: digest)
                        .padding(.top, 14)
                    StatsSummaryRow(digest: digest)
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 22) {
                            StatsActivityCard(digest: digest)
                            StatsRecordsCard(digest: digest)
                        }
                        VStack(spacing: 22) {
                            StatsMostSeenCard(digest: digest)
                            StatsPlacesCard(digest: digest)
                        }
                    }
                }
                .padding(24)
            } else {
                VStack(spacing: 22) {
                    StatsSkyHeader(digest: digest, choice: choice, here: digest.spot(near: observer), scope: $scope)
                    if choice.sky.isFillingIn {
                        StatsSkyFillingCard(choice: choice)
                    } else {
                        StatsDirectionsCard(sky: choice.sky)
                        StatsWhenCard(sky: choice.sky)
                        StatsAltitudeCard(sky: choice.sky)
                    }
                    StatsEverywhereHeader(digest: digest)
                        .padding(.top, 14)
                    StatsSummaryRow(digest: digest)
                    StatsActivityCard(digest: digest)
                    StatsRecordsCard(digest: digest)
                    StatsMostSeenCard(digest: digest)
                    StatsPlacesCard(digest: digest)
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity)
        .background(LogbookBackdrop())
    }
}

/// "Your sky · Atlanta, GA": whose sky the charts below describe, with a menu of every spot
/// you've watched from (and all of them together) once there's more than one.
private struct StatsSkyHeader: View {
    let digest: LogbookDigest
    let choice: LogbookSkyChoice
    /// The spot you're at now.
    let here: LogbookSpot?
    @Binding var scope: LogbookSkyScope?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LogbookHeader("Your sky")
            if digest.spots.count > 1 {
                Menu {
                    Picker("Place", selection: Binding(get: { choice.scope }, set: { scope = $0 })) {
                        ForEach(digest.spots) { spot in
                            Label(spot.name, systemImage: spot.id == here?.id ? "location.fill" : "mappin")
                                .tag(LogbookSkyScope.spot(spot.id))
                        }
                        Label("All places", systemImage: "globe.americas")
                            .tag(LogbookSkyScope.everywhere)
                    }
                } label: {
                    HStack(spacing: 6) {
                        title
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .accessibilityLabel("Your sky: \(choice.title)")
                .accessibilityHint("Choose another place")
            } else {
                title
            }
            Text(choice.detail(here: here, places: digest.spots.count))
                .monoScaled(11)
                .foregroundStyle(Palette.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: some View {
        Text(choice.title)
            .monoScaled(22, .heavy)
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Heads the half of the tab that counts every sighting, wherever it was.
private struct StatsEverywhereHeader: View {
    let digest: LogbookDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LogbookHeader("Everywhere")
            Text("Your collection")
                .monoScaled(22, .heavy)
                .foregroundStyle(Palette.ink)
            Text(digest.spots.count > 1
                 ? "\(RadarFormat.wholeNumber(digest.stats.total)) aircraft from \(digest.spots.count) places"
                 : "\(RadarFormat.wholeNumber(digest.stats.total)) aircraft")
                .monoScaled(11)
                .foregroundStyle(Palette.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A spot with too few aircraft for any chart yet: how far along it is.
private struct StatsSkyFillingCard: View {
    let choice: LogbookSkyChoice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogbookHeader("Filling in")
            LogbookSkyProgress(count: choice.sky.count)
            Text("Which way they fly, when the sky is busiest and how high they pass appear once \(LogbookSky.minimum) aircraft are logged\(choice.spot == nil ? "" : " around \(choice.title)"): enough to show this sky's pattern, not just one afternoon.")
                .monoScaled(11)
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .logbookCard()
    }
}

/// Average per day, best day, busiest hour and best streak.
private struct StatsSummaryRow: View {
    let digest: LogbookDigest

    var body: some View {
        let days = max(1, digest.days.count)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            LogbookStatTile(title: "Per day", value: RadarFormat.wholeNumber(Int((Double(digest.stats.total) / Double(days)).rounded())), symbol: "calendar", tint: ChartTone.teal.color)
            LogbookStatTile(title: "Best day", value: digest.busiestDay.map { RadarFormat.wholeNumber($0.count) } ?? "—", symbol: "trophy.fill", tint: ChartTone.amber.color)
            LogbookStatTile(title: "Best hour", value: digest.busiestHour.map { RadarFormat.wholeNumber($0.count) } ?? "—", symbol: "clock.fill", tint: ChartTone.pink.color)
            LogbookStatTile(title: "Best streak", value: "\(digest.streak.best) day\(digest.streak.best == 1 ? "" : "s")", symbol: "flame.fill", tint: ChartTone.coral.color)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Aircraft per day for the last 30 days, or per month since the start.
private struct StatsActivityCard: View {
    let digest: LogbookDigest

    @State private var byMonth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogbookHeader(byMonth ? "Activity · by month" : "Activity · last 30 days")
            Picker("Range", selection: $byMonth) {
                Text("30 days").tag(false)
                Text("By month").tag(true)
            }
            .pickerStyle(.segmented)
            if byMonth {
                LogbookActivityChart(points: digest.monthlyCounts().map { (day: $0.month, count: $0.count) }, unit: .month, height: 150)
            } else {
                LogbookActivityChart(points: digest.recentDays(30), height: 150)
            }
            Text("Touch a bar to read it. \(digest.streak.current > 0 ? "Current streak: \(digest.streak.current) day\(digest.streak.current == 1 ? "" : "s")." : "")")
                .monoScaled(10)
                .foregroundStyle(Palette.caption)
        }
        .logbookCard()
    }
}

/// When your sky is busiest: by hour of the day and by weekday.
private struct StatsWhenCard: View {
    let sky: LogbookSky

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogbookHeader(title: "When your sky is busiest") {
                if sky.showsTimes, let hour = sky.busiestHourOfDay {
                    Text(LogbookFormat.hourRange(hour)).foregroundStyle(Palette.value)
                }
            }
            if sky.showsTimes {
                LogbookHourlyChart(counts: sky.hourly, highlight: sky.busiestHourOfDay, height: 120)
                Divider()
                HStack {
                    Text("By day of the week").monoScaled(11, .semibold).foregroundStyle(Palette.caption)
                    Spacer()
                    if let i = sky.busiestWeekday {
                        Text("Busiest on \(Calendar.current.weekdaySymbols[i])s").monoScaled(11, .bold).foregroundStyle(Palette.value)
                    }
                }
                LogbookWeekdayChart(counts: sky.weekdays, height: 100)
            } else {
                StatsChartPending(count: sky.count)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .logbookCard()
    }
}

/// A chart that needs more aircraft (old sightings can lack a heading or an altitude, so one
/// chart can be ready before another).
private struct StatsChartPending: View {
    let count: Int
    var noun = "aircraft"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LogbookSkyProgress(count: count, noun: noun)
            Text("Appears at \(LogbookSky.minimum), enough to show a pattern.")
                .monoScaled(10)
                .foregroundStyle(Palette.caption)
        }
    }
}

/// Which way aircraft fly over you: a big compass rose of their headings at the closest
/// pass, the main direction and the top three. Leads the Stats tab.
private struct StatsDirectionsCard: View {
    let sky: LogbookSky
    /// Rose and numbers side by side (iPad).
    var wide = false

    var body: some View {
        if !sky.showsHeadings {
            VStack(alignment: .leading, spacing: 12) {
                LogbookHeader("Which way they fly")
                StatsChartPending(count: sky.headed, noun: "with a heading")
            }
            .logbookCard()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                LogbookHeader("Which way they fly")
                let layout = wide ? AnyLayout(HStackLayout(alignment: .center, spacing: 36)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                layout {
                    LogbookHeadingRose(sectors: sky.headings, size: wide ? 320 : 290, scale: 1.35)
                        .frame(maxWidth: wide ? nil : .infinity)
                    VStack(alignment: .leading, spacing: 14) {
                        if let main = sky.mainHeading {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(Int((main.share * 100).rounded()))%")
                                    .monoScaled(44, .heavy)
                                    .foregroundStyle(ChartTone.heading(main.degrees))
                                Text("heading \(LogbookFormat.direction(main.degrees))")
                                    .monoScaled(16, .bold)
                                    .foregroundStyle(Palette.value)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(sky.topHeadings(), id: \.sector) { entry in
                                VStack(spacing: 2) {
                                    Text(LogbookFormat.sectorNames[entry.sector])
                                        .monoScaled(18, .heavy)
                                        .foregroundStyle(ChartTone.heading(Double(entry.sector) * 22.5))
                                    Text("\(Int((entry.share * 100).rounded()))%")
                                        .monoScaled(11, .semibold)
                                        .foregroundStyle(Palette.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Palette.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .accessibilityElement(children: .combine)
                            }
                        }
                        Text("Each petal is the share of aircraft on that heading at their closest pass; the red dot is you. A strong lean usually means you're under an approach or departure path.")
                            .monoScaled(11)
                            .foregroundStyle(Palette.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .logbookCard(padding: 18)
        }
    }
}

/// How high aircraft were at their closest pass.
private struct StatsAltitudeCard: View {
    let sky: LogbookSky

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LogbookHeader("How high they pass")
            if sky.showsAltitudes {
                LogbookAltitudeChart(bins: sky.altitudes, height: 190)
                Text("Altitude at the closest pass, in feet.")
                    .monoScaled(10)
                    .foregroundStyle(Palette.caption)
            } else {
                StatsChartPending(count: sky.withAltitude, noun: "in the air")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .logbookCard()
    }
}

/// Every record, plus the busiest day, hour and best streak.
private struct StatsRecordsCard: View {
    let digest: LogbookDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LogbookHeader(title: "Records") {
                NavigationLink(value: LogbookRoute.records) { Text("All ›") }
            }
            VStack(spacing: 0) {
                ForEach(Array(digest.records.prefix(4).enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Divider() }
                    NavigationLink(value: LogbookRoute.sighting(r.sighting.id)) {
                        LogbookRecordRow(record: r)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct LogbookRecordRow: View {
    let record: LogbookRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(record.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).radarCaption(scales: true)
                Text("\(record.sighting.displayIdentifier) · \(record.sighting.typeName ?? record.sighting.typeCode ?? "Aircraft")")
                    .monoScaled(13, .semibold)
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(record.value)
                .monoScaled(16, .heavy)
                .foregroundStyle(record.tint)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The top five of any ranking, with a link to the full list.
private struct StatsMostSeenCard: View {
    let digest: LogbookDigest

    @State private var kind: LogbookRanking = .airlines

    var body: some View {
        let entries = digest.rankings[kind] ?? []
        VStack(alignment: .leading, spacing: 10) {
            LogbookHeader(title: "Most seen") {
                NavigationLink(value: LogbookRoute.ranking(kind)) { Text("All \(entries.count) ›") }
            }
            LogbookRankingPicker(selection: $kind)
            VStack(spacing: 0) {
                if entries.isEmpty {
                    Text("Nothing yet.").monoScaled(12).foregroundStyle(Palette.caption)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                }
                ForEach(Array(entries.prefix(5).enumerated()), id: \.element.id) { i, entry in
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

/// Where you watched from, and which devices did the logging.
private struct StatsPlacesCard: View {
    let digest: LogbookDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !digest.places.isEmpty {
                LogbookHeader("Watched from")
                VStack(spacing: 0) {
                    ForEach(Array(digest.places.prefix(5).enumerated()), id: \.element.id) { i, place in
                        if i > 0 { Divider() }
                        NavigationLink(value: LogbookRoute.filter(.place(place.id))) {
                            LogbookRankRow(rank: i + 1, entry: place, top: digest.places[0].count)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !digest.devices.isEmpty {
                LogbookHeader("Logged on")
                    .padding(.top, 8)
                HStack(spacing: 8) {
                    ForEach(digest.devices, id: \.device) { entry in
                        VStack(spacing: 6) {
                            Image(systemName: entry.device.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Palette.route)
                            Text(RadarFormat.wholeNumber(entry.count)).monoScaled(16, .heavy).foregroundStyle(Palette.ink)
                            Text(entry.device.title).monoScaled(9, .semibold).textCase(.uppercase).foregroundStyle(Palette.caption)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

/// Aircraft · Airlines · Types · Routes · Airports · Countries, as chips.
struct LogbookRankingPicker: View {
    @Binding var selection: LogbookRanking

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LogbookRanking.allCases) { kind in
                    Button {
                        selection = kind
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                            .labelStyle(.titleAndIcon)
                            .monoScaled(12, .bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(selection == kind ? Color.white : Palette.value)
                            .background(selection == kind ? Palette.ink : Palette.paperShade.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == kind ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }
}

// MARK: - Full lists

/// Every entry of a ranking, most seen first.
struct LogbookMostSeenView: View {
    let ctx: LogbookContext
    @State private var kind: LogbookRanking

    init(kind: LogbookRanking, ctx: LogbookContext) {
        self.ctx = ctx
        _kind = State(initialValue: kind)
    }

    var body: some View {
        let entries = ctx.logbook.digest.rankings[kind] ?? []
        List {
            Section {
                LogbookRankingPicker(selection: $kind)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            Section {
                if entries.isEmpty {
                    Text(kind == .aircraft ? "No repeat visitors yet. Any aircraft you see more than once is listed here." : "Nothing yet.")
                        .monoScaled(12)
                        .foregroundStyle(Palette.caption)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                    NavigationLink(value: LogbookRoute.entry(kind, entry.id)) {
                        LogbookRankRow(rank: i + 1, entry: entry, top: entries[0].count, showsGlyph: kind == .aircraft)
                            .padding(.vertical, 4)
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
            } header: {
                Text(Self.caption(kind, count: entries.count))
            }
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .navigationTitle("Most Seen")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    static func caption(_ kind: LogbookRanking, count: Int) -> String {
        switch kind {
        case .aircraft: return "Seen more than once · \(count)"
        case .airports: return "Origins and destinations · \(count)"
        case .countries: return "By registration · \(count)"
        default: return "\(kind.title) · \(count)"
        }
    }
}

/// Every record, then the busiest day and hour and the best streak.
struct LogbookRecordsView: View {
    let ctx: LogbookContext

    var body: some View {
        let digest = ctx.logbook.digest
        List {
            Section("Aircraft") {
                ForEach(digest.records) { r in
                    NavigationLink(value: LogbookRoute.sighting(r.sighting.id)) {
                        LogbookRecordRow(record: r)
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
            }
            Section("Days and hours") {
                if let best = digest.busiestDay {
                    NavigationLink(value: LogbookRoute.day(best.day)) {
                        row("calendar", "Busiest day", best.day.formatted(date: .abbreviated, time: .omitted), "\(RadarFormat.wholeNumber(best.count)) aircraft")
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
                if let peak = digest.busiestHour {
                    NavigationLink(value: LogbookRoute.day(peak.start)) {
                        row("clock.fill", "Busiest hour", peak.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()), "\(peak.count) aircraft")
                    }
                    .listRowBackground(Palette.paperShade.opacity(0.25))
                }
                row("flame.fill", "Longest streak", "Days in a row with a sighting", "\(digest.streak.best) days")
                    .listRowBackground(Palette.paperShade.opacity(0.25))
            }
        }
        .scrollContentBackground(.hidden)
        .background(LogbookBackdrop())
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
    }

    private func row(_ symbol: String, _ title: String, _ detail: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Palette.route)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).radarCaption(scales: true)
                Text(detail).monoScaled(13, .semibold).foregroundStyle(Palette.value).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(value).monoScaled(16, .heavy).foregroundStyle(Palette.ink).fixedSize()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
#endif
