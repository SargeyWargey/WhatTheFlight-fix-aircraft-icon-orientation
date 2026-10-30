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
    /// Aircraft anywhere in the world whose tail number, flight number or callsign starts
    /// with the query's identifier, or flying for the airlines or to and from the airports
    /// it names.
    func search(_ query: FlightSearchQuery) async throws -> [Flight]
    /// Where these airframes (by registration) and flights (by callsign) are now, anywhere.
    func lookup(registrations: [String], callsigns: [String]) async throws -> [Flight]
    /// Where this airframe (or, without a registration, this callsign) is right now,
    /// anywhere, on the ground included. `nil` when it isn't transmitting.
    func locate(registration: String?, callsign: String?) async throws -> Flight?
    /// Which source answered the last request; a layered feed says which of its sources.
    func lastSource() async -> FeedSource?
    /// Automatic, Flightradar24 only, or open data only (layered feeds; others ignore it).
    func setPreference(_ preference: DataSourcePreference) async
}

extension FlightFeed {
    func search(_ query: FlightSearchQuery) async throws -> [Flight] { [] }
    func lookup(registrations: [String], callsigns: [String]) async throws -> [Flight] { [] }
    func locate(registration: String?, callsign: String?) async throws -> Flight? { nil }
    func lastSource() async -> FeedSource? { nil }
    func setPreference(_ preference: DataSourcePreference) async {}
}

/// A worldwide search, read from what was typed: a prefix of a tail number, flight number or
/// callsign, plus the airlines ("american") and airports ("XNA", "chicago") it names.
struct FlightSearchQuery: Equatable, Sendable {
    /// Upper case, spaces removed: "DL570", "N509DN", "GXLEI".
    let identifier: String
    /// ICAO designators of the airlines the text names: "american" → AAL, EGF…
    let airlines: [String]
    /// IATA codes of the airports it names: "xna" → XNA, "chicago" → ORD, MDW.
    let airports: [String]

    init(identifier: String, airlines: [String] = [], airports: [String] = []) {
        self.identifier = identifier
        self.airlines = airlines
        self.airports = airports
    }

    /// Reads the catalogs (a few milliseconds), so build it off the main thread.
    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isWords = !trimmed.isEmpty && trimmed.allSatisfy { $0.isLetter || " -'.&/".contains($0) }
        self.init(
            identifier: trimmed.uppercased().filter { !$0.isWhitespace },
            // Names from four letters: a three-letter code is already a callsign prefix
            // ("AAL"), and "air" starts half the catalog.
            airlines: isWords && trimmed.count >= 4 ? AirlineCatalog.search(trimmed, limit: 4, namesOnly: true).map(\.icao) : [],
            airports: isWords ? AirportCatalog.search(trimmed).map(\.iata) : []
        )
    }
}

enum FeedError: LocalizedError, Equatable {
    case offline
    /// Online, but the server can't be reached (DNS, TLS, refused connection…).
    case unreachable
    case timedOut
    case rateLimited
    case http(Int)
    case badData

    var errorDescription: String? {
        switch self {
        case .offline: return "You're offline"
        case .unreachable: return "Can't reach the flight data right now"
        case .timedOut: return "The flight data took too long to arrive"
        case .rateLimited: return "Too many requests for flight data — slowing down"
        case .http(let code): return "The flight data server returned HTTP \(code)"
        case .badData: return "The flight data couldn't be read"
        }
    }

    /// Worth trying another source for: the server, not the phone's connection.
    var isServerProblem: Bool { self != .offline }

    /// Maps a transport error the way every feed does.
    static func from(_ error: URLError) -> Error {
        switch error.code {
        case .cancelled: return CancellationError()
        case .timedOut: return FeedError.timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: return FeedError.offline
        default: return FeedError.unreachable
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

    /// The whole world filtered by `reg`, `flight` or `callsign`. Flightradar24 matches
    /// prefixes, case-sensitively, and takes comma-separated lists; different filters AND
    /// together, so each needs its own request.
    static func worldURL(filter name: String, values: [String]) -> URL? {
        let list = values.map { $0.uppercased() }.filter { !$0.isEmpty }
        guard !list.isEmpty else { return nil }
        return url(bounds: "90,-90,-180,180", extra: [URLQueryItem(name: name, value: list.joined(separator: ","))], ground: true)
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

    func lastSource() async -> FeedSource? { .flightradar24 }

    /// Where this airframe (or, without a registration, this callsign) is right now,
    /// anywhere in the world. `nil` when it isn't transmitting.
    func locate(registration: String?, callsign: String?) async throws -> Flight? {
        guard let url = Self.locateURL(registration: registration, callsign: callsign) else { return nil }
        return try await fetch(url).max { $0.positionTime < $1.positionTime }
    }

    /// `airline` takes ICAO designators and `airport` IATA codes (flights to and from it),
    /// both exact, both comma lists.
    func search(_ query: FlightSearchQuery) async throws -> [Flight] {
        let q = query.identifier
        guard q.count >= 2 else { return [] }
        let urls = [
            Self.worldURL(filter: "reg", values: [q] + RegistrationCountry.hyphenatedForms(of: q)),
            Self.worldURL(filter: "flight", values: [q]),
            Self.worldURL(filter: "callsign", values: [q]),
            Self.worldURL(filter: "airline", values: query.airlines),
            Self.worldURL(filter: "airport", values: query.airports),
        ].compactMap { $0 }
        return try await fetchAll(urls)
    }

    func lookup(registrations: [String], callsigns: [String]) async throws -> [Flight] {
        let urls = [
            Self.worldURL(filter: "reg", values: registrations),
            Self.worldURL(filter: "callsign", values: callsigns),
        ].compactMap { $0 }
        return try await fetchAll(urls)
    }

    /// Runs the requests side by side and merges them by flight id. One failing is fine;
    /// all failing throws the first error.
    private func fetchAll(_ urls: [URL]) async throws -> [Flight] {
        guard !urls.isEmpty else { return [] }
        let results = await withTaskGroup(of: Result<[Flight], Error>.self) { group in
            for url in urls {
                group.addTask {
                    do { return .success(try await fetch(url)) } catch { return .failure(error) }
                }
            }
            var all: [Result<[Flight], Error>] = []
            for await result in group { all.append(result) }
            return all
        }
        var merged: [String: Flight] = [:]
        var firstError: Error?
        for result in results {
            switch result {
            case .success(let flights):
                for f in flights where (merged[f.id]?.positionTime ?? .distantPast) <= f.positionTime { merged[f.id] = f }
            case .failure(let error):
                firstError = firstError ?? error
            }
        }
        if merged.isEmpty, let firstError, results.allSatisfy({ if case .failure = $0 { return true } else { return false } }) {
            throw firstError
        }
        return Array(merged.values)
    }

    private func fetch(_ url: URL) async throws -> [Flight] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .timedOut:
                throw FeedError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw FeedError.offline
            default:
                Log.feed.error("feed.js: URLError \(error.code.rawValue, privacy: .public)")
                throw FeedError.unreachable
            }
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            Log.feed.error("feed.js: HTTP \(http.statusCode, privacy: .public)")
            throw http.statusCode == 429 ? FeedError.rateLimited : FeedError.http(http.statusCode)
        }
        do {
            return try FlightFeedParser.parse(data, receivedAt: Date())
        } catch {
            Log.feed.error("feed.js: unreadable response, \(data.count, privacy: .public) bytes: \(error.localizedDescription, privacy: .public)")
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
