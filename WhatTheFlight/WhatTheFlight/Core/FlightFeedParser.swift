//
//  FlightFeedParser.swift
//  WhatTheFlight
//
//  Parses the Flightradar24 `feed.js` response. Each aircraft is a JSON array:
//
//   [0] ICAO hex     [1] latitude     [2] longitude   [3] track
//   [4] altitude ft  [5] speed kts    [6] squawk      [7] radar
//   [8] type code    [9] registration [10] timestamp  [11] origin IATA
//   [12] dest IATA   [13] flight no.  [14] on ground  [15] vertical rate fpm
//   [16] callsign    [17] glider flag [18] airline ICAO
//
//  Non-array keys (`full_count`, `version`, `stats`) are ignored.
//

import Foundation

enum FlightFeedParser {
    enum ParseError: Error, Equatable {
        case notAnObject
    }

    static func parse(_ data: Data, receivedAt: Date = Date()) throws -> [Flight] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let json = object as? [String: Any] else { throw ParseError.notAnObject }
        return parse(json: json, receivedAt: receivedAt)
    }

    static func parse(json: [String: Any], receivedAt: Date = Date()) -> [Flight] {
        json.compactMap { key, value in
            guard let fields = value as? [Any] else { return nil }
            return flight(id: key, fields: fields, receivedAt: receivedAt)
        }
    }

    static func flight(id: String, fields f: [Any], receivedAt: Date) -> Flight? {
        guard f.count >= 13,
              let latitude = number(f, 1), let longitude = number(f, 2),
              abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }

        // Prefer the feed's own timestamp, but never trust one from the future.
        var positionTime = receivedAt
        if let stamp = number(f, 10), stamp > 0 {
            positionTime = min(Date(timeIntervalSince1970: stamp), receivedAt)
        }

        return Flight(
            id: id,
            hex: string(f, 0),
            latitude: latitude,
            longitude: longitude,
            track: GeoMath.normalize(number(f, 3) ?? 0),
            altitudeFeet: Int(number(f, 4) ?? 0),
            groundSpeedKnots: Int(number(f, 5) ?? 0),
            verticalRateFPM: Int(number(f, 15) ?? 0),
            squawk: string(f, 6),
            typeCode: string(f, 8)?.uppercased(),
            registration: string(f, 9),
            originIATA: string(f, 11)?.uppercased(),
            destinationIATA: string(f, 12)?.uppercased(),
            flightNumber: string(f, 13),
            callsign: string(f, 16),
            airlineICAO: string(f, 18)?.uppercased(),
            isOnGround: (number(f, 14) ?? 0) != 0,
            positionTime: positionTime
        )
    }

    private static func number(_ fields: [Any], _ index: Int) -> Double? {
        guard index < fields.count else { return nil }
        switch fields[index] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func string(_ fields: [Any], _ index: Int) -> String? {
        guard index < fields.count, let s = fields[index] as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
