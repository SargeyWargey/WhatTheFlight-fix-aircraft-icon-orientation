//
//  tvOSComponents.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import SwiftUI
import CoreLocation
import MapKit

#if os(tvOS)

// MARK: - tvOS-Specific Button Styles

/// Accessible button style for tvOS with proper contrast
struct TVAccessibleButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundColor(textColor)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
                    .stroke(borderColor, lineWidth: isFocused ? 4 : 2)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .shadow(color: shadowColor, radius: isFocused ? 12 : 6)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var textColor: Color {
        if isFocused {
            return .black
        } else {
            return .white
        }
    }
    
    private var backgroundColor: Color {
        if isFocused {
            return .white
        } else {
            return .clear
        }
    }
    
    private var borderColor: Color {
        if isFocused {
            return .white
        } else {
            return .white.opacity(0.6)
        }
    }
    
    private var shadowColor: Color {
        if isFocused {
            return .white.opacity(0.8)
        } else {
            return .black.opacity(0.3)
        }
    }
}

/// Primary accessible button style for tvOS with high contrast
struct TVPrimaryAccessibleButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title)
            .fontWeight(.bold)
            .foregroundColor(textColor)
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(backgroundColor)
                    .stroke(borderColor, lineWidth: isFocused ? 5 : 3)
            )
            .scaleEffect(isFocused ? 1.15 : 1.0)
            .shadow(color: shadowColor, radius: isFocused ? 16 : 8)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private var textColor: Color {
        if isFocused {
            return .black
        } else {
            return .white
        }
    }
    
    private var backgroundColor: Color {
        if isFocused {
            return .white
        } else {
            return .blue.opacity(0.3)
        }
    }
    
    private var borderColor: Color {
        if isFocused {
            return .white
        } else {
            return .blue.opacity(0.8)
        }
    }
    
    private var shadowColor: Color {
        if isFocused {
            return .white.opacity(0.9)
        } else {
            return .blue.opacity(0.4)
        }
    }
}

/// tvOS-optimized button style with focus effects
struct TVFocusButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .fontWeight(.medium)
            .foregroundColor(.primary)
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.accentColor : Color.secondary.opacity(0.3))
                    .shadow(color: isFocused ? .accentColor : .clear, radius: 8)
            )
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Primary action button for tvOS with prominent focus
struct TVPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 60)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFocused ? Color.accentColor : Color.accentColor.opacity(0.8))
                    .shadow(color: isFocused ? .accentColor.opacity(0.6) : .clear, radius: 12)
            )
            .scaleEffect(isFocused ? 1.15 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - tvOS-Specific Layout Components

/// Simplified navigation container for tvOS
struct TVNavigationContainer<Content: View>: View {
    let content: Content
    let title: String
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 40) {
            // Large title for TV viewing distance
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.top, 40)
            
            content
                .padding(.horizontal, 80)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}


/// Main tvOS radar-style display with centered aircraft and perimeter aircraft
struct TVRadarDisplayView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var currentOrientationDegrees: Double = 0.0
    @State private var safeAreaMultiplier: Double = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                
                // Center flight display
                centerFlightDisplay
                
                // Perimeter aircraft
                perimeterAircraftOverlay(geometry: geometry)
                
                // Orientation indicator in corner
                orientationIndicator
                    .position(x: geometry.size.width - 120, y: 80)
                
                #if os(tvOS)
                // Debug info for tvOS
                VStack(alignment: .leading, spacing: 4) {
                    Text("Debug Info")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.yellow)
                    Text("Flights: \(viewModel.flights.count)")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("Current: \(viewModel.currentFlight?.displayIdentifier ?? "None")")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("Show Icons: \(viewModel.settingsManager.showAircraftIcons ? "YES" : "NO")")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("Monitoring: \(viewModel.isMonitoring ? "YES" : "NO")")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("Status: \(viewModel.connectionStatus.description)")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("User Loc: \(userLocation != nil ? "YES" : "NO")")
                        .font(.caption)
                        .foregroundColor(.white)
                    Text("Bounds: \(viewModel.settingsManager.geographicBounds != nil ? "YES" : "NO")")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(8)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .position(x: 120, y: 130)
                #endif
            }
        }
        .onAppear {
            currentOrientationDegrees = viewModel.settingsManager.displayPreferences.tvOSOrientationDegrees
            safeAreaMultiplier = viewModel.settingsManager.displayPreferences.tvOSSafeAreaMultiplier
        }
        .onChange(of: viewModel.settingsManager.displayPreferences.tvOSSafeAreaMultiplier) { _, newValue in
            safeAreaMultiplier = newValue
        }
        .onChange(of: viewModel.settingsManager.displayPreferences.tvOSOrientationDegrees) { _, newValue in
            currentOrientationDegrees = newValue
        }
    }
    
    @ViewBuilder
    private var centerFlightDisplay: some View {
        VStack {
            Spacer()
            if userLocation == nil {
                TVLocationRequiredView()
            } else if viewModel.flights.isEmpty {
                TVNoFlightsView()
            } else if let nearestFlight = nearestAircraft {
                TVCenterFlightView(
                    flight: nearestFlight,
                    userLocation: userLocation
                )
            }
            Spacer()
        }
    }
    
    @ViewBuilder
    private func perimeterAircraftOverlay(geometry: GeometryProxy) -> some View {
        if viewModel.settingsManager.showAircraftIcons {
            // Show other aircraft (excluding center one) as perimeter aircraft
            let perimeterFlights = Array(otherAircraft.prefix(15)) // Limit for performance
            
            ForEach(perimeterFlights, id: \.id) { flight in
                TVPerimeterAircraftView(
                    flight: flight,
                    userLocation: userLocation,
                    screenSize: geometry.size,
                    safeAreaInsets: geometry.safeAreaInsets,
                    tvOrientationDegrees: currentOrientationDegrees,
                    isSelected: flight.id == nearestAircraft?.id,
                    safeAreaMultiplier: safeAreaMultiplier,
                    onAircraftSelected: { selectedFlight in
                        viewModel.selectAircraft(selectedFlight)
                    }
                )
            }
        }
    }
    
    @ViewBuilder
    private var orientationIndicator: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.north")
                .font(.title2)
                .foregroundColor(.white)
                .rotationEffect(.degrees(-currentOrientationDegrees))
                .shadow(color: .black, radius: 2)
            
            Text("\(Int(currentOrientationDegrees))°")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .shadow(color: .black, radius: 1)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.8))
                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                .shadow(color: .black, radius: 4)
        )
    }
    
    private var nearestAircraft: FlightData? {
        // Use MainViewModel's current flight for center display
        return viewModel.currentFlight
    }
    
    private var otherAircraft: [FlightData] {
        guard let nearest = nearestAircraft else { return viewModel.flights }
        return viewModel.flights.filter { $0.id != nearest.id }
    }
    
    private var userLocation: CLLocation? {
        // On tvOS, prioritize manual location if set
        #if os(tvOS)
        if viewModel.settingsManager.useManualLocation,
           let lat = viewModel.settingsManager.manualLocationLatitude,
           let lon = viewModel.settingsManager.manualLocationLongitude {
            return CLLocation(latitude: lat, longitude: lon)
        }
        #endif
        
        guard let bounds = viewModel.settingsManager.geographicBounds else { return nil }
        let centerLat = (bounds.northLatitude + bounds.southLatitude) / 2
        let centerLon = (bounds.eastLongitude + bounds.westLongitude) / 2
        return CLLocation(latitude: centerLat, longitude: centerLon)
    }
}

