//
//  LogbookSky.swift
//  WhatTheFlight
//
//  What a place's sky is like: when it's busiest, which way aircraft fly over it and how high
//  they pass. Those depend on where you watch from (runways, approach paths, the local rush
//  hours), so a trip away shouldn't blur home's pattern. The logbook groups sightings into
//  spots by where they were watched from and works the sky out for each spot as well as for
//  everywhere. A chart only shows once `LogbookSky.minimum` aircraft back it up, and hours are
//  local time where each aircraft was seen.
//

import Foundation
import CoreLocation

// MARK: - One sky

/// The chart data for one spot's sky, or everywhere's.
struct LogbookSky: Sendable {
    /// Aircraft a chart needs before it shows. Fewer describes an afternoon (one runway
    /// direction, the hours you happened to look up) rather than the place.
    static let minimum = 50
    /// Altitude bands of 5,000 ft, or 1,500 m with metric units (the digest is rebuilt when
    /// the units change).
    static var altitudeBandFeet: Double { Units.isMetric ? 1_500 / UnitSystem.metersPerFoot : 5_000 }
    static let altitudeBands = 9

    /// "10–15k" / "3–4.5 km", the top band open-ended: "40k+ ft" / "12+ km".
    static func altitudeBandLabel(_ index: Int, units: UnitSystem = Units.current) -> String {
        let top = index == altitudeBands - 1
        if units == .metric {
            func km(_ i: Int) -> String { (Double(i) * 1.5).formatted(.number.precision(.fractionLength(0...1))) }
            return top ? "\(km(index))+ km" : "\(km(index))–\(km(index + 1))"
        }
        return top ? "\(index * 5)k+ ft" : "\(index * 5)–\((index + 1) * 5)k"
    }

    let count: Int
    /// Aircraft first seen in each hour of the day, local time where they were seen, midnight first.
    let hourly: [Int]
    /// Aircraft per weekday, local time, Sunday first (`Calendar` weekday 1).
    let weekdays: [Int]
    /// Tracks at the closest pass in 16 compass sectors, north first.
    let headings: [Int]
    /// Altitude at the closest pass in 5,000 ft (or 1,500 m) bands; the last is open-ended.
    let altitudes: [Int]
    #if !os(watchOS)
    /// Every aircraft with a speed, at its closest pass, for the altitude-vs-speed chart. The
    /// Watch has no such chart, so it skips the work.
    let altitudeSpeed: AltitudeSpeedSet
    /// Where they were flying from and to, between the busiest route airports.
    let routeWeb: RouteWeb
    #endif

    /// Aircraft with a heading (sightings from before headings were logged have none).
    var headed: Int { headings.reduce(0, +) }
    var withAltitude: Int { altitudes.reduce(0, +) }

    /// Enough aircraft for the hour and weekday charts, the rose, the altitude chart.
    var showsTimes: Bool { count >= Self.minimum }
    var showsHeadings: Bool { headed >= Self.minimum }
    var showsAltitudes: Bool { withAltitude >= Self.minimum }
    #if !os(watchOS)
    var showsAltitudeSpeed: Bool { altitudeSpeed.count >= Self.minimum }
    /// Enough aircraft with a known route, and at least two airports to join.
    var showsRouteWeb: Bool { routeWeb.routed >= Self.minimum && routeWeb.airports.count > 1 }
    #endif
    /// No chart has enough behind it yet.
    var isFillingIn: Bool { !showsTimes && !showsHeadings && !showsAltitudes }

    /// Each sighting goes in its own time zone; ones logged before time zones were recorded
    /// use `fallbackZone` (a spot's usual zone), then the calendar's.
    init(_ sightings: [Sighting], fallbackZone: String? = nil, calendar: Calendar = .current) {
        var hourly = Array(repeating: 0, count: 24)
        var weekdays = Array(repeating: 0, count: 7)
        var headings = Array(repeating: 0, count: 16)
        var altitudes = Array(repeating: 0, count: Self.altitudeBands)
        let bandFeet = Self.altitudeBandFeet
        var clocks = SkyClocks(calendar, fallbackZone: fallbackZone)
        for s in sightings {
            hourly[clocks.hour(of: s)] += 1
            weekdays[clocks.weekday(of: s)] += 1
            if let sector = Self.sector(of: s) { headings[sector] += 1 }
            if let band = Self.altitudeBand(of: s, bandFeet: bandFeet) { altitudes[band] += 1 }
        }
        count = sightings.count
        self.hourly = hourly
        self.weekdays = weekdays
        self.headings = headings
        self.altitudes = altitudes
        #if !os(watchOS)
        altitudeSpeed = AltitudeSpeedSet(sightings: sightings)
        routeWeb = RouteWeb(sightings)
        #endif
    }

