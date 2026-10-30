//
//  OpenFeed.swift
//  WhatTheFlight
//
//  A second source of traffic so a Flightradar24 outage or block doesn't take the radar down
//  (Enhancements Spec C1; the longer plan is `Flight Data Sources Spec.md`).
//
//  `ReadsbFeed` reads adsb.lol, open community ADS-B data (ODbL 1.0, attribution required).
//  Without a production key it allows 500 requests a day per address, so it backs
//  Flightradar24 up rather than replacing it. `LayeredFeed` asks Flightradar24 first, steps
//  down to adsb.lol after two failures in a row (or straight away when rate limited), and
//  tries Flightradar24 again every five minutes. It says which source answered, for the badge
//  on the radar and the credit on the details.
//

import Foundation
import CoreLocation

/// Where the traffic on screen came from.
enum FeedSource: String, Codable, Sendable {
    case flightradar24, adsbLol, demo

    var title: String {
        switch self {
        case .flightradar24: return String(localized: "Flightradar24")
        case .adsbLol: return String(localized: "adsb.lol")
        case .demo: return String(localized: "Demo traffic")
        }
    }

    /// The credit line under a flight's details: open data's licence asks for one.
    var attribution: String? {
        switch self {
        case .flightradar24: return nil
        case .adsbLol: return "Live data: adsb.lol, © adsb.lol contributors, ODbL 1.0. No routes from this source. Positions between updates are estimated."
        case .demo: return "Simulated traffic for trying the app out."
        }
    }

    /// Open data carries no routes or schedules.
    var hasRoutes: Bool { self != .adsbLol }
}

/// Settings → Radar → Data source.
enum DataSourcePreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic, flightradar24, openData = "open"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return String(localized: "Automatic")
        case .flightradar24: return String(localized: "Flightradar24")
        case .openData: return String(localized: "Open data")
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: return String(localized: "Flightradar24, switching to adsb.lol while it's down")
        case .flightradar24: return String(localized: "Flightradar24 only")
        case .openData: return String(localized: "adsb.lol only: open ADS-B data, without routes")
        }
    }
}

// MARK: - adsb.lol

struct ReadsbFeed: FlightFeed {
    static let adsbLol = URL(string: "https://api.adsb.lol")!
    /// The API's largest point query.
    static let maxRadiusNM = 250.0

    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = ReadsbFeed.adsbLol, session: URLSession = ReadsbFeed.makeSession()) {
        self.baseURL = baseURL
        self.session = session
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        config.httpAdditionalHeaders = [
            // Open data providers ask apps to say who they are.
            "User-Agent": "WhatTheFlight/\(version) (iOS, tvOS and watchOS app; SargeyWargey.WhatTheFlight)",
            "Accept": "application/json",
        ]
        return URLSession(configuration: config)
    }

    func lastSource() async -> FeedSource? { .adsbLol }

    /// A circle round the box's centre reaching its corners.
    static func pointURL(for bounds: GeographicBounds, base: URL = adsbLol) -> URL {
        let center = bounds.center
        let corner = CLLocationCoordinate2D(latitude: bounds.northLatitude, longitude: bounds.eastLongitude)
        let nm = min(maxRadiusNM, max(1, (GeoMath.distanceMiles(from: center, to: corner) / 1.150779).rounded(.up)))
        return base.appendingPathComponent("v2/point/\(format(center.latitude))/\(format(center.longitude))/\(Int(nm))")
    }

    /// `/v2/reg/N1,N2` or `/v2/callsign/DAL1,UAL2`: exact matches, comma lists.
    static func listURL(_ kind: String, values: [String], base: URL = adsbLol) -> URL? {
        let list = values.map { $0.uppercased().filter { !$0.isWhitespace } }.filter { !$0.isEmpty }
        guard !list.isEmpty else { return nil }
        return base.appendingPathComponent("v2/\(kind)/\(list.joined(separator: ","))")
    }

    private static func format(_ degrees: Double) -> String { String(format: "%.4f", degrees) }

    func flights(in bounds: GeographicBounds) async throws -> [Flight] {
        try await fetch(Self.pointURL(for: bounds, base: baseURL), includeGround: false)
    }

    /// Exact tail numbers (with and without the hyphen) and callsigns: open data has no
    /// prefix search, and without routes no airports either.
    func search(_ query: FlightSearchQuery) async throws -> [Flight] {
        let q = query.identifier
        guard q.count >= 3 else { return [] }
        let urls = [
            Self.listURL("reg", values: [q] + RegistrationCountry.hyphenatedForms(of: q), base: baseURL),
            Self.listURL("callsign", values: [q], base: baseURL),
        ].compactMap { $0 }
        return try await fetchAll(urls)
    }

    func lookup(registrations: [String], callsigns: [String]) async throws -> [Flight] {
        let urls = [
            Self.listURL("reg", values: registrations, base: baseURL),
            Self.listURL("callsign", values: callsigns, base: baseURL),
        ].compactMap { $0 }
        return try await fetchAll(urls)
    }

    func locate(registration: String?, callsign: String?) async throws -> Flight? {
        let found: [Flight]
        if let registration, !registration.isEmpty {
            found = try await lookup(registrations: [registration] + RegistrationCountry.hyphenatedForms(of: registration), callsigns: [])
        } else if let callsign, !callsign.isEmpty {
            found = try await lookup(registrations: [], callsigns: [callsign])
        } else {
            return nil
        }
        return found.max { $0.positionTime < $1.positionTime }
    }

    private func fetchAll(_ urls: [URL]) async throws -> [Flight] {
        var merged: [String: Flight] = [:]
        var firstError: Error?
        var anySucceeded = false
        // One at a time: the keyless limit is four a second.
        for url in urls {
            do {
                for f in try await fetch(url, includeGround: true) { merged[f.id] = f }
                anySucceeded = true
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                firstError = firstError ?? error
            }
        }
        if !anySucceeded, let firstError { throw firstError }
        return Array(merged.values)
    }

    private func fetch(_ url: URL, includeGround: Bool) async throws -> [Flight] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch let error as URLError {
            if error.code != .cancelled { Log.feed.error("adsb.lol: URLError \(error.code.rawValue, privacy: .public)") }
            throw FeedError.from(error)
        }
        if let http = response as? HTTPURLResponse {
            if let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining") {
                Log.feed.debug("adsb.lol: \(remaining, privacy: .public) requests left in the window")
            }
            guard (200..<300).contains(http.statusCode) else {
                Log.feed.error("adsb.lol: HTTP \(http.statusCode, privacy: .public)")
                throw http.statusCode == 429 ? FeedError.rateLimited : FeedError.http(http.statusCode)
            }
        }
        do {
            return try ReadsbParser.parse(data, receivedAt: Date(), includeGround: includeGround)
        } catch {
            Log.feed.error("adsb.lol: unreadable response, \(data.count, privacy: .public) bytes")
            throw FeedError.badData
        }
    }
}

