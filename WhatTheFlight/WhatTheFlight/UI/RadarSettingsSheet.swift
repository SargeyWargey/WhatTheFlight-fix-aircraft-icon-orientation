//
//  RadarSettingsSheet.swift
//  WhatTheFlight
//

#if os(iOS)
import SwiftUI
import MapKit

struct RadarSettingsSheet: View {
    @Bindable var settings: RadarSettings
    let location: RadarLocationService
    let model: RadarModel
    let logbook: Logbook
    let placeName: String
    let onTrack: (String) -> Void
    let showWelcome: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false
    private let skyWatch = SkyWatch.shared

    var body: some View {
        NavigationStack {
            Form {
                locationSection
                logbookSection
                alertsSection
                skyViewSection
                appleTVSection
                radarSection
                displaySection
                behaviourSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.mono(15, .semibold))
                }
            }
            .tint(Palette.ink)
            .fontDesign(.monospaced)
        }
    }

    // MARK: Sections

    private var locationSection: some View {
        Section {
            Picker("Watch from", selection: $settings.locationMode) {
                ForEach(RadarSettings.LocationMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if settings.locationMode == .device {
                LabeledContent("Status", value: deviceStatus)
                if location.isDenied {
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } else if !location.isAuthorized {
                    Button("Allow Location Access") { location.requestPermission() }
                }
            } else {
                NavigationLink {
                    LocationPickerView(settings: settings, location: location)
                } label: {
                    LabeledContent("Spot", value: customDescription)
                }
            }
        } header: {
            Text("Location")
        } footer: {
            Text("A custom spot lets you watch the sky over home, an airport fence, anywhere.")
        }
    }

    private var logbookSection: some View {
        Section {
            NavigationLink {
                LogbookView(logbook: logbook, onTrack: onTrack, isLive: { model.contact(id: $0) != nil })
            } label: {
                LabeledContent {
                    Text(RadarFormat.wholeNumber(logbook.sightings.count))
                } label: {
                    Label("Logbook", systemImage: "book.closed.fill")
                }
            }
            Toggle("Keep a logbook", isOn: $settings.keepLogbook)
        } header: {
            Text("Logbook")
        } footer: {
            Text("Every aircraft that comes inside your radius, with stats and badges. Stored only on this iPhone.")
        }
    }

    private var alertsSection: some View {
        Section {
            Toggle("Overhead alerts", isOn: $settings.overheadAlerts)
            if settings.overheadAlerts {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Overhead means within", value: "\(settings.overheadAlertMiles.formatted(.number.precision(.fractionLength(0...1)))) mi")
                    Slider(value: $settings.overheadAlertMiles, in: RadarSettings.overheadAlertRange, step: 0.5)
                        .accessibilityLabel("Overhead distance in miles")
                }
            }
            Toggle("Notable aircraft", isOn: $settings.notableAlerts)
            Button {
                Task {
                    if skyWatch.isActive {
                        await skyWatch.stop()
                    } else {
                        await skyWatch.start(placeName: placeName, radiusMiles: settings.radiusMiles, contacts: model.contacts)
                    }
                }
            } label: {
                Label(skyWatch.isActive ? "Stop Sky Watch" : "Start Sky Watch",
                      systemImage: skyWatch.isActive ? "stop.circle.fill" : "dot.radiowaves.left.and.right")
            }
            if let ends = skyWatch.endsAt {
                LabeledContent("Watching until", value: ends.formatted(date: .omitted, time: .shortened))
            }
            if let problem = skyWatch.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
        } header: {
            Text("Alerts")
        } footer: {
            Text("Overhead alerts fire when an aircraft is about to pass within that distance; notable ones cover emergencies, military, air ambulances and rare types. Sky Watch keeps watching from your Lock Screen and Dynamic Island for two hours and sends alerts as notifications. It uses location in the background, so expect some battery use.")
        }
    }

    private var skyViewSection: some View {
        Section {
            Toggle("Lift to open Sky View", isOn: $settings.raiseToSkyView)
        } header: {
            Text("Sky View")
        } footer: {
            Text("Raise your iPhone toward the sky and every aircraft is labelled through the camera; lower it or tap ✕ to return to the radar. With this off, open Sky View from Find in the Sky on any flight's details.")
        }
    }

    private var appleTVSection: some View {
        Section {
            NavigationLink {
                TVLinkSetupView(settings: settings, location: location)
            } label: {
                Label("Aim at Your Apple TV", systemImage: "appletv")
            }
        } header: {
            Text("Apple TV")
        } footer: {
            Text("Open WhatTheFlight on your Apple TV, then point your iPhone at the TV. It sends your location and the direction the screen faces, so every plane on the TV is where it really is.")
        }
    }

    private var radarSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Radius", value: "\(Int(settings.radiusMiles)) mi")
                Slider(value: $settings.radiusMiles, in: RadarSettings.radiusRange, step: 1)
                    .accessibilityLabel("Radius in miles")
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Refresh every", value: "\(Int(settings.refreshSeconds)) s")
                Slider(value: $settings.refreshSeconds, in: RadarSettings.refreshRange, step: 5)
                    .accessibilityLabel("Refresh interval in seconds")
            }
            Toggle("Show helicopters", isOn: $settings.showHelicopters)
        } header: {
            Text("Radar")
        } footer: {
            Text("Positions are smoothed between refreshes, so a longer interval still moves fluidly and is kinder to your battery.")
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(RadarSettings.Appearance.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Topographic background", isOn: $settings.showTopography)
            Toggle("Compass bezel", isOn: $settings.showCompassBezel)
            Toggle("Radar sweep", isOn: $settings.radarSweep)
            Toggle("Aircraft photos", isOn: $settings.showPhotos)
        }
    }

    private var behaviourSection: some View {
        Section {
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
            Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
            Toggle("Demo traffic", isOn: $settings.demoTraffic)
            Button("Show gesture guide") {
                dismiss()
                showWelcome()
            }
        } header: {
            Text("Behaviour")
        } footer: {
            Text("Demo traffic replaces live data with simulated aircraft around you — handy indoors or for showing the app off.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Flight data", value: "Flightradar24")
            LabeledContent("Photos", value: "Planespotters.net")
            LabeledContent("Airports", value: "OurAirports")
            LabeledContent("Airlines", value: "OpenFlights (ODbL)")
            Button("Reset to Defaults", role: .destructive) { confirmReset = true }
                .confirmationDialog("Reset all settings?", isPresented: $confirmReset, titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { settings.resetToDefaults() }
                }
        } header: {
            Text("About")
        } footer: {
            Text("WhatTheFlight uses Flightradar24's public web feed, which is unofficial and may change without notice.")
        }
    }

    // MARK: Helpers

    private var deviceStatus: String {
        if location.isDenied { return "Access denied" }
        if !location.isAuthorized { return "Not allowed yet" }
        guard let coordinate = location.location?.coordinate else { return "Finding you…" }
        return coordinate.shortDescription
    }

    private var customDescription: String {
        settings.customCoordinate?.shortDescription ?? "Not set"
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

// MARK: - Location picker

struct LocationPickerView: View {
    let settings: RadarSettings
    let location: RadarLocationService

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if let center {
                    MapCircle(center: center, radius: settings.radiusMiles * 1609.344)
                        .foregroundStyle(Palette.ink.opacity(0.08))
                        .stroke(Palette.ink.opacity(0.5), lineWidth: 1.5)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapCompass() }
            .onMapCameraChange(frequency: .continuous) { context in
                center = context.region.center
            }

            // Crosshair
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Palette.signal)
                .allowsHitTesting(false)

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    Text(center?.shortDescription ?? "Move the map")
                        .font(.mono(13, .semibold))
                        .foregroundStyle(Palette.value)
                    Text("\(Int(settings.radiusMiles)) mi radius")
                        .font(.mono(11))
                        .foregroundStyle(Palette.caption)
                    HStack(spacing: 10) {
                        if let here = location.location?.coordinate {
                            Button {
                                withAnimation { camera = .region(region(around: here)) }
                            } label: {
                                Label("Me", systemImage: "location.fill").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(RadarButtonStyle(prominent: false))
                        }
                        Button {
                            if let center {
                                settings.customCoordinate = center
                                settings.locationMode = .custom
                            }
                            dismiss()
                        } label: {
                            Text("Watch This Spot").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RadarButtonStyle(prominent: true))
                        .disabled(center == nil)
                    }
                }
                .padding(16)
                .glassSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(16)
            }
        }
        .navigationTitle("Pick a Spot")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let start = settings.customCoordinate ?? location.location?.coordinate
            if let start { camera = .region(region(around: start)) }
        }
    }

    private func region(around coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        let meters = settings.radiusMiles * 1609.344 * 2.6
        return MKCoordinateRegion(center: coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
    }
}
#endif
