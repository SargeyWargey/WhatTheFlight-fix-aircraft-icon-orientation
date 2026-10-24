// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  FlightDisplayView.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import SwiftUI
import CoreLocation
#if os(iOS)
import UIKit
import SafariServices
#elseif os(macOS)
import AppKit
import WebKit
#endif

/// Main view for displaying flight information in radar-style layout
struct FlightDisplayView: View {
    @ObservedObject var viewModel: MainViewModel
    @StateObject private var motionManager = MotionManager()
    @StateObject private var iconLayeringManager = IconLayeringManager()
    @State private var showDetailCard = false
    @State private var showPerimeterFlightDetail = false
    @State private var selectedPerimeterFlight: FlightData?
    @State private var showUnlockMessage = false
    @State private var showingSearch = false
    
    #if os(tvOS)
    @State private var currentTvOrientationDegrees: Double = 0.0
    #endif
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    
    var body: some View {
        radarDisplayContent
        .task {
            // Use .task for better lifecycle management
            motionManager.startMotionUpdates()
        }
        .onDisappear {
            motionManager.stopMotionUpdates()
        }
        #if os(tvOS)
        .onAppear {
            let orientationValue = viewModel.settingsManager.displayPreferences.tvOSOrientationDegrees
            print("FlightDisplayView onAppear: orientation=\(orientationValue)")
            currentTvOrientationDegrees = orientationValue
        }
        .onChange(of: viewModel.settingsManager.displayPreferences.tvOSOrientationDegrees) { _, newValue in
            print("FlightDisplayView orientation changed to: \(newValue)")
            currentTvOrientationDegrees = newValue
        }
        #endif
    }
    
    @ViewBuilder
    private var radarDisplayContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                mainBackgroundColor
                    .ignoresSafeArea()
                
                // Center flight display with swipe gestures
                centerFlightDisplayView
                
                // Perimeter aircraft positioned at main view edges
                perimeterAircraftOverlay(geometry: geometry)
                
                // Detail card overlay
                detailCardOverlay
                
                // Unlock message overlay
                unlockMessageOverlay
            }
        }
        .sheet(isPresented: $showingSearch) {
            SearchView(viewModel: viewModel)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSearchFromSwipe)) { _ in
            showingSearch = true
        }
    }
    
    @ViewBuilder
    private var centerFlightDisplayView: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                
                #if os(iOS)
                // Card container for iOS with fixed size
                let cardWidth = min(geometry.size.width * 0.65, 400)
                let cardHeight = min(geometry.size.height * 0.6, 500)
                
                HStack {
                    Spacer()
                    ZStack {
                        // Card background
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.regularMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                            .frame(width: cardWidth, height: cardHeight)
                        
                        // Content inside card
                        if viewModel.flights.isEmpty {
                            NoFlightsView(
                                isMonitoring: viewModel.isMonitoring,
                                statusMessage: viewModel.statusMessage,
                                onSettingsRequest: {
                                    viewModel.showSettings()
                                }
                            )
                            .frame(width: cardWidth * 0.9, height: cardHeight * 0.9)
                            .clipped()
                        } else if let currentFlight = viewModel.currentFlight {
                            CenterFlightView(
                                flight: currentFlight,
                                userLocation: userLocation,
                                motionManager: motionManager,
                                settingsManager: viewModel.settingsManager,
                                viewModel: viewModel
                            )
                            .frame(width: cardWidth * 0.9, height: cardHeight * 0.9)
                            .clipped()
                            .onTapGesture {
                                // Open flight details
                                showDetailCard = true
                            }
                        }
                    }
                    Spacer()
                }
                #elseif os(tvOS)
                // tvOS centered layout
                HStack {
                    Spacer()
                    if viewModel.flights.isEmpty {
                        NoFlightsView(
                            isMonitoring: viewModel.isMonitoring,
                            statusMessage: viewModel.statusMessage,
                            onSettingsRequest: {
                                viewModel.showSettings()
                            }
                        )
                    } else if let currentFlight = viewModel.currentFlight {
                        CenterFlightView(
                            flight: currentFlight,
                            userLocation: userLocation,
                            motionManager: motionManager,
                            settingsManager: viewModel.settingsManager,
                            viewModel: viewModel
                        )
                        .onTapGesture {
                            // Open flight details
                            showDetailCard = true
                        }
                    }
                    Spacer()
                }
                #else
                // Original layout for macOS
                if viewModel.flights.isEmpty {
                    NoFlightsView(
                        isMonitoring: viewModel.isMonitoring,
                        statusMessage: viewModel.statusMessage,
                        onSettingsRequest: {
                            viewModel.showSettings()
                        }
                    )
                } else if let currentFlight = viewModel.currentFlight {
                    CenterFlightView(
                        flight: currentFlight,
                        userLocation: userLocation,
                        motionManager: motionManager,
                        settingsManager: viewModel.settingsManager,
                        viewModel: viewModel
                    )
                    .onTapGesture {
                        // Open flight details
                        showDetailCard = true
                    }
                }
                #endif
                
                Spacer()
            }
        }
        #if !os(tvOS)
        .gesture(mainSwipeGesture)
        #endif
        .sheet(isPresented: $showDetailCard) {
            if let currentFlight = viewModel.currentFlight {
                FlightDetailView(
                    flight: currentFlight, 
                    settingsManager: viewModel.settingsManager,
                    locationManager: viewModel.locationManager,
                    viewModel: viewModel
                )
            }
        }
        .sheet(isPresented: $showPerimeterFlightDetail) {
            if let selectedFlight = selectedPerimeterFlight {
                FlightDetailView(
                    flight: selectedFlight, 
                    settingsManager: viewModel.settingsManager,
                    locationManager: viewModel.locationManager,
                    viewModel: viewModel
                )
            }
        }
        #if os(macOS)
        .accessibilityIdentifier("flight_display_area")
        .contextMenu {
            ForEach(macOSContextMenuItems, id: \.title) { item in
                Button(item.title) {
                    item.action()
                }
                .keyboardShortcut(item.keyboardShortcut ?? KeyboardShortcut(.clear))
            }
        }
        #endif
    }
    
    #if !os(tvOS)
    private var mainSwipeGesture: some Gesture {
        DragGesture()
            .onEnded { value in
                let threshold: CGFloat = 50
                
                if value.translation.height < -threshold {
                    // Swipe up - show settings menu
                    viewModel.showSettings()
                } else if value.translation.height > threshold {
                    // Swipe down - show search
                    viewModel.showSearch()
                } else if value.translation.width > threshold {
                    // Swipe right - go to previous aircraft (closer)
                    if viewModel.isAircraftLocked {
                        displayUnlockMessage()
                    } else {
                        viewModel.selectPreviousAircraft()
                    }
                } else if value.translation.width < -threshold {
                    // Swipe left - go to next aircraft (farther)
                    if viewModel.isAircraftLocked {
                        displayUnlockMessage()
                    } else {
                        viewModel.selectNextAircraft()
                    }
                }
            }
    }
    #endif
    
    @ViewBuilder
    private func perimeterAircraftOverlay(geometry: GeometryProxy) -> some View {
        #if !os(tvOS)
        // Only render aircraft in container for non-tvOS platforms
        // tvOS uses full-screen overlay to bypass container padding
        if viewModel.settingsManager.showAircraftIcons {
            // Limit perimeter aircraft for performance (show max 20 closest)
            let limitedFlights = Array(perimeterFlights.prefix(20))
            
            // Calculate positions and distances for layering
            let positions = calculateAircraftPositions(flights: limitedFlights, geometry: geometry)
            let distances = calculateAircraftDistances(flights: limitedFlights)
            
            // Calculate layering information
            let layeredIcons = iconLayeringManager.calculateLayering(
                flights: limitedFlights,
                positions: positions,
                distances: distances,
                focusedFlightId: viewModel.currentFlight?.id,
                proximityThreshold: viewModel.settingsManager.displayPreferences.proximityDistanceThreshold
            )
            
            ForEach(layeredIcons, id: \.flight.id) { layerInfo in
                PerimeterAircraftView(
                    flight: layerInfo.flight,
                    userLocation: userLocation,
                    screenSize: {
                        #if os(tvOS)
                        // Use true screen size for tvOS to bypass container padding
                        return CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                        #else
                        // Use geometry size for iOS (preserves existing behavior)
                        return geometry.size
                        #endif
                    }(),
                    safeAreaInsets: geometry.safeAreaInsets,
                    motionManager: motionManager,
                    currentFlight: viewModel.currentFlight,
                    layerInfo: layerInfo,
                    selectedPerimeterFlight: $selectedPerimeterFlight,
                    showPerimeterFlightDetail: $showPerimeterFlightDetail,
                    onAircraftTapped: { tappedFlight in
                        if viewModel.isAircraftLocked {
                            displayUnlockMessage()
                        } else {
                            viewModel.selectAircraft(tappedFlight)
                        }
                    }
                )
            }
        }
        #endif
    }
    
    @ViewBuilder
    private var detailCardOverlay: some View {
        EmptyView()
    }
    
    /// Helper function to show the unlock message with consistent timing and animation
    private func displayUnlockMessage() {
        showUnlockMessage = true
        
        // Hide message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showUnlockMessage = false
        }
    }
    
    @ViewBuilder
    private var unlockMessageOverlay: some View {
        if showUnlockMessage {
            VStack {
                Text("Hold Flight Number to Unlock")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.1))
                    )
                    .opacity(showUnlockMessage ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.5), value: showUnlockMessage)
                
                Spacer()
            }
            .padding(.top, 20)
        }
    }
    

    
    
    private var userLocation: CLLocation? {
        guard let bounds = viewModel.settingsManager.geographicBounds else { return nil }
        let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
        let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
        return CLLocation(latitude: centerLat, longitude: centerLon)
    }
    
    private var perimeterFlights: [FlightData] {
        // Show ALL aircraft on perimeter
        return viewModel.flights
    }
    
    /// Calculate positions for all aircraft icons using predicted positions
    private func calculateAircraftPositions(flights: [FlightData], geometry: GeometryProxy) -> [String: CGPoint] {
        var positions: [String: CGPoint] = [:]
        
        for flight in flights {
            if let userLocation = userLocation {
                // Use predicted bearing if available, otherwise fall back to current bearing
                let bearing: Double
                if let predictedBearing = viewModel.getPredictedBearing(for: flight) {
                    bearing = predictedBearing
                } else if let currentBearing = flight.bearingFromLocation(userLocation) {
                    bearing = currentBearing
                } else {
                    continue // Skip if no bearing available
                }
                
                let compassAwareBearing = calculateCompassAwareBearing(bearing: bearing)
                let position = calculateAircraftPosition(bearing: compassAwareBearing, geometry: geometry)
                positions[flight.id] = position
            }
        }
        
        return positions
    }
    
    /// Calculate distances for all aircraft using predicted positions
    private func calculateAircraftDistances(flights: [FlightData]) -> [String: Double] {
        var distances: [String: Double] = [:]
        
        for flight in flights {
            if let userLocation = userLocation {
                // Use predicted distance if available, otherwise fall back to current distance
                let distance: Double
                if let predictedDistance = viewModel.getPredictedDistance(for: flight) {
                    distance = predictedDistance
                } else if let currentDistance = flight.distanceFromLocation(userLocation) {
                    distance = currentDistance
                } else {
                    continue // Skip if no distance available
                }
                
                distances[flight.id] = distance
            }
        }
        
        return distances
    }
    
    /// Calculate compass-aware bearing that adjusts for device rotation
    private func calculateCompassAwareBearing(bearing: Double) -> Double {
        #if os(tvOS)
        let adjustedBearing = bearing + currentTvOrientationDegrees
        #else
        let adjustedBearing = bearing - motionManager.currentHeading
        #endif
        let normalized = adjustedBearing.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Calculate aircraft position on screen edge
    private func calculateAircraftPosition(bearing: Double, geometry: GeometryProxy) -> CGPoint {
        let iconRadius: CGFloat = 12
        let edgeBuffer: CGFloat = 5
        let bottomExtraBuffer: CGFloat = 0
        
        #if os(tvOS)
        // For tvOS, position aircraft icons right at the screen edges
        let topMargin: CGFloat = iconRadius // Just icon radius from top edge
        let bottomMargin: CGFloat = iconRadius // Just icon radius from bottom edge  
        let leftMargin: CGFloat = iconRadius // Just icon radius from left edge
        let rightMargin: CGFloat = iconRadius // Just icon radius from right edge
        #else
        let topMargin: CGFloat = geometry.safeAreaInsets.top + 0 + edgeBuffer
        let bottomMargin: CGFloat = geometry.safeAreaInsets.bottom + 0 + edgeBuffer + bottomExtraBuffer
        let leftMargin: CGFloat = geometry.safeAreaInsets.leading + iconRadius + edgeBuffer
        let rightMargin: CGFloat = geometry.safeAreaInsets.trailing + iconRadius + edgeBuffer
        #endif
        
        let availableWidth = geometry.size.width - leftMargin - rightMargin
        let availableHeight = geometry.size.height - topMargin - bottomMargin
        let centerX = leftMargin + (availableWidth / 2)
        let centerY = topMargin + (availableHeight / 2)
        
        let radians = (bearing - 90) * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        
        let distanceToLeftEdge = dx < 0 ? abs((availableWidth / 2) / dx) : CGFloat.greatestFiniteMagnitude
        let distanceToRightEdge = dx > 0 ? abs((availableWidth / 2) / dx) : CGFloat.greatestFiniteMagnitude
        let distanceToTopEdge = dy < 0 ? abs((availableHeight / 2) / dy) : CGFloat.greatestFiniteMagnitude
        let distanceToBottomEdge = dy > 0 ? abs((availableHeight / 2) / dy) : CGFloat.greatestFiniteMagnitude
        
        let minDistance = min(min(distanceToLeftEdge, distanceToRightEdge), min(distanceToTopEdge, distanceToBottomEdge))
        
        let x = centerX + dx * minDistance
        let y = centerY + dy * minDistance
        
        let clampedX = max(leftMargin, min(geometry.size.width - rightMargin, x))
        let clampedY = max(topMargin, min(geometry.size.height - bottomMargin, y))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
}


/// Compass-aware directional arrow that stays pointed at aircraft regardless of device rotation
struct CompassAwareArrow: View {
    let flight: FlightData
    let userLocation: CLLocation?
    let deviceHeading: Double
    let viewModel: MainViewModel
    
    @State private var continuousRotation: Double = 0
    @State private var isInitialized: Bool = false
    
    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 32, weight: .bold))
            .foregroundColor(isApproaching ? .green : .red)
            .rotationEffect(.degrees(continuousRotation))
            .animation(.easeInOut(duration: isInitialized ? 1.0 : 0.0), value: continuousRotation)
            .onAppear {
                let bearing = adjustedBearing
                continuousRotation = bearing
                isInitialized = true
            }
            .onChange(of: adjustedBearing) { _, newBearing in
                if isInitialized {
                    updateContinuousRotation(to: newBearing)
                } else {
                    // First update, no animation
                    continuousRotation = newBearing
                    isInitialized = true
                }
            }
    }
    
    /// Calculate the arrow rotation accounting for device orientation and predicted position
    private var adjustedBearing: Double {
        // Use predicted bearing if available, otherwise fall back to current bearing
        let bearing: Double
        if let predictedBearing = viewModel.getPredictedBearing(for: flight) {
            bearing = predictedBearing
        } else if let userLocation = userLocation,
                  let currentBearing = flight.bearingFromLocation(userLocation) {
            bearing = currentBearing
        } else {
            bearing = 0
        }
        
        // Adjust aircraft bearing by device heading to maintain fixed direction
        let adjusted = bearing - deviceHeading
        
        // Normalize to 0-360 range
        let normalized = adjusted.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Determine if aircraft is approaching based on predicted or current data
    private var isApproaching: Bool {
        if let userLocation = userLocation {
            return flight.isMovingTowardsLocation(userLocation) == true
        }
        return false
    }
    
    /// Update rotation with smooth transition, allowing continuous rotation beyond 360°
    private func updateContinuousRotation(to newBearing: Double) {
        // Get the current rotation normalized to 0-360 range
        let currentNormalized = continuousRotation.truncatingRemainder(dividingBy: 360)
        let normalizedCurrent = currentNormalized < 0 ? currentNormalized + 360 : currentNormalized
        
        // Calculate the difference between new bearing and current normalized rotation
        let diff = newBearing - normalizedCurrent
        
        // Choose the shortest path
        if abs(diff) > 180 {
            // We're crossing the 0°/360° boundary, choose shorter path
            if diff > 0 {
                // Going from ~359° to ~0°, rotate backwards (shorter path)
                continuousRotation += diff - 360
            } else {
                // Going from ~0° to ~359°, rotate forwards (shorter path)
                continuousRotation += diff + 360
            }
        } else {
            // Normal transition, add the difference to maintain continuous rotation
            continuousRotation += diff
        }
    }
}