// MARK: - Layered

/// Flightradar24 first, adsb.lol when it's down. See the file header.
actor LayeredFeed: FlightFeed {
    private let primary: FlightFeed
    private let secondary: FlightFeed
    private var preference: DataSourcePreference
    private let clock: @Sendable () -> Date

    /// Primary failures in a row.
    private var failures = 0
    /// When the radar stepped down to the secondary, so it knows when to try the primary again.
    private var steppedDownAt: Date?
    private var answered: FeedSource?

    /// Primary failures in a row before stepping down; a rate limit steps down at once.
    static let failuresBeforeFallback = 2
    /// How long to stay on the secondary before trying the primary again.
    static let retryPrimaryAfter: TimeInterval = 5 * 60

    init(primary: FlightFeed = FlightRadarFeed(), secondary: FlightFeed = ReadsbFeed(),
         preference: DataSourcePreference = .automatic, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.primary = primary
        self.secondary = secondary
        self.preference = preference
        self.clock = clock
    }

    func setPreference(_ preference: DataSourcePreference) async {
        guard preference != self.preference else { return }
        self.preference = preference
        failures = 0
        steppedDownAt = nil
    }

    func lastSource() async -> FeedSource? { answered }

    /// On the secondary now, and not yet time to try the primary again.
    private var isSteppedDown: Bool {
        guard let steppedDownAt else { return false }
        return clock().timeIntervalSince(steppedDownAt) < Self.retryPrimaryAfter
    }

    /// Runs `request` against the source the preference and recent failures say, stepping
    /// down or back as it goes.
    private func run<T: Sendable>(_ request: @Sendable (FlightFeed) async throws -> T) async throws -> T {
        switch preference {
        case .flightradar24:
            let result = try await request(primary)
            answered = .flightradar24
            return result
        case .openData:
            let result = try await request(secondary)
            answered = .adsbLol
            return result
        case .automatic:
            break
        }
        if isSteppedDown {
            do {
                let result = try await request(secondary)
                answered = .adsbLol
                return result
            } catch let error as FeedError where error.isServerProblem {
                // Both struggling: the primary may be back.
                steppedDownAt = nil
                return try await tryPrimary(request)
            }
        }
        return try await tryPrimary(request)
    }

    private func tryPrimary<T: Sendable>(_ request: @Sendable (FlightFeed) async throws -> T) async throws -> T {
        do {
            let result = try await request(primary)
            if steppedDownAt != nil || failures > 0 {
                Log.feed.notice("Flightradar24 answering again")
            }
            failures = 0
            steppedDownAt = nil
            answered = .flightradar24
            return result
        } catch let error as FeedError where error.isServerProblem {
            failures += 1
            guard failures >= Self.failuresBeforeFallback || error == .rateLimited else { throw error }
            Log.feed.notice("Flightradar24 failing (\(error.localizedDescription, privacy: .public)); using adsb.lol")
            steppedDownAt = clock()
            do {
                let result = try await request(secondary)
                answered = .adsbLol
                return result
            } catch {
                throw error
            }
        }
    }

    func flights(in bounds: GeographicBounds) async throws -> [Flight] {
        try await run { try await $0.flights(in: bounds) }
    }

    func search(_ query: FlightSearchQuery) async throws -> [Flight] {
        try await run { try await $0.search(query) }
    }

    func lookup(registrations: [String], callsigns: [String]) async throws -> [Flight] {
        try await run { try await $0.lookup(registrations: registrations, callsigns: callsigns) }
    }

    func locate(registration: String?, callsign: String?) async throws -> Flight? {
        try await run { try await $0.locate(registration: registration, callsign: callsign) }
    }
}
