// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  FlightServiceTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
import Combine
@testable import WhatTheFlight

// MARK: - Mock Network Manager
class MockNetworkManager: NetworkManagerProtocol {
    var shouldThrowError = false
    var errorToThrow: Error = NetworkError.networkUnavailable
    var mockResponse: [String: Any] = [:]
    var fetchFlightsCallCount = 0
    var fetchDetailsCallCount = 0
    var lastBounds: GeographicBounds?
    var lastFlightId: String?
    
    func fetchFlightsInBounds(_ bounds: GeographicBounds) async throws -> [String: Any] {
        fetchFlightsCallCount += 1
        lastBounds = bounds
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockResponse
    }
    
    func fetchFlightDetails(flightId: String) async throws -> [String: Any] {
        fetchDetailsCallCount += 1
        lastFlightId = flightId
        
        if shouldThrowError {
            throw errorToThrow
        }
        
        return mockResponse
    }
    
    func reset() {
        shouldThrowError = false
        errorToThrow = NetworkError.networkUnavailable
        mockResponse = [:]
        fetchFlightsCallCount = 0
        fetchDetailsCallCount = 0
        lastBounds = nil
        lastFlightId = nil
    }
}

// MARK: - Flight Service Tests
class FlightServiceTests: XCTestCase {
    
    var flightService: FlightService!
    var mockNetworkManager: MockNetworkManager!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        mockNetworkManager = MockNetworkManager()
        flightService = FlightService(networkManager: mockNetworkManager)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        flightService.stopMonitoring()
        flightService = nil
        mockNetworkManager = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialState() {
        XCTAssertEqual(flightService.currentFlights, [])
        XCTAssertEqual(flightService.connectionStatus, .disconnected)
        XCTAssertFalse(flightService.isMonitoring)
    }
    
    // MARK: - Start Monitoring Tests
    
    func testStartMonitoring() {
        let bounds = createTestBounds()
        
        flightService.startMonitoring(bounds: bounds)
        
        XCTAssertTrue(flightService.isMonitoring)
        XCTAssertEqual(flightService.connectionStatus, .connecting)
    }
    
