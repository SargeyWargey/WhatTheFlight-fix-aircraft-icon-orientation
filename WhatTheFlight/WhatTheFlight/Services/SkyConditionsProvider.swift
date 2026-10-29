//
//  SkyConditionsProvider.swift
//  WhatTheFlight
//
//  The weather around the radar, from aviationweather.gov (US NOAA, free, worldwide METARs,
//  no key): fetched at most every 15 minutes per place. The nearest report answers "Can I see
//  it?" (`Core/SkyVisibility.swift`); all of them place the clouds and fog drawn over the
//  radar and the map (`Core/WeatherFog.swift`).
//

import Foundation
import CoreLocation

actor SkyConditionsProvider {
    static let shared = SkyConditionsProvider()

    private var cached: (latitude: Double, longitude: Double, degrees: Double, fetched: Date, report: SkyReport)?
    private let session: URLSession
    static let refresh: TimeInterval = 15 * 60

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "WhatTheFlight/2.0 (+https://github.com/SargeyWargey/WhatTheFlight)",
            "Accept": "application/json",
        ]
        session = URLSession(configuration: config)
    }

    func conditions(near observer: CLLocationCoordinate2D) async -> SkyConditions? {
        await report(near: observer).nearest
    }

    /// The reports out to `reachMiles` (at least the nearest station's usual distance), so the
    /// fog covers the map's whole range.
    func report(near observer: CLLocationCoordinate2D, reachMiles: Double = 0) async -> SkyReport {
        // About 40 mi either side covers the radar and finds the nearest station; up to 200 mi
        // for a wide map.
        let degrees = min(3, max(0.6, reachMiles / 69))
        if let c = cached, Date().timeIntervalSince(c.fetched) < Self.refresh, c.degrees >= degrees,
           GeoMath.distanceMiles(from: observer, to: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)) < 15 {
            return c.report
        }
        var reports = await fetch(around: observer, degrees: degrees)
        // Nothing that close (open ocean, the far north): a wider box for the nearest.
        if reports?.isEmpty == true, degrees < 1.5 { reports = await fetch(around: observer, degrees: 1.5) }
        guard let reports else {
            // Offline: keep what's known of this area rather than clearing the sky.
            if let c = cached, GeoMath.distanceMiles(from: observer, to: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)) < 30 {
                return c.report
            }
            return .none
        }
        let report = SkyReport(nearest: SkyConditions.nearest(to: observer, in: reports), all: reports)
        cached = (observer.latitude, observer.longitude, degrees, Date(), report)
        return report
    }

    /// Nil when the request failed; empty when it worked and there are no stations.
    private func fetch(around c: CLLocationCoordinate2D, degrees: Double) async -> [SkyConditions]? {
        let lonDegrees = degrees / max(0.2, cos(c.latitude * .pi / 180))
        let box = [c.latitude - degrees, c.longitude - lonDegrees, c.latitude + degrees, c.longitude + lonDegrees]
            .map { String(format: "%.3f", $0) }.joined(separator: ",")
        guard let url = URL(string: "https://aviationweather.gov/api/data/metar?bbox=\(box)&format=json") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            // No stations in the box comes back as 204 No Content.
            if http.statusCode == 204 { return [] }
            guard http.statusCode == 200 else { return nil }
            return SkyConditions.parseReports(data)
        } catch {
            Log.feed.debug("METAR lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
