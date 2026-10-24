// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  NetworkManager.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import Foundation

// MARK: - Network Errors
enum NetworkError: LocalizedError, Equatable {
    case invalidURL
    case noData
    case invalidResponse
    case httpError(Int)
    case timeout
    case rateLimited
    case parseError(String)
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .invalidResponse:
            return "Invalid response format"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .timeout:
            return "Request timeout"
        case .rateLimited:
            return "API rate limit exceeded"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .networkUnavailable:
            return "Network unavailable"
        }
    }
}

// MARK: - Network Manager Protocol
protocol NetworkManagerProtocol {
    func fetchFlightsInBounds(_ bounds: GeographicBounds) async throws -> [String: Any]
    func fetchFlightDetails(flightId: String) async throws -> [String: Any]
}

// MARK: - URLSession Protocol
protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - Network Manager Implementation
class NetworkManager: NetworkManagerProtocol {
    
    // MARK: - Properties
    private let session: URLSessionProtocol
    private let baseSearchURL = "https://data-cloud.flightradar24.com/zones/fcgi/feed.js"
    private let baseDetailsURL = "https://data-live.flightradar24.com/clickhandler/"
    
    private let requestHeaders: [String: String] = [
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        "Cache-Control": "no-store, no-cache, must-revalidate",
        "Accept": "application/json",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "Sec-Fetch-Dest": "empty",
        "Sec-Fetch-Mode": "cors",
        "Sec-Fetch-Site": "same-site"
    ]
    
    // MARK: - Initialization
    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }
    
    // MARK: - Public Methods
    
    /// Fetches flights within the specified geographic bounds
    func fetchFlightsInBounds(_ bounds: GeographicBounds) async throws -> [String: Any] {
        // Validate bounds before making request
        try bounds.validate()
        
        // Construct URL with bounds parameters
        guard let url = buildSearchURL(for: bounds) else {
            throw NetworkError.invalidURL
        }
        
        // Create and configure request
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        addHeaders(to: &request)
        
        // Execute request with error handling
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate HTTP response
            try validateHTTPResponse(response)
            
            // Parse JSON response
            return try parseJSONResponse(data)
            
        } catch let error as URLError {
            throw mapURLError(error)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkUnavailable
        }
    }
    
    /// Fetches detailed information for a specific flight
    func fetchFlightDetails(flightId: String) async throws -> [String: Any] {
        // Validate flight ID
        guard !flightId.isEmpty else {
            throw NetworkError.invalidURL
        }
        
        // Construct URL for flight details
        guard let url = buildDetailsURL(for: flightId) else {
            throw NetworkError.invalidURL
        }
        
        // Create and configure request
        var request = URLRequest(url: url)
        request.timeoutInterval = 30.0
        addHeaders(to: &request)
        
        // Execute request with error handling
        do {
            let (data, response) = try await session.data(for: request)
            
            // Validate HTTP response
            try validateHTTPResponse(response)
            
            // Parse JSON response
            return try parseJSONResponse(data)
            
        } catch let error as URLError {
            throw mapURLError(error)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.networkUnavailable
        }
    }
}

// MARK: - Private Helper Methods
private extension NetworkManager {
    
    /// Builds the search URL with geographic bounds parameters
    func buildSearchURL(for bounds: GeographicBounds) -> URL? {
        var components = URLComponents(string: baseSearchURL)
        components?.queryItems = [
            URLQueryItem(name: "bounds", value: bounds.boundsString),
            URLQueryItem(name: "faa", value: "1"),
            URLQueryItem(name: "satellite", value: "1"),
            URLQueryItem(name: "mlat", value: "1"),
            URLQueryItem(name: "flarm", value: "1"),
            URLQueryItem(name: "adsb", value: "1"),
            URLQueryItem(name: "gnd", value: "1"),
            URLQueryItem(name: "air", value: "1"),
            URLQueryItem(name: "vehicles", value: "1"),
            URLQueryItem(name: "estimated", value: "1"),
            URLQueryItem(name: "maxage", value: "14400"),
            URLQueryItem(name: "gliders", value: "1"),
            URLQueryItem(name: "stats", value: "1")
        ]
        return components?.url
    }
    
    /// Builds the details URL for a specific flight
    func buildDetailsURL(for flightId: String) -> URL? {
        var components = URLComponents(string: baseDetailsURL)
        components?.queryItems = [
            URLQueryItem(name: "version", value: "1.5"),
            URLQueryItem(name: "flight", value: flightId)
        ]
        return components?.url
    }
    
    /// Adds required headers to the request
    func addHeaders(to request: inout URLRequest) {
        for (key, value) in requestHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
    
    /// Validates the HTTP response and throws appropriate errors
    func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return // Success
        case 429:
            throw NetworkError.rateLimited
        case 400...499:
            throw NetworkError.httpError(httpResponse.statusCode)
        case 500...599:
            throw NetworkError.httpError(httpResponse.statusCode)
        default:
            throw NetworkError.httpError(httpResponse.statusCode)
        }
    }
    
    /// Parses JSON response data
    func parseJSONResponse(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty else {
            throw NetworkError.noData
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.parseError("Response is not a valid JSON object")
            }
            return json
        } catch let error as NSError {
            throw NetworkError.parseError(error.localizedDescription)
        }
    }
    
    /// Maps URLError to NetworkError
    func mapURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkUnavailable
        case .badURL:
            return .invalidURL
        default:
            return .networkUnavailable
        }
    }
}
#endif
