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
        // A clock per zone; sightings in a row nearly always share one. "" is the calendar's.
        var clocks: [String: DayClock] = [:]
        var zone = ""
        var clock = DayClock(calendar)
        for s in sightings {
            let z = s.timeZone ?? fallbackZone ?? ""
            if z != zone {
                clocks[zone] = clock
                zone = z
                clock = clocks[z] ?? DayClock(Self.calendar(calendar, in: z))
            }
            hourly[clock.hour(of: s.firstSeen)] += 1
            weekdays[(clock.weekday(of: s.firstSeen) - 1) % 7] += 1
            if let track = s.trackAtClosest {
                headings[Int(((GeoMath.normalize(track) + 11.25) / 22.5).rounded(.down)) % 16] += 1
            }
            if s.altitudeAtClosestFeet > 0 {
                altitudes[min(Self.altitudeBands - 1, Int(Double(s.altitudeAtClosestFeet) / bandFeet))] += 1
            }
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

    private static func calendar(_ base: Calendar, in zone: String) -> Calendar {
        guard !zone.isEmpty, let timeZone = TimeZone(identifier: zone) else { return base }
        var calendar = base
        calendar.timeZone = timeZone
        return calendar
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

    var count: Int { sky.count }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    func contains(_ c: CLLocationCoordinate2D) -> Bool {
        GeoMath.distanceMiles(from: coordinate, to: c) <= Self.radiusMiles
    }

    /// Groups sightings by where they were watched from, most sightings first. Squares of
    /// about 7 miles, busiest first, each join the nearest spot within `radiusMiles` or start
    /// a new one, so the result doesn't depend on the order things were logged. A sighting
    /// with no position joins the spot named after its place, if there is one.
    static func spots(_ sightings: [Sighting], calendar: Calendar = .current) -> [LogbookSpot] {
        func square(_ c: CLLocationCoordinate2D) -> String {
            "\(Int((c.latitude * 10).rounded())),\(Int((c.longitude * 10).rounded()))"
        }

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

        var spots: [LogbookSpot] = seeds.indices.map { i in
            var zones: [String: Int] = [:]
            for s in members[i] { if let z = s.timeZone { zones[z, default: 0] += 1 } }
            let zone = zones.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
            return LogbookSpot(id: seeds[i].id,
                               name: places[i] ?? coordinateName(seeds[i].center),
                               latitude: seeds[i].center.latitude, longitude: seeds[i].center.longitude,
                               sky: LogbookSky(members[i], fallbackZone: zone, calendar: calendar),
                               lastSeen: members[i].map(\.lastSeen).max() ?? .distantPast)
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
        LogbookSpot(id: id, name: name, latitude: latitude, longitude: longitude, sky: sky, lastSeen: lastSeen)
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
}
