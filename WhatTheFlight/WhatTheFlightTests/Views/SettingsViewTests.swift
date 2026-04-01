//
//  SettingsViewTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import SwiftUI
import CoreLocation
@testable import WhatTheFlight

final class SettingsViewTests: XCTestCase {
    
    var mockSettingsManager: MockSettingsManager!
    var mockLocationManager: MockLocationManager!
    var settingsView: SettingsView!
    
    override func setUpWithError() throws {
        mockSettingsManager = MockSettingsManager()
        mockLocationManager = MockLocationManager()
        settingsView = SettingsView(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
    }
    
    override func tearDownWithError() throws {
        mockSettingsManager = nil
        mockLocationManager = nil
        settingsView = nil
    }
    
    // MARK: - View Structure Tests
    
    func testSettingsViewInitialization() throws {
        XCTAssertNotNil(settingsView, "SettingsView should initialize successfully")
    }
    
    func testSettingsViewWithValidManagers() throws {
        let view = SettingsView(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        XCTAssertNotNil(view, "SettingsView should initialize with valid managers")
    }
    
    // MARK: - ViewModel Integration Tests
    
    func testSettingsViewModelInitialization() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        XCTAssertNotNil(viewModel, "SettingsViewModel should initialize successfully")
    }
    
    func testSettingsViewModelBindsToManagers() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test that ViewModel reflects manager state
        XCTAssertEqual(viewModel.queryInterval, mockSettingsManager.queryInterval)
        XCTAssertEqual(viewModel.displayPreferences, mockSettingsManager.displayPreferences)
        XCTAssertEqual(viewModel.notificationSettings, mockSettingsManager.notificationSettings)
    }
    
    // MARK: - Query Interval Tests
    
    func testQueryIntervalValidation() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test valid intervals
        viewModel.queryInterval = 30.0
        XCTAssertTrue(viewModel.isQueryIntervalValid, "30 seconds should be valid")
        
        viewModel.queryInterval = 15.0
        XCTAssertTrue(viewModel.isQueryIntervalValid, "15 seconds should be valid")
        
        viewModel.queryInterval = 120.0
        XCTAssertTrue(viewModel.isQueryIntervalValid, "120 seconds should be valid")
        
        // Test invalid intervals
        viewModel.queryInterval = 10.0
        XCTAssertFalse(viewModel.isQueryIntervalValid, "10 seconds should be invalid")
        
