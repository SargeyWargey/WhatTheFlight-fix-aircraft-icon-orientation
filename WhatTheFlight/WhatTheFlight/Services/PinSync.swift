//
//  PinSync.swift
//  WhatTheFlight
//
//  Pinned and favourite aircraft on every device signed in to the same iCloud account
//  (iPhone, iPad, Apple TV, Apple Watch), through iCloud key-value storage. Each one is its own
//  key ("pin.<airframe>", "fav.<airframe>"), so adding on two devices at once keeps both and
//  removing deletes the key everywhere. The keys this device has seen in iCloud are
//  remembered, so one missing from iCloud can be told apart: removed on another device (drop
//  it here) or never sent (send it). Demo traffic's stay on their device.
//

import Foundation

/// The bits of `NSUbiquitousKeyValueStore` that the syncs use, so tests can stand in.
protocol PinStore: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: PinStore {}

/// Something kept as one key per item in iCloud key-value storage.
protocol CloudListItem: Codable, Equatable, Sendable {
    var id: String { get }
    /// Stays on this device (demo traffic).
    var isLocalOnly: Bool { get }
    /// Orders the list across devices, oldest first; nil sorts first.
    var syncDate: Date? { get }
}

extension PinnedAircraft: CloudListItem {
    var isLocalOnly: Bool { isDemo }
    var syncDate: Date? { pinnedAt }
}

extension FavoriteAircraft: CloudListItem {
    var isLocalOnly: Bool { isDemo }
    var syncDate: Date? { addedAt }
}

/// Keeps one list in `RadarSettings` and iCloud together. `PinSync` and `FavoriteSync` say
/// which list, under which keys, and how long it may grow.
@MainActor
class CloudListSync<Item: CloudListItem> {
    private let keyPrefix: String
    private let seenKey: String
    /// Past this the oldest make way (pins); nil for no limit.
    private let limit: Int?
    private let store: PinStore
    private let defaults: UserDefaults
    private let read: () -> [Item]
    private let write: ([Item]) -> Void
    /// Installs (or, with nil, removes) the settings' hook for local changes.
    private let watch: (((_ old: [Item]) -> Void)?) -> Void
    private var observer: NSObjectProtocol?
    private var isApplyingRemote = false

    /// After items arrive from (or are removed on) another device, with the ones that arrived.
    var onRemoteChange: (([Item]) -> Void)?

    init(keyPrefix: String, seenKey: String, limit: Int?, store: PinStore, defaults: UserDefaults,
         read: @escaping () -> [Item], write: @escaping ([Item]) -> Void,
         watch: @escaping (((_ old: [Item]) -> Void)?) -> Void) {
        self.keyPrefix = keyPrefix
        self.seenKey = seenKey
        self.limit = limit
        self.store = store
        self.defaults = defaults
        self.read = read
        self.write = write
        self.watch = watch
    }

