//
//  SettingsView.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/1/25.
//

import SwiftUI
import CoreLocation

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    let onSettingsChanged: (() -> Void)?
    
    @FocusState private var focusedField: LocationField?
    
    enum LocationField {
        case latitude
        case longitude
    }
    
    init(settingsManager: any SettingsManagerProtocol, locationManager: any LocationManagerProtocol, onSettingsChanged: (() -> Void)? = nil) {
        self._viewModel = StateObject(wrappedValue: SettingsViewModel(
            settingsManager: settingsManager,
            locationManager: locationManager
        ))
        self.onSettingsChanged = onSettingsChanged
    }
    
    var body: some View {
        NavigationView {
            Form {
                locationSection
                queryIntervalSection
                displayPreferencesSection
                notificationSection
                advancedSection
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(DesktopOptimizedButtonStyle())
                    .keyboardShortcut(.escape)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSettingsChanged?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .buttonStyle(DesktopOptimizedButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                }
                #else
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        #if os(iOS)
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        #endif
                        dismiss()
                    }
                    #if os(iOS)
                    .buttonStyle(TouchOptimizedButtonStyle())
                    #endif
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        #if os(iOS)
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        #endif
                        onSettingsChanged?()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    #if os(iOS)
                    .buttonStyle(TouchOptimizedButtonStyle())
                    #endif
                }
                #endif
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") {
                    viewModel.clearMessages()
                }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
            .overlay(alignment: .top) {
                if let successMessage = viewModel.successMessage {
                    SuccessMessageView(message: successMessage)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.3), value: viewModel.successMessage)
                }
            }
        }
        #if os(iOS)
        .navigationViewStyle(StackNavigationViewStyle())
        #endif
    }
}

// MARK: - Location Section
private extension SettingsView {
    
    @ViewBuilder
    var locationSection: some View {
        Section {
            locationStatusRow
            
            if viewModel.canUseLocationServices && !viewModel.isManualEntryMode {
                automaticLocationControls
            } else {
                manualLocationControls
            }
            
            locationModeToggle
            
            if let bounds = viewModel.geographicBounds {
                boundsDisplayRow(bounds)
            }
            
            radiusField
            
        } header: {
            Text("Geographic Area")
        } footer: {
            Text("Configure the area where you want to monitor flights. You can use your current location or enter coordinates manually.")
        }
    }
    
