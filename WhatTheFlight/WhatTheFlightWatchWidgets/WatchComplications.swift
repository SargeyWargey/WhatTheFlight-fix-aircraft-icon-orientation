//
//  WatchComplications.swift
//  WhatTheFlightWatchWidgets
//
//  Watch face complications and the Smart Stack: the nearest aircraft, which way it is and
//  when it passes closest. Complications reload only a few times an hour, so each timeline
//  dead-reckons the traffic forward a minute at a time for five minutes, then admits it
//  needs a refresh rather than inventing positions.
//

import WidgetKit
import SwiftUI
import CoreLocation

@main
struct WhatTheFlightWatchWidgets: WidgetBundle {
    var body: some Widget {
        OverheadComplication()
    }
}

struct OverheadEntry: TimelineEntry {
    let date: Date
    let snapshot: RadarSnapshot?
    var needsSetup = false
    /// Past the projection horizon: the positions would be guesses.
    var isStale = false
    var relevance: TimelineEntryRelevance?

    var nearest: SnapshotFlight? { isStale ? nil : snapshot?.flights.first }

    /// When the nearest aircraft passes closest, if it's still approaching.
    var passAt: Date? {
        guard let f = nearest, let seconds = f.closestPassSeconds, let snapshot else { return nil }
        return snapshot.date.addingTimeInterval(seconds)
    }
}

struct OverheadProvider: TimelineProvider {
    static let steps = 6
    static let step: TimeInterval = 60

    func placeholder(in context: Context) -> OverheadEntry {
        OverheadEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (OverheadEntry) -> Void) {
        if context.isPreview {
            completion(OverheadEntry(date: Date(), snapshot: .sample))
            return
        }
        Task { completion(await entries().first ?? OverheadEntry(date: Date(), snapshot: nil)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OverheadEntry>) -> Void) {
        Catalogs.warmUp()
        Task { completion(Timeline(entries: await entries(), policy: .atEnd)) }
    }

    private func entries() async -> [OverheadEntry] {
        let store = SharedRadarStore()
        let now = Date()
        guard let observer = store.observer else {
            return [OverheadEntry(date: now, snapshot: store.snapshot, needsSetup: store.snapshot == nil)]
        }
        guard let flights = try? await NearbyTraffic.flights(around: observer, radiusMiles: store.radiusMiles) else {
            // Offline: show what the app last saw, once.
            return [OverheadEntry(date: now, snapshot: store.snapshot),
                    OverheadEntry(date: now.addingTimeInterval(Self.step), snapshot: store.snapshot, isStale: true)]
        }
        let snapshots = NearbyTraffic.projectedSnapshots(flights, observer: observer, radiusMiles: store.radiusMiles,
                                                         placeName: store.placeName, start: now,
                                                         count: Self.steps, step: Self.step)
        var result = snapshots.map { OverheadEntry(date: $0.date, snapshot: $0, relevance: Self.relevance(for: $0)) }
        let end = now.addingTimeInterval(Double(Self.steps) * Self.step)
        result.append(OverheadEntry(date: end, snapshot: snapshots.last, isStale: true))
        return result
    }

    /// Push the Smart Stack card up when something is about to pass or worth a look.
    static func relevance(for snapshot: RadarSnapshot) -> TimelineEntryRelevance {
        let soon = snapshot.flights.contains { ($0.closestPassSeconds ?? .infinity) < 180 && ($0.closestPassMiles ?? .infinity) < 2 }
        let notable = snapshot.flights.contains { $0.notableTag != nil }
        let score: Float = soon ? 80 : notable ? 60 : snapshot.inRangeCount > 0 ? 10 : 0
        return TimelineEntryRelevance(score: score, duration: Self.step)
    }
}

struct OverheadComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchOverhead", provider: OverheadProvider()) { entry in
            OverheadComplicationView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(entry.nearest.map { URL(string: "whattheflight://flight/\($0.id)")! })
        }
        .configurationDisplayName("Overhead")
        .description("The nearest aircraft, where to look, and when it passes closest.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Views

struct OverheadComplicationView: View {
    let entry: OverheadEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        case .accessoryInline: inline
        default: rectangular
        }
    }

    private var glyph: String { entry.nearest?.isHelicopter == true ? "fan.fill" : "airplane" }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let f = entry.nearest {
                // North-up: a complication can't know which way the wrist faces.
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(f.bearing))
                    .offset(x: sin(f.bearing.radians) * 17, y: -cos(f.bearing.radians) * 17)
                VStack(spacing: -2) {
                    Text(RadarFormat.miles(f.distanceMiles))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.6)
                    Text("mi").font(.system(size: 8, weight: .semibold))
                }
            } else {
                Image(systemName: entry.isStale ? "arrow.clockwise" : (entry.needsSetup ? "airplane" : "sun.haze"))
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .widgetAccentable()
    }

    private var corner: some View {
        Image(systemName: glyph)
            .font(.system(size: 20, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                if let f = entry.nearest {
                    Text("\(f.identifier) · \(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
                } else {
                    Text(statusText)
                }
            }
    }

    private var inline: some View {
        if let f = entry.nearest {
            Text("\(Image(systemName: glyph)) \(f.identifier) \(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
        } else {
            Text("\(Image(systemName: "airplane")) \(statusText)")
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let f = entry.nearest {
                HStack(spacing: 4) {
                    Image(systemName: glyph).widgetAccentable()
                    Text(f.identifier).font(.system(.headline, design: .monospaced)).widgetAccentable()
                    if let route = f.route {
                        Text(route).font(.system(size: 11, weight: .semibold, design: .monospaced)).lineLimit(1)
                    }
                }
                Text("\(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing)) · \(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let passAt = entry.passAt, passAt > entry.date {
                    HStack(spacing: 3) {
                        Text("Closest in")
                        Text(timerInterval: entry.date...passAt, countsDown: true).monospacedDigit()
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                } else if let count = entry.snapshot?.inRangeCount, count > 1 {
                    Text("+\(count - 1) more in range")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("What The Flight?", systemImage: "airplane")
                    .font(.system(.headline, design: .monospaced))
                    .widgetAccentable()
                Text(statusText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        if entry.needsSetup { return "Open the app" }
        if entry.isStale { return "Open to refresh" }
        if let radius = entry.snapshot?.radiusMiles { return "Clear within \(Int(radius)) mi" }
        return "Clear skies"
    }
}

extension RadarSnapshot {
    static var sample: RadarSnapshot {
        let observer = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
        let position = GeoMath.destination(from: observer, bearingDegrees: 40, distanceMiles: 2)
        let flight = Flight(id: "sample", hex: nil, latitude: position.latitude, longitude: position.longitude, track: 225,
                            altitudeFeet: 30_000, groundSpeedKnots: 300, verticalRateFPM: 0, squawk: nil, typeCode: "B752",
                            registration: "N685DA", originIATA: "SFO", destinationIATA: "ATL", flightNumber: "DL570",
                            callsign: "DAL570", airlineICAO: "DAL", isOnGround: false, positionTime: Date())
        return RadarSnapshot(placeName: "Here", radiusMiles: 10,
                             contacts: [RadarContact(flight: flight, observer: observer, at: Date())])
    }
}
