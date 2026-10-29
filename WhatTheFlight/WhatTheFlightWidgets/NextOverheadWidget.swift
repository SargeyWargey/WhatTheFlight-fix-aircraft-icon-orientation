//
//  NextOverheadWidget.swift
//  WhatTheFlightWidgets
//
//  "Next overhead" on the Home Screen, Lock Screen and in StandBy (Enhancements Spec C6):
//  counts down to the next aircraft passing within the overhead alert's distance, with a ring
//  that drains over the last five minutes. The timeline comes from `NearbyTraffic.timeline`,
//  the same one the Watch's Next Overhead complication uses, and the countdown is a timer
//  text, so it ticks without the widget refreshing.
//

import WidgetKit
import SwiftUI
import CoreLocation

struct NextOverheadEntry: TimelineEntry {
    let date: Date
    let moment: SkyMoment?
    var needsSetup = false
    var isStale = false
    var relevance: TimelineEntryRelevance? = nil
}

struct NextOverheadProvider: TimelineProvider {
    static let steps = 10
    static let step: TimeInterval = 60

    func placeholder(in context: Context) -> NextOverheadEntry {
        NextOverheadEntry(date: Date(), moment: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextOverheadEntry) -> Void) {
        if context.isPreview {
            completion(NextOverheadEntry(date: Date(), moment: Self.sample))
            return
        }
        Task { completion(await entries().first ?? NextOverheadEntry(date: Date(), moment: nil)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextOverheadEntry>) -> Void) {
        Units.reload()
        Task {
            // Refreshes are rationed: the countdown covers ten minutes, then ask again.
            completion(Timeline(entries: await entries(), policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func entries() async -> [NextOverheadEntry] {
        Catalogs.warmUp(airports: false)
        let store = SharedRadarStore()
        let now = Date()
        let saved = store.snapshot.map { SkyMoment(snapshot: $0, overheadMiles: store.overheadMiles) }
        guard let observer = store.observer else {
            return [NextOverheadEntry(date: now, moment: saved, needsSetup: saved == nil)]
        }
        guard let flights = try? await NearbyTraffic.flights(around: observer, radiusMiles: store.radiusMiles) else {
            return [NextOverheadEntry(date: now, moment: saved, isStale: true)]
        }
        let moments = NearbyTraffic.timeline(flights, observer: observer, radiusMiles: store.radiusMiles,
                                             overheadMiles: store.overheadMiles, placeName: store.placeName,
                                             start: now, count: Self.steps, step: Self.step)
        var result = moments.map { moment in
            NextOverheadEntry(date: moment.date, moment: moment, relevance: Self.relevance(for: moment))
        }
        result.append(NextOverheadEntry(date: now.addingTimeInterval(Double(Self.steps) * Self.step), moment: moments.last, isStale: true))
        return result
    }

    /// The Smart Stack lifts the widget as a pass nears and while it's overhead.
    private static func relevance(for moment: SkyMoment) -> TimelineEntryRelevance? {
        if moment.passing != nil { return TimelineEntryRelevance(score: 100, duration: SkyPass.linger) }
        guard let pass = moment.nextPass else { return TimelineEntryRelevance(score: 0) }
        let lead = pass.date.timeIntervalSince(moment.date)
        guard lead <= SkyPass.ringWindow else { return TimelineEntryRelevance(score: 10) }
        return TimelineEntryRelevance(score: Float(100 - lead / SkyPass.ringWindow * 60), duration: lead + SkyPass.linger)
    }

    static var sample: SkyMoment {
        let snapshot = RadarSnapshot.sample
        guard let f = snapshot.flights.first else { return SkyMoment(snapshot: snapshot) }
        return SkyMoment(snapshot: snapshot, nextPass: SkyPass(flight: f, date: Date().addingTimeInterval(95), miles: 0.8))
    }
}

struct NextOverheadWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedRadarStore.nextOverheadKind, provider: NextOverheadProvider()) { entry in
            NextOverheadView(entry: entry)
                .containerBackground(for: .widget) { Palette.paper }
        }
        .configurationDisplayName("Next Overhead")
        .description("Counts down to the next aircraft passing over you.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct NextOverheadView: View {
    let entry: NextOverheadEntry
    @Environment(\.widgetFamily) private var family

    private var pass: SkyPass? { entry.moment?.passing ?? entry.moment?.nextPass }
    private var isOverhead: Bool { entry.moment?.passing != nil }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            default: small
            }
        }
        .widgetURL(pass.map { AppRouter.url(for: .find($0.flight.id)) } ?? AppRouter.url(for: .sky))
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var inline: some View {
        if let pass, isOverhead {
            Text("\(Image(systemName: "scope")) \(pass.flight.identifier) overhead now")
        } else if let pass {
            Text("\(Image(systemName: "scope")) \(pass.flight.identifier) in \(Text(timerInterval: entry.date...pass.date, countsDown: true))")
        } else {
            Text("\(Image(systemName: "sun.haze")) Nothing passing over")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let pass {
                ProgressView(timerInterval: pass.date.addingTimeInterval(-SkyPass.ringWindow)...pass.date, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: isOverhead ? "scope" : "airplane")
                }
                .progressViewStyle(.circular)
                .padding(2)
            } else {
                Image(systemName: "sun.haze").font(.system(size: 18, weight: .semibold))
            }
        }
        .accessibilityLabel(pass.map { "\($0.flight.identifier) passes over \(isOverhead ? "now" : $0.date.formatted(date: .omitted, time: .shortened))" } ?? "Nothing passing over")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let pass {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                    Text(pass.flight.identifier).font(.mono(15, .heavy))
                }
                if isOverhead {
                    Text("Overhead now · look up").font(.mono(12, .semibold))
                } else {
                    Text("Over you in \(Text(timerInterval: entry.date...pass.date, countsDown: true))")
                        .font(.mono(12, .semibold))
                        .monospacedDigit()
                }
                Text("\(RadarFormat.distanceText(pass.flight.distanceMiles)) \(GeoMath.cardinal(pass.flight.bearing)) · \(RadarFormat.altitudeText(pass.flight.altitudeFeet))")
                    .font(.mono(11))
                    .lineLimit(1)
            } else {
                Label("Nothing passing over", systemImage: "sun.haze").font(.mono(13, .bold))
                Text(entry.needsSetup ? "Open What The Flight? to start" : "in the next ten minutes")
                    .font(.mono(11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next overhead")
                .font(.mono(10, .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
            Spacer(minLength: 2)
            if let pass {
                HStack(alignment: .center, spacing: 10) {
                    ring(pass, size: 46)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pass.flight.identifier)
                            .font(.mono(18, .heavy))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if isOverhead {
                            Text("Now").font(.mono(16, .heavy)).foregroundStyle(Palette.signal)
                        } else {
                            Text(timerInterval: entry.date...pass.date, countsDown: true)
                                .font(.mono(16, .heavy))
                                .foregroundStyle(Palette.signal)
                                .monospacedDigit()
                        }
                    }
                }
                Text(pass.flight.route ?? pass.flight.typeName ?? pass.flight.operatorName)
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Palette.route)
                    .lineLimit(1)
                Text("Look \(GeoMath.cardinal(pass.flight.bearing)) · \(RadarFormat.altitudeText(pass.flight.altitudeFeet))")
                    .font(.mono(10))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            } else {
                Image(systemName: "sun.haze")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Palette.ink)
                Text(entry.needsSetup ? "Open the app to start" : "Nothing passing over in the next 10 min")
                    .font(.mono(11, .semibold))
                    .foregroundStyle(Palette.value)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small
            VStack(alignment: .leading, spacing: 8) {
                Text("\(entry.moment?.snapshot.inRangeCount ?? 0) in range")
                    .font(.mono(10, .bold))
                    .foregroundStyle(Palette.caption)
                Spacer(minLength: 0)
                // Opens the app, which starts Sky Watch: alerts while the phone is locked.
                Link(destination: AppRouter.url(for: .startSkyWatch)) {
                    Label("Start Sky Watch", systemImage: "dot.radiowaves.left.and.right")
                        .font(.mono(12, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Palette.ink, in: Capsule())
                }
                Text("Alerts with your phone locked")
                    .font(.mono(9))
                    .foregroundStyle(Palette.caption)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func ring(_ pass: SkyPass, size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.15), lineWidth: 5)
            ProgressView(timerInterval: pass.date.addingTimeInterval(-SkyPass.ringWindow)...pass.date, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(Palette.signal)
            Image(systemName: isOverhead ? "scope" : "airplane")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundStyle(Palette.ink)
        }
        .frame(width: size, height: size)
    }
}