/// Center flight view for tvOS radar display
struct TVCenterFlightView: View {
    let flight: FlightData
    let userLocation: CLLocation?
    
    var body: some View {
        VStack(spacing: 30) {
            // Flight Number - Extra large, bold, white for contrast
            Text(flight.displayIdentifier)
                .font(.system(size: 64, weight: .bold))
                .foregroundColor(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .shadow(color: .black, radius: 4)
            
            // Route - Large format with arrow
            if let route = flight.route {
                HStack(spacing: 20) {
                    Text(route.origin.iataCode)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.yellow)
                        .shadow(color: .black, radius: 2)
                    
                    Text(route.destination.iataCode)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black, radius: 2)
                }
            }
            
            // Aircraft Type - White with shadow
            if let aircraft = flight.aircraft {
                Text(aircraft.code.isEmpty ? aircraft.model : aircraft.code)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .shadow(color: .black, radius: 2)
            }
            
            // Flight data in grid
            HStack(spacing: 80) {
                // Altitude
                if let position = flight.position, let altitude = position.altitude {
                    VStack(spacing: 12) {
                        Text("Altitude")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black, radius: 1)
                        Text("\(altitude)ft")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2)
                    }
                }
                
                // Speed
                if let position = flight.position, let speed = position.speed {
                    VStack(spacing: 12) {
                        Text("Speed")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black, radius: 1)
                        Text("\(speed)kts")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2)
                    }
                }
                
                // Distance
                if let userLocation = userLocation,
                   let distance = flight.distanceFromLocation(userLocation) {
                    VStack(spacing: 12) {
                        Text("Distance")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black, radius: 1)
                        Text("\(Int(distance.rounded()))")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black, radius: 2)
                    }
                }
            }
        }
        .padding(40)
    }
}

/// Perimeter aircraft view for tvOS radar display
struct TVPerimeterAircraftView: View {
    let flight: FlightData
    let userLocation: CLLocation?
    let screenSize: CGSize
    let safeAreaInsets: EdgeInsets
    let tvOrientationDegrees: Double
    let isSelected: Bool
    let safeAreaMultiplier: Double
    let onAircraftSelected: (FlightData) -> Void
    
