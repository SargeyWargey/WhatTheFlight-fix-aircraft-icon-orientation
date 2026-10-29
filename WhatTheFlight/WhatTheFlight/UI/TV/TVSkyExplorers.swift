//
//  TVSkyExplorers.swift
//  WhatTheFlight
//
//  The logbook's bar charts and compass rose full screen on the Apple TV, opened with a click
//  on their card (`TVExplorableCard`). Which way they fly, by hour, by weekday and how high
//  they pass (`TVSkySliceExplorer`): the arrows pick a petal or bar and the panel beside it
//  says what it's made of, its share, rank, airlines, types and routes. Aircraft per day or
//  month (`TVActivityExplorer`): the arrows step through the bars and the panel says what that
//  day was like. Either way a click lists the aircraft (`TVSightingListView`), and a click on
//  one opens its page.
//

#if os(tvOS)
import SwiftUI

// MARK: - Sky charts

/// One of a sky's charts full screen, opened on `start` (usually its busiest bar).
struct TVSkySliceExplorer: View {
    let start: LogbookSkySlice
    let choice: LogbookSkyChoice
    let ctx: TVLogbookContext

    @State private var slice: LogbookSkySlice
    @State private var list: TVSliceList?

    init(start: LogbookSkySlice, choice: LogbookSkyChoice, ctx: TVLogbookContext) {
        self.start = start
        self.choice = choice
        self.ctx = ctx
        _slice = State(initialValue: start)
    }