    /// The rose's sector for its track at the closest pass: 0 = north, clockwise in 22.5° steps.
    static func sector(of s: Sighting) -> Int? {
        s.trackAtClosest.map { Int(((GeoMath.normalize($0) + 11.25) / 22.5).rounded(.down)) % 16 }
    }

    /// Its altitude band at the closest pass, or nil on the ground.
    static func altitudeBand(of s: Sighting, bandFeet: Double = altitudeBandFeet) -> Int? {
        guard s.altitudeAtClosestFeet > 0 else { return nil }
        return min(altitudeBands - 1, Int(Double(s.altitudeAtClosestFeet) / bandFeet))
    }

    /// "Below 5,000 ft", "10,000–15,000 ft", "40,000+ ft"; "3–4.5 km", "12+ km".
    static func altitudeBandTitle(_ index: Int, units: UnitSystem = Units.current) -> String {
        if units == .metric {
            func km(_ i: Int) -> String { (Double(i) * 1.5).formatted(.number.precision(.fractionLength(0...1))) }
            if index == 0 { return "Below \(km(1)) km" }
            return index == altitudeBands - 1 ? "\(km(index))+ km" : "\(km(index))–\(km(index + 1)) km"
        }
        func feet(_ i: Int) -> String { RadarFormat.wholeNumber(i * 5_000) }
        if index == 0 { return "Below \(feet(1)) ft" }
        return index == altitudeBands - 1 ? "\(feet(index))+ ft" : "\(feet(index))–\(feet(index + 1)) ft"
    }

    /// The bars a slice is one of: the rose's petals, the hours, the weekdays or the altitude bands.
    func bins(of slice: LogbookSkySlice) -> [Int] {
        switch slice {
        case .heading: return headings
        case .hour: return hourly
        case .weekday: return weekdays
        case .altitude: return altitudes
        }
    }

    /// The busiest hour of the day.
    var busiestHourOfDay: Int? {
        guard let max = hourly.max(), max > 0 else { return nil }
        return hourly.firstIndex(of: max)
    }

    /// The busiest weekday, 0 = Sunday.
    var busiestWeekday: Int? {
        guard let max = weekdays.max(), max > 0 else { return nil }
        return weekdays.firstIndex(of: max)
    }

    /// The busiest compass sectors (0 = N, 4 = E…) and their shares, busiest first.
    func topHeadings(_ limit: Int = 3) -> [(sector: Int, share: Double)] {
        let total = headed
        guard total > 0 else { return [] }
        return headings.enumerated().filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(limit)
            .map { (sector: $0.offset, share: Double($0.element) / Double(total)) }
    }

    /// The compass sector most aircraft were heading, and its share.
    var mainHeading: (degrees: Double, share: Double)? {
        let total = headed
        guard total > 0, let max = headings.max(), let i = headings.firstIndex(of: max) else { return nil }
        return (Double(i) * 22.5, Double(max) / Double(total))
    }

    /// The busiest sector, 0 = north.
    var mainSector: Int? {
        guard let max = headings.max(), max > 0 else { return nil }
        return headings.firstIndex(of: max)
    }

    /// The busiest altitude band.
    var busiestAltitudeBand: Int? {
        guard let max = altitudes.max(), max > 0 else { return nil }
        return altitudes.firstIndex(of: max)
    }
}

// MARK: - Local time

/// Each sighting's hour and weekday where it was seen: its own time zone, else a spot's usual
/// zone (sightings logged before zones were recorded), else the calendar's. A `DayClock` per
/// zone; sightings in a row nearly always share one, so it's fast in time order either way.
struct SkyClocks {
    private let base: Calendar
    private let fallbackZone: String?
    private var clocks: [String: DayClock] = [:]
    /// The zone `clock` runs in; "" is the calendar's.
    private var zone = ""
    private var clock: DayClock