    var body: some View {
        if let userLocation = userLocation,
           let bearing = flight.bearingFromLocation(userLocation),
           let distance = flight.distanceFromLocation(userLocation) {
            
            let adjustedBearing = calculateAdjustedBearing(bearing: bearing)
            let aircraftPosition = calculateAircraftPosition(bearing: adjustedBearing)
            let isHelicopter = flight.isHelicopter
            
            ZStack {
                // Aircraft icon
                Button(action: {
                    onAircraftSelected(flight)
                }) {
                    Group {
                        if isHelicopter {
                            // Use green helicopter for selected flight, blue for others
                            let helicopterImageName = isSelected ? "helicopterActive" : "helicopter"
                            if UIImage(named: helicopterImageName) != nil {
                                Image(helicopterImageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 21, height: 21) // 75% of 28 = 21
                            } else {
                                Image(systemName: "helicopter")
                                    .font(.title3) // Smaller than .title
                            }
                        } else {
                            Image(systemName: "airplane")
                                .font(.title3) // Smaller than .title
                        }
                    }
                        .foregroundColor(isSelected ? .green : .white)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.8))
                                .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                                .frame(width: 30, height: 30) // 75% of 40 = 30
                        )
                        .shadow(color: .black, radius: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .position(x: aircraftPosition.x, y: aircraftPosition.y)
                
                // Distance label positioned below the aircraft icon with controllable offset
                Text("\(Int(distance.rounded()))")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.black.opacity(0.8))
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                            .padding(.horizontal, -3)
                            .padding(.vertical, -1)
                    )
                    .shadow(color: .black, radius: 2)
                    .position(x: aircraftPosition.x, y: calculateDistanceLabelPosition(aircraftPosition: aircraftPosition))
            }
        }
    }
    
    private func calculateAdjustedBearing(bearing: Double) -> Double {
        // Adjust bearing based on TV orientation degrees (since no compass)
        // If TV faces West (270°), North aircraft should appear on right (90° on screen)
        // So we ADD the TV orientation to rotate the view correctly
        let adjustedBearing = bearing + tvOrientationDegrees
        
        // Normalize to 0-360 range
        let normalized = adjustedBearing.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
    
    private func calculateAircraftPosition(bearing: Double) -> CGPoint {
        print("tvOS TVRadarDisplayView: calculateAircraftPosition called - THIS VIEW IS BEING USED!")
        let iconRadius: CGFloat = 15 // Reduced from 20 for smaller icons (75% of original)
        let edgeBuffer: CGFloat = 0 // Reduced from 10 to move icons closer to edge
        
        // Apply safe area multiplier (0.0 = no safe area, 1.0 = full safe area)
        let adjustedSafeAreaTop = safeAreaInsets.top * safeAreaMultiplier
        let adjustedSafeAreaBottom = safeAreaInsets.bottom * safeAreaMultiplier
        let adjustedSafeAreaLeading = safeAreaInsets.leading * safeAreaMultiplier
        let adjustedSafeAreaTrailing = safeAreaInsets.trailing * safeAreaMultiplier
        
        let topMargin: CGFloat = adjustedSafeAreaTop + edgeBuffer
        let bottomMargin: CGFloat = adjustedSafeAreaBottom + edgeBuffer
        let leftMargin: CGFloat = adjustedSafeAreaLeading + iconRadius + edgeBuffer
        let rightMargin: CGFloat = adjustedSafeAreaTrailing + iconRadius + edgeBuffer
        
        let availableWidth = screenSize.width - leftMargin - rightMargin
        let availableHeight = screenSize.height - topMargin - bottomMargin
        let centerX = leftMargin + (availableWidth / 2)
        let centerY = topMargin + (availableHeight / 2)
        
        // Convert bearing to radians (0° = North, 90° = East)
        let radians = (bearing - 90) * .pi / 180
        
        let dx = cos(radians)
        let dy = sin(radians)
        
        // Calculate distance to each edge
        let distanceToLeftEdge = dx < 0 ? abs((availableWidth / 2) / dx) : CGFloat.greatestFiniteMagnitude
        let distanceToRightEdge = dx > 0 ? abs((availableWidth / 2) / dx) : CGFloat.greatestFiniteMagnitude
        let distanceToTopEdge = dy < 0 ? abs((availableHeight / 2) / dy) : CGFloat.greatestFiniteMagnitude
        let distanceToBottomEdge = dy > 0 ? abs((availableHeight / 2) / dy) : CGFloat.greatestFiniteMagnitude
        
        let minDistance = min(min(distanceToLeftEdge, distanceToRightEdge), min(distanceToTopEdge, distanceToBottomEdge))
        
        let x = centerX + dx * minDistance
        let y = centerY + dy * minDistance
        
        let clampedX = max(leftMargin, min(screenSize.width - rightMargin, x))
        let clampedY = max(topMargin, min(screenSize.height - bottomMargin, y))
        
        return CGPoint(x: clampedX, y: clampedY)
    }
    
    private func calculateDistanceLabelPosition(aircraftPosition: CGPoint) -> CGFloat {
        let labelSpacing: CGFloat = 300 // CHANGE THIS VALUE to adjust spacing between aircraft icon and distance number
        return aircraftPosition.y + labelSpacing
    }
    
}

/// Large flight information card optimized for TV viewing
struct TVFlightCardView: View {
    let flight: FlightData
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        VStack(spacing: 40) {
            // Flight identifier with very large text
            Text(flight.displayIdentifier)
                .font(.system(size: 72, weight: .bold, design: .default))
                .foregroundColor(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            
            // Route information with large, clear layout
            if let route = flight.route {
                TVRouteView(route: route)
            }
            
            // Aircraft and airline with high contrast
            VStack(spacing: 20) {
                if let airline = flight.airline {
                    Text(airline.name)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                
                if let aircraft = flight.aircraft {
                    Text(aircraft.model)
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Flight details with large icons and text
            if let position = flight.position {
                TVFlightDetailsView(position: position)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.1))
                .shadow(color: isFocused ? .accentColor.opacity(0.3) : .black.opacity(0.1), 
                       radius: isFocused ? 16 : 8)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// Simplified route display for TV
struct TVRouteView: View {
    let route: RouteInfo
    
    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 60) {
                // Origin airport
                TVAirportView(airport: route.origin, isDestination: false)
                
                // Large arrow
                Image(systemName: "arrow.right")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.accentColor)
                
                // Destination airport
                TVAirportView(airport: route.destination, isDestination: true)
            }
            
            // Route description
            Text("\(route.origin.displayName) to \(route.destination.displayName)")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }
}

/// Large airport display for TV viewing
struct TVAirportView: View {
    let airport: AirportInfo
    let isDestination: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            Text(airport.iataCode)
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(isDestination ? .green : .blue)
            
            if let city = airport.city {
                Text(city)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(minWidth: 200)
    }
}

/// Flight details with large, accessible layout
struct TVFlightDetailsView: View {
    let position: FlightPosition
    
    var body: some View {
        HStack(spacing: 80) {
            if let altitude = position.altitude {
                TVDetailItem(
                    icon: "arrow.up",
                    label: "Altitude",
                    value: "\(altitude) ft"
                )
            }
            
            if let speed = position.speed {
                TVDetailItem(
                    icon: "speedometer",
                    label: "Speed",
                    value: "\(speed) kts"
                )
            }
            
            if let heading = position.heading {
                TVDetailItem(
                    icon: "location.north",
                    label: "Heading",
                    value: "\(heading)°"
                )
            }
        }
    }
}

/// Large detail item for TV display
struct TVDetailItem: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.accentColor)
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text(label)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 160)
    }
}

/// Location required view for tvOS
struct TVLocationRequiredView: View {
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        VStack(spacing: 40) {
            // Location icon
            Image(systemName: "location.slash")
                .font(.system(size: 120))
                .foregroundColor(.white.opacity(0.8))
                .shadow(color: .black, radius: 6)
            
            VStack(spacing: 20) {
                Text("Location Required")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 4)
                
                Text("Please set your location in Settings to see aircraft in your area")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .shadow(color: .black, radius: 2)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.1))
                .shadow(color: isFocused ? .accentColor.opacity(0.3) : .black.opacity(0.1), 
                       radius: isFocused ? 16 : 8)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

