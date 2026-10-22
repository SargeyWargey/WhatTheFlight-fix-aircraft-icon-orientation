//
//  WatchIntents.swift
//  WhatTheFlightWatch
//
//  Siri on the Watch. "What's that plane?" answers without opening the app, from where the
//  Watch radar last watched; "Identify a plane" opens Identify, ready to point.
//

import AppIntents
import Foundation

struct WatchWhatsOverheadIntent: AppIntent {
    static let title: LocalizedStringResource = "What's That Plane?"
    static let description = IntentDescription("Tells you about the aircraft nearest to you right now.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = SharedRadarStore()
        guard let observer = store.observer else {
            return .result(dialog: "Open What The Flight? on your Watch once so I know where you are.")
        }
        let contacts: [RadarContact]
        do {
            contacts = try await NearbyTraffic.contacts(around: observer, radiusMiles: store.radiusMiles)
        } catch {
            return .result(dialog: "I couldn't reach Flightradar24 just now. Try again in a moment.")
        }
        guard let nearest = contacts.first else {
            return .result(dialog: "Clear skies — nothing's flying within \(Int(store.radiusMiles)) miles of you.")
        }
        return .result(dialog: IntentDialog(stringLiteral: SpokenTraffic.siriAnswer(for: nearest)))
    }
}

struct IdentifyPlaneIntent: AppIntent {
    static let title: LocalizedStringResource = "Identify a Plane"
    static let description = IntentDescription("Point at an aircraft you can see and the Watch tells you what it is.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRouter.shared.pending = .identify
        return .result()
    }
}

struct WatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WatchWhatsOverheadIntent(), phrases: [
            "What's that plane in \(.applicationName)",
            "What's flying over me in \(.applicationName)",
        ], shortTitle: "What's That Plane?", systemImageName: "airplane")
        AppShortcut(intent: IdentifyPlaneIntent(), phrases: [
            "Identify a plane in \(.applicationName)",
            "What am I pointing at in \(.applicationName)",
        ], shortTitle: "Identify", systemImageName: "hand.point.up.left.fill")
    }
}
