//
//  FlightFeed.swift
//  WhatTheFlight
//
//  Live traffic sources. `FlightRadarFeed` talks to the unofficial Flightradar24 endpoint;
//  `DemoTrafficFeed` synthesises believable traffic for testing, previews and screenshots.
//

import Foundation
import CoreLocation

protocol FlightFeed: Sendable {
    func flights(in bounds: GeographicBounds) async throws -> [Flight]
}

enum FeedError: LocalizedError, Equatable {
    case offline
    case timedOut
    case rateLimited
    case http(Int)
    case badData

    var errorDescription: String? {
        switch self {
        case .offline: return "You're offline"
        case .timedOut: return "Flightradar24 took too long to answer"
        case .rateLimited: return "Flightradar24 is rate limiting us — slowing down"
        case .http(let code): return "Flightradar24 returned HTTP \(code)"
        case .badData: return "Flightradar24 sent data we couldn't read"
        }
    }
}

// MARK: - Flightradar24

struct FlightRadarFeed: FlightFeed {
    private let session: URLSession

    init(session: URLSession = FlightRadarFeed.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/json",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        return URLSession(configuration: config)
    }

    static func url(for bounds: GeographicBounds) -> URL? {
        url(bounds: bounds.boundsString, extra: [])
    }

    /// The whole world, narrowed to one airframe (`reg`) or flight (`callsign`). Ground
    /// traffic is included so a parked aircraft is found at its gate.
    static func locateURL(registration: String?, callsign: String?) -> URL? {
        let filter: URLQueryItem
        if let registration = registration?.trimmingCharacters(in: .whitespaces), !registration.isEmpty {
            filter = URLQueryItem(name: "reg", value: registration.uppercased())
        } else if let callsign = callsign?.trimmingCharacters(in: .whitespaces), !callsign.isEmpty {
            filter = URLQueryItem(name: "callsign", value: callsign.uppercased())
        } else {
            return nil
        }
        return url(bounds: "90,-90,-180,180", extra: [filter], ground: true)
    }

    private static func url(bounds: String, extra: [URLQueryItem], ground: Bool = false) -> URL? {
        var components = URLComponents(string: "https://data-cloud.flightradar24.com/zones/fcgi/feed.js")
        components?.queryItems = [
            URLQueryItem(name: "bounds", value: bounds),
            URLQueryItem(name: "faa", value: "1"),
            URLQueryItem(name: "satellite", value: "1"),
            URLQueryItem(name: "mlat", value: "1"),
            URLQueryItem(name: "flarm", value: "1"),
            URLQueryItem(name: "adsb", value: "1"),
            URLQueryItem(name: "gnd", value: ground ? "1" : "0"),
            URLQueryItem(name: "air", value: "1"),
            URLQueryItem(name: "vehicles", value: "0"),
            URLQueryItem(name: "estimated", value: "1"),
            URLQueryItem(name: "maxage", value: "14400"),
            URLQueryItem(name: "gliders", value: "1"),
            URLQueryItem(name: "stats", value: "0"),
        ] + extra
        return components?.url
    }

    func flights(in bounds: GeographicBounds) async throws -> [Flight] {
        guard let url = Self.url(for: bounds) else { throw FeedError.badData }
        return try await fetch(url)
    }

    /// Where this airframe (or, without a registration, this callsign) is right now,
    /// anywhere in the world. `nil` when it isn't transmitting.
    func locate(registration: String?, callsign: String?) async throws -> Flight? {
        guard let url = Self.locateURL(registration: registration, callsign: callsign) else { return nil }
        return try await fetch(url).max { $0.positionTime < $1.positionTime }
    }

    private func fetch(_ url: URL) async throws -> [Flight] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw FeedError.timedOut
            case .cancelled: throw CancellationError()
            default: throw FeedError.offline
            }
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw FeedError.rateLimited }
            guard (200..<300).contains(http.statusCode) else { throw FeedError.http(http.statusCode) }
        }
        do {
            return try FlightFeedParser.parse(data, receivedAt: Date())
        } catch {
            throw FeedError.badData
        }
    }
}

// MARK: - Demo traffic

/// Deterministic fake traffic that moves in real time around the centre of the query.
/// Used when "Demo traffic" is switched on, in previews and in UI tests.
struct DemoTrafficFeed: FlightFeed {
    private struct Seed {
        let number: String, callsign: String, airline: String, type: String, reg: String
        let from: String, to: String
        let bearing: Double, miles: Double, track: Double, speed: Double, altitude: Int, vs: Int
    }

