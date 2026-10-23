//
//  TVRadarSettingsView.swift
//  WhatTheFlight
//
//  Apple TV settings, built for the Siri Remote: a sidebar (focus moves = page changes,
//  like tvOS Settings), big rows, chip pickers instead of sliders, full-screen tvOS search
//  for places (with suggestions as you type), and an iPhone hand-off card that does the
//  hard part (location + TV direction).
//

#if os(tvOS)
import SwiftUI
import CoreLocation

enum TVSettingsPane: String, CaseIterable, Identifiable {
    case radar, display, location, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: return "Location"
        case .radar: return "Radar"
        case .display: return "Display"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .location: return "location.north.circle.fill"
        case .radar: return "dot.radiowaves.left.and.right"
        case .display: return "circle.lefthalf.filled"
        case .about: return "info.circle.fill"
        }
    }
}

struct TVRadarSettingsView: View {
    @Bindable var settings: RadarSettings
    let model: RadarModel
    let link: TVLinkReceiver
    let tvLocation: TVLocationProvider
    let initialPane: TVSettingsPane
    /// Replays the first-run tour (About → Take the Tour).
    var showTour: () -> Void = {}

    @State private var pane: TVSettingsPane
    @FocusState private var focusedPane: TVSettingsPane?
    @State private var showSearch = false
    @State private var showCoordinates = false
    @State private var confirmReset = false
    @State private var confirmClearLocation = false