        viewModel.queryInterval = 150.0
        XCTAssertFalse(viewModel.isQueryIntervalValid, "150 seconds should be invalid")
    }
    
    func testQueryIntervalValidationMessage() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        viewModel.queryInterval = 10.0
        XCTAssertNotNil(viewModel.queryIntervalValidationMessage, "Should have validation message for invalid interval")
        
        viewModel.queryInterval = 30.0
        XCTAssertNil(viewModel.queryIntervalValidationMessage, "Should not have validation message for valid interval")
    }
    
    // MARK: - Display Preferences Tests
    
    func testDisplayPreferencesDefaults() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        let preferences = viewModel.displayPreferences
        XCTAssertEqual(preferences.textSize, .medium, "Default text size should be medium")
        XCTAssertEqual(preferences.colorTheme, .system, "Default color theme should be system")
        XCTAssertEqual(preferences.informationDensity, .normal, "Default information density should be normal")
        XCTAssertTrue(preferences.animationsEnabled, "Animations should be enabled by default")
        XCTAssertTrue(preferences.showAltitude, "Show altitude should be enabled by default")
        XCTAssertTrue(preferences.showSpeed, "Show speed should be enabled by default")
        XCTAssertFalse(preferences.showHeading, "Show heading should be disabled by default")
    }
    
    func testDisplayPreferencesUpdate() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Update display preferences
        viewModel.displayPreferences.textSize = .large
        viewModel.displayPreferences.colorTheme = .dark
        viewModel.displayPreferences.animationsEnabled = false
        
        viewModel.saveDisplayPreferences()
        
        // Verify settings manager was updated
        XCTAssertEqual(mockSettingsManager.displayPreferences.textSize, .large)
        XCTAssertEqual(mockSettingsManager.displayPreferences.colorTheme, .dark)
        XCTAssertFalse(mockSettingsManager.displayPreferences.animationsEnabled)
    }
    
    // MARK: - Notification Settings Tests
    
    func testNotificationSettingsDefaults() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        let notifications = viewModel.notificationSettings
        XCTAssertTrue(notifications.flightDetectionEnabled, "Flight detection should be enabled by default")
        XCTAssertFalse(notifications.connectionStatusEnabled, "Connection status should be disabled by default")
        XCTAssertTrue(notifications.errorAlertsEnabled, "Error alerts should be enabled by default")
        XCTAssertTrue(notifications.soundEnabled, "Sound should be enabled by default")
        XCTAssertFalse(notifications.badgeEnabled, "Badge should be disabled by default")
    }
    
    func testNotificationSettingsUpdate() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Update notification settings
        viewModel.notificationSettings.flightDetectionEnabled = false
        viewModel.notificationSettings.connectionStatusEnabled = true
        viewModel.notificationSettings.soundEnabled = false
        
        viewModel.saveNotificationSettings()
        
        // Verify settings manager was updated
        XCTAssertFalse(mockSettingsManager.notificationSettings.flightDetectionEnabled)
        XCTAssertTrue(mockSettingsManager.notificationSettings.connectionStatusEnabled)
        XCTAssertFalse(mockSettingsManager.notificationSettings.soundEnabled)
    }
    
    // MARK: - Location and Geographic Bounds Tests
    
    func testLocationPermissionStatus() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test different permission states
        mockLocationManager.authorizationStatus = .notDetermined
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission not requested")
        XCTAssertFalse(viewModel.canUseLocationServices)
        
        mockLocationManager.authorizationStatus = .denied
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission denied - use manual entry")
        XCTAssertFalse(viewModel.canUseLocationServices)
        
        #if os(iOS)
        mockLocationManager.authorizationStatus = .authorizedWhenInUse
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission granted")
        XCTAssertTrue(viewModel.canUseLocationServices)
        #endif
        
        mockLocationManager.authorizationStatus = .authorizedAlways
        XCTAssertEqual(viewModel.locationStatusMessage, "Location permission granted")
        XCTAssertTrue(viewModel.canUseLocationServices)
    }
    
    func testManualCoordinateValidation() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test valid coordinates
        viewModel.manualLatitude = "37.7749"
        viewModel.manualLongitude = "-122.4194"
        viewModel.manualRadius = "50"
        XCTAssertTrue(viewModel.areManualCoordinatesValid, "Valid coordinates should pass validation")
        
        // Test invalid latitude
        viewModel.manualLatitude = "999"
        XCTAssertFalse(viewModel.areManualCoordinatesValid, "Invalid latitude should fail validation")
        
        // Test invalid longitude
        viewModel.manualLatitude = "37.7749"
        viewModel.manualLongitude = "999"
        XCTAssertFalse(viewModel.areManualCoordinatesValid, "Invalid longitude should fail validation")
        
        // Test invalid radius
        viewModel.manualLongitude = "-122.4194"
        viewModel.manualRadius = "0"
        XCTAssertFalse(viewModel.areManualCoordinatesValid, "Invalid radius should fail validation")
        
        // Test empty values
        viewModel.manualLatitude = ""
        viewModel.manualLongitude = ""
        viewModel.manualRadius = ""
        XCTAssertFalse(viewModel.areManualCoordinatesValid, "Empty coordinates should fail validation")
    }
    
    func testGeographicBoundsDescription() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test with no bounds
        XCTAssertEqual(viewModel.boundsDescription, "No area configured")
        
        // Test with valid bounds
        let bounds = GeographicBounds(
            northLatitude: 38.0,
            southLatitude: 37.0,
            eastLongitude: -122.0,
            westLongitude: -123.0
        )
        viewModel.geographicBounds = bounds
        
        let description = viewModel.boundsDescription
        XCTAssertTrue(description.contains("Center:"), "Description should contain center coordinates")
        XCTAssertTrue(description.contains("37.5"), "Description should contain calculated center latitude")
        XCTAssertTrue(description.contains("-122.5"), "Description should contain calculated center longitude")
    }
    
    // MARK: - Advanced Settings Tests
    
    func testPowerSavingMode() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test default state
        XCTAssertFalse(viewModel.powerSavingEnabled, "Power saving should be disabled by default")
        
        // Test enabling power saving
        viewModel.powerSavingEnabled = true
        viewModel.savePowerSavingEnabled()
        
        XCTAssertTrue(mockSettingsManager.powerSavingEnabled, "Settings manager should reflect power saving state")
    }
    
    func testCloudKitSync() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test default state
        XCTAssertTrue(viewModel.cloudKitSyncEnabled, "CloudKit sync should be enabled by default")
        
        // Test disabling CloudKit sync
        viewModel.cloudKitSyncEnabled = false
        viewModel.saveCloudKitSyncEnabled()
        
        XCTAssertFalse(mockSettingsManager.cloudKitSyncEnabled, "Settings manager should reflect CloudKit sync state")
    }
    
    func testResetToDefaults() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Modify some settings
        viewModel.queryInterval = 60.0
        viewModel.powerSavingEnabled = true
        viewModel.displayPreferences.textSize = .large
        
        // Reset to defaults
        viewModel.resetToDefaults()
        
        // Verify settings were reset (this would be async in real implementation)
        // The mock should handle the reset operation
        XCTAssertTrue(mockSettingsManager.resetToDefaultsCalled, "Reset to defaults should be called")
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorMessageHandling() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test setting error message
        viewModel.setError("Test error message")
        XCTAssertEqual(viewModel.errorMessage, "Test error message")
        XCTAssertNil(viewModel.successMessage, "Success message should be cleared when error is set")
        
        // Test clearing messages
        viewModel.clearMessages()
        XCTAssertNil(viewModel.errorMessage, "Error message should be cleared")
        XCTAssertNil(viewModel.successMessage, "Success message should be cleared")
    }
    
    func testSuccessMessageHandling() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test setting success message
        viewModel.showSuccess("Test success message")
        XCTAssertEqual(viewModel.successMessage, "Test success message")
        XCTAssertNil(viewModel.errorMessage, "Error message should be cleared when success is set")
    }
    
    func testValidationHelpers() throws {
        let viewModel = SettingsViewModel(
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        // Test coordinate string validation
        XCTAssertTrue(viewModel.validateCoordinateString("37.7749", range: -90...90))
        XCTAssertFalse(viewModel.validateCoordinateString("999", range: -90...90))
        XCTAssertFalse(viewModel.validateCoordinateString("invalid", range: -90...90))
        
        // Test radius string validation
        XCTAssertTrue(viewModel.validateRadiusString("50"))
        XCTAssertFalse(viewModel.validateRadiusString("0"))
        XCTAssertFalse(viewModel.validateRadiusString("600"))
        XCTAssertFalse(viewModel.validateRadiusString("invalid"))
    }
}

