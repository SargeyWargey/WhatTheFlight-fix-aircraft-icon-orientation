//
//  MainViewModel.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import Combine
import CoreLocation

@MainActor
class MainViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private var allFlights: [FlightData] = [] {
        didSet {
            updateFilteredFlights()
            // Update prediction service with new flight data and user location
            predictionService.updateFlightData(flights)
            predictionService.updateUserLocation(userLocation)
        }
    }
    
    @Published var flights: [FlightData] = []
    
    /// User location derived from geographic bounds center
    private var userLocation: CLLocation? {
        guard let bounds = currentBounds else { return nil }
        let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
        let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
        return CLLocation(latitude: centerLat, longitude: centerLon)
    }
    
    /// Updates filtered flights when data or settings change
    private func updateFilteredFlights() {
        guard let userLocation = userLocation else { 
            flights = allFlights
            return 
        }
        let maxDistanceMiles = settingsManager.radiusInMiles
        
        // Filter flights within range
        var filteredFlights = allFlights.filter { flight in
            if let distance = flight.distanceFromLocation(userLocation) {
                return distance <= maxDistanceMiles
            }
            return true // Include flights without distance data
        }
        
        // Add locked aircraft even if out of range
        if isAircraftLocked, 
           let lockedId = lockedFlightId,
           let lockedFlight = lockedFlightData,
           !filteredFlights.contains(where: { $0.id == lockedId }) {
            filteredFlights.append(lockedFlight)
        }
        
        flights = filteredFlights
        
        // Fetch updated data for locked aircraft if it's not in the main response
        if isAircraftLocked, 
           let lockedId = lockedFlightId,
           !allFlights.contains(where: { $0.id == lockedId }) {
            Task {
                await fetchLockedAircraftDetails(flightId: lockedId)
            }
        }
    }
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isMonitoring: Bool = false
    @Published var currentBounds: GeographicBounds?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var lastUpdateTime: Date?
    
    // MARK: - Settings Properties (Proxied from SettingsManager)
    
    var queryInterval: TimeInterval {
        get { settingsManager.queryInterval }
        set { settingsManager.queryInterval = newValue }
    }
    
    var powerSavingEnabled: Bool {
        get { settingsManager.powerSavingEnabled }
        set { settingsManager.powerSavingEnabled = newValue }
    }
    
    var autoFocusNearest: Bool {
        get { settingsManager.autoFocusNearest }
        set { settingsManager.autoFocusNearest = newValue }
    }
    
    // MARK: - Computed Properties
    
    /// Returns flights sorted by distance from user location
    var sortedFlights: [FlightData] {
        guard let location = userLocation else { return flights }
        
        return flights.sorted { flight1, flight2 in
            let distance1 = flight1.distanceFromLocation(location) ?? Double.greatestFiniteMagnitude
            let distance2 = flight2.distanceFromLocation(location) ?? Double.greatestFiniteMagnitude
            return distance1 < distance2
        }
    }
    
    /// Returns the current flight being displayed based on currentAircraftIndex
    var currentFlight: FlightData? {
        let sorted = sortedFlights
        guard currentAircraftIndex < sorted.count else { return sorted.first }
        return sorted[currentAircraftIndex]
    }
    
    /// Returns the number of flights currently detected
    var flightCount: Int {
        return flights.count
    }
    
    /// Returns true if there are multiple flights to cycle through
    var hasMultipleFlights: Bool {
        return flights.count > 1
    }
    
    /// Returns a user-friendly status message
    var statusMessage: String {
        if isLoading {
            return "Loading..."
        }
        
        switch connectionStatus {
        case .disconnected:
            return isMonitoring ? "Starting monitoring..." : "Not monitoring"
        case .connecting:
            return "Connecting to flight data..."
        case .connected:
            if flights.isEmpty {
                return "No flights detected in area"
            } else {
                return "Monitoring \(flights.count) flight\(flights.count == 1 ? "" : "s")"
            }
        case .error(let message):
            return "Error: \(message)"
        case .rateLimited:
            return "Rate limited - reducing query frequency"
        }
    }
    
    /// Returns formatted last update time
    var lastUpdateDescription: String {
        guard let lastUpdate = lastUpdateTime else {
            return "Never updated"
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "Last updated: \(formatter.string(from: lastUpdate))"
    }
    
    // MARK: - Private Properties
    
    private let flightService: FlightServiceProtocol
    let settingsManager: any SettingsManagerProtocol
    let locationManager: any LocationManagerProtocol
    private let predictionService = AircraftPredictionService()
    private var cancellables = Set<AnyCancellable>()
    private var flightCycleTimer: Timer?
    @Published var currentAircraftIndex: Int = 0
    private var manuallySelectedFlightId: String?
    
    // MARK: - Aircraft Lock Properties
    @Published var isAircraftLocked: Bool = false
    private var lockedFlightId: String?
    private var lockedFlightData: FlightData?
    
    // MARK: - Search Properties
    @Published var searchText: String = ""
    @Published var searchResults: [FlightData] = []
    @Published var isSearching: Bool = false
    
    // MARK: - Initialization
    
    init(flightService: FlightServiceProtocol,
         settingsManager: any SettingsManagerProtocol,
         locationManager: any LocationManagerProtocol) {
        self.flightService = flightService
        self.settingsManager = settingsManager
        self.locationManager = locationManager
        
        setupBindings()
        loadInitialSettings()
        startMonitoringAutomatically()
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring flights in the configured area
    func startMonitoring() {
        guard let bounds = currentBounds else {
            setError("No geographic bounds configured")
            return
        }
        
        guard bounds.isValid else {
            setError("Invalid geographic bounds")
            return
        }
        
        clearError()
        isLoading = true
        
        flightService.startMonitoring(bounds: bounds)
    }
    
    /// Stops monitoring flights
    func stopMonitoring() {
        flightService.stopMonitoring()
        stopFlightCycling()
        clearError()
        isLoading = false
    }
    
    /// Toggles monitoring state
    func toggleMonitoring() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    /// Updates the geographic bounds for monitoring
    func updateBounds(_ bounds: GeographicBounds) {
        guard bounds.isValid else {
            setError("Invalid geographic bounds")
            return
        }
        
        currentBounds = bounds
        settingsManager.geographicBounds = bounds
        updateFilteredFlights()
        
        // Update prediction service with new user location
        predictionService.updateUserLocation(userLocation)
        
        // If currently monitoring, restart with new bounds
        if isMonitoring {
            flightService.updateBounds(bounds)
        }
        
        clearError()
    }
    
    /// Requests location permission and sets bounds based on current location
    func requestLocationAndSetBounds() {
        Task {
            do {
                locationManager.requestLocationPermission()
                
                // Wait for permission to be granted
                try await waitForLocationPermission()
                
                let location = try await locationManager.getCurrentLocation()
                let bounds = createBoundsAroundLocation(location)
                
                await MainActor.run {
                    updateBounds(bounds)
                }
                
            } catch {
                await MainActor.run {
                    setError("Failed to get location: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Manually refreshes flight data
    func refreshFlightData() {
        guard isMonitoring else { return }
        
        isLoading = true
        clearError()
        
        // Trigger a manual refresh through the flight service
        if let flightService = flightService as? FlightService {
            Task {
                await flightService.triggerFlightFetch()
            }
        }
    }
    
    /// Refreshes flight data and restarts monitoring with current settings
    func refreshFlightDataWithSettings() {
        clearError()
        
        if isMonitoring {
            // If currently monitoring, restart with current settings
            if let bounds = currentBounds, bounds.isValid {
                isLoading = true
                flightService.updateBounds(bounds)
                
                // Trigger immediate refresh
                if let flightService = flightService as? FlightService {
                    Task {
                        await flightService.triggerFlightFetch()
                    }
                }
            }
        } else {
            // If not monitoring, try to start if we have valid bounds
            if let bounds = currentBounds, bounds.isValid {
                startMonitoring()
            }
        }
    }
    
    /// Pauses monitoring (for background mode)
    func pauseMonitoring() {
        flightService.pauseMonitoring()
        stopFlightCycling()
    }
    
    /// Resumes monitoring (for foreground mode)
    func resumeMonitoring() {
        flightService.resumeMonitoring()
        
        // Only restart flight cycling if auto-focus is enabled and no manual selection
        if hasMultipleFlights && autoFocusNearest && manuallySelectedFlightId == nil {
            startFlightCycling()
        }
    }
    
    /// Handles connection status changes with appropriate user feedback
    func handleConnectionStatusChange(_ status: ConnectionStatus) {
        connectionStatus = status
        
        switch status {
        case .connected:
            clearError()
            isLoading = false
        case .connecting:
            isLoading = true
            clearError()
        case .disconnected:
            isLoading = false
            clearError()
        case .error(let message):
            isLoading = false
            setError(message)
        case .rateLimited:
            isLoading = false
            setError("API rate limit exceeded - reducing query frequency")
        }
    }
    
    /// Validates the current configuration before starting monitoring
    func validateConfiguration() -> Bool {
        guard let bounds = currentBounds else {
            setError("No geographic bounds configured")
            return false
        }
        
        guard bounds.isValid else {
            setError("Invalid geographic bounds")
            return false
        }
        
        return true
    }
    
    /// Cycles to the next flight in the list (deprecated - use selectNextAircraft instead)
    func cycleToNextFlight() {
        selectNextAircraft()
    }
    
    /// Starts automatic flight cycling for multiple flights
    func startFlightCycling(interval: TimeInterval = 5.0) {
        stopFlightCycling()
        
        guard hasMultipleFlights else { return }
        
        flightCycleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cycleToNextFlight()
            }
        }
    }
    
    /// Stops automatic flight cycling
    func stopFlightCycling() {
        flightCycleTimer?.invalidate()
        flightCycleTimer = nil
        currentAircraftIndex = 0
    }
    

    
    /// Navigate to the next aircraft (swipe left)
    func selectNextAircraft() {
        // Don't change selection if aircraft is locked
        guard !isAircraftLocked else { return }
        
        let sorted = sortedFlights
        guard sorted.count > 0 else { return }
        currentAircraftIndex = (currentAircraftIndex + 1) % sorted.count
        
        // Mark as manually selected when auto-focus is disabled
        if !autoFocusNearest, let selectedFlight = currentFlight {
            manuallySelectedFlightId = selectedFlight.id
        }
    }
    
    /// Navigate to the previous aircraft (swipe right)
    func selectPreviousAircraft() {
        // Don't change selection if aircraft is locked
        guard !isAircraftLocked else { return }
        
        let sorted = sortedFlights
        guard sorted.count > 0 else { return }
        currentAircraftIndex = currentAircraftIndex > 0 ? currentAircraftIndex - 1 : sorted.count - 1
        
        // Mark as manually selected when auto-focus is disabled
        if !autoFocusNearest, let selectedFlight = currentFlight {
            manuallySelectedFlightId = selectedFlight.id
        }
    }
    
    /// Select a specific aircraft by its flight data
    func selectAircraft(_ flight: FlightData) {
        // Don't change selection if aircraft is locked
        guard !isAircraftLocked else { return }
        
        let sorted = sortedFlights
        if let index = sorted.firstIndex(where: { $0.id == flight.id }) {
            currentAircraftIndex = index
            
            // Mark as manually selected when auto-focus is disabled
            if !autoFocusNearest {
                manuallySelectedFlightId = flight.id
            }
        }
    }
    
    /// Reset aircraft selection only when flight list actually changes (not just data updates)
    private func resetAircraftSelectionIfNeeded(previousFlights: [FlightData], newFlights: [FlightData]) {
        // Create sets of flight IDs to compare
        let previousIds = Set(previousFlights.map { $0.id })
        let newIds = Set(newFlights.map { $0.id })
        
        // Only reset selection if:
        // 1. Flight list changed (aircraft added/removed)
        // 2. Current aircraft is no longer in the list
        // 3. We have no current aircraft selection
        
        let flightListChanged = previousIds != newIds
        let currentFlightStillExists = currentFlight.map { newIds.contains($0.id) } ?? false
        let hasNoCurrentSelection = currentFlight == nil
        
        if flightListChanged || !currentFlightStillExists || hasNoCurrentSelection {
            resetAircraftSelection()
        } else {
            // Just update the index for the same aircraft (in case sort order changed)
            updateCurrentAircraftIndex()
        }
    }
    
    /// Update the current aircraft index without changing the selected aircraft
    private func updateCurrentAircraftIndex() {
        guard let currentFlight = currentFlight else { return }
        let sorted = sortedFlights
        
        if let newIndex = sorted.firstIndex(where: { $0.id == currentFlight.id }) {
            currentAircraftIndex = newIndex
        }
    }

    /// Reset aircraft selection when flights change or aircraft goes out of range
    func resetAircraftSelection() {
        let sorted = sortedFlights
        
        // If aircraft is locked, try to maintain focus on locked aircraft
        if isAircraftLocked, let lockedId = lockedFlightId {
            if let lockedIndex = sorted.firstIndex(where: { $0.id == lockedId }) {
                // Locked aircraft still in range, keep it focused
                currentAircraftIndex = lockedIndex
                return
            } else {
                // Locked aircraft out of range, unlock and proceed with normal logic
                unlockAircraft()
            }
        }
        
        if autoFocusNearest {
            // Auto-focus enabled: always focus on nearest aircraft
            if let currentFlight = currentFlight,
               sorted.contains(where: { $0.id == currentFlight.id }) {
                // Current aircraft still in range, update index if needed
                if let newIndex = sorted.firstIndex(where: { $0.id == currentFlight.id }) {
                    currentAircraftIndex = newIndex
                }
            } else {
                // Current aircraft out of range, select closest aircraft
                currentAircraftIndex = 0
                manuallySelectedFlightId = nil // Clear manual selection
            }
        } else {
            // Auto-focus disabled: maintain focus on manually selected aircraft
            if let manuallySelectedId = manuallySelectedFlightId,
               let manualIndex = sorted.firstIndex(where: { $0.id == manuallySelectedId }) {
                // Manually selected aircraft still in range, keep it focused
                currentAircraftIndex = manualIndex
            } else if let currentFlight = currentFlight,
                      sorted.contains(where: { $0.id == currentFlight.id }),
                      let newIndex = sorted.firstIndex(where: { $0.id == currentFlight.id }) {
                // Current aircraft still in range, update index
                currentAircraftIndex = newIndex
            } else {
                // Current aircraft out of range and no manual selection, focus on nearest
                currentAircraftIndex = 0
                manuallySelectedFlightId = nil
            }
        }
    }
    
    /// Shows the settings menu
    func showSettings() {
        NotificationCenter.default.post(name: .showSettingsFromSwipe, object: nil)
    }
    
    // MARK: - Search Methods
    
    /// Shows the search interface
    func showSearch() {
        NotificationCenter.default.post(name: .showSearchFromSwipe, object: nil)
    }
    

    
    /// Performs search on flights based on search text
    func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }
        
        let searchTerm = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First, search in local flight data
        let localResults = allFlights.filter { flight in
            // Search in flight number
            if let flightNumber = flight.flightNumber?.lowercased(),
               flightNumber.contains(searchTerm) {
                return true
            }
            
            // Search in callsign
            if let callsign = flight.callsign?.lowercased(),
               callsign.contains(searchTerm) {
                return true
            }
            
            // Search in airline name
            if let airlineName = flight.airline?.name.lowercased(),
               airlineName.contains(searchTerm) {
                return true
            }
            
            // Search in airline code
            if let airlineCode = flight.airline?.code?.lowercased(),
               airlineCode.contains(searchTerm) {
                return true
            }
            
            // Search in aircraft model
            if let aircraftModel = flight.aircraft?.model.lowercased(),
               aircraftModel.contains(searchTerm) {
                return true
            }
            
            // Search in aircraft code
            if let aircraftCode = flight.aircraft?.code.lowercased(),
               aircraftCode.contains(searchTerm) {
                return true
            }
            
            // Search in aircraft registration
            if let registration = flight.aircraft?.registration?.lowercased(),
               registration.contains(searchTerm) {
                return true
            }
            
            // Search in route (origin and destination)
            if let route = flight.route {
                let originCode = route.origin.iataCode.lowercased()
                let originName = route.origin.name.lowercased()
                let destCode = route.destination.iataCode.lowercased()
                let destName = route.destination.name.lowercased()
                
                if originCode.contains(searchTerm) || originName.contains(searchTerm) ||
                   destCode.contains(searchTerm) || destName.contains(searchTerm) {
                    return true
                }
            }
            
            return false
        }
        
        searchResults = localResults
        
        // If no local results found and search term looks like a flight number, try API search
        if localResults.isEmpty && isLikelyFlightNumber(searchTerm) {
            Task {
                await searchFlightViaAPI(searchTerm)
            }
        }
    }
    
    /// Determines if a search term looks like a flight number
    private func isLikelyFlightNumber(_ searchTerm: String) -> Bool {
        // Flight numbers typically have 2-3 letters followed by 1-4 numbers
        let flightNumberPattern = "^[A-Za-z]{1,3}[0-9]{1,4}$"
        let regex = try? NSRegularExpression(pattern: flightNumberPattern)
        let range = NSRange(location: 0, length: searchTerm.count)
        return regex?.firstMatch(in: searchTerm, options: [], range: range) != nil
    }
    
    /// Searches for a flight via API when not found locally
    private func searchFlightViaAPI(_ flightNumber: String) async {
        await MainActor.run {
            isSearching = true
        }
        
        // Try to find the flight by searching through a broader area
        // Since we don't have a direct search API, we'll try to fetch flight details
        // This is a limitation of the FlightRadar24 API - it doesn't have a search endpoint

        // For now, we'll show a message that the flight wasn't found locally
        // In a real implementation, you might want to expand the search bounds
        // or use a different API that supports flight number search

        await MainActor.run {
            isSearching = false
            // Could add a message here about expanding search or trying different terms
        }
    }
    
    /// Selects a flight from search results
    func selectFlightFromSearch(_ flight: FlightData) {
        // First add the flight to our filtered flights if it's not already there
        if !flights.contains(where: { $0.id == flight.id }) {
            // Check if flight is within range or if we should add it anyway
            if let userLocation = userLocation,
               let distance = flight.distanceFromLocation(userLocation),
               distance <= settingsManager.radiusInMiles {
                // Flight is within range, it should already be in flights
                // This might happen due to timing - refresh filtered flights
                updateFilteredFlights()
            } else {
                // Flight is out of range, but user selected it from search
                // Add it temporarily to flights array
                flights.append(flight)
            }
        }
        
        // Select the aircraft
        selectAircraft(flight)
        
        // Lock the selected aircraft to keep it as the main focus
        lockCurrentAircraft()
        
        // Clear search after selection
        searchText = ""
        searchResults = []
    }
    
    /// Locks the current aircraft to prevent selection changes
    func lockCurrentAircraft() {
        guard let currentFlight = currentFlight else { return }
        isAircraftLocked = true
        lockedFlightId = currentFlight.id
        lockedFlightData = currentFlight
    }
    
    /// Unlocks the aircraft selection
    func unlockAircraft() {
        isAircraftLocked = false
        lockedFlightId = nil
        lockedFlightData = nil
        updateFilteredFlights() // Refresh flights to remove out-of-range locked aircraft
    }
    
    /// Toggles the aircraft lock state
    func toggleAircraftLock() {
        if isAircraftLocked {
            unlockAircraft()
        } else {
            lockCurrentAircraft()
        }
    }
    
    /// Clears any current error message
    func clearError() {
        errorMessage = nil
    }
    
    /// Sets an error message
    func setError(_ message: String) {
        errorMessage = message
    }
    
    // MARK: - Prediction Methods
    
    /// Gets the predicted bearing from user location to a specific flight
    func getPredictedBearing(for flight: FlightData) -> Double? {
        guard let userLocation = userLocation else { return nil }
        return predictionService.getPredictedBearing(for: flight.id, from: userLocation)
    }
    
    /// Gets the predicted distance from user location to a specific flight
    func getPredictedDistance(for flight: FlightData) -> Double? {
        guard let userLocation = userLocation else { return nil }
        return predictionService.getPredictedDistance(for: flight.id, from: userLocation)
    }
    
    /// Gets the predicted ETA to nearest point for a specific flight
    func getPredictedETA(for flight: FlightData) -> String? {
        guard let userLocation = userLocation else { return nil }
        return predictionService.getPredictedETA(for: flight.id, from: userLocation)
    }
    
    /// Gets the predicted nearest approach distance for a specific flight
    func getPredictedNearestApproach(for flight: FlightData) -> Double? {
        guard let userLocation = userLocation else { return nil }
        return predictionService.getPredictedNearestApproach(for: flight.id, to: userLocation)
    }
    
    /// Gets the predicted position for a specific flight
    func getPredictedPosition(for flight: FlightData) -> PredictedPosition? {
        return predictionService.getPredictedPosition(for: flight.id)
    }
    
    /// Returns formatted flight information for display
    func formatFlightInfo(_ flight: FlightData) -> FlightDisplayInfo {
        return FlightDisplayInfo(
            primaryIdentifier: flight.displayIdentifier,
            route: flight.routeDescription,
            aircraftInfo: flight.aircraftDescription,
            altitude: flight.position?.altitudeDescription ?? "Unknown",
            speed: flight.position?.speedDescription ?? "Unknown",
            lastUpdated: formatRelativeTime(flight.lastUpdated)
        )
    }
}

// MARK: - Private Methods
private extension MainViewModel {
    
    /// Sets up Combine bindings with services
    func setupBindings() {
        // Bind flight service properties
        if let observableFlightService = flightService as? FlightService {
            observableFlightService.$currentFlights
                .receive(on: DispatchQueue.main)
                .sink { [weak self] flights in
                    let previousFlights = self?.allFlights ?? []
                    self?.allFlights = flights
                    self?.lastUpdateTime = Date()
                    self?.isLoading = false
                    
                    // Update locked flight data if it's found in the new flights
                    self?.updateLockedFlightData(from: flights)
                    
                    // Only reset aircraft selection if flight list actually changed (not just updated)
                    self?.resetAircraftSelectionIfNeeded(previousFlights: previousFlights, newFlights: flights)
                }
                .store(in: &cancellables)
            
            observableFlightService.$connectionStatus
                .receive(on: DispatchQueue.main)
                .sink { [weak self] status in
                    self?.connectionStatus = status
                    self?.isLoading = status.isConnecting
                    
                    // Handle error states
                    if status.isError {
                        self?.setError(status.description)
                    } else {
                        self?.clearError()
                    }
                }
                .store(in: &cancellables)
            
            observableFlightService.$isMonitoring
                .receive(on: DispatchQueue.main)
                .sink { [weak self] monitoring in
                    self?.isMonitoring = monitoring
                }
                .store(in: &cancellables)
        }
        
        // Bind settings manager properties
        if let observableSettingsManager = settingsManager as? SettingsManager {
            observableSettingsManager.$geographicBounds
                .receive(on: DispatchQueue.main)
                .sink { [weak self] bounds in
                    self?.currentBounds = bounds
                    self?.updateFilteredFlights()
                    // Update prediction service with new user location when bounds change
                    self?.predictionService.updateUserLocation(self?.userLocation)
                }
                .store(in: &cancellables)
            
            observableSettingsManager.$radiusInMiles
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    // Update filtered flights when radius changes
                    self?.updateFilteredFlights()
                }
                .store(in: &cancellables)
        }
        
        // Bind location manager properties
        if let observableLocationManager = locationManager as? LocationManager {
            observableLocationManager.$authorizationStatus
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    // Handle authorization status changes if needed
                }
                .store(in: &cancellables)
        }
    }
    
    /// Loads initial settings from the settings manager
    func loadInitialSettings() {
        currentBounds = settingsManager.geographicBounds
        updateFilteredFlights()
    }
    
    /// Automatically starts monitoring if valid geographic bounds are configured
    func startMonitoringAutomatically() {
        // Only start monitoring if we have valid bounds configured
        if let bounds = currentBounds, bounds.isValid {
            // Add a small delay to ensure all initialization is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startMonitoring()
            }
        }
    }
    
    /// Waits for location permission to be granted or denied
    func waitForLocationPermission() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            
            if let observableLocationManager = locationManager as? LocationManager {
                cancellable = observableLocationManager.$authorizationStatus
                    .sink { status in
                        switch status {
                        #if os(iOS)
                        case .authorizedWhenInUse, .authorizedAlways:
                            cancellable?.cancel()
                            continuation.resume()
                        case .denied, .restricted:
                            cancellable?.cancel()
                            continuation.resume(throwing: LocationError.permissionDenied)
                        case .notDetermined:
                            // Keep waiting
                            break
                        #elseif os(macOS)
                        case .authorizedAlways:
                            cancellable?.cancel()
                            continuation.resume()
                        case .denied, .restricted:
                            cancellable?.cancel()
                            continuation.resume(throwing: LocationError.permissionDenied)
                        case .notDetermined:
                            // Keep waiting
                            break
                        #elseif os(tvOS)
                        // tvOS doesn't support location services - all cases should fail
                        case .denied, .restricted, .notDetermined, .authorizedAlways, .authorizedWhenInUse:
                            cancellable?.cancel()
                            continuation.resume(throwing: LocationError.permissionDenied)
                        #else
                        case .authorizedAlways:
                            cancellable?.cancel()
                            continuation.resume()
                        case .denied, .restricted:
                            cancellable?.cancel()
                            continuation.resume(throwing: LocationError.permissionDenied)
                        case .notDetermined:
                            // Keep waiting
                            break
                        #endif
                        @unknown default:
                            cancellable?.cancel()
                            continuation.resume(throwing: LocationError.locationServicesDisabled)
                        }
                    }

            } else {
                continuation.resume(throwing: LocationError.locationServicesDisabled)
            }
        }
    }
    
    /// Creates geographic bounds around a given location
    func createBoundsAroundLocation(_ location: CLLocation, radiusKm: Double = 50.0) -> GeographicBounds {
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
    
    /// Fetches updated details for a locked aircraft that's out of range
    func fetchLockedAircraftDetails(flightId: String) async {
        do {
            let response = try await flightService.fetchFlightDetails(flightId: flightId)
            
            // Parse the flight details response
            if let updatedFlight = parseFlightDetailsResponse(response, flightId: flightId) {
                await MainActor.run {
                    lockedFlightData = updatedFlight
                    updateFilteredFlights()
                }
            }
        } catch {
            // If we can't fetch updated details, keep the existing locked flight data
            print("Failed to fetch locked aircraft details: \(error)")
        }
    }
    
    /// Parses flight details response into FlightData
    func parseFlightDetailsResponse(_ response: [String: Any], flightId: String) -> FlightData? {
        // This is a simplified parser - you may need to adjust based on the actual API response format
        // The FlightRadar24 details API returns different structure than the bounds API
        
        guard let flightNumber = response["identification"] as? [String: Any],
              let callsign = flightNumber["callsign"] as? String else {
            return nil
        }
        
        // Extract position data
        var position: FlightPosition?
        if let trail = response["trail"] as? [[Any]], let lastPoint = trail.last, lastPoint.count >= 4 {
            let latitude = lastPoint[1] as? Double ?? 0
            let longitude = lastPoint[2] as? Double ?? 0
            let altitude = lastPoint[3] as? Int
            let speed = response["speed"] as? Int
            let heading = response["track"] as? Int
            
            position = FlightPosition(
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speed: speed,
                heading: heading
            )
        }
        
        // Extract aircraft data
        var aircraft: AircraftInfo?
        if let aircraftInfo = response["aircraft"] as? [String: Any] {
            let model = aircraftInfo["model"] as? String ?? ""
            let code = aircraftInfo["code"] as? String ?? ""
            let registration = aircraftInfo["registration"] as? String ?? ""
            
            aircraft = AircraftInfo(
                model: model,
                code: code,
                registration: registration,
                photoURL: nil
            )
        }
        
        // Extract route data
        var route: RouteInfo?
        if let airport = response["airport"] as? [String: Any],
           let origin = airport["origin"] as? [String: Any],
           let destination = airport["destination"] as? [String: Any] {
            
            let originCode = origin["code"] as? [String: Any]
            let destCode = destination["code"] as? [String: Any]
            
            let originIATA = originCode?["iata"] as? String ?? ""
            let destIATA = destCode?["iata"] as? String ?? ""
            
            route = RouteInfo(
                origin: AirportInfo(name: "", iataCode: originIATA),
                destination: AirportInfo(name: "", iataCode: destIATA)
            )
        }
        
        return FlightData(
            id: flightId,
            flightNumber: callsign,
            callsign: callsign,
            airline: nil,
            aircraft: aircraft,
            route: route,
            position: position,
            lastUpdated: Date()
        )
    }
    
    /// Updates locked flight data if the locked aircraft is found in the regular API response
    func updateLockedFlightData(from flights: [FlightData]) {
        guard isAircraftLocked, let lockedId = lockedFlightId else { return }
        
        // If the locked aircraft is found in the regular response, update our stored data
        if let updatedFlight = flights.first(where: { $0.id == lockedId }) {
            lockedFlightData = updatedFlight
        }
    }
    
    /// Formats a date as a relative time string
    func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Types

struct FlightDisplayInfo {
    let primaryIdentifier: String
    let route: String
    let aircraftInfo: String
    let altitude: String
    let speed: String
    let lastUpdated: String
}

// MARK: - Preview Support
#if DEBUG
extension MainViewModel {
    static func preview(withFlights: Bool = true, withMultipleFlights: Bool = false) -> MainViewModel {
        // Create simple mock services for previews
        let networkManager = NetworkManager()
        let flightService = FlightService(networkManager: networkManager)
        let settingsManager = SettingsManager()
        let locationManager = LocationManager()
        
        let viewModel = MainViewModel(
            flightService: flightService,
            settingsManager: settingsManager,
            locationManager: locationManager
        )
        
        // Manually set preview data
        if withFlights {
            if withMultipleFlights {
                viewModel.allFlights = [
                    FlightData.mockFlight1,
                    FlightData.mockFlight2,
                    FlightData.mockFlight3
                ]
            } else {
                viewModel.allFlights = [FlightData.mockFlight1]
            }
            viewModel.connectionStatus = .connected
            viewModel.isMonitoring = true
            viewModel.lastUpdateTime = Date()
        } else {
            viewModel.allFlights = []
            viewModel.connectionStatus = .connected
            viewModel.isMonitoring = true
        }
        
        return viewModel
    }
}
#endif

// MARK: - Notification Names
extension Notification.Name {
    static let showSettingsFromSwipe = Notification.Name("showSettingsFromSwipe")
    static let showSearchFromSwipe = Notification.Name("showSearchFromSwipe")
}