/// No flights view optimized for TV
struct TVNoFlightsView: View {
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        VStack(spacing: 40) {
            // Large airplane icon
            Image(systemName: "airplane")
                .font(.system(size: 120))
                .foregroundColor(.secondary)
            
            VStack(spacing: 20) {
                Text("No Flights Detected")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("Looking for aircraft in your area...")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.gray.opacity(0.1))
                .shadow(color: isFocused ? .accentColor.opacity(0.3) : .black.opacity(0.1), 
                       radius: isFocused ? 16 : 8)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - tvOS Settings Interface

/// Apple Settings app style interface for tvOS
struct TVSettingsView: View {
    @Binding var queryInterval: Double
    @Binding var powerSavingEnabled: Bool
    @Binding var tvOrientation: TVOSOrientation
    @Binding var tvOrientationDegrees: Double
    @Binding var manualLocationLatitude: Double?
    @Binding var manualLocationLongitude: Double?
    @Binding var useManualLocation: Bool
    @Binding var safeAreaMultiplier: Double
    let onDismiss: () -> Void
    
    // Additional settings that would normally come from SettingsManager
    @State private var monitoringRadius: Double = 31.0
    
    @State private var selectedCategory: SettingsCategory = .monitoring
    @FocusState private var sidebarFocused: Bool
    @FocusState private var detailFocused: Bool
    @Namespace private var settingsFocusScope
    
    enum SettingsCategory: CaseIterable, Identifiable {
        case monitoring
        case location
        case display
        case performance
        case about
        
        var id: Self { self }
        
        var title: String {
            switch self {
            case .monitoring:
                return "Monitoring"
            case .location:
                return "Location"
            case .display:
                return "Display"
            case .performance:
                return "Performance"
            case .about:
                return "About"
            }
        }
        
        var icon: String {
            switch self {
            case .monitoring:
                return "antenna.radiowaves.left.and.right"
            case .location:
                return "location"
            case .display:
                return "tv"
            case .performance:
                return "speedometer"
            case .about:
                return "info.circle"
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                HStack(spacing: 0) {
                    // Left sidebar - Settings categories
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Settings")
                                        .font(.largeTitle)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                    
                                    Text("What The Flight?")
                                        .font(.title3)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Navigation hint when sidebar is focused
                                if sidebarFocused {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("⟨ Exit")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("⟩ Enter")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.top, 40)
                        }
                        
                        // Categories list
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(SettingsCategory.allCases) { category in
                                    TVSettingsCategoryRow(
                                        category: category,
                                        isSelected: selectedCategory == category
                                    ) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedCategory = category
                                        }
                                        // Move focus to detail panel when category is selected
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            sidebarFocused = false
                                            detailFocused = true
                                        }
                                    }
                                }
                            }
                            .padding(.top, 20)
                        }
                        .focused($sidebarFocused)
                        
                        Spacer()
                        
                        // Done button
                        Button("Done") {
                            onDismiss()
                        }
                        .buttonStyle(TVSidebarButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                    .frame(width: geometry.size.width * 0.35)
                    .background(
                        Rectangle()
                            .fill(sidebarFocused ? Color.gray.opacity(0.2) : Color.gray.opacity(0.15))
                            .ignoresSafeArea()
                            .animation(.easeInOut(duration: 0.2), value: sidebarFocused)
                    )
                    
                    // Vertical divider
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                    
                    // Right detail panel
                    VStack(alignment: .leading, spacing: 0) {
                        // Detail header
                        HStack {
                            Image(systemName: selectedCategory.icon)
                                .font(.title2)
                                .foregroundColor(.white)
                            
                            Text(selectedCategory.title)
                                .font(.largeTitle)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Spacer()
                            
                            // Focus indicator
                            if detailFocused {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                    
                                    Text("Press ⟨ to return")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 40)
                        
                        // Detail content
                        ScrollView {
                            detailContent
                                .padding(.horizontal, 40)
                        }
                        .focused($detailFocused)
                        .onExitCommand {
                            // Back button in detail panel should return to sidebar
                            detailFocused = false
                            sidebarFocused = true
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .focusScope(settingsFocusScope)
        .onAppear {
            sidebarFocused = true
        }
        .onExitCommand {
            handleBackButton()
        }
    }
    
    private func handleBackButton() {
        if detailFocused {
            // If user is in detail panel, move focus back to sidebar
            withAnimation(.easeInOut(duration: 0.2)) {
                detailFocused = false
                sidebarFocused = true
            }
        } else {
            // If user is in sidebar, exit settings to main page
            onDismiss()
        }
    }
    
    @ViewBuilder
    private var detailContent: some View {
        switch selectedCategory {
        case .monitoring:
            monitoringSettings
        case .location:
            locationSettings
        case .display:
            displaySettings
        case .performance:
            performanceSettings
        case .about:
            aboutSettings
        }
    }
    
    @ViewBuilder
    private var monitoringSettings: some View {
        VStack(alignment: .leading, spacing: 30) {
            TVDetailSettingItem(
                title: "Update Frequency",
                subtitle: "How often to check for new flights"
            ) {
                TVSliderView(
                    value: $queryInterval,
                    range: 15...120,
                    step: 15,
                    unit: "seconds"
                )
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            TVDetailSettingItem(
                title: "Monitoring Radius",
                subtitle: "Distance from your location to monitor for aircraft"
            ) {
                TVSliderView(
                    value: $monitoringRadius,
                    range: 5...100,
                    step: 5,
                    unit: "miles"
                )
            }
        }
    }
    
    @ViewBuilder
    private var locationSettings: some View {
        VStack(alignment: .leading, spacing: 30) {
            TVLocationInput(
                latitude: $manualLocationLatitude,
                longitude: $manualLocationLongitude,
                useManualLocation: $useManualLocation
            )
        }
    }
    
    @ViewBuilder
    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 30) {
            TVDetailSettingItem(
                title: "TV Orientation",
                subtitle: "Set the degrees your TV is facing (0° = North, 90° = East, 180° = South, 270° = West)"
            ) {
                VStack(alignment: .leading, spacing: 20) {
                    // Current degrees display
                    HStack {
                        Image(systemName: "tv")
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        
                        Text("Currently facing: \(Int(tvOrientationDegrees))°")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.1))
                    )
                    
                    // Degrees input
                    TVDegreesInputView(
                        value: Binding(
                            get: { tvOrientationDegrees },
                            set: { newValue in
                                tvOrientationDegrees = newValue
                            }
                        )
                    )
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
            
            TVDetailSettingItem(
                title: "Safe Area Adjustment",
                subtitle: "Adjust how close aircraft icons appear to the screen edge"
            ) {
                TVSafeAreaSliderView(
                    value: Binding(
                        get: { safeAreaMultiplier },
                        set: { newValue in
                            safeAreaMultiplier = newValue
                        }
                    )
                )
            }
        }
    }
    
    @ViewBuilder
    private var performanceSettings: some View {
        VStack(alignment: .leading, spacing: 30) {
            TVDetailSettingItem(
                title: "Power Saving Mode",
                subtitle: "Reduce update frequency when inactive"
            ) {
                Button(powerSavingEnabled ? "Enabled" : "Disabled") {
                    powerSavingEnabled.toggle()
                }
                .buttonStyle(TVToggleButtonStyle(isOn: powerSavingEnabled))
            }
        }
    }
    
    @ViewBuilder
    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 30) {
            TVDetailSettingItem(
                title: "What The Flight? for Apple TV",
                subtitle: "Real-time flight tracking"
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Version 1.0")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    Text("Track aircraft overhead using FlightRadar24 data")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
}

// MARK: - Settings Components

/// Category row for settings sidebar
struct TVSettingsCategoryRow: View {
    let category: TVSettingsView.SettingsCategory
    let isSelected: Bool
    let onTap: () -> Void
    
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 24) {
                Image(systemName: category.icon)
                    .font(.body)
                    .foregroundColor(iconColor)
                    .frame(width: 18, height: 18)
                
                Text(category.title)
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(textColor)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .background(backgroundColor)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
    
    private var backgroundColor: Color {
        if isFocused {
            return .white.opacity(0.15)
        } else if isSelected {
            return .accentColor.opacity(0.2)
        } else {
            return .clear
        }
    }
    
    private var textColor: Color {
        if isSelected {
            return .white
        } else {
            return .primary
        }
    }
    
    private var iconColor: Color {
        if isSelected {
            return .accentColor
        } else {
            return .secondary
        }
    }
}

/// Detail setting item with title, subtitle and content
struct TVDetailSettingItem<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content
    
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            content
        }
        .padding(.vertical, 20)
    }
}

