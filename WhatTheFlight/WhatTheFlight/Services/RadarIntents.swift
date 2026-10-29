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
            return .result(dialog: "Open What The Flight? once so I know where you're watching from.", view: OverheadSnippet(flight: nil, count: 0))
        }
        let contacts: [RadarContact]
        do {
            contacts = try await NearbyTraffic.contacts(around: observer, radiusMiles: store.radiusMiles)
        } catch {
            return .result(dialog: "I couldn't reach Flightradar24 just now. Try again in a moment.", view: OverheadSnippet(flight: nil, count: 0))
        }
        guard let nearest = contacts.first else {
            return .result(dialog: "Clear skies — nothing's flying within \(RadarFormat.spokenDistance(store.radiusMiles)) of you.", view: OverheadSnippet(flight: nil, count: 0))
        }
        return .result(dialog: IntentDialog(stringLiteral: Self.sentence(for: nearest)),
                       view: OverheadSnippet(flight: SnapshotFlight(nearest), count: contacts.count))
    }

    static func sentence(for contact: RadarContact) -> String {
        SpokenTraffic.siriAnswer(for: contact)
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
        AppShortcut(intent: SeenBeforeIntent(), phrases: [
            "Have I seen this plane before in \(.applicationName)",
            "Is that plane in my \(.applicationName) logbook",
            "Have I seen that plane with \(.applicationName)",
        ], shortTitle: "Seen It Before?", systemImageName: "book.and.wrench")
        AppShortcut(intent: LogbookTodayIntent(), phrases: [
            "How many planes have I seen today in \(.applicationName)",
            "What have I spotted today in \(.applicationName)",
        ], shortTitle: "Planes Today", systemImageName: "binoculars")
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
                    Text([f.typeName, "\(RadarFormat.distanceText(f.distanceMiles)) \(GeoMath.cardinal(f.bearing))",
                          "\(RadarFormat.altitudeText(f.altitudeFeet))"].compactMap { $0 }.joined(separator: " · "))
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
