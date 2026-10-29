//
//  AltitudeSpeed.swift
//  WhatTheFlight
//
//  The data behind the Stats tab's altitude-vs-speed chart: one dot per sighting at its
//  closest pass, coloured by what kind of flight it was (airline, cargo, business jet,
//  general aviation, helicopter, military), plus the screen-space maths for picking a dot,
//  the one nearest a finger or the next one over for the Siri Remote. Built with each
//  `LogbookSky`, so the chart follows the Stats tab's choice of place. Kept free of SwiftUI so
//  it's unit-tested.
//

import Foundation
import CoreGraphics

// MARK: - Kind of flight

/// What kind of flight a sighting was, for the chart's colours. It comes from the operator
/// line, which already says "Private aircraft" or "Unlisted operator XYZ", and from the tags.
/// The first rule that matches wins: military, helicopter, general aviation, cargo, business
/// jet, then airline.
enum FlightKind: String, CaseIterable, Sendable {
    case airline, cargo, businessJet, generalAviation, helicopter, military

    /// Operator lines starting with one of these are military, as is anything tagged military.
    static let militaryPrefixes = ["US Air Force", "US Army", "US Navy"]
    /// The rest match anywhere in the operator line, ignoring case.
    static let helicopterWords = ["helicopter"]
    static let generalAviationWords = ["private", "unlisted"]
    static let cargoOperators = ["FedEx", "UPS", "DHL", "Kalitta", "Atlas", "Prime Air", "Air Transport", "Freight", "USA Jet", "Fret"]
    static let businessJetOperators = ["NetJets", "Flexjet", "Wheels Up", "Jet Linx", "Executive", "Jet Suite", "Jetex", "Gulfstream"]

    var title: String { Self.titles[self] ?? rawValue }

    /// Looked up once: the chart asks for every dot's title on every draw.
    private static let titles: [FlightKind: String] = Dictionary(uniqueKeysWithValues: allCases.map { kind in
        switch kind {
        case .airline: return (kind, String(localized: "Airline"))
        case .cargo: return (kind, String(localized: "Cargo"))
        case .businessJet: return (kind, String(localized: "Business jet"))
        case .generalAviation: return (kind, String(localized: "General aviation"))
        case .helicopter: return (kind, String(localized: "Helicopter"))
        case .military: return (kind, String(localized: "Military"))
        }
    })

    /// `isHelicopter` adds the type catalog's verdict to the operator line's, so an air
    /// ambulance or tour operator's helicopter counts as one.
    static func classify(operatorName: String, tags: [NotableTag] = [], isHelicopter: Bool = false) -> FlightKind {
        resolve(classify(operatorName: operatorName), tags: tags, isHelicopter: isHelicopter)
    }

    /// The operator line alone.
    static func classify(operatorName: String) -> FlightKind {
        let name = operatorName.lowercased()
        func starts(_ list: [String]) -> Bool { list.contains { name.hasPrefix($0.lowercased()) } }
        func mentions(_ list: [String]) -> Bool { list.contains { name.contains($0.lowercased()) } }
        if starts(militaryPrefixes) { return .military }
        if mentions(helicopterWords) { return .helicopter }
        if mentions(generalAviationWords) { return .generalAviation }
        if mentions(cargoOperators) { return .cargo }
        if mentions(businessJetOperators) { return .businessJet }
        return .airline
    }

    /// An operator's kind with the tags and the airframe applied: military first, then
    /// helicopters. Lets a caller classify each operator once and reuse it.
    static func resolve(_ operatorKind: FlightKind, tags: [NotableTag], isHelicopter: Bool) -> FlightKind {
        if operatorKind == .military || tags.contains(.military) { return .military }
        return isHelicopter ? .helicopter : operatorKind
    }
}

// MARK: - Points

/// One sighting on the chart: where it sat at its closest pass, and what the callout says.
struct AltitudeSpeedPoint: Identifiable, Sendable {
    /// The sighting's id.
    let id: String
    let kind: FlightKind
    let speedKnots: Int
    let altitudeFeet: Int
    /// Speed and altitude in the units in use, as plotted (the digest is rebuilt when the
    /// units change).
    let speed: Double
    let altitude: Double
    let firstSeen: Date
    /// Flight number, then callsign, then registration, then "?".
    let flight: String
    let typeCode: String?
    let origin: String?
    let destination: String?

