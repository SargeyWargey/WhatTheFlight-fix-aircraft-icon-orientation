//
//  FavoriteAircraftTests.swift
//  WhatTheFlightTests
//
//  Favourites: airframes called out in yellow wherever they turn up, kept in settings and
//  shared between devices through iCloud.
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

final class FavoriteAircraftTests: XCTestCase {
    private func flight(_ id: String, registration: String? = nil, hex: String? = nil, callsign: String? = nil) -> Flight {
        var f = TestTraffic.flight(id, miles: 5)
        f.registration = registration
        f.hex = hex
        f.callsign = callsign
        return f
    }

    private func sighting(_ id: String, registration: String? = nil, hex: String? = nil, callsign: String? = nil) -> Sighting {
        let date = Date(timeIntervalSince1970: 1_000_000)
        return Sighting(id: id, firstSeen: date, lastSeen: date, displayIdentifier: id.uppercased(), callsign: callsign,
                        registration: registration, hex: hex, typeCode: "B78X", kind: .airplane, operatorName: "United Airlines",
                        isAirline: true, originIATA: "EWR", destinationIATA: "BRU", closestMiles: 4, altitudeAtClosestFeet: 7_200,
                        speedKnots: 260, tags: [], placeName: nil)
    }

    func testAFavouriteFollowsTheAirframeOntoItsNextLeg() {
        let favorite = FavoriteAircraft(flight("leg1", registration: "n12006"), operatorName: "United Airlines")
        XCTAssertEqual(favorite.id, "N12006", "Registrations are kept uppercased")
        XCTAssertTrue(favorite.matches(flight("leg2", registration: "N12006")))
        XCTAssertFalse(favorite.matches(flight("other", registration: "N12007")))
    }

    func testTheHexStandsInWhenTheFeedHasNoRegistration() {
        let favorite = FavoriteAircraft(flight("leg1", registration: "N12006", hex: "a0b1c2"), operatorName: nil)
        XCTAssertTrue(favorite.matches(flight("leg2", hex: "A0B1C2")))
        XCTAssertFalse(favorite.matches(flight("leg3", hex: "FFFFFF")))
    }

    func testOnlyAircraftWithNoRegistrationOrHexGoByCallsign() {
        let byCallsign = FavoriteAircraft(flight("leg1", callsign: "LIFE21"), operatorName: nil)
        XCTAssertTrue(byCallsign.matches(flight("leg2", callsign: "LIFE21")))
        // An airframe favourite isn't every flight that borrows its callsign.
        let byRegistration = FavoriteAircraft(flight("leg1", registration: "N12006", callsign: "UAL994"), operatorName: nil)
        XCTAssertFalse(byRegistration.matches(flight("leg2", registration: "N99999", callsign: "UAL994")))
    }

    func testTheSetFindsFlightsSightingsAndLogbookAirframes() {
        let set = FavoriteSet([
            FavoriteAircraft(flight("a", registration: "N12006"), operatorName: nil),
            FavoriteAircraft(flight("b", hex: "ABC123"), operatorName: nil),
        ])
        XCTAssertTrue(set.contains(flight("x", registration: "N12006")))
        XCTAssertTrue(set.contains(sighting("y", hex: "abc123")))
        XCTAssertFalse(set.contains(sighting("z", registration: "N55555")))
        XCTAssertTrue(set.contains(airframe: "N12006"))
        XCTAssertTrue(set.contains(airframe: "ABC123"), "Aircraft without a registration are logged by hex")
        XCTAssertFalse(set.contains(airframe: "N55555"))
        XCTAssertFalse(FavoriteSet().contains(flight("x", registration: "N12006")))
    }

    func testAFavouriteFromTheLogbookIsTheSameAirframeAsOneFromTheFeed() {
        let fromFeed = FavoriteAircraft(flight("leg1", hex: "A0B1C2"), operatorName: nil)
        let fromLogbook = FavoriteAircraft(sighting("seen", registration: "N12006", hex: "A0B1C2"))
        XCTAssertTrue(fromFeed.matches(fromLogbook))
        XCTAssertEqual(fromLogbook.title, "N12006")
        XCTAssertEqual(fromLogbook.typeName, "Boeing 787-10 Dreamliner")
        XCTAssertEqual(fromLogbook.operatorName, "United Airlines")
    }
}

