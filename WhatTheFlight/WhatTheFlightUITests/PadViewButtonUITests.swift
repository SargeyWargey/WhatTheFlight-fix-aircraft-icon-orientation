//
//  PadViewButtonUITests.swift
//  WhatTheFlightUITests
//
//  iPad: the bar's view button steps Radar → Split → Map → Radar, named for the view it goes
//  to, in portrait and in landscape alike.
//

import XCTest

#if os(iOS)

final class PadViewButtonUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "The three views are the iPad's")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // A custom spot east of Greenwich: a negative longitude would be read as another flag.
        app.launchArguments = ["-wtf.demoTraffic", "YES", "-wtf.hasSeenWelcome", "YES", "-wtf.iCloudLogbook", "NO",
                               "-wtf.mapView", "YES", "-wtf.padView", "radar", "-wtf.locationMode", "custom",
                               "-wtf.customLatitude", "48.85", "-wtf.customLongitude", "2.35"]
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    func testTheViewButtonStepsRadarSplitMapInBothOrientations() throws {
        let button = app.buttons["mapButton"]
        XCTAssertTrue(button.waitForExistence(timeout: 6))
        XCTAssertEqual(button.label, "Split", "The radar's button goes to Split")

        button.tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 3), "Split's button goes to Map")
        add(XCTAttachment(screenshot: app.screenshot()))

        // Turning the iPad keeps the split, now side by side.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(button.waitForExistence(timeout: 3), "Landscape keeps the view button")
        XCTAssertEqual(button.label, "Map")
        add(XCTAttachment(screenshot: app.screenshot()))

        button.tap()
        XCTAssertTrue(app.buttons["Radar"].waitForExistence(timeout: 3), "The map's button goes back to Radar")

        button.tap()
        XCTAssertTrue(app.buttons["Split"].waitForExistence(timeout: 3), "And round again")
    }
}

#endif
