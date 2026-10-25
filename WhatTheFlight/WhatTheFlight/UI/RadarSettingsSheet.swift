//
//  RadarSettingsSheet.swift
//  WhatTheFlight
//
//  iPhone / iPad settings. The first page is a list of rows, each opening a page of its
//  own (Radar, Display, Location, Alerts, Logbook, Sky View, Apple TV, Behavior, About),
//  plus "Take the tour again" for anyone who gets stuck. Section headings keep the
//  radar's mono voice, the rows use the system font.
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
    /// Closes settings and opens the logbook.
    let openLogbook: () -> Void
    let showWelcome: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var path: [SettingsPage] = SettingsPage.initialPath
    private let skyWatch = SkyWatch.shared

    enum SettingsPage: String, Hashable {
        case radar, display, topography, location, alerts, logbook, skyView = "skyview", behavior, about

        /// DEBUG: `-wtf.debugSettingsPage radar|display|topography|location|alerts|logbook|skyview|behavior|about`
        /// opens a page.
        static var initialPath: [SettingsPage] {
            #if DEBUG
            if let raw = UserDefaults.standard.string(forKey: "wtf.debugSettingsPage"),
               let page = SettingsPage(rawValue: raw) {
                return [page]
            }
            #endif
            return []
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    NavigationLink(value: SettingsPage.radar) {
                        SettingsPageRow("Radar", systemImage: "scope", color: .green, value: "\(Int(settings.radiusMiles)) mi")
                    }
                    NavigationLink(value: SettingsPage.display) {
                        SettingsPageRow("Display", systemImage: "sun.max.fill", color: .blue, value: settings.appearance.title)
                    }
                }

                Section {
                    NavigationLink(value: SettingsPage.location) {
                        SettingsPageRow("Location", systemImage: "location.fill", color: .teal, value: locationSummary)
                    }
                    NavigationLink(value: SettingsPage.alerts) {
                        SettingsPageRow("Alerts", systemImage: "bell.badge.fill", color: .red, value: alertsSummary)
                    }
                    NavigationLink(value: SettingsPage.logbook) {
                        SettingsPageRow("Logbook", systemImage: "book.closed.fill", color: .orange, value: logbookSummary)
                    }
                    NavigationLink(value: SettingsPage.skyView) {
                        SettingsPageRow("Sky View", systemImage: "camera.viewfinder", color: .indigo)
                    }
                    NavigationLink {
                        TVLinkSetupView(settings: settings, location: location)
                    } label: {
                        SettingsPageRow("Apple TV", systemImage: "appletv.fill", color: .gray)
                    }
                }

                Section {
                    NavigationLink(value: SettingsPage.behavior) {
                        SettingsPageRow("Behavior", systemImage: "gearshape.fill", color: .gray,
                                        value: settings.demoTraffic ? "Demo traffic" : nil)
                    }
                    NavigationLink(value: SettingsPage.about) {
                        SettingsPageRow("About", systemImage: "info", color: .gray, value: AboutSettingsPage.appVersion)
                    }
                }

                Section {
                    Button("Take the tour again") {
                        dismiss()
                        showWelcome()
                    }
                } footer: {
                    Text("A quick walk through the radar, Sky View and the logbook.")
                }
            }
            .settingsPage("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: SettingsPage.self) { page in
                switch page {
                case .radar: RadarSettingsPage(settings: settings)
                case .display: DisplaySettingsPage(settings: settings)
                case .topography: TopographySettingsPage(settings: settings)
                case .location: LocationSettingsPage(settings: settings, location: location)
                case .alerts: AlertSettingsPage(settings: settings, model: model, placeName: placeName)
                case .logbook: LogbookSettingsPage(settings: settings, logbook: logbook, openLogbook: openLogbook)
                case .skyView: SkyViewSettingsPage(settings: settings)
                case .behavior: BehaviorSettingsPage(settings: settings)
                case .about: AboutSettingsPage(settings: settings)
                }
            }
        }
    }

    // MARK: Summaries

    private var locationSummary: String {
        if settings.locationMode == .device {
            if location.isDenied { return "Access denied" }
            if !location.isAuthorized { return "Not allowed yet" }
        }
        return settings.locationMode.title
    }

    private var alertsSummary: String {
        if skyWatch.isActive { return "Sky Watch on" }
        switch (settings.overheadAlerts, settings.notableAlerts) {
        case (true, true): return "On"
        case (true, false): return "Overhead"
        case (false, true): return "Notable"
        case (false, false): return "Off"
        }
    }

    private var logbookSummary: String {
        settings.keepLogbook ? RadarFormat.wholeNumber(logbook.sightings.count) : "Off"
    }
}

// MARK: - Pages

private struct RadarSettingsPage: View {
    @Bindable var settings: RadarSettings

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Radius", value: "\(Int(settings.radiusMiles)) mi")
                    Slider(value: $settings.radiusMiles, in: RadarSettings.radiusRange, step: 1)
                        .accessibilityLabel("Radius in miles")
                }
                Toggle("Show helicopters", isOn: $settings.showHelicopters)
            } header: {
                SettingsHeader("Radar")
            }
        }
        .settingsPage("Radar")
    }
}

