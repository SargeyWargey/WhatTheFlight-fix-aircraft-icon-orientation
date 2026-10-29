//
//  Watchlist.swift
//  WhatTheFlight
//
//  Aircraft to be told about when they turn up: a tail number, any aircraft of a type, an
//  airline, or a callsign prefix (Enhancements Spec C2). Stored in `RadarSettings.watchlist`,
//  sent to Apple Watch with the rest of the alert rules.
//

import Foundation

struct WatchlistRule: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case registration, type, airline, callsign

        var id: String { rawValue }

        var title: String {
            switch self {
            case .registration: return String(localized: "Tail number")
            case .type: return String(localized: "Aircraft type")
            case .airline: return String(localized: "Airline")
            case .callsign: return String(localized: "Callsign")
            }
        }

        var symbol: String {
            switch self {
            case .registration: return "number"
            case .type: return "airplane"
            case .airline: return "building.2"
            case .callsign: return "antenna.radiowaves.left.and.right"
            }
        }

        var placeholder: String {
            switch self {
            case .registration: return String(localized: "N685DA")
            case .type: return String(localized: "B748 or Boeing 747")
            case .airline: return String(localized: "QTR or Qatar Airways")
            case .callsign: return String(localized: "RCH")
            }
        }
    }

    var kind: Kind
    /// Uppercased: a registration without its hyphen, an ICAO type code ("B744"), an airline's
    /// ICAO code ("QTR"), or the start of a callsign ("RCH").
    var value: String

    var id: String { "\(kind.rawValue):\(value)" }

    init(kind: Kind, value: String) {
        self.kind = kind
        self.value = Self.normalize(value, kind: kind)
    }

    static func normalize(_ value: String, kind: Kind) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch kind {
        case .registration: return trimmed.replacingOccurrences(of: "-", with: "").filter { !$0.isWhitespace }
        case .type, .airline, .callsign: return trimmed.filter { !$0.isWhitespace }
        }
    }

    /// "Any type, airline or tail number" from free text: the code itself, or a name the
    /// catalogs know. Nil when nothing matches.
    static func resolve(_ text: String, kind: Kind) -> WatchlistRule? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        switch kind {
        case .registration, .callsign:
            return WatchlistRule(kind: kind, value: q)
        case .type:
            if AircraftTypeCatalog.name(forTypeCode: q.uppercased()) != nil { return WatchlistRule(kind: .type, value: q) }
            return AircraftTypeCatalog.search(q).first.map { WatchlistRule(kind: .type, value: $0.code) }
                ?? (q.count <= 4 ? WatchlistRule(kind: .type, value: q) : nil)
        case .airline:
            if AirlineCatalog.airline(icao: q.uppercased()) != nil { return WatchlistRule(kind: .airline, value: q) }
            return AirlineCatalog.search(q).first.map { WatchlistRule(kind: .airline, value: $0.icao) }
        }
    }

    /// "N685DA", "Boeing 747-8 (B748)", "Qatar Airways", "Callsign RCH…".
    var title: String {
        switch kind {
        case .registration: return value
        case .type: return AircraftTypeCatalog.name(forTypeCode: value).map { "\($0) (\(value))" } ?? value
        case .airline: return AirlineCatalog.airline(icao: value)?.name ?? value
        case .callsign: return "Callsign \(value)…"
        }
    }

    /// For sentences: "the Boeing 747-8", "Qatar Airways".
    var spokenTitle: String {
        switch kind {
        case .registration: return SpokenTraffic.spelled(value)
        case .type: return AircraftTypeCatalog.name(forTypeCode: value) ?? SpokenTraffic.spelled(value)
        case .airline: return AirlineCatalog.airline(icao: value)?.name ?? SpokenTraffic.spelled(value)
        case .callsign: return "callsign \(SpokenTraffic.spelled(value))"
        }
    }

    func matches(_ flight: Flight, airline: Airline?) -> Bool {
        switch kind {
        case .registration:
            let reg = flight.registration.map { Self.normalize($0, kind: .registration) }
            return reg == value || flight.hex?.uppercased() == value
        case .type:
            return flight.typeCode?.uppercased() == value
        case .airline:
            return (airline?.icao ?? flight.airlineICAO)?.uppercased() == value
        case .callsign:
            return flight.callsign?.uppercased().hasPrefix(value) == true
        }
    }
}

extension WatchlistRule {
    /// What a flight's details offer to watch for: its type, its airline, the airframe.
    static func suggestions(for flight: Flight, profile: FlightProfile) -> [WatchlistRule] {
        var result: [WatchlistRule] = []
        if let code = flight.typeCode, !code.isEmpty { result.append(WatchlistRule(kind: .type, value: code)) }
        if profile.operatorInfo.kind == .airline, let icao = profile.airline?.icao { result.append(WatchlistRule(kind: .airline, value: icao)) }
        if let reg = flight.registration, !reg.isEmpty { result.append(WatchlistRule(kind: .registration, value: reg)) }
        return result
    }

    /// "Any Boeing 757-200", "Any Delta Air Lines", "This aircraft, N685DA".
    func offerTitle(for flight: Flight) -> String {
        switch kind {
        case .type: return "Any \(AircraftTypeCatalog.name(forTypeCode: value) ?? value)"
        case .airline: return "Any \(title)"
        case .registration: return "This aircraft, \(flight.registration ?? value)"
        case .callsign: return title
        }
    }
}

extension Array where Element == WatchlistRule {
    /// The first rule this flight matches.
    func match(_ flight: Flight, airline: Airline?) -> WatchlistRule? {
        first { $0.matches(flight, airline: airline) }
    }
}
