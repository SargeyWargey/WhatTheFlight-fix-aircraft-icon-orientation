//
//  SkyWatchAttributes.swift
//  WhatTheFlight
//
//  The Sky Watch Live Activity's data, shared by the app (which starts and updates it) and
//  the widget extension (which draws it on the Lock Screen and in the Dynamic Island).
//

#if os(iOS)
import Foundation
import ActivityKit
import AppIntents

struct SkyWatchAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The aircraft to watch: the nearest one that's still approaching, else the nearest.
        var flight: SnapshotFlight?
        /// When it passes closest, if it's still approaching.
        var passAt: Date?
        var inRangeCount: Int
        var updatedAt: Date
    }

    var placeName: String
    var radiusMiles: Int
    var endsAt: Date
}

/// "Stop" on the Live Activity. Runs in the app's process.
struct StopSkyWatchIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Sky Watch"
    static let description = IntentDescription("Ends the Sky Watch Live Activity and its alerts.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await SkyWatch.shared.stop()
        #endif
        return .result()
    }
}
#endif
