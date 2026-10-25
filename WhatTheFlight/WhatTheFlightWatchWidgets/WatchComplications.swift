//
//  WatchComplications.swift
//  WhatTheFlightWatchWidgets
//
//  Watch face complications and the Smart Stack:
//  - Nearest Aircraft: how far, which way and where it's heading (the original kind).
//  - Sky Radar: everything around you on a little north-up radar.
//  - Next Overhead: a countdown to the next aircraft passing within the overhead alert's
//    distance, which lifts itself in the Smart Stack before the pass.
//  - Identify: one tap from the face to pointing at a plane.
//  Complications reload only a few times an hour, so each traffic timeline dead-reckons the
//  aircraft forward a minute at a time for five minutes (plus a moment at each close pass),
//  then admits it needs a refresh rather than inventing positions. The three traffic kinds
//  share one fetch. The views are in ComplicationViews.swift.
//

import WidgetKit
import SwiftUI
import CoreLocation
import RelevanceKit

@main
struct WhatTheFlightWatchWidgets: WidgetBundle {
    var body: some Widget {
        NearestAircraftComplication()
        SkyRadarComplication()
        NextOverheadComplication()
        IdentifyComplication()
    }
}

// MARK: - Widgets

struct NearestAircraftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.nearest.rawValue, provider: SkyProvider(kind: .nearest)) { entry in
            FamilyReader { NearestComplicationView(entry: entry, family: $0) }
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(entry.nearest.map { ComplicationLink.flight($0.id) } ?? ComplicationLink.radar)
        }
        .configurationDisplayName("Nearest Aircraft")
        .description("The nearest aircraft: how far, which way, and where it's heading.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct SkyRadarComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.radar.rawValue, provider: SkyProvider(kind: .radar)) { entry in
            FamilyReader { SkyRadarComplicationView(entry: entry, family: $0) }
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(ComplicationLink.radar)
        }
        .configurationDisplayName("Sky Radar")
        .description("Every aircraft around you on a little radar, north up.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct NextOverheadComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.nextOverhead.rawValue, provider: SkyProvider(kind: .nextOverhead)) { entry in
            FamilyReader { NextOverheadComplicationView(entry: entry, family: $0) }
                .containerBackground(for: .widget) { Color.clear }
                // Tapping a countdown opens Find on that aircraft, to be looking when it arrives.
                .widgetURL((entry.passing ?? entry.nextPass).map { ComplicationLink.find($0.flight.id) } ?? ComplicationLink.radar)
        }
        .configurationDisplayName("Next Overhead")
        .description("Counts down to the next aircraft passing over you.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct IdentifyComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchComplicationKind.identify.rawValue, provider: IdentifyProvider()) { _ in
            FamilyReader { IdentifyComplicationView(family: $0) }
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(ComplicationLink.identify)
        }
        .configurationDisplayName("Identify")
        .description("Point at a plane to find out what it is.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

/// Hands the widget family to views that take it as a parameter.
struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    @ViewBuilder let content: (WidgetFamily) -> Content

    var body: some View { content(family) }
}

/// The Watch app's deep links (`WatchRouter.open`).
enum ComplicationLink {
    static let radar = URL(string: "whattheflight://radar")!
    /// Identify: "what am I pointing at?"
    static let identify = URL(string: "whattheflight://sky")!

    static func flight(_ id: String) -> URL { URL(string: "whattheflight://flight/\(id)")! }
    /// Find: guide the arm to this aircraft.
    static func find(_ id: String) -> URL { URL(string: "whattheflight://sky/\(id)")! }
}

// MARK: - Traffic

struct SkyProvider: TimelineProvider {
    let kind: WatchComplicationKind

    static let steps = 6
    static let step: TimeInterval = 60

    func placeholder(in context: Context) -> SkyEntry {
        ComplicationSamples.entry
    }

    func getSnapshot(in context: Context, completion: @escaping (SkyEntry) -> Void) {
        if context.isPreview {
            completion(ComplicationSamples.entry)
            return
        }
        Task { completion(await entries().first ?? SkyEntry(date: Date(), moment: nil)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SkyEntry>) -> Void) {
        Task { completion(Timeline(entries: await entries(), policy: .atEnd)) }
    }

    /// Lifts the card in the Smart Stack from five minutes before each close pass until it's
    /// over, rather than only scoring entries once they're showing. The Watch app asks for
    /// this again whenever it reloads the timelines.
    func relevance() async -> WidgetRelevance<Void> {
        guard WatchComplicationKind.passAware.contains(kind) else { return WidgetRelevance([]) }
        let now = Date()
        var passes: [String: SkyPass] = [:]
        for moment in await entries().compactMap(\.moment) {
            for pass in [moment.passing, moment.nextPass].compactMap({ $0 }) where passes[pass.flight.id] == nil {
                passes[pass.flight.id] = pass
            }
        }
        let attributes = passes.values
            .filter { $0.date.addingTimeInterval(SkyPass.linger) > now }
            .map { WidgetRelevanceAttribute<Void>(context: Self.context(for: $0, now: now)) }
        return WidgetRelevance(attributes)
    }

    private static func context(for pass: SkyPass, now: Date) -> RelevantContext {
        let start = max(now, pass.date.addingTimeInterval(-SkyPass.ringWindow))
        let end = pass.date.addingTimeInterval(SkyPass.linger)
        if #available(watchOS 26, *) {
            return .date(interval: DateInterval(start: start, end: end), kind: .default)
        }
        return .date(from: start, to: end)
    }