/// Center flight display view
struct CenterFlightView: View {
    let flight: FlightData
    let userLocation: CLLocation?
    @ObservedObject var motionManager: MotionManager
    let settingsManager: any SettingsManagerProtocol
    let viewModel: MainViewModel
    @State private var flightWithPhoto: FlightData
    
    init(flight: FlightData, userLocation: CLLocation?, motionManager: MotionManager, settingsManager: any SettingsManagerProtocol, viewModel: MainViewModel) {
        self.flight = flight
        self.userLocation = userLocation
        self.motionManager = motionManager
        self.settingsManager = settingsManager
        self.viewModel = viewModel
        self._flightWithPhoto = State(initialValue: flight)
    }
    
    var body: some View {
        // Use ViewThatFits for adaptive layout based on available space
        ViewThatFits(in: .vertical) {
            // Full layout for larger screens
            fullFlightLayout
            
            // Compact layout for smaller screens
            compactFlightLayout
        }
        .task(id: flight.id) {
            // Load aircraft photo if enabled and not already loaded
            if settingsManager.showAircraftPhotos && flightWithPhoto.aircraft?.photoURL == nil {
                flightWithPhoto = await flight.withAircraftPhoto(settingsManager: settingsManager)
            }
        }
        .onChange(of: flight) { _, newFlight in
            // Update flight data immediately for real-time updates
            // This ensures altitude, speed, distance, ETA all update in real-time
            flightWithPhoto = newFlight
            
            // Handle photo separately if photos are enabled and we don't have one yet
            if settingsManager.showAircraftPhotos && flightWithPhoto.aircraft?.photoURL == nil {
                Task {
                    flightWithPhoto = await newFlight.withAircraftPhoto(settingsManager: settingsManager)
                }
            }
        }
    }
    
