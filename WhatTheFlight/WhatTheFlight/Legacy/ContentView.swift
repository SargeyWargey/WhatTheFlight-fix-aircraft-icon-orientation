//
//  ContentView.swift
//  WhatTheFlight
//
//  Created by Joshua Sargent on 8/1/25.
//

import SwiftUI
import Combine
import CoreLocation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var mainViewModel: MainViewModel
    #if os(tvOS)
    @State private var showingSettings = false // Load main page on tvOS
    @State private var showingFlightDetails = false // Flight details modal
    #else
    @State private var showingSettings = false
    #endif
    
    // Store references to services for settings view
    private let settingsManager: any SettingsManagerProtocol
    private let locationManager: any LocationManagerProtocol
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        // Initialize with real services for production
        let networkManager = NetworkManager()
        let flightService = FlightService(networkManager: networkManager)
        
        // Initialize SettingsManager with CloudKit disabled for development
        // In production, you would set enableCloudKit to true
        let settingsManager = SettingsManager(enableCloudKit: false)
        let locationManager = LocationManager()
        
        self.settingsManager = settingsManager
        self.locationManager = locationManager
        
        self._mainViewModel = StateObject(wrappedValue: MainViewModel(
            flightService: flightService,
            settingsManager: settingsManager,
            locationManager: locationManager
        ))
    }
    
    var body: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact && verticalSizeClass == .regular {
            // iPhone portrait - use compact navigation
            iPhonePortraitLayout
        } else if horizontalSizeClass == .regular && verticalSizeClass == .compact {
            // iPhone landscape or iPad landscape - use split layout
            landscapeLayout
        } else {
            // iPad portrait or other configurations - use regular navigation
            regularLayout
        }
        #elseif os(tvOS)
        tvOSLayout
        #else
        regularLayout
        #endif
    }
    
    #if os(iOS)
    @ViewBuilder
    private var iPhonePortraitLayout: some View {
        NavigationView {
            FlightDisplayView(viewModel: mainViewModel)
                #if os(iOS)
                .navigationBarHidden(true)
                #endif
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settingsManager: settingsManager,
                locationManager: locationManager,
                onSettingsChanged: {
                    // Refresh flight data and restart monitoring with new settings
                    mainViewModel.refreshFlightDataWithSettings()
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsFromSwipe)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            mainViewModel.pauseMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            mainViewModel.resumeMonitoring()
        }
    }
    
    @ViewBuilder
    private var landscapeLayout: some View {
        NavigationView {
            FlightDisplayView(viewModel: mainViewModel)
                #if os(iOS)
                .navigationBarHidden(true)
                #endif
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settingsManager: settingsManager,
                locationManager: locationManager,
                onSettingsChanged: {
                    // Refresh flight data and restart monitoring with new settings
                    mainViewModel.refreshFlightDataWithSettings()
                }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsFromSwipe)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            mainViewModel.pauseMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            mainViewModel.resumeMonitoring()
        }
    }
    #endif
    
    @ViewBuilder
    private var regularLayout: some View {
        NavigationView {
            FlightDisplayView(viewModel: mainViewModel)
                #if os(iOS)
                .navigationBarHidden(true)
                #endif
            #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(mainViewModel.isMonitoring ? "Stop" : "Start") {
                        mainViewModel.toggleMonitoring()
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .accessibilityIdentifier("start_stop_button")
                    
                    Button("Settings") {
                        showingSettings = true
                    }
                    .buttonStyle(ToolbarButtonStyle())
                }
                
                ToolbarItem(placement: .status) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 8, height: 8)
                            .accessibilityIdentifier("connection_status")
                        
                        Text(mainViewModel.connectionStatus.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            #endif
        }
        #if os(iOS)
        .navigationViewStyle(StackNavigationViewStyle())
        #elseif os(macOS)
        .navigationSplitViewStyle(.balanced)
        #endif
        .sheet(isPresented: $showingSettings) {
            #if os(macOS)
            DesktopPreferencesView {
                SettingsView(
                    settingsManager: settingsManager,
                    locationManager: locationManager,
                    onSettingsChanged: {
                        // Refresh flight data when settings are updated
                        mainViewModel.refreshFlightData()
                    }
                )
            }
            #else
            SettingsView(
                settingsManager: settingsManager,
                locationManager: locationManager,
                onSettingsChanged: {
                    // Refresh flight data and restart monitoring with new settings
                    mainViewModel.refreshFlightDataWithSettings()
                }
            )
            #endif
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: .showSettingsFromSwipe)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            mainViewModel.pauseMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            mainViewModel.resumeMonitoring()
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .toggleMonitoring)) { _ in
            mainViewModel.toggleMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: .startMonitoring)) { _ in
            if !mainViewModel.isMonitoring {
                mainViewModel.toggleMonitoring()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshFlightData)) { _ in
            mainViewModel.refreshFlightData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .nextFlight)) { _ in
            mainViewModel.selectNextAircraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: .previousFlight)) { _ in
            mainViewModel.selectPreviousAircraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            mainViewModel.resumeMonitoring()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            mainViewModel.pauseMonitoring()
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            mainViewModel.selectPreviousAircraft()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            mainViewModel.selectNextAircraft()
            return .handled
        }
        .onKeyPress(.space) {
            mainViewModel.toggleMonitoring()
            return .handled
        }
        #endif
    }
    
    #if os(macOS)
    private var connectionStatusColor: Color {
        switch mainViewModel.connectionStatus {
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
    #endif
    
    #if os(tvOS)
    @ViewBuilder
    private var tvOSLayout: some View {
        if showingSettings {
            // Show settings view directly as the main view
            TVSettingsView(
                queryInterval: .constant(mainViewModel.queryInterval),
                powerSavingEnabled: .constant(mainViewModel.powerSavingEnabled),
                tvOrientation: tvOrientationBinding,
                tvOrientationDegrees: tvOrientationDegreesBinding,
                manualLocationLatitude: manualLocationLatitudeBinding,
                manualLocationLongitude: manualLocationLongitudeBinding,
                useManualLocation: useManualLocationBinding,
                safeAreaMultiplier: safeAreaMultiplierBinding
            ) {
                showingSettings = false
            }
            .preferredColorScheme(.dark)
        } else {
            // Main radar display view with Apple TV remote support
            TVNavigationContainer(title: "") {
                FlightDisplayView(viewModel: mainViewModel)
            }
            .overlay(
                // Full-screen aircraft overlay for tvOS to bypass container padding
                TVAircraftOverlay(viewModel: mainViewModel)
                    .allowsHitTesting(false) // Let touches pass through to underlying UI
            )
            .focusable()
            .onMoveCommand { direction in
                print("ContentView: Move command received: \(direction)")
                switch direction {
                case .left:
                    print("ContentView: Left press triggered - selecting previous aircraft")
                    mainViewModel.selectPreviousAircraft()
                case .right:
                    print("ContentView: Right press triggered - selecting next aircraft")
                    mainViewModel.selectNextAircraft()
                case .up:
                    print("ContentView: Up press triggered - showing flight details")
                    showFlightDetails()
                case .down:
                    print("ContentView: Down press triggered - showing settings")
                    showingSettings = true
                @unknown default:
                    break
                }
            }
            .onPlayPauseCommand {
                print("ContentView: Play/Pause pressed - showing flight details")
                showFlightDetails()
            }
            .onExitCommand {
                print("ContentView: Exit/Menu pressed - showing settings")
                showingSettings = true
            }
            .preferredColorScheme(.dark)
            .onAppear {
                // Always start monitoring on tvOS
                if !mainViewModel.isMonitoring {
                    mainViewModel.startMonitoring()
                }
            }
            .sheet(isPresented: $showingFlightDetails) {
                if let selectedFlight = mainViewModel.currentFlight {
                    TVFlightDetailModalView(
                        flight: selectedFlight,
                        onDismiss: { showingFlightDetails = false }
                    )
                }
            }
            .sheet(isPresented: $showingSettings) {
                TVSettingsView(
                    queryInterval: .constant(mainViewModel.queryInterval),
                    powerSavingEnabled: .constant(mainViewModel.powerSavingEnabled),
                    tvOrientation: tvOrientationBinding,
                    tvOrientationDegrees: tvOrientationDegreesBinding,
                    manualLocationLatitude: manualLocationLatitudeBinding,
                    manualLocationLongitude: manualLocationLongitudeBinding,
                    useManualLocation: useManualLocationBinding,
                    safeAreaMultiplier: safeAreaMultiplierBinding
                ) {
                    showingSettings = false
                }
            }
        }
    }
    
    private var tvOrientationBinding: Binding<TVOSOrientation> {
        Binding(
            get: { 
                if let settingsManager = settingsManager as? SettingsManager {
                    return settingsManager.displayPreferences.tvOSOrientation
                }
                return .north
            },
            set: { newValue in
                if let settingsManager = settingsManager as? SettingsManager {
                    var preferences = settingsManager.displayPreferences
                    preferences.tvOSOrientation = newValue
                    settingsManager.displayPreferences = preferences
                }
            }
        )
    }
    
    private var manualLocationLatitudeBinding: Binding<Double?> {
        Binding(
            get: { 
                if let settingsManager = settingsManager as? SettingsManager {
                    return settingsManager.manualLocationLatitude
                }
                return nil
            },
            set: { newValue in
                if let settingsManager = settingsManager as? SettingsManager {
                    settingsManager.manualLocationLatitude = newValue
                }
            }
        )
    }
    
    private var manualLocationLongitudeBinding: Binding<Double?> {
        Binding(
            get: { 
                if let settingsManager = settingsManager as? SettingsManager {
                    return settingsManager.manualLocationLongitude
                }
                return nil
            },
            set: { newValue in
                if let settingsManager = settingsManager as? SettingsManager {
                    settingsManager.manualLocationLongitude = newValue
                }
            }
        )
    }
    
    private var useManualLocationBinding: Binding<Bool> {
        Binding(
            get: { 
                if let settingsManager = settingsManager as? SettingsManager {
                    return settingsManager.useManualLocation
                }
                return false
            },
            set: { newValue in
                if let settingsManager = settingsManager as? SettingsManager {
                    settingsManager.useManualLocation = newValue
                }
            }
        )
    }
    
    private var safeAreaMultiplierBinding: Binding<Double> {
        Binding(
            get: { 
                if let settingsManager = settingsManager as? SettingsManager {
                    return settingsManager.displayPreferences.tvOSSafeAreaMultiplier
                }
                return 1.0
            },
            set: { newValue in
                if let settingsManager = settingsManager as? SettingsManager {
                    var preferences = settingsManager.displayPreferences
                    preferences.tvOSSafeAreaMultiplier = newValue
                    settingsManager.displayPreferences = preferences
                }
            }
        )
    }
    
    private var tvOrientationDegreesBinding: Binding<Double> {
        Binding(
            get: { 
                if let settingsManager = settingsManager as? SettingsManager {
                    return settingsManager.displayPreferences.tvOSOrientationDegrees
                }
                return 0.0
            },
            set: { newValue in
                if let settingsManager = settingsManager as? SettingsManager {
                    var preferences = settingsManager.displayPreferences
                    preferences.tvOSOrientationDegrees = newValue
                    settingsManager.displayPreferences = preferences
                }
            }
        )
    }
    
    // MARK: - tvOS Flight Details
    
    /// Show flight details for the currently selected aircraft
    private func showFlightDetails() {
        guard mainViewModel.currentFlight != nil else { return }
        showingFlightDetails = true
    }
    
    #endif
}

// MARK: - tvOS Aircraft Icons Helper View

#if os(tvOS)
struct TVAircraftIcons: View {
    let flights: [FlightData]
    let currentFlightId: String?
    let settingsManager: any SettingsManagerProtocol
    let currentHeading: Double
    
    private var userLocation: CLLocation? {
        // On tvOS, prioritize manual location if set
        #if os(tvOS)
        if settingsManager.useManualLocation,
           let lat = settingsManager.manualLocationLatitude,
           let lon = settingsManager.manualLocationLongitude {
            return CLLocation(latitude: lat, longitude: lon)
        }
        #endif
        
        guard let bounds = settingsManager.geographicBounds else { return nil }
        let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
        let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
        return CLLocation(latitude: centerLat, longitude: centerLon)
    }
    
    var body: some View {
        // Use true screen bounds for positioning aircraft
        let screenSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        
        // Calculate aircraft data with positions and distances for overlap detection
        let aircraftData = flights.compactMap { flight -> (flight: FlightData, position: CGPoint, distance: Double, color: Color, opacity: Double, zIndex: Double)? in
            guard let userLocation = userLocation,
                  let bearing = flight.bearingFromLocation(userLocation),
                  let distance = flight.distanceFromLocation(userLocation) else { return nil }
            
            let position = calculateScreenAircraftPosition(
                bearing: bearing - currentHeading,
                screenSize: screenSize
            )
            
            // Determine aircraft color based on proximity and movement
            let color = calculateAircraftColor(flight: flight, userLocation: userLocation)
            
            return (flight, position, distance, color, 1.0, distance)
        }
        
        // Process overlapping aircraft and adjust opacity
        let processedAircraftData = processOverlappingAircraft(aircraftData)
        
        ZStack {
            // Render aircraft sorted by z-index (distance) so closest are on top
            ForEach(processedAircraftData.sorted { $0.zIndex < $1.zIndex }, id: \.flight.id) { aircraftInfo in
                let labelPosition = calculateDistanceLabelPosition(
                    aircraftPosition: aircraftInfo.position,
                    screenSize: screenSize
                )
                
                // Aircraft icon
                Group {
                    if aircraftInfo.flight.isHelicopter {
                        Image("helicopter-bottom-view")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "airplane")
                            .font(.title2)
                    }
                }
                .foregroundColor(aircraftInfo.color)
                .opacity(aircraftInfo.opacity)
                .rotationEffect(.degrees(calculateIconRotation(flight: aircraftInfo.flight, bearing: aircraftInfo.flight.bearingFromLocation(userLocation!) ?? 0, userLocation: userLocation!)))
                .position(x: aircraftInfo.position.x, y: aircraftInfo.position.y)
                .zIndex(aircraftInfo.zIndex)
                
                // Distance label - matches aircraft icon color and opacity
                Text(formatDistanceNumber(aircraftInfo.distance))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(aircraftInfo.color)
                    .opacity(aircraftInfo.opacity)
                    .position(x: labelPosition.x, y: labelPosition.y)
                    .zIndex(aircraftInfo.zIndex)
            }
        }
    }
    
    /// Calculate aircraft position using true screen coordinates
    private func calculateScreenAircraftPosition(bearing: Double, screenSize: CGSize) -> CGPoint {
        let iconRadius: CGFloat = 12
        let aircraftSize: CGFloat = 24 // Size of aircraft icon
        let additionalSpacing: CGFloat = 12 // Additional space from screen edge
        
        // Position aircraft inward from screen edges by icon radius + aircraft size + additional spacing
        let edgeInset = iconRadius + aircraftSize + additionalSpacing
        let topMargin: CGFloat = edgeInset
        let bottomMargin: CGFloat = edgeInset
        let leftMargin: CGFloat = edgeInset
        let rightMargin: CGFloat = edgeInset
        
        let availableWidth = screenSize.width - leftMargin - rightMargin
        let availableHeight = screenSize.height - topMargin - bottomMargin
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
        
        return CGPoint(x: centerX + dx * minDistance, y: centerY + dy * minDistance)
    }
    
    /// Calculate position for distance label positioned 15% away from aircraft icon
    private func calculateDistanceLabelPosition(aircraftPosition: CGPoint, screenSize: CGSize) -> CGPoint {
        let screenCenterX = screenSize.width / 2
        let screenCenterY = screenSize.height / 2
        
        // Position label 15% of the way from aircraft toward center
        let vectorX = screenCenterX - aircraftPosition.x
        let vectorY = screenCenterY - aircraftPosition.y
        
        let labelX = aircraftPosition.x + vectorX * 0.15
        let labelY = aircraftPosition.y + vectorY * 0.15
        
        return CGPoint(x: labelX, y: labelY)
    }
    
    /// Format distance number for display (just the number)
    private func formatDistanceNumber(_ distanceInMiles: Double) -> String {
        if distanceInMiles < 1.0 {
            return String(format: "%.1f", distanceInMiles) // Show decimal for < 1 mile
        } else {
            return String(format: "%.0f", distanceInMiles) // Whole numbers for >= 1 mile
        }
    }
    
    /// Calculate aircraft color based on selection state and 3-mile proximity threshold
    private func calculateAircraftColor(flight: FlightData, userLocation: CLLocation) -> Color {
        // Selected aircraft is always green
        if flight.id == currentFlightId {
            return .green
        }
        
        // Check if aircraft is within 3-mile proximity threshold
        if flight.isNearProximityThreshold(to: userLocation, threshold: 3.0) {
            return .orange
        }
        
        // Default color for other aircraft
        return .blue
    }
    
    /// Process overlapping aircraft to adjust opacity and z-ordering
    private func processOverlappingAircraft(_ aircraftData: [(flight: FlightData, position: CGPoint, distance: Double, color: Color, opacity: Double, zIndex: Double)]) -> [(flight: FlightData, position: CGPoint, distance: Double, color: Color, opacity: Double, zIndex: Double)] {
        var processedData = aircraftData
        let overlapThreshold: CGFloat = 30.0 // Distance threshold for considering icons as overlapping
        
        // Check each aircraft against all others for overlaps
        for i in 0..<processedData.count {
            var hasOverlap = false
            let currentAircraft = processedData[i]
            
            for j in 0..<processedData.count {
                if i == j { continue }
                let otherAircraft = processedData[j]
                
                // Calculate distance between aircraft positions
                let dx = currentAircraft.position.x - otherAircraft.position.x
                let dy = currentAircraft.position.y - otherAircraft.position.y
                let distance = sqrt(dx * dx + dy * dy)
                
                // Check if aircraft overlap
                if distance < overlapThreshold {
                    hasOverlap = true
                    
                    // If current aircraft is farther away, reduce its opacity
                    if currentAircraft.distance > otherAircraft.distance {
                        processedData[i].opacity = 0.2
                        // Adjust z-index to put farther aircraft behind
                        processedData[i].zIndex = currentAircraft.distance + 1000
                    }
                }
            }
            
            // If no overlap, ensure full opacity and normal z-index
            if !hasOverlap {
                processedData[i].opacity = 1.0
                processedData[i].zIndex = currentAircraft.distance
            }
        }
        
        return processedData
    }
    
    /// Calculate icon rotation for tvOS aircraft based on heading and TV orientation
    private func calculateIconRotation(flight: FlightData, bearing: Double, userLocation: CLLocation) -> Double {
        // Determine rotation correction based on aircraft type
        // Airplane icons need 270° correction, helicopter SVG needs 360° (270° + 90°)
        let rotationCorrection: Double = flight.isHelicopter ? 360 : 270
        
        // Priority 1: Use aircraft heading from API if available
        if let apiHeading = flight.position?.heading {
            // Adjust API heading for TV orientation (similar to compass-aware on iOS)
            let adjustedHeading = Double(apiHeading) - currentHeading
            
            // Normalize to 0-360 range
            let normalized = adjustedHeading.truncatingRemainder(dividingBy: 360)
            let orientationAwareHeading = normalized < 0 ? normalized + 360 : normalized
            
            // Apply rotation correction (270° for airplane, 360° for helicopter)
            let correctedHeading = (orientationAwareHeading + rotationCorrection).truncatingRemainder(dividingBy: 360)
            return correctedHeading
        }
        
        // Priority 2: Fallback to movement direction
        let isMovingTowards = flight.isMovingTowardsLocation(userLocation) ?? false
        let fallbackHeading = isMovingTowards ? bearing + 180 : bearing
        let correctedFallback = (fallbackHeading + rotationCorrection).truncatingRemainder(dividingBy: 360)
        return correctedFallback
    }
}
#endif

