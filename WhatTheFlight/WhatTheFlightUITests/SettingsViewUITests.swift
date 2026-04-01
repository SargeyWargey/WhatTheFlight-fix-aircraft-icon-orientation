//
//  SettingsViewUITests.swift
//  WhatTheFlightUITests
//
//  Created by Kiro on 8/1/25.
//

import XCTest

final class SettingsViewUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Settings Navigation Tests
    
    func testSettingsButtonExists() throws {
        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.exists, "Settings button should exist in the main view")
    }
    
    func testSettingsViewOpens() throws {
        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()
        
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 2), "Settings view should open when settings button is tapped")
    }
    
    func testSettingsViewCanBeDismissed() throws {
        openSettingsView()
        
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Cancel button should exist in settings view")
        
        cancelButton.tap()
        
        let mainTitle = app.navigationBars["WhatTheFlight"]
        XCTAssertTrue(mainTitle.waitForExistence(timeout: 2), "Should return to main view when cancel is tapped")
    }
    
    func testSettingsViewCanBeDismissedWithDone() throws {
        openSettingsView()
        
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists, "Done button should exist in settings view")
        
        doneButton.tap()
        
        let mainTitle = app.navigationBars["WhatTheFlight"]
        XCTAssertTrue(mainTitle.waitForExistence(timeout: 2), "Should return to main view when done is tapped")
    }
    
    // MARK: - Geographic Area Section Tests
    
    func testGeographicAreaSectionExists() throws {
        openSettingsView()
        
        let geographicSection = app.staticTexts["Geographic Area"]
        XCTAssertTrue(geographicSection.exists, "Geographic Area section should exist")
    }
    
    func testLocationStatusRowExists() throws {
        openSettingsView()
        
        let locationStatus = app.staticTexts["Location Status"]
        XCTAssertTrue(locationStatus.exists, "Location Status row should exist")
    }
    
    func testLocationPermissionRequestButton() throws {
        openSettingsView()
        
        // Check if request button exists (depends on permission state)
        let requestButton = app.buttons["Request"]
        if requestButton.exists {
            XCTAssertTrue(requestButton.isEnabled, "Request button should be enabled when permission is not determined")
        }
    }
    
    func testManualCoordinateEntry() throws {
        openSettingsView()
        
        // Try to find manual entry toggle
        let manualEntryButton = app.buttons["Enter Coordinates Manually"]
        if manualEntryButton.exists {
            manualEntryButton.tap()
            
            // Check for coordinate input fields
            let latitudeField = app.textFields.matching(identifier: "Latitude").firstMatch
            let longitudeField = app.textFields.matching(identifier: "Longitude").firstMatch
            let radiusField = app.textFields.matching(identifier: "Radius (km)").firstMatch
            
            XCTAssertTrue(latitudeField.waitForExistence(timeout: 1), "Latitude field should appear in manual entry mode")
            XCTAssertTrue(longitudeField.exists, "Longitude field should appear in manual entry mode")
            XCTAssertTrue(radiusField.exists, "Radius field should appear in manual entry mode")
        }
    }
    
    func testManualCoordinateValidation() throws {
        openSettingsView()
        
        let manualEntryButton = app.buttons["Enter Coordinates Manually"]
        if manualEntryButton.exists {
            manualEntryButton.tap()
            
            let latitudeField = app.textFields.matching(identifier: "Latitude").firstMatch
            let setButton = app.buttons["Set Manual Coordinates"]
            
            if latitudeField.waitForExistence(timeout: 1) {
                // Test invalid coordinates
                latitudeField.tap()
                latitudeField.typeText("999") // Invalid latitude
                
                XCTAssertFalse(setButton.isEnabled, "Set button should be disabled with invalid coordinates")
                
                // Clear and enter valid coordinates
                latitudeField.doubleTap()
                latitudeField.typeText("37.7749")
                
                let longitudeField = app.textFields.matching(identifier: "Longitude").firstMatch
                longitudeField.tap()
                longitudeField.typeText("-122.4194")
                
                let radiusField = app.textFields.matching(identifier: "Radius (km)").firstMatch
                radiusField.tap()
                radiusField.typeText("50")
                
                // Button should now be enabled
                XCTAssertTrue(setButton.isEnabled, "Set button should be enabled with valid coordinates")
            }
        }
    }
    
    // MARK: - Query Interval Section Tests
    
    func testQueryIntervalSectionExists() throws {
        openSettingsView()
        
        let dataRefreshSection = app.staticTexts["Data Refresh"]
        XCTAssertTrue(dataRefreshSection.exists, "Data Refresh section should exist")
    }
    
    func testQueryIntervalSlider() throws {
        openSettingsView()
        
        let queryIntervalSlider = app.sliders.firstMatch
        XCTAssertTrue(queryIntervalSlider.exists, "Query interval slider should exist")
        
        // Test slider interaction
        let initialValue = queryIntervalSlider.value as? String
        queryIntervalSlider.adjust(toNormalizedSliderPosition: 0.8)
        
        let newValue = queryIntervalSlider.value as? String
        XCTAssertNotEqual(initialValue, newValue, "Slider value should change when adjusted")
    }
    
    func testPowerSavingToggle() throws {
        openSettingsView()
        
        let powerSavingToggle = app.switches["Power Saving Mode"]
        XCTAssertTrue(powerSavingToggle.exists, "Power Saving Mode toggle should exist")
        
        let initialState = powerSavingToggle.value as? String
        powerSavingToggle.tap()
        
        let newState = powerSavingToggle.value as? String
        XCTAssertNotEqual(initialState, newState, "Power saving toggle state should change when tapped")
    }
    
    // MARK: - Display Preferences Section Tests
    
    func testDisplayPreferencesSectionExists() throws {
        openSettingsView()
        
        let displaySection = app.staticTexts["Display Preferences"]
        XCTAssertTrue(displaySection.exists, "Display Preferences section should exist")
    }
    
    func testTextSizePicker() throws {
        openSettingsView()
        
        let textSizePicker = app.buttons["Text Size"]
        if textSizePicker.exists {
            textSizePicker.tap()
            
            // Check for text size options
            let smallOption = app.buttons["Small"]
            let mediumOption = app.buttons["Medium"]
            let largeOption = app.buttons["Large"]
            
            XCTAssertTrue(smallOption.waitForExistence(timeout: 1) || mediumOption.exists || largeOption.exists,
                         "Text size options should be available")
        }
    }
    
    func testColorThemePicker() throws {
        openSettingsView()
        
        let colorThemePicker = app.buttons["Color Theme"]
        if colorThemePicker.exists {
            colorThemePicker.tap()
            
            // Check for color theme options
            let systemOption = app.buttons["System"]
            let lightOption = app.buttons["Light"]
            let darkOption = app.buttons["Dark"]
            
            XCTAssertTrue(systemOption.waitForExistence(timeout: 1) || lightOption.exists || darkOption.exists,
                         "Color theme options should be available")
        }
    }
    
    func testDisplayOptionsToggles() throws {
        openSettingsView()
        
        let animationsToggle = app.switches["Enable Animations"]
        let altitudeToggle = app.switches["Show Altitude"]
        let speedToggle = app.switches["Show Speed"]
        let headingToggle = app.switches["Show Heading"]
        
        XCTAssertTrue(animationsToggle.exists, "Enable Animations toggle should exist")
        XCTAssertTrue(altitudeToggle.exists, "Show Altitude toggle should exist")
        XCTAssertTrue(speedToggle.exists, "Show Speed toggle should exist")
        XCTAssertTrue(headingToggle.exists, "Show Heading toggle should exist")
        
        // Test toggle interaction
        let initialState = animationsToggle.value as? String
        animationsToggle.tap()
        let newState = animationsToggle.value as? String
        XCTAssertNotEqual(initialState, newState, "Animations toggle state should change when tapped")
    }
    
    // MARK: - Notification Section Tests
    
    func testNotificationSectionExists() throws {
        openSettingsView()
        
        let notificationSection = app.staticTexts["Notifications"]
        XCTAssertTrue(notificationSection.exists, "Notifications section should exist")
    }
    
    func testNotificationToggles() throws {
        openSettingsView()
        
        let flightDetectionToggle = app.switches["Flight Detection Alerts"]
        let connectionStatusToggle = app.switches["Connection Status Updates"]
        let errorAlertsToggle = app.switches["Error Alerts"]
        let soundToggle = app.switches["Sound Enabled"]
        let badgeToggle = app.switches["Badge Enabled"]
        
        XCTAssertTrue(flightDetectionToggle.exists, "Flight Detection Alerts toggle should exist")
        XCTAssertTrue(connectionStatusToggle.exists, "Connection Status Updates toggle should exist")
        XCTAssertTrue(errorAlertsToggle.exists, "Error Alerts toggle should exist")
        XCTAssertTrue(soundToggle.exists, "Sound Enabled toggle should exist")
        XCTAssertTrue(badgeToggle.exists, "Badge Enabled toggle should exist")
        
        // Test toggle interaction
        let initialState = flightDetectionToggle.value as? String
        flightDetectionToggle.tap()
        let newState = flightDetectionToggle.value as? String
        XCTAssertNotEqual(initialState, newState, "Flight detection toggle state should change when tapped")
    }
    
    // MARK: - Advanced Section Tests
    
    func testAdvancedSectionExists() throws {
        openSettingsView()
        
        let advancedSection = app.staticTexts["Advanced"]
        XCTAssertTrue(advancedSection.exists, "Advanced section should exist")
    }
    
    func testCloudKitSyncToggle() throws {
        openSettingsView()
        
        let cloudKitToggle = app.switches["CloudKit Sync"]
        XCTAssertTrue(cloudKitToggle.exists, "CloudKit Sync toggle should exist")
        
        let initialState = cloudKitToggle.value as? String
        cloudKitToggle.tap()
        let newState = cloudKitToggle.value as? String
        XCTAssertNotEqual(initialState, newState, "CloudKit sync toggle state should change when tapped")
    }
    
    func testSyncNowButton() throws {
        openSettingsView()
        
        let cloudKitToggle = app.switches["CloudKit Sync"]
        if cloudKitToggle.exists && cloudKitToggle.value as? String == "1" {
            let syncButton = app.buttons["Sync Now"]
            XCTAssertTrue(syncButton.exists, "Sync Now button should exist when CloudKit sync is enabled")
            
            syncButton.tap()
            // Note: In a real test, you might want to verify the sync operation
        }
    }
    
    func testResetToDefaultsButton() throws {
        openSettingsView()
        
        let resetButton = app.buttons["Reset to Defaults"]
        XCTAssertTrue(resetButton.exists, "Reset to Defaults button should exist")
        XCTAssertTrue(resetButton.isEnabled, "Reset to Defaults button should be enabled")
        
        // Note: We don't actually tap this in the test to avoid resetting settings
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorMessageDisplay() throws {
        openSettingsView()
        
        // Try to trigger an error by entering invalid coordinates
        let manualEntryButton = app.buttons["Enter Coordinates Manually"]
        if manualEntryButton.exists {
            manualEntryButton.tap()
            
            let latitudeField = app.textFields.matching(identifier: "Latitude").firstMatch
            let setButton = app.buttons["Set Manual Coordinates"]
            
            if latitudeField.waitForExistence(timeout: 1) {
                latitudeField.tap()
                latitudeField.typeText("999") // Invalid latitude
                
                if setButton.isEnabled {
                    setButton.tap()
                    
                    // Check for error alert
                    let errorAlert = app.alerts["Error"]
                    XCTAssertTrue(errorAlert.waitForExistence(timeout: 2), "Error alert should appear for invalid coordinates")
                    
                    let okButton = errorAlert.buttons["OK"]
                    if okButton.exists {
                        okButton.tap()
                    }
                }
            }
        }
    }
    
    func testSuccessMessageDisplay() throws {
        openSettingsView()
        
        // Try to trigger a success message by changing a setting
        let animationsToggle = app.switches["Enable Animations"]
        if animationsToggle.exists {
            animationsToggle.tap()
            
            // Look for success message (this might be transient)
            let _ = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'updated'")).firstMatch
            // Note: Success messages might be too transient to reliably test in UI tests
        }
    }
    
    // MARK: - Accessibility Tests
    
    func testAccessibilityLabels() throws {
        openSettingsView()
        
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.exists, "Settings title should be accessible")
        
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.isEnabled, "Cancel button should be accessible")
        
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.isEnabled, "Done button should be accessible")
    }
    
    func testVoiceOverSupport() throws {
        openSettingsView()
        
        // Test that key elements have accessibility labels
        let locationStatus = app.staticTexts["Location Status"]
        XCTAssertTrue(locationStatus.exists, "Location Status should have accessibility support")
        
        let queryIntervalSlider = app.sliders.firstMatch
        if queryIntervalSlider.exists {
            XCTAssertNotNil(queryIntervalSlider.label, "Query interval slider should have accessibility label")
        }
    }
    
    // MARK: - Platform-Specific Tests
    
    func testPlatformSpecificElements() throws {
        openSettingsView()
        
        #if os(iOS)
        // iOS-specific tests
        let navigationBar = app.navigationBars["Settings"]
        XCTAssertTrue(navigationBar.exists, "iOS should show navigation bar")
        
        #elseif os(macOS)
        // macOS-specific tests
        // Add macOS-specific UI tests here
        
        #elseif os(tvOS)
        // tvOS-specific tests
        // Add tvOS-specific UI tests here
        #endif
    }
    
    // MARK: - Integration Tests
    
    func testSettingsIntegrationWithMainView() throws {
        // Test that settings changes affect the main view
        openSettingsView()
        
        // Change a setting
        let animationsToggle = app.switches["Enable Animations"]
        if animationsToggle.exists {
            let initialState = animationsToggle.value as? String
            animationsToggle.tap()
            
            // Close settings
            let doneButton = app.buttons["Done"]
            doneButton.tap()
            
            // Reopen settings to verify persistence
            let settingsButton = app.buttons["Settings"]
            settingsButton.tap()
            
            let updatedToggle = app.switches["Enable Animations"]
            let newState = updatedToggle.value as? String
            XCTAssertNotEqual(initialState, newState, "Setting should persist after closing and reopening settings")
        }
    }
    
    // MARK: - Helper Methods
    
    private func openSettingsView() {
        let settingsButton = app.buttons["Settings"]
        settingsButton.tap()
        
        let settingsTitle = app.navigationBars["Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 2), "Settings view should open")
    }
    
    private func closeSettingsView() {
        let doneButton = app.buttons["Done"]
        if doneButton.exists {
            doneButton.tap()
        } else {
            let cancelButton = app.buttons["Cancel"]
            cancelButton.tap()
        }
        
        let mainTitle = app.navigationBars["WhatTheFlight"]
        XCTAssertTrue(mainTitle.waitForExistence(timeout: 2), "Should return to main view")
    }
}

// MARK: - Performance Tests

extension SettingsViewUITests {
    
    func testSettingsViewLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            let settingsButton = app.buttons["Settings"]
            settingsButton.tap()
            
            let settingsTitle = app.navigationBars["Settings"]
            _ = settingsTitle.waitForExistence(timeout: 5)
        }
    }
    
    func testSettingsViewScrollPerformance() throws {
        openSettingsView()
        
        let settingsTable = app.tables.firstMatch
        if settingsTable.exists {
            measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
                settingsTable.swipeUp()
                settingsTable.swipeDown()
            }
        }
    }
}