    @ViewBuilder
    var locationStatusRow: some View {
        HStack {
            Image(systemName: locationStatusIcon)
                .foregroundColor(locationStatusColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Location Status")
                    .font(.headline)
                Text(viewModel.locationStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if viewModel.locationPermissionStatus == .notDetermined {
                Button("Request") {
                    #if os(iOS)
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    #endif
                    viewModel.requestLocationPermission()
                }
                .buttonStyle(.bordered)
                #if os(iOS)
                .buttonStyle(TouchOptimizedButtonStyle())
                #endif
            }
        }
    }
    
    @ViewBuilder
    var automaticLocationControls: some View {
        Button(action: {
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            #endif
            viewModel.useCurrentLocation()
        }) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.blue)
                Text("Use Current Location")
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .disabled(viewModel.isLoading)
        #if os(iOS)
        .buttonStyle(TouchOptimizedButtonStyle())
        #endif
    }
    
    @ViewBuilder
    var manualLocationControls: some View {
        VStack(spacing: 12) {
            #if os(macOS)
            DesktopTextField(
                title: "Latitude",
                text: $viewModel.manualLatitude,
                placeholder: "e.g., 37.7749"
            ) {
                viewModel.setManualCoordinates()
            }
            
            DesktopTextField(
                title: "Longitude",
                text: $viewModel.manualLongitude,
                placeholder: "e.g., -122.4194"
            ) {
                viewModel.setManualCoordinates()
            }
            
            #else
            CoordinateInputField(
                title: "Latitude",
                value: $viewModel.manualLatitude,
                placeholder: "e.g., 37.7749",
                range: -90...90
            )
            .focused($focusedField, equals: .latitude)
            
            CoordinateInputField(
                title: "Longitude", 
                value: $viewModel.manualLongitude,
                placeholder: "e.g., -122.4194",
                range: -180...180
            )
            .focused($focusedField, equals: .longitude)
            
            #endif
            
            if let validationMessage = viewModel.manualCoordinatesValidationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            Button("Set Manual Coordinates") {
                #if os(iOS)
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                #endif
                viewModel.setManualCoordinates()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.areManualCoordinatesValid || viewModel.isLoading)
            #if os(iOS)
            .buttonStyle(TouchOptimizedButtonStyle())
            #elseif os(macOS)
            .buttonStyle(DesktopOptimizedButtonStyle())
            #endif
        }
    }
    
    @ViewBuilder
    var locationModeToggle: some View {
        Button(action: {
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            #endif
            viewModel.toggleLocationMode()
            
            #if os(tvOS)
            // Focus on latitude field when switching to manual mode
            if viewModel.isManualEntryMode {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    focusedField = .latitude
                }
            }
            #endif
        }) {
            HStack {
                Image(systemName: viewModel.isManualEntryMode ? "location" : "pencil")
                Text(viewModel.isManualEntryMode ? "Use Automatic Location" : "Enter Coordinates Manually")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .disabled(!viewModel.canUseLocationServices && !viewModel.isManualEntryMode)
        #if os(iOS)
        .buttonStyle(TouchOptimizedButtonStyle())
        #endif
    }
    
    func boundsDisplayRow(_ bounds: GeographicBounds) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Current Area")
                .font(.headline)
            Text(viewModel.boundsDescription)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    var radiusField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monitoring Radius")
                    .font(.headline)
                Spacer()
                Text("\(Int(viewModel.radiusInMiles)) miles")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            #if !os(tvOS)
            Slider(
                value: $viewModel.radiusInMiles,
                in: 5...50,
                step: 1
            ) {
                Text("Monitoring Radius")
            } minimumValueLabel: {
                Text("5")
                    .font(.caption)
            } maximumValueLabel: {
                Text("50")
                    .font(.caption)
            }
            .onChange(of: viewModel.radiusInMiles) { _, _ in
                viewModel.updateRadiusFromMiles()
            }
            #else
            HStack(spacing: 16) {
                Button("-") {
                    if viewModel.radiusInMiles > 5 {
                        viewModel.radiusInMiles = max(5, viewModel.radiusInMiles - 1)
                        viewModel.updateRadiusFromMiles()
                    }
                }
                .disabled(viewModel.radiusInMiles <= 5)
                
                Text("\(Int(viewModel.radiusInMiles)) miles")
                    .frame(minWidth: 80)
                    .font(.body)
                
                Button("+") {
                    if viewModel.radiusInMiles < 50 {
                        viewModel.radiusInMiles = min(50, viewModel.radiusInMiles + 1)
                        viewModel.updateRadiusFromMiles()
                    }
                }
                .disabled(viewModel.radiusInMiles >= 50)
            }
            .buttonStyle(.plain)
            #endif
            
            Text("Range: 5 to 50 miles")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        
        if let radiusMessage = viewModel.radiusValidationMessage {
            Text(radiusMessage)
                .font(.caption)
                .foregroundColor(.red)
        }
    }
    
    var locationStatusIcon: String {
        switch viewModel.locationPermissionStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return "location.fill"
        case .denied, .restricted:
            return "location.slash"
        case .notDetermined:
            return "location"
        @unknown default:
            return "location"
        }
    }
    
    var locationStatusColor: Color {
        switch viewModel.locationPermissionStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }
}

// MARK: - Query Interval Section
private extension SettingsView {
    
    @ViewBuilder
    var queryIntervalSection: some View {
        Section {
            #if os(macOS)
            PrecisionSlider(
                title: "Query Interval",
                value: $viewModel.queryInterval,
                in: 15...120,
                step: 5,
                unit: "s"
            ) { newValue in
                viewModel.saveQueryInterval()
            }
            #else
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Query Interval")
                        .font(.headline)
                    Spacer()
                    Text("\(Int(viewModel.queryInterval))s")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                #if !os(tvOS)
                Slider(
                    value: $viewModel.queryInterval,
                    in: 15...120,
                    step: 5
                ) {
                    Text("Query Interval")
                } minimumValueLabel: {
                    Text("15s")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("120s")
                        .font(.caption)
                }
                .onChange(of: viewModel.queryInterval) { _, _ in
                    viewModel.saveQueryInterval()
                }
                #else
                VStack(alignment: .leading, spacing: 8) {
                    Text("Query Interval: \(Int(viewModel.queryInterval)) seconds")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        Button("-") {
                            if viewModel.queryInterval > 15 {
                                viewModel.queryInterval = max(15, viewModel.queryInterval - 5)
                                viewModel.saveQueryInterval()
                            }
                        }
                        .disabled(viewModel.queryInterval <= 15)
                        
                        Text("\(Int(viewModel.queryInterval))s")
                            .frame(minWidth: 40)
                            .font(.body)
                        
                        Button("+") {
                            if viewModel.queryInterval < 120 {
                                viewModel.queryInterval = min(120, viewModel.queryInterval + 5)
                                viewModel.saveQueryInterval()
                            }
                        }
                        .disabled(viewModel.queryInterval >= 120)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
            #endif
            
            if let validationMessage = viewModel.queryIntervalValidationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            powerSavingToggle
            
        } header: {
            Text("Data Refresh")
        } footer: {
            Text("How often to check for new flights. Lower values provide more real-time data but use more battery and data.")
        }
    }
    
    @ViewBuilder
    var powerSavingToggle: some View {
        Toggle("Power Saving Mode", isOn: $viewModel.powerSavingEnabled)
            .onChange(of: viewModel.powerSavingEnabled) { _, _ in
                viewModel.savePowerSavingEnabled()
            }
    }
}

// MARK: - Display Preferences Section
private extension SettingsView {
    