// MARK: - tvOS Aircraft Overlay

/// Full-screen aircraft overlay for tvOS that bypasses container padding constraints
struct TVAircraftOverlay: View {
    @ObservedObject var viewModel: MainViewModel
    
    var body: some View {
#if os(tvOS)
        GeometryReader { geometry in
            TVAircraftIcons(
                flights: Array(viewModel.flights.prefix(20)),
                currentFlightId: viewModel.currentFlight?.id,
                settingsManager: viewModel.settingsManager,
                currentHeading: viewModel.settingsManager.displayPreferences.tvOSOrientationDegrees
            )
        }
        .ignoresSafeArea(.all) // Extend to true screen edges
        #else
        EmptyView()
        #endif
    }
    
    /// Calculate aircraft position using true screen coordinates
    private func calculateScreenAircraftPosition(bearing: Double, screenSize: CGSize) -> CGPoint {
        let iconRadius: CGFloat = 12
        
        // Position aircraft right at screen edges
        let topMargin: CGFloat = iconRadius
        let bottomMargin: CGFloat = iconRadius
        let leftMargin: CGFloat = iconRadius
        let rightMargin: CGFloat = iconRadius
        
        let availableWidth = screenSize.width - leftMargin - rightMargin
        let availableHeight = screenSize.height - topMargin - bottomMargin
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
        
        return CGPoint(x: centerX + dx * minDistance, y: centerY + dy * minDistance)
    }
}

#Preview {
    ContentView()
}
