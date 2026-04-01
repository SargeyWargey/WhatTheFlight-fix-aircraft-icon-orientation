//
//  NetworkManagerTests.swift
//  WhatTheFlightTests
//
//  Created by Kiro on 8/1/25.
//

import XCTest
@testable import WhatTheFlight

// MARK: - Mock URLSession
class MockURLSession: URLSessionProtocol {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }
        
        let data = mockData ?? Data()
        let response = mockResponse ?? HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        
        return (data, response)
    }
}

// MARK: - NetworkManager Tests
class NetworkManagerTests: XCTestCase {
    
    var networkManager: NetworkManager!
    var mockSession: MockURLSession!
    var validBounds: GeographicBounds!
    
    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        networkManager = NetworkManager(session: mockSession!)
        validBounds = GeographicBounds(
            northLatitude: 40.0,
            southLatitude: 39.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
    }
    
    override func tearDown() {
        networkManager = nil
        mockSession = nil
        validBounds = nil
        super.tearDown()
    }
    
    // MARK: - fetchFlightsInBounds Tests
    
    func testFetchFlightsInBounds_Success() async throws {
        // Given
        let mockFlightData: [String: Any] = [
            "full_count": 1,
            "version": 4,
            "abc123": [
                "1234567890",  // ID
                40.7128,       // Latitude
                -74.0060,      // Longitude
                90,            // Heading
                35000,         // Altitude
                450,           // Speed
                "1234",        // Squawk
                "B738",        // Aircraft code
                "N12345",      // Registration
                1640995200,    // Timestamp
                "JFK",         // Origin
                "LAX",         // Destination
                "AA123",       // Flight number
                0,             // On ground
                450,           // Vertical speed
                "AAL123",      // Callsign
                0              // Source
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: mockFlightData)
        mockSession.mockData = jsonData
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await networkManager.fetchFlightsInBounds(validBounds)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertEqual(result["full_count"] as? Int, 1)
        XCTAssertEqual(result["version"] as? Int, 4)
        XCTAssertNotNil(result["abc123"])
    }
    
    func testFetchFlightsInBounds_InvalidBounds() async {
        // Given
        let invalidBounds = GeographicBounds(
            northLatitude: 39.0,  // South > North (invalid)
            southLatitude: 40.0,
            eastLongitude: -73.0,
            westLongitude: -74.0
        )
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(invalidBounds)
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is GeographicBounds.ValidationError)
        }
    }
    
    func testFetchFlightsInBounds_HTTPError() async {
        // Given
        mockSession.mockData = Data()
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(validBounds)
            XCTFail("Expected NetworkError to be thrown")
        } catch let error as NetworkError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 404)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Expected NetworkError, got \(error)")
        }
    }
    
    func testFetchFlightsInBounds_RateLimited() async {
        // Given
        mockSession.mockData = Data()
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 429,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(validBounds)
            XCTFail("Expected NetworkError.rateLimited to be thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("Expected NetworkError.rateLimited, got \(error)")
        }
    }
    
    func testFetchFlightsInBounds_NoData() async {
        // Given
        mockSession.mockData = Data() // Empty data
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(validBounds)
            XCTFail("Expected NetworkError.noData to be thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .noData)
        } catch {
            XCTFail("Expected NetworkError.noData, got \(error)")
        }
    }
    
    func testFetchFlightsInBounds_InvalidJSON() async {
        // Given
        mockSession.mockData = "invalid json".data(using: .utf8)
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(validBounds)
            XCTFail("Expected NetworkError.parseError to be thrown")
        } catch let error as NetworkError {
            if case .parseError = error {
                // Success - expected parse error
            } else {
                XCTFail("Expected parseError, got \(error)")
            }
        } catch {
            XCTFail("Expected NetworkError.parseError, got \(error)")
        }
    }
    
    func testFetchFlightsInBounds_Timeout() async {
        // Given
        mockSession.mockError = URLError(.timedOut)
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(validBounds)
            XCTFail("Expected NetworkError.timeout to be thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Expected NetworkError.timeout, got \(error)")
        }
    }
    
    func testFetchFlightsInBounds_NetworkUnavailable() async {
        // Given
        mockSession.mockError = URLError(.notConnectedToInternet)
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightsInBounds(validBounds)
            XCTFail("Expected NetworkError.networkUnavailable to be thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .networkUnavailable)
        } catch {
            XCTFail("Expected NetworkError.networkUnavailable, got \(error)")
        }
    }
    
    // MARK: - fetchFlightDetails Tests
    
    func testFetchFlightDetails_Success() async throws {
        // Given
        let flightId = "abc123"
        let mockFlightDetails: [String: Any] = [
            "identification": [
                "id": flightId,
                "number": ["default": "AA123"],
                "callsign": "AAL123"
            ],
            "aircraft": [
                "model": ["code": "B738", "text": "Boeing 737-800"],
                "registration": "N12345"
            ],
            "airline": [
                "name": "American Airlines",
                "code": ["iata": "AA", "icao": "AAL"]
            ],
            "airport": [
                "origin": [
                    "name": "John F. Kennedy International Airport",
                    "code": ["iata": "JFK", "icao": "KJFK"],
                    "position": ["country": ["name": "United States"]]
                ],
                "destination": [
                    "name": "Los Angeles International Airport",
                    "code": ["iata": "LAX", "icao": "KLAX"],
                    "position": ["country": ["name": "United States"]]
                ]
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: mockFlightDetails)
        mockSession.mockData = jsonData
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When
        let result = try await networkManager.fetchFlightDetails(flightId: flightId)
        
        // Then
        XCTAssertNotNil(result)
        XCTAssertNotNil(result["identification"])
        XCTAssertNotNil(result["aircraft"])
        XCTAssertNotNil(result["airline"])
        XCTAssertNotNil(result["airport"])
    }
    
    func testFetchFlightDetails_EmptyFlightId() async {
        // Given
        let emptyFlightId = ""
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightDetails(flightId: emptyFlightId)
            XCTFail("Expected NetworkError.invalidURL to be thrown")
        } catch let error as NetworkError {
            XCTAssertEqual(error, .invalidURL)
        } catch {
            XCTFail("Expected NetworkError.invalidURL, got \(error)")
        }
    }
    
    func testFetchFlightDetails_HTTPError() async {
        // Given
        let flightId = "abc123"
        mockSession.mockData = Data()
        mockSession.mockResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )
        
        // When/Then
        do {
            _ = try await networkManager.fetchFlightDetails(flightId: flightId)
            XCTFail("Expected NetworkError.httpError to be thrown")
        } catch let error as NetworkError {
            if case .httpError(let code) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("Expected httpError, got \(error)")
            }
        } catch {
            XCTFail("Expected NetworkError.httpError, got \(error)")
        }
    }
    
    // MARK: - NetworkError Tests
    
    func testNetworkError_Descriptions() {
        XCTAssertEqual(NetworkError.invalidURL.errorDescription, "Invalid URL")
        XCTAssertEqual(NetworkError.noData.errorDescription, "No data received")
        XCTAssertEqual(NetworkError.invalidResponse.errorDescription, "Invalid response format")
        XCTAssertEqual(NetworkError.httpError(404).errorDescription, "HTTP error: 404")
        XCTAssertEqual(NetworkError.timeout.errorDescription, "Request timeout")
        XCTAssertEqual(NetworkError.rateLimited.errorDescription, "API rate limit exceeded")
        XCTAssertEqual(NetworkError.parseError("test").errorDescription, "Parse error: test")
        XCTAssertEqual(NetworkError.networkUnavailable.errorDescription, "Network unavailable")
    }
    
    func testNetworkError_Equality() {
        XCTAssertEqual(NetworkError.invalidURL, NetworkError.invalidURL)
        XCTAssertEqual(NetworkError.httpError(404), NetworkError.httpError(404))
        XCTAssertEqual(NetworkError.parseError("test"), NetworkError.parseError("test"))
        XCTAssertNotEqual(NetworkError.httpError(404), NetworkError.httpError(500))
        XCTAssertNotEqual(NetworkError.parseError("test1"), NetworkError.parseError("test2"))
    }
}