    @ViewBuilder
    var displayPreferencesSection: some View {
        Section {
            textSizePicker
            colorThemePicker
            informationDensityPicker
            displayOptionsToggles
            
        } header: {
            Text("Display Preferences")
        } footer: {
            Text("Customize how flight information is displayed in the app.")
        }
    }
    
    @ViewBuilder
    var textSizePicker: some View {
        Picker("Text Size", selection: $viewModel.displayPreferences.textSize) {
            ForEach(TextSize.allCases, id: \.self) { size in
                Text(size.displayName)
                    .tag(size)
            }
        }
        .onChange(of: viewModel.displayPreferences.textSize) { _, _ in
            viewModel.saveDisplayPreferences()
        }
    }
    
    @ViewBuilder
    var colorThemePicker: some View {
        Picker("Color Theme", selection: $viewModel.displayPreferences.colorTheme) {
            ForEach(ColorTheme.allCases, id: \.self) { theme in
                Text(theme.displayName)
                    .tag(theme)
            }
        }
        .onChange(of: viewModel.displayPreferences.colorTheme) { _, _ in
            viewModel.saveDisplayPreferences()
        }
    }
    
    @ViewBuilder
    var informationDensityPicker: some View {
        Picker("Information Density", selection: $viewModel.displayPreferences.informationDensity) {
            ForEach(InformationDensity.allCases, id: \.self) { density in
                Text(density.displayName)
                    .tag(density)
            }
        }
        .onChange(of: viewModel.displayPreferences.informationDensity) { _, _ in
            viewModel.saveDisplayPreferences()
        }
    }
    
    @ViewBuilder
    var displayOptionsToggles: some View {
        Group {
            Toggle("Enable Animations", isOn: $viewModel.displayPreferences.animationsEnabled)
            Toggle("Show Aircraft Icons", isOn: $viewModel.showAircraftIcons)
            Toggle("Show Aircraft Photos", isOn: $viewModel.showAircraftPhotos)
                .help("Fetch and display aircraft photos when available. May increase data usage.")
            Toggle("Auto-Focus Nearest Aircraft", isOn: $viewModel.autoFocusNearest)
                .help("Automatically focus on the nearest aircraft. When disabled, manually selected aircraft remain in focus until they leave the monitoring area.")
            Toggle("Show Altitude", isOn: $viewModel.displayPreferences.showAltitude)
            Toggle("Show Speed", isOn: $viewModel.displayPreferences.showSpeed)
            Toggle("Show Heading", isOn: $viewModel.displayPreferences.showHeading)
            
            proximityDistanceSlider
        }
        .onChange(of: viewModel.displayPreferences.animationsEnabled) { _, _ in
            viewModel.saveDisplayPreferences()
        }
        .onChange(of: viewModel.showAircraftIcons) { _, _ in
            viewModel.saveShowAircraftIcons()
        }
        .onChange(of: viewModel.showAircraftPhotos) { _, _ in
            viewModel.saveShowAircraftPhotos()
        }
        .onChange(of: viewModel.autoFocusNearest) { _, _ in
            viewModel.saveAutoFocusNearest()
        }
        .onChange(of: viewModel.displayPreferences.showAltitude) { _, _ in
            viewModel.saveDisplayPreferences()
        }
        .onChange(of: viewModel.displayPreferences.showSpeed) { _, _ in
            viewModel.saveDisplayPreferences()
        }
        .onChange(of: viewModel.displayPreferences.showHeading) { _, _ in
            viewModel.saveDisplayPreferences()
        }
        .onChange(of: viewModel.displayPreferences.proximityDistanceThreshold) { _, _ in
            viewModel.saveDisplayPreferences()
        }
    }
    
