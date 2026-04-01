//
//  MainViewModelTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import Combine
import CoreLocation
@testable import WhatTheFlight

@MainActor
final class MainViewModelTests: XCTestCase {
    
    var viewModel: MainViewModel!
    var mockFlightService: MockFlightService!
    var mockSettingsManager: MockSettingsManager!
    var mockLocationManager: MockLocationManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        
        mockFlightService = MockFlightService()
        mockSettingsManager = MockSettingsManager()
        mockLocationManager = MockLocationManager()
        cancellables = Set<AnyCancellable>()
        
        viewModel = MainViewModel(
            flightService: mockFlightService,
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
    }
    
    override func tearDown() {
        cancellables = nil
        viewModel = nil
        mockLocationManager = nil
        mockSettingsManager = nil
        mockFlightService = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        XCTAssertEqual(viewModel.flights.count, 0)
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertNil(viewModel.currentBounds)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testInitializationWithExistingBounds() {
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        mockSettingsManager.geographicBounds = bounds
        
        let newViewModel = MainViewModel(
            flightService: mockFlightService,
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
        
        XCTAssertEqual(newViewModel.currentBounds, bounds)
    }
    
    // MARK: - Computed Properties Tests
    
    func testCurrentFlightWithNoFlights() {
        XCTAssertNil(viewModel.currentFlight)
    }
    
    func testCurrentFlightWithFlights() {
        let flight = createTestFlight(id: "test1")
        viewModel.flights = [flight]
        
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
    }
    
    func testFlightCount() {
        XCTAssertEqual(viewModel.flightCount, 0)
        
        viewModel.flights = [createTestFlight(id: "test1")]
        XCTAssertEqual(viewModel.flightCount, 1)
        
        viewModel.flights = [
            createTestFlight(id: "test1"),
            createTestFlight(id: "test2")
        ]
        XCTAssertEqual(viewModel.flightCount, 2)
    }
    
    func testHasMultipleFlights() {
        XCTAssertFalse(viewModel.hasMultipleFlights)
        
        viewModel.flights = [createTestFlight(id: "test1")]
        XCTAssertFalse(viewModel.hasMultipleFlights)
        
        viewModel.flights = [
            createTestFlight(id: "test1"),
            createTestFlight(id: "test2")
        ]
        XCTAssertTrue(viewModel.hasMultipleFlights)
    }
    
    func testStatusMessage() {
        // Loading state
        viewModel.isLoading = true
        XCTAssertEqual(viewModel.statusMessage, "Loading...")
        
        viewModel.isLoading = false
        
        // Disconnected state
        viewModel.connectionStatus = .disconnected
        viewModel.isMonitoring = false
        XCTAssertEqual(viewModel.statusMessage, "Not monitoring")
        
        viewModel.isMonitoring = true
        XCTAssertEqual(viewModel.statusMessage, "Starting monitoring...")
        
        // Connecting state
        viewModel.connectionStatus = .connecting
        XCTAssertEqual(viewModel.statusMessage, "Connecting to flight data...")
        
        // Connected with no flights
        viewModel.connectionStatus = .connected
        viewModel.flights = []
        XCTAssertEqual(viewModel.statusMessage, "No flights detected in area")
        
        // Connected with flights
        viewModel.flights = [createTestFlight(id: "test1")]
        XCTAssertEqual(viewModel.statusMessage, "Monitoring 1 flight")
        
        viewModel.flights = [
            createTestFlight(id: "test1"),
            createTestFlight(id: "test2")
        ]
        XCTAssertEqual(viewModel.statusMessage, "Monitoring 2 flights")
        
        // Error state
        viewModel.connectionStatus = .error("Test error")
        XCTAssertEqual(viewModel.statusMessage, "Error: Test error")
        
        // Rate limited state
        viewModel.connectionStatus = .rateLimited
        XCTAssertEqual(viewModel.statusMessage, "Rate limited - reducing query frequency")
    }
    
    // MARK: - Monitoring Tests
    
    func testStartMonitoringWithValidBounds() {
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.currentBounds = bounds
        
        viewModel.startMonitoring()
        
        XCTAssertTrue(mockFlightService.startMonitoringCalled)
        XCTAssertEqual(mockFlightService.lastBounds, bounds)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testStartMonitoringWithNoBounds() {
        viewModel.currentBounds = nil
        
        viewModel.startMonitoring()
        
        XCTAssertFalse(mockFlightService.startMonitoringCalled)
        XCTAssertEqual(viewModel.errorMessage, "No geographic bounds configured")
    }
    
    func testStartMonitoringWithInvalidBounds() {
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0, // Invalid: north < south
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.currentBounds = invalidBounds
        
        viewModel.startMonitoring()
        
        XCTAssertFalse(mockFlightService.startMonitoringCalled)
        XCTAssertEqual(viewModel.errorMessage, "Invalid geographic bounds")
    }
    
    func testStopMonitoring() {
        viewModel.isLoading = true
        viewModel.setError("Test error")
        
        viewModel.stopMonitoring()
        
        XCTAssertTrue(mockFlightService.stopMonitoringCalled)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testToggleMonitoring() {
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.currentBounds = bounds
        
        // Start monitoring
        viewModel.isMonitoring = false
        viewModel.toggleMonitoring()
        XCTAssertTrue(mockFlightService.startMonitoringCalled)
        
        // Stop monitoring
        mockFlightService.isMonitoring = true
        viewModel.isMonitoring = true
        viewModel.toggleMonitoring()
        XCTAssertTrue(mockFlightService.stopMonitoringCalled)
    }
    
    // MARK: - Bounds Update Tests
    
    func testUpdateBoundsWithValidBounds() {
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        viewModel.updateBounds(bounds)
        
        XCTAssertEqual(viewModel.currentBounds, bounds)
        XCTAssertEqual(mockSettingsManager.geographicBounds, bounds)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testUpdateBoundsWithInvalidBounds() {
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0, // Invalid: north < south
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        viewModel.updateBounds(invalidBounds)
        
        XCTAssertNotEqual(viewModel.currentBounds, invalidBounds)
        XCTAssertEqual(viewModel.errorMessage, "Invalid geographic bounds")
    }
    
    func testUpdateBoundsWhileMonitoring() {
        let bounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        mockFlightService.isMonitoring = true
        viewModel.isMonitoring = true
        
        viewModel.updateBounds(bounds)
        
        XCTAssertTrue(mockFlightService.updateBoundsCalled)
        XCTAssertEqual(mockFlightService.lastBounds, bounds)
    }
    
    // MARK: - Location Tests
    
    func testRequestLocationAndSetBounds() async {
        let testLocation = CLLocation(latitude: 40.7128, longitude: -74.0060)
        mockLocationManager.mockLocation = testLocation
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        
        let expectation = XCTestExpectation(description: "Location request completed")
        
        viewModel.requestLocationAndSetBounds()
        
        // Wait a bit for async operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockLocationManager.requestLocationPermissionCalled)
            XCTAssertNotNil(self.viewModel.currentBounds)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    func testRequestLocationAndSetBoundsWithError() async {
        mockLocationManager.shouldThrowError = true
        mockLocationManager.authorizationStatus = MockLocationManager.authorizedStatus
        
        let expectation = XCTestExpectation(description: "Location request failed")
        
        viewModel.requestLocationAndSetBounds()
        
        // Wait a bit for async operations
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNotNil(self.viewModel.errorMessage)
            XCTAssertTrue(self.viewModel.errorMessage?.contains("Failed to get location") ?? false)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Flight Cycling Tests
    
    func testCycleToNextFlightWithMultipleFlights() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        let flight3 = createTestFlight(id: "test3", flightNumber: "DL789")
        
        viewModel.flights = [flight1, flight2, flight3]
        
        // First cycle
        viewModel.cycleToNextFlight()
        XCTAssertEqual(viewModel.flights.first?.id, "test2")
        
        // Second cycle
        viewModel.cycleToNextFlight()
        XCTAssertEqual(viewModel.flights.first?.id, "test3")
        
        // Third cycle (should wrap around)
        viewModel.cycleToNextFlight()
        XCTAssertEqual(viewModel.flights.first?.id, "test1")
    }
    
    func testCycleToNextFlightWithSingleFlight() {
        let flight = createTestFlight(id: "test1")
        viewModel.flights = [flight]
        
        viewModel.cycleToNextFlight()
        
        // Should remain the same
        XCTAssertEqual(viewModel.flights.first?.id, "test1")
    }
    
    func testCycleToNextFlightWithNoFlights() {
        viewModel.flights = []
        
        viewModel.cycleToNextFlight()
        
        // Should remain empty
        XCTAssertTrue(viewModel.flights.isEmpty)
    }
    
    // MARK: - Error Handling Tests
    
    func testSetError() {
        viewModel.setError("Test error message")
        
        XCTAssertEqual(viewModel.errorMessage, "Test error message")
    }
    
    func testClearError() {
        viewModel.setError("Test error message")
        viewModel.clearError()
        
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Aircraft Lock Tests
    
    func testLockCurrentAircraft() {
        let flight = createTestFlight(id: "test1", flightNumber: "AA123")
        viewModel.flights = [flight]
        
        // Initially not locked
        XCTAssertFalse(viewModel.isAircraftLocked)
        
        // Lock the aircraft
        viewModel.lockCurrentAircraft()
        
        XCTAssertTrue(viewModel.isAircraftLocked)
    }
    
    func testLockCurrentAircraftWithNoFlight() {
        viewModel.flights = []
        
        // Try to lock when no flight is available
        viewModel.lockCurrentAircraft()
        
        // Should remain unlocked
        XCTAssertFalse(viewModel.isAircraftLocked)
    }
    
    func testUnlockAircraft() {
        let flight = createTestFlight(id: "test1", flightNumber: "AA123")
        viewModel.flights = [flight]
        
        // Lock first
        viewModel.lockCurrentAircraft()
        XCTAssertTrue(viewModel.isAircraftLocked)
        
        // Then unlock
        viewModel.unlockAircraft()
        XCTAssertFalse(viewModel.isAircraftLocked)
    }
    
    func testToggleAircraftLock() {
        let flight = createTestFlight(id: "test1", flightNumber: "AA123")
        viewModel.flights = [flight]
        
        // Initially not locked
        XCTAssertFalse(viewModel.isAircraftLocked)
        
        // Toggle to lock
        viewModel.toggleAircraftLock()
        XCTAssertTrue(viewModel.isAircraftLocked)
        
        // Toggle to unlock
        viewModel.toggleAircraftLock()
        XCTAssertFalse(viewModel.isAircraftLocked)
    }
    
    func testSelectAircraftWhenLocked() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        viewModel.flights = [flight1, flight2]
        
        // Lock the first aircraft
        viewModel.lockCurrentAircraft()
        XCTAssertTrue(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
        
        // Try to select the second aircraft
        viewModel.selectAircraft(flight2)
        
        // Should remain on the first aircraft due to lock
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
    }
    
    func testSelectAircraftWhenUnlocked() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        viewModel.flights = [flight1, flight2]
        
        // Ensure not locked
        XCTAssertFalse(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
        
        // Select the second aircraft
        viewModel.selectAircraft(flight2)
        
        // Should change to the second aircraft
        XCTAssertEqual(viewModel.currentFlight?.id, "test2")
    }
    
    func testSelectNextAircraftWhenLocked() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        viewModel.flights = [flight1, flight2]
        
        // Lock the first aircraft
        viewModel.lockCurrentAircraft()
        XCTAssertTrue(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
        
        // Try to select next aircraft
        viewModel.selectNextAircraft()
        
        // Should remain on the first aircraft due to lock
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
    }
    
    func testSelectPreviousAircraftWhenLocked() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        viewModel.flights = [flight1, flight2]
        viewModel.currentAircraftIndex = 1 // Start on second aircraft
        
        // Lock the second aircraft
        viewModel.lockCurrentAircraft()
        XCTAssertTrue(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test2")
        
        // Try to select previous aircraft
        viewModel.selectPreviousAircraft()
        
        // Should remain on the second aircraft due to lock
        XCTAssertEqual(viewModel.currentFlight?.id, "test2")
    }
    
    func testResetAircraftSelectionWithLockedAircraft() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        viewModel.flights = [flight1, flight2]
        
        // Lock the first aircraft
        viewModel.lockCurrentAircraft()
        XCTAssertTrue(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
        
        // Reset aircraft selection (simulating flight list update)
        viewModel.resetAircraftSelection()
        
        // Should maintain focus on locked aircraft
        XCTAssertTrue(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
    }
    
    func testResetAircraftSelectionWithLockedAircraftOutOfRange() {
        let flight1 = createTestFlight(id: "test1", flightNumber: "AA123")
        let flight2 = createTestFlight(id: "test2", flightNumber: "UA456")
        let flight3 = createTestFlight(id: "test3", flightNumber: "DL789")
        viewModel.flights = [flight1, flight2]
        
        // Lock the first aircraft
        viewModel.lockCurrentAircraft()
        XCTAssertTrue(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test1")
        
        // Update flights to remove the locked aircraft
        viewModel.flights = [flight3] // Only flight3 remains
        
        // Reset aircraft selection
        viewModel.resetAircraftSelection()
        
        // Should unlock and select available aircraft
        XCTAssertFalse(viewModel.isAircraftLocked)
        XCTAssertEqual(viewModel.currentFlight?.id, "test3")
    }
    
    // MARK: - Flight Display Info Tests
    
    func testFormatFlightInfo() {
        let flight = createTestFlight(
            id: "test1",
            flightNumber: "AA123",
            callsign: "AAL123"
        )
        
        let displayInfo = viewModel.formatFlightInfo(flight)
        
        XCTAssertEqual(displayInfo.primaryIdentifier, "AA123")
        XCTAssertEqual(displayInfo.route, "JFK → LAX")
        XCTAssertEqual(displayInfo.aircraftInfo, "American Airlines • Boeing 737")
        XCTAssertEqual(displayInfo.altitude, "35000 ft")
        XCTAssertEqual(displayInfo.speed, "450 kts")
    }
    
    // MARK: - Connection Status Handling Tests
    
    func testHandleConnectionStatusChange() {
        // Test connected status
        viewModel.handleConnectionStatusChange(.connected)
        XCTAssertEqual(viewModel.connectionStatus, .connected)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // Test connecting status
        viewModel.handleConnectionStatusChange(.connecting)
        XCTAssertEqual(viewModel.connectionStatus, .connecting)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // Test error status
        viewModel.handleConnectionStatusChange(.error("Test error"))
        XCTAssertEqual(viewModel.connectionStatus, .error("Test error"))
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "Test error")
        
        // Test rate limited status
        viewModel.handleConnectionStatusChange(.rateLimited)
        XCTAssertEqual(viewModel.connectionStatus, .rateLimited)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "API rate limit exceeded - reducing query frequency")
    }
    
    func testValidateConfiguration() {
        // Test with no bounds
        viewModel.currentBounds = nil
        XCTAssertFalse(viewModel.validateConfiguration())
        XCTAssertEqual(viewModel.errorMessage, "No geographic bounds configured")
        
        // Test with invalid bounds
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0, // Invalid: north < south
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.currentBounds = invalidBounds
        XCTAssertFalse(viewModel.validateConfiguration())
        XCTAssertEqual(viewModel.errorMessage, "Invalid geographic bounds")
        
        // Test with valid bounds
        let validBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        viewModel.currentBounds = validBounds
        XCTAssertTrue(viewModel.validateConfiguration())
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Reactive Binding Tests
    
    func testFlightServiceBindings() {
        let expectation = XCTestExpectation(description: "Flight service bindings")
        
        // Test flight updates
        let testFlights = [createTestFlight(id: "test1")]
        mockFlightService.currentFlights = testFlights
        
        // Test connection status updates
        mockFlightService.connectionStatus = .connected
        
        // Test monitoring status updates
        mockFlightService.isMonitoring = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.flights, testFlights)
            XCTAssertEqual(self.viewModel.connectionStatus, .connected)
            XCTAssertTrue(self.viewModel.isMonitoring)
            XCTAssertNotNil(self.viewModel.lastUpdateTime)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testSettingsManagerBindings() {
        let expectation = XCTestExpectation(description: "Settings manager bindings")
        
        let testBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        mockSettingsManager.geographicBounds = testBounds
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.viewModel.currentBounds, testBounds)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - Search Tests
    
    func testShowHideSearch() {
        // Initially search should be hidden
        XCTAssertFalse(viewModel.isSearchVisible)
        XCTAssertTrue(viewModel.searchText.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        
        // Show search
        viewModel.showSearch()
        XCTAssertTrue(viewModel.isSearchVisible)
        XCTAssertTrue(viewModel.searchText.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        
        // Hide search
        viewModel.hideSearch()
        XCTAssertFalse(viewModel.isSearchVisible)
        XCTAssertTrue(viewModel.searchText.isEmpty)
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }
    
    func testPerformSearch() {
        // Set up test data
        let mockFlights = [
            FlightData.mockFlight1, // AA123
            FlightData.mockFlight2, // DL456
            FlightData.mockFlight3  // UA789
        ]
        
        // Simulate flight service providing flights
        mockFlightService.currentFlights = mockFlights
        
        // Wait for flights to be processed
        let expectation = XCTestExpectation(description: "Flights processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Test search by flight number
        viewModel.searchText = "AA123"
        viewModel.performSearch()
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.flightNumber, "AA123")
        
        // Test search by airline name
        viewModel.searchText = "Delta"
        viewModel.performSearch()
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.flightNumber, "DL456")
        
        // Test search by aircraft model
        viewModel.searchText = "Boeing 777"
        viewModel.performSearch()
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.flightNumber, "UA789")
        
        // Test search by airport code
        viewModel.searchText = "JFK"
        viewModel.performSearch()
        XCTAssertEqual(viewModel.searchResults.count, 1)
        XCTAssertEqual(viewModel.searchResults.first?.flightNumber, "AA123")
        
        // Test empty search
        viewModel.searchText = ""
        viewModel.performSearch()
        XCTAssertTrue(viewModel.searchResults.isEmpty)
        
        // Test no results
        viewModel.searchText = "NONEXISTENT"
        viewModel.performSearch()
        XCTAssertTrue(viewModel.searchResults.isEmpty)
    }
    
    func testSelectFlightFromSearch() {
        // Set up test data
        let mockFlights = [
            FlightData.mockFlight1,
            FlightData.mockFlight2,
            FlightData.mockFlight3
        ]
        
        // Simulate flight service providing flights
        mockFlightService.currentFlights = mockFlights
        
        // Wait for flights to be processed
        let expectation = XCTestExpectation(description: "Flights processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        // Show search and find a flight
        viewModel.showSearch()
        viewModel.searchText = "DL456"
        viewModel.performSearch()
        
        XCTAssertEqual(viewModel.searchResults.count, 1)
        let searchedFlight = viewModel.searchResults.first!
        
        // Select flight from search
        viewModel.selectFlightFromSearch(searchedFlight)
        
        // Verify search is hidden
        XCTAssertFalse(viewModel.isSearchVisible)
        
        // Verify flight is selected
        XCTAssertEqual(viewModel.currentFlight?.id, searchedFlight.id)
    }
}

// MARK: - Test Helpers
extension MainViewModelTests {
    
    func createTestFlight(id: String, 
                         flightNumber: String? = "AA123",
                         callsign: String? = "AAL123") -> FlightData {
        let airline = AirlineInfo(name: "American Airlines", code: "AA")
        let aircraft = AircraftInfo(model: "Boeing 737", code: "B737", registration: "N123AA")
        let origin = AirportInfo(name: "John F. Kennedy International Airport", iataCode: "JFK", city: "New York")
        let destination = AirportInfo(name: "Los Angeles International Airport", iataCode: "LAX", city: "Los Angeles")
        let route = RouteInfo(origin: origin, destination: destination)
        let position = FlightPosition(latitude: 40.7128, longitude: -74.0060, altitude: 35000, speed: 450, heading: 270)
        
        return FlightData(
            id: id,
            flightNumber: flightNumber,
            callsign: callsign,
            airline: airline,
            aircraft: aircraft,
            route: route,
            position: position,
            lastUpdated: Date()
        )
    }
}