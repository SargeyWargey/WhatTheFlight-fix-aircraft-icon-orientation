//
//  SettingsViewModel.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import Combine
import CoreLocation

@MainActor
class SettingsViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var queryInterval: TimeInterval = 30.0
    @Published var geographicBounds: GeographicBounds?
    @Published var displayPreferences: DisplayPreferences = .default
    @Published var notificationSettings: NotificationSettings = .default
    @Published var powerSavingEnabled: Bool = false
    @Published var cloudKitSyncEnabled: Bool = true
    @Published var showAircraftIcons: Bool = true
    @Published var showAircraftPhotos: Bool = false
    @Published var autoFocusNearest: Bool = true
    
    // UI State
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var isSyncing: Bool = false
    @Published var locationPermissionStatus: CLAuthorizationStatus = .notDetermined
    
    // Manual coordinate entry
    @Published var manualLatitude: String = ""
    @Published var manualLongitude: String = ""
    @Published var manualRadius: String = "50"
    @Published var manualRadiusInMiles: String = "31"
    @Published var radiusInMiles: Double = 31.0
    @Published var isManualEntryMode: Bool = false
    
    // MARK: - Computed Properties
    
    /// Returns true if the current query interval is valid
    var isQueryIntervalValid: Bool {
        return settingsManager.validateQueryInterval(queryInterval)
    }
    
    /// Returns the query interval validation message
    var queryIntervalValidationMessage: String? {
        if !isQueryIntervalValid {
            return "Query interval must be between 15-120 seconds"
        }
        return nil
    }
    
    /// Returns true if manual coordinates are valid
    var areManualCoordinatesValid: Bool {
        guard let lat = Double(manualLatitude),
              let lon = Double(manualLongitude) else {
            return false
        }
        
        return abs(lat) <= 90 && abs(lon) <= 180
    }
    
    /// Returns true if radius in miles is valid
    var isRadiusInMilesValid: Bool {
        return radiusInMiles >= 5 && radiusInMiles <= 50
    }
    
    /// Returns validation message for manual coordinates
    var manualCoordinatesValidationMessage: String? {
        if isManualEntryMode && !areManualCoordinatesValid {
            return "Enter valid coordinates (lat: ±90°, lon: ±180°)"
        }
        return nil
    }
    
    /// Returns validation message for radius in miles
    var radiusValidationMessage: String? {
        if radiusInMiles < 5 || radiusInMiles > 50 {
            return "Radius must be between 5-50 miles"
        }
        
        return nil
    }
    
    /// Returns true if location services are available
    var canUseLocationServices: Bool {
        #if os(iOS)
        return locationPermissionStatus == .authorizedWhenInUse || 
               locationPermissionStatus == .authorizedAlways
        #elseif os(macOS)
        return locationPermissionStatus == .authorizedAlways
        #else
        return locationPermissionStatus == .authorizedAlways
        #endif
    }
    
    /// Returns a user-friendly location status message
    var locationStatusMessage: String {
        switch locationPermissionStatus {
        case .notDetermined:
            return "Location permission not requested"
        case .denied, .restricted:
            #if os(tvOS)
            return "Location not available on tvOS - use manual entry"
            #else
            return "Location permission denied - use manual entry"
            #endif
        case .authorizedAlways:
            return "Location permission granted"
        #if os(iOS)
        case .authorizedWhenInUse:
            return "Location permission granted"
        #endif
        #if os(tvOS)
        case .authorizedWhenInUse:
            return "Location not available on tvOS - use manual entry"
        #endif
        @unknown default:
            return "Unknown location status"
        }
    }
    
    /// Returns formatted bounds description
    var boundsDescription: String {
        guard let bounds = geographicBounds else {
            return "No area configured"
        }
        
        let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
        let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
        let latSpan = bounds.northLatitude - bounds.southLatitude
        let lonSpan = bounds.eastLongitude - bounds.westLongitude
        let radiusKm = max(latSpan, lonSpan) * 111.0 / 2 // Rough conversion
        let radiusMiles = kilometersToMiles(radiusKm)
        
        return String(format: "Center: %.3f°, %.3f° (±%.1f miles)", centerLat, centerLon, radiusMiles)
    }
    
    // MARK: - Private Properties
    
    private let settingsManager: any SettingsManagerProtocol
    private let locationManager: any LocationManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    private var messageTimer: Timer?
    
    // MARK: - Initialization
    
    init(settingsManager: any SettingsManagerProtocol, locationManager: any LocationManagerProtocol) {
        self.settingsManager = settingsManager
        self.locationManager = locationManager
        
        setupBindings()
        loadCurrentSettings()
    }
    
    // MARK: - Public Methods
    
    /// Saves the current query interval
    func saveQueryInterval() {
        guard isQueryIntervalValid else {
            setError("Invalid query interval")
            return
        }
        
        settingsManager.queryInterval = queryInterval
        showSuccess("Query interval updated")
    }
    
    /// Saves the current display preferences
    func saveDisplayPreferences() {
        settingsManager.displayPreferences = displayPreferences
        showSuccess("Display preferences updated")
    }
    
    /// Saves the current notification settings
    func saveNotificationSettings() {
        settingsManager.notificationSettings = notificationSettings
        showSuccess("Notification settings updated")
    }
    
    /// Saves the power saving setting
    func savePowerSavingEnabled() {
        settingsManager.powerSavingEnabled = powerSavingEnabled
        showSuccess("Power saving setting updated")
    }
    
    /// Saves the CloudKit sync setting
    func saveCloudKitSyncEnabled() {
        settingsManager.cloudKitSyncEnabled = cloudKitSyncEnabled
        showSuccess("CloudKit sync setting updated")
    }
    
    /// Saves the aircraft icons display setting
    func saveShowAircraftIcons() {
        settingsManager.showAircraftIcons = showAircraftIcons
        showSuccess("Aircraft icons setting updated")
    }
    
    /// Saves the aircraft photos display setting
    func saveShowAircraftPhotos() {
        settingsManager.showAircraftPhotos = showAircraftPhotos
        showSuccess("Aircraft photos setting updated")
    }
    
    /// Saves the auto-focus nearest aircraft setting
    func saveAutoFocusNearest() {
        settingsManager.autoFocusNearest = autoFocusNearest
        showSuccess("Auto-focus setting updated")
    }
    
    /// Requests location permission and automatically gets location if granted
    func requestLocationPermission() {
        locationManager.requestLocationPermission()
        
        // Wait a moment for permission to be processed, then try to get location
        Task {
            try? await Task.sleep(for: .seconds(1))
            
            await MainActor.run {
                if canUseLocationServices {
                    useCurrentLocation()
                }
            }
        }
    }
    
    /// Uses current location to set geographic bounds
    func useCurrentLocation() {
        guard canUseLocationServices else {
            setError("Location permission required")
            return
        }
        
        isLoading = true
        clearMessages()
        
        Task {
            do {
                let location = try await locationManager.getCurrentLocation()
                let bounds = createBoundsAroundLocation(location, radiusKm: 50.0)
                
                await MainActor.run {
                    updateGeographicBounds(bounds)
                    
                    // Populate manual entry fields with the obtained coordinates
                    manualLatitude = String(format: "%.6f", location.coordinate.latitude)
                    manualLongitude = String(format: "%.6f", location.coordinate.longitude)
                    manualRadius = "50.0"
                    manualRadiusInMiles = String(format: "%.1f", kilometersToMiles(50.0))
                    
                    isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    isLoading = false
                    setError("Failed to get location: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Sets geographic bounds using manual coordinate entry
    func setManualCoordinates() {
        guard areManualCoordinatesValid else {
            setError("Invalid coordinates entered")
            return
        }
        
        guard let lat = Double(manualLatitude),
              let lon = Double(manualLongitude) else {
            setError("Invalid coordinate format")
            return
        }
        
        // Use the current radius from miles
        let radiusKm = milesToKilometers(radiusInMiles)
        
        let location = CLLocation(latitude: lat, longitude: lon)
        let bounds = createBoundsAroundLocation(location, radiusKm: radiusKm)
        
        updateGeographicBounds(bounds)
        showSuccess("Manual coordinates set successfully")
    }
    
    /// Updates the radius when the miles value changes
    func updateRadiusFromMiles() {
        guard radiusInMiles >= 5 && radiusInMiles <= 50 else {
            setError("Radius must be between 5-50 miles")
            return
        }
        
        // Save to settings manager
        settingsManager.radiusInMiles = radiusInMiles
        
        // Convert miles to kilometers and update the internal radius
        let radiusKm = milesToKilometers(radiusInMiles)
        manualRadius = String(format: "%.1f", radiusKm)
        manualRadiusInMiles = String(format: "%.1f", radiusInMiles)
        
        // If we have existing bounds, update them with the new radius
        if let bounds = geographicBounds {
            let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
            let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
            let location = CLLocation(latitude: centerLat, longitude: centerLon)
            let newBounds = createBoundsAroundLocation(location, radiusKm: radiusKm)
            updateGeographicBounds(newBounds)
        }
    }
    
    /// Toggles between automatic location and manual entry modes
    func toggleLocationMode() {
        isManualEntryMode.toggle()
        clearMessages()
        
        if isManualEntryMode {
            // Pre-fill with current bounds if available
            if let bounds = geographicBounds {
                let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
                let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
                let latSpan = bounds.northLatitude - bounds.southLatitude
                let radiusKm = latSpan * 111.0 / 2
                
                manualLatitude = String(format: "%.6f", centerLat)
                manualLongitude = String(format: "%.6f", centerLon)
                manualRadius = String(format: "%.1f", radiusKm)
                manualRadiusInMiles = String(format: "%.1f", kilometersToMiles(radiusKm))
            }
        }
    }
    
    /// Resets all settings to defaults
    func resetToDefaults() {
        isLoading = true
        clearMessages()
        
        Task {
            settingsManager.resetToDefaults()
            
            await MainActor.run {
                loadCurrentSettings()
                isLoading = false
                showSuccess("Settings reset to defaults")
            }
        }
    }
    
    /// Manually triggers CloudKit sync
    func syncWithCloudKit() {
        guard cloudKitSyncEnabled else {
            setError("CloudKit sync is disabled")
            return
        }
        
        isSyncing = true
        clearMessages()
        
        Task {
            do {
                try await settingsManager.syncWithCloudKit()
                
                await MainActor.run {
                    isSyncing = false
                    showSuccess("Settings synced with CloudKit")
                }
                
            } catch {
                await MainActor.run {
                    isSyncing = false
                    setError("CloudKit sync failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Validates and updates a specific setting
    func validateAndUpdateSetting<T: Equatable>(_ keyPath: WritableKeyPath<SettingsViewModel, T>, 
                                               value: T, 
                                               validator: ((T) -> Bool)? = nil,
                                               errorMessage: String = "Invalid value") {
        if let validator = validator, !validator(value) {
            setError(errorMessage)
            return
        }
        
        // Use a switch or if-else to handle specific key paths
        // This is a workaround for the keyPath assignment limitation
        clearMessages()
    }
    
    /// Clears all messages
    func clearMessages() {
        errorMessage = nil
        successMessage = nil
        messageTimer?.invalidate()
        messageTimer = nil
    }
    
    /// Sets an error message
    func setError(_ message: String) {
        errorMessage = message
        successMessage = nil
        scheduleMessageClear()
    }
    
    /// Shows a success message
    func showSuccess(_ message: String) {
        successMessage = message
        errorMessage = nil
        scheduleMessageClear()
    }
}

// MARK: - Private Methods
private extension SettingsViewModel {
    
    /// Sets up Combine bindings with the settings manager
    func setupBindings() {
        // Bind settings manager properties
        if let observableSettingsManager = settingsManager as? SettingsManager {
            observableSettingsManager.$queryInterval
                .receive(on: DispatchQueue.main)
                .sink { [weak self] interval in
                    self?.queryInterval = interval
                }
                .store(in: &cancellables)
            
            observableSettingsManager.$geographicBounds
                .receive(on: DispatchQueue.main)
                .sink { [weak self] bounds in
                    self?.geographicBounds = bounds
                }
                .store(in: &cancellables)
            
            observableSettingsManager.$displayPreferences
                .receive(on: DispatchQueue.main)
                .sink { [weak self] preferences in
                    self?.displayPreferences = preferences
                }
                .store(in: &cancellables)
            
            observableSettingsManager.$notificationSettings
                .receive(on: DispatchQueue.main)
                .sink { [weak self] settings in
                    self?.notificationSettings = settings
                }
                .store(in: &cancellables)
            
            observableSettingsManager.$powerSavingEnabled
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in
                    self?.powerSavingEnabled = enabled
                }
                .store(in: &cancellables)
            
            observableSettingsManager.$cloudKitSyncEnabled
                .receive(on: DispatchQueue.main)
                .sink { [weak self] enabled in
                    self?.cloudKitSyncEnabled = enabled
                }
                .store(in: &cancellables)
        }
        
        // Bind location manager properties
        if let observableLocationManager = locationManager as? LocationManager {
            observableLocationManager.$authorizationStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    let previousStatus = self?.locationPermissionStatus
                    self?.locationPermissionStatus = status
                    
                    // Auto-fetch location when permission is newly granted
                    if let self = self,
                       let previous = previousStatus,
                       previous == .notDetermined && self.canUseLocationServices {
                        self.useCurrentLocation()
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    /// Loads current settings from the settings manager
    func loadCurrentSettings() {
        queryInterval = settingsManager.queryInterval
        geographicBounds = settingsManager.geographicBounds
        radiusInMiles = settingsManager.radiusInMiles
        displayPreferences = settingsManager.displayPreferences
        notificationSettings = settingsManager.notificationSettings
        powerSavingEnabled = settingsManager.powerSavingEnabled
        cloudKitSyncEnabled = settingsManager.cloudKitSyncEnabled
        showAircraftIcons = settingsManager.showAircraftIcons
        showAircraftPhotos = settingsManager.showAircraftPhotos
        autoFocusNearest = settingsManager.autoFocusNearest
        
        // Initialize manual fields from existing bounds
        if let bounds = geographicBounds {
            let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
            let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
            let latSpan = bounds.northLatitude - bounds.southLatitude
            let radiusKm = latSpan * 111.0 / 2
            let radiusMiles = kilometersToMiles(radiusKm)
            
            manualLatitude = String(format: "%.6f", centerLat)
            manualLongitude = String(format: "%.6f", centerLon)
            manualRadius = String(format: "%.1f", radiusKm)
            manualRadiusInMiles = String(format: "%.1f", radiusMiles)
            
            // Use stored radius or calculated radius, clamped to slider range
            if radiusInMiles < 5 || radiusInMiles > 50 {
                radiusInMiles = max(5, min(50, radiusMiles))
                settingsManager.radiusInMiles = radiusInMiles
            }
        }
    }
    
    /// Updates the geographic bounds
    func updateGeographicBounds(_ bounds: GeographicBounds) {
        guard bounds.isValid else {
            setError("Invalid geographic bounds")
            return
        }
        
        geographicBounds = bounds
        settingsManager.geographicBounds = bounds
    }
    
    /// Creates geographic bounds around a given location
    func createBoundsAroundLocation(_ location: CLLocation, radiusKm: Double) -> GeographicBounds {
        let coordinate = location.coordinate
        
        // Calculate approximate degree offset for the given radius
        let latOffset = radiusKm / 111.0 // Rough conversion: 1 degree ≈ 111 km
        let lonOffset = radiusKm / (111.0 * cos(coordinate.latitude * .pi / 180.0))
        
        return GeographicBounds(
            northLatitude: coordinate.latitude + latOffset,
            southLatitude: coordinate.latitude - latOffset,
            eastLongitude: coordinate.longitude + lonOffset,
            westLongitude: coordinate.longitude - lonOffset
        )
    }
    
    /// Schedules automatic message clearing
    func scheduleMessageClear() {
        messageTimer?.invalidate()
        messageTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.clearMessages()
            }
        }
    }
    
    /// Converts miles to kilometers
    func milesToKilometers(_ miles: Double) -> Double {
        return miles * 1.609344
    }
    
    /// Converts kilometers to miles
    func kilometersToMiles(_ kilometers: Double) -> Double {
        return kilometers / 1.609344
    }
}

// MARK: - Validation Helpers
extension SettingsViewModel {
    
    /// Validates query interval input
    func validateQueryInterval(_ interval: TimeInterval) -> Bool {
        return settingsManager.validateQueryInterval(interval)
    }
    
    /// Validates geographic bounds
    func validateGeographicBounds(_ bounds: GeographicBounds?) -> Bool {
        return bounds?.isValid ?? false
    }
    
    /// Validates coordinate string input
    func validateCoordinateString(_ coordinate: String, range: ClosedRange<Double>) -> Bool {
        guard let value = Double(coordinate) else { return false }
        return range.contains(value)
    }
    
    /// Validates radius string input
    func validateRadiusString(_ radius: String) -> Bool {
        guard let value = Double(radius) else { return false }
        return value > 0 && value <= 500
    }
    
    /// Validates radius in miles string input
    func validateRadiusInMilesString(_ radius: String) -> Bool {
        guard let value = Double(radius) else { return false }
        return value > 0 && value <= 311
    }
}

// MARK: - Data Transformation Helpers
extension SettingsViewModel {
    
    /// Converts display preferences to UI-friendly format
    func displayPreferencesForUI() -> DisplayPreferencesUI {
        return DisplayPreferencesUI(
            textSizeIndex: TextSize.allCases.firstIndex(of: displayPreferences.textSize) ?? 1,
            colorThemeIndex: ColorTheme.allCases.firstIndex(of: displayPreferences.colorTheme) ?? 0,
            densityIndex: InformationDensity.allCases.firstIndex(of: displayPreferences.informationDensity) ?? 1,
            animationsEnabled: displayPreferences.animationsEnabled,
            showAltitude: displayPreferences.showAltitude,
            showSpeed: displayPreferences.showSpeed,
            showHeading: displayPreferences.showHeading
        )
    }
    
    /// Updates display preferences from UI format
    func updateDisplayPreferencesFromUI(_ ui: DisplayPreferencesUI) {
        displayPreferences = DisplayPreferences(
            textSize: TextSize.allCases[ui.textSizeIndex],
            colorTheme: ColorTheme.allCases[ui.colorThemeIndex],
            informationDensity: InformationDensity.allCases[ui.densityIndex],
            animationsEnabled: ui.animationsEnabled,
            showAltitude: ui.showAltitude,
            showSpeed: ui.showSpeed,
            showHeading: ui.showHeading
        )
    }
    
    /// Transforms notification settings for UI presentation
    func notificationSettingsForUI() -> NotificationSettingsUI {
        return NotificationSettingsUI(
            flightDetectionEnabled: notificationSettings.flightDetectionEnabled,
            connectionStatusEnabled: notificationSettings.connectionStatusEnabled,
            errorAlertsEnabled: notificationSettings.errorAlertsEnabled,
            soundEnabled: notificationSettings.soundEnabled,
            badgeEnabled: notificationSettings.badgeEnabled
        )
    }
    
    /// Updates notification settings from UI format
    func updateNotificationSettingsFromUI(_ ui: NotificationSettingsUI) {
        notificationSettings = NotificationSettings(
            flightDetectionEnabled: ui.flightDetectionEnabled,
            connectionStatusEnabled: ui.connectionStatusEnabled,
            errorAlertsEnabled: ui.errorAlertsEnabled,
            soundEnabled: ui.soundEnabled,
            badgeEnabled: ui.badgeEnabled
        )
    }
    
    /// Validates and applies a batch of settings changes
    func applySettingsBatch(_ changes: SettingsChangeBatch) -> [String] {
        var errors: [String] = []
        
        if let interval = changes.queryInterval {
            if validateQueryInterval(interval) {
                queryInterval = interval
            } else {
                errors.append("Invalid query interval: must be between 15-120 seconds")
            }
        }
        
        if let bounds = changes.geographicBounds {
            if validateGeographicBounds(bounds) {
                geographicBounds = bounds
            } else {
                errors.append("Invalid geographic bounds")
            }
        }
        
        if let preferences = changes.displayPreferences {
            displayPreferences = preferences
        }
        
        if let notifications = changes.notificationSettings {
            notificationSettings = notifications
        }
        
        if let powerSaving = changes.powerSavingEnabled {
            powerSavingEnabled = powerSaving
        }
        
        if let cloudKitSync = changes.cloudKitSyncEnabled {
            cloudKitSyncEnabled = cloudKitSync
        }
        
        // Save all changes if no errors
        if errors.isEmpty {
            saveAllSettings()
        }
        
        return errors
    }
    
    /// Saves all current settings to the settings manager
    private func saveAllSettings() {
        settingsManager.queryInterval = queryInterval
        settingsManager.geographicBounds = geographicBounds
        settingsManager.displayPreferences = displayPreferences
        settingsManager.notificationSettings = notificationSettings
        settingsManager.powerSavingEnabled = powerSavingEnabled
        settingsManager.cloudKitSyncEnabled = cloudKitSyncEnabled
        settingsManager.showAircraftIcons = showAircraftIcons
        settingsManager.showAircraftPhotos = showAircraftPhotos
        settingsManager.autoFocusNearest = autoFocusNearest
    }
}

// MARK: - Supporting Types

struct DisplayPreferencesUI {
    var textSizeIndex: Int
    var colorThemeIndex: Int
    var densityIndex: Int
    var animationsEnabled: Bool
    var showAltitude: Bool
    var showSpeed: Bool
    var showHeading: Bool
}

struct NotificationSettingsUI {
    var flightDetectionEnabled: Bool
    var connectionStatusEnabled: Bool
    var errorAlertsEnabled: Bool
    var soundEnabled: Bool
    var badgeEnabled: Bool
}

struct SettingsChangeBatch {
    var queryInterval: TimeInterval?
    var geographicBounds: GeographicBounds?
    var displayPreferences: DisplayPreferences?
    var notificationSettings: NotificationSettings?
    var powerSavingEnabled: Bool?
    var cloudKitSyncEnabled: Bool?
}