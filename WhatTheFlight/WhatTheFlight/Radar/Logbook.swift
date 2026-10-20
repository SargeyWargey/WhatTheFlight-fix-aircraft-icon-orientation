//
//  Logbook.swift
//  WhatTheFlight
//
//  Every aircraft that came inside the radius, kept on this device: when you saw it, how
//  close it came, and whether it was anything special. Feeds the stats and the badges.
//

import Foundation
import Observation

struct Sighting: Codable, Identifiable, Hashable, Sendable {
    /// The feed's flight id: one per flight leg, so a repeat visit tomorrow is a new sighting.
    let id: String
    var firstSeen: Date
    var lastSeen: Date
    var displayIdentifier: String
    var callsign: String?
    var registration: String?
    var hex: String?
    var typeCode: String?
    var kind: AircraftKind
    var operatorName: String
    var isAirline: Bool
    var originIATA: String?
    var destinationIATA: String?
    var closestMiles: Double
    var altitudeAtClosestFeet: Int
    var speedKnots: Int
    var tags: [NotableTag]
    var placeName: String?

    /// The airframe, for "seen N times" (falls back to the hex code).
    var airframe: String? { registration ?? hex }
    var typeName: String? { AircraftTypeCatalog.name(forTypeCode: typeCode) }
}

@MainActor
@Observable
final class Logbook {
    /// Oldest first; use `recent` for display.
    private(set) var sightings: [Sighting] = []

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var index: [String: Int] = [:]
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var lastSave = Date.distantPast
    @ObservationIgnored private let maxEntries: Int

    /// `fileURL == nil` keeps everything in memory (tests, previews).
    init(fileURL: URL? = Logbook.defaultURL, maxEntries: Int = 10_000) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        load()
    }

    nonisolated static var defaultURL: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("Logbook.json")
    }

    var recent: [Sighting] { sightings.reversed() }
    var isEmpty: Bool { sightings.isEmpty }

    // MARK: Recording

    /// Call with the in-range contacts; cheap enough to run every tick.
    func record(_ contacts: [RadarContact], at date: Date = Date(), placeName: String? = nil) {
        guard !contacts.isEmpty else { return }
        for contact in contacts {
            let f = contact.flight
            if let i = index[f.id] {
                var s = sightings[i]
                s.lastSeen = date
                if contact.distanceMiles < s.closestMiles - 0.05 {
                    s.closestMiles = contact.distanceMiles
                    s.altitudeAtClosestFeet = f.altitudeFeet
                    s.speedKnots = f.groundSpeedKnots
                }
                let tags = Set(s.tags).union(f.notable.map(\.tag))
                if tags.count != s.tags.count { s.tags = tags.sorted() }
                // Only write back meaningful changes so observers aren't churned every second.
                if s.closestMiles != sightings[i].closestMiles || s.tags != sightings[i].tags
                    || date.timeIntervalSince(sightings[i].lastSeen) > 60 {
                    sightings[i] = s
                    isDirty = true
                }
            } else {
                let info = f.operatorInfo
                sightings.append(Sighting(
                    id: f.id, firstSeen: date, lastSeen: date, displayIdentifier: f.displayIdentifier,
                    callsign: f.callsign, registration: f.registration, hex: f.hex, typeCode: f.typeCode,
                    kind: f.kind, operatorName: info.title, isAirline: info.kind == .airline,
                    originIATA: f.originIATA, destinationIATA: f.destinationIATA,
                    closestMiles: contact.distanceMiles, altitudeAtClosestFeet: f.altitudeFeet,
                    speedKnots: f.groundSpeedKnots, tags: f.notable.map(\.tag), placeName: placeName
                ))
                index[f.id] = sightings.count - 1
                isDirty = true
            }
        }
        trimIfNeeded()
        if isDirty, date.timeIntervalSince(lastSave) > 30 { save() }
    }

    func timesSeen(airframe: String?) -> Int {
        guard let airframe else { return 0 }
        return sightings.reduce(0) { $0 + ($1.airframe == airframe ? 1 : 0) }
    }

    func firstSighting(airframe: String?) -> Sighting? {
        guard let airframe else { return nil }
        return sightings.first { $0.airframe == airframe }
    }

    /// "Seen 3 times before · first Oct 2, 2026" for an airframe already in the logbook.
    func seenBeforeSummary(for flight: Flight) -> String? {
        guard let airframe = flight.registration ?? flight.hex else { return nil }
        let earlier = sightings.filter { $0.airframe == airframe && $0.id != flight.id }
        guard let first = earlier.first else { return nil }
        let times = earlier.count == 1 ? "Seen once before" : "Seen \(earlier.count) times before"
        return "\(times) · first \(first.firstSeen.formatted(date: .abbreviated, time: .omitted))"
    }

    func delete(_ ids: Set<String>) {
        sightings.removeAll { ids.contains($0.id) }
        rebuildIndex()
        isDirty = true
        save()
    }

    func clear() {
        sightings = []
        index = [:]
        isDirty = true
        save()
    }

    // MARK: Persistence

    /// Writes pending changes now (call when the app goes to the background).
    func flush() {
        if isDirty { save() }
    }

    private func save() {
        lastSave = Date()
        isDirty = false
        guard let fileURL else { return }
        let snapshot = sightings
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // A failed write just means the next save tries again with everything.
            }
        }
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Sighting].self, from: data) else { return }
        sightings = decoded
        rebuildIndex()
    }

    private func trimIfNeeded() {
        guard sightings.count > maxEntries else { return }
        sightings.removeFirst(sightings.count - maxEntries)
        rebuildIndex()
    }

    private func rebuildIndex() {
        index = Dictionary(sightings.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, last in last })
    }
}