@MainActor
final class FavoriteRadarModelTests: XCTestCase {
    var defaults: UserDefaults!
    var settings: RadarSettings!
    var feed: WorldFeed!
    var model: RadarModel!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "FavoriteRadarModelTests-\(UUID().uuidString)")
        settings = RadarSettings(defaults: defaults)
        settings.radiusMiles = 20
        feed = WorldFeed()
        model = RadarModel(settings: settings, liveFeed: feed, demoFeed: feed)
        model.setObserver(TestTraffic.observer)
    }

    private func flight(_ id: String, registration: String, miles: Double = 5) -> Flight {
        var f = TestTraffic.flight(id, miles: miles)
        f.registration = registration
        return f
    }

    func testToggleAddsThenRemoves() {
        let f = flight("ua994", registration: "N12006")
        model.toggleFavorite(f)
        XCTAssertTrue(model.isFavorite(f))
        XCTAssertEqual(model.favorites.map(\.id), ["N12006"])
        XCTAssertTrue(settings.favoriteSet.contains(f), "The lookup views read stays in step")

        model.toggleFavorite(f)
        XCTAssertFalse(model.isFavorite(f))
        XCTAssertTrue(model.favorites.isEmpty)
    }

    func testFavouritesAreRememberedAcrossLaunches() {
        model.favorite(flight("ua994", registration: "N12006"))
        let relaunched = RadarSettings(defaults: defaults)
        XCTAssertEqual(relaunched.favoriteAircraft.map(\.id), ["N12006"])
        XCTAssertTrue(relaunched.favoriteSet.contains(airframe: "N12006"))
    }

    func testFavouritingTwiceKeepsOne() {
        model.favorite(flight("leg1", registration: "N12006"))
        model.favorite(flight("leg2", registration: "N12006"))
        XCTAssertEqual(model.favorites.count, 1)
    }

    func testRemovingFromTheLogbookFindsAFavouriteSavedByHex() {
        var f = TestTraffic.flight("leg1", miles: 5)
        f.hex = "A0B1C2"
        model.favorite(f)
        // The logbook's page knows the registration too; it's still the same aircraft.
        model.toggleFavorite(FavoriteAircraft(registration: "N12006", hex: "A0B1C2", callsign: nil, flightID: "seen",
                                              label: "UA994", typeCode: "B78X", operatorName: nil))
        XCTAssertTrue(model.favorites.isEmpty)
    }

    func testThereIsALimit() {
        settings.favoriteAircraft = (0..<RadarModel.maxFavorites).map {
            FavoriteAircraft(registration: "N\($0)", hex: nil, callsign: nil, flightID: "f\($0)", label: "F\($0)",
                             typeCode: nil, operatorName: nil)
        }
        model.favorite(flight("one-more", registration: "G-XLEI"))
        XCTAssertEqual(model.favorites.count, RadarModel.maxFavorites)
        XCTAssertEqual(model.notice?.text, "\(RadarModel.maxFavorites) favorites max · remove one to add G-XLEI")
    }

    func testWhereAFavouriteIsNow() async {
        feed.local = [flight("near", registration: "N12006", miles: 3), flight("parked", registration: "G-XLEI", miles: 2)]
        feed.local[1].isOnGround = true
        await model.pollOnce()
        model.favorite(feed.local[0])
        model.favorite(feed.local[1])
        model.toggleFavorite(FavoriteAircraft(registration: "D-ABYA", hex: nil, callsign: nil, flightID: "gone",
                                              label: "LH403", typeCode: "B748", operatorName: "Lufthansa"))

        let states = model.favorites.map { model.state(of: $0) }
        guard case .visible(let contact) = states[0] else { return XCTFail("N12006 should be on the radar") }
        XCTAssertEqual(contact.id, "near")
        guard case .onGround = states[1] else { return XCTFail("G-XLEI is parked") }
        guard case .unseen = states[2] else { return XCTFail("D-ABYA isn't in the feed") }
    }
}