/// Sidebar button style
struct TVSidebarButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
                    .shadow(color: shadowColor, radius: isFocused ? 8 : 4)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    
    private var backgroundColor: Color {
        if isFocused {
            return .accentColor
        } else {
            return .white.opacity(0.1)
        }
    }
    
    private var shadowColor: Color {
        if isFocused {
            return .accentColor.opacity(0.4)
        } else {
            return .clear
        }
    }
}

/// Toggle button style for settings
struct TVToggleButtonStyle: ButtonStyle {
    let isOn: Bool
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3)
            .fontWeight(.medium)
            .foregroundColor(textColor)
            .padding(.horizontal, 30)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor)
                    .shadow(color: shadowColor, radius: isFocused ? 8 : 4)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    
    private var backgroundColor: Color {
        if isFocused {
            return isOn ? .green : .red.opacity(0.8)
        } else if isOn {
            return .green.opacity(0.3)
        } else {
            return .red.opacity(0.2)
        }
    }
    
    private var textColor: Color {
        if isFocused {
            return .white
        } else {
            return isOn ? .green : .red
        }
    }
    
    private var shadowColor: Color {
        if isFocused {
            return isOn ? .green.opacity(0.4) : .red.opacity(0.4)
        } else {
            return .clear
        }
    }
}

/// tvOS-optimized slider with focus support
struct TVSliderView: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    
    @Environment(\.isFocused) private var isFocused
    @State private var isEditing = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("\(Int(value)) \(unit)")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            HStack(spacing: 40) {
                Button("-") {
                    let newValue = max(range.lowerBound, value - step)
                    value = newValue
                }
                .buttonStyle(TVFocusButtonStyle())
                .disabled(value <= range.lowerBound)
                
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 400, height: 8)
                    .overlay(
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: progressWidth, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: value),
                        alignment: .leading
                    )
                    .cornerRadius(4)
                
                Button("+") {
                    let newValue = min(range.upperBound, value + step)
                    value = newValue
                }
                .buttonStyle(TVFocusButtonStyle())
                .disabled(value >= range.upperBound)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .shadow(color: isFocused ? .accentColor.opacity(0.3) : .clear, radius: 8)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    
    private var progressWidth: CGFloat {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return 400 * progress
    }
}

/// Safe Area adjustment slider for tvOS
struct TVSafeAreaSliderView: View {
    @Binding var value: Double
    
    @Environment(\.isFocused) private var isFocused
    
    private let range: ClosedRange<Double> = 0.0...1.0
    private let step: Double = 0.1
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("\(Int(value * 100))%")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(safeAreaDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack(spacing: 40) {
                Button("-") {
                    let newValue = max(range.lowerBound, value - step)
                    value = newValue
                }
                .buttonStyle(TVFocusButtonStyle())
                .disabled(value <= range.lowerBound)
                
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: 400, height: 8)
                    .overlay(
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: progressWidth, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: value),
                        alignment: .leading
                    )
                    .cornerRadius(4)
                
                Button("+") {
                    let newValue = min(range.upperBound, value + step)
                    value = newValue
                }
                .buttonStyle(TVFocusButtonStyle())
                .disabled(value >= range.upperBound)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .shadow(color: isFocused ? .accentColor.opacity(0.3) : .clear, radius: 8)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    
    private var progressWidth: CGFloat {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return 400 * progress
    }
    
    private var safeAreaDescription: String {
        switch value {
        case 0.0...0.2:
            return "Icons very close to edge\n(may be cut off)"
        case 0.2...0.5:
            return "Icons close to edge"
        case 0.5...0.8:
            return "Moderate safe area"
        default:
            return "Full safe area\n(maximum visibility)"
        }
    }
}

