// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  AircraftPhotoService.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/3/25.
//

import Foundation

/// Service for fetching aircraft photos from various sources
class AircraftPhotoService {
    
    private let session: URLSession
    
    init(session: URLSession = URLSession.shared) {
        self.session = session
    }
    
    /// Fetches aircraft photo URL using registration number
    func fetchAircraftPhotoURL(registration: String) async -> String? {
        print("🛩️ [AircraftPhotoService] Starting photo search for registration: \(registration)")
        
        // Try multiple photo sources in order of preference
        let photoSources: [(String, () async -> String?)] = [
            ("AirHistory", { await self.fetchFromAirHistory(registration: registration) }),
            ("FlightAware", { await self.fetchFromFlightAware(registration: registration) }),
            ("AviationDB", { await self.fetchFromAviationDB(registration: registration) }),
            ("Planespotters", { await self.fetchFromPlanespotters(registration: registration) }),
            ("JetPhotos Alternative", { await self.fetchFromJetPhotosAlternative(registration: registration) }),
            ("Generic Aviation APIs", { await self.fetchFromGenericAPIs(registration: registration) })
        ]
        
        for (sourceName, fetchFunction) in photoSources {
            print("🔍 [AircraftPhotoService] Trying source: \(sourceName)")
            if let url = await fetchFunction() {
                print("✅ [AircraftPhotoService] Found photo from \(sourceName): \(url)")
                return url
            }
            print("❌ [AircraftPhotoService] No photo found from \(sourceName)")
        }
        
        // Return a placeholder image URL as final fallback
        print("ℹ️ [AircraftPhotoService] No photo found from any source, using placeholder for registration: \(registration)")
        return generatePlaceholderImageURL(registration: registration)
    }
    
    /// Attempts to get photo from AirHistory.net
    private func fetchFromAirHistory(registration: String) async -> String? {
        print("🔍 [AirHistory] Searching for registration: \(registration)")
        
        let cleanRegistration = registration.replacingOccurrences(of: "-", with: "")
        
        // Try different AirHistory URL patterns
        let possibleURLs = [
            "https://www.airhistory.net/photos/\(cleanRegistration.lowercased()).jpg",
            "https://cdn.airhistory.net/images/\(cleanRegistration.lowercased())_1.jpg",
            "https://static.airhistory.net/aircraft/\(cleanRegistration.lowercased()).jpg"
        ]
        
        for (index, urlString) in possibleURLs.enumerated() {
            print("🔍 [AirHistory] Trying URL pattern \(index + 1): \(urlString)")
            if await isImageURLValid(urlString) {
                print("✅ [AirHistory] Found valid image at: \(urlString)")
                return urlString
            }
        }
        
        print("❌ [AirHistory] No photos found for \(registration)")
        return nil
    }
    
    /// Attempts to get photo from FlightAware
    private func fetchFromFlightAware(registration: String) async -> String? {
        print("🔍 [FlightAware] Searching for registration: \(registration)")
        
        let cleanRegistration = registration.replacingOccurrences(of: "-", with: "")
        
        // FlightAware sometimes has aircraft photos in their CDN
        let possibleURLs = [
            "https://flightaware-web-assets-prod.s3.amazonaws.com/var/aircraft_thumbnails/\(cleanRegistration.uppercased()).jpg",
            "https://cdn.flightaware.com/images/aircraft/\(cleanRegistration.lowercased()).jpg",
            "https://static.flightaware.com/photos/\(cleanRegistration.lowercased())_1.jpg"
        ]
        
        for (index, urlString) in possibleURLs.enumerated() {
            print("🔍 [FlightAware] Trying URL pattern \(index + 1): \(urlString)")
            if await isImageURLValid(urlString) {
                print("✅ [FlightAware] Found valid image at: \(urlString)")
                return urlString
            }
        }
        
        print("❌ [FlightAware] No photos found for \(registration)")
        return nil
    }
    
    /// Attempts to get photo from AviationDB or similar databases
    private func fetchFromAviationDB(registration: String) async -> String? {
        print("🔍 [AviationDB] Searching for registration: \(registration)")
        
        let cleanRegistration = registration.replacingOccurrences(of: "-", with: "")
        
        // Try various aviation database CDNs
        let possibleURLs = [
            "https://cdn.aviationdb.com/aircraft/\(cleanRegistration.lowercased()).jpg",
            "https://images.aviationdb.com/photos/\(cleanRegistration.uppercased())_1.jpg",
            "https://static.aviationdb.net/images/\(cleanRegistration.lowercased()).jpg"
        ]
        
        for (index, urlString) in possibleURLs.enumerated() {
            print("🔍 [AviationDB] Trying URL pattern \(index + 1): \(urlString)")
            if await isImageURLValid(urlString) {
                print("✅ [AviationDB] Found valid image at: \(urlString)")
                return urlString
            }
        }
        
        print("❌ [AviationDB] No photos found for \(registration)")
        return nil
    }
    
