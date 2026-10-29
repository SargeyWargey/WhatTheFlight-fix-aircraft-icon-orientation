//
//  AircraftFactsProvider.swift
//  WhatTheFlight
//
//  Airframe facts (`AirframeFacts`) from adsbdb.com, by tail number then ICAO hex: cached in
//  memory and on disk for a month, one request per airframe however many views ask, and
//  none at all with Settings → Display → Aircraft details off.
//

import Foundation

actor AircraftFactsProvider {
    static let shared = AircraftFactsProvider()

    private var cache: [String: AirframeFacts?] = [:]
    private var inFlight: [String: Task<AirframeFacts?, Never>] = [:]
    private let session: URLSession
    private let directory: URL?
    /// Registers change slowly.
    static let maxAge: TimeInterval = 30 * 86_400

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "WhatTheFlight/2.0 (+https://github.com/SargeyWargey/WhatTheFlight)",
            "Accept": "application/json",
        ]
        session = URLSession(configuration: config)
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AirframeFacts", isDirectory: true)
    }

    func facts(registration: String?, hex: String?) async -> AirframeFacts? {
        let key = (registration ?? hex ?? "").uppercased().filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if let stored = read(key) {
            cache[key] = stored
            return stored
        }
        if let running = inFlight[key] { return await running.value }
        let task = Task<AirframeFacts?, Never> {
            if let registration, let hit = await fetch(registration) { return hit }
            if let hex, let hit = await fetch(hex) { return hit }
            return nil
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = result
        if let result { write(result, key: key) }
        return result
    }

    private func fetch(_ id: String) async -> AirframeFacts? {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.adsbdb.com/v0/aircraft/\(encoded)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return AirframeFacts.parseAdsbdb(data)
        } catch {
            Log.feed.debug("adsbdb lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private struct Stored: Codable {
        let savedAt: Date
        let facts: AirframeFacts
    }

    private func file(_ key: String) -> URL? { directory?.appendingPathComponent("\(key).json") }

    private func read(_ key: String) -> AirframeFacts? {
        guard let url = file(key), let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              Date().timeIntervalSince(stored.savedAt) < Self.maxAge else { return nil }
        return stored.facts
    }

    private func write(_ facts: AirframeFacts, key: String) {
        guard let url = file(key), let data = try? JSONEncoder().encode(Stored(savedAt: Date(), facts: facts)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
