//
//  FlightDisplayViewTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import SwiftUI
@testable import WhatTheFlight

@MainActor
final class FlightDisplayViewTests: XCTestCase {
    
    var mockFlightService: MockFlightService!
    var mockSettingsManager: MockSettingsManager!
    var mockLocationManager: MockLocationManager!
    var viewModel: MainViewModel!
    
    override func setUp() {
        super.setUp()
        mockFlightService = MockFlightService()
        mockSettingsManager = MockSettingsManager()
        mockLocationManager = MockLocationManager()
        
        viewModel = MainViewModel(
            flightService: mockFlightService,
            settingsManager: mockSettingsManager,
            locationManager: mockLocationManager
        )
    }
    
    override func tearDown() {
        mockFlightService = nil
        mockSettingsManager = nil
        mockLocationManager = nil
        viewModel = nil
        super.tearDown()
    }
    
    // MARK: - ViewModel State Tests
    
    func testViewModelInitialState() {
        // Given/When - ViewModel is initialized in setUp
        
        // Then
        XCTAssertTrue(viewModel.flights.isEmpty)
        XCTAssertEqual(viewModel.connectionStatus, .disconnected)
        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertNil(viewModel.currentBounds)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.lastUpdateTime)
    }
    
    func testViewModelWithSingleFlight() {
        // Given
        let mockFlight = FlightData.mockFlight1
        
        // When
        viewModel.flights = [mockFlight]
        viewModel.connectionStatus = .connected
        viewModel.isMonitoring = true
        
        // Then
        XCTAssertEqual(viewModel.flights.count, 1)
        XCTAssertEqual(viewModel.flights.first?.id, mockFlight.id)
        XCTAssertEqual(viewModel.currentFlight?.id, mockFlight.id)
        XCTAssertFalse(viewModel.hasMultipleFlights)
        XCTAssertEqual(viewModel.flightCount, 1)
    }
    
    func testViewModelWithMultipleFlights() {
        // Given
        let flights = [FlightData.mockFlight1, FlightData.mockFlight2, FlightData.mockFlight3]
        
        // When
        viewModel.flights = flights
        viewModel.connectionStatus = .connected
        viewModel.isMonitoring = true
        
        // Then
        XCTAssertEqual(viewModel.flights.count, 3)
        XCTAssertTrue(viewModel.hasMultipleFlights)
        XCTAssertEqual(viewModel.flightCount, 3)
        XCTAssertEqual(viewModel.currentFlight?.id, flights.first?.id)
    }
    
    func testViewModelStatusMessages() {
        // Test loading state
        viewModel.isLoading = true
        XCTAssertEqual(viewModel.statusMessage, "Loading...")
        
        // Test disconnected state
        viewModel.isLoading = false
        viewModel.connectionStatus = .disconnected
        viewModel.isMonitoring = false
        XCTAssertEqual(viewModel.statusMessage, "Not monitoring")
        
        // Test connecting state
        viewModel.connectionStatus = .connecting
        XCTAssertEqual(viewModel.statusMessage, "Connecting to flight data...")
        
        // Test connected with no flights
        viewModel.connectionStatus = .connected
        viewModel.flights = []
        XCTAssertEqual(viewModel.statusMessage, "No flights detected in area")
        
        // Test connected with flights
        viewModel.flights = [FlightData.mockFlight1]
        XCTAssertEqual(viewModel.statusMessage, "Monitoring 1 flight")
        
        // Test error state
        let errorMessage = "Network error"
        viewModel.connectionStatus = .error(errorMessage)
        XCTAssertEqual(viewModel.statusMessage, "Error: \(errorMessage)")
        
        // Test rate limited state
        viewModel.connectionStatus = .rateLimited
        XCTAssertEqual(viewModel.statusMessage, "Rate limited - reducing query frequency")
    }
    
    func testViewModelLastUpdateDescription() {
        // Test with no update time
        viewModel.lastUpdateTime = nil
        XCTAssertEqual(viewModel.lastUpdateDescription, "Never updated")
        
        // Test with update time
        let updateTime = Date()
        viewModel.lastUpdateTime = updateTime
        XCTAssertTrue(viewModel.lastUpdateDescription.contains("Last updated:"))
    }
    
    // MARK: - Flight Display Logic Tests
    
    func testFlightDisplayInfoFormatting() {
        // Given
        let mockFlight = FlightData.mockFlight1
        
        // When
        let displayInfo = viewModel.formatFlightInfo(mockFlight)
        
        // Then
        XCTAssertEqual(displayInfo.primaryIdentifier, mockFlight.displayIdentifier)
        XCTAssertEqual(displayInfo.route, mockFlight.routeDescription)
        XCTAssertEqual(displayInfo.aircraftInfo, mockFlight.aircraftDescription)
        
        if let position = mockFlight.position {
            XCTAssertEqual(displayInfo.altitude, position.altitudeDescription)
            XCTAssertEqual(displayInfo.speed, position.speedDescription)
        }
    }
    
    func testFlightCycling() {
        // Given
        let flights = [FlightData.mockFlight1, FlightData.mockFlight2, FlightData.mockFlight3]
        viewModel.flights = flights
        
        // When
        viewModel.cycleToNextFlight()
        
        // Then - Should cycle to next flight
        XCTAssertEqual(viewModel.flights.first?.id, FlightData.mockFlight2.id)
        
        // When - Cycle again
        viewModel.cycleToNextFlight()
        
        // Then - Should cycle to third flight
        XCTAssertEqual(viewModel.flights.first?.id, FlightData.mockFlight3.id)
        
        // When - Cycle again (should wrap around)
        viewModel.cycleToNextFlight()
        
        // Then - Should wrap back to first flight
        XCTAssertEqual(viewModel.flights.first?.id, FlightData.mockFlight1.id)
    }
    
    func testFlightCyclingWithSingleFlight() {
        // Given
        viewModel.flights = [FlightData.mockFlight1]
        let originalFlightId = viewModel.flights.first?.id
        
        // When
        viewModel.cycleToNextFlight()
        
        // Then - Should not change with single flight
        XCTAssertEqual(viewModel.flights.first?.id, originalFlightId)
    }
    
    func testFlightCyclingWithEmptyFlights() {
        // Given
        viewModel.flights = []
        
        // When/Then - Should not crash
        XCTAssertNoThrow(viewModel.cycleToNextFlight())
    }
    
    // MARK: - Connection Status Tests
    
    func testConnectionStatusHandling() {
        // Test connected status
        viewModel.handleConnectionStatusChange(.connected)
        XCTAssertEqual(viewModel.connectionStatus, .connected)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        
        // Test connecting status
        viewModel.handleConnectionStatusChange(.connecting)
        XCTAssertEqual(viewModel.connectionStatus, .connecting)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        
        // Test error status
        let errorMessage = "Test error"
        viewModel.handleConnectionStatusChange(.error(errorMessage))
        XCTAssertEqual(viewModel.connectionStatus, .error(errorMessage))
        XCTAssertEqual(viewModel.errorMessage, errorMessage)
        XCTAssertFalse(viewModel.isLoading)
        
        // Test rate limited status
        viewModel.handleConnectionStatusChange(.rateLimited)
        XCTAssertEqual(viewModel.connectionStatus, .rateLimited)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorMessageHandling() {
        // Test setting error
        let errorMessage = "Test error message"
        viewModel.setError(errorMessage)
        XCTAssertEqual(viewModel.errorMessage, errorMessage)
        
        // Test clearing error
        viewModel.clearError()
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Configuration Validation Tests
    
    func testConfigurationValidation() {
        // Test with no bounds
        viewModel.currentBounds = nil
        XCTAssertFalse(viewModel.validateConfiguration())
        XCTAssertNotNil(viewModel.errorMessage)
        
        // Test with invalid bounds
        let invalidBounds = GeographicBounds(
            northLatitude: -90, // Invalid: north should be > south
            southLatitude: 90,
            eastLongitude: 180,
            westLongitude: -180
        )
        viewModel.currentBounds = invalidBounds
        XCTAssertFalse(viewModel.validateConfiguration())
        
        // Test with valid bounds
        let validBounds = GeographicBounds(
            northLatitude: 45.0,
            southLatitude: 40.0,
            eastLongitude: -70.0,
            westLongitude: -75.0
        )
        viewModel.currentBounds = validBounds
        viewModel.clearError()
        XCTAssertTrue(viewModel.validateConfiguration())
        XCTAssertNil(viewModel.errorMessage)
    }
    
    // MARK: - Monitoring Control Tests
    
    func testStartMonitoring() {
        // Given
        let validBounds = GeographicBounds(
            northLatitude: 45.0,
            southLatitude: 40.0,
            eastLongitude: -70.0,
            westLongitude: -75.0
        )
        viewModel.currentBounds = validBounds
        
        // When
        viewModel.startMonitoring()
        
        // Then
        XCTAssertTrue(mockFlightService.startMonitoringCalled)
        XCTAssertEqual(mockFlightService.lastBounds, validBounds)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testStartMonitoringWithoutBounds() {
        // Given
        viewModel.currentBounds = nil
        
        // When
        viewModel.startMonitoring()
        
        // Then
        XCTAssertFalse(mockFlightService.startMonitoringCalled)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("No geographic bounds") == true)
    }
    
    func testStopMonitoring() {
        // When
        viewModel.stopMonitoring()
        
        // Then
        XCTAssertTrue(mockFlightService.stopMonitoringCalled)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testToggleMonitoring() {
        // Given
        let validBounds = GeographicBounds(
            northLatitude: 45.0,
            southLatitude: 40.0,
            eastLongitude: -70.0,
            westLongitude: -75.0
        )
        viewModel.currentBounds = validBounds
        viewModel.isMonitoring = false
        
        // When - Toggle to start monitoring
        viewModel.toggleMonitoring()
        
        // Then
        XCTAssertTrue(mockFlightService.startMonitoringCalled)
        
        // When - Toggle to stop monitoring
        mockFlightService.reset()
        viewModel.isMonitoring = true
        viewModel.toggleMonitoring()
        
        // Then
        XCTAssertTrue(mockFlightService.stopMonitoringCalled)
    }
    
    // MARK: - Bounds Update Tests
    
    func testUpdateBounds() {
        // Given
        let newBounds = GeographicBounds(
            northLatitude: 50.0,
            southLatitude: 45.0,
            eastLongitude: -65.0,
            westLongitude: -70.0
        )
        
        // When
        viewModel.updateBounds(newBounds)
        
        // Then
        XCTAssertEqual(viewModel.currentBounds, newBounds)
        XCTAssertEqual(mockSettingsManager.geographicBounds, newBounds)
        XCTAssertNil(viewModel.errorMessage)
    }
    
    func testUpdateBoundsWithInvalidBounds() {
        // Given
        let invalidBounds = GeographicBounds(
            northLatitude: -90, // Invalid
            southLatitude: 90,
            eastLongitude: 180,
            westLongitude: -180
        )
        
        // When
        viewModel.updateBounds(invalidBounds)
        
        // Then
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.errorMessage?.contains("Invalid geographic bounds") == true)
    }
    
    // MARK: - Flight Cycling Timer Tests
    
    func testFlightCyclingTimer() {
        // Given
        let flights = [FlightData.mockFlight1, FlightData.mockFlight2]
        viewModel.flights = flights
        
        // When
        viewModel.startFlightCycling(interval: 0.1) // Short interval for testing
        
        // Then - Wait for timer to fire
        let expectation = XCTestExpectation(description: "Flight should cycle")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Should have cycled to next flight
            if self.viewModel.flights.first?.id == FlightData.mockFlight2.id {
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Cleanup
        viewModel.stopFlightCycling()
    }
    
    func testStopFlightCycling() {
        // Given
        let flights = [FlightData.mockFlight1, FlightData.mockFlight2]
        viewModel.flights = flights
        viewModel.startFlightCycling(interval: 0.1)
        
        // When
        viewModel.stopFlightCycling()
        
        // Then - Should reset to first flight
        XCTAssertEqual(viewModel.flights.first?.id, FlightData.mockFlight1.id)
    }
    
    // MARK: - Edge Cases and Error Conditions
    
    func testFlightDataWithMissingInformation() {
        // Given
        let incompleteFlightData = FlightData(
            id: "incomplete",
            flightNumber: nil,
            callsign: "TEST123",
            airline: nil,
            aircraft: nil,
            route: nil,
            position: nil
        )
        
        // When
        let displayInfo = viewModel.formatFlightInfo(incompleteFlightData)
        
        // Then - Should handle missing data gracefully
        XCTAssertEqual(displayInfo.primaryIdentifier, "TEST123")
        XCTAssertEqual(displayInfo.route, "Unknown Route")
        XCTAssertEqual(displayInfo.aircraftInfo, "Unknown Airline • Unknown Aircraft")
        XCTAssertEqual(displayInfo.altitude, "Unknown")
        XCTAssertEqual(displayInfo.speed, "Unknown")
    }
    
    func testRefreshFlightDataWhenNotMonitoring() {
        // Given
        viewModel.isMonitoring = false
        
        // When
        viewModel.refreshFlightData()
        
        // Then - Should not trigger refresh
        XCTAssertFalse(viewModel.isLoading)
    }
    
    func testRefreshFlightDataWhenMonitoring() {
        // Given
        viewModel.isMonitoring = true
        
        // When
        viewModel.refreshFlightData()
        
        // Then - Should trigger loading state
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }
}