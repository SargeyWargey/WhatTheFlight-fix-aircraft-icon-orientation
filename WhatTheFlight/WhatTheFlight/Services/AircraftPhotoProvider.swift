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
    /// Apple Watch without "Photos on cellular": Wi-Fi or the iPhone's connection only.
    static let noCellular = AircraftPhotoProvider(allowsCellularAccess: false)

    private var cache: [String: AircraftPhoto?] = [:]
    private var inFlight: [String: Task<AircraftPhoto?, Never>] = [:]
    private let session: URLSession

    init(allowsCellularAccess: Bool = true) {
        let config = URLSessionConfiguration.default
        config.allowsCellularAccess = allowsCellularAccess
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

    /// The photo itself, fetched over this provider's session (so the cellular rule applies).
    func imageData(for photo: AircraftPhoto) async -> Data? {
        guard let (data, response) = try? await session.data(from: photo.imageURL),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
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
            Log.feed.debug("Planespotters \(path, privacy: .public) lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
