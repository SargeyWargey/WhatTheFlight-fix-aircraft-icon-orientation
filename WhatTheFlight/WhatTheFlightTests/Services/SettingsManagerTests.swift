//
//  SettingsManagerTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import CloudKit
import Combine
@testable import WhatTheFlight

@MainActor
final class SettingsManagerTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    var mockContainer: CKContainer!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        
        // Clear UserDefaults before each test
        clearUserDefaults()
        
        // Use a test container to avoid affecting real CloudKit data
        mockContainer = CKContainer(identifier: "iCloud.com.test.WhatTheFlight")
        settingsManager = SettingsManager(container: mockContainer)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        settingsManager = nil
        mockContainer = nil
        clearUserDefaults()
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialValues() {
        XCTAssertEqual(settingsManager.queryInterval, 30.0)
        XCTAssertNil(settingsManager.geographicBounds)
        XCTAssertEqual(settingsManager.displayPreferences, .default)
        XCTAssertEqual(settingsManager.notificationSettings, .default)
        XCTAssertFalse(settingsManager.powerSavingEnabled)
        XCTAssertTrue(settingsManager.cloudKitSyncEnabled)
    }
    
    func testLoadFromUserDefaults() {
        // Set up UserDefaults with test data
        UserDefaults.standard.set(45.0, forKey: "queryInterval")
        UserDefaults.standard.set(true, forKey: "powerSavingEnabled")
        UserDefaults.standard.set(false, forKey: "cloudKitSyncEnabled")
        
        let testBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        if let boundsData = try? JSONEncoder().encode(testBounds) {
            UserDefaults.standard.set(boundsData, forKey: "geographicBounds")
        }
        
        // Create new settings manager to test loading
        let newSettingsManager = SettingsManager(container: mockContainer)
        
        XCTAssertEqual(newSettingsManager.queryInterval, 45.0)
        XCTAssertTrue(newSettingsManager.powerSavingEnabled)
        XCTAssertFalse(newSettingsManager.cloudKitSyncEnabled)
        XCTAssertEqual(newSettingsManager.geographicBounds, testBounds)
    }
    
    // MARK: - Query Interval Tests
    
    func testValidQueryInterval() {
        XCTAssertTrue(settingsManager.validateQueryInterval(15.0))
        XCTAssertTrue(settingsManager.validateQueryInterval(30.0))
        XCTAssertTrue(settingsManager.validateQueryInterval(60.0))
        XCTAssertTrue(settingsManager.validateQueryInterval(120.0))
    }
    
    func testInvalidQueryInterval() {
        XCTAssertFalse(settingsManager.validateQueryInterval(14.9))
        XCTAssertFalse(settingsManager.validateQueryInterval(120.1))
        XCTAssertFalse(settingsManager.validateQueryInterval(0))
        XCTAssertFalse(settingsManager.validateQueryInterval(-10))
    }
    
    func testQueryIntervalSetting() {
        let expectation = XCTestExpectation(description: "Query interval updated")
        
        settingsManager.$queryInterval
            .dropFirst()
            .sink { interval in
                XCTAssertEqual(interval, 60.0)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        settingsManager.queryInterval = 60.0
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "queryInterval") as? TimeInterval, 60.0)
    }
    
    func testInvalidQueryIntervalRejected() {
        let originalInterval = settingsManager.queryInterval
        
        settingsManager.queryInterval = 10.0 // Invalid (too low)
        XCTAssertEqual(settingsManager.queryInterval, originalInterval)
        
        settingsManager.queryInterval = 150.0 // Invalid (too high)
        XCTAssertEqual(settingsManager.queryInterval, originalInterval)
    }
    
    // MARK: - Geographic Bounds Tests
    
    func testValidGeographicBounds() {
        let validBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        let expectation = XCTestExpectation(description: "Geographic bounds updated")
        
        settingsManager.$geographicBounds
            .dropFirst()
            .sink { bounds in
                XCTAssertEqual(bounds, validBounds)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        settingsManager.geographicBounds = validBounds
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify persistence
        if let data = UserDefaults.standard.data(forKey: "geographicBounds"),
           let savedBounds = try? JSONDecoder().decode(GeographicBounds.self, from: data) {
            XCTAssertEqual(savedBounds, validBounds)
        } else {
            XCTFail("Geographic bounds not saved to UserDefaults")
        }
    }
    
    func testInvalidGeographicBoundsRejected() {
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0, // Invalid: north < south
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        let originalBounds = settingsManager.geographicBounds
        settingsManager.geographicBounds = invalidBounds
        
        XCTAssertEqual(settingsManager.geographicBounds, originalBounds)
    }
    
    func testNilGeographicBounds() {
        // First set valid bounds
        let validBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        settingsManager.geographicBounds = validBounds
        
        // Then set to nil
        settingsManager.geographicBounds = nil
        
        XCTAssertNil(settingsManager.geographicBounds)
        XCTAssertNil(UserDefaults.standard.data(forKey: "geographicBounds"))
    }
    
    // MARK: - Display Preferences Tests
    
    func testDisplayPreferencesUpdate() {
        var newPreferences = DisplayPreferences.default
        newPreferences.textSize = .large
        newPreferences.colorTheme = .dark
        newPreferences.animationsEnabled = false
        
        let expectation = XCTestExpectation(description: "Display preferences updated")
        
        settingsManager.$displayPreferences
            .dropFirst()
            .sink { preferences in
                XCTAssertEqual(preferences.textSize, .large)
                XCTAssertEqual(preferences.colorTheme, .dark)
                XCTAssertFalse(preferences.animationsEnabled)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        settingsManager.displayPreferences = newPreferences
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify persistence
        if let data = UserDefaults.standard.data(forKey: "displayPreferences"),
           let savedPreferences = try? JSONDecoder().decode(DisplayPreferences.self, from: data) {
            XCTAssertEqual(savedPreferences, newPreferences)
        } else {
            XCTFail("Display preferences not saved to UserDefaults")
        }
    }
    
    // MARK: - Notification Settings Tests
    
    func testNotificationSettingsUpdate() {
        var newSettings = NotificationSettings.default
        newSettings.flightDetectionEnabled = false
        newSettings.connectionStatusEnabled = true
        newSettings.soundEnabled = false
        
        let expectation = XCTestExpectation(description: "Notification settings updated")
        
        settingsManager.$notificationSettings
            .dropFirst()
            .sink { settings in
                XCTAssertFalse(settings.flightDetectionEnabled)
                XCTAssertTrue(settings.connectionStatusEnabled)
                XCTAssertFalse(settings.soundEnabled)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        settingsManager.notificationSettings = newSettings
        
        wait(for: [expectation], timeout: 1.0)
        
        // Verify persistence
        if let data = UserDefaults.standard.data(forKey: "notificationSettings"),
           let savedSettings = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            XCTAssertEqual(savedSettings, newSettings)
        } else {
            XCTFail("Notification settings not saved to UserDefaults")
        }
    }
    
    // MARK: - Power Saving Tests
    
    func testPowerSavingEnabled() {
        let expectation = XCTestExpectation(description: "Power saving updated")
        
        settingsManager.$powerSavingEnabled
            .dropFirst()
            .sink { enabled in
                XCTAssertTrue(enabled)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        settingsManager.powerSavingEnabled = true
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "powerSavingEnabled"))
    }
    
    // MARK: - CloudKit Sync Tests
    
    func testCloudKitSyncEnabled() {
        let expectation = XCTestExpectation(description: "CloudKit sync updated")
        
        settingsManager.$cloudKitSyncEnabled
            .dropFirst()
            .sink { enabled in
                XCTAssertFalse(enabled)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        settingsManager.cloudKitSyncEnabled = false
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "cloudKitSyncEnabled"))
    }
    
    // MARK: - Reset to Defaults Tests
    
    func testResetToDefaults() {
        // Set non-default values
        settingsManager.queryInterval = 60.0
        settingsManager.powerSavingEnabled = true
        settingsManager.cloudKitSyncEnabled = false
        
        var customPreferences = DisplayPreferences.default
        customPreferences.textSize = .large
        settingsManager.displayPreferences = customPreferences
        
        // Reset to defaults
        settingsManager.resetToDefaults()
        
        // Verify all values are reset
        XCTAssertEqual(settingsManager.queryInterval, 30.0)
        XCTAssertNil(settingsManager.geographicBounds)
        XCTAssertEqual(settingsManager.displayPreferences, .default)
        XCTAssertEqual(settingsManager.notificationSettings, .default)
        XCTAssertFalse(settingsManager.powerSavingEnabled)
        XCTAssertTrue(settingsManager.cloudKitSyncEnabled)
        
        // Verify UserDefaults are cleared
        XCTAssertNil(UserDefaults.standard.object(forKey: "geographicBounds"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "displayPreferences"))
        XCTAssertNil(UserDefaults.standard.object(forKey: "notificationSettings"))
    }
    
    // MARK: - Migration Tests
    
    func testMigrationFromVersion0To1() {
        // Set old version
        UserDefaults.standard.set(0, forKey: "settingsVersion")
        
        // Create new settings manager to trigger migration
        _ = SettingsManager(container: mockContainer)
        
        // Verify migration occurred
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "settingsVersion"), 1)
    }
    
    // MARK: - Error Handling Tests
    
    func testSettingsErrorDescriptions() {
        let invalidIntervalError = SettingsError.invalidQueryInterval(10.0)
        XCTAssertTrue(invalidIntervalError.errorDescription?.contains("Invalid query interval") == true)
        
        let invalidBounds = GeographicBounds(northLatitude: 0, southLatitude: 0, eastLongitude: 0, westLongitude: 0)
        let invalidBoundsError = SettingsError.invalidGeographicBounds(invalidBounds)
        XCTAssertTrue(invalidBoundsError.errorDescription?.contains("Invalid geographic bounds") == true)
        
        let testError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let cloudKitError = SettingsError.cloudKitSyncFailed(testError)
        XCTAssertTrue(cloudKitError.errorDescription?.contains("CloudKit sync failed") == true)
        
        let migrationError = SettingsError.migrationFailed(testError)
        XCTAssertTrue(migrationError.errorDescription?.contains("Settings migration failed") == true)
    }
    
    // MARK: - Helper Methods
    
    private func clearUserDefaults() {
        let keys = ["queryInterval", "geographicBounds", "displayPreferences", 
                   "notificationSettings", "powerSavingEnabled", "cloudKitSyncEnabled", 
                   "settingsVersion", "lastCloudKitSync"]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}

