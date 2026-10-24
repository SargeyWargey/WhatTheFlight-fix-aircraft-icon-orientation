//
//  MockSettingsManager.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import Combine
@testable import WhatTheFlight

@MainActor
class MockSettingsManager: SettingsManagerProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published var queryInterval: TimeInterval = 30.0
    @Published var geographicBounds: GeographicBounds?
    @Published var radiusInMiles: Double = 25.0
    @Published var displayPreferences: DisplayPreferences = .default
    @Published var notificationSettings: NotificationSettings = .default
    @Published var powerSavingEnabled: Bool = false
    @Published var cloudKitSyncEnabled: Bool = true
    @Published var showAircraftIcons: Bool = true
    @Published var showAircraftPhotos: Bool = false
    @Published var autoFocusNearest: Bool = true
    @Published var manualLocationLatitude: Double?
    @Published var manualLocationLongitude: Double?
    @Published var useManualLocation: Bool = false
    
    // MARK: - Mock Tracking Properties
    var validateQueryIntervalCalled = false
    var resetToDefaultsCalled = false
    var syncWithCloudKitCalled = false
    var migrateSettingsCalled = false
    var shouldThrowSyncError = false
    var lastValidatedInterval: TimeInterval?
    
    // MARK: - SettingsManagerProtocol Implementation
    
    func validateQueryInterval(_ interval: TimeInterval) -> Bool {
        validateQueryIntervalCalled = true
        lastValidatedInterval = interval
        return interval >= 15.0 && interval <= 120.0
    }
    
    func resetToDefaults() {
        resetToDefaultsCalled = true
        queryInterval = 30.0
        geographicBounds = nil
        radiusInMiles = 25.0
        displayPreferences = .default
        notificationSettings = .default
        powerSavingEnabled = false
        cloudKitSyncEnabled = true
        showAircraftIcons = true
        showAircraftPhotos = false
        autoFocusNearest = true
        manualLocationLatitude = nil
        manualLocationLongitude = nil
        useManualLocation = false
    }
    
    func syncWithCloudKit() async throws {
        syncWithCloudKitCalled = true
        
        if shouldThrowSyncError {
            throw MockError.syncFailed
        }
        
        // Simulate async operation
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
    }
    
    func migrateSettings(from version: Int, to newVersion: Int) {
        migrateSettingsCalled = true
    }
    
    // MARK: - Mock Helper Methods
    
    func reset() {
        validateQueryIntervalCalled = false
        resetToDefaultsCalled = false
        syncWithCloudKitCalled = false
        migrateSettingsCalled = false
        shouldThrowSyncError = false
        lastValidatedInterval = nil
        
        // Reset to defaults
        queryInterval = 30.0
        geographicBounds = nil
        radiusInMiles = 25.0
        displayPreferences = .default
        notificationSettings = .default
        powerSavingEnabled = false
        cloudKitSyncEnabled = true
        showAircraftIcons = true
        showAircraftPhotos = false
        autoFocusNearest = true
        manualLocationLatitude = nil
        manualLocationLongitude = nil
        useManualLocation = false
    }
    
    func setTestBounds(_ bounds: GeographicBounds) {
        geographicBounds = bounds
    }
    
    func setTestPreferences(_ preferences: DisplayPreferences) {
        displayPreferences = preferences
    }
    
    func setTestNotificationSettings(_ settings: NotificationSettings) {
        notificationSettings = settings
    }
}

// MARK: - Mock Error Types
enum MockError: Error, LocalizedError {
    case syncFailed
    case migrationFailed
    case validationFailed
    
    var errorDescription: String? {
        switch self {
        case .syncFailed:
            return "Mock sync failed"
        case .migrationFailed:
            return "Mock migration failed"
        case .validationFailed:
            return "Mock validation failed"
        }
    }
}