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
    @State private var appIcon = AppIconChoice.current
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
            InfoHeader("Location", info: "A custom spot lets you watch the sky over home, an airport fence, anywhere. Aircraft seen at a custom spot aren't logged and don't count toward stats or badges: the logbook is what you saw yourself.")
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
            Toggle(isOn: $settings.keepLogbook) {
                InfoLabel("Keep a logbook", info: "Every aircraft that comes inside your radius, with where you were, stats and badges. Demo traffic and custom spots aren't logged, only what's around you.")
            }
            Toggle(isOn: $settings.syncLogbook) {
                InfoLabel("Sync with iCloud", info: "One logbook across your iPhone, iPad and Apple TV. Each sighting shows which device logged it, and a flight seen on two devices counts once.")
            }
            .disabled(!settings.keepLogbook)
        } header: {
            Text("Logbook")
        }
    }

    private var alertsSection: some View {
        Section {
            Toggle(isOn: $settings.overheadAlerts) {
                InfoLabel("Overhead alerts", info: "A heads-up when an aircraft is about to pass within the distance below.")
            }
            if settings.overheadAlerts {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Overhead means within", value: "\(settings.overheadAlertMiles.formatted(.number.precision(.fractionLength(0...1)))) mi")
                    Slider(value: $settings.overheadAlertMiles, in: RadarSettings.overheadAlertRange, step: 0.5)
                        .accessibilityLabel("Overhead distance in miles")
                }
            }
            Toggle(isOn: $settings.notableAlerts) {
                InfoLabel("Notable aircraft", info: "Emergencies, military, air ambulances and rare types.")
            }
            HStack {
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
                .buttonStyle(.borderless)
                Spacer()
                InfoButton(info: "Sky Watch keeps watching from your Lock Screen and Dynamic Island for two hours and sends alerts as notifications. It uses location in the background, so expect some battery use.")
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
        }
    }

    private var skyViewSection: some View {
        Section {
            Toggle(isOn: $settings.raiseToSkyView) {
                InfoLabel("Lift to open Sky View", info: "Raise your iPhone toward the sky and every aircraft is labeled through the camera; lower it or tap ✕ to return to the radar. With this off, open Sky View from Find in the Sky on any flight's details.")
            }
            Toggle(isOn: $settings.skySaveToPhotos) {
                InfoLabel("Save photos to camera roll", info: "Photos you take in Sky View go to your camera roll at full resolution, with the flight in the caption. The logbook keeps its own smaller copy either way, for the boarding pass and iCloud.")
            }
        } header: {
            Text("Sky View")
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
            InfoHeader("Apple TV", info: "Open What The Flight? on your Apple TV, then point your iPhone at the TV. It sends your location and the direction the screen faces, so every plane on the TV is where it really is.")
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
                LabeledContent {
                    Text("\(Int(settings.refreshSeconds)) s")
                } label: {
                    InfoLabel("Refresh every", info: "Positions are smoothed between refreshes, so a longer interval still moves fluidly and is kinder to your battery.")
                }
                Slider(value: $settings.refreshSeconds, in: RadarSettings.refreshRange, step: 5)
                    .accessibilityLabel("Refresh interval in seconds")
            }
            Toggle("Show helicopters", isOn: $settings.showHelicopters)
        } header: {
            Text("Radar")
        }
    }

    private var displaySection: some View {
        Section {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(RadarSettings.Appearance.allCases) { Text($0.title).tag($0) }
            }
            NavigationLink {
                AppIconPickerView { appIcon = $0 }
            } label: {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(appIcon.title)
                        AppIconPreview(choice: appIcon, size: 28)
                    }
                } label: {
                    Text("App Icon")
                }
            }
            Toggle("Topographic background", isOn: $settings.showTopography)
            Toggle("Compass bezel", isOn: $settings.showCompassBezel)
            Toggle("Radar sweep", isOn: $settings.radarSweep)
            Toggle("Aircraft photos", isOn: $settings.showPhotos)
            // The map pane is an iPad thing: the iPhone keeps the radar face.
            if UIDevice.current.userInterfaceIdiom == .pad {
                Toggle("Map view", isOn: $settings.mapView)
                if settings.mapView {
                    Toggle("Map north up", isOn: $settings.mapNorthUp)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Text("Map view: in landscape, shows a live map beside the radar.")
            }
        }
    }

    private var behaviourSection: some View {
        Section {
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
            Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
            Toggle(isOn: $settings.demoTraffic) {
                InfoLabel("Demo traffic", info: "Replaces live data with simulated aircraft around you, handy indoors or for showing the app off. Demo aircraft aren't logged.")
            }
            Button("Take the tour again") {
                dismiss()
                showWelcome()
            }
        } header: {
            Text("Behavior")
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
            InfoHeader("About", info: "What The Flight? uses Flightradar24's public web feed, which is unofficial and may change without notice.")
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

// MARK: - Info buttons

/// ⓘ that shows a setting's explanation in a small popover, instead of a long footer.
struct InfoButton: View {
    let info: String
    @State private var isShown = false

    var body: some View {
        Button { isShown = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 15))
                .foregroundStyle(Palette.caption)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("More info")
        .accessibilityHint(info)
        .popover(isPresented: $isShown) {
            Text(info)
                .font(.mono(13))
                .foregroundStyle(Palette.value)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 280, alignment: .leading)
                .padding(16)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// A setting's title with its ⓘ right after it.
struct InfoLabel: View {
    let title: String
    let info: String

    init(_ title: String, info: String) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            InfoButton(info: info)
        }
    }
}

/// A section header with an ⓘ for notes about the whole section.
struct InfoHeader: View {
    let title: String
    let info: String

    init(_ title: String, info: String) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            InfoButton(info: info)
                .textCase(nil)
        }
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
