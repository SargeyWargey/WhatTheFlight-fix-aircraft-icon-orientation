//
//  TVRadarRootView.swift
//  WhatTheFlight
//
//  Apple TV entry point: owns state, listens for the iPhone hand-off, and presents the
//  settings, detail and aircraft-list screens.
//

#if os(tvOS)
import SwiftUI
import CoreLocation
import TVServices

struct TVRadarRootView: View {
    @State private var settings: RadarSettings
    @State private var model: RadarModel
    @LazyState private var logbook = Logbook(device: .current)
    @State private var logbookSync: LogbookSync?
    @State private var pinSync: PinSync?
    @State private var favoriteSync: FavoriteSync?
    @LazyState private var placeNamer = PlaceNamer()
    @LazyState private var link = TVLinkReceiver()
    @LazyState private var tvLocation = TVLocationProvider()
    @State private var presented: Presented?
    /// Goes up once the cover on screen has gone (`present(_:)`).
    @State private var queued: Presented?
    /// A Top Shelf selection that arrived before the first feed load.
    @State private var pendingFlight: String?
    @State private var lastTopShelfRefresh = Date.distantPast
    /// Bumped on every radius change; the re-query waits for the chips to settle.
    @State private var radiusEdits = 0
    /// Naming a place the iPhone sent; a newer hand-off replaces it.
    @State private var placeLookup: Task<Void, Never>?

    @Environment(\.scenePhase) private var scenePhase

    enum Presented: Identifiable, Equatable {
        case settings(TVSettingsPane)
        case detail(String)
        case aircraft
        case logbook
        case tour

        var id: String {
            switch self {
            case .settings: return "settings"
            case .detail(let id): return "detail-\(id)"
            case .aircraft: return "aircraft"
            case .logbook: return "logbook"
            case .tour: return "tour"
            }
        }
    }

    init() {
        let settings = RadarSettings()
        #if DEBUG
        // `-wtf.debugSpot 33.749,-84.388` (a negative value can't be passed as its own argument).
        if let spot = UserDefaults.standard.string(forKey: "wtf.debugSpot")?.split(separator: ","),
           spot.count == 2, let lat = Double(spot[0]), let lon = Double(spot[1]) {
            settings.customCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            settings.locationMode = .custom
        }
        #endif
        // The TV has no GPS: unless the user picked "Use This Apple TV", watch a set spot.
        if settings.customCoordinate == nil, UserDefaults.standard.object(forKey: "wtf.locationMode") == nil {
            settings.locationMode = .custom
        }
        _settings = State(initialValue: settings)
        _model = State(initialValue: RadarModel(settings: settings))
    }

