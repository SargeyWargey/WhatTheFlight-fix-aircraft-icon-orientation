//
//  LogbookExport.swift
//  WhatTheFlight
//
//  The logbook out of the app (Enhancements Spec C4): a CSV for Numbers or Excel, and a
//  backup that can be restored on any device. A backup is a folder: `Logbook.json` (every
//  sighting, as the app stores them) and `Photos/<id>.heic` (the logbook's copies of
//  Sky View and camera roll photos). Restoring merges, so nothing already there is lost.
//

import Foundation

enum LogbookExport {
    static let backupFileName = "Logbook.json"
    static let photoFolderName = "Photos"

    /// What a backup's `Logbook.json` holds. A bare array of sightings (the app's own
    /// Logbook.json, copied out by hand) restores too.
    struct Backup: Codable {
        var format = "WhatTheFlight.logbook"
        var version = 1
        var exportedAt: Date
        var sightings: [Sighting]
    }

    enum ReadError: LocalizedError {
        case unreadable

        var errorDescription: String? { "That isn't a What The Flight? logbook backup." }
    }

    static func backupData(_ sightings: [Sighting], exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Backup(exportedAt: exportedAt, sightings: sightings))
    }

    static func readBackup(_ data: Data) throws -> [Sighting] {
        let decoder = JSONDecoder()
        if let backup = try? decoder.decode(Backup.self, from: data) { return backup.sightings }
        if let bare = try? decoder.decode([Sighting].self, from: data) { return bare }
        throw ReadError.unreadable
    }

    /// "What The Flight Logbook 2026-10-26".
    static func suggestedName(_ what: String = "Logbook", date: Date = Date()) -> String {
        "What The Flight \(what) \(date.formatted(.iso8601.year().month().day()))"
    }

    // MARK: CSV

    /// One row per sighting, oldest first, distances, altitudes and speeds in the units in use
    /// (the headers say which). Times are local to where each aircraft was seen.
    static func csv(_ sightings: [Sighting], units: UnitSystem = Units.current) -> String {
        let metric = units == .metric
        let header = [
            "First seen", "Last seen", "Flight", "Callsign", "Registration", "ICAO hex", "Type", "Type name", "Operator",
            "From", "To", "Closest (\(metric ? "km" : "mi"))", "Altitude at closest (\(metric ? "m" : "ft"))",
            "Speed (\(metric ? "km/h" : "kts"))", "Tags", "Place", "Latitude", "Longitude", "Logged on", "Photos",
        ]
        var lines = [header.map(field).joined(separator: ",")]
        lines.reserveCapacity(sightings.count + 1)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var zone = ""
        for s in sightings {
            let z = s.timeZone ?? TimeZone.current.identifier
            if z != zone {
                formatter.timeZone = TimeZone(identifier: z) ?? .current
                zone = z
            }
            let closest = metric ? s.closestMiles * UnitSystem.kilometersPerMile : s.closestMiles
            let altitude = metric ? Double(s.altitudeAtClosestFeet) * UnitSystem.metersPerFoot : Double(s.altitudeAtClosestFeet)
            let speed = metric ? Double(s.speedKnots) * UnitSystem.kmhPerKnot : Double(s.speedKnots)
            let row: [String] = [
                formatter.string(from: s.firstSeen),
                formatter.string(from: s.lastSeen),
                s.displayIdentifier,
                s.callsign ?? "",
                s.registration ?? "",
                s.hex ?? "",
                s.typeCode ?? "",
                s.typeName ?? "",
                s.operatorName,
                s.originIATA ?? "",
                s.destinationIATA ?? "",
                String(format: "%.2f", closest),
                String(Int(altitude.rounded())),
                String(Int(speed.rounded())),
                s.tags.map(\.rawValue).joined(separator: " "),
                s.placeName ?? "",
                s.closestLatitude.map { String(format: "%.5f", $0) } ?? "",
                s.closestLongitude.map { String(format: "%.5f", $0) } ?? "",
                s.loggedOn.map(\.title).joined(separator: " "),
                String(s.spotPhotos.count),
            ]
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180: quoted when it holds a comma, quote or line break, quotes doubled.
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension Logbook {
    struct RestoreResult: Equatable, Sendable {
        var added = 0
        var updated = 0
        var photos = 0
    }

    /// Merges sightings from a backup, copying in the photos it has, and sends what changed
    /// to iCloud. `photo(id)` gives a photo's file in the backup, if it's there.
    func restore(_ incoming: [Sighting], photo: (String) -> URL? = { _ in nil }) -> RestoreResult {
        var result = RestoreResult()
        guard !incoming.isEmpty else { return result }
        let known = allIDs
        let before = Dictionary(uniqueKeysWithValues: incoming.compactMap { s in sighting(id: s.id).map { (s.id, $0) } })
        var photoIDs = Set<String>()
        for s in incoming {
            for p in s.spotPhotos where !photoStore.hasImage(p.id) {
                guard let url = photo(p.id) else { continue }
                do {
                    try photoStore.importFile(at: url, id: p.id)
                    photoIDs.insert(p.id)
                } catch {
                    Log.logbook.error("Couldn't restore a photo: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        merge(remote: incoming)
        result.added = incoming.filter { !known.contains($0.id) && sighting(id: $0.id) != nil }.count
        result.updated = before.filter { id, old in sighting(id: id) != old }.count
        result.photos = photoIDs.count
        let changed = Set(incoming.map(\.id)).filter { sighting(id: $0) != nil }
        if !changed.isEmpty { onLocalChange?(changed, []) }
        if !photoIDs.isEmpty { onLocalPhotoChange?(photoIDs, []) }
        return result
    }
}
