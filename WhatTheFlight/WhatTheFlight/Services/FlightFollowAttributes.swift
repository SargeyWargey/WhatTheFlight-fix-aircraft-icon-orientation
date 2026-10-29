//
//  FlightFollowAttributes.swift
//  WhatTheFlight
//
//  "Follow on Lock Screen": a Live Activity for one flight, wherever it is. Shared by the
//  app (`FlightFollow`, which starts and updates it) and the widget extension (which draws
//  it). The arrival countdown and progress bar are timer-driven, so they keep moving between
//  updates, which only arrive while the app runs (in the foreground, or with Sky Watch on).
//

#if os(iOS)
import Foundation
import ActivityKit
import AppIntents

struct FlightFollowAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var altitudeFeet: Int
        var speedKnots: Int
        var remainingMiles: Double?
        /// When it took off (worked out from distance flown) and when it lands, at the current
        /// ground speed: the progress bar runs between them.
        var departedAt: Date?
        var arrivesAt: Date?
        /// "Cruising · 2h 05m to DFW".
        var phase: String?
        var distanceFromYouMiles: Double?
        var hasLanded: Bool
        var updatedAt: Date
    }

    var flightID: String
    var identifier: String
    var operatorName: String
    var originIATA: String?
    var originCity: String?
    var destinationIATA: String?
    var destinationCity: String?
    var typeName: String?
    var silhouette: AircraftSilhouette
}

/// "Stop" on the Live Activity. Runs in the app's process.
struct StopFollowingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Following"
    static let description = IntentDescription("Ends the flight's Live Activity.")

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await FlightFollow.shared.stop()
        #endif
        return .result()
    }
}
#endif
