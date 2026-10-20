//
//  RadarIntents.swift
//  WhatTheFlight
//
//  Siri and Shortcuts. "What's that plane?" answers without opening the app, using the spot
//  the radar last watched; the others open the app to Sky View, the logbook or Sky Watch.
//

#if os(iOS)
import AppIntents
import SwiftUI

struct WhatsOverheadIntent: AppIntent {
    static let title: LocalizedStringResource = "What's That Plane?"
    static let description = IntentDescription("Tells you about the aircraft nearest to you right now.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = SharedRadarStore()
        guard let observer = store.observer else {
            return .result(dialog: "Open WhatTheFlight once so I know where you're watching from.", view: OverheadSnippet(flight: nil, count: 0))
        }
        let contacts: [RadarContact]
        do {
            contacts = try await NearbyTraffic.contacts(around: observer, radiusMiles: store.radiusMiles)
        } catch {
            return .result(dialog: "I couldn't reach Flightradar24 just now. Try again in a moment.", view: OverheadSnippet(flight: nil, count: 0))
        }
        guard let nearest = contacts.first else {
            return .result(dialog: "Clear skies — nothing's flying within \(Int(store.radiusMiles)) miles of you.", view: OverheadSnippet(flight: nil, count: 0))
        }
        return .result(dialog: IntentDialog(stringLiteral: Self.sentence(for: nearest)),
                       view: OverheadSnippet(flight: SnapshotFlight(nearest), count: contacts.count))
    }

    /// "That's Delta Air Lines DL570, a Boeing 757-200 from San Francisco to Atlanta. It's
    /// 2 miles north at 30,000 feet, and passes closest in about a minute."
    static func sentence(for contact: RadarContact) -> String {
        let f = contact.flight
        let info = f.operatorInfo
        var who = info.kind == .airline ? "\(info.title) \(f.displayIdentifier)" : "\(f.displayIdentifier), \(info.title.lowercased())"
        if let type = f.typeName ?? f.typeCode { who += ", a \(type)" }
        if let from = f.origin?.city ?? f.originIATA, let to = f.destination?.city ?? f.destinationIATA {
            who += " from \(from) to \(to)"
        }
        let direction = ["N": "north", "NE": "northeast", "E": "east", "SE": "southeast",
                         "S": "south", "SW": "southwest", "W": "west", "NW": "northwest"][GeoMath.cardinal(contact.bearing)] ?? ""
        let miles = contact.distanceMiles < 0.5 ? "right overhead" : "\(RadarFormat.miles(contact.distanceMiles)) miles \(direction)"
        var sentence = "That's \(who). It's \(miles) at \(RadarFormat.wholeNumber(f.altitudeFeet)) feet"
        if contact.isApproaching, contact.closestApproach.secondsFromNow < 900 {
            let minutes = Int((contact.closestApproach.secondsFromNow / 60).rounded())
            sentence += minutes < 1 ? ", and it's about to pass closest" : ", and passes closest in about \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        if let notable = f.notable.first { sentence += ". Heads up: it \(notable.reason)" }
        return sentence + "."
    }
}

struct OpenSkyViewIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sky View"
    static let description = IntentDescription("Point your camera at the sky to label every aircraft.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .sky
        return .result()
    }
}

struct OpenLogbookIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Logbook"
    static let description = IntentDescription("Shows every aircraft you've spotted.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .logbook
        return .result()
    }
}

struct StartSkyWatchIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Sky Watch"
    static let description = IntentDescription("Watch for aircraft from your Lock Screen and Dynamic Island, with overhead alerts.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.pending = .startSkyWatch
        return .result()
    }
}

struct WhatTheFlightShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WhatsOverheadIntent(), phrases: [
            "What's that plane in \(.applicationName)",
            "What's flying over me in \(.applicationName)",
            "Ask \(.applicationName) what's overhead",
        ], shortTitle: "What's That Plane?", systemImageName: "airplane")
        AppShortcut(intent: OpenSkyViewIntent(), phrases: [
            "Open Sky View in \(.applicationName)",
            "Show me the sky in \(.applicationName)",
        ], shortTitle: "Sky View", systemImageName: "camera.viewfinder")
        AppShortcut(intent: StartSkyWatchIntent(), phrases: [
            "Start Sky Watch in \(.applicationName)",
            "Watch the sky with \(.applicationName)",
        ], shortTitle: "Start Sky Watch", systemImageName: "dot.radiowaves.left.and.right")
        AppShortcut(intent: StopSkyWatchIntent(), phrases: [
            "Stop Sky Watch in \(.applicationName)",
        ], shortTitle: "Stop Sky Watch", systemImageName: "stop.circle")
        AppShortcut(intent: OpenLogbookIntent(), phrases: [
            "Show my \(.applicationName) logbook",
            "Open the logbook in \(.applicationName)",
        ], shortTitle: "Logbook", systemImageName: "book.closed")
    }
}

/// The card Siri shows under its answer.
struct OverheadSnippet: View {
    let flight: SnapshotFlight?
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: flight?.isHelicopter == true ? "fan.fill" : (flight == nil ? "sun.haze" : "airplane"))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.signal)
            if let f = flight {
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.operatorName)
                        .font(.mono(11, .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.caption)
                    HStack(spacing: 8) {
                        Text(f.identifier).font(.mono(24, .heavy)).foregroundStyle(Palette.ink)
                        if let route = f.route {
                            Text(route).font(.mono(14, .bold)).foregroundStyle(Palette.route)
                        }
                    }
                    Text([f.typeName, "\(RadarFormat.miles(f.distanceMiles)) mi \(GeoMath.cardinal(f.bearing))",
                          "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft"].compactMap { $0 }.joined(separator: " · "))
                        .font(.mono(12))
                        .foregroundStyle(Palette.value)
                    if count > 1 {
                        Text("+\(count - 1) more in range")
                            .font(.mono(10))
                            .foregroundStyle(Palette.caption)
                    }
                }
            } else {
                Text("Nothing to show")
                    .font(.mono(14, .semibold))
                    .foregroundStyle(Palette.caption)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
#endif