    /// Sightings without a speed (on the ground, or a bad reading) aren't plotted.
    init?(_ s: Sighting, kind: FlightKind, units: UnitSystem = Units.current) {
        guard s.speedKnots > 0 else { return nil }
        id = s.id
        self.kind = kind
        speedKnots = s.speedKnots
        altitudeFeet = max(0, s.altitudeAtClosestFeet)
        speed = RadarFormat.speedValue(s.speedKnots, in: units)
        altitude = RadarFormat.altitudeValue(altitudeFeet, in: units)
        firstSeen = s.firstSeen
        // `displayIdentifier` falls back to the type code, or "UNKNOWN", once the rest run out.
        let display = s.displayIdentifier
        flight = display != "UNKNOWN" && display != s.typeCode ? display : s.callsign ?? s.registration ?? "?"
        typeCode = s.typeCode
        origin = s.originIATA
        destination = s.destinationIATA
    }

    /// "AA768 · Oct 19, 10:20 PM CT".
    func headline(locale: Locale = .current) -> String {
        "\(flight) · \(AltitudeSpeed.timeText(firstSeen, locale: locale))"
    }

    /// "Boeing 737-800", else the type code, else "Unknown".
    var model: String {
        AircraftTypeCatalog.name(forTypeCode: typeCode) ?? typeCode ?? String(localized: "Unknown")
    }

    /// "CLT → OKC", with "?" for an end the feed didn't give.
    var route: String { "\(origin ?? "?") → \(destination ?? "?")" }

    var altitudeText: String { RadarFormat.altitudeText(altitudeFeet) }
    var speedText: String { RadarFormat.speedText(speedKnots) }

    /// For VoiceOver: "AA768, Oct 19, 10:20 PM Central, Boeing 737-800, airline, 36,000 feet,
    /// 426 knots, CLT to OKC."
    var spokenSummary: String {
        let time = AltitudeSpeed.dayAndTime(firstSeen)
        var parts = [flight, "\(time) Central", model, kind.title.lowercased(),
                     RadarFormat.spokenAltitude(altitudeFeet), RadarFormat.spokenSpeed(speedKnots)]
        if origin != nil || destination != nil {
            parts.append("\(origin ?? "unknown") to \(destination ?? "unknown")")
        }
        return parts.joined(separator: ", ")
    }
}

enum AltitudeSpeed {
    /// The callout's times are US Central, whichever zone the device or the sighting is in.
    static let timeZone = TimeZone(identifier: "America/Chicago")!
    static let timeZoneLabel = "CT"

    /// "Oct 19, 10:20 PM", in Central time. Day and time are formatted apart: together they
    /// read "Oct 19 at 10:20 PM".
    static func dayAndTime(_ date: Date, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: timeZone)
        return "\(style.month(.abbreviated).day().format(date)), \(style.hour().minute().format(date))"
    }

    /// "Oct 19, 10:20 PM CT".
    static func timeText(_ date: Date, locale: Locale = .current) -> String {
        "\(dayAndTime(date, locale: locale)) \(timeZoneLabel)"
    }

    /// The speed axis: "100", with the unit on the last tick only: "500 kts".
    static func speedAxisLabel(_ value: Double, isLast: Bool, units: UnitSystem = Units.current) -> String {
        let number = RadarFormat.wholeNumber(Int(value.rounded()))
        return isLast ? "\(number) \(RadarFormat.speedUnit(units))" : number
    }

    /// The altitude axis, in thousands: "0", "10k ft", "2.5k ft"; metric "0", "3 km".
    static func altitudeAxisLabel(_ value: Double, units: UnitSystem = Units.current) -> String {
        guard value > 0 else { return "0" }
        let thousands = (value / 1_000).formatted(.number.precision(.fractionLength(0...1)))
        return units == .metric ? "\(thousands) km" : "\(thousands)k ft"
    }
}

/// Every plotted sighting of one sky, with the axes and the kinds the legend lists.
struct AltitudeSpeedSet: Sendable {
    let points: [AltitudeSpeedPoint]
    /// The kinds that appear, in `FlightKind.allCases` order.
    let kinds: [FlightKind]
    /// Both axes start at zero and end a little past the fastest and the highest, in the
    /// units in use.
    let speedDomain: ClosedRange<Double>
    let altitudeDomain: ClosedRange<Double>
    /// Changes whenever a dot would: a new sighting, or a closer pass moving one. Lets the
    /// chart skip redrawing thousands of dots when nothing moved.
    let fingerprint: Int

    static let empty = AltitudeSpeedSet([])

