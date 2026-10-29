//
//  Logbook.swift
//  WhatTheFlight
//
//  Every aircraft that came inside the radius (or that you photographed in Sky View): when
//  you saw it, how close it came, where you were, which device logged it, whether it was
//  anything special, and your photos of it. Feeds the stats and the badges. Kept on each
//  device and merged across them through iCloud (`LogbookSync`); the same flight logged on
//  two devices becomes one sighting.
//

import Foundation
import CoreLocation
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// The kind of device a sighting was logged on.
enum LogDevice: String, Codable, CaseIterable, Sendable, Comparable {
    case iPhone, iPad, appleTV, watch, mac

    var title: String {
        switch self {
        case .iPhone: return String(localized: "iPhone")
        case .iPad: return String(localized: "iPad")
        case .appleTV: return String(localized: "Apple TV")
        case .watch: return String(localized: "Apple Watch")
        case .mac: return String(localized: "Mac")
        }
    }

    var symbol: String {
        switch self {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .appleTV: return "appletv"
        case .watch: return "applewatch"
        case .mac: return "laptopcomputer"
        }
    }

    static func < (lhs: LogDevice, rhs: LogDevice) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }

    @MainActor
    static var current: LogDevice {
        #if os(tvOS)
        return .appleTV
        #elseif os(watchOS)
        return .watch
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
        #else
        return .mac
        #endif
    }
}

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
    /// Where the aircraft was at its closest pass, which way it was heading, and where it was
    /// watched from. Missing on sightings logged before they were recorded.
    var closestLatitude: Double?
    var closestLongitude: Double?
    var trackAtClosest: Double?
    var observerLatitude: Double?
    var observerLongitude: Double?
    /// The time zone it was logged in ("Europe/London"), so hour charts read local time where
    /// you were. Missing on sightings logged before it was recorded.
    var timeZone: String?
    /// Devices that logged it. Missing on sightings logged before devices were recorded.
    var devices: [LogDevice]?
    /// Sky View photos of it. Read them through `spotPhotos`.
    var photos: [SpotPhoto]?
    /// Photos deleted on any device, so a merge with an older copy doesn't bring them back.
    var removedPhotoIDs: [String]?

    /// The airframe, for "seen N times" (falls back to the hex code).
    var airframe: String? { registration ?? hex }
    var typeName: String? { AircraftTypeCatalog.name(forTypeCode: typeCode) }
    var silhouette: AircraftSilhouette { AircraftTypeCatalog.silhouette(forTypeCode: typeCode) }

    var closestCoordinate: CLLocationCoordinate2D? {
        guard let closestLatitude, let closestLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: closestLatitude, longitude: closestLongitude)
    }

    var observerCoordinate: CLLocationCoordinate2D? {
        guard let observerLatitude, let observerLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: observerLatitude, longitude: observerLongitude)
    }

    var origin: Airport? { originIATA.flatMap(AirportCatalog.airport(iata:)) }
    var destination: Airport? { destinationIATA.flatMap(AirportCatalog.airport(iata:)) }

    var loggedOn: [LogDevice] { devices ?? [] }

    /// Photos still in the logbook, oldest first.
    var spotPhotos: [SpotPhoto] {
        let removed = Set(removedPhotoIDs ?? [])
        return (photos ?? []).filter { !removed.contains($0.id) }.sorted { $0.takenAt < $1.takenAt }
    }

    /// The same flight as logged by another device: the longest time in range, the closest
    /// pass (with where it was watched from), every tag and every device.
    func merged(with other: Sighting) -> Sighting {
        var m = self
        m.firstSeen = min(firstSeen, other.firstSeen)
        m.lastSeen = max(lastSeen, other.lastSeen)
        if other.closestMiles < closestMiles - 0.01 {
            m.closestMiles = other.closestMiles
            m.altitudeAtClosestFeet = other.altitudeAtClosestFeet
            m.speedKnots = other.speedKnots
            m.closestLatitude = other.closestLatitude
            m.closestLongitude = other.closestLongitude
            m.trackAtClosest = other.trackAtClosest
            m.observerLatitude = other.observerLatitude ?? observerLatitude
            m.observerLongitude = other.observerLongitude ?? observerLongitude
            m.placeName = other.placeName ?? placeName
        }
        m.placeName = m.placeName ?? other.placeName
        m.timeZone = timeZone ?? other.timeZone
        m.callsign = callsign ?? other.callsign
        m.registration = registration ?? other.registration
        m.hex = hex ?? other.hex
        m.typeCode = typeCode ?? other.typeCode
        m.originIATA = originIATA ?? other.originIATA
        m.destinationIATA = destinationIATA ?? other.destinationIATA
        m.tags = Set(tags).union(other.tags).sorted()
        let devices = Set(loggedOn).union(other.loggedOn)
        m.devices = devices.isEmpty ? nil : devices.sorted()
        // Photos: every one either copy has, minus any either copy deleted.
        let removed = Set(removedPhotoIDs ?? []).union(other.removedPhotoIDs ?? [])
        var byID = Dictionary((other.photos ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for photo in photos ?? [] { byID[photo.id] = photo }
        let kept = byID.values.filter { !removed.contains($0.id) }.sorted { ($0.takenAt, $0.id) < ($1.takenAt, $1.id) }
        m.photos = kept.isEmpty ? nil : kept
        m.removedPhotoIDs = removed.isEmpty ? nil : removed.sorted()
        return m
    }

    fileprivate mutating func noteClosest(_ contact: RadarContact, observer: CLLocationCoordinate2D?) {
        closestMiles = contact.distanceMiles
        altitudeAtClosestFeet = contact.altitudeFeet
        speedKnots = contact.flight.groundSpeedKnots
        closestLatitude = contact.coordinate.latitude
        closestLongitude = contact.coordinate.longitude
        trackAtClosest = contact.flight.track
        if let observer {
            observerLatitude = observer.latitude
            observerLongitude = observer.longitude
        }
    }
}

@MainActor
@Observable
final class Logbook {
    /// Oldest first; use `recent` for display.
    private(set) var sightings: [Sighting] = [] {
        didSet { revision &+= 1 }
    }
    /// Bumped on every change, so `digest` knows when to rebuild.
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private var digestCache: (revision: Int, day: Date, digest: LogbookDigest)?
    /// Bumped when a background rebuild lands, so screens showing the old digest refresh.
    private var digestVersion = 0
    @ObservationIgnored private var rebuildingDigest = false
    /// Past this many sightings a changed logbook rebuilds its digest off the main thread
    /// (around 85 ms for 10,000 in a release build) while screens keep the previous one.
    nonisolated static let backgroundDigestThreshold = 2_000
    /// Badge levels already announced ("spotter@1000"), so a new one is only called out once.
    @ObservationIgnored private var announcedLevels: Set<String>?
    @ObservationIgnored private var lastBadgeCheck = Date.distantPast
    /// A badge (or a new level of one) was just earned by something on the radar.
    @ObservationIgnored var onBadgeUnlocked: ((Achievement) -> Void)?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var index: [String: Int] = [:]
    /// Where each airframe's sightings sit in `sightings`, oldest first, so an aircraft's
    /// count and history don't scan the whole book. Observed, so a count on screen updates
    /// when a new visit is logged.
    private var byAirframe: [String: [Int]] = [:]
    /// The first sighting (by id) of each type code and each airline, for "First Qatar
    /// Airways in your logbook".
    @ObservationIgnored private var firstOfType: [String: String] = [:]
    @ObservationIgnored private var firstOfAirline: [String: String] = [:]
    /// First-of alerts wait until the logbook holds this many sightings: a new logbook would
    /// otherwise call out nearly everything.
    nonisolated static let firstSeenBaseline = 100
    @ObservationIgnored private var isDirty = false
    @ObservationIgnored private var lastSave = Date.distantPast
    /// Off when the file is there but couldn't be read: a save would replace it.
    @ObservationIgnored private var canSave = true
    @ObservationIgnored private let maxEntries: Int
    /// Stamped on everything this device logs.
    @ObservationIgnored let device: LogDevice?
    /// Sightings this device created or changed, and ones it deleted, for iCloud.
    @ObservationIgnored var onLocalChange: ((_ saved: Set<String>, _ deleted: Set<String>) -> Void)?
    /// Photo images this device added or deleted (by photo id), for iCloud.
    @ObservationIgnored var onLocalPhotoChange: ((_ saved: Set<String>, _ deleted: Set<String>) -> Void)?
    /// The logbook's copies of Sky View photos.
    @ObservationIgnored let photoStore: SpotPhotoStore

    /// `fileURL == nil` keeps everything in memory (tests, previews), photos included unless
    /// `photoDirectory` says otherwise.
    init(fileURL: URL? = Logbook.defaultURL, photoDirectory: URL? = nil, maxEntries: Int = 10_000, device: LogDevice? = nil) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        self.device = device
        photoStore = SpotPhotoStore(directory: photoDirectory ?? fileURL.flatMap { _ in SpotPhotoStore.defaultDirectory })
        load()
    }

    func sighting(id: String) -> Sighting? {
        index[id].map { sightings[$0] }
    }

    nonisolated static var defaultURL: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("Logbook.json")
    }

    var recent: [Sighting] { sightings.reversed() }
    var isEmpty: Bool { sightings.isEmpty }

    /// Stats, records, days, rankings, chart data and badges for the logbook screens. Built
    /// once per change (and once a day, for "today"), however often a view asks.
    var digest: LogbookDigest {
        // Reading these registers the caller for changes and for background rebuilds.
        let current = sightings
        _ = digestVersion
        let now = Date()
        let day = Calendar.current.startOfDay(for: now)
        if let cache = digestCache, cache.revision == revision, cache.day == day { return cache.digest }
        if let cache = digestCache, current.count > Self.backgroundDigestThreshold {
            rebuildDigest(current, revision: revision, day: day)
            return cache.digest
        }
        let digest = LogbookDigest(current, now: now)
        digestCache = (revision, day, digest)
        return digest
    }

    /// Builds the digest of a big logbook off the main thread; screens keep the previous one
    /// until it lands. If the logbook changed meanwhile, the next read starts another.
    private func rebuildDigest(_ snapshot: [Sighting], revision: Int, day: Date) {
        guard !rebuildingDigest else { return }
        rebuildingDigest = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let digest = LogbookDigest(snapshot, now: Date())
            await self?.finishRebuild(digest, revision: revision, day: day)
        }
    }

    /// The units changed: records and badge labels in the digest are worded in them, so
    /// screens rebuild it.
    func formattingDidChange() {
        revision &+= 1
        digestVersion &+= 1
    }

    private func finishRebuild(_ digest: LogbookDigest, revision: Int, day: Date) {
        rebuildingDigest = false
        if (digestCache?.revision ?? -1) <= revision { digestCache = (revision, day, digest) }
        digestVersion &+= 1
    }

    // MARK: Recording

    /// Call with the in-range contacts; cheap enough to run every tick.
    func record(_ contacts: [RadarContact], at date: Date = Date(), observer: CLLocationCoordinate2D? = nil, placeName: String? = nil) {
        guard !contacts.isEmpty else { return }
        var changed = Set<String>()
        var added = false
        for contact in contacts {
            let f = contact.flight
            if let i = index[f.id] {
                var s = sightings[i]
                s.lastSeen = date
                if contact.distanceMiles < s.closestMiles - 0.05 {
                    s.noteClosest(contact, observer: observer)
                    if s.placeName == nil { s.placeName = placeName }
                }
                let tags = Set(s.tags).union(contact.profile.notable.map(\.tag))
                if tags.count != s.tags.count { s.tags = tags.sorted() }
                if let device, !s.loggedOn.contains(device) { s.devices = (s.loggedOn + [device]).sorted() }
                // Only write back meaningful changes so observers aren't churned every second.
                if s.closestMiles != sightings[i].closestMiles || s.tags != sightings[i].tags || s.devices != sightings[i].devices
                    || date.timeIntervalSince(sightings[i].lastSeen) > 60 {
                    sightings[i] = s
                    isDirty = true
                    changed.insert(s.id)
                }
            } else {
                let info = contact.profile.operatorInfo
                var s = Sighting(
                    id: f.id, firstSeen: date, lastSeen: date, displayIdentifier: f.displayIdentifier,
                    callsign: f.callsign, registration: f.registration, hex: f.hex, typeCode: f.typeCode,
                    kind: contact.profile.kind, operatorName: info.title, isAirline: info.kind == .airline,
                    originIATA: f.originIATA, destinationIATA: f.destinationIATA,
                    closestMiles: contact.distanceMiles, altitudeAtClosestFeet: contact.altitudeFeet,
                    speedKnots: f.groundSpeedKnots, tags: contact.profile.notable.map(\.tag), placeName: placeName
                )
                s.noteClosest(contact, observer: observer)
                s.devices = device.map { [$0] }
                s.timeZone = TimeZone.current.identifier
                sightings.append(s)
                added = true
                index[f.id] = sightings.count - 1
                if let airframe = s.airframe { byAirframe[airframe, default: []].append(sightings.count - 1) }
                noteFirsts(s)
                isDirty = true
                changed.insert(s.id)
            }
        }
        trimIfNeeded()
        if isDirty, date.timeIntervalSince(lastSave) > 30 { save() }
        if !changed.isEmpty { onLocalChange?(changed, []) }
        if added { checkBadges(at: date) }
    }

    // MARK: Badges

    nonisolated static let announcedKey = "wtf.announcedBadges"
    /// Levels by position ("spotter#3"), which a changed ladder would misread.
    private static let legacyAnnouncedKey = "wtf.announcedBadgeLevels"

    /// Calls `onBadgeUnlocked` for badges and levels earned since the last check, at most every
    /// 20 seconds. The first check on a device with an existing logbook only notes what's
    /// already earned, so updating the app doesn't announce a pile of old badges.
    private func checkBadges(at date: Date) {
        guard onBadgeUnlocked != nil, date.timeIntervalSince(lastBadgeCheck) > 20 else { return }
        lastBadgeCheck = date
        // Reuse the screens' digest when it's current; otherwise just the badges.
        let achievements = digestCache.flatMap { $0.revision == revision ? $0.digest.achievements : nil } ?? Achievement.all(for: sightings)
        // Each level by what it takes, so moving a badge's levels never re-announces or hides one.
        let earned = Set(achievements.flatMap { a in a.tiers.prefix(a.level).map { "\(a.id)@\($0)" } })
        let stored = UserDefaults.standard.stringArray(forKey: Self.announcedKey)
        let isBaseline = announcedLevels == nil && stored == nil && sightings.count > 1
        let known = announcedLevels ?? Set(stored ?? [])
        let fresh = earned.subtracting(known)
        announcedLevels = known.union(fresh)
        guard !fresh.isEmpty else { return }
        UserDefaults.standard.set(known.union(fresh).sorted(), forKey: Self.announcedKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyAnnouncedKey)
        guard !isBaseline else { return }
        let newIDs = Set(fresh.map { String($0.split(separator: "@")[0]) })
        for a in achievements where newIDs.contains(a.id) { onBadgeUnlocked?(a) }
    }

    // MARK: Photos

    /// Every photo in the logbook, newest first.
    var allPhotos: [SpotPhoto] {
        sightings.flatMap(\.spotPhotos).sorted { $0.takenAt > $1.takenAt }
    }

    func photo(id: String) -> SpotPhoto? {
        for s in sightings { if let p = s.photos?.first(where: { $0.id == id }) { return p } }
        return nil
    }

    /// Every photo id still in the logbook, for a first upload to iCloud.
    var allPhotoIDs: Set<String> { Set(sightings.flatMap { $0.spotPhotos.map(\.id) }) }

    /// Files a photographed aircraft under its sighting, creating the sighting if it was
    /// never inside the radius (photographing it counts as seeing it). `imageData` is the
    /// logbook's copy. Returns false if there's no sighting to attach it to.
    @discardableResult
    func addPhoto(_ photo: SpotPhoto, imageData: Data, contact: RadarContact?,
                  observer: CLLocationCoordinate2D? = nil, placeName: String? = nil) -> Bool {
        if index[photo.flightID] == nil, let contact {
            record([contact], at: photo.takenAt, observer: observer, placeName: placeName)
        }
        guard let i = index[photo.flightID] else { return false }
        do {
            try photoStore.write(imageData, id: photo.id)
        } catch {
            Log.logbook.error("Couldn't store a Sky View photo: \(error.localizedDescription, privacy: .public)")
            return false
        }
        var s = sightings[i]
        s.photos = (s.photos ?? []).filter { $0.id != photo.id } + [photo]
        sightings[i] = s
        isDirty = true
        save()
        onLocalChange?([s.id], [])
        onLocalPhotoChange?([photo.id], [])
        return true
    }

    func removePhoto(id: String) {
        guard let i = sightings.firstIndex(where: { $0.photos?.contains { $0.id == id } == true }) else { return }
        var s = sightings[i]
        s.photos = s.photos?.filter { $0.id != id }
        if s.photos?.isEmpty == true { s.photos = nil }
        s.removedPhotoIDs = Array(Set(s.removedPhotoIDs ?? []).union([id])).sorted()
        sightings[i] = s
        photoStore.delete([id])
        isDirty = true
        save()
        onLocalChange?([s.id], [])
        onLocalPhotoChange?([], [id])
    }

    private func deletePhotoFiles(of removed: [Sighting]) {
        let ids = removed.flatMap { ($0.photos ?? []).map(\.id) }
        guard !ids.isEmpty else { return }
        photoStore.delete(ids)
    }

    // MARK: Merging (iCloud)

    /// Folds in sightings from other devices. Returns the ids whose merged copy differs from
    /// what came in, so the merged version can go back up.
    @discardableResult
    func merge(remote: [Sighting]) -> Set<String> {
        guard !remote.isEmpty else { return [] }
        var differs = Set<String>()
        var appended = false
        var airframeChanged = false
        for incoming in remote {
            if let i = index[incoming.id] {
                let merged = sightings[i].merged(with: incoming)
                // The other copy can fill in a registration this one only knew by hex.
                if merged.airframe != sightings[i].airframe { airframeChanged = true }
                // Deleted on another device: drop our copy of the image too.
                let gone = Set(merged.removedPhotoIDs ?? []).subtracting(sightings[i].removedPhotoIDs ?? [])
                if !gone.isEmpty { photoStore.delete(gone) }
                if merged != sightings[i] { sightings[i] = merged }
                if merged != incoming { differs.insert(incoming.id) }
            } else {
                sightings.append(incoming)
                index[incoming.id] = sightings.count - 1
                appended = true
            }
        }
        if appended {
            // Keep oldest first; remote sightings can be older than local ones.
            sightings.sort { $0.firstSeen < $1.firstSeen }
            trimIfNeeded()
            rebuildIndex()
        } else if airframeChanged {
            rebuildIndex()
        }
        isDirty = true
        save()
        return differs
    }

    /// Sightings another device deleted.
    func applyRemoteDeletions(_ ids: Set<String>) {
        guard !ids.isEmpty, ids.contains(where: { index[$0] != nil }) else { return }
        deletePhotoFiles(of: sightings.filter { ids.contains($0.id) })
        sightings.removeAll { ids.contains($0.id) }
        rebuildIndex()
        isDirty = true
        save()
    }

    /// Everything, for a first upload to iCloud.
    var allIDs: Set<String> { Set(sightings.map(\.id)) }

    func timesSeen(airframe: String?) -> Int {
        guard let airframe else { return 0 }
        return byAirframe[airframe]?.count ?? 0
    }

    /// Every sighting of this airframe, oldest first.
    private func visits(of airframe: String?) -> [Sighting] {
        guard let airframe, let positions = byAirframe[airframe] else { return [] }
        return positions.map { sightings[$0] }
    }

    /// Every sighting of this airframe, newest first.
    func history(airframe: String?) -> [Sighting] {
        visits(of: airframe).reversed()
    }

    /// The all-time numbers behind an aircraft's "Logbook" button and its history screen.
    func summary(airframe: String?) -> AirframeSummary {
        AirframeSummary(history: history(airframe: airframe))
    }

    func firstSighting(airframe: String?) -> Sighting? {
        guard let airframe else { return nil }
        return byAirframe[airframe]?.first.map { sightings[$0] }
    }

    /// "Seen 3 times before · first Oct 2, 2026" for an airframe already in the logbook.
    func seenBeforeSummary(for flight: Flight) -> String? {
        guard let airframe = flight.registration ?? flight.hex else { return nil }
        let earlier = visits(of: airframe).filter { $0.id != flight.id }
        guard let first = earlier.first else { return nil }
        let times = earlier.count == 1 ? "Seen once before" : "Seen \(earlier.count) times before"
        return "\(times) · first \(first.firstSeen.formatted(date: .abbreviated, time: .omitted))"
    }

    func delete(_ ids: Set<String>) {
        let removed = sightings.filter { ids.contains($0.id) }
        deletePhotoFiles(of: removed)
        sightings.removeAll { ids.contains($0.id) }
        rebuildIndex()
        isDirty = true
        save()
        onLocalChange?([], ids)
        let photoIDs = Set(removed.flatMap { ($0.photos ?? []).map(\.id) })
        if !photoIDs.isEmpty { onLocalPhotoChange?([], photoIDs) }
    }

    func clear() {
        let ids = allIDs
        let photoIDs = Set(sightings.flatMap { ($0.photos ?? []).map(\.id) })
        deletePhotoFiles(of: sightings)
        if !photoIDs.isEmpty { onLocalPhotoChange?([], photoIDs) }
        sightings = []
        index = [:]
        byAirframe = [:]
        firstOfType = [:]
        firstOfAirline = [:]
        isDirty = true
        save()
        onLocalChange?([], ids)
    }

    // MARK: Persistence

    /// Writes pending changes now (call when the app goes to the background).
    func flush() {
        if isDirty { save() }
    }

    private func save() {
        lastSave = Date()
        isDirty = false
        guard let fileURL, canSave else { return }
        let snapshot = sightings
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // A failed write just means the next save tries again with everything.
                Log.logbook.error("Couldn't save the logbook: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func load() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // There but not readable yet (still locked after a restart?): don't save over it
            // this session; the next launch reads it.
            canSave = false
            Log.logbook.error("Couldn't open the logbook, not saving this session: \(error.localizedDescription, privacy: .public)")
            return
        }
        do {
            sightings = try JSONDecoder().decode([Sighting].self, from: data)
            rebuildIndex()
        } catch {
            // Unreadable for good (damaged, or written by a newer version): set it aside so the
            // next save can't replace it, and start a fresh logbook.
            let aside = Self.unreadableCopyURL(for: fileURL)
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                Log.logbook.fault("Logbook unreadable (\(error.localizedDescription, privacy: .public)); kept as \(aside.lastPathComponent, privacy: .public)")
            } catch let moveError {
                canSave = false
                Log.logbook.fault("Logbook unreadable and couldn't be set aside (\(moveError.localizedDescription, privacy: .public)); not saving this session")
            }
        }
    }

    /// Where an unreadable logbook is kept: "Logbook-unreadable-1792771200.json" beside it.
    nonisolated static func unreadableCopyURL(for url: URL, at date: Date = Date()) -> URL {
        let name = "\(url.deletingPathExtension().lastPathComponent)-unreadable-\(Int(date.timeIntervalSince1970)).\(url.pathExtension)"
        return url.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func trimIfNeeded() {
        guard sightings.count > maxEntries else { return }
        deletePhotoFiles(of: Array(sightings.prefix(sightings.count - maxEntries)))
        sightings.removeFirst(sightings.count - maxEntries)
        rebuildIndex()
    }

    private func rebuildIndex() {
        index = Dictionary(sightings.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, last in last })
        var airframes: [String: [Int]] = [:]
        for (i, s) in sightings.enumerated() {
            if let airframe = s.airframe { airframes[airframe, default: []].append(i) }
        }
        byAirframe = airframes
        firstOfType = [:]
        firstOfAirline = [:]
        for s in sightings { noteFirsts(s) }
    }

    private func noteFirsts(_ s: Sighting) {
        if let code = s.typeCode, firstOfType[code] == nil { firstOfType[code] = s.id }
        if s.isAirline, firstOfAirline[s.operatorName] == nil { firstOfAirline[s.operatorName] = s.id }
    }

    // MARK: Firsts

    /// Whether this aircraft is the first of its type or airline in the logbook (it's
    /// logged as it enters the radius, so it's the first when its own sighting is), once
    /// the logbook has a baseline. The type wins when it's both.
    func firstSeen(_ contact: RadarContact) -> FirstSeen? {
        guard sightings.count >= Self.firstSeenBaseline else { return nil }
        let f = contact.flight
        if let code = f.typeCode, firstOfType[code] == f.id {
            return .type(contact.profile.typeName ?? code)
        }
        let info = contact.profile.operatorInfo
        if info.kind == .airline, firstOfAirline[info.title] == f.id {
            return .airline(info.title)
        }
        return nil
    }
}