    @ViewBuilder
    private var fullFlightLayout: some View {
        VStack(spacing: 12) {
            // Aircraft Photo (if enabled and available)
            aircraftPhotoSection
            
            // Flight Number with Lock Icon - Large, bold, blue
            HStack(alignment: .center, spacing: 8) {
                if viewModel.isAircraftLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.red)
                }
                
                Text(flightWithPhoto.displayIdentifier)
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.blue)
            }
            .onLongPressGesture {
                viewModel.toggleAircraftLock()
            }
            
            // Route - SFO → ATL style with red arrow
            if let route = flightWithPhoto.route {
                HStack(spacing: 12) {
                    // Origin
                    Text(route.origin.iataCode)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue.opacity(0.7))
                    
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundColor(.red)
                    
                    // Destination
                    Text(route.destination.iataCode)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.blue.opacity(0.7))
                }
            }
            
            // Aircraft Type - Gray, smaller
            if let aircraft = flightWithPhoto.aircraft {
                Text(aircraft.code.isEmpty ? aircraft.model : aircraft.code)
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            
            // Compass-Aware Directional Arrow (moved from bottom)
            CompassAwareArrow(
                flight: flightWithPhoto,
                userLocation: userLocation,
                deviceHeading: motionManager.currentHeading,
                viewModel: viewModel
            )
            .font(.title2)
            
            // Altitude and Speed - Two columns side by side
            HStack(spacing: 60) {
                // Altitude
                if let position = flightWithPhoto.position, let altitude = position.altitude {
                    VStack(spacing: 4) {
                        Text("Altitude")
                            .font(.title3)
                            .foregroundColor(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(altitude)")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("ft")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Speed
                if let position = flightWithPhoto.position, let speed = position.speed {
                    VStack(spacing: 4) {
                        Text("Speed")
                            .font(.title3)
                            .foregroundColor(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(speed)")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("kts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Distance display
            if let userLocation = userLocation,
               let _ = flightWithPhoto.distanceFromLocation(userLocation),
               let _ = flightWithPhoto.position {
                PredictiveCountdownDistanceView(
                    flight: flightWithPhoto,
                    userLocation: userLocation,
                    viewModel: viewModel
                )
            }
            
            // Nearest approach distance with predictions - only show if aircraft is approaching and has ETA
            if let userLocation = userLocation,
               let _ = flightWithPhoto.etaToNearestPoint(from: userLocation),
               flightWithPhoto.isMovingTowardsLocation(userLocation) == true {
                PredictiveNearestApproachView(
                    flight: flightWithPhoto,
                    userLocation: userLocation,
                    viewModel: viewModel,
                    motionManager: motionManager
                )
            }
        }
    }
    
    @ViewBuilder
    private var compactFlightLayout: some View {
        VStack(spacing: 8) {
            // Smaller flight number for compact screens with lock icon
            HStack(alignment: .center, spacing: 6) {
                if viewModel.isAircraftLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(.red)
                }
                
                Text(flightWithPhoto.displayIdentifier)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.blue)
            }
            .onLongPressGesture {
                viewModel.toggleAircraftLock()
            }
            
            // Route in compact format
            if let route = flightWithPhoto.route {
                HStack(spacing: 6) {
                    Text(route.origin.iataCode)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue.opacity(0.7))
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(route.destination.iataCode)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue.opacity(0.7))
                }
            }
            
            // Compact data layout - single row
            HStack(spacing: 16) {
                if let position = flightWithPhoto.position, let altitude = position.altitude {
                    VStack(spacing: 4) {
                        Text("Alt")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(altitude)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("ft")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let position = flightWithPhoto.position, let speed = position.speed {
                    VStack(spacing: 4) {
                        Text("Spd")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(speed)")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("kts")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let userLocation = userLocation,
                   let _ = flightWithPhoto.distanceFromLocation(userLocation),
                   let _ = flightWithPhoto.position {
                    VStack(spacing: 4) {
                        Text("Dist")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            PredictiveCountdownDistanceText(
                                flight: flightWithPhoto,
                                userLocation: userLocation,
                                viewModel: viewModel
                            )
                            Text("mi")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Nearest approach distance in compact layout with predictions
                if let userLocation = userLocation,
                   let _ = flightWithPhoto.etaToNearestPoint(from: userLocation),
                   flightWithPhoto.isMovingTowardsLocation(userLocation) == true {
                    VStack(spacing: 4) {
                        Text("Near")
                            .font(.caption2)
                            .foregroundColor(.gray)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            PredictiveNearestApproachText(
                                flight: flightWithPhoto,
                                userLocation: userLocation,
                                viewModel: viewModel,
                                motionManager: motionManager
                            )
                            Text("mi")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var aircraftPhotoSection: some View {
        if settingsManager.showAircraftPhotos,
           let aircraft = flightWithPhoto.aircraft,
           let photoURL = aircraft.photoURL,
           let url = URL(string: photoURL) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 200, maxHeight: 120)
                    .cornerRadius(8)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 120)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
            }
        }
    }
}

/// Real-time countdown distance text component for compact layouts
struct CountdownDistanceText: View {
    let initialDistance: Double
    let flightId: String
    let lastUpdated: Date
    let aircraftSpeed: Int?
    let aircraftHeading: Int?
    let userLocation: CLLocation
    let aircraftPosition: FlightPosition
    
    @State private var currentDistance: Double = 0
    @State private var timer: Timer?
    
    init(initialDistance: Double, flightId: String, lastUpdated: Date, 
         aircraftSpeed: Int?, aircraftHeading: Int?, userLocation: CLLocation, 
         aircraftPosition: FlightPosition) {
        self.initialDistance = initialDistance
        self.flightId = flightId
        self.lastUpdated = lastUpdated
        self.aircraftSpeed = aircraftSpeed
        self.aircraftHeading = aircraftHeading
        self.userLocation = userLocation
        self.aircraftPosition = aircraftPosition
        self._currentDistance = State(initialValue: initialDistance)
    }
    
    var body: some View {
        Text("\(String(format: "%.0f", currentDistance))")
            .font(.caption)
            .fontWeight(.medium)
            .onAppear {
                startDistanceUpdates()
            }
            .onDisappear {
                stopDistanceUpdates()
            }
            .onChange(of: lastUpdated) { _, _ in
                resetDistance()
            }
            .onChange(of: flightId) { _, _ in
                resetDistance()
            }
    }
    
    private func startDistanceUpdates() {
        stopDistanceUpdates()
        
        guard let speed = aircraftSpeed, 
              let _ = aircraftHeading,
              speed > 0 else {
            return
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateDistanceEstimate()
        }
    }
    
    private func stopDistanceUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetDistance() {
        stopDistanceUpdates()
        currentDistance = initialDistance
        startDistanceUpdates()
    }
    
    private func updateDistanceEstimate() {
        guard let speed = aircraftSpeed,
              let heading = aircraftHeading,
              speed > 0 else {
            return
        }
        
        // Convert speed from knots to miles per second
        let speedMilesPerSecond = Double(speed) * 0.000277778 // knots to miles/sec
        
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Calculate current aircraft position (estimated)
        let timeElapsed = Date().timeIntervalSince(lastUpdated)
        
        // Estimate new aircraft position based on heading and speed
        let distanceTraveled = speedMilesPerSecond * timeElapsed
        
        // Calculate new latitude and longitude (simplified great circle approximation)
        let earthRadius = 3959.0 // miles
        let lat1 = aircraftPosition.latitude * .pi / 180
        let lon1 = aircraftPosition.longitude * .pi / 180
        
        let lat2 = asin(sin(lat1) * cos(distanceTraveled / earthRadius) + 
                       cos(lat1) * sin(distanceTraveled / earthRadius) * cos(headingRadians))
        let lon2 = lon1 + atan2(sin(headingRadians) * sin(distanceTraveled / earthRadius) * cos(lat1),
                               cos(distanceTraveled / earthRadius) - sin(lat1) * sin(lat2))
        
        // Convert back to degrees
        let newLat = lat2 * 180 / .pi
        let newLon = lon2 * 180 / .pi
        
        // Calculate new distance to user
        let estimatedAircraftLocation = CLLocation(latitude: newLat, longitude: newLon)
        let newDistance = userLocation.distance(from: estimatedAircraftLocation) * 0.000621371 // meters to miles
        
        currentDistance = max(0, newDistance)
    }
}

/// Real-time countdown distance view that updates based on aircraft movement
struct CountdownDistanceView: View {
    let initialDistance: Double
    let flightId: String
    let lastUpdated: Date
    let aircraftSpeed: Int?
    let aircraftHeading: Int?
    let userLocation: CLLocation
    let aircraftPosition: FlightPosition
    
    @State private var currentDistance: Double = 0
    @State private var timer: Timer?
    
    init(initialDistance: Double, flightId: String, lastUpdated: Date, 
         aircraftSpeed: Int?, aircraftHeading: Int?, userLocation: CLLocation, 
         aircraftPosition: FlightPosition) {
        self.initialDistance = initialDistance
        self.flightId = flightId
        self.lastUpdated = lastUpdated
        self.aircraftSpeed = aircraftSpeed
        self.aircraftHeading = aircraftHeading
        self.userLocation = userLocation
        self.aircraftPosition = aircraftPosition
        self._currentDistance = State(initialValue: initialDistance)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Distance")
                .font(.title3)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(String(format: "%.1f", currentDistance))")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("mi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            startDistanceUpdates()
        }
        .onDisappear {
            stopDistanceUpdates()
        }
        .onChange(of: lastUpdated) { _, _ in
            resetDistance()
        }
        .onChange(of: flightId) { _, _ in
            resetDistance()
        }
    }
    
    private func startDistanceUpdates() {
        stopDistanceUpdates()
        
        guard let speed = aircraftSpeed, 
              let _ = aircraftHeading,
              speed > 0 else {
            return
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateDistanceEstimate()
        }
    }
    
    private func stopDistanceUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetDistance() {
        stopDistanceUpdates()
        currentDistance = initialDistance
        startDistanceUpdates()
    }
    
    private func updateDistanceEstimate() {
        guard let speed = aircraftSpeed,
              let heading = aircraftHeading,
              speed > 0 else {
            return
        }
        
        // Convert speed from knots to miles per second
        let speedMilesPerSecond = Double(speed) * 0.000277778 // knots to miles/sec
        
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Calculate current aircraft position (estimated)
        let timeElapsed = Date().timeIntervalSince(lastUpdated)
        
        // Estimate new aircraft position based on heading and speed
        let distanceTraveled = speedMilesPerSecond * timeElapsed
        
        // Calculate new latitude and longitude (simplified great circle approximation)
        let earthRadius = 3959.0 // miles
        let lat1 = aircraftPosition.latitude * .pi / 180
        let lon1 = aircraftPosition.longitude * .pi / 180
        
        let lat2 = asin(sin(lat1) * cos(distanceTraveled / earthRadius) + 
                       cos(lat1) * sin(distanceTraveled / earthRadius) * cos(headingRadians))
        let lon2 = lon1 + atan2(sin(headingRadians) * sin(distanceTraveled / earthRadius) * cos(lat1),
                               cos(distanceTraveled / earthRadius) - sin(lat1) * sin(lat2))
        
        // Convert back to degrees
        let newLat = lat2 * 180 / .pi
        let newLon = lon2 * 180 / .pi
        
        // Calculate new distance to user
        let estimatedAircraftLocation = CLLocation(latitude: newLat, longitude: newLon)
        let newDistance = userLocation.distance(from: estimatedAircraftLocation) * 0.000621371 // meters to miles
        
        currentDistance = max(0, newDistance)
    }
}

/// Real-time countdown ETA view that decrements every second
struct CountdownETAView: View {
    let initialETA: String
    let flightId: String
    let lastUpdated: Date
    
    @State private var currentMinutes: Int = 0
    @State private var currentSeconds: Int = 0
    @State private var timer: Timer?
    @State private var totalSeconds: Int
    
    init(initialETA: String, flightId: String, lastUpdated: Date) {
        self.initialETA = initialETA
        self.flightId = flightId
        self.lastUpdated = lastUpdated
        
        // Parse initial ETA (format: "7m 34s") into total seconds
        let minutesPattern = /(\d+)m/
        let secondsPattern = /(\d+)s/
        
        let minutes = Int(initialETA.firstMatch(of: minutesPattern)?.1 ?? "0") ?? 0
        let seconds = Int(initialETA.firstMatch(of: secondsPattern)?.1 ?? "0") ?? 0
        let total = minutes * 60 + seconds
        
        self._totalSeconds = State(initialValue: total)
        self._currentMinutes = State(initialValue: minutes)
        self._currentSeconds = State(initialValue: seconds)
    }
    
    var body: some View {
        VStack(spacing: 4) {
            Text("ETA")
                .font(.title3)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(currentMinutes)")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("m")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(currentSeconds)")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            startCountdown()
        }
        .onDisappear {
            stopCountdown()
        }
        .onChange(of: lastUpdated) { _, _ in
            // Reset countdown when flight data is updated
            resetCountdown()
        }
        .onChange(of: flightId) { _, _ in
            // Reset countdown when switching to different flight
            resetCountdown()
        }
    }
    
    private func startCountdown() {
        stopCountdown() // Stop any existing timer
        
        guard totalSeconds > 0 else {
            currentMinutes = 0
            currentSeconds = 0
            return
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if totalSeconds > 0 {
                totalSeconds -= 1
                updateETADisplay()
            } else {
                // ETA reached, stop countdown
                currentMinutes = 0
                currentSeconds = 0
                stopCountdown()
            }
        }
    }
    
    private func stopCountdown() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetCountdown() {
        stopCountdown()
        
        // Parse the new initial ETA (format: "7m 34s")
        let minutesPattern = /(\d+)m/
        let secondsPattern = /(\d+)s/
        
        let minutes = Int(initialETA.firstMatch(of: minutesPattern)?.1 ?? "0") ?? 0
        let seconds = Int(initialETA.firstMatch(of: secondsPattern)?.1 ?? "0") ?? 0
        totalSeconds = minutes * 60 + seconds
        currentMinutes = minutes
        currentSeconds = seconds
        
        startCountdown()
    }
    
    private func updateETADisplay() {
        currentMinutes = totalSeconds / 60
        currentSeconds = totalSeconds % 60
    }
}

/// Perimeter aircraft view positioned around screen edges with compass-aware positioning
struct PerimeterAircraftView: View {
    let flight: FlightData
    let userLocation: CLLocation?
    let screenSize: CGSize
    let safeAreaInsets: EdgeInsets
    @ObservedObject var motionManager: MotionManager
    let currentFlight: FlightData?
    let layerInfo: AircraftIconLayer
    @Binding var selectedPerimeterFlight: FlightData?
    @Binding var showPerimeterFlightDetail: Bool
    let onAircraftTapped: (FlightData) -> Void
    
    @State private var animatedPosition: CGPoint = .zero
    @State private var animatedDistancePosition: CGPoint = .zero
    @State private var isInitialized: Bool = false
    @State private var isNewlyAppeared: Bool = true
    @State private var entryOpacity: Double = 0.0
    
    var body: some View {
        if let userLocation = userLocation,
           let bearing = flight.bearingFromLocation(userLocation) {
            
            let compassAwareBearing = calculateCompassAwareBearing(bearing: bearing)
            let targetAircraftPosition = layerInfo.position
            let targetDistancePosition = calculateDistancePosition(bearing: compassAwareBearing, aircraftPosition: targetAircraftPosition)
            let isMovingTowards = flight.isMovingTowardsLocation(userLocation) ?? false
            let isHelicopter = flight.isHelicopter
            let isCurrentlySelectedAircraft = flight.id == currentFlight?.id
            let isNearProximityThreshold = flight.isNearProximityThreshold(to: userLocation, threshold: layerInfo.proximityThreshold)
            
            ZStack {
                // Aircraft icon with smooth positioning
                Group {
                    if isHelicopter {
                        Image("helicopter-bottom-view")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "airplane")
                            .font(.title2)
                    }
                }
                    .foregroundColor(
                        isCurrentlySelectedAircraft ? .green : 
                        isNearProximityThreshold ? .orange : .blue
                    )
                    .rotationEffect(.degrees(calculateIconRotation(flight: flight, compassAwareBearing: compassAwareBearing, isMovingTowards: isMovingTowards)))
                    .opacity(layerInfo.opacity * entryOpacity)
                    .zIndex(Double(layerInfo.zIndex))
                    .position(x: animatedPosition.x, y: animatedPosition.y)
                    .gesture(
                        TapGesture(count: 2)
                            .onEnded {
                                // Double tap - show flight details
                                selectedPerimeterFlight = flight
                                showPerimeterFlightDetail = true
                            }
                    )
                    .gesture(
                        TapGesture(count: 1)
                            .onEnded {
                                // Single tap - select aircraft
                                onAircraftTapped(flight)
                            }
                    )
                
                // Distance label with smooth positioning
                Text("\(String(format: "%.0f", layerInfo.distance))")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .opacity(layerInfo.opacity * entryOpacity)
                    .zIndex(Double(layerInfo.zIndex))
                    .position(x: animatedDistancePosition.x, y: animatedDistancePosition.y)
            }
            .onAppear {
                // Start aircraft from offscreen position for smooth entry animation
                let offscreenAircraftPosition = calculateOffscreenStartPosition(
                    bearing: compassAwareBearing, 
                    targetPosition: targetAircraftPosition
                )
                let offscreenDistancePosition = calculateOffscreenStartPosition(
                    bearing: compassAwareBearing, 
                    targetPosition: targetDistancePosition
                )
                animatedPosition = offscreenAircraftPosition
                animatedDistancePosition = offscreenDistancePosition
                
                // Animate to final position after a brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 1.5)) {
                        animatedPosition = targetAircraftPosition
                        animatedDistancePosition = targetDistancePosition
                        entryOpacity = 1.0
                        isNewlyAppeared = false
                    }
                }
                isInitialized = true
            }
            .onChange(of: targetAircraftPosition) { _, newPosition in
                if isInitialized && !isNewlyAppeared {
                    // Normal position update for existing aircraft
                    withAnimation(.easeInOut(duration: 1.0)) {
                        animatedPosition = newPosition
                    }
                } else if !isInitialized {
                    // First initialization - this shouldn't happen due to onAppear
                    animatedPosition = newPosition
                    isInitialized = true
                }
                // If isNewlyAppeared is true, ignore position changes until entry animation completes
            }
            .onChange(of: targetDistancePosition) { _, newPosition in
                if isInitialized && !isNewlyAppeared {
                    // Normal distance position update for existing aircraft
                    withAnimation(.easeInOut(duration: 1.0)) {
                        animatedDistancePosition = newPosition
                    }
                } else if !isInitialized {
                    animatedDistancePosition = newPosition
                }
                // If isNewlyAppeared is true, ignore distance position changes until entry animation completes
            }
            .onChange(of: flight.id) { _, _ in
                // New aircraft detected - reset for entry animation
                isNewlyAppeared = true
                let offscreenAircraftPosition = calculateOffscreenStartPosition(
                    bearing: compassAwareBearing, 
                    targetPosition: targetAircraftPosition
                )
                let offscreenDistancePosition = calculateOffscreenStartPosition(
                    bearing: compassAwareBearing, 
                    targetPosition: targetDistancePosition
                )
                animatedPosition = offscreenAircraftPosition
                animatedDistancePosition = offscreenDistancePosition
                
                // Animate to final position
                entryOpacity = 0.0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 1.5)) {
                        animatedPosition = targetAircraftPosition
                        animatedDistancePosition = targetDistancePosition
                        entryOpacity = 1.0
                        isNewlyAppeared = false
                    }
                }
            }
        }
    }
    
    private func calculateAircraftPosition(bearing: Double) -> CGPoint {
        // Add buffer between screen edges and icons
        let iconRadius: CGFloat = 12 // Half the icon size
        let edgeBuffer: CGFloat = 5 // Additional buffer from screen edge
        let bottomExtraBuffer: CGFloat = 0 // Extra buffer for bottom to prevent cutoff
        
        #if os(tvOS)
        // For tvOS, ignore safe areas and position icons right at screen edges
        let topMargin: CGFloat = iconRadius
        let bottomMargin: CGFloat = iconRadius
        let leftMargin: CGFloat = iconRadius
        let rightMargin: CGFloat = iconRadius
        #else
        let topMargin: CGFloat = safeAreaInsets.top + 0 + edgeBuffer // Reduce top padding
        let bottomMargin: CGFloat = safeAreaInsets.bottom + 0 + edgeBuffer + bottomExtraBuffer // Reduce bottom padding
        let leftMargin: CGFloat = safeAreaInsets.leading + iconRadius + edgeBuffer
        let rightMargin: CGFloat = safeAreaInsets.trailing + iconRadius + edgeBuffer
        #endif
        
        // Calculate center based on available space (excluding safe areas)
        let availableWidth = screenSize.width - leftMargin - rightMargin
        let availableHeight = screenSize.height - topMargin - bottomMargin
        let centerX = leftMargin + (availableWidth / 2)
        let centerY = topMargin + (availableHeight / 2)
        
        // Convert bearing to radians (0° = North, 90° = East)
        let radians = (bearing - 90) * .pi / 180
        
        // Calculate direction vector
        let dx = cos(radians)
        let dy = sin(radians)
        
        // Calculate distance to each edge from the adjusted center
        let distanceToLeftEdge = dx < 0 ? abs((availableWidth / 2) / dx) : CGFloat.greatestFiniteMagnitude
        let distanceToRightEdge = dx > 0 ? abs((availableWidth / 2) / dx) : CGFloat.greatestFiniteMagnitude
        let distanceToTopEdge = dy < 0 ? abs((availableHeight / 2) / dy) : CGFloat.greatestFiniteMagnitude
        let distanceToBottomEdge = dy > 0 ? abs((availableHeight / 2) / dy) : CGFloat.greatestFiniteMagnitude
        
        // Find the minimum distance (closest edge)
        let minDistance = min(min(distanceToLeftEdge, distanceToRightEdge), min(distanceToTopEdge, distanceToBottomEdge))
        
        // Calculate position at the edge
        let x = centerX + dx * minDistance
        let y = centerY + dy * minDistance
        
        // Ensure we stay within bounds
        let clampedX = max(leftMargin, min(screenSize.width - rightMargin, x))
        let clampedY = max(topMargin, min(screenSize.height - bottomMargin, y))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    private func calculateDistancePosition(bearing: Double, aircraftPosition: CGPoint) -> CGPoint {
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        
        // Calculate vector from center to aircraft
        let deltaX = aircraftPosition.x - centerX
        let deltaY = aircraftPosition.y - centerY
        let distanceToAircraft = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        // Platform-specific distance from aircraft icon perimeter toward center
        #if os(tvOS)
        let labelDistanceFromIcon: CGFloat = 40.0 // tvOS: More distance for better TV viewing
        #else
        let labelDistanceFromIcon: CGFloat = 25.0 // iOS/macOS: Standard distance
        #endif
        let aircraftIconRadius: CGFloat = 12.0 // Approximate radius of aircraft icon (24x24 frame / 2)
        
        // Calculate normalized direction vector (from center towards aircraft)
        let normalizedX = deltaX / distanceToAircraft
        let normalizedY = deltaY / distanceToAircraft
        
        // Position label at fixed distance INWARD from aircraft icon perimeter (toward center)
        let offsetFromCenter = distanceToAircraft - aircraftIconRadius - labelDistanceFromIcon
        let x = centerX + normalizedX * max(0, offsetFromCenter)
        let y = centerY + normalizedY * max(0, offsetFromCenter)
        
        return CGPoint(x: x, y: y)
    }
    
    /// Calculate compass-aware bearing that adjusts for device rotation
    private func calculateCompassAwareBearing(bearing: Double) -> Double {
        // Adjust bearing by device heading to maintain fixed direction relative to real world
        let adjustedBearing = bearing - motionManager.currentHeading
        
        // Normalize to 0-360 range
        let normalized = adjustedBearing.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Calculate icon rotation based on aircraft heading from API, with fallback to movement direction
    private func calculateIconRotation(flight: FlightData, compassAwareBearing: Double, isMovingTowards: Bool) -> Double {
        // Determine rotation correction based on aircraft type
        // Airplane icons need 270° correction, helicopter SVG needs 360° (270° + 90°)
        let rotationCorrection: Double = flight.isHelicopter ? 360 : 270
        
        // Priority 1: Use aircraft heading from API if available
        if let apiHeading = flight.position?.heading {
            // Adjust API heading for device orientation (compass-aware)
            let adjustedHeading = Double(apiHeading) - motionManager.currentHeading
            
            // Normalize to 0-360 range
            let normalized = adjustedHeading.truncatingRemainder(dividingBy: 360)
            let compassAwareHeading = normalized < 0 ? normalized + 360 : normalized
            
            // Apply rotation correction (270° for airplane, 360° for helicopter)
            let correctedHeading = (compassAwareHeading + rotationCorrection).truncatingRemainder(dividingBy: 360)
            return correctedHeading
        }
        
        // Priority 2: Fallback to current method based on movement direction
        // Icon should face away from center if moving away, towards center if approaching
        let fallbackHeading = isMovingTowards ? compassAwareBearing + 180 : compassAwareBearing
        let correctedFallback = (fallbackHeading + rotationCorrection).truncatingRemainder(dividingBy: 360)
        return correctedFallback
    }
    
    /// Calculate offscreen starting position for smooth entry animation
    private func calculateOffscreenStartPosition(bearing: Double, targetPosition: CGPoint) -> CGPoint {
        let centerX = screenSize.width / 2
        let centerY = screenSize.height / 2
        
        // Calculate vector from center to target position
        let deltaX = targetPosition.x - centerX
        let deltaY = targetPosition.y - centerY
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        // Normalize the direction vector
        let normalizedX = deltaX / distance
        let normalizedY = deltaY / distance
        
        // Extend beyond the target position by 100 pixels for offscreen start
        let offscreenDistance: CGFloat = 100
        let offscreenX = targetPosition.x + normalizedX * offscreenDistance
        let offscreenY = targetPosition.y + normalizedY * offscreenDistance
        
        return CGPoint(x: offscreenX, y: offscreenY)
    }
    
}

extension FlightDisplayView {
    #if os(macOS)
    private var macOSContextMenuItems: [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        
        if !viewModel.flights.isEmpty,
           let nearestFlight = viewModel.currentFlight {
            items.append(ContextMenuItem(
                title: "Copy Flight Number",
                keyboardShortcut: KeyboardShortcut("c", modifiers: .command)
            ) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(nearestFlight.displayIdentifier, forType: .string)
            })
            
            items.append(ContextMenuItem(
                title: "Copy Flight Details",
                keyboardShortcut: KeyboardShortcut("c", modifiers: [.command, .shift])
            ) {
                let pasteboard = NSPasteboard.general
                pasteboard.setFlightData(nearestFlight)
            })
        }
        
        items.append(ContextMenuItem(
            title: viewModel.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
            keyboardShortcut: KeyboardShortcut(.space, modifiers: .command)
        ) {
            viewModel.toggleMonitoring()
        })
        
        items.append(ContextMenuItem(
            title: "Refresh",
            keyboardShortcut: KeyboardShortcut("r", modifiers: .command)
        ) {
            viewModel.refreshFlightData()
        })
        
        return items
    }
    #endif
    
}

/// View for displaying connection status with color coding
struct ConnectionStatusView: View {
    let status: ConnectionStatus
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .scaleEffect(status.isConnecting ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), 
                          value: status.isConnecting)
            
            Text(status.description)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColorPrimary)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        )
    }
    
    private var statusColor: Color {
        switch status {
        case .disconnected:
            return .gray
        case .connecting:
            return .yellow
        case .connected:
            return .green
        case .error, .rateLimited:
            return .red
        }
    }
}