/// Degrees input for TV orientation (0-360 degrees)
struct TVDegreesInputView: View {
    @Binding var value: Double
    
    @Environment(\.isFocused) private var isFocused
    @State private var showingNumberPad = false
    
    private let step: Double = 15.0 // 15-degree increments
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("\(Int(value))°")
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(compassDirection)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            
            HStack(spacing: 40) {
                Button("-15°") {
                    let newValue = value - step
                    value = newValue < 0 ? newValue + 360 : newValue
                }
                .buttonStyle(TVFocusButtonStyle())
                
                Button("Enter Value") {
                    showingNumberPad = true
                }
                .buttonStyle(TVFocusButtonStyle())
                .sheet(isPresented: $showingNumberPad) {
                    TVNumberPadView(
                        value: $value,
                        title: "TV Orientation Degrees",
                        range: 0...360,
                        onDismiss: {
                            showingNumberPad = false
                        }
                    )
                }
                
                Button("+15°") {
                    let newValue = value + step
                    value = newValue >= 360 ? newValue - 360 : newValue
                }
                .buttonStyle(TVFocusButtonStyle())
            }
            
            // Compass visualization
            VStack(spacing: 16) {
                Text("Compass Preview")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                    
                    // Cardinal directions
                    ForEach([(0, "N"), (90, "E"), (180, "S"), (270, "W")], id: \.0) { degrees, label in
                        VStack {
                            Text(label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .offset(y: -60)
                        .rotationEffect(.degrees(Double(degrees)))
                    }
                    
                    // TV direction indicator
                    Image(systemName: "tv")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                        .rotationEffect(.degrees(value))
                        .animation(.easeInOut(duration: 0.3), value: value)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
                .shadow(color: isFocused ? .accentColor.opacity(0.3) : .clear, radius: 8)
        )
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
    
    private var compassDirection: String {
        switch value {
        case 0..<22.5, 337.5...360:
            return "North"
        case 22.5..<67.5:
            return "Northeast"
        case 67.5..<112.5:
            return "East"
        case 112.5..<157.5:
            return "Southeast"
        case 157.5..<202.5:
            return "South"
        case 202.5..<247.5:
            return "Southwest"
        case 247.5..<292.5:
            return "West"
        case 292.5..<337.5:
            return "Northwest"
        default:
            return "Unknown"
        }
    }
}

// MARK: - tvOS Location Input

/// Compass-style orientation picker for tvOS
struct TVCompassOrientationPicker: View {
    @Binding var selectedOrientation: TVOSOrientation
    @FocusState private var isFocused: Bool
    
    private let orientations = TVOSOrientation.allCases
    
    var body: some View {
        VStack(spacing: 16) {
            Text("TV Orientation")
                .font(.headline)
                .foregroundColor(.white)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(orientations, id: \.self) { orientation in
                    Button(action: {
                        selectedOrientation = orientation
                    }) {
                        VStack(spacing: 4) {
                            Text(orientation.displayName)
                                .font(.title3)
                                .fontWeight(.medium)
                                .foregroundColor(selectedOrientation == orientation ? .black : .white)
                            
                            Text("\(Int(orientation.degrees))°")
                                .font(.caption)
                                .foregroundColor(selectedOrientation == orientation ? .black : .secondary)
                        }
                        .frame(width: 60, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedOrientation == orientation ? Color.white : Color.white.opacity(0.1))
                        )
                    }
                    .buttonStyle(TVAccessibleButtonStyle())
                }
            }
            
            Text("Select the direction your TV is facing")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.3))
        )
    }
}

/// tvOS editable coordinate view with number pad input
struct TVEditableCoordinateView: View {
    @Binding var value: Double
    let label: String
    let range: ClosedRange<Double>
    let step: Double
    @FocusState var focused: TVLocationInput.LocationField?
    let fieldType: TVLocationInput.LocationField
    
    @State private var showingNumberPad = false
    
