//
//  LogbookSync.swift
//  WhatTheFlight
//
//  One logbook across your iPhone, iPad and Apple TV, through iCloud (CloudKit, private
//  database). Each sighting is one record named after the feed's flight id, so the same
//  flight logged on two devices lands on one record and the copies merge
//  (`Sighting.merged(with:)`). `CKSyncEngine` does the scheduling, batching and retries.
//

#if os(iOS) || os(tvOS)
import CloudKit
import Foundation
import os

@MainActor
final class LogbookSync: CKSyncEngineDelegate {
    static let containerID = "iCloud.SargeyWargey.WhatTheFlight"

    private static let zoneID = CKRecordZone.ID(zoneName: "Logbook", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "Sighting"
    private static let log = Logger(subsystem: "SargeyWargey.WhatTheFlight", category: "LogbookSync")

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
        if saved == nil {
            // First run on this device: make the zone and send up everything logged so far.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
            queue(saved: logbook.allIDs, deleted: [])
        }
        Task { try? await engine.fetchChanges() }
    }

    /// Stops syncing; the logbook stays on this device.
    func stop() {
        logbook.onLocalChange = nil
        engine = nil
    }

    /// Pulls anything new from other devices now (the app came to the foreground).
    func fetchNow() {
        guard let engine else { return }
        Task { try? await engine.fetchChanges() }
    }

    private func queue(saved: Set<String>, deleted: Set<String>) {
        guard let engine else { return }
        let changes = saved.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: $0)) }
            + deleted.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID(for: $0)) }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    private func recordID(for id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: Self.zoneID)
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
                queue(saved: logbook.allIDs, deleted: [])
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
                serverRecords[record.recordID.recordName] = record
                if let sighting = Self.sighting(from: record) { incoming.append(sighting) }
            }
            let differs = logbook.merge(remote: incoming)
            // Our copy knew something the server didn't (another device, a closer pass).
            queue(saved: differs, deleted: [])
            let deleted = Set(changes.deletions.map(\.recordID.recordName))
            deleted.forEach { serverRecords[$0] = nil }
            logbook.applyRemoteDeletions(deleted)

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
                        if let theirs = Self.sighting(from: server) { logbook.merge(remote: [theirs]) }
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
                queue(saved: logbook.allIDs, deleted: [])
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
        // CloudKit takes up to 400 records a request; stay well under.
        for change in pending.prefix(Self.batchLimit) {
            switch change {
            case .saveRecord(let id):
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

    // MARK: Records

    /// nil drops the change (the sighting was deleted or trimmed since it was queued).
    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard let sighting = logbook.sighting(id: recordID.recordName),
              let payload = try? JSONEncoder().encode(sighting) else { return nil }
        let record = serverRecords[recordID.recordName] ?? CKRecord(recordType: Self.recordType, recordID: recordID)
        record["payload"] = payload as NSData
        record["lastSeen"] = sighting.lastSeen as NSDate
        return record
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
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    private func removeState() {
        guard let stateURL else { return }
        try? FileManager.default.removeItem(at: stateURL)
    }
}
#endif