/// View for displaying when no flights are detected
struct NoFlightsView: View {
    let isMonitoring: Bool
    let statusMessage: String
    let onSettingsRequest: () -> Void
    
    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                    // Airplane icon with animation
                    Image(systemName: "airplane")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(isMonitoring ? 360 : 0))
                        .animation(.linear(duration: 2).repeatForever(autoreverses: false), 
                                  value: isMonitoring)
                    
                    VStack(spacing: 12) {
                        Text("No Flights Detected")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text(statusMessage)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                    }
                    
                    if !isMonitoring {
                        Text("Start monitoring to detect flights in your area")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if !os(tvOS)
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let threshold: CGFloat = 50
                        if value.translation.height < -threshold {
                            // Swipe up - show settings menu
                            #if os(iOS)
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                            #endif
                            onSettingsRequest()
                        }
                    }
            )
            #endif
            
            // Settings gear icon in bottom right corner
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onSettingsRequest) {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding()
                            .background(
                                Circle()
                                    .fill(.regularMaterial)
                                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                            )
                    }
                    #if os(iOS)
                    .buttonStyle(TouchOptimizedButtonStyle())
                    #elseif os(macOS)
                    .buttonStyle(DesktopOptimizedButtonStyle())
                    #endif
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
}



// MARK: - Preview Support

