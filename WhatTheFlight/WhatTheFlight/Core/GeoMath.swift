//
//  GeoMath.swift
//  WhatTheFlight
//
//  Pure geodesy helpers used by the radar. Everything here is deterministic and unit tested.
//

import Foundation
import CoreLocation

enum GeoMath {
    static let earthRadiusMiles = 3958.8
    static let milesPerKnotHour = 1.150779
    static let kilometersPerMile = 1.609344

    /// Great-circle distance in statute miles (haversine).
    static func distanceMiles(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLat = (b.latitude - a.latitude).radians
        let dLon = (b.longitude - a.longitude).radians
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMiles * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from `a` to `b` in degrees, 0 = true north, clockwise, in 0..<360.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLon = (b.longitude - a.longitude).radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalize(atan2(y, x).degrees)
    }

    /// Point reached travelling `distanceMiles` from `start` on initial bearing `bearingDegrees`.
    static func destination(from start: CLLocationCoordinate2D, bearingDegrees: Double, distanceMiles: Double) -> CLLocationCoordinate2D {
        let angular = distanceMiles / earthRadiusMiles
        let bearing = bearingDegrees.radians
        let lat1 = start.latitude.radians, lon1 = start.longitude.radians
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        var longitude = lon2.degrees
        if longitude > 180 { longitude -= 360 } else if longitude < -180 { longitude += 360 }
        return CLLocationCoordinate2D(latitude: lat2.degrees, longitude: longitude)
    }

    /// Dead-reckons an aircraft forward along its track.
    static func extrapolate(_ start: CLLocationCoordinate2D, trackDegrees: Double, speedKnots: Double, seconds: TimeInterval) -> CLLocationCoordinate2D {
        guard speedKnots > 0, seconds > 0 else { return start }
        let miles = speedKnots * milesPerKnotHour * seconds / 3600
        return destination(from: start, bearingDegrees: trackDegrees, distanceMiles: miles)
    }

    /// Angle above the horizon at which an aircraft appears to the observer, allowing for
    /// the Earth curving away beneath it (which matters past ~20 miles).
    static func elevationDegrees(groundDistanceMiles: Double, altitudeFeet: Double, observerAltitudeFeet: Double = 0) -> Double {
        let feetPerMile = 5280.0
        let distance = groundDistanceMiles * feetPerMile
        guard distance > 1 else { return 90 }
        let drop = distance * distance / (2 * earthRadiusMiles * feetPerMile)
        return atan2(altitudeFeet - observerAltitudeFeet - drop, distance).degrees
    }

    /// Wraps any angle into 0..<360.
    static func normalize(_ degrees: Double) -> Double {
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Signed shortest rotation from `from` to `to`, in -180...180.
    static func shortestDelta(from: Double, to: Double) -> Double {
        var d = normalize(to) - normalize(from)
        if d > 180 { d -= 360 } else if d < -180 { d += 360 }
        return d
    }

    /// Eight-point compass label for a bearing.
    static func cardinal(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((normalize(degrees) + 22.5) / 45) % 8]
    }

    /// Closest point of approach between a straight-flying aircraft and a fixed observer.
    ///
    /// Uses a local flat-earth projection, which is accurate to well under 1% within the
    /// ~100 mile radius the radar works in.
    static func closestApproach(observer: CLLocationCoordinate2D,
                                aircraft: CLLocationCoordinate2D,
                                trackDegrees: Double,
                                speedKnots: Double) -> ClosestApproach {
        let range = distanceMiles(from: observer, to: aircraft)
        let bearingToAircraft = bearing(from: observer, to: aircraft).radians
        // Position of the aircraft relative to the observer (x = east, y = north), miles.
        let px = range * sin(bearingToAircraft)
        let py = range * cos(bearingToAircraft)
        // Velocity in miles per second.
        let speed = max(0, speedKnots) * milesPerKnotHour / 3600
        let vx = speed * sin(trackDegrees.radians)
        let vy = speed * cos(trackDegrees.radians)
        let v2 = vx * vx + vy * vy
        guard v2 > 0 else {
            return ClosestApproach(distanceMiles: range, secondsFromNow: 0)
        }
        let t = -(px * vx + py * vy) / v2
        guard t > 0 else {
            // Already past the closest point: it is getting farther away.
            return ClosestApproach(distanceMiles: range, secondsFromNow: 0)
        }
        let cx = px + vx * t, cy = py + vy * t
        return ClosestApproach(distanceMiles: sqrt(cx * cx + cy * cy), secondsFromNow: t)
    }
}

struct ClosestApproach: Equatable, Sendable {
    /// Distance at the closest point, in miles.
    let distanceMiles: Double
    /// Seconds until the closest point; 0 when the aircraft is already moving away.
    let secondsFromNow: TimeInterval

    var isAhead: Bool { secondsFromNow > 0 }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}

extension GeographicBounds {
    /// Square query box around `center` reaching `radiusMiles` in every direction.
    static func around(center: CLLocationCoordinate2D, radiusMiles: Double) -> GeographicBounds {
        let latDelta = radiusMiles / 69.0
        let lonDelta = radiusMiles / (69.172 * max(0.01, cos(center.latitude.radians)))
        return GeographicBounds(
            northLatitude: min(89.9, center.latitude + latDelta),
            southLatitude: max(-89.9, center.latitude - latDelta),
            eastLongitude: min(180, center.longitude + lonDelta),
            westLongitude: max(-180, center.longitude - lonDelta)
        )
    }
}

extension CLLocationCoordinate2D {
    var shortDescription: String {
        let lat = String(format: "%.3f°%@", abs(latitude), latitude >= 0 ? "N" : "S")
        let lon = String(format: "%.3f°%@", abs(longitude), longitude >= 0 ? "E" : "W")
        return "\(lat) \(lon)"
    }
}
