//
//  SkyVisibility.swift
//  WhatTheFlight
//
//  "Can I see it?" The nearest aircraft isn't always one you can see: it can be above
//  solid overcast, lost in haze, too small at that range, low behind the trees, or next to
//  the sun. This works that out from the local weather report (a METAR from
//  aviationweather.gov, `SkyConditions`) and where the sun is (`SunPosition`). The hero says
//  so when an aircraft can't be seen, and "Prefer aircraft you can see" lets visible ones
//  take the centre first.
//

import Foundation
import CoreLocation

// MARK: - Sun

enum SunPosition {
    struct Position: Equatable, Sendable {
        /// Degrees clockwise from true north.
        let azimuth: Double
        /// Degrees above the horizon (negative below).
        let elevation: Double
    }

    /// Accurate to about a degree, plenty for glare and dusk (NOAA's low-precision formulae).
    static func at(_ date: Date, latitude: Double, longitude: Double) -> Position {
        let rad = Double.pi / 180
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let meanLongitude = (280.460 + 0.9856474 * n).truncatingRemainder(dividingBy: 360)
        let anomaly = ((357.528 + 0.9856003 * n).truncatingRemainder(dividingBy: 360)) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * n) * rad
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let gmstHours = (18.697374558 + 24.06570982441908 * n).truncatingRemainder(dividingBy: 24)
        let hourAngle = (gmstHours * 15 + longitude) * rad - rightAscension
        let lat = latitude * rad
        let elevation = asin(sin(lat) * sin(declination) + cos(lat) * cos(declination) * cos(hourAngle))
        let azimuth = atan2(-sin(hourAngle), tan(declination) * cos(lat) - sin(lat) * cos(hourAngle))
        return Position(azimuth: GeoMath.normalize(azimuth / rad), elevation: elevation / rad)
    }

    /// Angle between two directions in the sky, in degrees.
    static func separation(azimuth a1: Double, elevation e1: Double, azimuth a2: Double, elevation e2: Double) -> Double {
        let rad = Double.pi / 180
        let c = sin(e1 * rad) * sin(e2 * rad) + cos(e1 * rad) * cos(e2 * rad) * cos((a1 - a2) * rad)
        return acos(max(-1, min(1, c))) / rad
    }
}

// MARK: - Weather

/// The nearest weather report: visibility and cloud layers.
struct SkyConditions: Codable, Equatable, Sendable {
    struct Layer: Codable, Equatable, Sendable {
        /// FEW, SCT, BKN, OVC, or VV (sky hidden: fog, heavy snow).
        let cover: String
        /// Above the station, in feet.
        let baseFeet: Int

        /// Broken, overcast or obscured: a ceiling you can't see through.
        var isCeiling: Bool { ["BKN", "OVC", "OVX", "VV"].contains(cover) }

        var words: String {
            switch cover {
            case "FEW": return "a few clouds"
            case "SCT": return "scattered clouds"
            case "BKN": return "broken cloud"
            case "OVC", "OVX": return "overcast"
            case "VV": return "fog"
            default: return "cloud"
            }
        }
    }

    let station: String
    let stationName: String?
    let latitude: Double
    let longitude: Double
    /// Above sea level, so cloud bases compare with aircraft altitudes.
    let elevationFeet: Int
    let observedAt: Date
    /// Statute miles; "10+" reads 10.
    let visibilityMiles: Double?
    let layers: [Layer]
    let weather: String?
    /// Where the wind blows from, degrees true; nil when calm or variable.
    var windFromDegrees: Double? = nil
    var windKnots: Double? = nil
    /// Whether the report covers the sky above 12,000 ft: an observer's SKC, or a layer up
    /// there. Automated stations' "CLR" only means nothing below 12,000 ft.
    var seesHighCloud = false

    /// The lowest broken or overcast layer.
    var ceiling: Layer? { layers.filter(\.isCeiling).min { $0.baseFeet < $1.baseFeet } }

    /// Is a report this old still worth trusting? METARs come hourly.
    func isFresh(at date: Date) -> Bool { date.timeIntervalSince(observedAt) < 3 * 3600 }

    /// "Broken 3,500 ft", "Clear · 3 mi": what fits a tile. Visibility only when it's poor.
    var shortSummary: String {
        let sky: String
        if let layer = ceiling ?? layers.min(by: { $0.baseFeet < $1.baseFeet }) {
            let cover = ["FEW": "Few", "SCT": "Scattered", "BKN": "Broken", "OVC": "Overcast", "OVX": "Overcast", "VV": "Fog"][layer.cover] ?? "Cloud"
            sky = "\(cover) \(RadarFormat.altitudeText(layer.baseFeet))"
        } else {
            sky = "Clear"
        }
        guard let v = visibilityMiles, v < 10 else { return sky }
        return "\(sky) · \(RadarFormat.preciseDistance(v))"
    }

