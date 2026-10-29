//
//  LogbookSync.swift
//  WhatTheFlight
//
//  One logbook across your iPhone, iPad and Apple TV, through iCloud (CloudKit, private
//  database). Each sighting is one record named after the feed's flight id, so the same
//  flight logged on two devices lands on one record and the copies merge
//  (`Sighting.merged(with:)`). Sky View photos ride on their sighting's record; each
//  photo's image is a record of its own ("photo-<id>", the logbook's 1600 px copy as a
//  CKAsset) so sighting saves stay small. `CKSyncEngine` does the scheduling, batching and
//  retries. Apple Watch syncs sightings too, but never downloads photo images (it has no
//  gallery), so the photo records are skipped there.
//

#if os(iOS) || os(tvOS) || os(watchOS)
import CloudKit
import Foundation
import os

@MainActor
final class LogbookSync: CKSyncEngineDelegate {
    static let containerID = "iCloud.SargeyWargey.WhatTheFlight"

    private static let zoneID = CKRecordZone.ID(zoneName: "Logbook", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "Sighting"
    private static let photoRecordType = "SpotPhoto"
    private static let photoPrefix = "photo-"
    private static let log = Log.sync

    private let logbook: Logbook
    private let stateURL: URL?
    private var engine: CKSyncEngine?
    /// Latest server copy of each record, so saves carry the right change tag.
    private var serverRecords: [String: CKRecord] = [:]

    init(logbook: Logbook, stateURL: URL? = LogbookSync.defaultStateURL) {
        self.logbook = logbook
        self.stateURL = stateURL
    }

    nonisolated static var defaultStateURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LogbookSyncState.json")
    }

    var isRunning: Bool { engine != nil }

    func start() {
        guard engine == nil else { return }
        let saved = loadState()
        let container = CKContainer(identifier: Self.containerID)
        let configuration = CKSyncEngine.Configuration(database: container.privateCloudDatabase,
                                                       stateSerialization: saved, delegate: self)
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        logbook.onLocalChange = { [weak self] saved, deleted in self?.queue(saved: saved, deleted: deleted) }
        logbook.onLocalPhotoChange = { [weak self] saved, deleted in self?.queuePhotos(saved: saved, deleted: deleted) }
        if saved == nil {
            // First run on this device: make the zone and send up everything logged so far.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            queueEverything()
        }
        Task { await Self.fetchChanges(engine) }
    }

    /// Stops syncing; the logbook stays on this device.
    func stop() {
        logbook.onLocalChange = nil
        logbook.onLocalPhotoChange = nil
        engine = nil
    }

    /// Pulls anything new from other devices now (the app came to the foreground).
    func fetchNow() {
        guard let engine else { return }
        Task { await Self.fetchChanges(engine) }
    }

