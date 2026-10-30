//
//  LogbookStatsView.swift
//  WhatTheFlightWidgets
//
//  The Logbook widget's faces: aircraft logged today, the streak, the last weeks as bars,
//  what you've collected and your records. Also compiled into the app for its DEBUG widget
//  gallery, so it takes the family rather than reading it.
//

#if os(iOS)
import WidgetKit
import SwiftUI

struct LogbookStatsView: View {
    let entry: LogbookEntry
    let family: WidgetFamily

    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: entry.date) }

    var body: some View {
        Group {
            if let s = entry.snapshot, s.total > 0 {
                switch family {
                case .accessoryInline: inline(s)
                case .accessoryCircular: circular(s)
                case .accessoryRectangular: rectangular(s)
                case .systemMedium: medium(s)
                case .systemLarge: large(s)
                default: small(s)
                }
            } else {
                switch family {
                case .accessoryInline: Text("\(Image(systemName: "book.closed")) Logbook")
                case .accessoryCircular:
                    ZStack {
                        AccessoryWidgetBackground()
                        Image(systemName: "book.closed").font(.system(size: 20, weight: .semibold))
                    }
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Label("Logbook", systemImage: "book.closed").font(.mono(13, .bold))
                        Text(entry.snapshot == nil ? "Open What The Flight? to start" : "Nothing logged yet").font(.mono(11))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                default:
                    LogbookWidgetEmpty(snapshot: entry.snapshot, compact: family == .systemSmall)
                }
            }
        }
        .widgetURL(AppRouter.url(for: family == .systemLarge ? .logbookTab("stats") : .logbook))
    }

    // MARK: Lock Screen

    private func inline(_ s: LogbookSnapshot) -> some View {
        let streak = s.streak(at: entry.date)
        return Text(streak > 1
                    ? "\(Image(systemName: "airplane")) \(s.count(on: entry.date)) today · \(streak)-day streak"
                    : "\(Image(systemName: "airplane")) \(s.count(on: entry.date)) today · \(RadarFormat.wholeNumber(s.total)) logged")
    }

    private func circular(_ s: LogbookSnapshot) -> some View {
        let count = s.count(on: entry.date)
        let best = max(1, s.bestDay?.count ?? 1, count)
        return Gauge(value: Double(count), in: 0...Double(best)) {
            Image(systemName: "airplane")
        } currentValueLabel: {
            Text("\(count)").font(.mono(16, .heavy)).minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("\(count) aircraft today, best day \(best)")
    }

    private func rectangular(_ s: LogbookSnapshot) -> some View {
        let streak = s.streak(at: entry.date)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "book.closed.fill")
                Text("Logbook").font(.mono(12, .bold)).textCase(.uppercase)
            }
            .widgetAccentable()
            HStack(spacing: 6) {
                Text("\(s.count(on: entry.date)) today").font(.mono(15, .heavy))
                if streak > 0 {
                    Text("\(Image(systemName: "flame.fill"))\(streak)").font(.mono(13, .bold))
                }
            }
            Text("\(RadarFormat.wholeNumber(s.total)) · \(s.types) types").font(.mono(11)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private func small(_ s: LogbookSnapshot) -> some View {
        let count = s.count(on: entry.date)
        let streak = s.streak(at: entry.date)
        let atRisk = s.streakNeedsToday(at: entry.date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                WidgetCaption("Today")
                Spacer(minLength: 4)
                if streak > 0 { StreakChip(days: streak, atRisk: atRisk, size: 10) }
            }
            Text(RadarFormat.wholeNumber(count))
                .font(.mono(44, .heavy))
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .widgetAccentable()
                .padding(.top, 2)
            Text(atRisk ? "Log one to keep the streak" : "aircraft logged")
                .font(.mono(9, .semibold))
                .foregroundStyle(atRisk ? ChartTone.amber.color : Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            DayBars(days: s.days(7, endingOn: entry.date), today: today, spacing: 4, labels: true)
                .frame(height: 36)
            Text("\(RadarFormat.wholeNumber(s.total)) in all · \(s.types) types")
                .font(.mono(9, .medium))
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ s: LogbookSnapshot) -> some View {
        let count = s.count(on: entry.date)
        let streak = s.streak(at: entry.date)
        let atRisk = s.streakNeedsToday(at: entry.date)
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetCaption("Today")
                Text(RadarFormat.wholeNumber(count))
                    .font(.mono(46, .heavy))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .widgetAccentable()
                Text("aircraft logged")
                    .font(.mono(9, .semibold))
                    .foregroundStyle(Palette.caption)
                Spacer(minLength: 6)
                if streak > 0 {
                    HStack(spacing: 5) {
                        StreakChip(days: streak, atRisk: atRisk, size: 11)
                        Text(atRisk ? "keep it going" : "days in a row")
                            .font(.mono(8, .semibold))
                            .foregroundStyle(atRisk ? ChartTone.amber.color : Palette.caption)
                            .lineLimit(2)
                    }
                } else if s.bestStreak > 1 {
                    Text("Best run \(s.bestStreak) days")
                        .font(.mono(9, .semibold))
                        .foregroundStyle(Palette.caption)
                }
            }
            .frame(width: 104, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    WidgetCaption("Last 14 days")
                    Spacer()
                    if let best = s.days(14, endingOn: entry.date).map(\.count).max(), best > 0 {
                        Text("peak \(best)")
                            .font(.mono(8, .semibold))
                            .foregroundStyle(Palette.faint)
                    }
                }
                DayBars(days: s.days(14, endingOn: entry.date), today: today, spacing: 3, labels: true)
                    .frame(maxHeight: .infinity)
                HStack(spacing: 0) {
                    MiniStat(value: s.total, label: "Logged", tint: Palette.ink)
                    MiniStat(value: s.types, label: "Types", tint: ChartTone.sky.color)
                    MiniStat(value: s.airlines, label: "Airlines", tint: ChartTone.teal.color)
                    MiniStat(value: s.countries, label: "Countries", tint: ChartTone.pink.color)
                }
            }
        }
    }

    private func large(_ s: LogbookSnapshot) -> some View {
        let count = s.count(on: entry.date)
        let streak = s.streak(at: entry.date)
        let atRisk = s.streakNeedsToday(at: entry.date)
        let highlights = s.highlights(at: entry.date)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                WidgetCaption("Logbook", color: Palette.signal)
                Spacer()
                Text("\(RadarFormat.wholeNumber(s.total)) aircraft")
                    .font(.mono(10, .bold))
                    .foregroundStyle(Palette.caption)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(RadarFormat.wholeNumber(count))
                        .font(.mono(44, .heavy))
                        .foregroundStyle(Palette.ink)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .widgetAccentable()
                    Text("today")
                        .font(.mono(9, .semibold))
                        .foregroundStyle(Palette.caption)
                }
                Spacer(minLength: 4)
                if streak > 0 {
                    HeroFact(symbol: "flame.fill", tint: atRisk ? ChartTone.amber.color : ChartTone.coral.color,
                             value: "\(streak)", label: atRisk ? "keep it going" : "day streak")
                }
                HeroFact(symbol: "trophy.fill", tint: ChartTone.amber.color,
                         value: "\(s.bestStreak)", label: "best run")
                if let best = s.bestDay {
                    HeroFact(symbol: "chart.bar.fill", tint: ChartTone.pink.color,
                             value: RadarFormat.wholeNumber(best.count), label: "best day")
                }
            }

            if let highlights {
                TodayHighlights(today: highlights)
            }

            VStack(alignment: .leading, spacing: 4) {
                WidgetCaption("Last 30 days")
                DayBars(days: s.days(30, endingOn: entry.date), today: today, spacing: 2)
                    .frame(maxHeight: .infinity)
            }

            HStack(spacing: 6) {
                StatTile(value: s.airframes, label: "Airframes", symbol: "airplane", tint: Palette.ink)
                StatTile(value: s.types, label: "Types", symbol: "square.stack.3d.up.fill", tint: ChartTone.sky.color)
                StatTile(value: s.airlines, label: "Airlines", symbol: "building.2.fill", tint: ChartTone.teal.color)
                StatTile(value: s.countries, label: "Countries", symbol: "flag.fill", tint: ChartTone.pink.color)
            }

            let records = RecordCell.shown(s.records)
            if !records.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 7) {
                    ForEach(Array(stride(from: 0, to: records.count, by: 2)), id: \.self) { i in
                        GridRow {
                            RecordCell(record: records[i])
                            if i + 1 < records.count { RecordCell(record: records[i + 1]) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Pieces

private struct MiniStat: View {
    let value: Int
    let label: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.formatted(.number.notation(.compactName)))
                .font(.mono(13, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.mono(7, .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HeroFact: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
                Text(value)
                    .font(.mono(17, .heavy))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(label)
                .font(.mono(7, .bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let value: Int
    let label: LocalizedStringKey
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(height: 11)
            Text(value.formatted(.number.notation(.compactName)))
                .font(.mono(15, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.mono(7, .bold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Palette.paperShade.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct RecordCell: View {
    let record: LogbookSnapshot.Record

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: record.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Self.tint(record.id))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(record.title)
                    .font(.mono(7, .bold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                Text(record.value)
                    .font(.mono(13, .heavy))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(record.flight)
                    .font(.mono(8))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Four records, the ones people brag about first.
    static func shown(_ records: [LogbookSnapshot.Record]) -> [LogbookSnapshot.Record] {
        let order = ["closest", "highest", "fastest", "route", "longest", "lowest"]
        return Array(records.sorted { (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count) }.prefix(4))
    }

    /// The logbook's record tints (`LogbookRecord.tint`).
    static func tint(_ id: String) -> Color {
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

/// Today's notable aircraft, new types and new airlines, as one line of chips.
private struct TodayHighlights: View {
    let today: LogbookSnapshot.Today

    var body: some View {
        let chips: [(symbol: String, text: String, tint: Color)] = [
            today.notable > 0 ? ("star.fill", today.notable == 1 ? String(localized: "1 notable") : String(localized: "\(today.notable) notable"), Palette.notable) : nil,
            today.newTypes.first.map { ("sparkles", String(localized: "New: \($0)"), ChartTone.sky.color) },
            today.newAirlines.first.map { ("building.2.fill", $0, ChartTone.teal.color) },
            today.closest.map { ("scope", $0, ChartTone.coral.color) },
        ].compactMap { $0 }
        ViewThatFits(in: .horizontal) {
            row(chips)
            row(Array(chips.prefix(2)))
            row(Array(chips.prefix(1)))
        }
    }

    private func row(_ chips: [(symbol: String, text: String, tint: Color)]) -> some View {
        HStack(spacing: 5) {
            ForEach(chips, id: \.text) { chip in
                HStack(spacing: 3) {
                    Image(systemName: chip.symbol).font(.system(size: 8, weight: .bold))
                    Text(chip.text).font(.mono(9, .bold)).lineLimit(1)
                }
                .foregroundStyle(chip.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(chip.tint.opacity(0.13)))
                .fixedSize()
            }
        }
    }
}
#endif
