//
//  SavedSpotTests.swift
//  WhatTheFlightTests
//
//  Named places to watch from (Enhancements Spec C8).
//

import XCTest
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class SavedSpotTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "wtf.tests.savedSpots"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private let home = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
    private let office = CLLocationCoordinate2D(latitude: 33.640, longitude: -84.427)
    private let fence = CLLocationCoordinate2D(latitude: 40.640, longitude: -73.779)

    func testThreeSpotsSurviveARelaunch() {
        let settings = RadarSettings(defaults: defaults)
        settings.saveSpot(named: "Home", at: home)
        settings.saveSpot(named: "Office", at: office)
        settings.saveSpot(named: "JFK fence", at: fence)
        let relaunched = RadarSettings(defaults: defaults)
        XCTAssertEqual(relaunched.savedSpots.map(\.name), ["Home", "Office", "JFK fence"])
    }

    func testWatchingASpotSetsTheCustomSpotAndItsName() {
        let settings = RadarSettings(defaults: defaults)
        let spot = settings.saveSpot(named: "Office", at: office)
        settings.watch(spot)
        XCTAssertEqual(settings.locationMode, .custom)
        XCTAssertEqual(settings.customPlaceName, "Office")
        XCTAssertEqual(settings.customCoordinate?.latitude ?? 0, office.latitude, accuracy: 1e-9)
        XCTAssertEqual(settings.currentSavedSpot?.id, spot.id)
    }

    func testSavingTheSamePlaceAgainRenamesIt() {
        let settings = RadarSettings(defaults: defaults)
        settings.saveSpot(named: "Home", at: home)
        let nearby = CLLocationCoordinate2D(latitude: home.latitude + 0.0003, longitude: home.longitude)
        settings.saveSpot(named: "Home sweet home", at: nearby)
        XCTAssertEqual(settings.savedSpots.map(\.name), ["Home sweet home"])
    }

    func testAnUnnamedSpotIsNamedByItsCoordinates() {
        let settings = RadarSettings(defaults: defaults)
        let spot = settings.saveSpot(named: "  ", at: fence)
        XCTAssertEqual(spot.name, fence.shortDescription)
    }
}