private struct DisplaySettingsPage: View {
    @Bindable var settings: RadarSettings

    @State private var appIcon = AppIconChoice.current
    @Environment(\.isFoldable) private var isFoldable

    var body: some View {
        Form {
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
            } header: {
                SettingsHeader("Look")
            }

            Section {
                NavigationLink(value: RadarSettingsSheet.SettingsPage.topography) {
                    LabeledContent("Topography", value: topographySummary)
                }
                Toggle("Compass bezel", isOn: $settings.showCompassBezel)
                Toggle("Radar sweep", isOn: $settings.radarSweep)
                Toggle("Aircraft photos", isOn: $settings.showPhotos)
                Toggle(isOn: $settings.cardPhotos) {
                    InfoLabel("Photos on flight cards", info: "The aircraft's photo under its details on the radar and beside them on the map card, whenever Planespotters has one. Sky View always shows it.")
                }
                .disabled(!settings.showPhotos)
            } header: {
                SettingsHeader("Radar face")
            }

            Section {
                Toggle("Map view", isOn: $settings.mapView)
                if settings.mapView {
                    Toggle("Map north up", isOn: $settings.mapNorthUp)
                }
            } header: {
                SettingsHeader("Map")
            } footer: {
                Text(mapFooter)
            }
        }
        .settingsPage("Display")
    }

    private var mapFooter: String {
        let button = "Map view adds a Map button to the bar at the bottom of the radar, for a live map of the traffic in its place."
        if isFoldable {
            return button + " Half open like a book or standing like a laptop, the radar goes on one side of the fold and the map on the other."
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            return button + " In landscape the map sits beside the radar instead."
        }
        return button
    }

    private var topographySummary: String {
        switch (settings.topography, settings.topographyMotion) {
        case (.off, _): return "Off"
        case (let style, .off): return style.title
        case (let style, let motion): return "\(style.title) · \(motion.title)"
        }
    }
}

/// Display → Topography: each style drawn small, and how fast the radar's contours creep.
private struct TopographySettingsPage: View {
    @Bindable var settings: RadarSettings

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Form {
            Section {
                ForEach(RadarSettings.TopographyStyle.allCases) { style in
                    Button {
                        settings.topography = style
                    } label: {
                        row(style)
                    }
                    .accessibilityAddTraits(settings.topography == style ? .isSelected : [])
                }
            } header: {
                SettingsHeader("Style")
            }

            if settings.topography != .off {
                Section {
                    Picker("Motion", selection: $settings.topographyMotion) {
                        ForEach(RadarSettings.TopographyMotion.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    SettingsHeader("Motion", info: "On the radar the contour lines slowly flow out from the hilltops while the ground stays put. At 1× they move one line spacing every 20 seconds. Motion pauses with Reduce Motion and in Low Power Mode.")
                }
            }
        }
        .settingsPage("Topography")
    }

    private func row(_ style: RadarSettings.TopographyStyle) -> some View {
        HStack(spacing: 14) {
            preview(style)
                .frame(width: 92, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Palette.faint.opacity(0.6), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(style.title)
                    .foregroundStyle(Palette.value)
                Text(style.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Palette.caption)
            }
            Spacer(minLength: 8)
            if settings.topography == style {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.ink)
            }
        }
        .contentShape(Rectangle())
    }

    /// A whole screen's worth of the style, shrunk into the thumbnail.
    @ViewBuilder
    private func preview(_ style: RadarSettings.TopographyStyle) -> some View {
        let size = CGSize(width: 92, height: 60)
        if let image = TopographyRenderer.shared?.image(style: style, dark: colorScheme == .dark, size: size,
                                                        scale: displayScale, zoom: 420 / size.width) {
            Image(decorative: image, scale: displayScale)
        } else {
            Palette.paper
        }
    }
}

private struct BehaviorSettingsPage: View {
    @Bindable var settings: RadarSettings

    var body: some View {
        Form {
            Section {
                Toggle("Haptics", isOn: $settings.hapticsEnabled)
                Toggle("Keep screen awake", isOn: $settings.keepScreenAwake)
                Toggle(isOn: $settings.demoTraffic) {
                    InfoLabel("Demo traffic", info: "Replaces live data with simulated aircraft around you, handy indoors or for showing the app off. Demo aircraft aren't logged.")
                }
            } header: {
                SettingsHeader("Behavior")
            }
        }
        .settingsPage("Behavior")
    }
}

private struct LocationSettingsPage: View {
    @Bindable var settings: RadarSettings
    let location: RadarLocationService

    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
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
                        LabeledContent("Spot", value: settings.customCoordinate?.shortDescription ?? "Not set")
                    }
                }
            } header: {
                SettingsHeader("Watch from", info: "A custom spot lets you watch the sky over home, an airport fence, anywhere. Aircraft seen at a custom spot aren't logged and don't count toward stats or badges: the logbook is what you saw yourself.")
            }
        }
        .settingsPage("Location")
    }

    private var deviceStatus: String {
        if location.isDenied { return "Access denied" }
        if !location.isAuthorized { return "Not allowed yet" }
        guard let coordinate = location.location?.coordinate else { return "Finding you…" }
        return coordinate.shortDescription
    }
}