    init(settings: RadarSettings, model: RadarModel, link: TVLinkReceiver, tvLocation: TVLocationProvider, initialPane: TVSettingsPane,
         showTour: @escaping () -> Void = {}) {
        self.settings = settings
        self.model = model
        self.link = link
        self.tvLocation = tvLocation
        self.initialPane = initialPane
        self.showTour = showTour
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            sidebar
                .frame(width: 380)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch pane {
                    case .location: locationPane
                    case .radar: radarPane
                    case .display: displayPane
                    case .about: aboutPane
                    }
                }
                .padding(.vertical, 30)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 50)
        .background(RadarBackdrop(showTopography: settings.showTopography, showSweep: false, isActive: true).ignoresSafeArea())
        .preferredColorScheme(settings.appearance.colorScheme)
        .defaultFocus($focusedPane, initialPane)
        .onChange(of: focusedPane) { _, newValue in
            if let newValue { withAnimation(.smooth(duration: 0.25)) { pane = newValue } }
        }
        // Full screen, not a sheet: a tvOS sheet is a small card that squeezes the keyboard.
        .fullScreenCover(isPresented: $showSearch) {
            TVPlaceSearchView(near: model.observer, showTopography: settings.showTopography) { place in
                apply(place.coordinate, name: place.detail.isEmpty ? place.name : "\(place.name) · \(place.detail)")
                showSearch = false
            }
            .preferredColorScheme(settings.appearance.colorScheme)
        }
        .fullScreenCover(isPresented: $showCoordinates) {
            TVCoordinateFormView(initial: settings.customCoordinate ?? model.observer) { coordinate in
                apply(coordinate, name: nil)
                showCoordinates = false
            }
            .background(RadarBackdrop(showTopography: settings.showTopography, showSweep: false, isActive: true).ignoresSafeArea())
            .preferredColorScheme(settings.appearance.colorScheme)
        }
        #if DEBUG
        .task {
            // `-wtf.debugSearch "123 Peachtree"` opens place search with that query.
            if UserDefaults.standard.string(forKey: "wtf.debugSearch") != nil { showSearch = true }
        }
        #endif
        .onChange(of: tvLocation.coordinate?.latitude) { _, _ in
            // "Use this Apple TV's location" finished.
            if settings.locationMode == .device { model.post(notice: "Using this Apple TV's location", symbol: "appletv.fill") }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.mono(52, .heavy))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 24)
                .padding(.leading, 26)
            ForEach(TVSettingsPane.allCases) { item in
                Button {
                    pane = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                }
                .buttonStyle(TVSidebarItemStyle(isSelected: pane == item))
                .focused($focusedPane, equals: item)
            }
            Spacer()
            Text("Press MENU to return to the radar")
                .font(.mono(18))
                .foregroundStyle(Palette.caption)
                .padding(.leading, 26)
        }
        .focusSection()
    }

    // MARK: Location

    @ViewBuilder
    private var locationPane: some View {
        summaryCard
        iPhoneCard

        TVSectionHeader(title: "Or set it up manually")
        HStack(spacing: 24) {
            tile(symbol: "magnifyingglass", title: "Search for a Place", detail: "Type or say an address, city or airport") {
                showSearch = true
            }
            tile(symbol: "appletv.fill", title: "Use This Apple TV", detail: tvLocationDetail) {
                settings.locationMode = .device
                tvLocation.locate()
            }
            tile(symbol: "number", title: "Enter Coordinates", detail: "Latitude & longitude") {
                showCoordinates = true
            }
        }
        .focusSection()

        TVSectionHeader(title: "Which way does the TV face?")
        Text("The compass direction you look when you watch the TV. Planes ahead of you appear at the top of the screen.")
            .font(.mono(20))
            .foregroundStyle(Palette.caption)
            .padding(.leading, 6)

        TVChoiceRow(
            title: "Facing",
            subtitle: "\(Int(settings.tvFacingDegrees.rounded()) % 360)° \(GeoMath.cardinal(settings.tvFacingDegrees))",
            options: Array(stride(from: 0.0, to: 360, by: 45)),
            selection: settings.tvFacingDegrees,
            label: { GeoMath.cardinal($0) },
            onSelect: { settings.tvFacingDegrees = $0 }
        )

        TVChoiceRow(
            title: "Fine tune",
            options: [-15.0, -5.0, -1.0, 1.0, 5.0, 15.0],
            selection: .nan,
            label: { $0 > 0 ? "+\(Int($0))°" : "\(Int($0))°" },
            onSelect: { settings.tvFacingDegrees = GeoMath.normalize(settings.tvFacingDegrees + $0) }
        )

        TVSectionHeader(title: "Start over")
        TVValueRow(
            title: "Clear Location",
            subtitle: "Forget the saved place, facing direction and iPhone hand-off",
            value: "",
            symbol: "trash"
        ) {
            confirmClearLocation = true
        }
        .confirmationDialog("Clear the location?", isPresented: $confirmClearLocation) {
            Button("Clear Location", role: .destructive) { clearLocation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The radar will stop until you set a new location.")
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 34) {
            TVFacingDial(facing: settings.tvFacingDegrees, size: 210)
            VStack(alignment: .leading, spacing: 10) {
                Text("Watching from").radarCaptionTV()
                Text(placeTitle)
                    .font(.mono(34, .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let coordinate = model.observer {
                    Text(coordinate.shortDescription)
                        .font(.mono(20))
                        .foregroundStyle(Palette.caption)
                }
                Text("Facing").radarCaptionTV().padding(.top, 14)
                Text("\(Int(settings.tvFacingDegrees.rounded()) % 360)° \(GeoMath.cardinal(settings.tvFacingDegrees))")
                    .font(.mono(34, .bold))
                    .foregroundStyle(Palette.value)
                    .contentTransition(.numericText(value: settings.tvFacingDegrees))
            }
            Spacer(minLength: 0)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var iPhoneCard: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Palette.signal)
                    Text("Easiest: aim your iPhone")
                        .font(.mono(28, .bold))
                        .foregroundStyle(Palette.value)
                }
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "On your iPhone, open the What The Flight? app, tap its ⚙︎ Settings button, then Apple TV → Aim at Your Apple TV")
                    step(2, "Stand directly in front of this TV, facing it, and hold the iPhone up so its camera points at the center of the screen")
                    step(3, "Hold it steady and tap Send — your location and the direction the TV faces arrive here")
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                Text("Code").radarCaptionTV()
                Text(link.code.map(String.init).joined(separator: " "))
                    .font(.mono(56, .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                linkStatus
                    .lineLimit(1)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.mono(18, .heavy))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Palette.ink, in: Circle())
            Text(text)
                .font(.mono(20))
                .foregroundStyle(Palette.value)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var linkStatus: some View {
        if let received = link.lastReceivedAt {
            Label("Received \(received.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                .font(.mono(20, .semibold))
                .foregroundStyle(Palette.live)
                .labelStyle(TVLabelStyle())
        } else {
            switch link.status {
            case .listening, .connected:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(link.status == .connected ? "iPhone connected" : "Waiting for iPhone")
                        .font(.mono(20, .semibold))
                        .foregroundStyle(Palette.caption)
                }
            case .failed(let message):
                Text(message)
                    .font(.mono(18))
                    .foregroundStyle(Palette.signal)
            case .idle:
                EmptyView()
            }
        }
    }

    private func tile(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TileContent(symbol: symbol, title: title, detail: detail)
        }
        .buttonStyle(TVTileButtonStyle())
    }

    private struct TileContent: View {
        let symbol: String
        let title: String
        let detail: String
        @Environment(\.tvRowFocused) private var focused

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(focused ? .white : Palette.ink)
                Spacer(minLength: 0)
                Text(title)
                    .font(.mono(26, .bold))
                Text(detail)
                    .font(.mono(18))
                    .foregroundStyle(focused ? .white.opacity(0.85) : Palette.caption)
                    .lineLimit(2)
            }
        }
    }

    private var placeTitle: String {
        switch settings.locationMode {
        case .custom:
            if let name = settings.customPlaceName { return name }
            return settings.customCoordinate == nil ? "Not set yet" : "Custom spot"
        case .device:
            if tvLocation.isLocating { return "Locating this Apple TV…" }
            return tvLocation.coordinate == nil ? "Not set yet" : "This Apple TV"
        }
    }

    private var tvLocationDetail: String {
        if tvLocation.isLocating { return "Locating…" }
        if let error = tvLocation.lastError { return error }
        if settings.locationMode == .device, tvLocation.coordinate != nil { return "In use · approximate" }
        return "Approximate, from Wi-Fi"
    }

    private func clearLocation() {
        settings.customCoordinate = nil
        settings.locationMode = .custom
        withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { settings.tvFacingDegrees = 0 }
        tvLocation.forget()
        link.forgetLastPayload()
        model.post(notice: "Location cleared", symbol: "trash")
    }

    private func apply(_ coordinate: CLLocationCoordinate2D, name: String?) {
        settings.customCoordinate = coordinate
        settings.locationMode = .custom
        if let name {
            settings.customPlaceName = name
        } else {
            Task { settings.customPlaceName = await PlaceServices.name(for: coordinate) }
        }
    }

    // MARK: Radar

    @ViewBuilder
    private var radarPane: some View {
        TVSectionHeader(title: "Coverage")
        TVChoiceRow(
            title: "Radius",
            subtitle: "\(Int(settings.radiusMiles)) mi",
            options: [5.0, 10, 15, 20, 25, 30, 40, 50, 75, 100],
            selection: settings.radiusMiles,
            label: { "\(Int($0))" },
            onSelect: { settings.radiusMiles = $0 }
        )
        TVChoiceRow(
            title: "Refresh every",
            subtitle: "\(Int(settings.refreshSeconds)) s · positions stay smooth in between",
            options: [5.0, 10, 15, 30, 60],
            selection: settings.refreshSeconds,
            label: { "\(Int($0))s" },
            onSelect: { settings.refreshSeconds = $0 }
        )
        TVSectionHeader(title: "Traffic")
        TVToggleRow(title: "Demo traffic", subtitle: "Simulated aircraft — great for trying it out", symbol: "sparkles", isOn: $settings.demoTraffic)

        TVSectionHeader(title: "Alerts")
        TVToggleRow(title: "Overhead alerts", subtitle: "A banner when an aircraft is about to pass over you", symbol: "scope", isOn: $settings.overheadAlerts)
        if settings.overheadAlerts {
            TVChoiceRow(
                title: "Overhead means within",
                subtitle: "\(settings.overheadAlertMiles.formatted(.number.precision(.fractionLength(0...1)))) mi",
                options: [0.5, 1, 1.5, 2, 3, 5],
                selection: settings.overheadAlertMiles,
                label: { "\($0.formatted(.number.precision(.fractionLength(0...1)))) mi" },
                onSelect: { settings.overheadAlertMiles = $0 }
            )
            TVChoiceRow(
                title: "Alert ahead",
                subtitle: "\(Self.leadLabel(settings.overheadAlertLeadSeconds)) before it passes over",
                options: [30.0, 60, 90, 120, 150, 180, 300],
                selection: settings.overheadAlertLeadSeconds,
                label: Self.leadLabel,
                onSelect: { settings.overheadAlertLeadSeconds = $0 }
            )
        }
        TVToggleRow(title: "Speak alerts", subtitle: "Also announce them out loud: “Delta Air Lines flight 1199 is approaching overhead…”",
                    symbol: "speaker.wave.2.fill", isOn: $settings.spokenAlerts)
        if settings.spokenAlerts {
            TVValueRow(title: "Play a sample", subtitle: sampleSubtitle, value: "", symbol: "play.circle.fill") {
                AlertSpeaker.shared.speak(sampleAnnouncement)
            }
        }
        TVToggleRow(title: "Notable aircraft", subtitle: "Emergencies, military, air ambulances and rare types", symbol: "star.fill", isOn: $settings.notableAlerts)

        TVSectionHeader(title: "Logbook")
        TVToggleRow(title: "Keep a logbook", subtitle: "Record every aircraft that comes inside your radius. Kept on this Apple TV only; demo traffic is never logged",
                    symbol: "book.closed.fill", isOn: $settings.keepLogbook)
    }

    /// The nearest real aircraft if there is one, so the sample sounds like the real thing.
    private var sampleAnnouncement: String {
        if let contact = model.contacts.first {
            return SpokenTraffic.sentence(for: contact, reason: .overhead)
        }
        return "Delta Air Lines flight 1199, from Atlanta to Chicago, is approaching overhead, about 2 minutes away, at 9,500 feet. Look northeast."
    }

    /// "30 s", "1 min", "2½ min".
    private static func leadLabel(_ seconds: Double) -> String {
        guard seconds >= 60 else { return "\(Int(seconds)) s" }
        let whole = Int(seconds) / 60
        return Int(seconds) % 60 == 0 ? "\(whole) min" : "\(whole)½ min"
    }

    private var sampleSubtitle: String {
        model.contacts.first.map { "Announces \($0.flight.displayIdentifier), the nearest aircraft right now" } ?? "Hear what an overhead alert sounds like"
    }

    // MARK: Display

    @ViewBuilder
    private var displayPane: some View {
        TVSectionHeader(title: "Look")
        TVChoiceRow(
            title: "Appearance",
            options: RadarSettings.Appearance.allCases,
            selection: settings.appearance,
            label: { $0.title },
            onSelect: { settings.appearance = $0 }
        )
        TVChoiceRow(
            title: "Topography",
            subtitle: settings.topography.subtitle,
            options: RadarSettings.TopographyStyle.allCases,
            selection: settings.topography,
            label: { $0.title },
            onSelect: { settings.topography = $0 }
        )
        if settings.topography != .off {
            TVChoiceRow(
                title: "Contour motion",
                subtitle: "The lines slowly flow out from the hilltops on the radar",
                options: RadarSettings.TopographyMotion.allCases,
                selection: settings.topographyMotion,
                label: { $0.title },
                onSelect: { settings.topographyMotion = $0 }
            )
        }
        TVToggleRow(title: "Compass bezel", symbol: "location.north.line.fill", isOn: $settings.showCompassBezel)
        TVToggleRow(title: "Radar sweep", symbol: "dot.radiowaves.right", isOn: $settings.radarSweep)
        TVToggleRow(title: "Aircraft photos", symbol: "photo.fill", isOn: $settings.showPhotos)

        TVSectionHeader(title: "Map")
        TVToggleRow(title: "Map view", subtitle: "A live map of every aircraft around you, beside the radar or full screen",
                    symbol: "map.fill", isOn: $settings.mapView)
        if settings.mapView {
            TVChoiceRow(
                title: "View",
                subtitle: "Split puts the map beside the radar. The dock's view button steps through all three",
                options: RadarSettings.TVView.allCases,
                selection: settings.tvView,
                label: { $0.title },
                onSelect: { settings.tvView = $0 }
            )
            TVChoiceRow(
                title: "Map range",
                subtitle: "\(Int(settings.effectiveMapRadius)) mi · on the radar or map, hold ● to change it",
                options: RadarSettings.mapRadiusChoices,
                selection: settings.mapRadiusMiles,
                label: { $0.map { "\(Int($0))" } ?? "Same as radar" },
                onSelect: { settings.mapRadiusMiles = $0 }
            )
            TVChoiceRow(
                title: "Map style",
                options: RadarSettings.MapType.allCases,
                selection: settings.mapType,
                label: { $0.title },
                onSelect: { settings.mapType = $0 }
            )
            TVToggleRow(title: "Map north up", subtitle: "Off, the map turns so the top of the screen is the way the TV faces",
                        symbol: "location.north.line.fill", isOn: $settings.mapNorthUp)
        }

        TVSectionHeader(title: "Screen")
        TVToggleRow(title: "Keep screen awake", subtitle: "No screen saver or sleep while the radar is open",
                    symbol: "sun.max.fill", isOn: $settings.keepScreenAwake)
    }

    // MARK: About

    @ViewBuilder
    private var aboutPane: some View {
        TVSectionHeader(title: "What The Flight?")
        TVValueRow(title: "Version", value: appVersion, symbol: "app.badge") {}
        TVValueRow(title: "Flight data", subtitle: "Unofficial public feed — may change without notice", value: "Flightradar24", symbol: "antenna.radiowaves.left.and.right") {}
        TVValueRow(title: "Aircraft photos", value: "Planespotters.net", symbol: "camera.fill") {}
        TVValueRow(title: "Airports", subtitle: "Public domain", value: "OurAirports", symbol: "mappin.and.ellipse") {}
        TVValueRow(title: "Airlines", subtitle: "Open Database License (ODbL)", value: "OpenFlights", symbol: "airplane.circle") {}
        TVValueRow(title: "iPhone link code", value: link.code, symbol: "iphone") {}
        TVValueRow(title: "Take the tour", subtitle: "What the radar shows and how to drive it", value: "", symbol: "sparkles") {
            showTour()
        }
        TVSectionHeader(title: "Reset")
        TVValueRow(title: "Reset all settings", value: "", symbol: "arrow.counterclockwise") {
            confirmReset = true
        }
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                settings.tvFacingDegrees = 0
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "—") (\(info?["CFBundleVersion"] as? String ?? "—"))"
    }
}

