//
//  SpotPhoto.swift
//  WhatTheFlight
//
//  A photo taken in Sky View and the moment it caught: which aircraft, how far, how high,
//  how fast, where it was in the frame. The full-resolution original goes to the camera
//  roll; the logbook keeps this record plus one smaller copy (`SpotPhotoStore`), and the
//  boarding-pass card is drawn from the two whenever it's shared, so the card itself is
//  never stored. Photos ride on their sighting and sync with it.
//

import Foundation
import CoreGraphics
import CoreLocation

struct SpotPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var flightID: String
    var takenAt: Date
    var device: LogDevice?

    // The aircraft, so the card can be drawn without the sighting.
    var displayIdentifier: String
    var callsign: String?
    var registration: String?
    var typeCode: String?
    var operatorName: String
    var kind: AircraftKind
    var originIATA: String?
    var destinationIATA: String?
    var tags: [NotableTag]

    // At the shutter.
    var distanceMiles: Double
    var altitudeFeet: Int
    var speedKnots: Int
    var track: Double
    var elevationDegrees: Double
    var bearingDegrees: Double
    var aircraftLatitude: Double
    var aircraftLongitude: Double
    var observerLatitude: Double?
    var observerLongitude: Double?
    var placeName: String?
    /// The zoom on the chip when it was taken ("5×").
    var displayZoom: Double
    /// Where the aircraft sits in the photo, 0…1 from the top left. Nil when it was outside
    /// the frame (or behind the camera).
    var frameX: Double?
    var frameY: Double?
    /// The camera found the aircraft itself, so the marker is on the real dot.
    var visuallyLocked: Bool
    var pixelWidth: Int
    var pixelHeight: Int

    var fileName: String { "\(id).heic" }

    var origin: Airport? { originIATA.flatMap(AirportCatalog.airport(iata:)) }
    var destination: Airport? { destinationIATA.flatMap(AirportCatalog.airport(iata:)) }
    var typeName: String? { AircraftTypeCatalog.name(forTypeCode: typeCode) }

    var aircraftCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: aircraftLatitude, longitude: aircraftLongitude)
    }

    var framePoint: CGPoint? {
        guard let frameX, let frameY else { return nil }
        return CGPoint(x: frameX, y: frameY)
    }

    /// Miles flown and to go along the route, from where the aircraft was at the shutter.
    var routeMiles: (flown: Double, remaining: Double)? {
        guard let from = origin?.coordinate, let to = destination?.coordinate else { return nil }
        return (GeoMath.distanceMiles(from: from, to: aircraftCoordinate),
                GeoMath.distanceMiles(from: aircraftCoordinate, to: to))
    }

    init(id: String = UUID().uuidString, contact: RadarContact, takenAt: Date, device: LogDevice?,
         elevationDegrees: Double, observer: CLLocationCoordinate2D?, placeName: String?,
         displayZoom: Double, framePoint: CGPoint?, visuallyLocked: Bool, pixelWidth: Int, pixelHeight: Int) {
        let f = contact.flight
        let info = f.operatorInfo
        self.id = id
        flightID = f.id
        self.takenAt = takenAt
        self.device = device
        displayIdentifier = f.displayIdentifier
        callsign = f.callsign
        registration = f.registration
        typeCode = f.typeCode
        operatorName = info.title
        kind = f.kind
        originIATA = f.originIATA
        destinationIATA = f.destinationIATA
        tags = f.notable.map(\.tag)
        distanceMiles = contact.distanceMiles
        altitudeFeet = contact.altitudeFeet
        speedKnots = f.groundSpeedKnots
        track = f.track
        self.elevationDegrees = elevationDegrees
        bearingDegrees = contact.bearing
        aircraftLatitude = contact.coordinate.latitude
        aircraftLongitude = contact.coordinate.longitude
        observerLatitude = observer?.latitude
        observerLongitude = observer?.longitude
        self.placeName = placeName
        self.displayZoom = displayZoom
        frameX = framePoint.map { Double($0.x) }
        frameY = framePoint.map { Double($0.y) }
        self.visuallyLocked = visuallyLocked
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The same shot, credited to a different aircraft that was also in it.
    func reassigned(to other: SpotPhoto) -> SpotPhoto {
        var copy = other
        copy.takenAt = takenAt
        copy.device = device
        copy.displayZoom = displayZoom
        copy.pixelWidth = pixelWidth
        copy.pixelHeight = pixelHeight
        return copy
    }
}

/// The logbook's copies of Sky View photos, one HEIC file per photo id, next to
/// Logbook.json. Without a directory (tests, previews) it keeps them in memory.
final class SpotPhotoStore: @unchecked Sendable {
    let directory: URL?
    private let lock = NSLock()
    private var memory: [String: Data] = [:]

    init(directory: URL?) {
        self.directory = directory
    }

    /// The app's own store, for views that show photos without a logbook at hand.
    static let standard = SpotPhotoStore(directory: defaultDirectory)

    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SpotPhotos", isDirectory: true)
    }

    func url(for id: String) -> URL? {
        directory?.appendingPathComponent("\(id).heic")
    }

    func hasImage(_ id: String) -> Bool {
        if let url = url(for: id) { return FileManager.default.fileExists(atPath: url.path) }
        return lock.withLock { memory[id] != nil }
    }

    func data(_ id: String) -> Data? {
        if let url = url(for: id) { return try? Data(contentsOf: url) }
        return lock.withLock { memory[id] }
    }

    func write(_ data: Data, id: String) throws {
        guard let url = url(for: id) else {
            lock.withLock { memory[id] = data }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Copies a downloaded file in (an iCloud asset, which CloudKit deletes afterwards).
    func importFile(at source: URL, id: String) throws {
        guard let url = url(for: id) else {
            let data = try Data(contentsOf: source)
            lock.withLock { memory[id] = data }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try FileManager.default.copyItem(at: source, to: url)
    }

    func delete(_ ids: some Sequence<String>) {
        for id in ids {
            if let url = url(for: id) {
                try? FileManager.default.removeItem(at: url)
            } else {
                _ = lock.withLock { memory.removeValue(forKey: id) }
            }
        }
    }
}
