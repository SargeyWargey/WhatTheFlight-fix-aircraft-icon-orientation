//
//  WatchRootView.swift
//  WhatTheFlightWatch
//
//  Owns the Watch's state and wires location, the iPhone link and the wrist (scene phase)
//  into the same `RadarModel` the iPhone and Apple TV use. The top level is three vertical
//  pages: Settings above the radar, the Nearby list below it.
//

import SwiftUI
import WidgetKit
import CoreLocation

struct WatchRootView: View {
    enum Page: Hashable {
        case settings, radar, nearby
    }

    enum Screen: Hashable {
        case detail(String)
        /// Guide the arm to this aircraft.
        case find(String)
        /// "What am I pointing at?"
        case identify
        case nearby
    }

    @State private var settings: RadarSettings
    @State private var watchSettings = WatchSettings()
    @State private var model: RadarModel
    @State private var location = WatchLocationService()
    @State private var page: Page = .radar
    @State private var path: [Screen] = []
    @State private var complications = ComplicationPublisher()
    /// First run: the tour, before the location prompt.
    @State private var showTour = false
    /// A route that arrived before the first feed load (e.g. from a complication).
    @State private var deferredRoute: WatchRouter.Route?
    #if DEBUG
    @State private var debugNotification: SnapshotFlight?
    #endif

