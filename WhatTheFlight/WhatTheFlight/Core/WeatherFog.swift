//
//  WeatherFog.swift
//  WhatTheFlight
//
//  Clouds and fog over the radar and the map (Settings → Radar → Clouds and fog). Built from
//  Apple Weather at five points around the radar (`CloudSample`, fetched by
//  `Services/CloudCoverProvider.swift`), or, when that isn't available, from every METAR
//  around (`SkyConditions`): each point's cloud and its fog, mist or haze, blended between
//  points by inverse-distance weighting, drifting downwind. Either way it's broadly where the
//  weather is, not a satellite picture. The drawing is `UI/WeatherFogLayer.swift`.
//

import Foundation
import CoreLocation

struct WeatherFog: Equatable, Sendable {
    struct Station: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
        /// Cloud up to 12,000 ft, which every station sees: 0 clear … 1 overcast.
        let lowCloud: Double
        /// Cloud above that; nil when the station can't see so high (an automated "CLR").
        var highCloud: Double? = nil
        /// Fog, mist, haze or smoke near the ground: 0 … 1.
        let fog: Double

        var cloud: Double { Self.stack(lowCloud, highCloud ?? 0) }

        static func stack(_ a: Double, _ b: Double) -> Double { 1 - (1 - a) * (1 - b) }
    }

    /// Samples east-north around a centre, `count` × `count`, row 0 along the north edge.
    struct Grid: Equatable, Sendable {
        let count: Int
        let cloud: [Double]
        let fog: [Double]

        var maxCloud: Double { cloud.max() ?? 0 }
        var maxFog: Double { fog.max() ?? 0 }
        /// The same everywhere (one station, or stations that agree): no mask needed.
        var isUniform: Bool {
            guard let c = cloud.first, let f = fog.first else { return true }
            return cloud.allSatisfy { abs($0 - c) < 0.02 } && fog.allSatisfy { abs($0 - f) < 0.02 }
        }
    }

    let stations: [Station]
    /// Where the clouds drift to, degrees clockwise from north (the wind blows from the
    /// reported direction, so this is opposite it).
    let driftBearing: Double
    /// The nearest report's wind; calm and missing read as a breeze, so the clouds still move.
    let windKnots: Double

    /// How far out the fog is drawn for a radius: past the map's fringe (1.5×) with room to
    /// fade out.
    static func reachMiles(radius: Double) -> Double { radius * 2.5 }

    /// Below this, cloud or fog isn't worth drawing.
    static let threshold = 0.04
    /// Automated stations see cloud up to here and no higher.
    static let highCloudFeet = 12_000
    /// Calm or variable wind still drifts the clouds, eastward like the prevailing westerlies.
    static let minimumWindKnots = 4.0

    /// Nil when every fresh report is clear.
    init?(reports: [SkyConditions], near observer: CLLocationCoordinate2D? = nil, at date: Date = Date()) {
        let fresh = reports.filter { $0.isFresh(at: date) }
        let stations = fresh.map {
            Station(latitude: $0.latitude, longitude: $0.longitude,
                    lowCloud: Self.cloud(from: $0.layers.filter { $0.baseFeet <= Self.highCloudFeet }),
                    highCloud: $0.seesHighCloud ? Self.cloud(from: $0.layers.filter { $0.baseFeet > Self.highCloudFeet }) : nil,
                    fog: Self.fog(visibilityMiles: $0.visibilityMiles, weather: $0.weather, layers: $0.layers))
        }
        guard stations.contains(where: { $0.cloud >= Self.threshold || $0.fog >= Self.threshold }) else { return nil }
        self.stations = stations
        // The nearest report that gives a direction says which way they go.
        let windy = fresh.filter { $0.windFromDegrees != nil }
        let nearest = observer.flatMap { o in
            windy.min { GeoMath.distanceMiles(from: o, to: $0.coordinate) < GeoMath.distanceMiles(from: o, to: $1.coordinate) }
        } ?? windy.first
        if let nearest, let from = nearest.windFromDegrees {
            driftBearing = GeoMath.normalize(from + 180)
            windKnots = max(Self.minimumWindKnots, nearest.windKnots ?? 0)
        } else {
            driftBearing = 90
            windKnots = Self.minimumWindKnots
        }
    }

    /// From Apple Weather's samples; nil when they're all clear (it is clear: not a reason to
    /// fall back to the airports).
    init?(samples: [CloudSample], at date: Date = Date()) {
        let fresh = samples.filter { date.timeIntervalSince($0.observedAt) < CloudSample.freshFor }
        let stations = fresh.map {
            Station(latitude: $0.latitude, longitude: $0.longitude,
                    // Medium (1.8–6.3 km) is as thick as low; high is cirrus, counted half as for METARs.
                    lowCloud: Station.stack($0.low, $0.medium), highCloud: $0.high * 0.5,
                    fog: Self.fog(visibilityMiles: $0.visibilityMiles, weather: $0.condition?.metarCode, layers: []))
        }
        guard stations.contains(where: { $0.cloud >= Self.threshold || $0.fog >= Self.threshold }) else { return nil }
        self.stations = stations
        // The centre sample (the first) says which way they drift.
        if let wind = fresh.first(where: { $0.windFromDegrees != nil }), let from = wind.windFromDegrees {
            driftBearing = GeoMath.normalize(from + 180)
            windKnots = max(Self.minimumWindKnots, wind.windKnots ?? 0)
        } else {
            driftBearing = 90
            windKnots = Self.minimumWindKnots
        }
    }

    init(stations: [Station], driftBearing: Double = 90, windKnots: Double = Self.minimumWindKnots) {
        self.stations = stations
        self.driftBearing = driftBearing
        self.windKnots = windKnots
    }

    // MARK: Per station

    /// The share of the sky each report's layers cover, stacked: two scattered layers cover
    /// more than one. Cirrus (18,000 ft and up) counts for half, being thin.
    static func cloud(from layers: [SkyConditions.Layer]) -> Double {
        var clear = 1.0
        for layer in layers {
            let cover: Double
            switch layer.cover {
            case "FEW": cover = 0.2
            case "SCT": cover = 0.45
            case "BKN": cover = 0.75
            case "OVC", "OVX": cover = 1
            case "VV": cover = 0.6     // sky hidden by fog: the fog carries it
            default: cover = 0
            }
            clear *= 1 - cover * (layer.baseFeet >= 18_000 ? 0.5 : 1)
        }
        return min(1, max(0, 1 - clear))
    }

    /// Fog from the weather codes (FG fog, BR mist, HZ haze, FU smoke, DU/SA dust and sand),
    /// a hidden sky (VV), or simply poor visibility, whichever says most.
    static func fog(visibilityMiles: Double?, weather: String?, layers: [SkyConditions.Layer]) -> Double {
        var fog = 0.0
        if layers.contains(where: { $0.cover == "VV" }) { fog = 1 }
        for token in (weather ?? "").split(separator: " ") {
            let code = token.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
            if code.hasSuffix("FG") {
                // Shallow, patchy or partial fog (MIFG, BCFG, PRFG) covers less.
                fog = max(fog, ["MI", "BC", "PR"].contains(where: code.hasPrefix) ? 0.5 : 0.9)
            } else if code.contains("BR") {
                fog = max(fog, 0.45)
            } else if code.contains("FU") {
                fog = max(fog, 0.4)
            } else if code.contains("HZ") || code.contains("DU") || code.contains("SA") {
                fog = max(fog, 0.3)
            }
        }
        if let v = visibilityMiles, v < 7 {
            fog = max(fog, (7 - max(0, v)) / 7 * 0.8)
        }
        return min(1, fog)
    }

    // MARK: Anywhere

    /// Cloud and fog at a point, blended from the stations: the nearer, the more it counts.
    /// High cloud only blends between stations that can see it, so one airport's report of
    /// cirrus isn't thinned out by its automated neighbours' "clear below 12,000 ft".
    func sample(latitude: Double, longitude: Double) -> (cloud: Double, fog: Double) {
        let here = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        var weight = 0.0, low = 0.0, fog = 0.0, highWeight = 0.0, high = 0.0
        for s in stations {
            let miles = GeoMath.distanceMiles(from: here, to: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude))
            // Softened so a point right on a station doesn't take only its report.
            let w = 1 / (miles * miles + 25)
            weight += w
            low += w * s.lowCloud
            fog += w * s.fog
            if let h = s.highCloud {
                highWeight += w
                high += w * h
            }
        }
        guard weight > 0 else { return (0, 0) }
        return (Station.stack(low / weight, highWeight > 0 ? high / highWeight : 0), fog / weight)
    }

    /// `count` × `count` samples spanning `halfMiles` either side of `center`, row 0 north,
    /// column 0 west.
    func grid(center: CLLocationCoordinate2D, halfMiles: Double, count: Int) -> Grid {
        let n = max(2, count)
        let milesPerDegreeLongitude = max(1, 69.17 * cos(center.latitude * .pi / 180))
        var cloud: [Double] = [], fog: [Double] = []
        cloud.reserveCapacity(n * n)
        fog.reserveCapacity(n * n)
        for row in 0..<n {
            let north = halfMiles * (1 - 2 * Double(row) / Double(n - 1))
            for column in 0..<n {
                let east = halfMiles * (2 * Double(column) / Double(n - 1) - 1)
                let s = sample(latitude: center.latitude + north / 69.0, longitude: center.longitude + east / milesPerDegreeLongitude)
                cloud.append(s.cloud)
                fog.append(s.fog)
            }
        }
        return Grid(count: n, cloud: cloud, fog: fog)
    }

    /// How far the clouds have drifted after `seconds`, in tiles of the cloud texture east and
    /// south (screen axes before the radar turns). A 15-knot wind moves them a tile (about a
    /// screen) every two minutes, sped up so it shows; the real thing takes hours.
    func drift(after seconds: Double) -> (east: Double, south: Double) {
        let tiles = seconds * windKnots / 15 / 120
        let bearing = driftBearing * .pi / 180
        return (tiles * sin(bearing), -tiles * cos(bearing))
    }
}