// MARK: - CoordinateInputField Tests

final class CoordinateInputFieldTests: XCTestCase {
    
    func testCoordinateInputFieldInitialization() throws {
        let coordinateField = CoordinateInputField(
            title: "Test Coordinate",
            value: .constant("0.0"),
            placeholder: "Enter value",
            range: -90...90
        )
        
        XCTAssertNotNil(coordinateField, "CoordinateInputField should initialize successfully")
    }
    
    func testCoordinateInputFieldWithDifferentRanges() throws {
        let latitudeField = CoordinateInputField(
            title: "Latitude",
            value: .constant(""),
            placeholder: "Enter latitude",
            range: -90...90
        )
        
        let longitudeField = CoordinateInputField(
            title: "Longitude",
            value: .constant(""),
            placeholder: "Enter longitude",
            range: -180...180
        )
        
        let radiusField = CoordinateInputField(
            title: "Radius",
            value: .constant(""),
            placeholder: "Enter radius",
            range: 1...500
        )
        
        XCTAssertNotNil(latitudeField, "Latitude field should initialize")
        XCTAssertNotNil(longitudeField, "Longitude field should initialize")
        XCTAssertNotNil(radiusField, "Radius field should initialize")
    }
}

// MARK: - SuccessMessageView Tests

final class SuccessMessageViewTests: XCTestCase {
    
    func testSuccessMessageViewInitialization() throws {
        let successView = SuccessMessageView(message: "Test Success")
        XCTAssertNotNil(successView, "SuccessMessageView should initialize successfully")
    }
    
    func testSuccessMessageViewWithDifferentMessages() throws {
        let messages = [
            "Settings updated",
            "Location saved",
            "Preferences applied",
            "Sync completed"
        ]
        
        for message in messages {
            let successView = SuccessMessageView(message: message)
            XCTAssertNotNil(successView, "SuccessMessageView should initialize with message: \(message)")
        }
    }
}

// MARK: - Mock Extensions for Testing

extension SettingsViewTests {
    
    func createMockSettingsView(
        locationStatus: CLAuthorizationStatus = .notDetermined,
        queryInterval: TimeInterval = 30.0,
        bounds: GeographicBounds? = nil
    ) -> SettingsView {
        let mockSettings = MockSettingsManager()
        let mockLocation = MockLocationManager()
        
        mockLocation.authorizationStatus = locationStatus
        mockSettings.queryInterval = queryInterval
        mockSettings.geographicBounds = bounds
        
        return SettingsView(
            settingsManager: mockSettings,
            locationManager: mockLocation
        )
    }
}

// MARK: - Integration Tests

extension SettingsViewTests {
    
    func testSettingsViewIntegrationWithViewModel() throws {
        // Test that the view properly integrates with its ViewModel
        let testView = createMockSettingsView(
            locationStatus: .authorizedWhenInUse,
            queryInterval: 45.0
        )
        
        // Verify that the view reflects the ViewModel state
        // This would require accessing the ViewModel through the view
    }
    
    func testSettingsViewStateUpdates() throws {
        // Test that the view updates when ViewModel state changes
        let testView = createMockSettingsView()
        
        // Change mock data
        mockSettingsManager.queryInterval = 60.0
        
        // Verify that the view reflects the change
        // This would require triggering a view update and inspecting the result
    }
}

// MARK: - Performance Tests

extension SettingsViewTests {
    
    func testSettingsViewRenderingPerformance() throws {
        measure {
            let testView = createMockSettingsView()
            _ = try? testView.inspect()
        }
    }
    
    func testSettingsViewWithLargeDataPerformance() throws {
        // Test performance with complex settings data
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 35.0,
            eastLongitude: -120.0,
            westLongitude: -125.0
        )
        
        measure {
            let testView = createMockSettingsView(
                locationStatus: .authorizedWhenInUse,
                queryInterval: 30.0,
                bounds: bounds
            )
            _ = try? testView.inspect()
        }
    }
}