    var body: some View {
        screen
        .environment(\.radarObserver, model.observer)
        .environment(\.topographyStyle, settings.topography)
        .environment(\.favoriteAircraft, settings.favoriteSet)
        .onAppear {
            link.onPayload = { apply($0) }
            model.logbook = logbook
            logbook.onBadgeUnlocked = { [model] badge in model.post(notice: badge.unlockNotice, symbol: badge.symbol) }
            // The TV has no GPS, so its set place is where it really is: log from there.
            model.logsCustomSpot = true
            startPinSync()
            model.onAlert = announce
            model.queryRadiusFloor = mapQueryFloor
            model.trailRadiusFloor = mapTrailFloor
            link.start()
            model.start()
            if settings.locationMode == .device { tvLocation.locate() }
            if !settings.hasSeenWelcome { presented = .tour }
            #if DEBUG
            openDebugScreenIfRequested()
            model.debugPinIfRequested()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                link.start()
                model.start()
                model.refreshNow()
                logbookSync?.fetchNow()
                pinSync?.refresh()
                favoriteSync?.refresh()
            case .background:
                model.stop()
                link.stop()
                logbook.flush()
            default:
                break
            }
        }
        // Also names the place for the logbook; a newer spot cancels the lookup for the old one.
        .task(id: observerKey) {
            syncObserver()
            await nameLoggingPlace()
        }
        // "Keep screen awake" holds off the screen saver (and sleep) while the radar is open.
        .onChange(of: keepsScreenAwake, initial: true) { _, awake in UIApplication.shared.isIdleTimerDisabled = awake }
        .onChange(of: settings.syncLogbook, initial: true) { _, _ in updateLogbookSync() }
        .onChange(of: settings.demoTraffic) { _, _ in model.settingsDidChange(refetch: true) }
        .onChange(of: settings.radiusMiles) { _, _ in
            // Re-filter at once while the chips move; re-query once they settle.
            model.settingsDidChange(refetch: false)
            radiusEdits += 1
        }
        .task(id: radiusEdits) {
            guard radiusEdits > 0 else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            model.settingsDidChange(refetch: true)
        }
        .onChange(of: mapQueryFloor) { _, floor in
            model.queryRadiusFloor = floor
            model.trailRadiusFloor = mapTrailFloor
            // Only a map wider than the radar's own query needs fetching again now.
            if floor > settings.radiusMiles * 1.5 + 3 { model.settingsDidChange(refetch: true) }
        }
        .onChange(of: model.lastUpdated) { _, _ in publishTopShelf() }
        .onChange(of: AlertSpeaker.shared.speakingFlightID) { _, id in followAnnouncement(id) }
        .onChange(of: model.hasLoadedOnce) { _, loaded in
            if loaded, let id = pendingFlight {
                pendingFlight = nil
                showFlight(id)
            }
        }
        .onOpenURL(perform: open)
    }

    /// whattheflight://flight/<id> from the Top Shelf.
    private func open(_ url: URL) {
        guard url.host() == "flight", let id = url.pathComponents.dropFirst().first else { return }
        if model.hasLoadedOnce { showFlight(id) } else { pendingFlight = id }
    }

    /// The radar and everything presented over it.
    private var screen: some View {
        TVRadarScreen(
            model: model,
            settings: settings,
            centerState: centerState,
            actions: .init(
                openSettings: { presented = .settings($0) },
                openDetail: { presented = .detail($0) },
                openAircraft: { presented = .aircraft },
                openLogbook: { presented = .logbook },
                centerPrimary: centerPrimary,
                centerSecondary: centerSecondary
            )
        )
        .preferredColorScheme(settings.appearance.colorScheme)
        .fullScreenCover(item: $presented, onDismiss: presentQueued) { item in
            presentation(item)
                .environment(\.topographyStyle, settings.topography)
                .environment(\.favoriteAircraft, settings.favoriteSet)
                .environment(\.toggleFavorite, FavoriteToggle { [model] in model.toggleFavorite($0) })
        }
    }

    @ViewBuilder
    private func presentation(_ item: Presented) -> some View {
        switch item {
        case .settings(let pane):
            TVRadarSettingsView(settings: settings, model: model, link: link, tvLocation: tvLocation, initialPane: pane) {
                present(.tour)
            }
        case .detail(let id):
            TVFlightDetailView(flightID: id, model: model, settings: settings, logbook: logbook) { presented = nil }
        case .aircraft:
            TVAircraftListView(model: model, heading: settings.tvFacingDegrees) { id in
                // A pinned aircraft still on the ground isn't on the radar yet.
                if model.contact(id: id) != nil {
                    withAnimation(.snappy) { model.focus(on: id) }
                }
                presented = nil
            }
        case .logbook:
            TVLogbookView(logbook: logbook, showTopography: settings.showTopography, showPhotos: settings.showPhotos,
                          isLive: { model.contact(id: $0) != nil }) { id in
                withAnimation(.snappy) { model.focus(on: id) }
                presented = nil
            }
            .preferredColorScheme(settings.appearance.colorScheme)
        case .tour:
            TVOnboardingView(hasLocation: observerCoordinate != nil,
                             placeName: settings.locationMode == .custom ? settings.customPlaceName : "this Apple TV's location",
                             showTopography: settings.showTopography, onExit: finishTour)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }

    /// The feed must reach past the map's ring too when the map's range is the wider one
    /// (the same margin the radar's own query gets).
    private var mapQueryFloor: Double {
        settings.mapView ? settings.effectiveMapRadius * 1.5 + 3 : 0
    }

    /// The map's ring, so the model keeps trails as far out as the map draws them.
    private var mapTrailFloor: Double {
        settings.mapView ? settings.effectiveMapRadius : 0
    }

    private var keepsScreenAwake: Bool { settings.keepScreenAwake && scenePhase == .active }

    /// Banner always; spoken too when "Speak alerts" is on, with the aircraft pulsing purple
    /// on the radar and map while it's read out.
    private func announce(_ alert: TrafficAlert) {
        model.post(notice: alert.title, symbol: alert.symbol)
        guard settings.spokenAlerts, let contact = model.contact(id: alert.flightID) else { return }
        AlertSpeaker.shared.speak(SpokenTraffic.sentence(for: contact, reason: alert.reason), about: contact.id)
    }

    /// The aircraft being read out takes over the centre as its sentence starts, and stays
    /// there like any focus: until it leaves the radius or the remote moves on.
    private func followAnnouncement(_ id: String?) {
        guard let id, model.contacts.contains(where: { $0.id == id }), model.focus.focusedID != id else { return }
        withAnimation(.snappy) { model.focus(on: id) }
    }

    private func showFlight(_ id: String) {
        guard model.contact(id: id) != nil else {
            model.post(notice: "That aircraft has left the area", symbol: "airplane.departure")
            return
        }
        withAnimation(.snappy) { model.focus(on: id) }
        presented = .detail(id)
    }

    /// Shares what the radar sees with the Top Shelf, refreshing it every few minutes.
    private func publishTopShelf() {
        guard !settings.demoTraffic else { return }
        let store = SharedRadarStore()
        store.snapshot = RadarSnapshot(placeName: settings.customPlaceName, radiusMiles: settings.radiusMiles, contacts: model.contacts)
        if Date().timeIntervalSince(lastTopShelfRefresh) > 300 {
            lastTopShelfRefresh = Date()
            TVTopShelfContentProvider.topShelfContentDidChange()
        }
    }

    // MARK: iPhone hand-off

    private func apply(_ payload: TVLink.Payload) {
        let coordinate = CLLocationCoordinate2D(latitude: payload.latitude, longitude: payload.longitude)
        settings.customCoordinate = coordinate
        settings.locationMode = .custom
        if let facing = payload.facingDegrees {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
                settings.tvFacingDegrees = GeoMath.normalize(facing)
            }
            model.post(notice: "iPhone set location · TV faces \(Int(facing.rounded()) % 360)° \(GeoMath.cardinal(facing))",
                       symbol: "iphone.radiowaves.left.and.right")
        } else {
            model.post(notice: "Location received from iPhone", symbol: "iphone.radiowaves.left.and.right")
        }
        placeLookup?.cancel()
        placeLookup = Task {
            let name = await PlaceServices.name(for: coordinate)
            guard !Task.isCancelled else { return }
            settings.customPlaceName = name
        }
    }

    // MARK: State

    private var observerCoordinate: CLLocationCoordinate2D? {
        switch settings.locationMode {
        case .custom: return settings.customCoordinate
        case .device: return tvLocation.coordinate ?? settings.customCoordinate
        }
    }

    /// What `syncObserver` and the logbook's place name depend on, as one value to watch.
    private var observerKey: ObserverKey {
        ObserverKey(latitude: observerCoordinate?.latitude, longitude: observerCoordinate?.longitude,
                    placeName: settings.customPlaceName, mode: settings.locationMode)
    }

    private struct ObserverKey: Equatable {
        let latitude: Double?
        let longitude: Double?
        let placeName: String?
        let mode: RadarSettings.LocationMode
    }

    private var centerState: CenterStateView.Kind? {
        if model.observer == nil {
            return tvLocation.isLocating ? .scanning : .needsLocation(denied: false)
        }
        if model.focusedContact != nil { return nil }
        switch model.status {
        case .error(let message) where !model.hasLoadedOnce:
            return .error(message)
        case .idle, .loading:
            return .scanning
        default:
            return model.hasLoadedOnce ? .clearSkies(radius: settings.radiusMiles) : .scanning
        }
    }

    private func centerPrimary() {
        switch centerState {
        case .needsLocation:
            presented = .settings(.location)
        case .clearSkies(let radius):
            settings.radiusMiles = min(RadarSettings.radiusRange.upperBound, radius * 2)
        case .error:
            model.refreshNow()
        case .scanning, .none:
            break
        }
    }

    private func centerSecondary() {
        if case .needsLocation = centerState { startDemo() }
    }

    private func startDemo() {
        settings.demoTraffic = true
        if observerCoordinate == nil {
            // Demo traffic needs somewhere to fly: default to Atlanta until set up properly.
            settings.customCoordinate = CLLocationCoordinate2D(latitude: 33.749, longitude: -84.388)
            settings.customPlaceName = "Atlanta, GA (demo)"
            settings.locationMode = .custom
        }
    }

    // MARK: Tour

    private func finishTour(_ exit: TVOnboardingView.Exit) {
        settings.hasSeenWelcome = true
        switch exit {
        case .start: presented = nil
        case .setLocation: present(.settings(.location))
        case .demo:
            startDemo()
            presented = nil
        }
    }

    /// Swaps one full-screen cover for another once the first has gone: tvOS drops a cover
    /// asked for while the last one is still on its way out (Settings → Take the tour did
    /// nothing when this waited a fixed half second).
    private func present(_ item: Presented) {
        guard presented != nil else {
            presented = item
            return
        }
        queued = item
        presented = nil
    }

    private func presentQueued() {
        guard let next = queued else { return }
        queued = nil
        presented = next
    }

    private func syncObserver() {
        model.setObserver(observerCoordinate)
        let store = SharedRadarStore()
        store.observer = observerCoordinate
        store.placeName = settings.customPlaceName
        store.radiusMiles = settings.radiusMiles
    }

    /// "Atlanta, GA" on sightings, when the set place doesn't already carry a name.
    private func nameLoggingPlace() async {
        model.logPlaceName = nil
        guard settings.customPlaceName == nil || settings.locationMode == .device, let here = observerCoordinate else { return }
        let name = await placeNamer.name(for: here)
        guard !Task.isCancelled, let name else { return }
        model.logPlaceName = name
    }

    /// Pins and favourites follow you between devices through iCloud (`PinSync`,
    /// `FavoriteSync`).
    private func startPinSync() {
        guard pinSync == nil else { return }
        let sync = PinSync(settings: settings)
        sync.onRemoteChange = { model.pinsDidChangeElsewhere(arrived: $0) }
        sync.start()
        pinSync = sync
        let favorites = FavoriteSync(settings: settings)
        favorites.start()
        favoriteSync = favorites
    }

    private func updateLogbookSync() {
        if settings.syncLogbook {
            if logbookSync == nil { logbookSync = LogbookSync(logbook: logbook) }
            logbookSync?.start()
        } else {
            logbookSync?.stop()
        }
    }

    #if DEBUG
    /// `-wtf.debugScreen settings|detail|aircraft|logbook|tour` and `-wtf.debugPane radar|display|about` for screenshots.
    private func openDebugScreenIfRequested() {
        let defaults = UserDefaults.standard
        guard let screen = defaults.string(forKey: "wtf.debugScreen") else { return }
        let pane = TVSettingsPane(rawValue: defaults.string(forKey: "wtf.debugPane") ?? "") ?? .location
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            switch screen {
            case "settings": presented = .settings(pane)
            case "aircraft": presented = .aircraft
            case "logbook": presented = .logbook
            case "tour": presented = .tour
            case "detail": if let id = model.focus.focusedID { presented = .detail(id) }
            default: break
            }
        }
    }
    #endif
}
#endif