    private static let seeds: [Seed] = [
        Seed(number: "DL570", callsign: "DAL570", airline: "DAL", type: "B752", reg: "N685DA", from: "SFO", to: "ATL", bearing: 20, miles: 1.2, track: 235, speed: 300, altitude: 30000, vs: -640),
        Seed(number: "WN2533", callsign: "SWA2533", airline: "SWA", type: "B737", reg: "N7854B", from: "BNA", to: "ATL", bearing: 300, miles: 9, track: 120, speed: 378, altitude: 11850, vs: -1200),
        Seed(number: "AA1385", callsign: "AAL1385", airline: "AAL", type: "A321", reg: "N111ZM", from: "CLT", to: "DFW", bearing: 75, miles: 16, track: 255, speed: 455, altitude: 34000, vs: 0),
        Seed(number: "UA902", callsign: "UAL902", airline: "UAL", type: "B789", reg: "N24976", from: "EWR", to: "IAH", bearing: 140, miles: 12, track: 215, speed: 470, altitude: 37000, vs: 0),
        Seed(number: "5X1303", callsign: "UPS1303", airline: "UPS", type: "B763", reg: "N353UP", from: "ATL", to: "SDF", bearing: 200, miles: 6, track: 1, speed: 290, altitude: 8000, vs: 3328),
        Seed(number: "DL1589", callsign: "DAL1589", airline: "DAL", type: "A339", reg: "N401DX", from: "ATL", to: "MIA", bearing: 250, miles: 18, track: 160, speed: 268, altitude: 5325, vs: 1536),
        Seed(number: "", callsign: "LIFE2", airline: "", type: "EC45", reg: "N145LF", from: "", to: "", bearing: 330, miles: 4, track: 80, speed: 120, altitude: 1500, vs: 0),
        Seed(number: "", callsign: "N44RH", airline: "", type: "R44", reg: "N44RH", from: "", to: "", bearing: 170, miles: 3, track: 300, speed: 95, altitude: 1100, vs: -200),
        Seed(number: "B6371", callsign: "JBU371", airline: "JBU", type: "A320", reg: "N533JB", from: "BOS", to: "MCO", bearing: 50, miles: 19, track: 190, speed: 440, altitude: 33000, vs: 0),
        Seed(number: "", callsign: "N172SP", airline: "", type: "C172", reg: "N172SP", from: "", to: "", bearing: 110, miles: 7, track: 20, speed: 105, altitude: 3500, vs: 300),
        Seed(number: "EK211", callsign: "UAE211", airline: "UAE", type: "A388", reg: "A6-EUA", from: "DXB", to: "IAH", bearing: 280, miles: 14, track: 95, speed: 490, altitude: 39000, vs: 0),
    ]

    var now: @Sendable () -> Date = { Date() }

    func flights(in bounds: GeographicBounds) async throws -> [Flight] {
        try? await Task.sleep(for: .milliseconds(250))
        let center = bounds.center
        let date = now()
        // Each aircraft flies a straight 90-mile leg through its anchor point, then loops,
        // so the sky never empties and the wrap happens well outside the radius.
        let legMiles = 90.0
        return Self.seeds.enumerated().map { index, seed in
            let milesPerSecond = seed.speed * GeoMath.milesPerKnotHour / 3600
            let period = legMiles / milesPerSecond
            let phase = (date.timeIntervalSince1970 + Double(index) * 97).truncatingRemainder(dividingBy: period) - period / 2
            let anchor = GeoMath.destination(from: center, bearingDegrees: seed.bearing, distanceMiles: seed.miles)
            let travelled = milesPerSecond * phase
            let position = GeoMath.destination(from: anchor, bearingDegrees: seed.track, distanceMiles: travelled)
            return Flight(
                id: "demo-\(index)",
                hex: String(format: "DE%04X", index),
                latitude: position.latitude,
                longitude: position.longitude,
                track: seed.track,
                altitudeFeet: seed.altitude,
                groundSpeedKnots: Int(seed.speed),
                verticalRateFPM: seed.vs,
                squawk: String(format: "%04d", 1200 + index * 111),
                typeCode: seed.type,
                registration: seed.reg,
                originIATA: seed.from.isEmpty ? nil : seed.from,
                destinationIATA: seed.to.isEmpty ? nil : seed.to,
                flightNumber: seed.number.isEmpty ? nil : seed.number,
                callsign: seed.callsign,
                airlineICAO: seed.airline.isEmpty ? nil : seed.airline,
                isOnGround: false,
                positionTime: date
            )
        }
    }
}