    init(_ calendar: Calendar, fallbackZone: String? = nil) {
        base = calendar
        self.fallbackZone = fallbackZone
        clock = DayClock(calendar)
    }

    /// 0 = midnight.
    mutating func hour(of s: Sighting) -> Int {
        use(s)
        return clock.hour(of: s.firstSeen)
    }

    /// 0 = Sunday.
    mutating func weekday(of s: Sighting) -> Int {
        use(s)
        return (clock.weekday(of: s.firstSeen) - 1) % 7
    }

    private mutating func use(_ s: Sighting) {
        let z = s.timeZone ?? fallbackZone ?? ""
        guard z != zone else { return }
        clocks[zone] = clock
        zone = z
        clock = clocks[z] ?? DayClock(Self.calendar(base, in: z))
    }

    private static func calendar(_ base: Calendar, in zone: String) -> Calendar {
        guard !zone.isEmpty, let timeZone = TimeZone(identifier: zone) else { return base }
        var calendar = base
        calendar.timeZone = timeZone
        return calendar
    }
}

// MARK: - Slices

/// One petal or bar of a sky's charts, to see the aircraft behind it.
enum LogbookSkySlice: Hashable, Sendable {
    /// A petal of the rose: 16 sectors, 0 = north.
    case heading(Int)
    /// An hour of the day, local time where each was seen; 0 = midnight.
    case hour(Int)
    /// A day of the week, local time; 0 = Sunday.
    case weekday(Int)
    /// An altitude band at the closest pass (`LogbookSky.altitudeBands`).
    case altitude(Int)

    /// "Heading southwest", "8–9 AM", "Tuesdays", "10,000–15,000 ft".
    var title: String {
        switch self {
        case .heading(let i): return "Heading \(LogbookFormat.sectorWords[i % 16].lowercased())"
        case .hour(let h): return LogbookFormat.hourRange(h)
        case .weekday(let d): return "\(Calendar.current.weekdaySymbols[d % 7])s"
        case .altitude(let b): return LogbookSky.altitudeBandTitle(b)
        }
    }

    /// After its share: "24% heading southwest", "6% from 8–9 AM", "14% on Tuesdays",
    /// "31% at 30,000–35,000 ft".
    var phrase: String {
        switch self {
        case .heading(let i): return "heading \(LogbookFormat.sectorWords[i % 16].lowercased())"
        case .hour(let h): return "from \(LogbookFormat.hourRange(h))"
        case .weekday: return "on \(title)"
        case .altitude(let b): return b == 0 ? title.prefix(1).lowercased() + title.dropFirst() : "at \(title)"
        }
    }

    /// The chart it's part of.
    var chartTitle: String {
        switch self {
        case .heading: return String(localized: "Which way they fly")
        case .hour: return String(localized: "By hour")
        case .weekday: return String(localized: "By day of the week")
        case .altitude: return String(localized: "How high they pass")
        }
    }

    /// For "the 2nd busiest hour".
    var noun: String {
        switch self {
        case .heading: return "direction"
        case .hour: return "hour"
        case .weekday: return "day"
        case .altitude: return "altitude"
        }
    }

    /// Which bar it is.
    var index: Int {
        switch self {
        case .heading(let i), .hour(let i), .weekday(let i), .altitude(let i): return i
        }
    }

    /// The same chart's bar at `index`.
    func with(index: Int) -> LogbookSkySlice {
        switch self {
        case .heading: return .heading(index)
        case .hour: return .hour(index)
        case .weekday: return .weekday(index)
        case .altitude: return .altitude(index)
        }
    }

    func contains(_ s: Sighting, clocks: inout SkyClocks, bandFeet: Double) -> Bool {
        switch self {
        case .heading(let i): return LogbookSky.sector(of: s) == i
        case .hour(let h): return clocks.hour(of: s) == h
        case .weekday(let d): return clocks.weekday(of: s) == d
        case .altitude(let b): return LogbookSky.altitudeBand(of: s, bandFeet: bandFeet) == b
        }
    }
}