    var body: some View {
        Button(action: {
            showingNumberPad = true
        }) {
            VStack(spacing: 4) {
                Text(String(format: "%.6f°", value))
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("select to enter value")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(TVEditableCoordinateButtonStyle(isEditing: showingNumberPad))
        .focused($focused, equals: fieldType)
        .sheet(isPresented: $showingNumberPad) {
            TVNumberPadView(
                value: $value,
                title: label,
                range: range,
                onDismiss: {
                    showingNumberPad = false
                }
            )
        }
    }
}

enum CoordinateDirection {
    case increase, decrease
}

/// tvOS Number Pad View for coordinate input
struct TVNumberPadView: View {
    @Binding var value: Double
    let title: String
    let range: ClosedRange<Double>
    let onDismiss: () -> Void
    
    @State private var inputText: String = ""
    @State private var isNegative: Bool = false
    @State private var errorMessage: String?
    @FocusState private var focusedButton: NumberPadButton?
    
    enum NumberPadButton: CaseIterable, Hashable {
        case number1, number2, number3
        case number4, number5, number6
        case number7, number8, number9
        case decimal, number0, backspace
        case negative, clear, done
        
        var displayText: String {
            switch self {
            case .number0: return "0"
            case .number1: return "1"
            case .number2: return "2"
            case .number3: return "3"
            case .number4: return "4"
            case .number5: return "5"
            case .number6: return "6"
            case .number7: return "7"
            case .number8: return "8"
            case .number9: return "9"
            case .decimal: return "."
            case .backspace: return "⌫"
            case .negative: return "+/-"
            case .clear: return "Clear"
            case .done: return "Done"
            }
        }
        
        var systemImage: String? {
            switch self {
            case .backspace: return "delete.left"
            default: return nil
            }
        }
    }
    
    var body: some View {
        TVNavigationContainer(title: "Enter \(title)") {
            VStack(spacing: 40) {
                // Current value display
                VStack(spacing: 12) {
                    Text("Current Value")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("\(value, specifier: "%.6f")°")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.2))
                )
                
                // Input display
                VStack(spacing: 12) {
                    Text("New Value")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(displayText)
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundColor(isValidInput ? .white : .red)
                        .frame(minHeight: 40)
                    
                    Text("Range: \(range.lowerBound, specifier: "%.1f") to \(range.upperBound, specifier: "%.1f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                        .stroke(isValidInput ? Color.gray.opacity(0.3) : Color.red, lineWidth: 2)
                )
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                // Number pad
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(NumberPadButton.allCases, id: \.self) { button in
                        numberPadButton(for: button)
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            inputText = String(format: "%.6f", abs(value)).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if inputText.isEmpty || inputText == "." {
                inputText = "0"
            }
            isNegative = value < 0
            focusedButton = .number5 // Start focus in center
        }
    }
    
    @ViewBuilder
    private func numberPadButton(for button: NumberPadButton) -> some View {
        Button(action: {
            handleButtonPress(button)
        }) {
            Group {
                if let systemImage = button.systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(.white)
                } else {
                    Text(button.displayText)
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
            }
            .frame(width: 80, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(buttonBackgroundColor(for: button))
                    .shadow(color: .black, radius: 2)
            )
        }
        .buttonStyle(TVNumberPadButtonStyle())
        .focused($focusedButton, equals: button)
    }
    
    private func buttonBackgroundColor(for button: NumberPadButton) -> Color {
        switch button {
        case .done:
            return .green.opacity(0.8)
        case .clear, .backspace:
            return .red.opacity(0.8)
        case .negative:
            return .orange.opacity(0.8)
        default:
            return .gray.opacity(0.6)
        }
    }
    
    private func handleButtonPress(_ button: NumberPadButton) {
        errorMessage = nil
        
        switch button {
        case .number0, .number1, .number2, .number3, .number4,
             .number5, .number6, .number7, .number8, .number9:
            let digit = button.displayText
            if inputText == "0" {
                inputText = digit
            } else if inputText.count < 8 { // Limit input length
                inputText += digit
            }
            
        case .decimal:
            if !inputText.contains(".") && !inputText.isEmpty {
                inputText += "."
            }
            
        case .backspace:
            if !inputText.isEmpty {
                inputText.removeLast()
                if inputText.isEmpty {
                    inputText = "0"
                }
            }
            
        case .negative:
            isNegative.toggle()
            
        case .clear:
            inputText = "0"
            isNegative = false
            
        case .done:
            if isValidInput {
                saveValue()
            } else {
                errorMessage = "Please enter a valid number within the allowed range"
            }
        }
    }
    
    private var displayText: String {
        let sign = isNegative ? "-" : ""
        return "\(sign)\(inputText)"
    }
    
    private var isValidInput: Bool {
        guard let doubleValue = Double(displayText) else { return false }
        return range.contains(doubleValue)
    }
    
    private func saveValue() {
        guard let doubleValue = Double(displayText),
              range.contains(doubleValue) else {
            errorMessage = "Invalid value or out of range"
            return
        }
        
        value = doubleValue
        onDismiss()
    }
}

/// Button style for number pad buttons
struct TVNumberPadButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Custom button style for editable coordinates
struct TVEditableCoordinateButtonStyle: ButtonStyle {
    let isEditing: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isEditing 
                            ? Color.blue.opacity(0.2)
                            : (configuration.isPressed ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isEditing ? Color.blue : Color.clear,
                                lineWidth: isEditing ? 2 : 0
                            )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}


/// tvOS location input for manual coordinates
struct TVLocationInput: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @Binding var useManualLocation: Bool
    
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @FocusState private var focusedField: LocationField?
    
    enum LocationField {
        case latitudeEdit
        case longitudeEdit
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // Location display section
            if let lat = latitude, let lon = longitude {
                VStack(spacing: 12) {
                    Text("Current Location")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 20) {
                        VStack(spacing: 8) {
                            Text("Latitude")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TVEditableCoordinateView(
                                value: Binding(
                                    get: { lat },
                                    set: { newValue in
                                        latitude = newValue
                                        useManualLocation = true
                                    }
                                ),
                                label: "Latitude",
                                range: -90.0...90.0,
                                step: 0.001,
                                fieldType: .latitudeEdit
                            )
                        }
                        
                        VStack(spacing: 8) {
                            Text("Longitude")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TVEditableCoordinateView(
                                value: Binding(
                                    get: { lon },
                                    set: { newValue in
                                        longitude = newValue
                                        useManualLocation = true
                                    }
                                ),
                                label: "Longitude",
                                range: -180.0...180.0,
                                step: 0.001,
                                fieldType: .longitudeEdit
                            )
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
            } else {
                // No location set placeholder
                VStack(spacing: 16) {
                    Image(systemName: "location.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Location Set")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Use the buttons below to set your location manually or with the map")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.05)))
                )
            }
            
            
        }
        .onAppear {
            // Set initial focus to latitude field
            focusedField = .latitudeEdit
        }
        .onAppear {
            // Initialize text fields with current values
            if let lat = latitude {
                latitudeText = String(format: "%.6f", lat)
            }
            if let lon = longitude {
                longitudeText = String(format: "%.6f", lon)
            }
        }
    }
}

/// Coordinate entry modal for tvOS
struct TVCoordinateEntryView: View {
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @Binding var useManualLocation: Bool
    let onDismiss: () -> Void
    
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var errorMessage: String?
    @FocusState private var focusedField: CoordField?
    
    enum CoordField {
        case latitude
        case longitude
        case save
        case cancel
    }
    
    var body: some View {
        TVNavigationContainer(title: "Enter Coordinates") {
            VStack(spacing: 40) {
                // Instructions
                Text("Enter your latitude and longitude coordinates")
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Coordinate input fields
                VStack(spacing: 30) {
                    // Latitude input
                    VStack(spacing: 12) {
                        Text("Latitude (-90 to 90)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TVNumberInputField(
                            text: $latitudeText,
                            placeholder: "37.7749"
                        )
                        .focused($focusedField, equals: .latitude)
                    }
                    
                    // Longitude input
                    VStack(spacing: 12) {
                        Text("Longitude (-180 to 180)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        TVNumberInputField(
                            text: $longitudeText,
                            placeholder: "-122.4194"
                        )
                        .focused($focusedField, equals: .longitude)
                    }
                }
                
                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.headline)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                
                // Action buttons
                HStack(spacing: 60) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .buttonStyle(TVAccessibleButtonStyle())
                    .focused($focusedField, equals: .cancel)
                    
                    Button("Save") {
                        saveCoordinates()
                    }
                    .buttonStyle(TVPrimaryAccessibleButtonStyle())
                    .focused($focusedField, equals: .save)
                }
            }
        }
        .onAppear {
            // Initialize text fields with current values
            if let lat = latitude {
                latitudeText = String(format: "%.6f", lat)
            }
            if let lon = longitude {
                longitudeText = String(format: "%.6f", lon)
            }
            focusedField = .latitude
        }
    }
    
    private func saveCoordinates() {
        errorMessage = nil
        
        guard let lat = Double(latitudeText.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitudeText.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Please enter valid numbers"
            return
        }
        
        guard abs(lat) <= 90 else {
            errorMessage = "Latitude must be between -90 and 90"
            return
        }
        
        guard abs(lon) <= 180 else {
            errorMessage = "Longitude must be between -180 and 180"
            return
        }
        
        latitude = lat
        longitude = lon
        useManualLocation = true
        onDismiss()
    }
}

/// Number input field for tvOS
struct TVNumberInputField: View {
    @Binding var text: String
    let placeholder: String
    
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        Text(text.isEmpty ? placeholder : text)
            .font(.title2)
            .fontWeight(.medium)
            .foregroundColor(text.isEmpty ? .secondary : .primary)
            .frame(width: 300, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .shadow(color: isFocused ? .accentColor : .clear, radius: 6)
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
            .onLongPressGesture {
                // On tvOS, long press opens the system keyboard
                // This is a placeholder - actual text input would require
                // a custom text input implementation for tvOS
            }
    }
}

// MARK: - tvOS Remote Handler

/// Apple TV Remote handler for capturing remote input
struct AppleTVRemoteHandler: UIViewRepresentable {
    let onLeftPress: () -> Void
    let onRightPress: () -> Void
    let onUpPress: () -> Void
    let onDownPress: () -> Void
    let onSelectPress: () -> Void
    
