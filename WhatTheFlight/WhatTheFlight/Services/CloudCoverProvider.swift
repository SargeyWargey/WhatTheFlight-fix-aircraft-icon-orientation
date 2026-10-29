//
//  CloudCoverProvider.swift
//  WhatTheFlight
//
//  Apple Weather (WeatherKit) at five points around the radar for the clouds and fog
//  (`Core/WeatherFog.swift`): where you are and the four compass points at the map's fringe,
//  every 15 minutes while the radar is on screen. Every call counts against the developer
//  account's monthly allowance (500,000 calls, shared by every user), so it's careful:
//  - a fresh set is reused, across launches too (`wtf.cloudSamples`);
//  - each device stops at `WeatherKitBudget.dailyCap` calls a day (`wtf.weatherKitBudget`);
//  - after a failure it rests for 30 minutes.
//  Nil means "not available" (not set up on the App ID, an unsigned build, offline, over the
//  cap), and the radar falls back to the airport reports. The cloud base height still comes
//  from the airports either way: WeatherKit doesn't give one, and "Can I see it?" needs it.
//
//  Showing Apple's data means showing its attribution: `WeatherAttributionView`.
//

import Foundation
import CoreLocation
import SwiftUI
import WeatherKit

actor CloudCoverProvider {
    static let shared = CloudCoverProvider()
    static let refresh: TimeInterval = 15 * 60
    static let restAfterFailure: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private var cache: CloudSampleSet?
    private var budget: WeatherKitBudget
    private var restingUntil: Date?
    private var loggedFailure = false

    private static let cacheKey = "wtf.cloudSamples"
    private static let budgetKey = "wtf.weatherKitBudget"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cache = defaults.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode(CloudSampleSet.self, from: $0) }
        budget = defaults.data(forKey: Self.budgetKey).flatMap { try? JSONDecoder().decode(WeatherKitBudget.self, from: $0) } ?? WeatherKitBudget()
    }

    /// The samples for a radar of `radiusMiles` around `center`, or nil when Apple Weather
    /// isn't available right now.
    func samples(around center: CLLocationCoordinate2D, radiusMiles: Double) async -> [CloudSample]? {
        let now = Date()
        if let cache, cache.covers(center, radiusMiles: radiusMiles, at: now, refresh: Self.refresh) { return cache.samples }
        if let restingUntil, now < restingUntil { return nearbyCache(center, at: now) }
        let points = CloudSample.points(around: center, radiusMiles: radiusMiles)
        guard budget.canSpend(points.count, at: now) else {
            Log.feed.notice("Apple Weather: today's \(WeatherKitBudget.dailyCap) calls are used up; using the airport reports")
            return nearbyCache(center, at: now)
        }
        // Failed calls may count too, so they're spent up front.
        budget.spend(points.count, at: now)
        save(budget, Self.budgetKey)

        let samples = await withTaskGroup(of: CloudSample?.self) { group in
            for point in points {
                group.addTask { await Self.fetch(point) }
            }
            var found: [CloudSample?] = []
            for await sample in group { found.append(sample) }
            return found
        }
        // Keep the centre first: it supplies the wind.
        let ordered = samples.compactMap { $0 }.sorted {
            GeoMath.distanceMiles(from: center, to: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                < GeoMath.distanceMiles(from: center, to: CLLocationCoordinate2D(latitude: $1.latitude, longitude: $1.longitude))
        }
        guard !ordered.isEmpty else {
            restingUntil = now.addingTimeInterval(Self.restAfterFailure)
            if !loggedFailure {
                loggedFailure = true
                Log.feed.notice("Apple Weather unavailable (is WeatherKit on for the App ID?); using the airport reports")
            }
            return nearbyCache(center, at: now)
        }
        loggedFailure = false
        let set = CloudSampleSet(latitude: center.latitude, longitude: center.longitude, radiusMiles: radiusMiles,
                                 fetchedAt: now, samples: ordered)
        cache = set
        save(set, Self.cacheKey)
        return ordered
    }

    /// An older set for about the same place still beats nothing while WeatherKit rests.
    private func nearbyCache(_ center: CLLocationCoordinate2D, at date: Date) -> [CloudSample]? {
        guard let cache, date.timeIntervalSince(cache.fetchedAt) < CloudSample.freshFor,
              GeoMath.distanceMiles(from: center, to: CLLocationCoordinate2D(latitude: cache.latitude, longitude: cache.longitude)) < 15
        else { return nil }
        return cache.samples
    }

    private func save(_ value: some Encodable, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func fetch(_ point: CLLocationCoordinate2D) async -> CloudSample? {
        do {
            let current = try await WeatherService.shared.weather(for: CLLocation(latitude: point.latitude, longitude: point.longitude),
                                                                  including: .current)
            let byHeight = current.cloudCoverByAltitude
            let condition: CloudSample.Obscuration?
            switch current.condition {
            case .foggy: condition = .fog
            case .haze: condition = .haze
            case .smoky: condition = .smoke
            case .blowingDust: condition = .dust
            default: condition = nil
            }
            let speed = current.wind.speed.converted(to: .knots).value
            return CloudSample(latitude: point.latitude, longitude: point.longitude,
                               low: byHeight.low, medium: byHeight.medium, high: byHeight.high,
                               visibilityMiles: current.visibility.converted(to: .miles).value, condition: condition,
                               windFromDegrees: speed > 0.5 ? current.wind.direction.converted(to: .degrees).value : nil,
                               windKnots: speed, observedAt: current.date)
        } catch {
            Log.feed.debug("Apple Weather lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

// MARK: - Attribution

/// The Apple Weather mark and the link to its other data sources, which Apple requires
/// wherever its weather data shows: in full in Settings → Radar → Weather, and `compact` (the
/// mark alone, linking to the legal page) on the map while its clouds come from Apple Weather.
/// Nothing until WeatherKit answers (not set up, unsigned); DEBUG `-wtf.debugAttribution YES`
/// draws a stand-in for layout screenshots.
struct WeatherAttributionView: View {
    var compact = false
    var markHeight: CGFloat = 12

    @State private var attribution: WeatherAttribution?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let attribution {
                if compact {
                    #if os(tvOS)
                    mark(attribution)
                    #else
                    Link(destination: attribution.legalPageURL) { mark(attribution) }
                        .accessibilityLabel("\(attribution.serviceName), other data sources")
                    #endif
                } else {
                    HStack(spacing: 10) {
                        mark(attribution)
                        #if os(tvOS)
                        // No browser on the TV: the address itself.
                        Text(attribution.legalPageURL.absoluteString).font(.caption2)
                        #else
                        Link("Other data sources", destination: attribution.legalPageURL).font(.footnote)
                        #endif
                    }
                }
            } else if Self.showsStandIn {
                Label("Weather", systemImage: "apple.logo")
                    .font(.system(size: markHeight, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? .white : .black)
            }
        }
        .task { attribution = try? await WeatherService.shared.attribution }
    }

    private func mark(_ attribution: WeatherAttribution) -> some View {
        AsyncImage(url: colorScheme == .dark ? attribution.combinedMarkDarkURL : attribution.combinedMarkLightURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Text(attribution.serviceName).font(.system(size: markHeight * 0.9, weight: .semibold))
        }
        .frame(height: markHeight)
        .accessibilityLabel(attribution.serviceName)
    }

    static var showsStandIn: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "wtf.debugAttribution")
        #else
        false
        #endif
    }
}