// MARK: - Apple Weather samples

/// Apple Weather's current conditions at one point: cloud by height, visibility, fog or haze,
/// and the wind. Stored, so a relaunch within the refresh doesn't ask again.
struct CloudSample: Codable, Equatable, Sendable {
    enum Obscuration: String, Codable, Sendable {
        case fog, haze, smoke, dust

        /// The METAR code it reads as, so both sources go through `WeatherFog.fog`.
        var metarCode: String {
            switch self {
            case .fog: return "FG"
            case .haze: return "HZ"
            case .smoke: return "FU"
            case .dust: return "DU"
            }
        }
    }

    let latitude: Double
    let longitude: Double
    /// Share of the sky, 0 … 1: low is up to 1.8 km, medium to 6.3 km, high above.
    let low: Double
    let medium: Double
    let high: Double
    let visibilityMiles: Double?
    let condition: Obscuration?
    /// Where the wind blows from, degrees true.
    let windFromDegrees: Double?
    let windKnots: Double?
    let observedAt: Date

    /// Older than this, it isn't drawn.
    static let freshFor: TimeInterval = 2 * 3600

    /// Where to ask: you, and the four compass points at the map's fringe (1.5 × the radius),
    /// so the blend has something to go on across the whole map. The centre comes first.
    static func points(around center: CLLocationCoordinate2D, radiusMiles: Double) -> [CLLocationCoordinate2D] {
        [center] + [0.0, 90, 180, 270].map { GeoMath.destination(from: center, bearingDegrees: $0, distanceMiles: radiusMiles * 1.5) }
    }
}

