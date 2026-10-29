//
//  ReadsbParser.swift
//  WhatTheFlight
//
//  Parses the readsb JSON the open ADS-B feeds share (adsb.lol and others):
//  `{ "now": ms, "ac": [ { "hex", "flight", "r", "t", "lat", "lon", "alt_baro", "gs",
//  "track", "baro_rate", "squawk", "seen_pos", … } ] }`. There are no routes or flight
//  numbers in it; a flight number is worked out from an airline callsign whose suffix is
//  all digits ("DAL1751" → "DL1751"), and the catalogs recover the airline.
//

import Foundation

enum ReadsbParser {
    enum ParseError: Error, Equatable {
        case notAnObject
    }

    /// Ids are the airframe's ICAO hex with this prefix, so they never collide with
    /// Flightradar24's per-leg flight ids.
    static let idPrefix = "ac-"

    /// `includeGround` keeps aircraft on the ground (lookups, "Where is it now?"); the radar
    /// leaves them out.
    static func parse(_ data: Data, receivedAt: Date = Date(), includeGround: Bool = false) throws -> [Flight] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else { throw ParseError.notAnObject }
        // The server's own clock, when it says, so `seen_pos` is measured against it; never
        // later than when the answer arrived.
        let now = (json["now"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }.map { min($0, receivedAt) } ?? receivedAt
        let aircraft = json["ac"] as? [[String: Any]] ?? json["aircraft"] as? [[String: Any]] ?? []
        return aircraft.compactMap { flight($0, now: now, includeGround: includeGround) }
    }

    static func flight(_ a: [String: Any], now: Date, includeGround: Bool) -> Flight? {
        guard let hex = (a["hex"] as? String)?.lowercased(), !hex.isEmpty,
              let latitude = number(a["lat"]), let longitude = number(a["lon"]),
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        let onGround = (a["alt_baro"] as? String) == "ground"
        guard includeGround || !onGround else { return nil }
        let altitude = onGround ? 0 : Int((number(a["alt_baro"]) ?? number(a["alt_geom"]) ?? 0).rounded())
        let callsign = (a["flight"] as? String)?.trimmingCharacters(in: .whitespaces).nilIfBlank
        let seen = max(0, number(a["seen_pos"]) ?? number(a["seen"]) ?? 0)
        let registration = (a["r"] as? String)?.trimmingCharacters(in: .whitespaces).nilIfBlank
        return Flight(
            id: idPrefix + hex.trimmingCharacters(in: CharacterSet(charactersIn: "~")),
            hex: hex.hasPrefix("~") ? nil : hex.uppercased(),
            latitude: latitude,
            longitude: longitude,
            track: number(a["track"]) ?? number(a["true_heading"]) ?? number(a["mag_heading"]) ?? 0,
            altitudeFeet: max(0, altitude),
            groundSpeedKnots: Int((number(a["gs"]) ?? 0).rounded()),
            verticalRateFPM: Int((number(a["baro_rate"]) ?? number(a["geom_rate"]) ?? 0).rounded()),
            squawk: (a["squawk"] as? String)?.nilIfBlank,
            typeCode: (a["t"] as? String)?.trimmingCharacters(in: .whitespaces).uppercased().nilIfBlank,
            registration: registration,
            originIATA: nil,
            destinationIATA: nil,
            flightNumber: flightNumber(callsign: callsign),
            callsign: callsign,
            // The callsign finds the airline, special words ("SAM", "LIFE") first.
            airlineICAO: nil,
            isOnGround: onGround,
            positionTime: now.addingTimeInterval(-seen)
        )
    }

    /// "DAL1751" → "DL1751". Only when the rest of the callsign is digits: "BAW29G" is sold
    /// as BA238, which no open data says.
    static func flightNumber(callsign: String?) -> String? {
        guard let callsign, let prefix = AirlineCatalog.icaoPrefix(ofCallsign: callsign),
              let iata = AirlineCatalog.airline(icao: prefix)?.iata, !iata.isEmpty else { return nil }
        let digits = callsign.dropFirst(prefix.count)
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return nil }
        // Leading zeros aren't part of a flight number: "UAL0012" is UA12.
        let number = String(digits.drop { $0 == "0" })
        return number.isEmpty ? nil : iata + number
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespaces).isEmpty ? nil : self }
}
