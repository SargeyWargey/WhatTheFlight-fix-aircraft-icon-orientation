//
//  TrafficAlerts.swift
//  WhatTheFlight
//
//  Decides when something deserves a heads-up: an aircraft about to pass overhead, or a
//  notable one (emergency, military, air ambulance, rare type) inside the radius. Each
//  aircraft alerts at most once per reason. How it's delivered (banner, notification,
//  Live Activity) is up to the platform.
//

import Foundation

struct TrafficAlert: Identifiable, Equatable, Sendable {
    enum Reason: String, Sendable { case overhead, notable }

    let flightID: String
    let reason: Reason
    let title: String
    let body: String
    let symbol: String

    var id: String { "\(flightID)-\(reason.rawValue)" }
}

struct TrafficAlertRules: Equatable, Sendable {
    var overhead = true
    var notable = true
    /// "Overhead" means the closest point of approach is within this many miles…
    var overheadMiles = 1.5
    /// …and is at most this far in the future.
    var leadSeconds: TimeInterval = 150
}

struct TrafficAlertEngine {
    private var alerted: [String: Date] = [:]

    mutating func evaluate(_ contacts: [RadarContact], rules: TrafficAlertRules, now: Date = Date()) -> [TrafficAlert] {
        // Forget aircraft we haven't heard about for half an hour.
        alerted = alerted.filter { now.timeIntervalSince($0.value) < 1800 }
        var alerts: [TrafficAlert] = []
        for contact in contacts {
            for alert in candidates(for: contact, rules: rules) {
                if alerted[alert.id] == nil { alerts.append(alert) }
                alerted[alert.id] = now
            }
        }
        return alerts
    }

    private func candidates(for contact: RadarContact, rules: TrafficAlertRules) -> [TrafficAlert] {
        let f = contact.flight
        let name = f.displayIdentifier
        let what = f.typeName ?? f.typeCode ?? (f.kind == .helicopter ? "Helicopter" : "Aircraft")
        var result: [TrafficAlert] = []

        if rules.overhead {
            let cpa = contact.closestApproach
            let soon = cpa.isAhead && cpa.secondsFromNow <= rules.leadSeconds && cpa.distanceMiles <= rules.overheadMiles
            let already = contact.distanceMiles <= min(0.75, rules.overheadMiles)
            if soon || already {
                let when = already ? "now" : "in \(RadarFormat.countdown(cpa.secondsFromNow))"
                result.append(TrafficAlert(
                    flightID: f.id, reason: .overhead,
                    title: "\(name) overhead \(when)",
                    body: "\(what) at \(RadarFormat.wholeNumber(f.altitudeFeet)) ft — look \(GeoMath.cardinal(contact.bearing))\(f.hasRoute ? ", \(f.originIATA ?? "") → \(f.destinationIATA ?? "")" : "").",
                    symbol: "scope"
                ))
            }
        }

        if rules.notable, let top = f.notable.first {
            result.append(TrafficAlert(
                flightID: f.id, reason: .notable,
                title: "\(name) \(top.reason)",
                body: "\(what), \(RadarFormat.miles(contact.distanceMiles)) mi \(GeoMath.cardinal(contact.bearing)) at \(RadarFormat.wholeNumber(f.altitudeFeet)) ft.",
                symbol: top.tag.symbol
            ))
        }
        return result
    }
}

// MARK: - Spoken alerts

/// Sentences for reading an alert aloud. Written for the ear: "Delta Air Lines flight 1199"
/// instead of "DL1199", tail numbers spelled out, no abbreviations or brackets.
enum SpokenTraffic {
    static func sentence(for contact: RadarContact, reason: TrafficAlert.Reason) -> String {
        let f = contact.flight
        let name = spokenName(f)
        let route: String = {
            guard let from = f.origin?.city, let to = f.destination?.city else { return "" }
            return ", from \(from) to \(to),"
        }()
        let what = f.typeName.map { ", a \($0)" } ?? ""
        let altitude = "\(RadarFormat.wholeNumber(Int((Double(f.altitudeFeet) / 100).rounded()) * 100)) feet"
        let look = "Look \(direction(contact.bearing))."

        switch reason {
        case .overhead:
            let cpa = contact.closestApproach
            let when: String
            if contact.distanceMiles <= 0.75 || !cpa.isAhead || cpa.secondsFromNow < 30 {
                when = "is passing overhead now"
            } else {
                let minutes = Int((cpa.secondsFromNow / 60).rounded())
                when = minutes <= 1 ? "is approaching overhead, about a minute away" : "is approaching overhead, about \(minutes) minutes away"
            }
            return "\(name)\(route) \(when), at \(altitude). \(look)"
        case .notable:
            let reasonText = f.notable.first.map { speakable($0.reason) } ?? "is nearby"
            return "Heads up. \(name)\(what) \(reasonText), \(RadarFormat.miles(contact.distanceMiles)) miles \(direction(contact.bearing)), at \(altitude)."
        }
    }

    /// "Delta Air Lines flight 1199", "Private aircraft N 5 4 0 4 T", "Air ambulance LIFE 2".
    static func spokenName(_ f: Flight) -> String {
        let info = f.operatorInfo
        if info.kind == .airline, let number = flightDigits(f) {
            return "\(info.title) flight \(number)"
        }
        let id = f.callsign ?? f.registration ?? f.displayIdentifier
        let title = info.kind == .unknown ? "Aircraft" : info.title
        return "\(title) \(spelled(id))"
    }

    /// The flight number without its airline code: "B61897" → "1897", "DAL570" → "570".
    /// Airline codes can contain digits (B6, 5X), so strip the code itself, not "letters".
    private static func flightDigits(_ f: Flight) -> String? {
        let number = f.flightNumber?.uppercased() ?? ""
        if let iata = f.airline?.iata, number.hasPrefix(iata), number.count > iata.count {
            return String(number.dropFirst(iata.count))
        }
        if let prefix = AirlineCatalog.icaoPrefix(ofCallsign: f.callsign) {
            return String(f.callsign!.uppercased().dropFirst(prefix.count))
        }
        return nil
    }

    /// Letters and digits one at a time, so "N5404T" isn't read as a word.
    static func spelled(_ id: String) -> String {
        id.uppercased().filter { $0.isLetter || $0.isNumber }.map(String.init).joined(separator: " ")
    }

    private static func direction(_ bearing: Double) -> String {
        ["N": "north", "NE": "northeast", "E": "east", "SE": "southeast",
         "S": "south", "SW": "southwest", "W": "west", "NW": "northwest"][GeoMath.cardinal(bearing)] ?? ""
    }

    /// "squawking 7700 (general emergency)" → "squawking 7 7 0 0, general emergency".
    private static func speakable(_ text: String) -> String {
        var t = text.replacingOccurrences(of: " (", with: ", ").replacingOccurrences(of: ")", with: "")
        for code in ["7500", "7600", "7700"] { t = t.replacingOccurrences(of: code, with: spelled(code)) }
        return t
    }
}