    /// "Clear, 10 mi" / "Overcast at 2,500 ft, 6 mi" for the details.
    var summary: String {
        var parts: [String] = []
        if let ceiling {
            parts.append("\(ceiling.words.prefix(1).uppercased() + ceiling.words.dropFirst()) at \(RadarFormat.altitudeText(ceiling.baseFeet))")
        } else if let lowest = layers.min(by: { $0.baseFeet < $1.baseFeet }) {
            parts.append("\(lowest.words.prefix(1).uppercased() + lowest.words.dropFirst()) at \(RadarFormat.altitudeText(lowest.baseFeet))")
        } else {
            parts.append("Clear")
        }
        if let v = visibilityMiles { parts.append("\(RadarFormat.preciseDistance(v)) visibility") }
        return parts.joined(separator: " · ")
    }

    /// The report nearest `observer` from aviationweather.gov's JSON (`/api/data/metar?bbox=…&format=json`).
    static func parseMetars(_ data: Data, near observer: CLLocationCoordinate2D, now: Date = Date()) -> SkyConditions? {
        nearest(to: observer, in: parseReports(data, now: now))
    }

    static func nearest(to observer: CLLocationCoordinate2D, in reports: [SkyConditions]) -> SkyConditions? {
        reports.min { GeoMath.distanceMiles(from: observer, to: $0.coordinate) < GeoMath.distanceMiles(from: observer, to: $1.coordinate) }
    }

    /// Every fresh report in aviationweather.gov's JSON, one per station (the latest).
    static func parseReports(_ data: Data, now: Date = Date()) -> [SkyConditions] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        func number(_ v: Any?) -> Double? {
            switch v {
            case let d as Double: return d
            case let i as Int: return Double(i)
            case let s as String: return Double(s.replacingOccurrences(of: "+", with: ""))
            default: return nil
            }
        }
        let reports: [SkyConditions] = array.compactMap { m in
            guard let id = m["icaoId"] as? String, let lat = number(m["lat"]), let lon = number(m["lon"]),
                  let time = number(m["obsTime"]) else { return nil }
            let clouds = (m["clouds"] as? [[String: Any]] ?? []).compactMap { c -> Layer? in
                guard let cover = c["cover"] as? String else { return nil }
                return Layer(cover: cover, baseFeet: Int(number(c["base"]) ?? 0))
            }
            // A sky-obscured report puts the vertical visibility in `vertVis` (hundreds of feet).
            var layers = clouds.filter { $0.cover != "CLR" && $0.cover != "SKC" && $0.cover != "CAVOK" }
            if let vv = number(m["vertVis"]) { layers.append(Layer(cover: "VV", baseFeet: Int(vv * 100))) }
            // `wdir` is degrees, or "VRB" for variable; 0 at 0 knots is calm.
            let speed = number(m["wspd"])
            let direction = (speed ?? 0) > 0 ? number(m["wdir"]) : nil
            return SkyConditions(station: id, stationName: m["name"] as? String, latitude: lat, longitude: lon,
                                 elevationFeet: Int(((number(m["elev"]) ?? 0) * 3.28084).rounded()),
                                 observedAt: Date(timeIntervalSince1970: time), visibilityMiles: number(m["visib"]),
                                 layers: layers, weather: m["wxString"] as? String,
                                 windFromDegrees: direction, windKnots: speed,
                                 seesHighCloud: (m["cover"] as? String) == "SKC" || layers.contains { $0.baseFeet > 12_000 })
        }
        // A station can report twice in the window (a special after the hourly): keep its latest.
        var latest: [String: SkyConditions] = [:]
        for r in reports where r.isFresh(at: now) {
            if let held = latest[r.station], held.observedAt >= r.observedAt { continue }
            latest[r.station] = r
        }
        return latest.values.sorted { $0.station < $1.station }
    }
}

/// Every fresh report around a place, and the one nearest it.
struct SkyReport: Equatable, Sendable {
    var nearest: SkyConditions?
    var all: [SkyConditions]

    static let none = SkyReport(nearest: nil, all: [])
}

// MARK: - Can I see it?