    /// Attempts to get photo from JetPhotos using alternative approaches
    private func fetchFromJetPhotosAlternative(registration: String) async -> String? {
        print("🔍 [JetPhotos Alt] Searching for registration: \(registration)")
        print("⚠️ [JetPhotos Alt] Using alternative URL patterns")
        
        let cleanRegistration = registration.replacingOccurrences(of: "-", with: "")
        
        // Try different JetPhotos URL patterns that might not be blocked
        let possibleURLs = [
            "https://images.jetphotos.com/img/\(cleanRegistration.lowercased()).jpg",
            "https://static.jetphotos.com/photos/\(cleanRegistration.uppercased())_1.jpg",
            "https://cdn2.jetphotos.com/400/\(cleanRegistration.lowercased()).jpg"
        ]
        
        for (index, urlString) in possibleURLs.enumerated() {
            print("🔍 [JetPhotos Alt] Trying URL pattern \(index + 1): \(urlString)")
            if await isImageURLValid(urlString) {
                print("✅ [JetPhotos Alt] Found valid image at: \(urlString)")
                return urlString
            }
        }
        
        print("❌ [JetPhotos Alt] No photos found for \(registration)")
        return nil
    }
    
    /// Attempts to get photo from generic aviation APIs and open sources
    private func fetchFromGenericAPIs(registration: String) async -> String? {
        print("🔍 [Generic APIs] Searching for registration: \(registration)")
        
        let cleanRegistration = registration.replacingOccurrences(of: "-", with: "")
        
        // Try some generic aviation photo sources
        let possibleURLs = [
            "https://aircraft-database.com/images/\(cleanRegistration.lowercased()).jpg",
            "https://registry.faa.gov/aircraftinquiry/photos/\(cleanRegistration.uppercased()).jpg",
            "https://openflights.org/img/aircraft/\(cleanRegistration.lowercased()).jpg",
            "https://aviation-safety.net/photos/\(cleanRegistration.uppercased())_1.jpg"
        ]
        
        for (index, urlString) in possibleURLs.enumerated() {
            print("🔍 [Generic APIs] Trying URL pattern \(index + 1): \(urlString)")
            if await isImageURLValid(urlString) {
                print("✅ [Generic APIs] Found valid image at: \(urlString)")
                return urlString
            }
        }
        
        print("❌ [Generic APIs] No photos found for \(registration)")
        return nil
    }
    
    /// Attempts to get photo from Planespotters
    private func fetchFromPlanespotters(registration: String) async -> String? {
        print("🔍 [Planespotters] Searching for registration: \(registration)")
        print("⚠️ [Planespotters] Note: This site also blocks automated access")
        
        // Planespotters.net approach - though they also block automated access
        let cleanRegistration = registration.replacingOccurrences(of: "-", with: "")
        let urlString = "https://cdn.planespotters.net/photo/400000/original/\(cleanRegistration.lowercased())_1.jpg"
        
        print("🔍 [Planespotters] Trying URL: \(urlString)")
        
        if await isImageURLValid(urlString) {
            print("✅ [Planespotters] Found valid image at: \(urlString)")
            return urlString
        } else {
            print("❌ [Planespotters] Blocked or not found: \(urlString)")
        }
        
        return nil
    }
    
    /// Generates a placeholder image URL for aircraft without photos
    private func generatePlaceholderImageURL(registration: String) -> String {
        // Use a service like placeholder.com or create a simple aircraft silhouette
        // For now, return a generic aircraft placeholder
        let encodedRegistration = registration.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? registration
        return "https://via.placeholder.com/400x300/E8E8E8/666666?text=Aircraft+\(encodedRegistration)"
    }
    
