// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  FlightService.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import Combine

// MARK: - Flight Service Protocol
protocol FlightServiceProtocol {
    func startMonitoring(bounds: GeographicBounds)
    func stopMonitoring()
    func pauseMonitoring()
    func resumeMonitoring()
    func updateBounds(_ bounds: GeographicBounds)
    func fetchFlightDetails(flightId: String) async throws -> [String: Any]
    func fetchFlights(in bounds: GeographicBounds) async throws -> [FlightData]
    var currentFlights: [FlightData] { get }
    var connectionStatus: ConnectionStatus { get }
    var isMonitoring: Bool { get }
}

// MARK: - Flight Service Implementation
class FlightService: FlightServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentFlights: [FlightData] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isMonitoring: Bool = false
    
    // MARK: - Private Properties
    private let networkManager: NetworkManagerProtocol
    private var monitoringTimer: Timer?
    private var currentBounds: GeographicBounds?
    private var retryCount: Int = 0
    private var maxRetries: Int = 5
    private var baseRetryDelay: TimeInterval = 1.0
    private var queryInterval: TimeInterval = 30.0
    private var previousFlightIds: Set<String> = []
    private var isPaused: Bool = false
    
    // MARK: - Initialization
    init(networkManager: NetworkManagerProtocol) {
        self.networkManager = networkManager
    }
    
    // MARK: - Public Methods
    
    /// Starts monitoring flights within the specified bounds
    func startMonitoring(bounds: GeographicBounds) {
        stopMonitoring() // Stop any existing monitoring
        
        currentBounds = bounds
        isMonitoring = true
        connectionStatus = .connecting
        retryCount = 0
        
        // Start the monitoring timer
        startMonitoringTimer()
        
        // Perform initial fetch
        Task {
            await fetchFlights()
        }
    }
    
    /// Stops flight monitoring
    func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false
        isPaused = false
        connectionStatus = .disconnected
        retryCount = 0
        currentFlights = []
        previousFlightIds = []
    }
    
    /// Updates the monitoring bounds
    func updateBounds(_ bounds: GeographicBounds) {
        currentBounds = bounds
        
        // If currently monitoring, restart with new bounds
        if isMonitoring {
            startMonitoring(bounds: bounds)
        }
    }
    
    /// Pauses monitoring without clearing state (for background mode)
    func pauseMonitoring() {
        guard isMonitoring && !isPaused else { return }
        
        isPaused = true
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        connectionStatus = .disconnected
    }
    
    /// Resumes monitoring if it was previously active (for foreground mode)
    func resumeMonitoring() {
        guard isMonitoring && isPaused else { return }
        
        isPaused = false
        connectionStatus = .connecting
        startMonitoringTimer()
        
        // Perform immediate fetch when resuming
        Task {
            await fetchFlights()
        }
    }
    
    /// Manually triggers a flight fetch (primarily for testing)
    func triggerFlightFetch() async {
        await fetchFlights()
    }
    
    /// Fetches detailed information for a specific flight
    func fetchFlightDetails(flightId: String) async throws -> [String: Any] {
        return try await networkManager.fetchFlightDetails(flightId: flightId)
    }
    
    /// Fetches flights within specific geographic bounds
    func fetchFlights(in bounds: GeographicBounds) async throws -> [FlightData] {
        let response = try await networkManager.fetchFlightsInBounds(bounds)
        return parseFlightData(from: response)
    }
}

// MARK: - Private Methods
private extension FlightService {
    