    func start() {
        guard observer == nil else { return }
        watch { [weak self] old in self?.localChange(from: old) }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                guard let self else { return }
                // A different iCloud account: nothing it holds was seen before, so send ours.
                if reason == NSUbiquitousKeyValueStoreAccountChange { self.defaults.removeObject(forKey: self.seenKey) }
                self.merge()
            }
        }
        store.synchronize()
        merge()
    }

    /// Checks iCloud again (the app came back to the foreground).
    func refresh() {
        store.synchronize()
        merge()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        watch(nil)
    }

    /// Brings this device's list and iCloud's together.
    func merge() {
        let remote = remoteItems()
        let local = read()
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        var result: [Item] = []
        var arrived: [Item] = []

        for item in local {
            if item.isLocalOnly {
                result.append(item)
            } else if remote[item.id] != nil {
                result.append(item)
            } else if !seen.contains(item.id) {
                // Added here and not sent yet (offline, or the first sync).
                send(item)
                result.append(item)
            }
            // Otherwise it was in iCloud and isn't any more: removed on another device.
        }
        for (id, item) in remote where !local.contains(where: { $0.id == id }) {
            result.append(item)
            arrived.append(item)
        }

        result.sort { ($0.syncDate ?? .distantPast) < ($1.syncDate ?? .distantPast) }
        if let limit, result.count > limit {
            let dropped = result.prefix(result.count - limit)
            dropped.filter { !$0.isLocalOnly }.forEach { store.removeObject(forKey: key(for: $0.id)) }
            result.removeFirst(dropped.count)
            arrived.removeAll { item in dropped.contains { $0.id == item.id } }
        }

        // Only what iCloud really holds counts as seen: without iCloud (signed out, or a build
        // without the entitlement) nothing is, so nothing is mistaken for removed elsewhere.
        let held = heldIDs()
        seen = Set(result.filter { !$0.isLocalOnly && held.contains($0.id) }.map(\.id))
        defaults.set(Array(seen).sorted(), forKey: seenKey)
        guard result != local else { return }
        isApplyingRemote = true
        write(result)
        isApplyingRemote = false
        onRemoteChange?(arrived)
    }

    /// Added, removed or changed here: tell iCloud.
    private func localChange(from old: [Item]) {
        guard !isApplyingRemote else { return }
        let new = read().filter { !$0.isLocalOnly }
        let before = old.filter { !$0.isLocalOnly }
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        for item in new where before.first(where: { $0.id == item.id }) != item {
            send(item)
            if heldIDs().contains(item.id) { seen.insert(item.id) }
        }
        for item in before where !new.contains(where: { $0.id == item.id }) {
            store.removeObject(forKey: key(for: item.id))
            seen.remove(item.id)
        }
        defaults.set(Array(seen).sorted(), forKey: seenKey)
    }

    private func send(_ item: Item) {
        guard let data = try? JSONEncoder().encode(item) else { return }
        store.set(data, forKey: key(for: item.id))
    }

    /// Ids iCloud holds a key for.
    private func heldIDs() -> Set<String> {
        Set(store.dictionaryRepresentation.keys.filter { $0.hasPrefix(keyPrefix) }.map { String($0.dropFirst(keyPrefix.count)) })
    }

    private func remoteItems() -> [String: Item] {
        var items: [String: Item] = [:]
        for (key, value) in store.dictionaryRepresentation where key.hasPrefix(keyPrefix) {
            guard let data = value as? Data, let item = try? JSONDecoder().decode(Item.self, from: data) else { continue }
            items[item.id] = item
        }
        return items
    }

    private func key(for id: String) -> String { keyPrefix + id }
}

/// Pins: at most `RadarModel.maxPins`, the oldest making way.
final class PinSync: CloudListSync<PinnedAircraft> {
    static let keyPrefix = "pin."
    /// Pin ids this device has seen in iCloud.
    static let seenKey = "wtf.pinsInCloud"

    init(settings: RadarSettings, store: PinStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard) {
        super.init(keyPrefix: Self.keyPrefix, seenKey: Self.seenKey, limit: RadarModel.maxPins, store: store, defaults: defaults,
                   read: { settings.pinnedAircraft }, write: { settings.pinnedAircraft = $0 },
                   watch: { settings.onPinnedAircraftChange = $0 })
    }

    static func key(for id: String) -> String { keyPrefix + id }
}

/// Favourites: no limit beyond `RadarModel.maxFavorites`, which adding enforces.
final class FavoriteSync: CloudListSync<FavoriteAircraft> {
    static let keyPrefix = "fav."
    /// Favourite ids this device has seen in iCloud.
    static let seenKey = "wtf.favoritesInCloud"

    init(settings: RadarSettings, store: PinStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard) {
        super.init(keyPrefix: Self.keyPrefix, seenKey: Self.seenKey, limit: nil, store: store, defaults: defaults,
                   read: { settings.favoriteAircraft }, write: { settings.favoriteAircraft = $0 },
                   watch: { settings.onFavoriteAircraftChange = $0 })
    }

    static func key(for id: String) -> String { keyPrefix + id }
}