    private func entries() async -> [SkyEntry] {
        // Airport codes only on a complication: skip the airport catalog (Apple Watch Enhancements A4).
        Catalogs.warmUp(airports: false)
        let store = SharedRadarStore()
        let now = Date()
        let saved = store.snapshot.map { SkyMoment(snapshot: $0, overheadMiles: store.overheadMiles) }
        guard let observer = store.observer else {
            return [SkyEntry(date: now, moment: saved, needsSetup: saved == nil)]
        }
        guard let flights = try? await ComplicationTraffic.shared.flights(around: observer, radiusMiles: store.radiusMiles) else {
            // Offline: show what the app last saw, once.
            return [SkyEntry(date: now, moment: saved),
                    SkyEntry(date: now.addingTimeInterval(Self.step), moment: saved, isStale: true)]
        }
        let moments = NearbyTraffic.timeline(flights, observer: observer, radiusMiles: store.radiusMiles,
                                             overheadMiles: store.overheadMiles, placeName: store.placeName,
                                             start: now, count: Self.steps, step: Self.step)
        var result = moments.map { SkyEntry(date: $0.date, moment: $0, relevance: kind.relevance(for: $0)) }
        result.append(SkyEntry(date: now.addingTimeInterval(Double(Self.steps) * Self.step), moment: moments.last, isStale: true))
        return result
    }
}

extension WatchComplicationKind {
    /// Scores each entry for the Smart Stack while it's showing.
    func relevance(for moment: SkyMoment) -> TimelineEntryRelevance? {
        let score: Float
        switch self {
        case .nextOverhead:
            let lead = moment.nextPass.map { $0.date.timeIntervalSince(moment.date) }
            score = moment.passing != nil ? 100 : (lead ?? .infinity) <= 180 ? 80 : lead != nil ? 40 : 0
        case .nearest:
            let soon = moment.snapshot.flights.contains { ($0.closestPassSeconds ?? .infinity) < 180 && ($0.closestPassMiles ?? .infinity) < 2 }
            let notable = moment.snapshot.flights.contains { $0.notableTag != nil }
            score = soon ? 80 : notable ? 60 : moment.snapshot.inRangeCount > 0 ? 10 : 0
        case .radar, .identify:
            return nil
        }
        return TimelineEntryRelevance(score: score, duration: SkyProvider.step)
    }
}

/// One fetch for all three traffic complications. WidgetKit reloads them together, and each
/// asking Flightradar24 on its own would triple the requests.
actor ComplicationTraffic {
    static let shared = ComplicationTraffic()
    /// Positions carry their own timestamps, so a fetch this recent dead-reckons as well as a new one.
    private static let reuseFor: TimeInterval = 45

    private struct Area: Equatable {
        let latitude: Double
        let longitude: Double
        let radiusMiles: Double
    }

    private var latest: (area: Area, date: Date, flights: [Flight])?
    private var pending: (area: Area, task: Task<[Flight], Error>)?

    func flights(around observer: CLLocationCoordinate2D, radiusMiles: Double) async throws -> [Flight] {
        let area = Area(latitude: observer.latitude, longitude: observer.longitude, radiusMiles: radiusMiles)
        if let latest, latest.area == area, Date().timeIntervalSince(latest.date) < Self.reuseFor {
            return latest.flights
        }
        if let pending, pending.area == area {
            return try await pending.task.value
        }
        let task = Task { try await NearbyTraffic.flights(around: observer, radiusMiles: radiusMiles) }
        pending = (area, task)
        defer { if pending?.area == area { pending = nil } }
        let flights = try await task.value
        latest = (area, Date(), flights)
        return flights
    }
}

// MARK: - Identify

struct IdentifyEntry: TimelineEntry {
    let date: Date
}

/// Nothing changes: one entry, forever.
struct IdentifyProvider: TimelineProvider {
    func placeholder(in context: Context) -> IdentifyEntry { IdentifyEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (IdentifyEntry) -> Void) {
        completion(IdentifyEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<IdentifyEntry>) -> Void) {
        completion(Timeline(entries: [IdentifyEntry(date: Date())], policy: .never))
    }
}

// MARK: - Previews

#Preview("Nearest", as: .accessoryRectangular) {
    NearestAircraftComplication()
} timeline: {
    ComplicationSamples.entry
    ComplicationSamples.clearEntry
}

#Preview("Sky Radar", as: .accessoryCircular) {
    SkyRadarComplication()
} timeline: {
    ComplicationSamples.entry
}

#Preview("Next Overhead", as: .accessoryRectangular) {
    NextOverheadComplication()
} timeline: {
    ComplicationSamples.entry
    ComplicationSamples.passingEntry
}

#Preview("Identify", as: .accessoryCircular) {
    IdentifyComplication()
} timeline: {
    IdentifyEntry(date: Date())
}