// MARK: - Stats

struct LogbookStats: Equatable, Sendable {
    var total = 0
    var today = 0
    var uniqueAirframes = 0
    var uniqueTypes = 0
    var uniqueAirlines = 0
    var helicopters = 0
    var notable = 0
    var closest: Sighting?
    var highest: Sighting?
    var fastest: Sighting?
    var topAirlines: [(name: String, count: Int)] = []
    var topTypes: [(name: String, count: Int)] = []

    static func == (lhs: LogbookStats, rhs: LogbookStats) -> Bool {
        lhs.total == rhs.total && lhs.today == rhs.today && lhs.uniqueAirframes == rhs.uniqueAirframes
            && lhs.uniqueTypes == rhs.uniqueTypes && lhs.uniqueAirlines == rhs.uniqueAirlines
            && lhs.closest == rhs.closest && lhs.highest == rhs.highest && lhs.fastest == rhs.fastest
    }

    init() {}

    init(_ sightings: [Sighting], now: Date = Date(), calendar: Calendar = .current) {
        total = sightings.count
        today = sightings.filter { calendar.isDate($0.firstSeen, inSameDayAs: now) }.count
        uniqueAirframes = Set(sightings.compactMap(\.airframe)).count
        uniqueTypes = Set(sightings.compactMap(\.typeCode)).count
        uniqueAirlines = Set(sightings.filter(\.isAirline).map(\.operatorName)).count
        helicopters = sightings.filter { $0.kind == .helicopter }.count
        notable = sightings.filter { !$0.tags.isEmpty }.count
        closest = sightings.min { $0.closestMiles < $1.closestMiles }
        highest = sightings.max { $0.altitudeAtClosestFeet < $1.altitudeAtClosestFeet }
        fastest = sightings.max { $0.speedKnots < $1.speedKnots }
        topAirlines = Self.top(sightings.filter(\.isAirline).map(\.operatorName))
        topTypes = Self.top(sightings.compactMap { $0.typeName ?? $0.typeCode })
    }

    private static func top(_ names: [String], limit: Int = 5) -> [(name: String, count: Int)] {
        Dictionary(names.map { ($0, 1) }, uniquingKeysWith: +)
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map { (name: $0.key, count: $0.value) }
    }
}

// MARK: - Badges