#if DEBUG
#Preview("With Flights") {
    FlightDisplayView(viewModel: MainViewModel.preview(withFlights: true))
}

#Preview("No Flights") {
    FlightDisplayView(viewModel: MainViewModel.preview(withFlights: false))
}

#Preview("Multiple Flights") {
    FlightDisplayView(viewModel: MainViewModel.preview(withMultipleFlights: true))
}
#endif

// MARK: - iOS-Specific Components



// MARK: - Platform-specific Colors

private var backgroundColorPrimary: Color {
    #if os(macOS)
    return Color(NSColor.controlBackgroundColor)
    #elseif os(tvOS)
    return Color.black
    #else
    return Color(.systemBackground)
    #endif
}

private var backgroundColorSecondary: Color {
    #if os(macOS)
    return Color(NSColor.controlColor)
    #elseif os(tvOS)
    return Color.gray.opacity(0.2)
    #else
    return Color(.systemGray6)
    #endif
}

private var mainBackgroundColor: Color {
    #if os(iOS)
    return Color(.systemGray6)
    #elseif os(macOS)
    return Color.clear
    #elseif os(tvOS)
    return Color.clear
    #else
    return Color.clear
    #endif
}

private var tertiaryTextColor: Color {
    #if os(macOS)
    return Color(NSColor.tertiaryLabelColor)
    #else
    return Color(.tertiaryLabel)
    #endif
}

// MARK: - Flight Detail View

