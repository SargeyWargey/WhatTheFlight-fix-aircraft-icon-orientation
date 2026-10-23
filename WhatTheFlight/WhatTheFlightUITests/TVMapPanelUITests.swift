//
//  TVMapPanelUITests.swift
//  WhatTheFlightUITests
//
//  Apple TV: holding ● on the hero (with the map on screen) opens the map panel; picking a
//  range closes it again; a plain click still opens the details.
//

import XCTest

#if os(tvOS)

final class TVMapPanelUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-wtf.demoTraffic", "YES", "-wtf.hasSeenWelcome", "YES", "-wtf.tvView", "split",
                               "-wtf.debugSpot", "33.749,-84.388", "-wtf.mapRadius", "20", "-wtf.mapType", "standard"]
        app.launch()
        // Demo traffic needs a moment to arrive and focus the nearest aircraft.
        Thread.sleep(forTimeInterval: 4)
    }

    func testHoldingSelectOpensTheMapPanelAndAPickClosesIt() throws {
        remote.press(.select, forDuration: 1.2)
        let satellite = app.buttons["Satellite"]
        let opened = satellite.waitForExistence(timeout: 3)
        add(XCTAttachment(screenshot: app.screenshot()))
        XCTAssertTrue(opened, "Holding ● should open the map panel")

        // Focus starts on the current range (20 mi); one step down is 30 mi.
        remote.press(.down)
        remote.press(.select)
        XCTAssertTrue(satellite.waitForNonExistence(timeout: 3), "Picking a range should close the panel")
    }

    func testMenuClosesTheMapPanel() throws {
        remote.press(.select, forDuration: 1.2)
        let satellite = app.buttons["Satellite"]
        XCTAssertTrue(satellite.waitForExistence(timeout: 3))
        remote.press(.menu)
        XCTAssertTrue(satellite.waitForNonExistence(timeout: 3), "MENU should close the panel")
        XCTAssertEqual(app.state, .runningForeground, "MENU should close the panel, not the app")
    }

    func testAPlainClickStillOpensTheDetails() throws {
        remote.press(.select)
        // Every details screen has Close; Full Route only shows for flights with a route.
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 4), "A click should open the details")
        XCTAssertFalse(app.buttons["Satellite"].exists)
    }
}

#endif