    /// Starts the monitoring timer with the current query interval
    func startMonitoringTimer() {
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: queryInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchFlights()
            }
        }
    }
    
    /// Fetches flights from the API and processes the response
    @MainActor
    func fetchFlights() async {
        guard let bounds = currentBounds else {
            connectionStatus = .error("No bounds configured")
            return
        }
        
        do {
            // Update connection status to connecting if not already connected
            if connectionStatus != .connected {
                connectionStatus = .connecting
            }
            
            // Fetch flight data from API
            let response = try await networkManager.fetchFlightsInBounds(bounds)
            
            // Parse and process flight data
            let flights = parseFlightData(from: response)
            
            // Detect new flights and update current flights
            let newFlights = detectNewFlights(flights)
            currentFlights = flights
            
            // Update connection status and reset retry count
            connectionStatus = .connected
            retryCount = 0
            
            // Log new flights detected (for debugging)
            if !newFlights.isEmpty {
                print("Detected \(newFlights.count) new flights: \(newFlights.map { $0.displayIdentifier })")
            }
            
        } catch NetworkError.rateLimited {
            connectionStatus = .rateLimited
            await handleRetryWithBackoff()
            
        } catch {
            let errorMessage = error.localizedDescription
            connectionStatus = .error(errorMessage)
            await handleRetryWithBackoff()
        }
    }
    
    /// Handles retry logic with exponential backoff
    func handleRetryWithBackoff() async {
        guard retryCount < maxRetries else {
            // Max retries reached, stop monitoring
            await MainActor.run {
                stopMonitoring()
            }
            return
        }
        
        retryCount += 1
        let delay = baseRetryDelay * pow(2.0, Double(retryCount - 1))
        
        // Wait for the calculated delay before retrying
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        // Retry the fetch
        await fetchFlights()
    }
    
    /// Parses flight data from the API response
    func parseFlightData(from response: [String: Any]) -> [FlightData] {
        var flights: [FlightData] = []
        
        // The FlightRadar24 API returns flight data in a specific format
        // Each flight is keyed by its ID and contains an array of data
        for (flightId, flightInfo) in response {
            // Skip non-flight entries (stats, version, etc.)
            guard flightId != "full_count" && flightId != "version" else { continue }
            
            // Parse flight data array
            if let flightArray = flightInfo as? [Any], flightArray.count >= 13 {
                if let flight = parseFlightFromArray(id: flightId, data: flightArray) {
                    flights.append(flight)
                }
            }
        }
        
        return flights
    }
    
    /// Parses a single flight from the API data array
    func parseFlightFromArray(id: String, data: [Any]) -> FlightData? {
        // FlightRadar24 API data format:
        // [0] = ICAO24 hex code
        // [1] = Latitude
        // [2] = Longitude
        // [3] = Track (heading)
        // [4] = Altitude
        // [5] = Speed
        // [6] = Squawk
        // [7] = Radar
        // [8] = Aircraft model
        // [9] = Registration
        // [10] = Timestamp
        // [11] = Origin airport
        // [12] = Destination airport
        // [13] = Flight number
        // [14] = On ground flag
        // [15] = Vertical speed
        // [16] = Callsign
        // [17] = Source
        
        guard data.count >= 13 else { return nil }
        
        // Extract basic position data
        guard let latitude = data[1] as? Double,
              let longitude = data[2] as? Double else {
            return nil
        }
        
        // Create flight position
        let position = FlightPosition(
            latitude: latitude,
            longitude: longitude,
            altitude: data[4] as? Int,
            speed: data[5] as? Int,
            heading: data[3] as? Int
        )
        
        // Validate position
        guard position.isValid else { return nil }
        
        // Extract flight identifiers
        let callsign = data.count > 16 ? data[16] as? String : nil
        let flightNumber = data.count > 13 ? data[13] as? String : nil
        
        // Extract aircraft information
        let aircraftModel = data[8] as? String ?? "Unknown"
        let registration = data[9] as? String
        let aircraft = AircraftInfo(
            model: aircraftModel,
            code: aircraftModel,
            registration: registration
        )
        
        // Extract route information if available
        var route: RouteInfo?
        if let originCode = data[11] as? String,
           let destinationCode = data[12] as? String,
           !originCode.isEmpty && !destinationCode.isEmpty {
            
            // Look up airport names from the database
            let originName = AirportDatabase.shared.getAirportNameWithFallback(for: originCode)
            let destinationName = AirportDatabase.shared.getAirportNameWithFallback(for: destinationCode)
            
            let origin = AirportInfo(name: originName, iataCode: originCode)
            let destination = AirportInfo(name: destinationName, iataCode: destinationCode)
            route = RouteInfo(origin: origin, destination: destination)
        }
        
        return FlightData(
            id: id,
            flightNumber: flightNumber,
            callsign: callsign,
            airline: nil, // Will be populated when fetching detailed flight info
            aircraft: aircraft,
            route: route,
            position: position,
            lastUpdated: Date()
        )
    }
    
    /// Detects new flights that have entered the monitored area
    func detectNewFlights(_ flights: [FlightData]) -> [FlightData] {
        let currentFlightIds = Set(flights.map { $0.id })
        let newFlightIds = currentFlightIds.subtracting(previousFlightIds)
        
        // Update previous flight IDs for next comparison
        previousFlightIds = currentFlightIds
        
        // Return flights that are new
        return flights.filter { newFlightIds.contains($0.id) }
    }
}
#endif
