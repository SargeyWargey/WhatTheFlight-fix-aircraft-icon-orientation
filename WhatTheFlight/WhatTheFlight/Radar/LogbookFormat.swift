//
//  LogbookFormat.swift
//  WhatTheFlight
//
//  How the logbook words durations, hours and compass directions. Shared with the iPhone
//  widgets and the Watch.
//

import Foundation

enum LogbookFormat {
    static func preciseMiles(_ miles: Double) -> String {
        RadarFormat.preciseDistance(miles)
    }

    /// "6 min", "1 h 05 min", "Under a min".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "Under a min" }
        if minutes < 60 { return "\(minutes) min" }
        return String(format: "%d h %02d min", minutes / 60, minutes % 60)
    }

    /// "7 AM", "12 PM".
    static func hour(_ hour: Int) -> String {
        switch hour % 24 {
        case 0: return "12 AM"
        case 12: return "12 PM"
        case let h where h < 12: return "\(h) AM"
        case let h: return "\(h - 12) PM"
        }
    }

    /// "7–8 AM", "11 AM–12 PM".
    static func hourRange(_ hour: Int) -> String {
        let start = Self.hour(hour), end = Self.hour(hour + 1)
        let sameHalf = (hour % 24 < 12) == ((hour + 1) % 24 < 12) && (hour + 1) % 24 != 12
        return sameHalf ? "\(start.split(separator: " ")[0])–\(end)" : "\(start)–\(end)"
    }

    /// "N", "NNE" … for a 16-point compass sector.
    static let sectorNames = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                              "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]

    /// "North", "North-northeast" … spelled out, in the same order.
    static let sectorWords = [
        String(localized: "North"), String(localized: "North-northeast"), String(localized: "Northeast"), String(localized: "East-northeast"),
        String(localized: "East"), String(localized: "East-southeast"), String(localized: "Southeast"), String(localized: "South-southeast"),
        String(localized: "South"), String(localized: "South-southwest"), String(localized: "Southwest"), String(localized: "West-southwest"),
        String(localized: "West"), String(localized: "West-northwest"), String(localized: "Northwest"), String(localized: "North-northwest"),
    ]

    /// Eight-way names for "mostly westbound".
    static func direction(_ degrees: Double) -> String {
        ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][Int(((GeoMath.normalize(degrees) + 22.5) / 45).rounded(.down)) % 8]
    }
}