    private let router = WatchRouter.shared
    private let link = WatchPhoneLink.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = RadarSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: RadarModel(settings: settings))
    }

    var body: some View {
        NavigationStack(path: $path) {
            TabView(selection: $page) {
                WatchSettingsView(settings: settings, watchSettings: watchSettings, location: location, link: link,
                                  nearbyCount: model.contacts.count, open: { path.append($0) }, close: backToRadar,
                                  showTour: { showTour = true })
                    .tag(Page.settings)
                WatchRadarView(model: model, settings: settings, watchSettings: watchSettings, location: location,
                               centerState: centerState, isActive: page == .radar && path.isEmpty,
                               open: { path.append($0) }, retry: centerAction)
                    .tag(Page.radar)
                WatchNearbyList(model: model, settings: settings, location: location, watchSettings: watchSettings,
                                open: { path.append($0) }, close: backToRadar)
                    .tag(Page.nearby)
            }
            .tabViewStyle(.verticalPage)
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .detail(let id):
                    WatchFlightDetail(flightID: id, model: model, settings: settings, watchSettings: watchSettings,
                                      location: location, open: { path.append($0) })
                case .find(let id):
                    PointAndFindView(model: model, settings: settings, watchSettings: watchSettings,
                                     location: location, initialTargetID: id)
                case .identify:
                    IdentifyView(model: model, settings: settings, watchSettings: watchSettings,
                                 location: location, open: { path.append($0) })
                case .nearby:
                    WatchNearbyList(model: model, settings: settings, location: location, watchSettings: watchSettings,
                                    open: { path.append($0) })
                }
            }
        }
        .fullScreenCover(isPresented: $showTour) {
            WatchTourView(settings: settings, watchSettings: watchSettings,
                          onDone: { finishTour(thenIdentify: false) },
                          onTryIdentify: { finishTour(thenIdentify: true) })
        }
        #if DEBUG
        .sheet(item: $debugNotification) { flight in
            ScrollView {
                TrafficNotificationView(title: "", message: "", flight: flight, postedAt: Date())
            }
        }
        #endif
        .onAppear {
            // A tap on the wrist only: the screen is too small for a banner over the radar.
            model.onAlert = { alert in
                WatchHaptics.play(for: alert, enabled: settings.hapticsEnabled)
            }
            link.onContext = { context in
                watchSettings.apply(context, to: settings)
                syncObserver()
                model.settingsDidChange(refetch: false)
            }
            link.activate()
            // Identify names anything you can see within 15 mi, whatever the radar's radius.
            model.queryRadiusFloor = WristPointing.identifyRangeMiles + 1
            if watchSettings.hasSeenTour {
                location.requestPermission()
            } else {
                showTour = true
            }
            location.start()
            model.start()
            syncObserver()
            #if DEBUG
            openDebugScreenIfRequested()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                location.start()
                model.start()
                model.refreshNow()
            case .inactive:
                // Pointing at the sky can look like "wrist down" to watchOS: keep tracking.
                guard !isPointing else { break }
                // Wrist down (Always-On): stop polling and GPS; the clock keeps the icons moving.
                model.stop()
                location.stop()
            case .background:
                model.stop()
                location.stop()
                complications.publish(model: model, settings: settings, placeName: placeName, force: true)
            @unknown default:
                break
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .inactive, !isPointing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                model.advanceClock()
            }
        }
        .onChange(of: model.lastUpdated) { _, _ in
            complications.publish(model: model, settings: settings, placeName: placeName)
        }
        .onChange(of: model.hasLoadedOnce) { _, loaded in
            if loaded, let route = deferredRoute {
                deferredRoute = nil
                handle(route)
            }
        }
        .onOpenURL { router.open($0) }
        .onChange(of: router.pending, initial: true) { _, route in
            guard let route else { return }
            router.pending = nil
            handle(route)
        }
        .onChange(of: location.location) { _, _ in syncObserver() }
        .onChange(of: watchSettings.locationSource) { _, _ in syncObserver() }
        .onChange(of: settings.showHelicopters) { _, _ in model.settingsDidChange(refetch: false) }
        .onChange(of: settings.demoTraffic) { _, _ in model.settingsDidChange(refetch: true) }
        .task(id: settings.radiusMiles) {
            model.settingsDidChange(refetch: false)
            SharedRadarStore().radiusMiles = settings.radiusMiles
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            model.settingsDidChange(refetch: true)
        }
    }

    // MARK: State

    /// In Identify or Find: the sensors and the radar keep running when the screen dims.
    private var isPointing: Bool {
        switch path.last {
        case .find, .identify: return true
        default: return false
        }
    }

    private var observerCoordinate: CLLocationCoordinate2D? {
        switch watchSettings.locationSource {
        case .here: return location.location?.coordinate
        case .phone: return watchSettings.phoneObserver ?? location.location?.coordinate
        }
    }

    private var placeName: String {
        switch watchSettings.locationSource {
        case .here: return "Here"
        case .phone: return watchSettings.phonePlaceName ?? "iPhone's spot"
        }
    }

    private var centerState: WatchCenterState.Kind? {
        if model.observer == nil {
            if watchSettings.locationSource == .phone && watchSettings.phoneObserver == nil {
                return .noPhoneSpot
            }
            return location.isAuthorized ? .scanning : .needsLocation(denied: location.isDenied)
        }
        if model.focusedContact != nil { return nil }
        switch model.status {
        case .error(let message) where !model.hasLoadedOnce: return .error(message)
        case .idle, .loading: return .scanning
        default: return model.hasLoadedOnce ? .clearSkies(radius: settings.radiusMiles) : .scanning
        }
    }

    private func finishTour(thenIdentify: Bool) {
        watchSettings.hasSeenTour = true
        showTour = false
        location.requestPermission()
        page = .radar
        if thenIdentify {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                path = [.identify]
            }
        }
    }

    private func backToRadar() {
        withAnimation { page = .radar }
    }

    private func centerAction() {
        switch centerState {
        case .needsLocation: location.requestPermission()
        case .noPhoneSpot: watchSettings.locationSource = .here
        case .error: model.refreshNow()
        default: break
        }
    }

    private func syncObserver() {
        let observer = observerCoordinate
        model.setObserver(observer)
        // Complications and Siri on the Watch read these.
        let store = SharedRadarStore()
        store.observer = observer
        store.placeName = placeName
        store.radiusMiles = settings.radiusMiles
    }

    private func handle(_ route: WatchRouter.Route) {
        switch route {
        case .radar:
            path = []
            page = .radar
        case .flight(let id):
            if model.contact(id: id) != nil {
                model.focus(on: id)
                path = [.detail(id)]
            } else if !model.hasLoadedOnce {
                deferredRoute = route
            } else {
                // It has left the area: the radar shows what's here now.
                path = []
                page = .radar
            }
        case .find(let id):
            if model.contact(id: id) != nil {
                model.focus(on: id)
                path = [.find(id)]
            } else if !model.hasLoadedOnce {
                deferredRoute = route
            } else {
                // It has left the area: Identify still names whatever you point at.
                path = [.identify]
            }
        case .identify:
            path = [.identify]
        }
    }

    #if DEBUG
    /// `-wtf.debugScreen detail|find|identify|nearby|settings|notification` and `-wtf.debugFocus <flight>` (screenshots).
    private func openDebugScreenIfRequested() {
        let defaults = UserDefaults.standard
        let focusName = defaults.string(forKey: "wtf.debugFocus")
        let name = defaults.string(forKey: "wtf.debugScreen")
        guard focusName != nil || name != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if let focusName, let hit = model.allContacts.first(where: { $0.flight.displayIdentifier == focusName }) {
                model.focus(on: hit.id)
            }
            let id = model.focus.focusedID
            switch name {
            case "detail": if let id { path = [.detail(id)] }
            case "find": if let id { path = [.find(id)] }
            case "identify": path = [.identify]
            case "nearby": page = .nearby
            case "settings": page = .settings
            case "notification": debugNotification = (id.flatMap(model.contact(id:)) ?? model.contacts.first).map(SnapshotFlight.init)
            default: break
            }
        }
    }
    #endif
}

/// Keeps the complications' snapshot fresh without asking WidgetKit to reload on every poll.
@MainActor
final class ComplicationPublisher {
    private var lastReload = Date.distantPast
    private var lastNearest: String?

    func publish(model: RadarModel, settings: RadarSettings, placeName: String, force: Bool = false) {
        guard !settings.demoTraffic, model.hasLoadedOnce else { return }
        let store = SharedRadarStore()
        store.snapshot = RadarSnapshot(placeName: placeName, radiusMiles: settings.radiusMiles, contacts: model.contacts)
        let nearest = model.contacts.first?.id
        let elapsed = Date().timeIntervalSince(lastReload)
        if (force && elapsed > 60) || (nearest != lastNearest && elapsed > 120) || elapsed > 600 {
            lastReload = Date()
            lastNearest = nearest
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