    func makeUIView(context: Context) -> AppleTVRemoteView {
        let view = AppleTVRemoteView()
        view.onLeftPress = onLeftPress
        view.onRightPress = onRightPress
        view.onUpPress = onUpPress
        view.onDownPress = onDownPress
        view.onSelectPress = onSelectPress
        view.backgroundColor = UIColor.clear
        print("AppleTVRemoteHandler: Created remote handler view")
        return view
    }
    
    func updateUIView(_ uiView: AppleTVRemoteView, context: Context) {
        uiView.onLeftPress = onLeftPress
        uiView.onRightPress = onRightPress
        uiView.onUpPress = onUpPress
        uiView.onDownPress = onDownPress
        uiView.onSelectPress = onSelectPress
        
        // Ensure the view can receive focus
        DispatchQueue.main.async {
            if uiView.canBecomeFocused {
                uiView.setNeedsFocusUpdate()
                uiView.updateFocusIfNeeded()
                print("AppleTVRemoteHandler: Focus update requested")
            }
        }
    }
}

class AppleTVRemoteView: UIView {
    var onLeftPress: (() -> Void)?
    var onRightPress: (() -> Void)?
    var onUpPress: (() -> Void)?
    var onDownPress: (() -> Void)?
    var onSelectPress: (() -> Void)?
    
    override var canBecomeFocused: Bool { return true }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupForInput()
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        setupForInput()
    }
    
    private func setupForInput() {
        print("AppleTVRemoteView: Setting up for input")
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsFocusUpdate()
            self?.updateFocusIfNeeded()
        }
    }
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        
        for press in presses {
            switch press.type {
            case .leftArrow:
                print("AppleTVRemoteView: Left arrow pressed")
                onLeftPress?()
                handled = true
            case .rightArrow:
                print("AppleTVRemoteView: Right arrow pressed")
                onRightPress?()
                handled = true
            case .upArrow:
                print("AppleTVRemoteView: Up arrow pressed")
                onUpPress?()
                handled = true
            case .downArrow:
                print("AppleTVRemoteView: Down arrow pressed")
                onDownPress?()
                handled = true
            case .select:
                print("AppleTVRemoteView: Select pressed")
                onSelectPress?()
                handled = true
            default:
                // Also try handling via key codes as fallback
                if let key = press.key {
                    switch key.keyCode {
                    case .keyboardLeftArrow:
                        print("AppleTVRemoteView: Left arrow (keyboard) pressed")
                        onLeftPress?()
                        handled = true
                    case .keyboardRightArrow:
                        print("AppleTVRemoteView: Right arrow (keyboard) pressed")
                        onRightPress?()
                        handled = true
                    case .keyboardUpArrow:
                        print("AppleTVRemoteView: Up arrow (keyboard) pressed")
                        onUpPress?()
                        handled = true
                    case .keyboardDownArrow:
                        print("AppleTVRemoteView: Down arrow (keyboard) pressed")
                        onDownPress?()
                        handled = true
                    case .keyboardSpacebar, .keyboardReturnOrEnter:
                        print("AppleTVRemoteView: Select (keyboard) pressed")
                        onSelectPress?()
                        handled = true
                    default:
                        break
                    }
                }
            }
        }
        
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}

// MARK: - tvOS Flight Detail Modal

/// Flight detail modal view for tvOS
struct TVFlightDetailModalView: View {
    let flight: FlightData
    let onDismiss: () -> Void
    @Environment(\.isFocused) private var isFocused
    
    var body: some View {
        TVNavigationContainer(title: "Flight Details") {
            VStack(spacing: 40) {
                // Flight information
                TVFlightCardView(flight: flight)
                
                // Dismiss button
                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(TVPrimaryAccessibleButtonStyle())
            }
            .padding(40)
        }
        .onExitCommand {
            onDismiss()
        }
        .preferredColorScheme(.dark)
    }
}

#endif