    func testStartMonitoringWithValidBounds() async {
        let bounds = createTestBounds()
        mockNetworkManager.mockResponse = createMockFlightResponse()
        
        let expectation = XCTestExpectation(description: "Flight data fetched")
        
        flightService.$connectionStatus
            .sink { status in
                if status == .connected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertEqual(flightService.connectionStatus, .connected)
        XCTAssertTrue(mockNetworkManager.fetchFlightsCallCount > 0)
        XCTAssertEqual(mockNetworkManager.lastBounds, bounds)
    }
    
    // MARK: - Stop Monitoring Tests
    
    func testStopMonitoring() {
        let bounds = createTestBounds()
        
        flightService.startMonitoring(bounds: bounds)
        XCTAssertTrue(flightService.isMonitoring)
        
        flightService.stopMonitoring()
        
        XCTAssertFalse(flightService.isMonitoring)
        XCTAssertEqual(flightService.connectionStatus, .disconnected)
        XCTAssertEqual(flightService.currentFlights, [])
    }
    
    // MARK: - Update Bounds Tests
    
    func testUpdateBounds() {
        let initialBounds = createTestBounds()
        let newBounds = GeographicBounds(
            northLatitude: 41.0,
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        flightService.startMonitoring(bounds: initialBounds)
        flightService.updateBounds(newBounds)
        
        XCTAssertTrue(flightService.isMonitoring)
        // The service should restart monitoring with new bounds
    }
    
    func testUpdateBoundsWhenNotMonitoring() {
        let bounds = createTestBounds()
        
        flightService.updateBounds(bounds)
        
        XCTAssertFalse(flightService.isMonitoring)
        XCTAssertEqual(flightService.connectionStatus, .disconnected)
    }
    
    // MARK: - Flight Data Parsing Tests
    
    func testFlightDataParsing() async {
        let bounds = createTestBounds()
        mockNetworkManager.mockResponse = createMockFlightResponse()
        
        let expectation = XCTestExpectation(description: "Flights parsed")
        
        flightService.$currentFlights
            .sink { flights in
                if !flights.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertFalse(flightService.currentFlights.isEmpty)
        
        let flight = flightService.currentFlights.first!
        XCTAssertEqual(flight.id, "test123")
        XCTAssertEqual(flight.callsign, "UAL123")
        XCTAssertEqual(flight.flightNumber, "UA123")
        XCTAssertNotNil(flight.position)
        XCTAssertEqual(flight.position?.latitude, 40.7128)
        XCTAssertEqual(flight.position?.longitude, -74.0060)
    }
    
    func testFlightDataParsingWithInvalidData() async {
        let bounds = createTestBounds()
        mockNetworkManager.mockResponse = [
            "invalid_flight": ["invalid", "data", "format"]
        ]
        
        let expectation = XCTestExpectation(description: "Invalid data handled")
        
        flightService.$connectionStatus
            .sink { status in
                if status == .connected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertTrue(flightService.currentFlights.isEmpty)
    }
    
    // MARK: - Error Handling Tests
    
    func testNetworkErrorHandling() async {
        let bounds = createTestBounds()
        mockNetworkManager.shouldThrowError = true
        mockNetworkManager.errorToThrow = NetworkError.networkUnavailable
        
        let expectation = XCTestExpectation(description: "Error handled")
        
        flightService.$connectionStatus
            .sink { status in
                if case .error = status {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertTrue(flightService.connectionStatus.isError)
    }
    
    func testRateLimitHandling() async {
        let bounds = createTestBounds()
        mockNetworkManager.shouldThrowError = true
        mockNetworkManager.errorToThrow = NetworkError.rateLimited
        
        let expectation = XCTestExpectation(description: "Rate limit handled")
        
        flightService.$connectionStatus
            .sink { status in
                if status == .rateLimited {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        XCTAssertEqual(flightService.connectionStatus, .rateLimited)
    }
    
    // MARK: - Retry Logic Tests
    
    func testRetryLogicWithRecovery() async {
        let bounds = createTestBounds()
        mockNetworkManager.shouldThrowError = true
        mockNetworkManager.errorToThrow = NetworkError.timeout
        
        let expectation = XCTestExpectation(description: "Retry attempted")
        expectation.expectedFulfillmentCount = 2 // Initial call + retry
        
        flightService.$connectionStatus
            .sink { status in
                if case .error = status {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        // After a short delay, allow the network to succeed
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.mockNetworkManager.shouldThrowError = false
            self.mockNetworkManager.mockResponse = self.createMockFlightResponse()
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        XCTAssertTrue(mockNetworkManager.fetchFlightsCallCount > 1)
    }
    
    // MARK: - Flight Detection Tests
    
    func testNewFlightDetection() async {
        let bounds = createTestBounds()
        
        // Start with one flight
        mockNetworkManager.mockResponse = createMockFlightResponse()
        
        let firstFlightExpectation = XCTestExpectation(description: "First flight detected")
        
        flightService.$currentFlights
            .dropFirst() // Skip initial empty state
            .sink { flights in
                if flights.count == 1 {
                    firstFlightExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        flightService.startMonitoring(bounds: bounds)
        
        await fulfillment(of: [firstFlightExpectation], timeout: 5.0)
        
        // Verify first flight is detected
        XCTAssertEqual(flightService.currentFlights.count, 1)
        XCTAssertEqual(flightService.currentFlights.first?.id, "test123")
        
        // Add a second flight and manually trigger fetch
        mockNetworkManager.mockResponse = createMockFlightResponseWithTwoFlights()
        
        let secondFlightExpectation = XCTestExpectation(description: "Second flight detected")
        
        flightService.$currentFlights
            .sink { flights in
                if flights.count == 2 {
                    secondFlightExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // Manually trigger another fetch
        await flightService.triggerFlightFetch()
        
        await fulfillment(of: [secondFlightExpectation], timeout: 5.0)
        
        XCTAssertEqual(flightService.currentFlights.count, 2)
    }
}

// MARK: - Test Helpers
extension FlightServiceTests {
    
    func createTestBounds() -> GeographicBounds {
        return GeographicBounds(
            northLatitude: 40.8,
            southLatitude: 40.6,
            eastLongitude: -73.8,
            westLongitude: -74.2
        )
    }
    
    func createMockFlightResponse() -> [String: Any] {
        return [
            "test123": [
                "ABC123",           // [0] ICAO24
                40.7128,           // [1] Latitude
                -74.0060,          // [2] Longitude
                180,               // [3] Track
                35000,             // [4] Altitude
                450,               // [5] Speed
                "1200",            // [6] Squawk
                "T-MLAT",          // [7] Radar
                "Boeing 737-800",  // [8] Aircraft model
                "N12345",          // [9] Registration
                1640995200,        // [10] Timestamp
                "JFK",             // [11] Origin
                "LAX",             // [12] Destination
                "UA123",           // [13] Flight number
                0,                 // [14] On ground
                0,                 // [15] Vertical speed
                "UAL123"           // [16] Callsign
            ],
            "full_count": 1,
            "version": 4
        ]
    }
    
    func createMockFlightResponseWithTwoFlights() -> [String: Any] {
        return [
            "test123": [
                "ABC123",           // [0] ICAO24
                40.7128,           // [1] Latitude
                -74.0060,          // [2] Longitude
                180,               // [3] Track
                35000,             // [4] Altitude
                450,               // [5] Speed
                "1200",            // [6] Squawk
                "T-MLAT",          // [7] Radar
                "Boeing 737-800",  // [8] Aircraft model
                "N12345",          // [9] Registration
                1640995200,        // [10] Timestamp
                "JFK",             // [11] Origin
                "LAX",             // [12] Destination
                "UA123",           // [13] Flight number
                0,                 // [14] On ground
                0,                 // [15] Vertical speed
                "UAL123"           // [16] Callsign
            ],
            "test456": [
                "DEF456",           // [0] ICAO24
                40.7500,           // [1] Latitude
                -73.9800,          // [2] Longitude
                90,                // [3] Track
                32000,             // [4] Altitude
                420,               // [5] Speed
                "2000",            // [6] Squawk
                "T-MLAT",          // [7] Radar
                "Airbus A320",     // [8] Aircraft model
                "N67890",          // [9] Registration
                1640995300,        // [10] Timestamp
                "LGA",             // [11] Origin
                "ORD",             // [12] Destination
                "AA456",           // [13] Flight number
                0,                 // [14] On ground
                -500,              // [15] Vertical speed
                "AAL456"           // [16] Callsign
            ],
            "full_count": 2,
            "version": 4
        ]
    }
}
#endif