/// What one slice of a sky is made of: its share of the chart, where it ranks, and who's in it.
struct LogbookSliceSummary: Sendable {
    let slice: LogbookSkySlice
    /// The aircraft in it, in the order they were given (newest first from `Logbook.recent`).
    let sightings: [Sighting]
    /// Aircraft on the whole chart: those with a heading for the rose, in the air for the
    /// altitude chart, every one for hours and weekdays.
    let total: Int
    /// 1 = the chart's busiest bar; ties share a rank.
    let rank: Int
    /// The busiest three of each.
    let airlines: [LogbookRank]
    let types: [LogbookRank]
    let routes: [LogbookRank]
    /// The middle altitude at the closest pass, of those in the air.
    let typicalAltitudeFeet: Int?
    /// The hour most of them came by (nil for an hour's own slice).
    let busiestHour: Int?
    /// The sector most of them were heading (nil for a petal's own slice).
    let mainSector: Int?

    var count: Int { sightings.count }
    var share: Double { total > 0 ? Double(count) / Double(total) : 0 }
    var percent: Int { Int((share * 100).rounded()) }

    /// "The busiest direction", "2nd busiest hour".
    var rankText: String {
        rank == 1 ? "The busiest \(slice.noun)" : "\(Self.ordinal(rank)) busiest \(slice.noun)"
    }

    init(slice: LogbookSkySlice, sightings: [Sighting], sky: LogbookSky, clocks: SkyClocks) {
        self.slice = slice
        self.sightings = sightings
        let bins = sky.bins(of: slice)
        total = bins.reduce(0, +)
        let own = bins.indices.contains(slice.index) ? bins[slice.index] : sightings.count
        rank = bins.filter { $0 > own }.count + 1

        airlines = Array(LogbookDigest.rank(sightings, key: { $0.isAirline ? $0.operatorName : nil }) { key, _ in (key, nil) }.prefix(3))
        types = Array(LogbookDigest.rank(sightings, key: \.typeCode) { key, latest in (latest.typeName ?? key, key) }.prefix(3))
        routes = Array(LogbookDigest.rank(sightings, key: \.routeKey) { key, _ in (key.replacingOccurrences(of: "-", with: " → "), nil) }.prefix(3))

        let altitudes = sightings.map(\.altitudeAtClosestFeet).filter { $0 > 0 }.sorted()
        typicalAltitudeFeet = altitudes.isEmpty ? nil : altitudes[altitudes.count / 2]

        var clocks = clocks
        var hours = Array(repeating: 0, count: 24)
        var sectors = Array(repeating: 0, count: 16)
        for s in sightings {
            hours[clocks.hour(of: s)] += 1
            if let sector = LogbookSky.sector(of: s) { sectors[sector] += 1 }
        }
        func peak(_ counts: [Int]) -> Int? {
            guard let max = counts.max(), max > 0 else { return nil }
            return counts.firstIndex(of: max)
        }
        if case .hour = slice { busiestHour = nil } else { busiestHour = peak(hours) }
        if case .heading = slice { mainSector = nil } else { mainSector = peak(sectors) }
    }

    /// "2nd", "3rd", "11th".
    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (_, 11...13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }
}

// MARK: - Spots

/// Somewhere you watch from: the sightings logged within `radiusMiles` of it, and its sky.
struct LogbookSpot: Identifiable, Sendable {
    /// About a radar's reach: the suburbs round home share one sky; a town an hour's drive
    /// away gets its own.
    static let radiusMiles = 15.0

    /// The grid square it grew from ("338,-844"), so it keeps its id as the logbook grows.
    let id: String
    /// "Atlanta, GA": the place most of its sightings were logged under.
    let name: String
    let latitude: Double
    let longitude: Double
    let sky: LogbookSky
    let lastSeen: Date
    /// The grid squares (`square(_:)`) its sightings were watched from.
    let squares: Set<String>
    /// The place whose sightings without a position join it, if any.
    let adoptedPlace: String?
    /// The zone most of its sightings were logged in, for older ones without one.
    let timeZone: String?

