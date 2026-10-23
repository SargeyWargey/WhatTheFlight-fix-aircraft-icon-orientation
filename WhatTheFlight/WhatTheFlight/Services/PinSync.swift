//
//  PinSync.swift
//  WhatTheFlight
//
//  Pinned aircraft on every device signed in to the same iCloud account (iPhone, iPad,
//  Apple TV, Apple Watch), through iCloud key-value storage. Each pin is its own key
//  ("pin.<airframe>"), so pinning on two devices at once keeps both and unpinning removes
//  the key everywhere. The keys this device has seen in iCloud are remembered, so a pin
//  missing from iCloud can be told apart: removed on another device (drop it here) or never
//  sent (send it). Demo-traffic pins stay on their device.
//

import Foundation

/// The bits of `NSUbiquitousKeyValueStore` that `PinSync` uses, so tests can stand in.
protocol PinStore: AnyObject {
    var dictionaryRepresentation: [String: Any] { get }
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: PinStore {}

@MainActor
final class PinSync {
    static let keyPrefix = "pin."
    /// Pin ids this device has seen in iCloud.
    static let seenKey = "wtf.pinsInCloud"

    private let settings: RadarSettings
    private let store: PinStore
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var isApplyingRemote = false

    /// After pins arrive from (or are removed on) another device, with the ones that arrived.
    var onRemoteChange: (([PinnedAircraft]) -> Void)?

    init(settings: RadarSettings, store: PinStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.store = store
        self.defaults = defaults
    }

    func start() {
        guard observer == nil else { return }
        settings.onPinnedAircraftChange = { [weak self] old in self?.localChange(from: old) }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                // A different iCloud account: nothing it holds was seen before, so send ours.
                if reason == NSUbiquitousKeyValueStoreAccountChange { self?.defaults.removeObject(forKey: Self.seenKey) }
                self?.merge()
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
        settings.onPinnedAircraftChange = nil
    }

    /// Brings this device's pins and iCloud's together.
    func merge() {
        let remote = remotePins()
        let local = settings.pinnedAircraft
        var seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        var result: [PinnedAircraft] = []
        var arrived: [PinnedAircraft] = []

        for pin in local {
            if pin.isDemo {
                result.append(pin)
            } else if remote[pin.id] != nil {
                result.append(pin)
            } else if !seen.contains(pin.id) {
                // Pinned here and not sent yet (offline, or the first sync).
                write(pin)
                result.append(pin)
            }
            // Otherwise it was in iCloud and isn't any more: unpinned on another device.
        }
        for (id, pin) in remote where !local.contains(where: { $0.id == id }) {
            result.append(pin)
            arrived.append(pin)
        }

        result.sort { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
        if result.count > RadarModel.maxPins {
            let dropped = result.prefix(result.count - RadarModel.maxPins)
            dropped.filter { !$0.isDemo }.forEach { store.removeObject(forKey: Self.key(for: $0.id)) }
            result.removeFirst(dropped.count)
            arrived.removeAll { pin in dropped.contains { $0.id == pin.id } }
        }

        seen = Set(result.filter { !$0.isDemo }.map(\.id))
        defaults.set(Array(seen).sorted(), forKey: Self.seenKey)
        guard result != local else { return }
        isApplyingRemote = true
        settings.pinnedAircraft = result
        isApplyingRemote = false
        onRemoteChange?(arrived)
    }

    /// Pinned, unpinned, or followed onto a new leg here: tell iCloud.
    private func localChange(from old: [PinnedAircraft]) {
        guard !isApplyingRemote else { return }
        let new = settings.pinnedAircraft.filter { !$0.isDemo }
        let before = old.filter { !$0.isDemo }
        var seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
        for pin in new where before.first(where: { $0.id == pin.id }) != pin {
            write(pin)
            seen.insert(pin.id)
        }
        for pin in before where !new.contains(where: { $0.id == pin.id }) {
            store.removeObject(forKey: Self.key(for: pin.id))
            seen.remove(pin.id)
        }
        defaults.set(Array(seen).sorted(), forKey: Self.seenKey)
    }

    private func write(_ pin: PinnedAircraft) {
        guard let data = try? JSONEncoder().encode(pin) else { return }
        store.set(data, forKey: Self.key(for: pin.id))
    }

    private func remotePins() -> [String: PinnedAircraft] {
        var pins: [String: PinnedAircraft] = [:]
        for (key, value) in store.dictionaryRepresentation where key.hasPrefix(Self.keyPrefix) {
            guard let data = value as? Data, let pin = try? JSONDecoder().decode(PinnedAircraft.self, from: data) else { continue }
            pins[pin.id] = pin
        }
        return pins
    }

    static func key(for id: String) -> String { keyPrefix + id }
}