private struct AlertSettingsPage: View {
    @Bindable var settings: RadarSettings
    let model: RadarModel
    let placeName: String

    private let skyWatch = SkyWatch.shared

    var body: some View {
        Form {
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
            } header: {
                SettingsHeader("Alerts")
            }

            Section {
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
                SettingsHeader("Sky Watch", info: "Sky Watch keeps watching from your Lock Screen and Dynamic Island for two hours and sends alerts as notifications. It uses location in the background, so expect some battery use.")
            }
        }
        .settingsPage("Alerts")
    }
}

private struct LogbookSettingsPage: View {
    @Bindable var settings: RadarSettings
    let logbook: Logbook
    let openLogbook: () -> Void

    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Button(action: openLogbook) {
                    LabeledContent {
                        Text(RadarFormat.wholeNumber(logbook.sightings.count))
                    } label: {
                        Label("Open Logbook", systemImage: "book.closed")
                    }
                }
            }

            Section {
                Toggle(isOn: $settings.keepLogbook) {
                    InfoLabel("Keep a logbook", info: "Every aircraft that comes inside your radius, with where you were, stats and badges. Demo traffic and custom spots aren't logged, only what's around you.")
                }
                Toggle(isOn: $settings.syncLogbook) {
                    InfoLabel("Sync with iCloud", info: "One logbook across your iPhone, iPad and Apple TV. Each sighting shows which device logged it, and a flight seen on two devices counts once.")
                }
                .disabled(!settings.keepLogbook)
            } header: {
                SettingsHeader("Logging")
            }

            Section {
                Button("Clear Logbook", systemImage: "trash", role: .destructive) { confirmClear = true }
                    .tint(.red)
                    .disabled(logbook.isEmpty)
            } footer: {
                Text("Removes every sighting, photo and badge, on all your devices if the logbook syncs with iCloud.")
            }
        }
        .confirmationDialog("Clear the whole logbook?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Logbook", role: .destructive) { logbook.clear() }
        } message: {
            Text("Every sighting, photo and badge will be removed, on all your devices if the logbook syncs with iCloud.")
        }
        .settingsPage("Logbook")
    }
}

private struct SkyViewSettingsPage: View {
    @Bindable var settings: RadarSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.raiseToSkyView) {
                    InfoLabel("Lift to open Sky View", info: "Raise your iPhone toward the sky and every aircraft is labeled through the camera; lower it or tap ✕ to return to the radar. With this off, open Sky View from Find in the Sky on any flight's details.")
                }
                Toggle(isOn: $settings.skySaveToPhotos) {
                    InfoLabel("Save photos to camera roll", info: "Photos you take in Sky View go to your camera roll at full resolution, with the flight in the caption. The logbook keeps its own smaller copy either way, for the boarding pass and iCloud.")
                }
            } header: {
                SettingsHeader("Sky View")
            }
        }
        .settingsPage("Sky View")
    }
}

private struct AboutSettingsPage: View {
    let settings: RadarSettings

    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Self.appVersion)
            } header: {
                SettingsHeader("What The Flight?", info: "What The Flight? uses Flightradar24's public web feed, which is unofficial and may change without notice.")
            }

            Section {
                LabeledContent("Flight data", value: "Flightradar24")
                LabeledContent("Photos", value: "Planespotters.net")
                LabeledContent("Airports", value: "OurAirports")
                LabeledContent("Airlines", value: "OpenFlights (ODbL)")
            } header: {
                SettingsHeader("Data")
            }

            Section {
                Button("Reset to Defaults", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Reset all settings?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Reset", role: .destructive) { settings.resetToDefaults() }
                    }
            }
        }
        .settingsPage("About")
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

private extension View {
    /// The paper background, ink tint and inline title every settings page shares.
    func settingsPage(_ title: String) -> some View {
        self.scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Palette.ink)
    }
}

// MARK: - Rows & headers

/// A row on the first page that opens a page of its own: an icon tile, the title and a
/// short summary of what's set inside.
private struct SettingsPageRow: View {
    let title: String
    let systemImage: String
    let color: Color
    let value: String?

    init(_ title: String, systemImage: String, color: Color, value: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.value = value
    }

    var body: some View {
        LabeledContent {
            if let value { Text(value) }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

/// A section heading in the radar's mono voice, with an optional ⓘ for notes about the
/// whole section.
struct SettingsHeader: View {
    let title: String
    let info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .fontDesign(.monospaced)
            if let info {
                InfoButton(info: info)
                    .textCase(nil)
            }
        }
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
                .font(.subheadline)
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
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.value)
                    Text("\(Int(settings.radiusMiles)) mi radius")
                        .font(.caption)
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
