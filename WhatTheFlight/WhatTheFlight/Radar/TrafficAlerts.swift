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
    /// The aircraft as it was when the alert fired, for richer notifications (Apple Watch).
    var flight: SnapshotFlight? = nil

    var id: String { "\(flightID)-\(reason.rawValue)" }
}

/// How traffic alerts travel as notifications: the iPhone posts them, Apple Watch draws its
/// own long-look for the category and offers Point & Find from the action.
enum TrafficNotification {
    static let category = "wtf.traffic"
    static let flightIDKey = "flightID"
    /// A `SnapshotFlight` as a JSON string.
    static let flightKey = "flight"
    static let findAction = "wtf.find"

    static func flight(from userInfo: [AnyHashable: Any]) -> SnapshotFlight? {
        let value = userInfo[flightKey]
        guard let data = (value as? String).map({ Data($0.utf8) }) ?? (value as? Data) else { return nil }
        return try? JSONDecoder().decode(SnapshotFlight.self, from: data)
    }
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
        let profile = contact.profile
        let name = f.displayIdentifier
        let what = profile.typeName ?? f.typeCode ?? (profile.kind == .helicopter ? "Helicopter" : "Aircraft")
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
                    body: "\(what) at \(RadarFormat.wholeNumber(contact.altitudeFeet)) ft — look \(GeoMath.cardinal(contact.bearing))\(f.hasRoute ? ", \(f.originIATA ?? "") → \(f.destinationIATA ?? "")" : "").",
                    symbol: "scope",
                    flight: SnapshotFlight(contact)
                ))
            }
        }

        if rules.notable, let top = profile.notable.first {
            result.append(TrafficAlert(
                flightID: f.id, reason: .notable,
                title: "\(name) \(top.reason)",
                body: "\(what), \(RadarFormat.miles(contact.distanceMiles)) mi \(GeoMath.cardinal(contact.bearing)) at \(RadarFormat.wholeNumber(contact.altitudeFeet)) ft.",
                symbol: top.tag.symbol,
                flight: SnapshotFlight(contact)
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
        let altitude = "\(RadarFormat.wholeNumber(Int((Double(contact.altitudeFeet) / 100).rounded()) * 100)) feet"
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

    /// The ambient map's VoiceOver label: "DL570, Delta Air Lines, 3 miles northeast, 30,000 feet".
    static func mapLabel(for contact: RadarContact) -> String {
        let f = contact.flight
        let where_ = contact.distanceMiles < 0.5 ? "overhead" : "\(RadarFormat.miles(contact.distanceMiles)) miles \(direction(contact.bearing))"
        return "\(f.displayIdentifier), \(contact.profile.operatorInfo.title), \(where_), \(RadarFormat.wholeNumber(contact.altitudeFeet)) feet"
    }

    static func direction(_ bearing: Double) -> String {
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

// MARK: - Siri

extension SpokenTraffic {
    /// Point & Find's call-out: "Delta Air Lines flight 570, San Francisco to Atlanta. A Boeing
    /// 757-200 at 30,000 feet, 8 miles southwest."
    static func identification(for contact: RadarContact) -> String {
        let f = contact.flight
        var first = spokenName(f)
        if let from = f.origin?.city, let to = f.destination?.city { first += ", \(from) to \(to)" }
        let altitude = "\(RadarFormat.wholeNumber(Int((Double(contact.altitudeFeet) / 100).rounded()) * 100)) feet"
        let where_ = contact.distanceMiles < 0.5 ? "right overhead" : "\(RadarFormat.miles(contact.distanceMiles)) miles \(direction(contact.bearing))"
        let what = f.typeName.map { "A \($0)" } ?? (f.kind == .helicopter ? "A helicopter" : "An aircraft")
        var sentence = "\(first). \(what) at \(altitude), \(where_)."
        if let notable = f.notable.first { sentence += " It \(speakable(notable.reason))." }
        return sentence
    }

    /// "That's Delta Air Lines DL570, a Boeing 757-200 from San Francisco to Atlanta. It's
    /// 2 miles north at 30,000 feet, and passes closest in about a minute."
    static func siriAnswer(for contact: RadarContact) -> String {
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
        var sentence = "That's \(who). It's \(miles) at \(RadarFormat.wholeNumber(contact.altitudeFeet)) feet"
        if contact.isApproaching, contact.closestApproach.secondsFromNow < 900 {
            let minutes = Int((contact.closestApproach.secondsFromNow / 60).rounded())
            sentence += minutes < 1 ? ", and it's about to pass closest" : ", and passes closest in about \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        if let notable = f.notable.first { sentence += ". Heads up: it \(notable.reason)" }
        return sentence + "."
    }
}