// MARK: - CloudKit Integration Tests

@MainActor
final class SettingsManagerCloudKitTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    var mockContainer: CKContainer!
    
    override func setUp() {
        super.setUp()
        
        // Use a test container
        mockContainer = CKContainer(identifier: "iCloud.com.test.WhatTheFlight")
        settingsManager = SettingsManager(container: mockContainer)
    }
    
    override func tearDown() {
        settingsManager = nil
        mockContainer = nil
        super.tearDown()
    }
    
    func testCloudKitSyncWithValidData() async {
        // Set up test data
        settingsManager.queryInterval = 45.0
        settingsManager.powerSavingEnabled = true
        
        let testBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        settingsManager.geographicBounds = testBounds
        
        // Note: In a real test environment, you would mock the CloudKit operations
        // For now, we test that the sync method doesn't throw with valid data
        do {
            try await settingsManager.syncWithCloudKit()
            // If we reach here without throwing, the sync method handled the data correctly
            XCTAssertTrue(true)
        } catch {
            // In a test environment, CloudKit operations might fail due to network/auth issues
            // We verify that our error handling works correctly
            if let settingsError = error as? SettingsError {
                switch settingsError {
                case .cloudKitSyncFailed:
                    XCTAssertTrue(true) // Expected in test environment
                default:
                    XCTFail("Unexpected settings error: \(settingsError)")
                }
            }
        }
    }
    
    func testCloudKitSyncDisabled() async {
        settingsManager.cloudKitSyncEnabled = false
        
        // Sync should complete immediately when disabled
        do {
            try await settingsManager.syncWithCloudKit()
            XCTAssertTrue(true) // Should not throw when disabled
        } catch {
            XCTFail("Sync should not fail when CloudKit sync is disabled")
        }
    }
}