    var body: some View {
        let sky = choice.sky
        let summary = ctx.logbook.digest.summary(of: slice, spot: choice.spot?.id, from: ctx.logbook.recent)
        TVChartExplorer(title: LocalizedStringKey(slice.chartTitle),
                        detail: "\(choice.title) · \(RadarFormat.wholeNumber(summary.total)) aircraft",
                        hint: hint, move: move, select: { open(summary) },
                        spoken: { "\(summary.slice.title): \(summary.percent)%, \(summary.count) aircraft, \(summary.rankText)" }) {
            HStack(alignment: .center, spacing: 70) {
                chart(sky)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 28) {
                    LogbookSliceOverview(summary: summary, scale: 2)
                    if case .heading = slice {
                        Text("Each petal is the share of aircraft on that heading at their closest pass; the red dot is you. A strong lean usually means you're under an approach or departure path.")
                            .font(.mono(20))
                            .foregroundStyle(Palette.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if summary.count > 0 {
                        Text(summary.count == 1 ? "Click to see the aircraft" : "Click to see the \(RadarFormat.wholeNumber(summary.count)) aircraft")
                            .font(.mono(22, .bold))
                            .foregroundStyle(Palette.ink)
                    }
                }
                .frame(width: 720, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy(duration: 0.18), value: slice)
        }
        .fullScreenCover(item: $list) { list in
            TVSightingListView(caption: "\(list.summary.slice.chartTitle) · \(choice.title)", sightings: list.summary.sightings,
                               logbook: ctx.logbook, showPhotos: ctx.showPhotos) {
                LogbookSliceOverview(summary: list.summary, scale: 2)
            }
        }
    }

    @ViewBuilder
    private func chart(_ sky: LogbookSky) -> some View {
        switch slice {
        case .heading(let i):
            LogbookHeadingRose(sectors: sky.headings, size: 620, scale: 2.8, picked: i)
        case .hour(let h):
            LogbookHourlyChart(counts: sky.hourly, highlight: sky.busiestHourOfDay, scale: 2, height: 200, picked: h)
        case .weekday(let d):
            LogbookWeekdayChart(counts: sky.weekdays, scale: 2, height: 200, picked: d)
        case .altitude(let b):
            LogbookAltitudeChart(bins: sky.altitudes, scale: 2, height: 270, picked: b)
        }
    }

    private var hint: LocalizedStringKey {
        switch slice {
        case .heading: return "◀ ▶ go round the directions · Click to see the aircraft · Back to return to Stats"
        case .hour: return "◀ ▶ step through the hours · Click to see the aircraft · Back to return to Stats"
        case .weekday: return "◀ ▶ step through the days · Click to see the aircraft · Back to return to Stats"
        case .altitude: return "▲ ▼ step through the altitudes · Click to see the aircraft · Back to return to Stats"
        }
    }

    /// Only to bars with aircraft: petals round the rose, hours round the clock, days round the
    /// week; altitudes up and down the bands.
    private func move(_ direction: ChartDirection) {
        let sky = choice.sky
        let next: Int?
        switch slice {
        case .heading(let i):
            guard direction == .left || direction == .right else { return }
            next = LogbookHeadingRose.step(from: i, by: direction == .right ? 1 : -1, in: sky.headings)
        case .hour(let h):
            guard direction == .left || direction == .right else { return }
            next = Self.next(from: h, by: direction == .right ? 1 : -1, in: sky.hourly, order: Array(0..<24), wraps: true)
        case .weekday(let d):
            guard direction == .left || direction == .right else { return }
            next = Self.next(from: d, by: direction == .right ? 1 : -1, in: sky.weekdays, order: LogbookWeekdayChart.order(), wraps: true)
        case .altitude(let b):
            next = Self.next(from: b, by: direction == .up || direction == .right ? 1 : -1, in: sky.altitudes,
                             order: Array(sky.altitudes.indices), wraps: false)
        }
        if let next { slice = slice.with(index: next) }
    }

    /// The next bar along `order` (left to right, or low to high) that has aircraft.
    private static func next(from bar: Int, by delta: Int, in counts: [Int], order: [Int], wraps: Bool) -> Int? {
        guard let at = order.firstIndex(of: bar) else { return nil }
        for k in 1..<max(2, order.count) {
            var p = at + delta * k
            if wraps {
                p = (p % order.count + order.count) % order.count
            } else if !order.indices.contains(p) {
                return nil
            }
            if counts.indices.contains(order[p]), counts[order[p]] > 0 { return order[p] }
        }
        return nil
    }

    private func open(_ summary: LogbookSliceSummary) {
        guard summary.count > 0 else { return }
        list = TVSliceList(summary: summary)
    }
}

private struct TVSliceList: Identifiable {
    let id = UUID()
    let summary: LogbookSliceSummary
}

// MARK: - Activity

/// Aircraft per day (or per month) full screen, opened on the latest with aircraft.
struct TVActivityExplorer: View {
    let title: LocalizedStringKey
    /// Oldest first, as the chart draws them.
    let points: [(day: Date, count: Int)]
    var unit: Calendar.Component = .day
    let ctx: TVLogbookContext
    /// The hint's "Back to return to …".
    var page: String = "Stats"

    @State private var index: Int
    @State private var list: TVPeriodList?

    init(title: LocalizedStringKey, points: [(day: Date, count: Int)], unit: Calendar.Component = .day,
         ctx: TVLogbookContext, page: String = "Stats") {
        self.title = title
        self.points = points
        self.unit = unit
        self.ctx = ctx
        self.page = page
        // The latest day (or month) with aircraft: early in the morning today is often empty.
        _index = State(initialValue: points.lastIndex { $0.count > 0 } ?? max(0, points.count - 1))
    }

    var body: some View {
        let point = points.indices.contains(index) ? points[index] : nil
        let period = point.map { period(for: $0.day) }
        let total = points.reduce(0) { $0 + $1.count }
        TVChartExplorer(title: title, detail: "\(RadarFormat.wholeNumber(total)) aircraft",
                        hint: "◀ ▶ step through the \(unit == .month ? "months" : "days") · Click to see the aircraft · Back to return to \(page)",
                        move: move, select: open,
                        spoken: { period.map { "\($0.title): \($0.sightings.count) aircraft" } ?? "" }) {
            HStack(alignment: .center, spacing: 70) {
                LogbookActivityChart(points: points, unit: unit, scale: 2, height: 200, picked: point?.day)
                    .frame(maxWidth: .infinity)
                if let period {
                    TVPeriodPanel(period: period, average: points.isEmpty ? 0 : Double(total) / Double(points.count), unit: unit)
                        .frame(width: 640, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fullScreenCover(item: $list) { list in
            TVSightingListView(caption: list.period.caption, sightings: list.period.sightings,
                               logbook: ctx.logbook, showPhotos: ctx.showPhotos) {
                TVPeriodPanel(period: list.period, average: list.average, unit: unit)
            }
        }
    }

    /// A day, or a month of days, newest first.
    private func period(for date: Date) -> TVPeriod {
        let digest = ctx.logbook.digest
        if unit == .month {
            let month = digest.month(date)
            return TVPeriod(title: LogbookGrouping.monthTitle(date), caption: String(localized: "By month"),
                            sightings: month?.days.flatMap(\.sightings) ?? [], days: month?.days ?? [],
                            notable: month?.notable ?? 0, newTypes: month?.newTypes ?? 0, photos: month?.photos ?? 0,
                            places: month?.places ?? [])
        }
        let day = digest.day(date)
        return TVPeriod(title: LogbookGrouping.title(for: date), caption: String(localized: "Activity"),
                        sightings: day?.sightings ?? [], days: day.map { [$0] } ?? [],
                        notable: day?.notable ?? 0, newTypes: day?.newTypes ?? 0, photos: day?.photos ?? 0,
                        places: day?.places ?? [])
    }

    private func move(_ direction: ChartDirection) {
        let next = index + (direction == .right ? 1 : direction == .left ? -1 : 0)
        if next != index, points.indices.contains(next) { index = next }
    }

    private func open() {
        guard let point = points.indices.contains(index) ? points[index] : nil else { return }
        let period = period(for: point.day)
        guard !period.sightings.isEmpty else { return }
        let total = points.reduce(0) { $0 + $1.count }
        list = TVPeriodList(period: period, average: points.isEmpty ? 0 : Double(total) / Double(points.count))
    }
}

/// A day or a month of the activity chart.
private struct TVPeriod {
    /// "Tuesday, Oct 27", "October 2026".
    let title: String
    /// The chart it came from, over its list.
    let caption: String
    /// Newest first.
    let sightings: [Sighting]
    /// Newest first: the day itself, or the month's days.
    let days: [LogbookDay]
    let notable: Int
    let newTypes: Int
    let photos: Int
    let places: [String]
}

private struct TVPeriodList: Identifiable {
    let id = UUID()
    let period: TVPeriod
    let average: Double
}

/// What a day (or month) was like: how many against the average, where you watched, what
/// stood out, and who came by.
private struct TVPeriodPanel: View {
    let period: TVPeriod
    /// The chart's average per bar.
    let average: Double
    let unit: Calendar.Component

    var body: some View {
        let count = period.sightings.count
        VStack(alignment: .leading, spacing: 22) {
            Text(period.title)
                .font(.mono(36, .heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(RadarFormat.wholeNumber(count))
                        .font(.mono(88, .heavy))
                        .foregroundStyle(count > 0 ? ChartTone.teal.color : Palette.faint)
                    Text("aircraft")
                        .font(.mono(30, .bold))
                        .foregroundStyle(Palette.value)
                }
                Text(comparison(count))
                    .font(.mono(22))
                    .foregroundStyle(Palette.caption)
            }
            if count > 0 {
                LogbookDayTags(notable: period.notable, newTypes: period.newTypes, photos: period.photos,
                               place: placeSummary, scale: 2)
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 24, verticalSpacing: 16) {
                    fact("Airlines", shares(LogbookDigest.rank(period.sightings, key: { $0.isAirline ? $0.operatorName : nil }) { key, _ in (key, nil) }))
                    fact("Types", shares(LogbookDigest.rank(period.sightings, key: \.typeCode) { key, latest in (latest.typeName ?? key, key) }))
                    if unit == .month {
                        fact("Best day", bestDay)
                    } else {
                        fact("Busiest hour", busiestHour)
                    }
                    fact("Closest", period.sightings.min { $0.closestMiles < $1.closestMiles }.map { "\($0.closestPreciseText) · \($0.displayIdentifier)" })
                }
            }
        }
    }

    /// "12 more than the average of 30", "Nothing logged".
    private func comparison(_ count: Int) -> String {
        guard count > 0 else { return "Nothing logged" }
        let mean = Int(average.rounded())
        let per = unit == .month ? "month" : "day"
        if count == mean { return "Right on the average \(per)" }
        let gap = abs(count - mean)
        return "\(RadarFormat.wholeNumber(gap)) \(count > mean ? "more" : "fewer") than the average \(per) (\(RadarFormat.wholeNumber(mean)))"
    }

    private var placeSummary: String? {
        guard let first = period.places.first else { return nil }
        return period.places.count == 1 ? first : "\(first) + \(period.places.count - 1) more"
    }

    private var busiestHour: String? {
        let counts = LogbookSightingsHours.hourly(period.sightings)
        guard let max = counts.max(), max > 0, let hour = counts.firstIndex(of: max) else { return nil }
        return "\(LogbookFormat.hourRange(hour)) · \(max)"
    }

    private var bestDay: String? {
        guard let best = period.days.max(by: { $0.count < $1.count }) else { return nil }
        return "\(best.day.formatted(.dateTime.month(.abbreviated).day())) · \(RadarFormat.wholeNumber(best.count))"
    }

    private func shares(_ ranks: [LogbookRank]) -> String? {
        let count = period.sightings.count
        guard !ranks.isEmpty, count > 0 else { return nil }
        return ranks.prefix(3).map { "\($0.title) \(Int((Double($0.count) / Double(count) * 100).rounded()))%" }
            .joined(separator: " · ")
    }

    @ViewBuilder
    private func fact(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value {
            GridRow {
                Text(label).radarCaptionTV()
                Text(value)
                    .font(.mono(24, .semibold))
                    .foregroundStyle(Palette.value)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Aircraft per hour, midnight first, on the TV's calendar.
private enum LogbookSightingsHours {
    static func hourly(_ sightings: [Sighting], calendar: Calendar = .current) -> [Int] {
        var counts = Array(repeating: 0, count: 24)
        var clock = DayClock(calendar)
        for s in sightings { counts[clock.hour(of: s.firstSeen)] += 1 }
        return counts
    }
}

// MARK: - The aircraft

/// The aircraft behind something picked on a chart (a petal, an hour, a day): what they add
/// up to on the left, every one of them on the right. Click one for its page, then ◀ ▶ through
/// the rest.
struct TVSightingListView<Summary: View>: View {
    /// "Which way they fly · Atlanta, GA".
    let caption: String
    /// Newest first.
    let sightings: [Sighting]
    let logbook: Logbook
    var showPhotos = true
    @ViewBuilder var summary: Summary

    @State private var browse: TVSightingBrowse?

    var body: some View {
        ZStack {
            LogbookBackdrop()
            HStack(alignment: .top, spacing: 70) {
                VStack(alignment: .leading, spacing: 22) {
                    Text(caption).radarCaptionTV()
                    summary
                }
                .frame(width: 720, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    TVSectionHeader(title: "Every aircraft · \(RadarFormat.wholeNumber(sightings.count))")
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(sightings) { s in
                                Button {
                                    browse = TVSightingBrowse(sightings, showing: s)
                                } label: {
                                    TVSightingRow(sighting: s, isLive: false, compact: true)
                                }
                                .buttonStyle(TVRowButtonStyle())
                            }
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 10)
                    }
                    .scrollClipDisabled()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .focusSection()
            }
            .padding(.horizontal, 100)
            .padding(.vertical, 70)
        }
        .fullScreenCover(item: $browse) { browse in
            TVSightingDetailView(browse: browse, logbook: logbook, showTopography: true, showPhotos: showPhotos) { _ in }
        }
    }
}
#endif