    init(_ points: [AltitudeSpeedPoint], units: UnitSystem = Units.current) {
        self.points = points
        let present = Set(points.map(\.kind))
        kinds = FlightKind.allCases.filter(present.contains)
        let fastest = points.map(\.speed).max() ?? 0
        let highest = points.map(\.altitude).max() ?? 0
        speedDomain = 0...max(RadarFormat.speedValue(100, in: units), fastest * 1.04)
        altitudeDomain = 0...max(RadarFormat.altitudeValue(5_000, in: units), highest * 1.06)
        var hasher = Hasher()
        for p in points {
            hasher.combine(p.id)
            hasher.combine(p.speed)
            hasher.combine(p.altitude)
            hasher.combine(p.kind)
        }
        fingerprint = hasher.finalize()
    }

    var count: Int { points.count }
    var isEmpty: Bool { points.isEmpty }

    /// Where point `index` sits in a plot of `size` (origin top-left, altitude up the screen).
    func position(of index: Int, in size: CGSize) -> CGPoint {
        let p = points[index]
        let x = (p.speed - speedDomain.lowerBound) / max(1, speedDomain.upperBound - speedDomain.lowerBound)
        let y = (p.altitude - altitudeDomain.lowerBound) / max(1, altitudeDomain.upperBound - altitudeDomain.lowerBound)
        return CGPoint(x: x * size.width, y: size.height - y * size.height)
    }

    /// Every point's place in a plot of `size`.
    func positions(in size: CGSize) -> [CGPoint] {
        points.indices.map { position(of: $0, in: size) }
    }

    /// The next sighting by speed (then altitude) from `index`, or the previous one with a
    /// negative `step`, for VoiceOver's swipe up and down. nil past either end.
    func step(from index: Int, by step: Int) -> Int? {
        guard points.indices.contains(index) else { return nil }
        func key(_ i: Int) -> (Double, Double, Int) { (points[i].speed, points[i].altitude, i) }
        let here = key(index)
        let candidates = points.indices.filter { step > 0 ? key($0) > here : key($0) < here }
        return step > 0 ? candidates.min { key($0) < key($1) } : candidates.max { key($0) < key($1) }
    }

    /// "2,914 sightings: 2,310 airline, 214 cargo, 180 general aviation…", for VoiceOver.
    var summary: String {
        var counts: [FlightKind: Int] = [:]
        for p in points { counts[p.kind, default: 0] += 1 }
        let kinds = kinds.map { "\(RadarFormat.wholeNumber(counts[$0] ?? 0)) \($0.title.lowercased())" }
        return "\(RadarFormat.wholeNumber(count)) sightings: \(kinds.joined(separator: ", "))"
    }

    /// Where the Siri Remote starts: the airliner nearest the middle of the chart (each axis
    /// scaled to its range), else the first point. Not the median: most skies are mostly
    /// light aircraft, which would start it in the crowd at the bottom left.
    var startIndex: Int? {
        guard !points.isEmpty else { return nil }
        let midSpeed = (speedDomain.lowerBound + speedDomain.upperBound) / 2
        let midAltitude = (altitudeDomain.lowerBound + altitudeDomain.upperBound) / 2
        let xRange = max(1, speedDomain.upperBound - speedDomain.lowerBound)
        let yRange = max(1, altitudeDomain.upperBound - altitudeDomain.lowerBound)
        let airliners = points.indices.filter { points[$0].kind == .airline }
        return airliners.min { a, b in
            func distance(_ i: Int) -> Double {
                let dx = (points[i].speed - midSpeed) / xRange, dy = (points[i].altitude - midAltitude) / yRange
                return dx * dx + dy * dy
            }
            return distance(a) < distance(b)
        } ?? 0
    }
}

// MARK: - Picking a dot

/// A step through a chart: the Siri Remote's arrows, or VoiceOver's swipes.
enum ChartDirection: Sendable {
    case left, right, up, down

    /// A unit step on screen: up is toward the top, so y falls.
    var vector: CGVector {
        switch self {
        case .left: return CGVector(dx: -1, dy: 0)
        case .right: return CGVector(dx: 1, dy: 0)
        case .up: return CGVector(dx: 0, dy: -1)
        case .down: return CGVector(dx: 0, dy: 1)
        }
    }
}

/// Screen-space picking for a scatter chart, in the plot's own points (y down).
enum ScatterPicking {

