//
//  AircraftPhotoProvider.swift
//  WhatTheFlight
//
//  Real aircraft photos from the public Planespotters.net API (by registration, then by
//  ICAO hex). Their terms require a descriptive User-Agent and photographer credit.
//

import Foundation

struct AircraftPhoto: Equatable, Sendable {
    let imageURL: URL
    let pageURL: URL?
    let photographer: String?
}

actor AircraftPhotoProvider {
    static let shared = AircraftPhotoProvider()

    private var cache: [String: AircraftPhoto?] = [:]
    private var inFlight: [String: Task<AircraftPhoto?, Never>] = [:]
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "WhatTheFlight/2.0 (+https://github.com/SargeyWargey/WhatTheFlight)",
            "Accept": "application/json",
        ]
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 64 << 20)
        session = URLSession(configuration: config)
    }

    func photo(registration: String?, hex: String?) async -> AircraftPhoto? {
        let key = (registration ?? hex ?? "").uppercased()
        guard !key.isEmpty else { return nil }
        if let cached = cache[key] { return cached }
        if let running = inFlight[key] { return await running.value }

        let task = Task<AircraftPhoto?, Never> {
            if let reg = registration, let hit = await fetch(path: "reg", value: reg) { return hit }
            if let hex, let hit = await fetch(path: "hex", value: hex) { return hit }
            return nil
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = result
        return result
    }

    private struct Response: Decodable {
        struct Photo: Decodable {
            struct Image: Decodable { let src: URL }
            let thumbnail_large: Image?
            let thumbnail: Image?
            let link: URL?
            let photographer: String?
        }
        let photos: [Photo]
    }

    private func fetch(path: String, value: String) async -> AircraftPhoto? {
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.planespotters.net/pub/photos/\(path)/\(encoded)") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            guard let first = decoded.photos.first,
                  let image = first.thumbnail_large?.src ?? first.thumbnail?.src else { return nil }
            return AircraftPhoto(imageURL: image, pageURL: first.link, photographer: first.photographer)
        } catch {
            return nil
        }
    }
}