    var count: Int { sky.count }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        GeoMath.distanceMiles(from: coordinate, to: c) <= Self.radiusMiles
    }

    /// Whether a sighting is part of this spot's sky (the way `spots(_:)` grouped it).
    func contains(_ s: Sighting) -> Bool {
        if let c = s.observerCoordinate { return squares.contains(Self.square(c)) }
        return s.placeName != nil && s.placeName == adoptedPlace
    }

    /// About 7 miles across: "338,-844".
    static func square(_ c: CLLocationCoordinate2D) -> String {
        "\(Int((c.latitude * 10).rounded())),\(Int((c.longitude * 10).rounded()))"
    }

    /// Groups sightings by where they were watched from, most sightings first. Squares of
    /// about 7 miles, busiest first, each join the nearest spot within `radiusMiles` or start
    /// a new one, so the result doesn't depend on the order things were logged. A sighting
    /// with no position joins the spot named after its place, if there is one.
    static func spots(_ sightings: [Sighting], calendar: Calendar = .current) -> [LogbookSpot] {
        var squares: [String: (count: Int, latitude: Double, longitude: Double)] = [:]
        for s in sightings {
            guard let c = s.observerCoordinate else { continue }
            let entry = squares[square(c)] ?? (0, 0, 0)
            squares[square(c)] = (entry.count + 1, entry.latitude + c.latitude, entry.longitude + c.longitude)
        }
        guard !squares.isEmpty else { return [] }

        var seeds: [(id: String, center: CLLocationCoordinate2D)] = []
        var spotOfSquare: [String: Int] = [:]
        let busiestFirst = squares.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        for (key, entry) in busiestFirst {
            let center = CLLocationCoordinate2D(latitude: entry.latitude / Double(entry.count), longitude: entry.longitude / Double(entry.count))
            let nearest = seeds.indices
                .map { (index: $0, miles: GeoMath.distanceMiles(from: seeds[$0].center, to: center)) }
                .min { $0.miles < $1.miles }
            if let nearest, nearest.miles <= radiusMiles {
                spotOfSquare[key] = nearest.index
            } else {
                spotOfSquare[key] = seeds.count
                seeds.append((key, center))
            }
        }

        // Each spot's name: the place most of its positioned sightings were logged under.
        var placeCounts = Array(repeating: [String: Int](), count: seeds.count)
        for s in sightings {
            guard let c = s.observerCoordinate, let i = spotOfSquare[square(c)], let place = s.placeName else { continue }
            placeCounts[i][place, default: 0] += 1
        }
        let places = placeCounts.map { counts in
            counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        }
        var spotNamed: [String: Int] = [:]
        for (i, place) in places.enumerated() {
            if let place, spotNamed[place] == nil { spotNamed[place] = i }
        }

        var members = Array(repeating: [Sighting](), count: seeds.count)
        for s in sightings {
            if let c = s.observerCoordinate, let i = spotOfSquare[square(c)] {
                members[i].append(s)
            } else if s.observerCoordinate == nil, let place = s.placeName, let i = spotNamed[place] {
                members[i].append(s)
            }
        }

        var squaresOf = Array(repeating: Set<String>(), count: seeds.count)
        for (key, i) in spotOfSquare { squaresOf[i].insert(key) }

        var spots: [LogbookSpot] = seeds.indices.map { i in
            var zones: [String: Int] = [:]
            for s in members[i] { if let z = s.timeZone { zones[z, default: 0] += 1 } }
            let zone = zones.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
            return LogbookSpot(id: seeds[i].id,
                               name: places[i] ?? coordinateName(seeds[i].center),
                               latitude: seeds[i].center.latitude, longitude: seeds[i].center.longitude,
                               sky: LogbookSky(members[i], fallbackZone: zone, calendar: calendar),
                               lastSeen: members[i].map(\.lastSeen).max() ?? .distantPast,
                               squares: squaresOf[i],
                               adoptedPlace: places[i].flatMap { spotNamed[$0] == i ? $0 : nil },
                               timeZone: zone)
        }
        .sorted { ($0.count, $0.lastSeen) > ($1.count, $1.lastSeen) }

        // Two spots that geocode to the same town: number the smaller ones.
        var used: [String: Int] = [:]
        for i in spots.indices {
            let n = (used[spots[i].name] ?? 0) + 1
            used[spots[i].name] = n
            if n > 1 { spots[i] = spots[i].renamed("\(spots[i].name) (\(n))") }
        }
        return spots
    }

    /// "33.75° N, 84.39° W", for a spot with no place name.
    static func coordinateName(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.2f° %@, %.2f° %@", abs(c.latitude), c.latitude >= 0 ? "N" : "S",
               abs(c.longitude), c.longitude >= 0 ? "E" : "W")
    }

    private func renamed(_ name: String) -> LogbookSpot {
        LogbookSpot(id: id, name: name, latitude: latitude, longitude: longitude, sky: sky, lastSeen: lastSeen,
                    squares: squares, adoptedPlace: adoptedPlace, timeZone: timeZone)
    }
}