enum SkyVisibility: Equatable, Sendable {
    case visible
    /// After dark: only its lights. Visible, so nothing is said about it.
    case lights
    /// Under 3°: behind trees and roofs.
    case lowOnHorizon
    case aboveClouds(SkyConditions.Layer)
    /// Further than the haze lets you see.
    case haze(visibilityMiles: Double)
    /// Too small to make out at this range, on a clear day.
    case tooFar
    case nearSun

    var canSee: Bool { self == .visible || self == .lights }

    /// The hero's line; nil when there's nothing to say (you can see it, by day or by its
    /// lights).
    var text: String? {
        switch self {
        case .visible, .lights: return nil
        case .lowOnHorizon: return "Low on the horizon"
        case .aboveClouds(let layer): return "Above the clouds · \(layer.words) at \(RadarFormat.altitudeText(layer.baseFeet))"
        case .haze(let miles): return "Lost in the haze · \(RadarFormat.preciseDistance(miles)) visibility"
        case .tooFar: return "Too far away to make out"
        case .nearSun: return "Close to the sun: shade your eyes"
        }
    }

    /// For a tile: "Above the clouds", "Too far".
    var shortText: String {
        switch self {
        case .visible, .lights: return "Yes"
        case .lowOnHorizon: return "Low on horizon"
        case .aboveClouds: return "Above the clouds"
        case .haze: return "Lost in haze"
        case .tooFar: return "Too far"
        case .nearSun: return "Near the sun"
        }
    }

    var symbol: String {
        switch self {
        case .visible: return "eye"
        case .lights: return "moon.stars"
        case .lowOnHorizon: return "tree"
        case .aboveClouds: return "cloud"
        case .haze: return "sun.haze"
        case .tooFar: return "eye.slash"
        case .nearSun: return "sun.max"
        }
    }

    /// How far each shape can be picked out by eye on a clear day, slant range in miles.
    static func nakedEyeMiles(_ silhouette: AircraftSilhouette) -> Double {
        switch silhouette {
        case .widebody, .fourEngine: return 35
        case .airliner, .militaryTransport: return 25
        case .regional, .bizjet, .fighter: return 15
        case .twinProp: return 10
        case .light: return 5
        case .helicopter: return 4
        }
    }

    /// Under this the trees and roofs win.
    static let horizonDegrees = 3.0
    /// The sun's glare reaches this far around it.
    static let glareDegrees = 12.0
    /// The sun this far below the horizon: dark enough that it's lights only.
    static let darkSunDegrees = -6.0

    static func assess(elevation: Double, azimuth: Double, groundMiles: Double, altitudeFeet: Int, silhouette: AircraftSilhouette,
                       conditions: SkyConditions?, sun: SunPosition.Position?) -> SkyVisibility {
        if elevation < horizonDegrees { return .lowOnHorizon }
        let slant = (groundMiles * groundMiles + pow(Double(altitudeFeet) / 5280, 2)).squareRoot()
        if let conditions {
            if let ceiling = conditions.ceiling, altitudeFeet > ceiling.baseFeet + conditions.elevationFeet {
                return .aboveClouds(ceiling)
            }
            if let visibility = conditions.visibilityMiles, visibility < 10, slant > visibility {
                return .haze(visibilityMiles: visibility)
            }
        }
        let isDark = (sun?.elevation ?? 10) < darkSunDegrees
        if isDark {
            // Strobes and beacons carry much further than the shape does.
            return slant <= 30 ? .lights : .tooFar
        }
        if slant > nakedEyeMiles(silhouette) { return .tooFar }
        if let sun, sun.elevation > 0,
           SunPosition.separation(azimuth: azimuth, elevation: elevation, azimuth: sun.azimuth, elevation: sun.elevation) < glareDegrees {
            return .nearSun
        }
        return .visible
    }
}

extension RadarContact {
    /// Whether this aircraft can be seen from `observer` given the weather and the sun.
    func visibility(observer: CLLocationCoordinate2D, conditions: SkyConditions?, at date: Date) -> SkyVisibility {
        let elevation = GeoMath.elevationDegrees(groundDistanceMiles: distanceMiles, altitudeFeet: Double(altitudeFeet))
        let sun = SunPosition.at(date, latitude: observer.latitude, longitude: observer.longitude)
        return SkyVisibility.assess(elevation: elevation, azimuth: bearing, groundMiles: distanceMiles, altitudeFeet: altitudeFeet,
                                    silhouette: profile.silhouette, conditions: conditions?.isFresh(at: date) == true ? conditions : nil, sun: sun)
    }
}