extension Text {
    func radarCaptionTV() -> some View {
        self.font(.mono(18, .bold))
            .tracking(2.5)
            .textCase(.uppercase)
            .foregroundStyle(Palette.caption)
    }
}

// MARK: - Place search

/// Full-screen tvOS search: the standard keyboard row (plus dictation with the Siri button,
/// or the iPhone keyboard), with MapKit suggesting addresses and places as you type.
struct TVPlaceSearchView: View {
    let near: CLLocationCoordinate2D?
    var showTopography = true
    let onPick: (PlaceResult) -> Void

    #if DEBUG
    @State private var query = UserDefaults.standard.string(forKey: "wtf.debugSearch") ?? ""
    #else
    @State private var query = ""
    #endif
    @State private var completer = PlaceCompleter()
    /// Plain search results, used when the suggestions come up empty.
    @State private var fallback: [PlaceResult] = []
    @State private var resolvingID: String?
    @State private var failedID: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if completer.suggestions.isEmpty, fallback.isEmpty {
                        emptyState
                    }
                    ForEach(completer.suggestions) { suggestion in
                        TVValueRow(
                            title: suggestion.title,
                            subtitle: suggestion.subtitle.isEmpty ? nil : suggestion.subtitle,
                            value: status(for: suggestion.id),
                            symbol: suggestion.isQuery ? "magnifyingglass" : "mappin.circle.fill"
                        ) {
                            pick(suggestion)
                        }
                    }
                    if completer.suggestions.isEmpty {
                        ForEach(fallback) { place in
                            TVValueRow(title: place.name, subtitle: place.detail.isEmpty ? nil : place.detail, value: "", symbol: "mappin.circle.fill") {
                                onPick(place)
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
            .searchable(text: $query, prompt: "Address, city or airport")
            .onAppear { completer.update(query, near: near) }
            .onChange(of: query) { _, newValue in
                failedID = nil
                completer.update(newValue, near: near)
            }
            .task(id: query) {
                // If MapKit has no suggestions for what was typed, fall back to a full search.
                fallback = []
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled, trimmedQuery.count >= 2, completer.suggestions.isEmpty else { return }
                fallback = await PlaceServices.search(trimmedQuery, near: near)
            }
        }
        .background(RadarBackdrop(showTopography: showTopography, showSweep: false, isActive: true).ignoresSafeArea())
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            if trimmedQuery.isEmpty {
                Text("Where are you watching from?")
                    .font(.mono(34, .bold))
                    .foregroundStyle(Palette.ink)
                Label("Type above — suggestions appear as you go", systemImage: "keyboard")
                Label("Or hold the Siri button on your remote and say the address", systemImage: "mic.fill")
                Label("Or type on your iPhone when the keyboard notification appears", systemImage: "iphone")
            } else if completer.settledQuery != trimmedQuery {
                Label("Searching…", systemImage: "magnifyingglass")
            } else {
                Label("No places found for “\(trimmedQuery)”", systemImage: "mappin.slash")
            }
        }
        .font(.mono(24))
        .labelStyle(TVLabelStyle())
        .foregroundStyle(Palette.caption)
        .padding(.top, 30)
    }

