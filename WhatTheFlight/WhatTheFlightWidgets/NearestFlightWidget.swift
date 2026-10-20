//
//  NearestFlightWidget.swift
//  WhatTheFlightWidgets
//
//  "What's overhead?" on the Home Screen and Lock Screen. The widget fetches fresh traffic
//  around the spot the app last watched (shared through the App Group) and falls back to
//  the app's own snapshot when the network is out.
//

import WidgetKit
import SwiftUI
import CoreLocation

struct NearestFlightEntry: TimelineEntry {
    let date: Date
    let snapshot: RadarSnapshot?
    /// The app has never told us where to watch.
    var needsSetup = false
}

struct NearestFlightProvider: TimelineProvider {
    func placeholder(in context: Context) -> NearestFlightEntry {
        NearestFlightEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NearestFlightEntry) -> Void) {
        if context.isPreview {
            completion(NearestFlightEntry(date: Date(), snapshot: .sample))
            return
        }
        Task { completion(await entry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NearestFlightEntry>) -> Void) {
        Task {
            let entry = await entry()
            // Air traffic changes fast, but widget refreshes are rationed: ask every 15 min.
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func entry() async -> NearestFlightEntry {
        let store = SharedRadarStore()
        guard store.observer != nil else {
            return NearestFlightEntry(date: Date(), snapshot: store.snapshot, needsSetup: store.snapshot == nil)
        }
        return NearestFlightEntry(date: Date(), snapshot: await NearbyTraffic.latestSnapshot(store: store))
    }
}

struct NearestFlightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedRadarStore.widgetKind, provider: NearestFlightProvider()) { entry in
            NearestFlightView(entry: entry)
                .containerBackground(for: .widget) { Palette.paper }
        }
        .configurationDisplayName("Overhead")
        .description("The nearest aircraft to you, and what else is in the sky.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - Views

struct NearestFlightView: View {
    let entry: NearestFlightEntry
    @Environment(\.widgetFamily) private var family

    private var flights: [SnapshotFlight] { entry.snapshot?.flights ?? [] }
    private var nearest: SnapshotFlight? { flights.first }

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
        .widgetURL(nearest.map { AppRouter.url(for: .flight($0.id)) } ?? AppRouter.url(for: .radar))
    }

    // MARK: Lock Screen

    @ViewBuilder
    private var inline: some View {
        if let f = nearest {
            Text("\(Image(systemName: "airplane")) \(f.identifier) · \(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
        } else {
            Text("\(Image(systemName: "sun.haze")) Clear skies")
        }
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .bold))
                Text("\(entry.snapshot?.inRangeCount ?? 0)")
                    .font(.mono(18, .heavy))
                    .minimumScaleFactor(0.6)
            }
        }
        .accessibilityLabel("\(entry.snapshot?.inRangeCount ?? 0) aircraft in range")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let f = nearest {
                HStack(spacing: 4) {
                    Image(systemName: f.isHelicopter ? "fan.fill" : "airplane")
                    Text(f.identifier).font(.mono(15, .heavy))
                    if let tag = f.notableTag { Image(systemName: tag.symbol) }
                }
                Text(f.route ?? f.operatorName)
                    .font(.mono(12, .semibold))
                    .lineLimit(1)
                Text("\(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing)) · \(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                    .font(.mono(11))
                    .lineLimit(1)
            } else {
                Label("Clear skies", systemImage: "sun.haze").font(.mono(14, .bold))
                Text(entry.needsSetup ? "Open WhatTheFlight to start" : "Nothing in range")
                    .font(.mono(11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            Spacer(minLength: 4)
            if let f = nearest {
                hero(f, size: 26)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                header
                Spacer(minLength: 4)
                if let f = nearest { hero(f, size: 28) } else { empty }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            if flights.count > 1 {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Also up there")
                        .font(.mono(9, .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.caption)
                    ForEach(flights.dropFirst().prefix(3)) { f in
                        Link(destination: AppRouter.url(for: .flight(f.id))) {
                            HStack(spacing: 6) {
                                Image(systemName: f.isHelicopter ? "fan.fill" : "airplane")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(f.notableTag.map(Palette.color(for:)) ?? Palette.blip)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(f.identifier).font(.mono(12, .bold)).foregroundStyle(Palette.ink)
                                    Text(f.route ?? f.typeName ?? f.operatorName)
                                        .font(.mono(9))
                                        .foregroundStyle(Palette.caption)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                Text("\(RadarFormat.miles(f.distanceMiles)) mi")
                                    .font(.mono(11, .bold))
                                    .foregroundStyle(Palette.value)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(entry.snapshot == nil ? Palette.warning : Palette.live)
                .frame(width: 6, height: 6)
            Text("\(entry.snapshot?.inRangeCount ?? 0) in range")
                .font(.mono(10, .bold))
                .foregroundStyle(Palette.caption)
            Spacer(minLength: 0)
            if let date = entry.snapshot?.date {
                Text(date, style: .time)
                    .font(.mono(9))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    private func hero(_ f: SnapshotFlight, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let badge = f.notableBadge, let tag = f.notableTag {
                Text(badge)
                    .font(.mono(8, .heavy))
                    .foregroundStyle(Palette.color(for: tag))
            }
            Text(f.operatorName)
                .font(.mono(9, .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
            Text(f.identifier)
                .font(.mono(size, .heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let route = f.route {
                Text(route)
                    .font(.mono(13, .bold))
                    .foregroundStyle(Palette.route)
            } else if let type = f.typeName {
                Text(type)
                    .font(.mono(11))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.signal)
                    .rotationEffect(.degrees(f.bearing))
                Text("\(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))")
                Text("·")
                Text("\(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
            }
            .font(.mono(10, .semibold))
            .foregroundStyle(Palette.value)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, 2)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: entry.needsSetup ? "location.slash" : "sun.haze")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.ink)
            Text(entry.needsSetup ? "Where are you?" : "Clear skies")
                .font(.mono(15, .bold))
                .foregroundStyle(Palette.ink)
            Text(entry.needsSetup ? "Open WhatTheFlight once to start." : "Nothing airborne nearby.")
                .font(.mono(10))
                .foregroundStyle(Palette.caption)
        }
    }
}

// MARK: - Sample

extension RadarSnapshot {
    static var sample: RadarSnapshot {
        let observer = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
        func contact(_ id: String, _ number: String, _ callsign: String, _ airline: String, _ type: String,
                     _ from: String, _ to: String, miles: Double, bearing: Double, altitude: Int) -> RadarContact {
            let p = GeoMath.destination(from: observer, bearingDegrees: bearing, distanceMiles: miles)
            let flight = Flight(id: id, hex: nil, latitude: p.latitude, longitude: p.longitude, track: 200,
                                altitudeFeet: altitude, groundSpeedKnots: 300, verticalRateFPM: 0, squawk: nil,
                                typeCode: type, registration: nil, originIATA: from, destinationIATA: to,
                                flightNumber: number, callsign: callsign, airlineICAO: airline, isOnGround: false,
                                positionTime: Date())
            return RadarContact(flight: flight, observer: observer, at: Date())
        }
        return RadarSnapshot(placeName: "Atlanta", radiusMiles: 20, contacts: [
            contact("s1", "DL570", "DAL570", "DAL", "B752", "SFO", "ATL", miles: 1.6, bearing: 30, altitude: 9_500),
            contact("s2", "WN2533", "SWA2533", "SWA", "B737", "BNA", "ATL", miles: 6, bearing: 300, altitude: 11_800),
            contact("s3", "EK211", "UAE211", "UAE", "A388", "DXB", "IAH", miles: 12, bearing: 120, altitude: 39_000),
            contact("s4", "AA1385", "AAL1385", "AAL", "A321", "CLT", "DFW", miles: 15, bearing: 80, altitude: 34_000),
        ])
    }
}