/// Every visit of one airframe, newest first, plus the headline numbers.
struct AirframeSummary: Equatable, Sendable {
    let history: [Sighting]

    var count: Int { history.count }
    var first: Sighting? { history.last }
    var latest: Sighting? { history.first }
    var closest: Sighting? { history.min { $0.closestMiles < $1.closestMiles } }
    var highest: Sighting? { history.max { $0.altitudeAtClosestFeet < $1.altitudeAtClosestFeet } }
    /// Different flight numbers / callsigns it was flying when you saw it.
    var flights: Int { Set(history.map(\.displayIdentifier)).count }
}

// MARK: - Daily recap

/// One day at a glance: how many, the notable ones, and anything new to the logbook.
struct DailyRecap: Equatable, Sendable {
    let day: Date
    let total: Int
    /// Military, government, air ambulance, emergency and rare aircraft, newest first.
    let notable: [Sighting]
    /// Sightings of a type never logged before this day, newest first.
    let newTypes: [Sighting]
    /// Airlines never logged before this day.
    let newAirlines: [String]
    let closest: Sighting?
    /// Where you watched from that day.
    let places: [String]

    var isEmpty: Bool { total == 0 }

    /// `sightings` oldest first, as `Logbook.sightings` keeps them.
    init(_ sightings: [Sighting], day: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let before = sightings.filter { $0.firstSeen < start }
        let that = sightings.filter { $0.firstSeen >= start && $0.firstSeen < end }

        self.day = start
        total = that.count
        notable = that.filter { !$0.tags.isEmpty }.reversed()
        closest = that.min { $0.closestMiles < $1.closestMiles }

        var knownTypes = Set(before.compactMap(\.typeCode))
        var firstOfType: [Sighting] = []
        for s in that {
            guard let code = s.typeCode, !knownTypes.contains(code) else { continue }
            knownTypes.insert(code)
            firstOfType.append(s)
        }
        // Only interesting once there's a history to compare with.
        newTypes = before.isEmpty ? [] : firstOfType.reversed()

        var knownAirlines = Set(before.filter(\.isAirline).map(\.operatorName))
        var airlines: [String] = []
        for s in that where s.isAirline && !knownAirlines.contains(s.operatorName) {
            knownAirlines.insert(s.operatorName)
            airlines.append(s.operatorName)
        }
        newAirlines = before.isEmpty ? [] : airlines

        var seenPlaces = Set<String>()
        places = that.compactMap(\.placeName).filter { seenPlaces.insert($0).inserted }
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
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        today = sightings.filter { $0.firstSeen >= dayStart && $0.firstSeen < dayEnd }.count
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