    private func status(for id: String) -> String {
        if resolvingID == id { return "Finding…" }
        if failedID == id { return "Not found" }
        return ""
    }

    private func pick(_ suggestion: PlaceSuggestion) {
        guard resolvingID == nil else { return }
        resolvingID = suggestion.id
        failedID = nil
        Task {
            let place = await PlaceServices.resolve(suggestion)
            resolvingID = nil
            if let place { onPick(place) } else { failedID = suggestion.id }
        }
    }
}

// MARK: - Coordinate entry

struct TVCoordinateFormView: View {
    let onApply: (CLLocationCoordinate2D) -> Void

    @State private var latitude: String
    @State private var longitude: String

    init(initial: CLLocationCoordinate2D?, onApply: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onApply = onApply
        _latitude = State(initialValue: initial.map { String(format: "%.4f", $0.latitude) } ?? "")
        _longitude = State(initialValue: initial.map { String(format: "%.4f", $0.longitude) } ?? "")
    }

    private var parsed: CLLocationCoordinate2D? {
        guard let lat = Double(latitude.trimmingCharacters(in: .whitespaces)),
              let lon = Double(longitude.trimmingCharacters(in: .whitespaces)),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("Enter Coordinates")
                .font(.mono(48, .heavy))
                .foregroundStyle(Palette.ink)
            Text("Decimal degrees. South latitudes and west longitudes are negative (Atlanta is 33.749, -84.388).")
                .font(.mono(22))
                .foregroundStyle(Palette.caption)
            HStack(spacing: 30) {
                field("Latitude", text: $latitude)
                field("Longitude", text: $longitude)
            }
            HStack(spacing: 24) {
                Button("Use These Coordinates") {
                    if let parsed { onApply(parsed) }
                }
                .buttonStyle(TVPillButtonStyle(prominent: true))
                .disabled(parsed == nil)
                if parsed == nil, !(latitude.isEmpty && longitude.isEmpty) {
                    Text("Latitude must be −90…90 and longitude −180…180.")
                        .font(.mono(20))
                        .foregroundStyle(Palette.signal)
                }
            }
        }
        .padding(80)
        .frame(maxWidth: 1300)
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).radarCaptionTV()
            TextField(title, text: text)
                .keyboardType(.numbersAndPunctuation)
                .font(.mono(30, .bold))
        }
    }
}
#endif