/// Flight detail view that matches the settings window presentation style
struct FlightDetailView: View {
    let flight: FlightData
    let settingsManager: any SettingsManagerProtocol
    let locationManager: (any LocationManagerProtocol)?
    let viewModel: MainViewModel?
    @Environment(\.dismiss) private var dismiss
    @State private var flightWithPhoto: FlightData
    @State private var showingSettings = false
    @State private var showingFlightRadar24 = false
    @State private var flightRadar24URL: URL?
    
    init(flight: FlightData, settingsManager: any SettingsManagerProtocol, locationManager: (any LocationManagerProtocol)? = nil, viewModel: MainViewModel? = nil) {
        self.flight = flight
        self.settingsManager = settingsManager
        self.locationManager = locationManager
        self.viewModel = viewModel
        self._flightWithPhoto = State(initialValue: flight)
    }
    
    var body: some View {
        NavigationView {
            Form {
                aircraftPhotoSection
                flightIdentificationSection
                routeInformationSection
                aircraftDetailsSection
                positionDataSection
                additionalInfoSection
            }
            .navigationTitle("Flight Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .task {
                // Load aircraft photo if photos are enabled and not already loaded
                print("🎬 [FlightDetailView] Detail view opened for flight: \(flight.displayIdentifier)")
                if settingsManager.showAircraftPhotos && flightWithPhoto.aircraft?.photoURL == nil {
                    print("🔄 [FlightDetailView] Starting photo fetch task...")
                    flightWithPhoto = await flight.withAircraftPhoto(settingsManager: settingsManager)
                    print("✅ [FlightDetailView] Photo fetch task completed")
                    
                    // Log photo section status
                    let aircraft = flightWithPhoto.aircraft
                    let photoURL = aircraft?.photoURL
                    if photoURL != nil {
                        print("🖼️ [FlightDetailView] Photo section should be visible with URL: \(photoURL!)")
                    } else {
                        print("❌ [FlightDetailView] No photo section - Aircraft: \(aircraft != nil), PhotoURL: nil")
                    }
                } else if !settingsManager.showAircraftPhotos {
                    print("ℹ️ [FlightDetailView] Aircraft photos disabled in settings, skipping fetch")
                } else {
                    print("ℹ️ [FlightDetailView] Photo already available, skipping fetch")
                }
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
                
                ToolbarItem(placement: .principal) {
                    if let viewModel = viewModel {
                        Button(action: {
                            viewModel.toggleAircraftLock()
                        }) {
                            Text(viewModel.isAircraftLocked ? "Locked" : "Unlocked")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(viewModel.isAircraftLocked ? Color.red : Color.gray)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                #else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    if let viewModel = viewModel {
                        Button(action: {
                            viewModel.toggleAircraftLock()
                        }) {
                            Text(viewModel.isAircraftLocked ? "Locked" : "Unlocked")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(viewModel.isAircraftLocked ? Color.red : Color.gray)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
                #endif
                #endif
            }
        }
        #if os(iOS)
        .navigationViewStyle(StackNavigationViewStyle())
        #endif
        .sheet(isPresented: $showingSettings) {
            if let locationManager = locationManager {
                SettingsView(
                    settingsManager: settingsManager,
                    locationManager: locationManager,
                    onSettingsChanged: {
                        // Settings changed - could trigger refresh if needed
                    }
                )
            } else {
                // Fallback if no location manager is provided
                Text("Settings")
                    .navigationTitle("Settings")
                    .toolbar {
                        #if os(iOS)
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                        #else
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                showingSettings = false
                            }
                        }
                        #endif
                    }
            }
        }
        .sheet(isPresented: $showingFlightRadar24) {
            if let url = flightRadar24URL {
                FlightRadar24WebView(url: url)
            }
        }
    }
}

// MARK: - Flight Detail Sections
private extension FlightDetailView {
    
    @ViewBuilder
    var aircraftPhotoSection: some View {
        if let aircraft = flightWithPhoto.aircraft,
           let photoURL = aircraft.photoURL,
           let url = URL(string: photoURL) {
            Section {
                VStack(spacing: 12) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 200)
                            .overlay {
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Loading aircraft photo...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                    }
                    
                    VStack(spacing: 4) {
                        Text(aircraft.model)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let registration = aircraft.registration {
                            Text(registration)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                        
                        if let airline = flightWithPhoto.airline {
                            Text(airline.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear {
                print("🖼️ [PhotoSection] Rendering photo section with URL: \(photoURL)")
            }
        }
    }
    
    @ViewBuilder
    var flightIdentificationSection: some View {
        Section {
            HStack {
                Text("Flight Number")
                    .font(.headline)
                Spacer()
                Text(flight.displayIdentifier)
                    .font(.body)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
            }
            
            if let callsign = flight.callsign, callsign != flight.flightNumber {
                HStack {
                    Text("Callsign")
                        .font(.headline)
                    Spacer()
                    Text(callsign)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            
            if let airline = flight.airline {
                HStack {
                    Text("Airline")
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(airline.name)
                            .font(.body)
                            .foregroundColor(.primary)
                        if let code = airline.code {
                            Text(code)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
        } header: {
            Text("Flight Information")
        }
    }
    
    @ViewBuilder
    var routeInformationSection: some View {
        if let route = flight.route {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Origin")
                            .font(.headline)
                        Text(route.origin.displayName)
                            .font(.body)
                            .foregroundColor(.primary)
                        Text(route.origin.iataCode)
                            .font(.caption)
                            .foregroundColor(.blue)
                        if let city = route.origin.city {
                            Text(city)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(.title3)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Destination")
                            .font(.headline)
                        Text(route.destination.displayName)
                            .font(.body)
                            .foregroundColor(.primary)
                        Text(route.destination.iataCode)
                            .font(.caption)
                            .foregroundColor(.blue)
                        if let city = route.destination.city {
                            Text(city)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                
            } header: {
                Text("Route")
            }
        }
    }
    
    @ViewBuilder
    var aircraftDetailsSection: some View {
        if let aircraft = flight.aircraft {
            Section {
                HStack {
                    Text("Aircraft Model")
                        .font(.headline)
                    Spacer()
                    Text(aircraft.model)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text("Aircraft Code")
                        .font(.headline)
                    Spacer()
                    Text(aircraft.code)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                
                if let registration = aircraft.registration {
                    HStack {
                        Text("Registration")
                            .font(.headline)
                        Spacer()
                        Text(registration)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Text("Aircraft Type")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 8) {
                        Group {
                            if flight.isHelicopter {
                                Image("helicopter-bottom-view")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "airplane")
                            }
                        }
                        .foregroundColor(.blue)
                        Text(flight.isHelicopter ? "Helicopter" : "Aircraft")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
            } header: {
                Text("Aircraft Details")
            }
        }
    }
    
    @ViewBuilder
    var positionDataSection: some View {
        if let position = flight.position {
            Section {
                if let altitude = position.altitude {
                    HStack {
                        Text("Altitude")
                            .font(.headline)
                        Spacer()
                        Text("\(altitude) ft")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
                if let speed = position.speed {
                    HStack {
                        Text("Speed")
                            .font(.headline)
                        Spacer()
                        Text("\(speed) kts")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
                if let heading = position.heading {
                    HStack {
                        Text("Heading")
                            .font(.headline)
                        Spacer()
                        Text("\(heading)°")
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
                HStack {
                    Text("Coordinates")
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.6f°", position.latitude))
                            .font(.body)
                            .foregroundColor(.primary)
                        Text(String(format: "%.6f°", position.longitude))
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }
                
            } header: {
                Text("Position & Flight Data")
            }
        }
    }
    
    @ViewBuilder
    var additionalInfoSection: some View {
        Section {
            HStack {
                Text("Last Updated")
                    .font(.headline)
                Spacer()
                Text(formatRelativeTime(flight.lastUpdated))
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Flight ID")
                    .font(.headline)
                Spacer()
                Text(flight.id)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            
        } header: {
            Text("Additional Information")
        }
        
        // FlightRadar24 Button Section
        Section {
            Button(action: {
                openFlightRadar24()
            }) {
                HStack {
                    Image(systemName: "globe")
                        .foregroundColor(.white)
                    Text("View on FlightRadar24")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.orange)
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        } header: {
            Text("External Links")
        }
    }
    
    private func openFlightRadar24() {
        // Construct FlightRadar24 URL based on available flight information
        var urlString = "https://www.flightradar24.com"
        
        // Try to use flight number first (most reliable)
        if let flightNumber = flight.flightNumber, !flightNumber.isEmpty {
            urlString += "/\(flightNumber)"
        }
        // Fallback to callsign if no flight number
        else if let callsign = flight.callsign, !callsign.isEmpty {
            urlString += "/\(callsign)"
        }
        // If we have aircraft registration, we can search by that
        else if let registration = flight.aircraft?.registration, !registration.isEmpty {
            urlString += "/data/aircraft/\(registration)"
        }
        // Last resort: search page with flight identifier
        else {
            urlString += "/data/flights/\(flight.displayIdentifier)"
        }
        
        // Show in-app web view
        if let url = URL(string: urlString) {
            flightRadar24URL = url
            showingFlightRadar24 = true
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - FlightRadar24 Web View
struct FlightRadar24WebView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            #if os(iOS)
            SafariWebView(url: url)
            #elseif os(macOS)
            MacWebView(url: url)
            #endif
        }
        .navigationTitle("FlightRadar24")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            #else
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
            #endif
        }
    }
}

#if os(iOS)
// MARK: - iOS Safari Web View
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        
        let safariVC = SFSafariViewController(url: url, configuration: config)
        safariVC.preferredBarTintColor = UIColor.systemBackground
        safariVC.preferredControlTintColor = UIColor.systemBlue
        
        return safariVC
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}
#endif

#if os(macOS)
// MARK: - macOS Web View
struct MacWebView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        nsView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            // Handle navigation start if needed
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Handle navigation completion if needed
        }
    }
}
#endif
// MARK: - Predictive Components

/// Real-time distance view using aircraft predictions
struct PredictiveCountdownDistanceView: View {
    let flight: FlightData
    let userLocation: CLLocation
    let viewModel: MainViewModel
    
    @State private var currentDistance: Double = 0
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Distance")
                .font(.title3)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(String(format: "%.1f", currentDistance))")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Text("mi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            startDistanceUpdates()
        }
        .onDisappear {
            stopDistanceUpdates()
        }
        .onChange(of: flight.lastUpdated) { _, _ in
            resetDistance()
        }
        .onChange(of: flight.id) { _, _ in
            resetDistance()
        }
    }
    
    private func startDistanceUpdates() {
        stopDistanceUpdates()
        
        // Set initial distance
        currentDistance = flight.distanceFromLocation(userLocation) ?? 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateDistance()
        }
    }
    
    private func stopDistanceUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetDistance() {
        stopDistanceUpdates()
        currentDistance = flight.distanceFromLocation(userLocation) ?? 0
        startDistanceUpdates()
    }
    
    private func updateDistance() {
        // Use predicted distance if available, otherwise calculate manually
        if let predictedDistance = viewModel.getPredictedDistance(for: flight) {
            currentDistance = predictedDistance
        } else {
            // Fallback to manual calculation
            guard let position = flight.position,
                  let speed = position.speed,
                  let heading = position.heading,
                  speed > 0 else { return }
            
            let timeElapsed = Date().timeIntervalSince(flight.lastUpdated)
            let speedMilesPerSecond = Double(speed) * 0.000277778
            let distanceTraveled = speedMilesPerSecond * timeElapsed
            
            let headingRadians = Double(heading) * .pi / 180
            let earthRadius = 3959.0
            
            let lat1 = position.latitude * .pi / 180
            let lon1 = position.longitude * .pi / 180
            
            let lat2 = asin(sin(lat1) * cos(distanceTraveled / earthRadius) +
                           cos(lat1) * sin(distanceTraveled / earthRadius) * cos(headingRadians))
            
            let lon2 = lon1 + atan2(sin(headingRadians) * sin(distanceTraveled / earthRadius) * cos(lat1),
                                   cos(distanceTraveled / earthRadius) - sin(lat1) * sin(lat2))
            
            let newAircraftLocation = CLLocation(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
            currentDistance = userLocation.distance(from: newAircraftLocation) * 0.000621371
        }
    }
}

/// Real-time distance text component for compact layouts using predictions
struct PredictiveCountdownDistanceText: View {
    let flight: FlightData
    let userLocation: CLLocation
    let viewModel: MainViewModel
    
    @State private var currentDistance: Double = 0
    @State private var timer: Timer?
    
    var body: some View {
        Text("\(String(format: "%.0f", currentDistance))")
            .font(.caption)
            .fontWeight(.medium)
            .onAppear {
                startDistanceUpdates()
            }
            .onDisappear {
                stopDistanceUpdates()
            }
            .onChange(of: flight.lastUpdated) { _, _ in
                resetDistance()
            }
            .onChange(of: flight.id) { _, _ in
                resetDistance()
            }
    }
    
    private func startDistanceUpdates() {
        stopDistanceUpdates()
        currentDistance = flight.distanceFromLocation(userLocation) ?? 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateDistance()
        }
    }
    
    private func stopDistanceUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetDistance() {
        stopDistanceUpdates()
        currentDistance = flight.distanceFromLocation(userLocation) ?? 0
        startDistanceUpdates()
    }
    
    private func updateDistance() {
        if let predictedDistance = viewModel.getPredictedDistance(for: flight) {
            currentDistance = predictedDistance
        }
    }
}

/// Real-time ETA view using aircraft predictions
struct PredictiveCountdownETAView: View {
    let flight: FlightData
    let userLocation: CLLocation
    let viewModel: MainViewModel
    
    @State private var currentETA: String = ""
    @State private var timer: Timer?
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // Parse and display minutes and seconds separately
                if let (minutes, seconds) = parseETA(currentETA) {
                    if minutes > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(minutes)")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            Text("m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(seconds)")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        Text("s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Fallback for unparseable ETA
                    Text(currentETA)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            }
        }
        .onAppear {
            startETAUpdates()
        }
        .onDisappear {
            stopETAUpdates()
        }
        .onChange(of: flight.lastUpdated) { _, _ in
            resetETA()
        }
        .onChange(of: flight.id) { _, _ in
            resetETA()
        }
    }
    
    private func startETAUpdates() {
        stopETAUpdates()
        currentETA = flight.etaToNearestPoint(from: userLocation) ?? "N/A"
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateETA()
        }
    }
    
    private func stopETAUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetETA() {
        stopETAUpdates()
        currentETA = flight.etaToNearestPoint(from: userLocation) ?? "N/A"
        startETAUpdates()
    }
    
    private func updateETA() {
        if let predictedETA = viewModel.getPredictedETA(for: flight) {
            currentETA = predictedETA
        } else {
            currentETA = "N/A"
        }
    }
    
    /// Parse ETA string like "5m 30s" into minutes and seconds
    private func parseETA(_ eta: String) -> (minutes: Int, seconds: Int)? {
        // Handle "N/A" or empty cases
        if eta == "N/A" || eta.isEmpty {
            return nil
        }
        
        // Parse using regex patterns
        let minutesPattern = /(\d+)m/
        let secondsPattern = /(\d+)s/
        
        let minutes = Int(eta.firstMatch(of: minutesPattern)?.1 ?? "0") ?? 0
        let seconds = Int(eta.firstMatch(of: secondsPattern)?.1 ?? "0") ?? 0
        
        return (minutes: minutes, seconds: seconds)
    }
}

/// Real-time nearest approach view using aircraft predictions
struct PredictiveNearestApproachView: View {
    let flight: FlightData
    let userLocation: CLLocation
    let viewModel: MainViewModel
    @ObservedObject var motionManager: MotionManager
    
    @State private var currentNearestApproach: Double = 0
    @State private var timer: Timer?
    @State private var continuousRotation: Double = 0
    @State private var isInitialized: Bool = false
    @State private var currentETA: String = ""
    @State private var etaTimer: Timer?
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Nearest Approach")
                .font(.title3)
                .foregroundColor(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(String(format: "%.1f", currentNearestApproach))")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                Text("mi")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                // Compass-aware arrow pointing towards nearest approach position
                if let _ = calculateNearestApproachBearing() {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .rotationEffect(.degrees(continuousRotation))
                        .animation(.easeInOut(duration: isInitialized ? 1.0 : 0.0), value: continuousRotation)
                }
                
                // ETA time display
                if let (minutes, seconds) = parseETA(currentETA) {
                    if minutes > 0 {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(minutes)")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                            Text("m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(seconds)")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                        Text("s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            startNearestApproachUpdates()
            initializeArrowRotation()
            startETAUpdates()
        }
        .onDisappear {
            stopNearestApproachUpdates()
            stopETAUpdates()
        }
        .onChange(of: flight.lastUpdated) { _, _ in
            resetNearestApproach()
            resetETA()
        }
        .onChange(of: flight.id) { _, _ in
            resetNearestApproach()
            resetETA()
        }
        .onChange(of: adjustedBearing) { _, newBearing in
            if isInitialized {
                updateContinuousRotation(to: newBearing)
            } else {
                continuousRotation = newBearing
                isInitialized = true
            }
        }
    }
    
    private func startNearestApproachUpdates() {
        stopNearestApproachUpdates()
        currentNearestApproach = flight.nearestApproachDistance(to: userLocation) ?? 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateNearestApproach()
        }
    }
    
    private func stopNearestApproachUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetNearestApproach() {
        stopNearestApproachUpdates()
        currentNearestApproach = flight.nearestApproachDistance(to: userLocation) ?? 0
        startNearestApproachUpdates()
    }
    
    private func updateNearestApproach() {
        if let predictedNearestApproach = viewModel.getPredictedNearestApproach(for: flight) {
            currentNearestApproach = predictedNearestApproach
        }
    }
    
    /// Calculate the bearing to the nearest approach point
    private func calculateNearestApproachBearing() -> Double? {
        guard let position = flight.position,
              let heading = position.heading else { return nil }
        
        // Aircraft current position
        let aircraftLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
        
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Calculate the vector from aircraft to user
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLon = userLocation.coordinate.longitude * .pi / 180
        let aircraftLat = aircraftLocation.coordinate.latitude * .pi / 180
        let aircraftLon = aircraftLocation.coordinate.longitude * .pi / 180
        
        // Great circle bearing from aircraft to user
        let deltaLon = userLon - aircraftLon
        let y = sin(deltaLon) * cos(userLat)
        let x = cos(aircraftLat) * sin(userLat) - sin(aircraftLat) * cos(userLat) * cos(deltaLon)
        let bearingToUser = atan2(y, x)
        
        // Calculate the angle between aircraft heading and bearing to user
        let angleDiff = headingRadians - bearingToUser
        
        // Calculate the component of the vector from aircraft to user that's perpendicular to the flight path
        // This gives us the direction to the nearest approach point
        let perpendicularBearing = bearingToUser + (angleDiff > 0 ? .pi / 2 : -.pi / 2)
        
        // Convert back to degrees and normalize
        let bearingDegrees = perpendicularBearing * 180 / .pi
        let normalized = bearingDegrees.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Calculate compass-aware bearing that adjusts for device rotation
    private var adjustedBearing: Double {
        guard let bearing = calculateNearestApproachBearing() else { return 0 }
        
        // Adjust bearing by device heading to maintain fixed direction relative to real world
        let adjustedBearing = bearing - motionManager.currentHeading
        
        // Normalize to 0-360 range
        let normalized = adjustedBearing.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Initialize arrow rotation on first appearance
    private func initializeArrowRotation() {
        let bearing = adjustedBearing
        continuousRotation = bearing
        isInitialized = true
    }
    
    /// Update rotation with smooth transition, allowing continuous rotation beyond 360°
    private func updateContinuousRotation(to newBearing: Double) {
        // Get the current rotation normalized to 0-360 range
        let currentNormalized = continuousRotation.truncatingRemainder(dividingBy: 360)
        let normalizedCurrent = currentNormalized < 0 ? currentNormalized + 360 : currentNormalized
        
        // Calculate the difference between new bearing and current normalized rotation
        let diff = newBearing - normalizedCurrent
        
        // Choose the shortest path
        if abs(diff) > 180 {
            // We're crossing the 0°/360° boundary, choose shorter path
            if diff > 0 {
                // Going from ~359° to ~0°, rotate backwards (shorter path)
                continuousRotation += diff - 360
            } else {
                // Going from ~0° to ~359°, rotate forwards (shorter path)
                continuousRotation += diff + 360
            }
        } else {
            // Normal transition, add the difference to maintain continuous rotation
            continuousRotation += diff
        }
    }
    
    // MARK: - ETA Methods
    
    private func startETAUpdates() {
        stopETAUpdates()
        currentETA = flight.etaToNearestPoint(from: userLocation) ?? "N/A"
        
        etaTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateETA()
        }
    }
    
    private func stopETAUpdates() {
        etaTimer?.invalidate()
        etaTimer = nil
    }
    
    private func resetETA() {
        stopETAUpdates()
        currentETA = flight.etaToNearestPoint(from: userLocation) ?? "N/A"
        startETAUpdates()
    }
    
    private func updateETA() {
        if let predictedETA = viewModel.getPredictedETA(for: flight) {
            currentETA = predictedETA
        } else {
            currentETA = "N/A"
        }
    }
    
    /// Parse ETA string like "5m 30s" into minutes and seconds
    private func parseETA(_ eta: String) -> (minutes: Int, seconds: Int)? {
        // Handle "N/A" or empty cases
        if eta == "N/A" || eta.isEmpty {
            return nil
        }
        
        // Parse using regex patterns
        let minutesPattern = /(\d+)m/
        let secondsPattern = /(\d+)s/
        
        let minutes = Int(eta.firstMatch(of: minutesPattern)?.1 ?? "0") ?? 0
        let seconds = Int(eta.firstMatch(of: secondsPattern)?.1 ?? "0") ?? 0
        
        return (minutes: minutes, seconds: seconds)
    }
}

/// Real-time nearest approach text component for compact layouts using predictions
struct PredictiveNearestApproachText: View {
    let flight: FlightData
    let userLocation: CLLocation
    let viewModel: MainViewModel
    @ObservedObject var motionManager: MotionManager
    
    @State private var currentNearestApproach: Double = 0
    @State private var timer: Timer?
    @State private var continuousRotation: Double = 0
    @State private var isInitialized: Bool = false
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(String(format: "%.0f", currentNearestApproach))")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.orange)
            
            // Compass-aware arrow pointing towards nearest approach position
            if let _ = calculateNearestApproachBearing() {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(continuousRotation))
                    .animation(.easeInOut(duration: isInitialized ? 1.0 : 0.0), value: continuousRotation)
            }
        }
        .onAppear {
            startNearestApproachUpdates()
            initializeArrowRotation()
        }
        .onDisappear {
            stopNearestApproachUpdates()
        }
        .onChange(of: flight.lastUpdated) { _, _ in
            resetNearestApproach()
        }
        .onChange(of: flight.id) { _, _ in
            resetNearestApproach()
        }
        .onChange(of: adjustedBearing) { _, newBearing in
            if isInitialized {
                updateContinuousRotation(to: newBearing)
            } else {
                continuousRotation = newBearing
                isInitialized = true
            }
        }
    }
    
    private func startNearestApproachUpdates() {
        stopNearestApproachUpdates()
        currentNearestApproach = flight.nearestApproachDistance(to: userLocation) ?? 0
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateNearestApproach()
        }
    }
    
    private func stopNearestApproachUpdates() {
        timer?.invalidate()
        timer = nil
    }
    
    private func resetNearestApproach() {
        stopNearestApproachUpdates()
        currentNearestApproach = flight.nearestApproachDistance(to: userLocation) ?? 0
        startNearestApproachUpdates()
    }
    
    private func updateNearestApproach() {
        if let predictedNearestApproach = viewModel.getPredictedNearestApproach(for: flight) {
            currentNearestApproach = predictedNearestApproach
        }
    }
    
    /// Calculate the bearing to the nearest approach point
    private func calculateNearestApproachBearing() -> Double? {
        guard let position = flight.position,
              let heading = position.heading else { return nil }
        
        // Aircraft current position
        let aircraftLocation = CLLocation(latitude: position.latitude, longitude: position.longitude)
        
        // Convert heading to radians
        let headingRadians = Double(heading) * .pi / 180
        
        // Calculate the vector from aircraft to user
        let userLat = userLocation.coordinate.latitude * .pi / 180
        let userLon = userLocation.coordinate.longitude * .pi / 180
        let aircraftLat = aircraftLocation.coordinate.latitude * .pi / 180
        let aircraftLon = aircraftLocation.coordinate.longitude * .pi / 180
        
        // Great circle bearing from aircraft to user
        let deltaLon = userLon - aircraftLon
        let y = sin(deltaLon) * cos(userLat)
        let x = cos(aircraftLat) * sin(userLat) - sin(aircraftLat) * cos(userLat) * cos(deltaLon)
        let bearingToUser = atan2(y, x)
        
        // Calculate the angle between aircraft heading and bearing to user
        let angleDiff = headingRadians - bearingToUser
        
        // Calculate the component of the vector from aircraft to user that's perpendicular to the flight path
        // This gives us the direction to the nearest approach point
        let perpendicularBearing = bearingToUser + (angleDiff > 0 ? .pi / 2 : -.pi / 2)
        
        // Convert back to degrees and normalize
        let bearingDegrees = perpendicularBearing * 180 / .pi
        let normalized = bearingDegrees.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Calculate compass-aware bearing that adjusts for device rotation
    private var adjustedBearing: Double {
        guard let bearing = calculateNearestApproachBearing() else { return 0 }
        
        // Adjust bearing by device heading to maintain fixed direction relative to real world
        let adjustedBearing = bearing - motionManager.currentHeading
        
        // Normalize to 0-360 range
        let normalized = adjustedBearing.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    /// Initialize arrow rotation on first appearance
    private func initializeArrowRotation() {
        let bearing = adjustedBearing
        continuousRotation = bearing
        isInitialized = true
    }
    
    /// Update rotation with smooth transition, allowing continuous rotation beyond 360°
    private func updateContinuousRotation(to newBearing: Double) {
        // Get the current rotation normalized to 0-360 range
        let currentNormalized = continuousRotation.truncatingRemainder(dividingBy: 360)
        let normalizedCurrent = currentNormalized < 0 ? currentNormalized + 360 : currentNormalized
        
        // Calculate the difference between new bearing and current normalized rotation
        let diff = newBearing - normalizedCurrent
        
        // Choose the shortest path
        if abs(diff) > 180 {
            // We're crossing the 0°/360° boundary, choose shorter path
            if diff > 0 {
                // Going from ~359° to ~0°, rotate backwards (shorter path)
                continuousRotation += diff - 360
            } else {
                // Going from ~0° to ~359°, rotate forwards (shorter path)
                continuousRotation += diff + 360
            }
        } else {
            // Normal transition, add the difference to maintain continuous rotation
            continuousRotation += diff
        }
    }
}

/// Search result row component
struct SearchResultRow: View {
    let flight: FlightData
    let userLocation: CLLocation?
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Flight identifier
                VStack(alignment: .leading, spacing: 2) {
                    Text(flight.displayIdentifier)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let airline = flight.airline {
                        Text(airline.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Route info
                if let route = flight.route {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(route.origin.iataCode)
                                .font(.caption)
                                .foregroundColor(.blue)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(route.destination.iataCode)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        
                        if let aircraft = flight.aircraft {
                            Text(aircraft.model)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Distance info
                if let userLocation = userLocation,
                   let distance = flight.distanceFromLocation(userLocation) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f mi", distance))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let position = flight.position,
                           let altitude = position.altitude {
                            Text("\(altitude) ft")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColorPrimary)
                    .shadow(radius: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Search view component displayed as a sheet
struct SearchView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isSearchFieldFocused: Bool
    
    private var userLocation: CLLocation? {
        guard let bounds = viewModel.settingsManager.geographicBounds else { return nil }
        let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
        let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
        return CLLocation(latitude: centerLat, longitude: centerLon)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 12) {
                    TextField("Search flights...", text: $viewModel.searchText)
                        #if os(tvOS)
                        .textFieldStyle(PlainTextFieldStyle())
                        #else
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        #endif
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            viewModel.performSearch()
                        }
                        .onChange(of: viewModel.searchText) { _, _ in
                            viewModel.performSearch()
                        }
                    
                    Button("Search") {
                        viewModel.performSearch()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider()
                
                // Search results
                if !viewModel.searchResults.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.searchResults) { flight in
                                SearchResultRow(
                                    flight: flight,
                                    userLocation: userLocation,
                                    onTap: {
                                        viewModel.selectFlightFromSearch(flight)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                } else if !viewModel.searchText.isEmpty {
                    // No results or searching message
                    VStack(spacing: 16) {
                        Spacer()
                        
                        if viewModel.isSearching {
                            ProgressView()
                                .scaleEffect(1.2)
                            
                            Text("Searching...")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        } else {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("No flights found locally")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Try searching by flight number, airline, aircraft, or airport. Flight may be outside your current monitoring area.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        
                        Spacer()
                    }
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "airplane")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("Search for flights")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Enter a flight number, airline, aircraft type, or airport code to search for flights.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Spacer()
                    }
                }
            }
            .navigationTitle("Search Flights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Auto-focus the search field when the view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
        .onDisappear {
            // Clear search when dismissing
            viewModel.searchText = ""
            viewModel.searchResults = []
        }
    }
}
#endif
