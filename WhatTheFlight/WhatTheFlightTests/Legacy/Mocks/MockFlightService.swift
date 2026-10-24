//
//  MockFlightService.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import Foundation
import Combine
@testable import WhatTheFlight

class MockFlightService: FlightServiceProtocol, ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentFlights: [FlightData] = []
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var isMonitoring: Bool = false
    
    // MARK: - Mock Tracking Properties
    var startMonitoringCalled = false
    var stopMonitoringCalled = false
    var updateBoundsCalled = false
    var pauseMonitoringCalled = false
    var resumeMonitoringCalled = false
    var lastBounds: GeographicBounds?
    
    // MARK: - FlightServiceProtocol Implementation
    
    func startMonitoring(bounds: GeographicBounds) {
        startMonitoringCalled = true
        lastBounds = bounds
        isMonitoring = true
        connectionStatus = .connecting
        
        // Simulate async connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.connectionStatus = .connected
        }
    }
    
    func stopMonitoring() {
        stopMonitoringCalled = true
        isMonitoring = false
        connectionStatus = .disconnected
        currentFlights = []
    }
    
    func updateBounds(_ bounds: GeographicBounds) {
        updateBoundsCalled = true
        lastBounds = bounds
    }
    
    func pauseMonitoring() {
        pauseMonitoringCalled = true
        connectionStatus = .disconnected
    }
    
    func resumeMonitoring() {
        resumeMonitoringCalled = true
        if isMonitoring {
            connectionStatus = .connecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.connectionStatus = .connected
            }
        }
    }
    
    func fetchFlightDetails(flightId: String) async throws -> [String: Any] {
        // Mock implementation for testing
        return [
            "identification": [
                "number": ["default": "TEST123"]
            ],
            "aircraft": [
                "model": ["text": "Test Aircraft"],
                "registration": "N123TEST"
            ],
            "airline": [
                "name": "Test Airlines"
            ]
        ]
    }
    
    func fetchFlights(in bounds: GeographicBounds) async throws -> [FlightData] {
        // Mock implementation for testing - return some mock flights
        return [
            FlightData.mockFlight1,
            FlightData.mockFlight2,
            FlightData.mockFlight3
        ]
    }
    
    // MARK: - Mock Helper Methods
    
    func simulateFlightDetection(_ flights: [FlightData]) {
        currentFlights = flights
    }
    
    func simulateFlights(_ flights: [FlightData]) {
        currentFlights = flights
    }
    
    func simulateConnectionError(_ message: String) {
        connectionStatus = .error(message)
    }
    
    func simulateRateLimited() {
        connectionStatus = .rateLimited
    }
    
    func reset() {
        startMonitoringCalled = false
        stopMonitoringCalled = false
        updateBoundsCalled = false
        pauseMonitoringCalled = false
        resumeMonitoringCalled = false
        lastBounds = nil
        currentFlights = []
        connectionStatus = .disconnected
        isMonitoring = false
    }
}