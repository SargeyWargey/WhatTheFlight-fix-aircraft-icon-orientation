//
//  LogbookAnswers.swift
//  WhatTheFlight
//
//  What Siri says about the logbook: "Have I seen this plane before?" and "How many planes
//  have I seen today?". Pure, so the wording is tested; the intents are in
//  `Services/LogbookIntents.swift`.
//

import Foundation

enum LogbookAnswers {
    /// Tail numbers without hyphens or spaces, uppercased: "g-xlei" → "GXLEI".
    static func normalize(_ text: String) -> String {
        text.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Every sighting of the aircraft or flight `query` names, oldest first: by tail number,
    /// ICAO hex, callsign or flight number.
    static func matches(_ query: String, in sightings: [Sighting]) -> [Sighting] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        return sightings.filter { s in
            [s.registration, s.hex, s.callsign, s.displayIdentifier].contains { $0.map(normalize) == q }
        }
    }

    /// "Yes. You've seen N608AT 4 times, most recently on October 3. The first time was
    /// September 12." Leaves out `excluding` (the sighting being logged right now).
    static func seenBefore(_ query: String, label: String? = nil, in sightings: [Sighting], excluding: String? = nil,
                           calendar: Calendar = .current) -> String {
        let name = label ?? query.uppercased()
        let earlier = matches(query, in: sightings).filter { $0.id != excluding }
        guard let first = earlier.first, let last = earlier.last else {
            return "No, \(name) isn't in your logbook yet."
        }
        func day(_ date: Date) -> String {
            calendar.isDateInToday(date) ? "earlier today"
                : calendar.isDateInYesterday(date) ? "yesterday"
                : "on \(date.formatted(.dateTime.month(.wide).day()))"
        }
        if earlier.count == 1 {
            return "Yes, once before: \(day(first.firstSeen))\(first.placeName.map { ", from \($0)" } ?? "")."
        }
        return "Yes. You've seen \(name) \(earlier.count) times, most recently \(day(last.firstSeen)). The first time was \(day(first.firstSeen))."
    }

    /// "You've logged 42 aircraft today, including 2 new types. The closest was N44RH at 0.3 miles."
    static func today(_ recap: DailyRecap) -> String {
        guard !recap.isEmpty else { return "Nothing logged yet today." }
        var sentence = "You've logged \(RadarFormat.wholeNumber(recap.total)) \(recap.total == 1 ? "aircraft" : "aircraft") today"
        var extras: [String] = []
        if !recap.newTypes.isEmpty { extras.append(recap.newTypes.count == 1 ? "a new type" : "\(recap.newTypes.count) new types") }
        if !recap.newAirlines.isEmpty { extras.append(recap.newAirlines.count == 1 ? "a new airline" : "\(recap.newAirlines.count) new airlines") }
        if !recap.notable.isEmpty { extras.append(recap.notable.count == 1 ? "one notable aircraft" : "\(recap.notable.count) notable aircraft") }
        if !extras.isEmpty { sentence += ", including " + list(extras) }
        sentence += "."
        if let closest = recap.closest {
            sentence += " The closest was \(SpokenTraffic.spelled(closest.displayIdentifier)) at \(closest.closestMiles < 1 ? RadarFormat.preciseDistance(closest.closestMiles) : RadarFormat.spokenDistance(closest.closestMiles))."
        }
        return sentence
    }

    /// "a, b and c".
    static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
        }
    }
}
