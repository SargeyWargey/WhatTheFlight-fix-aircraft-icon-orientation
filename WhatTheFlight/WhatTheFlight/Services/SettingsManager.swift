//
//  SettingsManager.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import CloudKit
import Combine

@MainActor
protocol SettingsManagerProtocol: ObservableObject {
    var queryInterval: TimeInterval { get set }
    var geographicBounds: GeographicBounds? { get set }
    var radiusInMiles: Double { get set }
    var displayPreferences: DisplayPreferences { get set }
    var notificationSettings: NotificationSettings { get set }
    var powerSavingEnabled: Bool { get set }
    var cloudKitSyncEnabled: Bool { get set }
    var showAircraftIcons: Bool { get set }
    var showAircraftPhotos: Bool { get set }
    var autoFocusNearest: Bool { get set }
    var manualLocationLatitude: Double? { get set }
    var manualLocationLongitude: Double? { get set }
    var useManualLocation: Bool { get set }
    
    func validateQueryInterval(_ interval: TimeInterval) -> Bool
    func resetToDefaults()
    func syncWithCloudKit() async throws
    func migrateSettings(from version: Int, to newVersion: Int)
}

@MainActor
class SettingsManager: SettingsManagerProtocol, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var queryInterval: TimeInterval = 30.0 {
        didSet {
            if validateQueryInterval(queryInterval) {
                saveToUserDefaults(queryInterval, forKey: Keys.queryInterval)
                if cloudKitSyncEnabled {
                    Task { try? await syncWithCloudKit() }
                }
            } else {
                queryInterval = oldValue
            }
        }
    }
    
    @Published var geographicBounds: GeographicBounds? {
        didSet {
            if let bounds = geographicBounds, bounds.isValid {
                saveToUserDefaults(bounds, forKey: Keys.geographicBounds)
                if cloudKitSyncEnabled {
                    Task { try? await syncWithCloudKit() }
                }
            } else if geographicBounds == nil {
                UserDefaults.standard.removeObject(forKey: Keys.geographicBounds)
                if cloudKitSyncEnabled {
                    Task { try? await syncWithCloudKit() }
                }
            } else {
                geographicBounds = oldValue
            }
        }
    }
    
    @Published var displayPreferences: DisplayPreferences = .default {
        didSet {
            saveToUserDefaults(displayPreferences, forKey: Keys.displayPreferences)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var notificationSettings: NotificationSettings = .default {
        didSet {
            saveToUserDefaults(notificationSettings, forKey: Keys.notificationSettings)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var powerSavingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(powerSavingEnabled, forKey: Keys.powerSavingEnabled)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var radiusInMiles: Double = 31.0 {
        didSet {
            UserDefaults.standard.set(radiusInMiles, forKey: Keys.radiusInMiles)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var cloudKitSyncEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(cloudKitSyncEnabled, forKey: Keys.cloudKitSyncEnabled)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var showAircraftIcons: Bool = false {
        didSet {
            UserDefaults.standard.set(showAircraftIcons, forKey: Keys.showAircraftIcons)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var showAircraftPhotos: Bool = false {
        didSet {
            UserDefaults.standard.set(showAircraftPhotos, forKey: Keys.showAircraftPhotos)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var autoFocusNearest: Bool = true {
        didSet {
            UserDefaults.standard.set(autoFocusNearest, forKey: Keys.autoFocusNearest)
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var manualLocationLatitude: Double? {
        didSet {
            if let latitude = manualLocationLatitude {
                UserDefaults.standard.set(latitude, forKey: Keys.manualLocationLatitude)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.manualLocationLatitude)
            }
            updateBoundsFromManualLocation()
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var manualLocationLongitude: Double? {
        didSet {
            if let longitude = manualLocationLongitude {
                UserDefaults.standard.set(longitude, forKey: Keys.manualLocationLongitude)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.manualLocationLongitude)
            }
            updateBoundsFromManualLocation()
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    @Published var useManualLocation: Bool = false {
        didSet {
            UserDefaults.standard.set(useManualLocation, forKey: Keys.useManualLocation)
            updateBoundsFromManualLocation()
            if cloudKitSyncEnabled {
                Task { try? await syncWithCloudKit() }
            }
        }
    }
    
    // MARK: - Private Properties
    
    private let container: CKContainer?
    private let database: CKDatabase?
    private let recordZone: CKRecordZone?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Constants
    
    private struct Keys {
        static let queryInterval = "queryInterval"
        static let geographicBounds = "geographicBounds"
        static let radiusInMiles = "radiusInMiles"
        static let displayPreferences = "displayPreferences"
        static let notificationSettings = "notificationSettings"
        static let powerSavingEnabled = "powerSavingEnabled"
        static let cloudKitSyncEnabled = "cloudKitSyncEnabled"
        static let showAircraftIcons = "showAircraftIcons"
        static let showAircraftPhotos = "showAircraftPhotos"
        static let autoFocusNearest = "autoFocusNearest"
        static let manualLocationLatitude = "manualLocationLatitude"
        static let manualLocationLongitude = "manualLocationLongitude"
        static let useManualLocation = "useManualLocation"
        static let settingsVersion = "settingsVersion"
        static let lastCloudKitSync = "lastCloudKitSync"
    }
    
    private struct CloudKitKeys {
        static let recordType = "UserSettings"
        static let recordID = "userSettings"
        static let zoneID = "SettingsZone"
    }
    
    private struct ValidationConstants {
        static let minQueryInterval: TimeInterval = 15.0
        static let maxQueryInterval: TimeInterval = 120.0
        static let currentSettingsVersion = 1
    }
    
    // MARK: - Initialization
    
    init(container: CKContainer? = nil, enableCloudKit: Bool = false) {
        // Initialize CloudKit container only if enabled and properly configured
        if enableCloudKit {
            if let container = container {
                self.container = container
            } else {
                // Use the default CloudKit container to avoid hardcoded identifiers
                self.container = CKContainer.default()
            }
            
            if let container = self.container {
                self.database = container.privateCloudDatabase
                self.recordZone = CKRecordZone(zoneName: CloudKitKeys.zoneID)
            } else {
                self.database = nil
                self.recordZone = nil
            }
        } else {
            // Don't initialize CloudKit when disabled
            self.container = nil
            self.database = nil
            self.recordZone = nil
        }
        
        loadFromUserDefaults()
        performMigrationIfNeeded()
        
        // Disable CloudKit sync if not enabled or if initialization failed
        if !enableCloudKit || self.container == nil {
            cloudKitSyncEnabled = false
        }
        
        // Setup CloudKit zone if needed (only if CloudKit is available and enabled)
        if enableCloudKit && container != nil {
            Task {
                await setupCloudKitZoneIfAvailable()
                if cloudKitSyncEnabled {
                    try? await syncWithCloudKit()
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    func validateQueryInterval(_ interval: TimeInterval) -> Bool {
        return interval >= ValidationConstants.minQueryInterval && 
               interval <= ValidationConstants.maxQueryInterval
    }
    
    func resetToDefaults() {
        queryInterval = 30.0
        geographicBounds = nil
        radiusInMiles = 31.0
        displayPreferences = .default
        notificationSettings = .default
        powerSavingEnabled = false
        cloudKitSyncEnabled = false
        showAircraftIcons = false
        showAircraftPhotos = false
        autoFocusNearest = true
        manualLocationLatitude = nil
        manualLocationLongitude = nil
        useManualLocation = false
        
        // Clear UserDefaults
        let keys = [Keys.queryInterval, Keys.geographicBounds, Keys.displayPreferences,
                   Keys.notificationSettings, Keys.powerSavingEnabled, Keys.showAircraftIcons,
                   Keys.showAircraftPhotos, Keys.autoFocusNearest, Keys.manualLocationLatitude, Keys.manualLocationLongitude, Keys.useManualLocation]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        
        if cloudKitSyncEnabled {
            Task { try? await syncWithCloudKit() }
        }
    }
    
    func syncWithCloudKit() async throws {
        guard cloudKitSyncEnabled, 
              let container = container,
              let database = database,
              let recordZone = recordZone else { return }
        
        // Check CloudKit availability first
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                print("CloudKit account not available: \(accountStatus)")
                await MainActor.run {
                    cloudKitSyncEnabled = false
                }
                return
            }
        } catch {
            print("Failed to check CloudKit account status: \(error)")
            throw SettingsError.cloudKitSyncFailed(error)
        }
        
        do {
            // Try to fetch existing record
            let recordID = CKRecord.ID(recordName: CloudKitKeys.recordID, zoneID: recordZone.zoneID)
            
            let record: CKRecord
            do {
                record = try await database.record(for: recordID)
            } catch {
                // Record doesn't exist, create new one
                record = CKRecord(recordType: CloudKitKeys.recordType, recordID: recordID)
            }
            
            // Update record with current settings
            record["queryInterval"] = queryInterval
            record["displayPreferences"] = try JSONEncoder().encode(displayPreferences)
            record["notificationSettings"] = try JSONEncoder().encode(notificationSettings)
            record["powerSavingEnabled"] = powerSavingEnabled
            record["showAircraftIcons"] = showAircraftIcons
            record["showAircraftPhotos"] = showAircraftPhotos
            record["autoFocusNearest"] = autoFocusNearest
            record["useManualLocation"] = useManualLocation
            record["lastModified"] = Date()
            
            if let bounds = geographicBounds {
                record["geographicBounds"] = try JSONEncoder().encode(bounds)
            } else {
                record["geographicBounds"] = nil
            }
            
            if let latitude = manualLocationLatitude {
                record["manualLocationLatitude"] = latitude
            } else {
                record["manualLocationLatitude"] = nil
            }
            
            if let longitude = manualLocationLongitude {
                record["manualLocationLongitude"] = longitude
            } else {
                record["manualLocationLongitude"] = nil
            }
            
            // Save to CloudKit
            _ = try await database.save(record)
            
            // Update last sync time
            UserDefaults.standard.set(Date(), forKey: Keys.lastCloudKitSync)
            
        } catch {
            print("CloudKit sync failed: \(error)")
            
            // Handle specific CloudKit errors
            if let ckError = error as? CKError {
                switch ckError.code {
                case .notAuthenticated, .quotaExceeded, .networkUnavailable:
                    await MainActor.run {
                        cloudKitSyncEnabled = false
                    }
                default:
                    break
                }
            }
            
            throw SettingsError.cloudKitSyncFailed(error)
        }
    }
    
    func migrateSettings(from version: Int, to newVersion: Int) {
        // Future migration logic can be added here
        switch (version, newVersion) {
        case (0, 1):
            // Initial version migration
            break
        default:
            break
        }
        
        UserDefaults.standard.set(newVersion, forKey: Keys.settingsVersion)
    }
    
    // MARK: - Private Methods
    
    private func loadFromUserDefaults() {
        queryInterval = UserDefaults.standard.object(forKey: Keys.queryInterval) as? TimeInterval ?? 30.0
        radiusInMiles = UserDefaults.standard.object(forKey: Keys.radiusInMiles) as? Double ?? 31.0
        powerSavingEnabled = UserDefaults.standard.bool(forKey: Keys.powerSavingEnabled)
        cloudKitSyncEnabled = UserDefaults.standard.object(forKey: Keys.cloudKitSyncEnabled) as? Bool ?? false
        #if os(tvOS)
        // On tvOS, force enable aircraft icons for better visual experience
        if UserDefaults.standard.object(forKey: Keys.showAircraftIcons) == nil {
            // First time - set to true and save it
            showAircraftIcons = true
            UserDefaults.standard.set(true, forKey: Keys.showAircraftIcons)
        } else {
            // Force enable on tvOS regardless of previous setting
            showAircraftIcons = true
            UserDefaults.standard.set(true, forKey: Keys.showAircraftIcons)
        }
        #else
        showAircraftIcons = UserDefaults.standard.object(forKey: Keys.showAircraftIcons) as? Bool ?? false
        #endif
        showAircraftPhotos = UserDefaults.standard.object(forKey: Keys.showAircraftPhotos) as? Bool ?? false
        autoFocusNearest = UserDefaults.standard.object(forKey: Keys.autoFocusNearest) as? Bool ?? true
        useManualLocation = UserDefaults.standard.bool(forKey: Keys.useManualLocation)
        
        // Load manual location coordinates
        if UserDefaults.standard.object(forKey: Keys.manualLocationLatitude) != nil {
            manualLocationLatitude = UserDefaults.standard.double(forKey: Keys.manualLocationLatitude)
        }
        if UserDefaults.standard.object(forKey: Keys.manualLocationLongitude) != nil {
            manualLocationLongitude = UserDefaults.standard.double(forKey: Keys.manualLocationLongitude)
        }
        
        #if os(tvOS)
        // On tvOS, automatically enable manual location mode since there's no GPS
        // Set default location to Denver if no location is configured
        if manualLocationLatitude == nil || manualLocationLongitude == nil {
            manualLocationLatitude = 39.7392 // Denver, Colorado latitude
            manualLocationLongitude = -104.9903 // Denver, Colorado longitude
            useManualLocation = true
        }
        #endif
        
        if let boundsData = UserDefaults.standard.data(forKey: Keys.geographicBounds) {
            geographicBounds = try? JSONDecoder().decode(GeographicBounds.self, from: boundsData)
        }
        
        if let preferencesData = UserDefaults.standard.data(forKey: Keys.displayPreferences) {
            displayPreferences = (try? JSONDecoder().decode(DisplayPreferences.self, from: preferencesData)) ?? .default
        }
        
        if let notificationData = UserDefaults.standard.data(forKey: Keys.notificationSettings) {
            notificationSettings = (try? JSONDecoder().decode(NotificationSettings.self, from: notificationData)) ?? .default
        }
    }
    
    private func saveToUserDefaults<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    private func performMigrationIfNeeded() {
        let currentVersion = UserDefaults.standard.integer(forKey: Keys.settingsVersion)
        let targetVersion = ValidationConstants.currentSettingsVersion
        
        if currentVersion < targetVersion {
            migrateSettings(from: currentVersion, to: targetVersion)
        }
    }
    
    private func updateBoundsFromManualLocation() {
        guard useManualLocation,
              let latitude = manualLocationLatitude,
              let longitude = manualLocationLongitude else {
            return
        }
        
        do {
            let bounds = try LocationManager.createBoundsFromManualEntry(
                latitude: latitude,
                longitude: longitude,
                radiusKm: radiusInMiles * 1.60934 // Convert miles to km
            )
            geographicBounds = bounds
        } catch {
            print("Failed to create bounds from manual location: \(error)")
        }
    }
    
    private func setupCloudKitZoneIfAvailable() async {
        guard let container = container, let database = database, let recordZone = recordZone else {
            print("CloudKit components not available")
            await MainActor.run {
                cloudKitSyncEnabled = false
            }
            return
        }
        
        // Check if CloudKit is available
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                print("CloudKit account not available: \(accountStatus)")
                await MainActor.run {
                    cloudKitSyncEnabled = false
                }
                return
            }
            
            // Create the custom zone
            _ = try await database.save(recordZone)
        } catch {
            // Zone might already exist, which is fine
            if let ckError = error as? CKError {
                switch ckError.code {
                case .zoneNotFound, .serverRecordChanged:
                    // These are expected errors, continue
                    break
                case .notAuthenticated, .quotaExceeded, .networkUnavailable:
                    print("CloudKit unavailable: \(ckError.localizedDescription)")
                    await MainActor.run {
                        cloudKitSyncEnabled = false
                    }
                default:
                    print("Failed to create CloudKit zone: \(error)")
                }
            } else {
                print("Failed to create CloudKit zone: \(error)")
            }
        }
    }
}

// MARK: - Error Types

enum SettingsError: LocalizedError {
    case invalidQueryInterval(TimeInterval)
    case invalidGeographicBounds(GeographicBounds)
    case cloudKitSyncFailed(Error)
    case migrationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidQueryInterval(let interval):
            return "Invalid query interval: \(interval). Must be between 15-120 seconds."
        case .invalidGeographicBounds(let bounds):
            return "Invalid geographic bounds: \(bounds)"
        case .cloudKitSyncFailed(let error):
            return "CloudKit sync failed: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Settings migration failed: \(error.localizedDescription)"
        }
    }
}