// MARK: - Choosing a sky

/// Whose sky the Stats tab shows.
enum LogbookSkyScope: Hashable, Sendable {
    case spot(String)
    case everywhere
}

/// A resolved scope: the sky, and the spot it belongs to (nil for everywhere).
struct LogbookSkyChoice: Sendable {
    let scope: LogbookSkyScope
    let spot: LogbookSpot?
    let sky: LogbookSky

    /// "Atlanta, GA", or "All places".
    var title: String { spot?.name ?? "All places" }

    /// "1,240 aircraft · you're here", "1,240 aircraft · last logged Oct 3, 2026", or for
    /// everywhere "1,300 aircraft from 3 places".
    func detail(here: LogbookSpot?, places: Int) -> String {
        let count = "\(RadarFormat.wholeNumber(sky.count)) aircraft"
        guard let spot else { return places > 1 ? "\(count) from \(places) places" : count }
        if spot.id == here?.id { return "\(count) · you're here" }
        return "\(count) · last logged \(spot.lastSeen.formatted(date: .abbreviated, time: .omitted))"
    }
}

extension LogbookDigest {
    /// The spot you're at, if you've logged anything there.
    func spot(near coordinate: CLLocationCoordinate2D?) -> LogbookSpot? {
        guard let coordinate else { return nil }
        return spots
            .map { (spot: $0, miles: GeoMath.distanceMiles(from: $0.coordinate, to: coordinate)) }
            .filter { $0.miles <= LogbookSpot.radiusMiles }
            .min { $0.miles < $1.miles }?.spot
    }

    /// The sky to show. No choice yet (or a spot that's since merged into another): where you
    /// are, if any of its charts are ready, else the spot with the most sightings. With no
    /// positioned sightings at all, everywhere.
    func sky(_ scope: LogbookSkyScope?, near observer: CLLocationCoordinate2D?) -> LogbookSkyChoice {
        if scope == .everywhere {
            return LogbookSkyChoice(scope: .everywhere, spot: nil, sky: sky)
        }
        if case .spot(let id)? = scope, let spot = spots.first(where: { $0.id == id }) {
            return LogbookSkyChoice(scope: .spot(id), spot: spot, sky: spot.sky)
        }
        if let here = spot(near: observer), !here.sky.isFillingIn {
            return LogbookSkyChoice(scope: .spot(here.id), spot: here, sky: here.sky)
        }
        if let home = spots.first {
            return LogbookSkyChoice(scope: .spot(home.id), spot: home, sky: home.sky)
        }
        return LogbookSkyChoice(scope: .everywhere, spot: nil, sky: sky)
    }

    /// The aircraft behind one petal or bar of a spot's charts (nil = every place), in `all`'s
    /// order, counted exactly as the chart counts them. A spot that's gone has none.
    func sightings(in slice: LogbookSkySlice, spot id: String?, from all: [Sighting], calendar: Calendar = .current) -> [Sighting] {
        let spot = id.flatMap { id in spots.first { $0.id == id } }
        guard id == nil || spot != nil else { return [] }
        var clocks = SkyClocks(calendar, fallbackZone: spot?.timeZone)
        let bandFeet = LogbookSky.altitudeBandFeet
        return all.filter { s in
            (spot?.contains(s) ?? true) && slice.contains(s, clocks: &clocks, bandFeet: bandFeet)
        }
    }

    /// Those aircraft and what they add up to: their share of the chart, its rank, who they are.
    func summary(of slice: LogbookSkySlice, spot id: String?, from all: [Sighting], calendar: Calendar = .current) -> LogbookSliceSummary {
        let spot = id.flatMap { id in spots.first { $0.id == id } }
        return LogbookSliceSummary(slice: slice, sightings: sightings(in: slice, spot: id, from: all, calendar: calendar),
                                   sky: spot?.sky ?? sky, clocks: SkyClocks(calendar, fallbackZone: spot?.timeZone))
    }
}