    @ViewBuilder
    var proximityDistanceSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Orange Icon Distance")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.displayPreferences.proximityDistanceThreshold, specifier: "%.1f") mi")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            #if !os(tvOS)
            Slider(
                value: $viewModel.displayPreferences.proximityDistanceThreshold,
                in: 0.5...10.0,
                step: 0.5
            ) {
                Text("Orange Icon Distance")
            } minimumValueLabel: {
                Text("0.5")
                    .font(.caption)
            } maximumValueLabel: {
                Text("10")
                    .font(.caption)
            }
            #else
            HStack(spacing: 16) {
                Button("-") {
                    if viewModel.displayPreferences.proximityDistanceThreshold > 0.5 {
                        viewModel.displayPreferences.proximityDistanceThreshold = max(0.5, viewModel.displayPreferences.proximityDistanceThreshold - 0.5)
                    }
                }
                .disabled(viewModel.displayPreferences.proximityDistanceThreshold <= 0.5)
                
                Text("\(viewModel.displayPreferences.proximityDistanceThreshold, specifier: "%.1f") mi")
                    .frame(minWidth: 80)
                    .font(.body)
                
                Button("+") {
                    if viewModel.displayPreferences.proximityDistanceThreshold < 10.0 {
                        viewModel.displayPreferences.proximityDistanceThreshold = min(10.0, viewModel.displayPreferences.proximityDistanceThreshold + 0.5)
                    }
                }
                .disabled(viewModel.displayPreferences.proximityDistanceThreshold >= 10.0)
            }
            .buttonStyle(.plain)
            #endif
            
            Text("Distance for orange aircraft icons (0.5 to 10 miles)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Notification Section
private extension SettingsView {
    
    @ViewBuilder
    var notificationSection: some View {
        Section {
            Group {
                Toggle("Flight Detection Alerts", isOn: $viewModel.notificationSettings.flightDetectionEnabled)
                Toggle("Connection Status Updates", isOn: $viewModel.notificationSettings.connectionStatusEnabled)
                Toggle("Error Alerts", isOn: $viewModel.notificationSettings.errorAlertsEnabled)
                Toggle("Sound Enabled", isOn: $viewModel.notificationSettings.soundEnabled)
                Toggle("Badge Enabled", isOn: $viewModel.notificationSettings.badgeEnabled)
            }
            .onChange(of: viewModel.notificationSettings.flightDetectionEnabled) { _, _ in
                viewModel.saveNotificationSettings()
            }
            .onChange(of: viewModel.notificationSettings.connectionStatusEnabled) { _, _ in
                viewModel.saveNotificationSettings()
            }
            .onChange(of: viewModel.notificationSettings.errorAlertsEnabled) { _, _ in
                viewModel.saveNotificationSettings()
            }
            .onChange(of: viewModel.notificationSettings.soundEnabled) { _, _ in
                viewModel.saveNotificationSettings()
            }
            .onChange(of: viewModel.notificationSettings.badgeEnabled) { _, _ in
                viewModel.saveNotificationSettings()
            }
            
        } header: {
            Text("Notifications")
        } footer: {
            Text("Configure when and how you receive notifications about flight activity and app status.")
        }
    }
}

// MARK: - Advanced Section
private extension SettingsView {
    
    @ViewBuilder
    var advancedSection: some View {
        Section {
            cloudKitSyncRow
            resetSettingsButton
            
        } header: {
            Text("Advanced")
        }
    }
    
    @ViewBuilder
    var cloudKitSyncRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("CloudKit Sync", isOn: $viewModel.cloudKitSyncEnabled)
                .onChange(of: viewModel.cloudKitSyncEnabled) { _, _ in
                    viewModel.saveCloudKitSyncEnabled()
                }
            
            if viewModel.cloudKitSyncEnabled {
                Button("Sync Now") {
                    viewModel.syncWithCloudKit()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSyncing)
                .overlay(alignment: .trailing) {
                    if viewModel.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var resetSettingsButton: some View {
        Button("Reset to Defaults") {
            viewModel.resetToDefaults()
        }
        .foregroundColor(.red)
        .disabled(viewModel.isLoading)
    }
}

// MARK: - Supporting Views

struct CoordinateInputField: View {
    let title: String
    @Binding var value: String
    let placeholder: String
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            
            TextField(placeholder, text: $value)
                #if !os(tvOS)
                .textFieldStyle(.roundedBorder)
                #else
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                #endif
                #if os(iOS)
                .keyboardType(.decimalPad)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            hideKeyboard()
                        }
                    }
                }
                #endif
            
            Text("Range: \(range.lowerBound, specifier: "%.0f") to \(range.upperBound, specifier: "%.0f")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct SuccessMessageView: View {
    let message: String
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
}



// MARK: - Preview

// MARK: - Helper Functions

#if os(iOS)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#else
extension View {
    func hideKeyboard() {
        // No-op for non-iOS platforms
    }
}
#endif

#Preview {
    SettingsView(
        settingsManager: SettingsManager(enableCloudKit: false),
        locationManager: LocationManager()
    )
}