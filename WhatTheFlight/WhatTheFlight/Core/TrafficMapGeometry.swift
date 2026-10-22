//
//  TrafficMapGeometry.swift
//  WhatTheFlight
//
//  The maths behind the ambient map (`TrafficMap`), kept free of SwiftUI and MapKit so it is
//  unit-tested: where the camera looks, how a trail fades with age, and which airports earn
//  a pin.
//

import Foundation
import CoreLocation

enum TrafficMapGeometry {
    /// What the camera shows. `radiusMiles` is the circle the frame was built around (zero
    /// for a frame fitted to arbitrary points): a circle looks the same whichever way the map
    /// is turned, so the frame holds when the map rotates to face the TV's direction.
    struct Frame: Equatable {
        let center: CLLocationCoordinate2D
        let latitudeDelta: Double
        let longitudeDelta: Double
        var radiusMiles: Double = 0

        static func == (lhs: Frame, rhs: Frame) -> Bool {
            lhs.center.latitude == rhs.center.latitude && lhs.center.longitude == rhs.center.longitude
                && lhs.latitudeDelta == rhs.latitudeDelta && lhs.longitudeDelta == rhs.longitudeDelta
                && lhs.radiusMiles == rhs.radiusMiles
        }

        var bounds: GeographicBounds {
            GeographicBounds(northLatitude: center.latitude + latitudeDelta / 2, southLatitude: center.latitude - latitudeDelta / 2,
                             eastLongitude: center.longitude + longitudeDelta / 2, westLongitude: center.longitude - longitudeDelta / 2)
        }

        /// Whether a point is inside the frame's circle, shrunk by `margin` (0.9 = the inner 90%).
        func encloses(_ point: CLLocationCoordinate2D, margin: Double = 1) -> Bool {
            GeoMath.distanceMiles(from: center, to: point) <= radiusMiles * margin
        }
    }

    static let milesPerDegreeLatitude = GeoMath.earthRadiusMiles * .pi / 180

    /// A frame around the radius ring, grown just enough to also hold every `extra` point (a
    /// pinned aircraft that has left), with `padding` as a multiplier on the diameter.
    static func frame(observer: CLLocationCoordinate2D, radiusMiles: Double,
                      extra: [CLLocationCoordinate2D] = [], padding: Double = 1.1) -> Frame {
        // Smallest enclosing circle, grown one point at a time: for a point outside, the new
        // circle spans from the far side of the old one to the point.
        var center = observer
        var radius = max(radiusMiles, 0.1)
        for point in extra {
            let d = GeoMath.distanceMiles(from: center, to: point)
            guard d > radius else { continue }
            let newRadius = (d + radius) / 2
            center = GeoMath.destination(from: center, bearingDegrees: GeoMath.bearing(from: center, to: point),
                                         distanceMiles: newRadius - radius)
            radius = newRadius
        }
        let latitudeDelta = min(170, 2 * radius * padding / milesPerDegreeLatitude)
        let longitudeDelta = min(355, latitudeDelta / max(0.01, cos(center.latitude * .pi / 180)))
        return Frame(center: center, latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta, radiusMiles: radius)
    }

    /// A frame around arbitrary points. Longitudes are unwrapped so a trans-Pacific route frames
    /// the short way across the date line.
    static func frame(fitting points: [CLLocationCoordinate2D], padding: Double, minimumSpan: Double) -> Frame {
        guard let first = points.first else {
            return Frame(center: CLLocationCoordinate2D(latitude: 0, longitude: 0), latitudeDelta: 0, longitudeDelta: 0)
        }
        let lats = points.map(\.latitude)
        let lons = points.map { p -> Double in
            var lon = p.longitude
            while lon - first.longitude > 180 { lon -= 360 }
            while lon - first.longitude < -180 { lon += 360 }
            return lon
        }
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        var centerLon = (minLon + maxLon) / 2
        if centerLon > 180 { centerLon -= 360 } else if centerLon < -180 { centerLon += 360 }
        return Frame(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: centerLon),
                     latitudeDelta: min(170, max(minimumSpan, (maxLat - minLat) * padding)),
                     longitudeDelta: min(355, max(minimumSpan, (maxLon - minLon) * padding)))
    }

    /// The ambient map's trail fade: brightest for the last five minutes, gone after fifteen.
    static let trailBands: [(minutes: Double, opacity: Double)] = [(5, 0.9), (10, 0.5), (15, 0.25)]

    /// Trail split by age for fading: (points, opacity) oldest first. `bands` run newest
    /// first, each up to its age in minutes; anything older than the last band is dropped.
    /// Neighbouring segments share their boundary point so the line has no gaps.
    static func segments(_ trail: [RadarModel.TrailPoint], now: Date,
                         bands: [(minutes: Double, opacity: Double)] = trailBands) -> [(coordinates: [CLLocationCoordinate2D], opacity: Double)] {
        func band(_ point: RadarModel.TrailPoint) -> Int? {
            let minutes = now.timeIntervalSince(point.time) / 60
            return bands.firstIndex { minutes <= $0.minutes }
        }
        var result: [(coordinates: [CLLocationCoordinate2D], opacity: Double)] = []
        var current: (band: Int, coordinates: [CLLocationCoordinate2D])?
        for point in trail {
            guard let index = band(point) else { continue }
            if let open = current, open.band != index {
                // Close the older segment at this point so it meets the next one.
                result.append((open.coordinates + [point.coordinate], bands[open.band].opacity))
                current = (index, [point.coordinate])
            } else {
                current = (index, (current?.coordinates ?? []) + [point.coordinate])
            }
        }
        if let open = current { result.append((open.coordinates, bands[open.band].opacity)) }
        return result.filter { $0.coordinates.count >= 2 }
    }

    /// Origin/destination airports of the given flights that fall inside `bounds`, by code.
    static func relevantAirports(for flights: [Flight], in bounds: GeographicBounds) -> [Airport] {
        let codes = Set(flights.flatMap { [$0.originIATA, $0.destinationIATA] }.compactMap { $0?.uppercased() }.filter { !$0.isEmpty })
        return codes.compactMap(AirportCatalog.airport(iata:))
            .filter { $0.coordinate.map(bounds.contains) ?? false }
            .sorted { $0.iata < $1.iata }
    }
}