    /// Validates if an image URL returns a valid image
    private func isImageURLValid(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { 
            print("❌ [URLValidation] Invalid URL: \(urlString)")
            return false 
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD" // Only check headers, don't download full image
            request.timeoutInterval = 5.0
            
            print("🌐 [URLValidation] Checking URL: \(urlString)")
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { 
                print("❌ [URLValidation] Not an HTTP response: \(urlString)")
                return false 
            }
            
            let statusCode = httpResponse.statusCode
            let mimeType = httpResponse.mimeType ?? "unknown"
            
            print("📊 [URLValidation] Status: \(statusCode), MIME: \(mimeType) for \(urlString)")
            
            // Check if response is successful and content type is image
            let isValid = statusCode == 200 && mimeType.hasPrefix("image/")
            
            if isValid {
                print("✅ [URLValidation] Valid image found: \(urlString)")
            } else {
                print("❌ [URLValidation] Invalid - Status: \(statusCode), MIME: \(mimeType)")
            }
            
            return isValid
            
        } catch {
            print("❌ [URLValidation] Error checking \(urlString): \(error.localizedDescription)")
            return false
        }
    }
}

/// Extension to add photo fetching to FlightData
extension FlightData {
    
    /// Returns aircraft with photo URL populated if photos are enabled in settings
    func withAircraftPhoto(settingsManager: any SettingsManagerProtocol) async -> FlightData {
        print("📸 [FlightData] Checking if photo fetch needed for flight: \(self.displayIdentifier)")
        
        // Check if aircraft photos are enabled in settings
        guard await settingsManager.showAircraftPhotos else {
            print("ℹ️ [FlightData] Aircraft photos disabled in settings for flight: \(self.displayIdentifier)")
            return self
        }
        
        guard let aircraft = self.aircraft else {
            print("❌ [FlightData] No aircraft info available for flight: \(self.displayIdentifier)")
            return self
        }
        
        guard let registration = aircraft.registration else {
            print("❌ [FlightData] No registration available for flight: \(self.displayIdentifier)")
            return self
        }
        
        guard aircraft.photoURL == nil else {
            print("ℹ️ [FlightData] Photo already exists for flight: \(self.displayIdentifier)")
            return self
        }
        
        print("🚀 [FlightData] Starting photo fetch for \(self.displayIdentifier) with registration: \(registration)")
        
        let photoService = AircraftPhotoService()
        let photoURL = await photoService.fetchAircraftPhotoURL(registration: registration)
        
        let updatedAircraft = AircraftInfo(
            model: aircraft.model,
            code: aircraft.code,
            registration: aircraft.registration,
            photoURL: photoURL
        )
        
        if let photoURL = photoURL {
            print("✅ [FlightData] Photo fetch successful for \(self.displayIdentifier): \(photoURL)")
        } else {
            print("❌ [FlightData] Photo fetch failed for \(self.displayIdentifier)")
        }
        
        return FlightData(
            id: self.id,
            flightNumber: self.flightNumber,
            callsign: self.callsign,
            airline: self.airline,
            aircraft: updatedAircraft,
            route: self.route,
            position: self.position,
            lastUpdated: self.lastUpdated
        )
    }
    
    /// Returns aircraft with photo URL populated (legacy method for backward compatibility)
    func withAircraftPhoto() async -> FlightData {
        // For backward compatibility, assume photos are enabled if no settings manager is provided
        print("⚠️ [FlightData] Using legacy photo fetch method - consider using withAircraftPhoto(settingsManager:)")
        
        guard let aircraft = self.aircraft else {
            print("❌ [FlightData] No aircraft info available for flight: \(self.displayIdentifier)")
            return self
        }
        
        guard let registration = aircraft.registration else {
            print("❌ [FlightData] No registration available for flight: \(self.displayIdentifier)")
            return self
        }
        
        guard aircraft.photoURL == nil else {
            print("ℹ️ [FlightData] Photo already exists for flight: \(self.displayIdentifier)")
            return self
        }
        
        print("🚀 [FlightData] Starting photo fetch for \(self.displayIdentifier) with registration: \(registration)")
        
        let photoService = AircraftPhotoService()
        let photoURL = await photoService.fetchAircraftPhotoURL(registration: registration)
        
        let updatedAircraft = AircraftInfo(
            model: aircraft.model,
            code: aircraft.code,
            registration: aircraft.registration,
            photoURL: photoURL
        )
        
        if let photoURL = photoURL {
            print("✅ [FlightData] Photo fetch successful for \(self.displayIdentifier): \(photoURL)")
        } else {
            print("❌ [FlightData] Photo fetch failed for \(self.displayIdentifier)")
        }
        
        return FlightData(
            id: self.id,
            flightNumber: self.flightNumber,
            callsign: self.callsign,
            airline: self.airline,
            aircraft: updatedAircraft,
            route: self.route,
            position: self.position,
            lastUpdated: self.lastUpdated
        )
    }
}
#endif