@MainActor
final class FavoriteSyncTests: XCTestCase {
    struct Device {
        let settings: RadarSettings
        let sync: FavoriteSync
    }

    var store: MemoryPinStore!

    override func setUp() async throws {
        store = MemoryPinStore()
    }

    private func device() -> Device {
        let defaults = UserDefaults(suiteName: "FavoriteSyncTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        return Device(settings: settings, sync: FavoriteSync(settings: settings, store: store, defaults: defaults))
    }

    private func favorite(_ registration: String, flightID: String? = nil, at seconds: TimeInterval = 0) -> FavoriteAircraft {
        FavoriteAircraft(registration: registration, hex: nil, callsign: nil, flightID: flightID ?? "f-\(registration)",
                         label: registration, typeCode: "A388", operatorName: "Emirates",
                         addedAt: Date(timeIntervalSince1970: 1_000 + seconds))
    }

    func testAFavouriteMadeOnOneDeviceArrivesOnTheOther() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.favoriteAircraft.append(favorite("A6-EUI"))
        XCTAssertNotNil(store.values[FavoriteSync.key(for: "A6-EUI")])
        tv.sync.merge()
        XCTAssertEqual(tv.settings.favoriteAircraft.map(\.id), ["A6-EUI"])
        XCTAssertTrue(tv.settings.favoriteSet.contains(airframe: "A6-EUI"))
    }

    func testRemovingOnOneDeviceRemovesItEverywhere() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.favoriteAircraft.append(favorite("A6-EUI"))
        tv.sync.merge()
        tv.settings.favoriteAircraft.removeAll()
        phone.sync.merge()
        XCTAssertTrue(phone.settings.favoriteAircraft.isEmpty)
    }

    func testFavouritesHaveNoPinLimitAndKeepTheirOrder() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.favoriteAircraft = (0..<12).map { favorite("N\($0)", at: Double($0)) }
        tv.sync.merge()
        XCTAssertEqual(tv.settings.favoriteAircraft.map(\.id), (0..<12).map { "N\($0)" })
    }

    func testDemoFavouritesStayOnTheirDevice() {
        let phone = device(), tv = device()
        phone.sync.start()
        tv.sync.start()
        phone.settings.favoriteAircraft.append(favorite("N-DEMO", flightID: "demo-1"))
        tv.sync.merge()
        XCTAssertTrue(tv.settings.favoriteAircraft.isEmpty)
        XCTAssertEqual(phone.settings.favoriteAircraft.map(\.id), ["N-DEMO"])
    }

    func testWithoutICloudNothingIsMistakenForRemovedElsewhere() {
        // A store that keeps nothing: signed out of iCloud, or a build without the entitlement.
        final class ForgetfulStore: PinStore {
            var dictionaryRepresentation: [String: Any] { [:] }
            func set(_ value: Any?, forKey key: String) {}
            func removeObject(forKey key: String) {}
            func synchronize() -> Bool { false }
        }
        let defaults = UserDefaults(suiteName: "FavoriteSyncTests-\(UUID().uuidString)")!
        let settings = RadarSettings(defaults: defaults)
        let sync = FavoriteSync(settings: settings, store: ForgetfulStore(), defaults: defaults)
        settings.favoriteAircraft = [favorite("D-ABYA")]
        sync.start()
        settings.favoriteAircraft.append(favorite("A6-EUI", at: 5))
        sync.refresh()
        sync.refresh()
        XCTAssertEqual(settings.favoriteAircraft.map(\.id), ["D-ABYA", "A6-EUI"])
    }

    func testPinsAndFavouritesKeepToTheirOwnKeys() {
        let phone = device()
        phone.sync.start()
        phone.settings.favoriteAircraft.append(favorite("A6-EUI"))
        XCTAssertTrue(store.values.keys.allSatisfy { $0.hasPrefix(FavoriteSync.keyPrefix) })
        let pins = PinSync(settings: phone.settings, store: store, defaults: UserDefaults(suiteName: "FavoriteSyncTests-pins-\(UUID().uuidString)")!)
        pins.merge()
        XCTAssertTrue(phone.settings.pinnedAircraft.isEmpty, "A favourite in iCloud is never read as a pin")
    }
}