    /// The dot nearest `location`, if one is within `radius`. Ties go to the earlier dot.
    static func nearest(to location: CGPoint, in positions: [CGPoint], within radius: CGFloat) -> Int? {
        var best: Int?
        var bestDistance = radius * radius
        for (i, p) in positions.enumerated() {
            let dx = p.x - location.x, dy = p.y - location.y
            let d = dx * dx + dy * dy
            if d < bestDistance || (d == bestDistance && best == nil) {
                best = i
                bestDistance = d
            }
        }
        return best
    }

    /// The remote's step: the nearest dot within 45° of `direction`, or within 80° when that
    /// cone is empty. The TV's plot is about four times wider than it's tall, so straight
    /// up from most dots is empty and "up" would otherwise do nothing; this way only the edge
    /// of the data stops it. nil past the edge.
    static func step(from index: Int, toward direction: ChartDirection, in positions: [CGPoint], minimumDistance: CGFloat = 0) -> Int? {
        neighbor(of: index, toward: direction, in: positions, cone: 45, minimumDistance: minimumDistance)
            ?? neighbor(of: index, toward: direction, in: positions, cone: 80, minimumDistance: minimumDistance)
    }

    /// Where a callout of `size` goes beside a dot at `anchor`, inside a plot of `bounds`:
    /// centred above the dot; beside it (right, else left) when there's no room above; below
    /// it when neither side fits. Never outside the plot, so it moves rather than clips.
    static func calloutOrigin(size: CGSize, anchor: CGPoint, in bounds: CGSize, gap: CGFloat) -> CGPoint {
        func clamp(_ v: CGFloat, _ length: CGFloat, _ limit: CGFloat) -> CGFloat { min(max(0, v), max(0, limit - length)) }
        let centredX = clamp(anchor.x - size.width / 2, size.width, bounds.width)
        if anchor.y - gap - size.height >= 0 {
            return CGPoint(x: centredX, y: anchor.y - gap - size.height)
        }
        let besideY = clamp(anchor.y - size.height / 2, size.height, bounds.height)
        if anchor.x + gap + size.width <= bounds.width {
            return CGPoint(x: anchor.x + gap, y: besideY)
        }
        if anchor.x - gap - size.width >= 0 {
            return CGPoint(x: anchor.x - gap - size.width, y: besideY)
        }
        return CGPoint(x: centredX, y: clamp(anchor.y + gap, size.height, bounds.height))
    }

    /// The nearest dot from `index` toward `direction`: within `cone` degrees either side of
    /// it and more than `minimumDistance` away, so dots drawn on top of each other count as
    /// one place. nil at the edge of the data.
    static func neighbor(of index: Int, toward direction: ChartDirection, in positions: [CGPoint],
                         cone: Double = 45, minimumDistance: CGFloat = 0) -> Int? {
        guard positions.indices.contains(index) else { return nil }
        let origin = positions[index]
        let step = direction.vector
        // Inside the cone: the angle off `direction` is at most `cone`, i.e. the step's share
        // of the distance is at least cos(cone). A hair of slack keeps exact diagonals in.
        let minCosine = cos(cone * .pi / 180) - 1e-9
        var best: Int?
        var bestDistance = CGFloat.infinity
        for (i, p) in positions.enumerated() where i != index {
            let dx = p.x - origin.x, dy = p.y - origin.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance > minimumDistance, distance < bestDistance else { continue }
            let along = dx * step.dx + dy * step.dy
            guard along > 0, Double(along / distance) >= minCosine else { continue }
            best = i
            bestDistance = distance
        }
        return best
    }
}

extension AltitudeSpeedSet {
    /// Every sighting with a speed. Each operator is classified once: most fly many times.
    init(sightings: [Sighting], units: UnitSystem = Units.current) {
        var operatorKinds: [String: FlightKind] = [:]
        var points: [AltitudeSpeedPoint] = []
        points.reserveCapacity(sightings.count)
        for s in sightings where s.speedKnots > 0 {
            let operatorKind: FlightKind
            if let known = operatorKinds[s.operatorName] {
                operatorKind = known
            } else {
                operatorKind = FlightKind.classify(operatorName: s.operatorName)
                operatorKinds[s.operatorName] = operatorKind
            }
            let kind = FlightKind.resolve(operatorKind, tags: s.tags, isHelicopter: s.kind == .helicopter)
            if let point = AltitudeSpeedPoint(s, kind: kind, units: units) { points.append(point) }
        }
        self.init(points, units: units)
    }
}