/// How many Apple Weather calls this device has made today, so one device can't run through
/// the developer account's monthly allowance (500,000 calls, shared by every user).
struct WeatherKitBudget: Codable, Equatable, Sendable {
    /// Five points every 15 minutes is 20 an hour: fifteen hours of radar a day.
    static let dailyCap = 300

    private(set) var day: String = ""
    private(set) var calls = 0

    static func dayKey(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    func canSpend(_ n: Int, at date: Date) -> Bool {
        (day == Self.dayKey(date) ? calls : 0) + n <= Self.dailyCap
    }

    mutating func spend(_ n: Int, at date: Date) {
        let today = Self.dayKey(date)
        if day != today { day = today; calls = 0 }
        calls += n
    }
}

/// A set of samples and where and when they were taken, for reuse.
struct CloudSampleSet: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let radiusMiles: Double
    let fetchedAt: Date
    let samples: [CloudSample]

    /// Still good for this place and radius: under the refresh old, the centre within 5 mi
    /// and the radius within a fifth.
    func covers(_ center: CLLocationCoordinate2D, radiusMiles radius: Double, at date: Date, refresh: TimeInterval) -> Bool {
        date.timeIntervalSince(fetchedAt) < refresh
            && GeoMath.distanceMiles(from: center, to: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) < 5
            && abs(radius - radiusMiles) <= radiusMiles * 0.2
    }
}

/// What a weather fetch depends on: the ~7 km square, how far out the fog reaches, and
/// whether the fog is on (Apple Weather is only asked for it).
struct WeatherFetchKey: Equatable {
    let area: String
    let reachMiles: Double
    var fog = true
}

extension SkyConditions {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
