//
//  SettingsViewModelTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import Combine
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class SettingsViewModelTests: XCTestCase {
    
    var viewModel: SettingsViewModel!
    var mockSettingsManager: MockSettingsManager!
    var mockLocationManager: MockLocationManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        
        mockSettingsManager = MockSettingsManager()
        mockLocationManager = MockLocationManager()
        cancellables = Set<AnyCancellable>()
        
        viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
    }
    
    override func tearDown() {
        cancellables = nil
        viewModel = nil
        mockLocationManager = nil
        mockSettingsManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertEqual(viewModel.queryInterval, 30.0)
        XCTAssertNil(viewModel.geographicBounds)
        XCTAssertEqual(viewModel.displayPreferences, .default)
        XCTAssertEqual(viewModel.notificationSettings, .default)
        XCTAssertFalse(viewModel.powerSavingEnabled)
        XCTAssertTrue(viewModel.cloudKitSyncEnabled)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.successMessage)
        XCTAssertFalse(viewModel.isSyncing)
    }
    
    func testInitializationWithExistingSettings() {
        mockSettingsManager.queryInterval = 60.0
        mockSettingsManager.powerSavingEnabled = true
        mockSettingsManager.cloudKitSyncEnabled = false
        
        let newViewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        XCTAssertEqual(newViewModel.queryInterval, 60.0)
        XCTAssertTrue(newViewModel.powerSavingEnabled)
        XCTAssertFalse(newViewModel.cloudKitSyncEnabled)
    }
    
    // MARK: - Computed Properties Tests
    
    func testIsQueryIntervalValid() {
        viewModel.queryInterval = 30.0
        XCTAssertTrue(viewModel.isQueryIntervalValid)
        
        viewModel.queryInterval = 10.0 // Too low
        XCTAssertFalse(viewModel.isQueryIntervalValid)
        
        viewModel.queryInterval = 150.0 // Too high
        XCTAssertFalse(viewModel.isQueryIntervalValid)
        
        viewModel.queryInterval = 15.0 // Minimum valid
        XCTAssertTrue(viewModel.isQueryIntervalValid)
        
        viewModel.queryInterval = 120.0 // Maximum valid
        XCTAssertTrue(viewModel.isQueryIntervalValid)
    }
    
    func testQueryIntervalValidationMessage() {
        viewModel.queryInterval = 30.0
        XCTAssertNil(viewModel.queryIntervalValidationMessage)
        
        viewModel.queryInterval = 10.0
        XCTAssertEqual(viewModel.queryIntervalValidationMessage, "Query interval must be between 15-120 seconds")
    }
    
    func testAreManualCoordinatesValid() {
        // Valid coordinates
        viewModel.manualLatitude = "40.7128"
        viewModel.manualLongitude = "-74.0060"
        viewModel.manualRadius = "50"
        XCTAssertTrue(viewModel.areManualCoordinatesValid)
        
        // Invalid latitude (too high)
        viewModel.manualLatitude = "95.0"
        XCTAssertFalse(viewModel.areManualCoordinatesValid)
        
        // Invalid longitude (too low)
        viewModel.manualLatitude = "40.7128"
        viewModel.manualLongitude = "-185.0"
        XCTAssertFalse(viewModel.areManualCoordinatesValid)
        
        // Invalid radius (too high)
        viewModel.manualLongitude = "-74.0060"
        viewModel.manualRadius = "600"
        XCTAssertFalse(viewModel.areManualCoordinatesValid)
        
        // Non-numeric input
        viewModel.manualRadius = "50"
        viewModel.manualLatitude = "invalid"
        XCTAssertFalse(viewModel.areManualCoordinatesValid)
    }
    
    func testManualCoordinatesValidationMessage() {
        viewModel.isManualEntryMode = true
        viewModel.manualLatitude = "invalid"
        viewModel.manualLongitude = "-74.0060"
        viewModel.manualRadius = "50"
        
        XCTAssertEqual(viewModel.manualCoordinatesValidationMessage, 
                      "Enter valid coordinates (lat: ±90°, lon: ±180°, radius: 1-500km)")
        
        viewModel.isManualEntryMode = false
        XCTAssertNil(viewModel.manualCoordinatesValidationMessage)
    }
    
    func testCanUseLocationServices() {
        mockLocationManager.authorizationStatus = .notDetermined
        XCTAssertFalse(viewModel.canUseLocationServices)
        
        mockLocationManager.authorizationStatus = .denied
        XCTAssertFalse(viewModel.canUseLocationServices)
        
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        XCTAssertTrue(viewModel.canUseLocationServices)
        
        mockLocationManager.authorizationStatus = .authorizedAlways
        XCTAssertTrue(viewModel.canUseLocationServices)
    }
    
    func testLocationStatusMessage() {
        mockLocationManager.authorizationStatus = .notDetermined
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission not requested")
        
        mockLocationManager.authorizationStatus = .denied
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission denied - use manual entry")
        
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission granted")
    }
    
    func testBoundsDescription() {
        XCTAssertEqual(viewModel.boundsDescription, "No area configured")
        
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.geographicBounds = bounds
        
        XCTAssertTrue(viewModel.boundsDescription.contains("Center:"))
        XCTAssertTrue(viewModel.boundsDescription.contains("39.500"))
        XCTAssertTrue(viewModel.boundsDescription.contains("-73.500"))
    }
    
    // MARK: - Save Methods Tests
    
    func testSaveQueryInterval() {
        viewModel.queryInterval = 45.0
        viewModel.saveQueryInterval()
        
        XCTAssertEqual(mockSettingsManager.queryInterval, 45.0)
        XCTAssertEqual(viewModel.successMessage, "Query interval updated")
    }
    
    func testSaveQueryIntervalWithInvalidValue() {
        viewModel.queryInterval = 10.0 // Invalid
        viewModel.saveQueryInterval()
        
        XCTAssertNotEqual(mockSettingsManager.queryInterval, 10.0)
        XCTAssertEqual(viewModel.errorMessage, "Invalid query interval")
    }
    
    func testSaveDisplayPreferences() {
        var preferences = DisplayPreferences.default
        preferences.textSize = .large
        viewModel.displayPreferences = preferences
        
        viewModel.saveDisplayPreferences()
        
        XCTAssertEqual(mockSettingsManager.displayPreferences.textSize, .large)
        XCTAssertEqual(viewModel.successMessage, "Display preferences updated")
    }
    
    func testSaveNotificationSettings() {
        var settings = NotificationSettings.default
        settings.flightDetectionEnabled = false
        viewModel.notificationSettings = settings
        
        viewModel.saveNotificationSettings()
        
        XCTAssertFalse(mockSettingsManager.notificationSettings.flightDetectionEnabled)
        XCTAssertEqual(viewModel.successMessage, "Notification settings updated")
    }
    
    func testSavePowerSavingEnabled() {
        viewModel.powerSavingEnabled = true
        viewModel.savePowerSavingEnabled()
        
        XCTAssertTrue(mockSettingsManager.powerSavingEnabled)
        XCTAssertEqual(viewModel.successMessage, "Power saving setting updated")
    }
    
    func testSaveCloudKitSyncEnabled() {
        viewModel.cloudKitSyncEnabled = false
        viewModel.saveCloudKitSyncEnabled()
        
        XCTAssertFalse(mockSettingsManager.cloudKitSyncEnabled)
        XCTAssertEqual(viewModel.successMessage, "CloudKit sync setting updated")
    }
    
    // MARK: - Location Methods Tests
    
    func testRequestLocationPermission() {
        viewModel.requestLocationPermission()
        
        XCTAssertTrue(mockLocationManager.requestLocationPermissionCalled)
    }
    
    func testUseCurrentLocation() async {
        let testLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        mockLocationManager.mockLocation = testLocation
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        
        let expectation = XCTestExpectation(description: "Location updated")
        
        viewModel.useCurrentLocation()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(self.viewModel.geographicBounds)
            XCTAssertEqual(self.viewModel.successMessage, "Location updated successfully")
            XCTAssertFalse(self.viewModel.isLoading)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testUseCurrentLocationWithoutPermission() {
        mockLocationManager.authorizationStatus = .denied
        
        viewModel.useCurrentLocation()
        
        XCTAssertEqual(viewModel.errorMessage, "Location permission required")
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testUseCurrentLocationWithError() async {
        mockLocationManager.shouldThrowError = true
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        
        let expectation = XCTestExpectation(description: "Location error handled")
        
        viewModel.useCurrentLocation()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(self.viewModel.errorMessage)
            XCTAssertTrue(self.viewModel.errorMessage?.contains("Failed to get location") ?? false)
            XCTAssertFalse(self.viewModel.isLoading)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Manual Coordinates Tests
    
    func testSetManualCoordinates() {
        viewModel.manualLatitude = "40.7128"
        viewModel.manualLongitude = "-74.0060"
        viewModel.manualRadius = "50"
        
        viewModel.setManualCoordinates()
        
        XCTAssertNotNil(viewModel.geographicBounds)
        XCTAssertEqual(viewModel.successMessage, "Manual coordinates set successfully")
    }
    
    func testSetManualCoordinatesWithInvalidInput() {
        viewModel.manualLatitude = "invalid"
        viewModel.manualLongitude = "-74.0060"
        viewModel.manualRadius = "50"
        
        viewModel.setManualCoordinates()
        
        XCTAssertEqual(viewModel.errorMessage, "Invalid coordinates entered")
    }
    
    func testToggleLocationMode() {
        XCTAssertFalse(viewModel.isManualEntryMode)
        
        // Set some bounds first
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.geographicBounds = bounds
        
        viewModel.toggleLocationMode()
        
        XCTAssertTrue(viewModel.isManualEntryMode)
        XCTAssertFalse(viewModel.manualLatitude.isEmpty)
        XCTAssertFalse(viewModel.manualLongitude.isEmpty)
        XCTAssertFalse(viewModel.manualRadius.isEmpty)
        
        viewModel.toggleLocationMode()
        XCTAssertFalse(viewModel.isManualEntryMode)
    }
    
    // MARK: - Reset and Sync Tests
    
    func testResetToDefaults() async {
        viewModel.queryInterval = 60.0
        viewModel.powerSavingEnabled = true
        
        let expectation = XCTestExpectation(description: "Settings reset")
        
        viewModel.resetToDefaults()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockSettingsManager.resetToDefaultsCalled)
            XCTAssertEqual(self.viewModel.successMessage, "Settings reset to defaults")
            XCTAssertFalse(self.viewModel.isLoading)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testSyncWithCloudKit() async {
        viewModel.cloudKitSyncEnabled = true
        
        let expectation = XCTestExpectation(description: "CloudKit sync")
        
        viewModel.syncWithCloudKit()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockSettingsManager.syncWithCloudKitCalled)
            XCTAssertEqual(self.viewModel.successMessage, "Settings synced with CloudKit")
            XCTAssertFalse(self.viewModel.isSyncing)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testSyncWithCloudKitDisabled() {
        viewModel.cloudKitSyncEnabled = false
        
        viewModel.syncWithCloudKit()
        
        XCTAssertEqual(viewModel.errorMessage, "CloudKit sync is disabled")
        XCTAssertFalse(viewModel.isSyncing)
    }
    
    func testSyncWithCloudKitError() async {
        viewModel.cloudKitSyncEnabled = true
        mockSettingsManager.shouldThrowSyncError = true
        
        let expectation = XCTestExpectation(description: "CloudKit sync error")
        
        viewModel.syncWithCloudKit()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(self.viewModel.errorMessage)
            XCTAssertTrue(self.viewModel.errorMessage?.contains("CloudKit sync failed") ?? false)
            XCTAssertFalse(self.viewModel.isSyncing)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Message Handling Tests
    
    func testSetError() {
        viewModel.setError("Test error")
        
        XCTAssertEqual(viewModel.errorMessage, "Test error")
        XCTAssertNil(viewModel.successMessage)
    }
    
    func testShowSuccess() {
        viewModel.showSuccess("Test success")
        
        XCTAssertEqual(viewModel.successMessage, "Test success")
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testClearMessages() {
        viewModel.setError("Test error")
        viewModel.clearMessages()
        
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.successMessage)
    }
    
    // MARK: - Validation Tests
    
    func testValidateQueryInterval() {
        XCTAssertTrue(viewModel.validateQueryInterval(30.0))
        XCTAssertTrue(viewModel.validateQueryInterval(15.0))
        XCTAssertTrue(viewModel.validateQueryInterval(120.0))
        XCTAssertFalse(viewModel.validateQueryInterval(10.0))
        XCTAssertFalse(viewModel.validateQueryInterval(150.0))
    }
    
    func testValidateGeographicBounds() {
        let validBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        XCTAssertTrue(viewModel.validateGeographicBounds(validBounds))
        
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0, // Invalid: north < south
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        XCTAssertFalse(viewModel.validateGeographicBounds(invalidBounds))
        
        XCTAssertFalse(viewModel.validateGeographicBounds(nil))
    }
    
    func testValidateCoordinateString() {
        XCTAssertTrue(viewModel.validateCoordinateString("40.7128", range: -90...90))
        XCTAssertTrue(viewModel.validateCoordinateString("-74.0060", range: -180...180))
        XCTAssertFalse(viewModel.validateCoordinateString("95.0", range: -90...90))
        XCTAssertFalse(viewModel.validateCoordinateString("invalid", range: -90...90))
    }
    
    func testValidateRadiusString() {
        XCTAssertTrue(viewModel.validateRadiusString("50"))
        XCTAssertTrue(viewModel.validateRadiusString("1"))
        XCTAssertTrue(viewModel.validateRadiusString("500"))
        XCTAssertFalse(viewModel.validateRadiusString("0"))
        XCTAssertFalse(viewModel.validateRadiusString("600"))
        XCTAssertFalse(viewModel.validateRadiusString("invalid"))
    }
    
    // MARK: - Data Transformation Tests
    
    func testDisplayPreferencesForUI() {
        var preferences = DisplayPreferences.default
        preferences.textSize = .large
        preferences.colorTheme = .dark
        preferences.informationDensity = .comfortable
        viewModel.displayPreferences = preferences
        
        let uiPreferences = viewModel.displayPreferencesForUI()
        
        XCTAssertEqual(uiPreferences.textSizeIndex, 2) // .large is index 2
        XCTAssertEqual(uiPreferences.colorThemeIndex, 2) // .dark is index 2
        XCTAssertEqual(uiPreferences.densityIndex, 2) // .comfortable is index 2
    }
    
    func testUpdateDisplayPreferencesFromUI() {
        let uiPreferences = DisplayPreferencesUI(
            textSizeIndex: 2, // .large
            colorThemeIndex: 2, // .dark
            densityIndex: 2, // .comfortable
            animationsEnabled: false,
            showAltitude: false,
            showSpeed: false,
            showHeading: true
        )
        
        viewModel.updateDisplayPreferencesFromUI(uiPreferences)
        
        XCTAssertEqual(viewModel.displayPreferences.textSize, .large)
        XCTAssertEqual(viewModel.displayPreferences.colorTheme, .dark)
        XCTAssertEqual(viewModel.displayPreferences.informationDensity, .comfortable)
        XCTAssertFalse(viewModel.displayPreferences.animationsEnabled)
        XCTAssertTrue(viewModel.displayPreferences.showHeading)
    }
    
    // MARK: - Batch Settings Tests
    
    func testApplySettingsBatch() {
        let validBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        let batch = SettingsChangeBatch(
            queryInterval: 45.0,
            geographicBounds: validBounds,
            displayPreferences: nil,
            notificationSettings: nil,
            powerSavingEnabled: true,
            cloudKitSyncEnabled: false
        )
        
        let errors = viewModel.applySettingsBatch(batch)
        
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(viewModel.queryInterval, 45.0)
        XCTAssertEqual(viewModel.geographicBounds, validBounds)
        XCTAssertTrue(viewModel.powerSavingEnabled)
        XCTAssertFalse(viewModel.cloudKitSyncEnabled)
    }
    
    func testApplySettingsBatchWithErrors() {
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0, // Invalid: north < south
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        let batch = SettingsChangeBatch(
            queryInterval: 10.0, // Invalid: too low
            geographicBounds: invalidBounds,
            displayPreferences: nil,
            notificationSettings: nil,
            powerSavingEnabled: nil,
            cloudKitSyncEnabled: nil
        )
        
        let errors = viewModel.applySettingsBatch(batch)
        
        XCTAssertEqual(errors.count, 2)
        XCTAssertTrue(errors.contains("Invalid query interval: must be between 15-120 seconds"))
        XCTAssertTrue(errors.contains("Invalid geographic bounds"))
    }
    
    func testNotificationSettingsTransformation() {
        var settings = NotificationSettings.default
        settings.flightDetectionEnabled = false
        settings.soundEnabled = false
        viewModel.notificationSettings = settings
        
        let uiSettings = viewModel.notificationSettingsForUI()
        
        XCTAssertFalse(uiSettings.flightDetectionEnabled)
        XCTAssertFalse(uiSettings.soundEnabled)
        XCTAssertTrue(uiSettings.errorAlertsEnabled) // Should remain default
        
        // Test reverse transformation
        var modifiedUI = uiSettings
        modifiedUI.connectionStatusEnabled = true
        
        viewModel.updateNotificationSettingsFromUI(modifiedUI)
        
        XCTAssertTrue(viewModel.notificationSettings.connectionStatusEnabled)
        XCTAssertFalse(viewModel.notificationSettings.flightDetectionEnabled)
    }
    
    // MARK: - Reactive Binding Tests
    
    func testSettingsManagerBindings() {
        let expectation = XCTestExpectation(description: "Settings manager bindings")
        
        // Update settings manager values
        mockSettingsManager.queryInterval = 45.0
        mockSettingsManager.powerSavingEnabled = true
        
        let testBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        mockSettingsManager.geographicBounds = testBounds
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.queryInterval, 45.0)
            XCTAssertTrue(self.viewModel.powerSavingEnabled)
            XCTAssertEqual(self.viewModel.geographicBounds, testBounds)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testLocationManagerBindings() {
        let expectation = XCTestExpectation(description: "Location manager bindings")
        
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.locationPermissionStatus, MockLocationManager.authorizedStatus)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}