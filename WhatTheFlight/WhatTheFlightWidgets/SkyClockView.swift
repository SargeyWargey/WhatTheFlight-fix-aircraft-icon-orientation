//
//  SkyClockView.swift
//  WhatTheFlightWidgets
//
//  The Your Sky widget's faces: when aircraft pass over where you watch, as a 24-hour dial
//  with a hand at the time now, and which way they fly as a rose. Also compiled into the app
//  for its DEBUG widget gallery.
//

#if os(iOS)
import WidgetKit
import SwiftUI

struct SkyClockView: View {
    let entry: LogbookEntry
    let family: WidgetFamily

    private var sky: LogbookSnapshot.Sky? { entry.snapshot?.sky }

    var body: some View {
        Group {
            if let sky, sky.showsTimes {
                switch family {
                case .accessoryCircular: circular(sky)
                case .systemMedium: medium(sky)
                default: small(sky)
                }
            } else {
                fillingIn
            }
        }
        .widgetURL(AppRouter.url(for: .logbookTab("stats")))
    }

    private var nowHour: Int { Calendar.current.component(.hour, from: entry.date) }

    // MARK: Lock Screen

    private func circular(_ sky: LogbookSnapshot.Sky) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            SkyDial(hourly: sky.hourly, now: entry.date, monochrome: true)
                .padding(3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sky.busiestHour.map { "Busiest at \(LogbookFormat.hour($0))" } ?? "Aircraft by hour")
    }

    // MARK: Home Screen

    private func small(_ sky: LogbookSnapshot.Sky) -> some View {
        VStack(spacing: 2) {
            HStack {
                WidgetCaption("Your sky")
                Spacer(minLength: 2)
                Text(sky.place.map(Self.shortPlace) ?? String(localized: "All places"))
                    .font(.mono(8, .semibold))
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
            }
            ZStack {
                SkyDial(hourly: sky.hourly, now: entry.date)
                DialCentre(title: LogbookFormat.hour(nowHour), caption: "Now",
                           detail: nowLabel(sky))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func medium(_ sky: LogbookSnapshot.Sky) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                WidgetCaption("Your sky")
                Text(sky.place ?? String(localized: "All places"))
                    .font(.mono(9, .bold))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(RadarFormat.wholeNumber(sky.count)) aircraft")
                    .font(.mono(8, .semibold))
                    .foregroundStyle(Palette.faint)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                ZStack {
                    SkyDial(hourly: sky.hourly, now: entry.date)
                    if let busiest = sky.busiestHour {
                        DialCentre(title: LogbookFormat.hour(busiest), caption: "Busiest", detail: nil)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                if sky.showsHeadings {
                    HeadingRose(sectors: sky.headings)
                        .aspectRatio(1, contentMode: .fit)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Fact(caption: "Now", value: LogbookFormat.hourRange(nowHour), detail: nowLabel(sky), tint: ChartTone.timeOfDay(nowHour))
                    if let busiest = sky.busiestHour {
                        Fact(caption: "Peak", value: LogbookFormat.hourRange(busiest), detail: nil, tint: ChartTone.timeOfDay(busiest))
                    }
                    if sky.showsHeadings, let sector = sky.mainSector {
                        Fact(caption: "Mostly", value: LogbookFormat.sectorNames[sector] + "-bound",
                             detail: "\(Int((sky.mainShare * 100).rounded()))%", tint: ChartTone.heading(Double(sector) * 22.5))
                    }
                }
                .frame(minWidth: 70, maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// "busy", "quiet", "usual" for the hour now, against the day's average.
    private func nowLabel(_ sky: LogbookSnapshot.Sky) -> String {
        let total = sky.hourly.reduce(0, +)
        guard total > 0 else { return "" }
        let share = Double(sky.hourly[nowHour]) / Double(total) * 24
        switch share {
        case ..<0.35: return String(localized: "quiet")
        case ..<0.8: return String(localized: "light")
        case ..<1.3: return String(localized: "steady")
        default: return String(localized: "busy")
        }
    }

    /// "Atlanta, GA" → "Atlanta".
    private static func shortPlace(_ place: String) -> String {
        place.split(separator: ",").first.map(String.init) ?? place
    }

    // MARK: Not enough yet

    @ViewBuilder
    private var fillingIn: some View {
        let count = sky?.count ?? 0
        let fraction = min(1, Double(count) / 50)
        switch family {
        case .accessoryCircular:
            Gauge(value: fraction) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: "clock").font(.system(size: 16, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircularCapacity)
        default:
            VStack(alignment: .leading, spacing: 6) {
                WidgetCaption("Your sky")
                Spacer(minLength: 0)
                Image(systemName: "clock.badge")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Palette.ink)
                Text(entry.snapshot == nil ? "Open What The Flight?" : "Filling in")
                    .font(.mono(13, .bold))
                    .foregroundStyle(Palette.ink)
                Text(entry.snapshot == nil ? "Your sky shows up here once the app has run."
                     : "\(count) of 50 aircraft logged here before the clock draws.")
                    .font(.mono(9))
                    .foregroundStyle(Palette.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.snapshot != nil {
                    ProgressCapsule(fraction: fraction, tint: Palette.ink, height: 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Pieces

private struct DialCentre: View {
    let title: String
    let caption: LocalizedStringKey
    let detail: String?

    var body: some View {
        VStack(spacing: 0) {
            Text(caption)
                .font(.mono(6.5, .heavy))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
            Text(title)
                .font(.mono(12, .heavy))
                .foregroundStyle(Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.mono(7, .bold))
                    .foregroundStyle(Palette.signal)
                    .lineLimit(1)
            }
        }
        .frame(width: 46)
    }
}

private struct Fact: View {
    let caption: LocalizedStringKey
    let value: String
    let detail: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.mono(7, .heavy))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.mono(11, .heavy))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.mono(8, .semibold))
                        .foregroundStyle(Palette.caption)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
