//
//  PlaceServices.swift
//  WhatTheFlight
//
//  Turning places into coordinates and back: free-text search ("Atlanta", "ATL",
//  "123 Main St"), suggestions as you type, friendly names for a coordinate, and Apple TV's one-shot location.
//

#if os(iOS) || os(tvOS)
import Foundation
import CoreLocation
import MapKit
import Observation

struct PlaceResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let detail: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum PlaceServices {
    /// Natural-language place search via MapKit.
    static func search(_ query: String, near: CLLocationCoordinate2D? = nil) async -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let near {
            request.region = MKCoordinateRegion(center: near, latitudinalMeters: 400_000, longitudinalMeters: 400_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return response.mapItems.prefix(8).map { result(from: $0, name: $0.name ?? $0.placemark.title ?? trimmed) }
    }

    /// Turns a type-ahead suggestion into a place with a coordinate.
    static func resolve(_ suggestion: PlaceSuggestion) async -> PlaceResult? {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        return result(from: item, name: suggestion.title)
    }

    private static func result(from item: MKMapItem, name: String) -> PlaceResult {
        let placemark = item.placemark
        let detail = [placemark.locality, placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .filter { $0 != name }
            .joined(separator: ", ")
        return PlaceResult(
            name: name,
            detail: detail,
            latitude: placemark.coordinate.latitude,
            longitude: placemark.coordinate.longitude
        )
    }

    /// "Atlanta, GA" style name for a coordinate, if the geocoder knows one.
    static func name(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let parts = [placemark.locality ?? placemark.subAdministrativeArea, placemark.administrativeArea]
            .compactMap { $0 }
        return parts.isEmpty ? placemark.country : parts.joined(separator: ", ")
    }
}

struct PlaceSuggestion: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion

    /// "Coffee near me"-style query rather than a specific place.
    var isQuery: Bool { subtitle.isEmpty || subtitle.hasPrefix("Search Nearby") }
}

/// Address / place suggestions as you type, from MapKit (free, no API key).
@MainActor
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [PlaceSuggestion] = []
    /// The query the current suggestions belong to.
    private(set) var settledQuery = ""

    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func update(_ query: String, near: CLLocationCoordinate2D?) {
        if let near {
            completer.region = MKCoordinateRegion(center: near, latitudinalMeters: 400_000, longitudinalMeters: 400_000)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completer.cancel()
            suggestions = []
            settledQuery = ""
        } else {
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        let fragment = completer.queryFragment
        MainActor.assumeIsolated {
            suggestions = results.prefix(10).enumerated().map { index, item in
                PlaceSuggestion(id: "\(index)|\(item.title)|\(item.subtitle)", title: item.title, subtitle: item.subtitle, completion: item)
            }
            settledQuery = fragment
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let fragment = completer.queryFragment
        MainActor.assumeIsolated {
            suggestions = []
            settledQuery = fragment
        }
    }
}
#endif

#if os(tvOS)
/// Apple TV has no GPS, but Core Location can still estimate its position from Wi-Fi.
@MainActor
@Observable
final class TVLocationProvider: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var isLocating = false
    private(set) var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsFix = false

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Asks for permission if needed, then for a single fix.
    func locate() {
        wantsFix = true
        lastError = nil
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            isLocating = true
            manager.requestLocation()
        } else {
            lastError = "Location access is off for WhatTheFlight in tvOS Settings."
        }
    }

    /// Drops the last fix, e.g. when the user clears their location.
    func forget() {
        wantsFix = false
        isLocating = false
        coordinate = nil
        lastError = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if wantsFix, isAuthorized {
                isLocating = true
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated {
            coordinate = latest.coordinate
            isLocating = false
            wantsFix = false
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            isLocating = false
            lastError = "Couldn't find this Apple TV's location (\(message))."
        }
    }
}
#endif
