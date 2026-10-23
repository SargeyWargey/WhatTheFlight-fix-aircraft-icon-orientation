//
//  PinSyncTests.swift
//  WhatTheFlightTests
//
//  Pins shared between devices through one iCloud key-value store.
//

import XCTest
@testable import WhatTheFlight

/// One iCloud key-value store, shared by every simulated device.
final class MemoryPinStore: PinStore {
    var values: [String: Any] = [:]
    var dictionaryRepresentation: [String: Any] { values }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func synchronize() -> Bool { true }
}

@MainActor
final class PinSyncTests: XCTestCase {
    /// A device: its own settings and defaults, the shared store.
    struct Device {
        let settings: RadarSettings
        let sync: PinSync
        var arrived: [[PinnedAircraft]] { box.value }
        let box: Box
        final class Box { var value: [[PinnedAircraft]] = [] }
    }

    var store: MemoryPinStore!

    override func setUp() async throws {
        store = MemoryPinStore()
    }

    private func device(_ name: String = UUID().uuidString) -> Device {
        let defaults = UserDefaults(suiteName: "PinSyncTests-\(name)-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        let sync = PinSync(settings: settings, store: store, defaults: defaults)
        let box = Device.Box()
        sync.onRemoteChange = { box.value.append($0) }
        return Device(settings: settings, sync: sync, box: box)
    }

    private func pin(_ reg: String, id: String? = nil, at seconds: TimeInterval = 0) -> PinnedAircraft {
        var f = TestTraffic.flight(id ?? "f-\(reg)", miles: 500)
        f.registration = reg
        return PinnedAircraft(f, pinnedAt: Date(timeIntervalSince1970: 1_000 + seconds))
    }

    func testAPinMadeOnOneDeviceArrivesOnTheOther() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.pinnedAircraft.append(pin("G-XLEB"))
        tv.sync.merge()
        XCTAssertEqual(tv.settings.pinnedAircraft.map(\.id), ["G-XLEB"])
        XCTAssertEqual(tv.arrived.last?.map(\.id), ["G-XLEB"])
    }

    func testUnpinningOnOneDeviceRemovesItEverywhere() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.pinnedAircraft = [pin("G-XLEB"), pin("N509DN", at: 1)]
        tv.sync.merge()
        XCTAssertEqual(tv.settings.pinnedAircraft.count, 2)

        tv.settings.pinnedAircraft.removeAll { $0.id == "G-XLEB" }
        phone.sync.merge()
        XCTAssertEqual(phone.settings.pinnedAircraft.map(\.id), ["N509DN"])
        XCTAssertEqual(phone.arrived.last?.count, 0, "a removal isn't an arrival")
    }

    func testPinsMadeBeforeSyncingAreSentNotDropped() {
        let phone = device()
        phone.settings.pinnedAircraft = [pin("G-XLEB")]
        phone.sync.start()
        XCTAssertEqual(phone.settings.pinnedAircraft.map(\.id), ["G-XLEB"])
        XCTAssertNotNil(store.values[PinSync.key(for: "G-XLEB")])
    }

    func testPinningOnTwoDevicesAtOnceKeepsBoth() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.pinnedAircraft.append(pin("G-XLEB", at: 1))
        tv.settings.pinnedAircraft.append(pin("N509DN", at: 2))
        phone.sync.merge()
        tv.sync.merge()
        XCTAssertEqual(phone.settings.pinnedAircraft.map(\.id), ["G-XLEB", "N509DN"])
        XCTAssertEqual(tv.settings.pinnedAircraft.map(\.id), ["G-XLEB", "N509DN"])
    }

    func testDemoPinsStayOnTheirDevice() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.pinnedAircraft.append(pin("N685DA", id: "demo-0"))
        tv.sync.merge()
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertTrue(tv.settings.pinnedAircraft.isEmpty)
        phone.sync.merge()
        XCTAssertEqual(phone.settings.pinnedAircraft.map(\.flightID), ["demo-0"])
    }

    func testTheOldestMakeWayAcrossDevices() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.pinnedAircraft = (0..<RadarModel.maxPins).map { pin("N\($0 + 1)AA", at: Double($0)) }
        tv.settings.pinnedAircraft = [pin("G-XLEB", at: 100)]
        tv.sync.merge()
        XCTAssertEqual(tv.settings.pinnedAircraft.count, RadarModel.maxPins)
        XCTAssertEqual(tv.settings.pinnedAircraft.last?.id, "G-XLEB")
        XCTAssertFalse(tv.settings.pinnedAircraft.contains { $0.id == "N1AA" })
        phone.sync.merge()
        XCTAssertEqual(phone.settings.pinnedAircraft.map(\.id), tv.settings.pinnedAircraft.map(\.id))
    }

    func testPinsSavedBeforeTimestampsStillLoad() throws {
        let old = #"{"flightID":"abc","registration":"N1","label":"N1"}"#
        let decoded = try JSONDecoder().decode(PinnedAircraft.self, from: Data(old.utf8))
        XCTAssertNil(decoded.pinnedAt)
        XCTAssertEqual(decoded.id, "N1")
    }
}