struct Achievement: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// What it takes: "Spot a Boeing 747".
    let detail: String
    /// A little more about it, for the badge's own screen.
    let about: String
    let symbol: String
    let progress: Int
    let target: Int
    /// The sighting that unlocked it (the target-th one to qualify).
    let unlockedBy: Sighting?
    /// The most recent qualifying sightings, newest first. For the "different airlines /
    /// types" badges, one per airline or type.
    let examples: [Sighting]

    var isUnlocked: Bool { progress >= target }
    var fraction: Double { min(1, Double(progress) / Double(max(target, 1))) }

    static let exampleLimit = 30

    /// `sightings` oldest first, as `Logbook.sightings` keeps them.
    static func all(for sightings: [Sighting], calendar: Calendar = .current) -> [Achievement] {
        func matching(_ predicate: (Sighting) -> Bool) -> [Sighting] { sightings.filter(predicate) }
        func type(_ codes: Set<String>) -> [Sighting] { matching { codes.contains($0.typeCode ?? "") } }
        /// The first sighting of each distinct key, in the order they were first seen.
        func distinct(_ key: (Sighting) -> String?) -> [Sighting] {
            var seen = Set<String>()
            return sightings.filter { s in
                guard let k = key(s), !seen.contains(k) else { return false }
                seen.insert(k)
                return true
            }
        }
        func make(_ id: String, _ title: String, _ detail: String, _ symbol: String, target: Int,
                  _ qualifying: [Sighting], about: String) -> Achievement {
            Achievement(id: id, title: title, detail: detail, about: about, symbol: symbol,
                        progress: qualifying.count, target: target,
                        unlockedBy: qualifying.count >= target ? qualifying[target - 1] : nil,
                        examples: Array(qualifying.suffix(exampleLimit).reversed()))
        }

        return [
            make("first", "First Contact", "Log your first aircraft", "airplane", target: 1, sightings,
                 about: "Every logbook starts somewhere. Any aircraft that comes inside your radius counts."),
            make("spotter", "Plane Spotter", "Log 50 aircraft", "binoculars.fill", target: 50, sightings,
                 about: "Fifty sightings. Leave the radar running near a window and they add up fast, especially under a busy approach path."),
            make("veteran", "Sky Veteran", "Log 500 aircraft", "medal.fill", target: 500, sightings,
                 about: "Five hundred aircraft in the book. You know the local traffic better than most people on the ground."),
            make("overhead", "Right Overhead", "Have an aircraft pass within half a mile", "scope", target: 1,
                 matching { $0.closestMiles < 0.5 },
                 about: "About as close as a flight gets: its track passed within half a mile of where you were watching."),
            make("queen", "Queen of the Skies", "Spot a Boeing 747", "crown.fill", target: 1,
                 type(["B741", "B742", "B743", "B744", "B748", "B74S", "BLCF", "VC25"]),
                 about: "The Boeing 747 first flew in 1969. Most passenger 747s have now retired, so these days you're most likely to catch a freighter."),
            make("superjumbo", "Superjumbo", "Spot an Airbus A380", "airplane.circle.fill", target: 1, type(["A388"]),
                 about: "The Airbus A380 is the largest passenger airliner ever built, with two full-length decks."),
            make("heavy", "Heavy Lifter", "Spot a giant freighter (An-124, C-5, C-17, Beluga, Dreamlifter)", "shippingbox.fill", target: 1,
                 type(["A124", "A225", "C5M", "C5", "C17", "BLCF", "A3ST", "A337"]),
                 about: "The giants of air cargo: Antonov An-124s, Lockheed C-5 Galaxies, Boeing C-17s, Airbus Belugas and the Boeing Dreamlifter that ferries 787 parts."),
            make("military", "Top Brass", "Spot a military aircraft", "shield.lefthalf.filled", target: 1,
                 matching { $0.tags.contains(.military) },
                 about: "Picked out by a military callsign (REACH is US Air Force Air Mobility Command) or by an airframe only air forces fly."),
            make("medical", "Guardian Angel", "Spot an air ambulance", "cross.case.fill", target: 1,
                 matching { $0.tags.contains(.medical) },
                 about: "Medical flights, usually helicopters flying low and fast to a hospital, recognised by callsigns like LIFE or LIFEGUARD."),
            make("emergency", "Mayday", "Witness an emergency squawk", "exclamationmark.triangle.fill", target: 1,
                 matching { $0.tags.contains { $0.isEmergency } },
                 about: "A transponder set to 7700 (general emergency), 7600 (lost radio contact) or 7500 (unlawful interference). Most end with a safe landing."),
            make("rotor", "Rotorhead", "Spot 10 helicopters", "fan.fill", target: 10, matching { $0.kind == .helicopter },
                 about: "News, police, medical and tour helicopters mostly fly low and slow, so they're often the closest traffic you'll log."),
            make("airlines", "Globetrotter", "Spot 15 different airlines", "globe.americas.fill", target: 15,
                 distinct { $0.isAirline ? $0.operatorName : nil },
                 about: "Each airline counts once, however many of its flights you see. Listed here: the first flight you logged from each."),
            make("types", "Type Collector", "Spot 25 different aircraft types", "square.stack.3d.up.fill", target: 25,
                 distinct(\.typeCode),
                 about: "Counted by ICAO type code, so an A320 and an A321 are different types. Listed here: the first of each you logged."),
            make("night", "Night Owl", "Spot an aircraft between midnight and 4 am", "moon.stars.fill", target: 1,
                 matching { (0..<4).contains(calendar.component(.hour, from: $0.firstSeen)) },
                 about: "The small hours belong to cargo flights and the occasional late-running airliner."),
        ]
    }
}
