//
//  PlaceNamer.swift
//  WhatTheFlight
//
//  "Atlanta, GA" for where you're watching from, so the logbook remembers where you were
//  when you saw each aircraft. Answers are cached per ~5 km square; a new lookup only
//  happens when you've moved.
//

#if os(iOS) || os(tvOS)
import CoreLocation
import MapKit

@MainActor
final class PlaceNamer {
    private var cache: [String: String] = [:]
    private var inFlight: String?

    /// nil while offline or when the spot has no town nearby.
    func name(for coordinate: CLLocationCoordinate2D) async -> String? {
        let key = Self.area(of: coordinate)
        if let cached = cache[key] { return cached }
        guard inFlight != key else { return nil }
        inFlight = key
        defer { inFlight = nil }
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let name = await Self.lookUp(location)
        if let name { cache[key] = name }
        return name
    }

    /// The ~0.05° square (about 5 km, a town-sized step) answers are cached by.
    static func area(of c: CLLocationCoordinate2D) -> String {
        "\((c.latitude * 20).rounded()),\((c.longitude * 20).rounded())"
    }

    private static func lookUp(_ location: CLLocation) async -> String? {
        if #available(iOS 26.0, tvOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location),
                  let item = try? await request.mapItems.first else { return nil }
            return item.addressRepresentations?.cityWithContext ?? item.name
        } else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            return format(city: placemark.locality ?? placemark.subAdministrativeArea,
                          region: placemark.administrativeArea, country: placemark.country)
        }
    }

    /// "Atlanta, GA", "Paris, France".
    private static func format(city: String?, region: String?, country: String?) -> String? {
        guard let city else { return region ?? country }
        if let region, region != city { return "\(city), \(region)" }
        if let country { return "\(city), \(country)" }
        return city
    }
}
#endif
