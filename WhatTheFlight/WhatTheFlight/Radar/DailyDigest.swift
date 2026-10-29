//
//  DailyDigest.swift
//  WhatTheFlight
//
//  The evening notification about the day's sky (Enhancements Spec C9): "Today: 142
//  aircraft · 3 new types · closest N44RH at 0.3 mi". Worded here, scheduled by the iPhone
//  app (`Services/DigestNotifier.swift`).
//

import Foundation

enum DailyDigest {
    /// Minutes after midnight the digest goes out unless changed: 8 pm.
    static let defaultMinutes = 20 * 60

    struct Message: Equatable, Sendable {
        let title: String
        let body: String
    }

    /// Nil for a day without sightings: no digest then.
    static func message(for recap: DailyRecap) -> Message? {
        guard !recap.isEmpty else { return nil }
        var parts = ["\(RadarFormat.wholeNumber(recap.total)) aircraft"]
        if !recap.newTypes.isEmpty {
            parts.append(recap.newTypes.count == 1 ? "1 new type" : "\(recap.newTypes.count) new types")
        }
        if !recap.newAirlines.isEmpty {
            parts.append(recap.newAirlines.count == 1 ? "1 new airline" : "\(recap.newAirlines.count) new airlines")
        }
        if let closest = recap.closest {
            parts.append("closest \(closest.displayIdentifier) at \(RadarFormat.preciseDistance(closest.closestMiles))")
        }
        let title: String
        if let first = recap.newTypes.first, let name = first.typeName ?? first.typeCode {
            title = "Today in the sky: your first \(name)"
        } else if let notable = recap.notable.first {
            title = "Today in the sky: \(notable.displayIdentifier) and more"
        } else {
            title = "Today in the sky"
        }
        return Message(title: title, body: parts.joined(separator: " · "))
    }

    /// When today's digest goes out, if that's still ahead.
    static func fireDate(minutes: Int, on day: Date = Date(), calendar: Calendar = .current) -> Date? {
        let start = calendar.startOfDay(for: day)
        guard let date = calendar.date(byAdding: .minute, value: minutes, to: start), date > day else { return nil }
        return date
    }
}