    private func queue(saved: Set<String>, deleted: Set<String>) {
        guard let engine else { return }
        let changes = saved.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: $0)) }
            + deleted.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID(for: $0)) }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func queuePhotos(saved: Set<String>, deleted: Set<String>) {
        queue(saved: Set(saved.map { Self.photoPrefix + $0 }), deleted: Set(deleted.map { Self.photoPrefix + $0 }))
    }

    private func queueEverything() {
        queue(saved: logbook.allIDs, deleted: [])
        queuePhotos(saved: logbook.allPhotoIDs.filter { logbook.photoStore.hasImage($0) }, deleted: [])
    }

    private func recordID(for id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: Self.zoneID)
    }

    private static func photoID(_ recordName: String) -> String? {
        recordName.hasPrefix(photoPrefix) ? String(recordName.dropFirst(photoPrefix.count)) : nil
    }

    /// Fetches one photo's image straight from iCloud, for a photo whose record arrived
    /// without it or whose local copy was purged. False when sync is off or it isn't there.
    static func downloadPhoto(id: String, into store: SpotPhotoStore) async -> Bool {
        let syncOn = UserDefaults.standard.object(forKey: "wtf.iCloudLogbook") as? Bool ?? true
        guard syncOn, FileManager.default.ubiquityIdentityToken != nil else { return false }
        let database = CKContainer(identifier: containerID).privateCloudDatabase
        let recordID = CKRecord.ID(recordName: photoPrefix + id, zoneID: zoneID)
        guard let record = try? await database.record(for: recordID),
              let asset = record["image"] as? CKAsset, let url = asset.fileURL else { return false }
        return (try? store.importFile(at: url, id: id)) != nil
    }

    // MARK: CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                queueEverything()
            case .switchAccounts, .signOut:
                // Someone else's iCloud: keep this device's logbook, forget the old account's state.
                serverRecords = [:]
                removeState()
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            var incoming: [Sighting] = []
            for modification in changes.modifications {
                let record = modification.record
                #if os(watchOS)
                if record.recordType == Self.photoRecordType { continue }
                #endif
                serverRecords[record.recordID.recordName] = record
                if record.recordType == Self.photoRecordType {
                    importPhoto(from: record)
                } else if let sighting = Self.sighting(from: record) {
                    incoming.append(sighting)
                }
            }
            let differs = logbook.merge(remote: incoming)
            // Our copy knew something the server didn't (another device, a closer pass).
            queue(saved: differs, deleted: [])
            let deleted = Set(changes.deletions.map(\.recordID.recordName))
            deleted.forEach { serverRecords[$0] = nil }
            // A deleted photo record only means its image is gone; the sighting's own
            // record says which photos it still has.
            logbook.photoStore.delete(deleted.compactMap(Self.photoID))
            logbook.applyRemoteDeletions(deleted.filter { Self.photoID($0) == nil })

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                serverRecords[record.recordID.recordName] = record
            }
            var retry = Set<String>()
            var needsZone = false
            for failure in sent.failedRecordSaves {
                let name = failure.record.recordID.recordName
                switch failure.error.code {
                case .serverRecordChanged:
                    // Another device saved it first: merge theirs into ours and send the result.
                    if let server = failure.error.serverRecord {
                        serverRecords[name] = server
                        if Self.photoID(name) == nil, let theirs = Self.sighting(from: server) { logbook.merge(remote: [theirs]) }
                    }
                    retry.insert(name)
                case .zoneNotFound:
                    needsZone = true
                    retry.insert(name)
                case .unknownItem:
                    serverRecords[name] = nil
                    retry.insert(name)
                case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    // The engine retries these on its own.
                    break
                default:
                    Self.log.error("Couldn't save \(name, privacy: .public): \(failure.error.localizedDescription, privacy: .public)")
                }
            }
            if needsZone {
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            }
            queue(saved: retry, deleted: [])

        case .fetchedDatabaseChanges(let changes):
            // The zone was deleted (e.g. the user cleared the app's iCloud data): start over.
            if changes.deletions.contains(where: { $0.zoneID == Self.zoneID }) {
                serverRecords = [:]
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
                queueEverything()
            }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        var saves: [CKRecord] = []
        var deletes: [CKRecord.ID] = []
        var gone: [CKSyncEngine.PendingRecordZoneChange] = []
        // CloudKit takes up to 400 records a request; stay well under, and send only a few
        // photos at a time (each carries a few hundred KB).
        var photos = 0
        for change in pending.prefix(Self.batchLimit) {
            switch change {
            case .saveRecord(let id):
                if Self.photoID(id.recordName) != nil {
                    guard photos < Self.photoBatchLimit else { continue }
                    photos += 1
                }
                if let record = record(for: id) { saves.append(record) } else { gone.append(change) }
            case .deleteRecord(let id):
                deletes.append(id)
            @unknown default:
                break
            }
        }
        // Deleted or trimmed since it was queued: nothing to send.
        if !gone.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: gone) }
        guard !saves.isEmpty || !deletes.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: saves, recordIDsToDelete: deletes, atomicByZone: false)
    }

    private static let batchLimit = 200
    private static let photoBatchLimit = 20

    // MARK: Records

    /// nil drops the change (the sighting was deleted or trimmed since it was queued).
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        if let photoID = Self.photoID(recordID.recordName) { return photoRecord(for: recordID, photoID: photoID) }
        guard let sighting = logbook.sighting(id: recordID.recordName),
              let payload = try? JSONEncoder().encode(sighting) else { return nil }
        let record = serverRecords[recordID.recordName] ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record["payload"] = payload as NSData
        record["lastSeen"] = sighting.lastSeen as NSDate
        return record
    }

    /// nil drops the change (the photo was deleted, or its image isn't on this device).
    private func photoRecord(for recordID: CKRecord.ID, photoID: String) -> CKRecord? {
        guard let photo = logbook.photo(id: photoID), logbook.photoStore.hasImage(photoID),
              let url = logbook.photoStore.url(for: photoID) else { return nil }
        let record = serverRecords[recordID.recordName] ?? CKRecord(recordType: Self.photoRecordType, recordID: recordID)
        record["image"] = CKAsset(fileURL: url)
        record["sighting"] = photo.flightID as NSString
        record["takenAt"] = photo.takenAt as NSDate
        return record
    }

    private func importPhoto(from record: CKRecord) {
        guard let id = Self.photoID(record.recordID.recordName),
              let asset = record["image"] as? CKAsset, let url = asset.fileURL else { return }
        // CloudKit deletes the downloaded file after this event, so copy it now.
        try? logbook.photoStore.importFile(at: url, id: id)
    }

    private static func sighting(from record: CKRecord) -> Sighting? {
        guard let payload = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(Sighting.self, from: payload)
    }

    // MARK: State

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let stateURL, let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let stateURL, let data = try? JSONEncoder().encode(state) else { return }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            // Next launch starts from an older state: it re-fetches, nothing is lost.
            Self.log.error("Couldn't save the sync state: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func fetchChanges(_ engine: CKSyncEngine) async {
        do {
            try await engine.fetchChanges()
        } catch {
            log.error("Couldn't fetch logbook changes: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeState() {
        guard let stateURL else { return }
        try? FileManager.default.removeItem(at: stateURL)
    }
}
#endif
