//
//  RadarRootView.swift
//  WhatTheFlight
//
//  Owns the app's state objects and wires location, settings and lifecycle into the model.
//

#if os(iOS)
import SwiftUI
import UIKit
import WidgetKit
import UserNotifications

struct RadarRootView: View {
    @State private var settings: RadarSettings
    @State private var model: RadarModel
    @State private var location = RadarLocationService()
    @State private var logbook = Logbook(device: .current)
    @State private var logbookSync: LogbookSync?
    @State private var pinSync: PinSync?
    @State private var placeNamer = PlaceNamer()
    @State private var raise = RaiseToSkyDetector()
    @State private var widgets = WidgetPublisher()
    @State private var sheet: Sheet?
    @State private var sky: SkyRequest?
    /// A deep link that arrived before the first feed load (e.g. tapped from a widget).
    @State private var deferredRoute: AppRouter.Route?
    /// `-wtf.debugLargeSheet YES` opens the detail sheet full height (screenshots).
    @State private var detailDetent: PresentationDetent = UserDefaults.standard.bool(forKey: "wtf.debugLargeSheet") ? .large : .medium

    private let router = AppRouter.shared
    private let skyWatch = SkyWatch.shared
    private let watchLink = PhoneWatchLink.shared

    /// iPad: the direction the map pane turns to, following the compass in steps.
    @State private var mapHeading: Double?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    enum Sheet: Identifiable, Equatable {
        case settings, search, welcome, pickSpot, tvLink, logbook, appIcon
        case detail(String)

        var id: String {
            switch self {
            case .settings: return "settings"
            case .search: return "search"
            case .welcome: return "welcome"
            case .pickSpot: return "pickSpot"
            case .tvLink: return "tvLink"
            case .logbook: return "logbook"
            case .appIcon: return "appIcon"
            case .detail(let id): return "detail-\(id)"
            }
        }
    }

    init() {
        let settings = RadarSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: RadarModel(settings: settings))
    }

    var body: some View {
        GeometryReader { geo in
            let showsMap = showsMapPane(in: geo.size)
            HStack(spacing: 0) {
                RadarScreen(
                    model: model,
                    settings: settings,
                    location: location,
                    centerState: centerState,
                    actions: .init(
                        openSettings: { sheet = .settings },
                        openSearch: { sheet = .search },  // even with an empty sky: search reaches the whole world
                        openDetail: { sheet = .detail($0) },
                        openLogbook: { sheet = .logbook },
                        openSpotPicker: { sheet = .pickSpot },
                        centerPrimary: centerPrimary,
                        centerSecondary: { sheet = .pickSpot }
                    )
                )
                // Square-ish beside the map: as wide as the screen is tall.
                .frame(width: showsMap ? geo.size.height : nil)

                if showsMap, let observer = model.observer {
                    TrafficMap(
                        observer: observer,
                        radiusMiles: settings.radiusMiles,
                        contacts: model.contacts,
                        fringe: model.outsideContacts,
                        focused: model.focusedContact,
                        isPinned: model.focus.isPinned,
                        pinnedIDs: model.pinnedIDs,
                        trail: model.trail(for:),
                        trailVersion: model.trailVersion,
                        headingUp: settings.mapNorthUp ? nil : mapHeading,
                        options: .init(interactive: true),
                        onTap: { id in withAnimation(.snappy) { model.focus(on: id) } }
                    )
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(\.radarObserver, model.observer)
        }
        .fullScreenCover(item: $sky) { request in
            SkyView(model: model, settings: settings, location: location, request: request,
                    onClose: { sky = nil },
                    onDetail: { id in
                        sky = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sheet = .detail(id) }
                    })
        }
        .onAppear {
            model.logbook = logbook
            updateLogbookSync()
            startPinSync()
            model.onAlert = deliver
            skyWatch.location = location
            skyWatch.endOrphanedActivities()
            raise.onRaise = { if sky == nil && sheet == nil { sky = SkyRequest(byRaise: true) } }
            watchLink.onStartSkyWatch = startSkyWatchForWatch
            watchLink.activate()
            location.start()
            model.start()
            syncObserver()
            if !settings.hasSeenWelcome {
                sheet = .welcome
            } else {
                location.requestPermission()
            }
            updateIdleTimer()
            #if DEBUG
            openDebugSheetIfRequested()
            model.debugPinIfRequested()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                location.start()
                model.start()
                model.refreshNow()
                logbookSync?.fetchNow()
                pinSync?.refresh()
            case .background:
                logbook.flush()
                // Sky Watch keeps the radar (and its alerts) running while the phone is locked.
                if !skyWatch.isActive {
                    model.stop()
                    location.stop()
                }
            default:
                break
            }
            updateIdleTimer()
            updateRaiseDetector()
        }
        .onChange(of: sheet) { _, _ in updateRaiseDetector() }
        .onChange(of: sky) { _, _ in updateRaiseDetector() }
        .onChange(of: settings.raiseToSkyView) { _, _ in updateRaiseDetector() }
        .onChange(of: model.lastUpdated) { _, _ in widgets.publish(model: model, settings: settings, placeName: placeName) }
        .onChange(of: model.now) { _, _ in skyWatch.update(contacts: model.contacts) }
        .onChange(of: model.hasLoadedOnce) { _, loaded in
            if loaded, let route = deferredRoute {
                deferredRoute = nil
                handle(route)
            }
        }
        .onOpenURL { router.open($0) }
        .onContinueUserActivity(WatchSync.handoffActivityType) { activity in
            if let id = activity.userInfo?[WatchSync.handoffFlightKey] as? String { router.pending = .flight(id) }
        }
        .onChange(of: router.pending, initial: true) { _, route in
            guard let route else { return }
            router.pending = nil
            handle(route)
        }
        .onChange(of: location.heading) { _, heading in followHeading(heading) }
        .onChange(of: location.location) { _, _ in syncObserver() }
        .onChange(of: settings.locationMode) { _, _ in syncObserver() }
        .onChange(of: settings.customLatitude) { _, _ in syncObserver() }
        .onChange(of: settings.customLongitude) { _, _ in syncObserver() }
        .onChange(of: settings.showHelicopters) { _, _ in
            model.settingsDidChange(refetch: false)
            sendWatchContext()
        }
        .onChange(of: settings.alertRules) { _, _ in sendWatchContext() }
        .onChange(of: settings.demoTraffic) { _, _ in model.settingsDidChange(refetch: true) }
        .onChange(of: settings.keepScreenAwake) { _, _ in updateIdleTimer() }
        .onChange(of: settings.syncLogbook) { _, _ in updateLogbookSync() }
        .task(id: settings.radiusMiles) {
            // Re-filter instantly while the slider moves; re-query once it settles.
            model.settingsDidChange(refetch: false)
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            model.settingsDidChange(refetch: true)
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .settings:
            RadarSettingsSheet(settings: settings, location: location, model: model, logbook: logbook,
                               placeName: placeName, onTrack: track) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.sheet = .welcome }
            }
            .presentationDragIndicator(.visible)
        case .search:
            FlightSearchSheet(model: model, heading: location.heading ?? 0) {
                self.sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.sheet = .logbook }
            }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        case .detail(let id):
            FlightDetailSheet(flightID: id, model: model, settings: settings, logbook: logbook) { id in
                self.sheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sky = SkyRequest(targetID: id) }
            }
            .presentationDetents([.medium, .large], selection: $detailDetent)
            .presentationDragIndicator(.visible)
        case .logbook:
            NavigationStack {
                LogbookView(logbook: logbook, onTrack: track, isLive: { model.contact(id: $0) != nil })
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { self.sheet = nil }.font(.mono(15, .semibold))
                        }
                    }
            }
        case .welcome:
            OnboardingView(
                onStart: {
                    settings.hasSeenWelcome = true
                    location.requestPermission()
                    self.sheet = nil
                },
                onDemo: {
                    settings.hasSeenWelcome = true
                    settings.demoTraffic = true
                    location.requestPermission()
                    self.sheet = nil
                }
            )
        case .tvLink:
            NavigationStack {
                TVLinkSetupView(settings: settings, location: location)
            }
        case .appIcon:
            NavigationStack {
                AppIconPickerView()
            }
        case .pickSpot:
            NavigationStack {
                LocationPickerView(settings: settings, location: location)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { self.sheet = nil }
                        }
                    }
            }
        }
    }

    // MARK: Map pane

    /// iPad in landscape at full width, with Map view on. Portrait, Split View and iPhone keep
    /// the radar alone.
    private func showsMapPane(in size: CGSize) -> Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
            && size.width > size.height && settings.mapView && model.observer != nil
    }

    /// The map turns with the iPad, but only once the heading has moved 10°, so compass
    /// jitter doesn't keep it rocking.
    private func followHeading(_ heading: Double?) {
        guard let heading else { return }
        if let current = mapHeading, abs(GeoMath.shortestDelta(from: current, to: heading)) < 10 { return }
        mapHeading = GeoMath.normalize((heading / 5).rounded() * 5)
    }

    // MARK: State

    private var observerCoordinate: CLLocationCoordinate2D? {
        switch settings.locationMode {
        case .custom: return settings.customCoordinate ?? location.location?.coordinate
        case .device: return location.location?.coordinate
        }
    }

    private var centerState: CenterStateView.Kind? {
        if model.observer == nil {
            if settings.locationMode == .device && location.isAuthorized {
                return .scanning
            }
            return .needsLocation(denied: location.isDenied)
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
        case .needsLocation(let denied):
            if denied {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } else {
                settings.locationMode = .device
                location.requestPermission()
            }
        case .clearSkies(let radius):
            settings.radiusMiles = min(RadarSettings.radiusRange.upperBound, radius * 2)
        case .error:
            model.refreshNow()
        case .scanning, .none:
            break
        }
    }

    private func syncObserver() {
        model.setObserver(observerCoordinate)
        nameLoggingPlace()
        let store = SharedRadarStore()
        store.observer = observerCoordinate
        store.placeName = placeName
        store.radiusMiles = settings.radiusMiles
        sendWatchContext()
    }

    /// "Atlanta, GA" on sightings logged from where you really are. A custom spot isn't logged.
    private func nameLoggingPlace() {
        guard settings.locationMode == .device, let here = location.location?.coordinate else { return }
        Task {
            if let name = await placeNamer.name(for: here) { model.logPlaceName = name }
        }
    }

    /// Pins follow you between devices through iCloud (`PinSync`).
    private func startPinSync() {
        guard pinSync == nil else { return }
        let sync = PinSync(settings: settings)
        sync.onRemoteChange = { model.pinsDidChangeElsewhere(arrived: $0) }
        sync.start()
        pinSync = sync
    }

    private func updateLogbookSync() {
        if settings.syncLogbook {
            if logbookSync == nil { logbookSync = LogbookSync(logbook: logbook) }
            logbookSync?.start()
        } else {
            logbookSync?.stop()
        }
    }

    /// Tells Apple Watch where the iPhone is watching (for its "iPhone's spot" mode) and the
    /// preferences both share. The Watch keeps its own radius.
    private func sendWatchContext() {
        // ~100 m is plenty for "what's over my iPhone's spot", and keeps GPS jitter off the link.
        func rounded(_ value: Double?) -> Double? { value.map { ($0 * 1000).rounded() / 1000 } }
        let observer = observerCoordinate
        watchLink.send(WatchSync.Context(
            latitude: rounded(observer?.latitude), longitude: rounded(observer?.longitude),
            placeName: settings.locationMode == .custom ? placeName : nil,
            showHelicopters: settings.showHelicopters,
            overheadAlerts: settings.overheadAlerts, overheadAlertMiles: settings.overheadAlertMiles,
            notableAlerts: settings.notableAlerts, sentAt: Date()
        ))
    }

    /// "Start Sky Watch" from the Watch. iOS only starts Live Activities from the foreground.
    private func startSkyWatchForWatch() async -> WatchSync.Reply {
        if skyWatch.isActive {
            return WatchSync.Reply(ok: true, message: "Sky Watch is already on.")
        }
        guard UIApplication.shared.applicationState == .active else {
            return WatchSync.Reply(ok: false, message: "Open What The Flight? on your iPhone to start Sky Watch. iOS only allows it while the app is open.")
        }
        await skyWatch.start(placeName: placeName, radiusMiles: settings.radiusMiles, contacts: model.contacts)
        guard skyWatch.isActive else {
            return WatchSync.Reply(ok: false, message: skyWatch.problem ?? "Sky Watch couldn't start.")
        }
        model.post(notice: "Sky Watch started from Apple Watch", symbol: "applewatch")
        return WatchSync.Reply(ok: true, message: "Sky Watch is on. Alerts will tap your wrist while your iPhone is locked.")
    }

    /// "Atlanta, GA" for a custom spot, "My location" otherwise.
    private var placeName: String {
        switch settings.locationMode {
        case .custom: return settings.customPlaceName ?? "Custom spot"
        case .device: return "My location"
        }
    }

    // MARK: Routing, alerts, Sky View

    private func handle(_ route: AppRouter.Route) {
        switch route {
        case .flight(let id):
            sky = nil
            if model.contact(id: id) != nil {
                model.focus(on: id)
                sheet = .detail(id)
            } else if !model.hasLoadedOnce {
                deferredRoute = route
            } else {
                sheet = nil
                model.post(notice: "That aircraft has left the area", symbol: "airplane.departure")
            }
        case .find(let id):
            if model.contact(id: id) != nil {
                sheet = nil
                model.focus(on: id)
                sky = SkyRequest(targetID: id)
            } else if !model.hasLoadedOnce {
                deferredRoute = route
            } else {
                model.post(notice: "That aircraft has left the area", symbol: "airplane.departure")
            }
        case .sky:
            sheet = nil
            sky = SkyRequest()
        case .logbook:
            sky = nil
            sheet = .logbook
        case .radar:
            sky = nil
            sheet = nil
        case .startSkyWatch:
            sky = nil
            sheet = nil
            Task {
                await skyWatch.start(placeName: placeName, radiusMiles: settings.radiusMiles, contacts: model.contacts)
                if let problem = skyWatch.problem {
                    model.post(notice: problem, symbol: "exclamationmark.triangle")
                } else {
                    model.post(notice: "Sky Watch is on — lock your phone and keep an eye on the Lock Screen", symbol: "dot.radiowaves.left.and.right")
                }
            }
        }
    }

    private func track(_ id: String) {
        withAnimation(.snappy) { model.focus(on: id) }
        sheet = nil
    }

    /// Banner while the app is on screen; a notification while it runs in the background.
    private func deliver(_ alert: TrafficAlert) {
        if UIApplication.shared.applicationState == .active {
            model.post(notice: alert.title, symbol: alert.symbol)
        } else {
            AlertNotifier.deliver(alert)
        }
    }

    private func updateRaiseDetector() {
        let listening = scenePhase == .active && settings.raiseToSkyView && sheet == nil && sky == nil
        if listening { raise.start() } else { raise.stop() }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake && scenePhase == .active
    }

    #if DEBUG
    /// `-wtf.debugSheet settings|search|detail|welcome|tvlink|logbook|sky` opens a sheet at launch and
    /// `-wtf.debugFocus DL570` focuses a flight (screenshots, UI tests).
    private func openDebugSheetIfRequested() {
        let defaults = UserDefaults.standard
        // `-wtf.debugIcon <choice>` switches the Home Screen icon (e.g. `edgeRadar`, `automatic`).
        if let raw = defaults.string(forKey: "wtf.debugIcon"), let choice = AppIconChoice(rawValue: raw) {
            Task { @MainActor in
                // iOS only changes the icon once the app is on screen.
                try? await Task.sleep(for: .seconds(2))
                do { try await choice.apply() } catch { print("debugIcon:", error) }
            }
        }
        let focusName = defaults.string(forKey: "wtf.debugFocus")
        let name = defaults.string(forKey: "wtf.debugSheet")
        guard focusName != nil || name != nil else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            if let focusName, let hit = model.allContacts.first(where: { $0.flight.displayIdentifier == focusName }) {
                model.focus(on: hit.id)
                if !model.focus.isPinned { model.togglePin() }
            }
            switch name {
            case "settings": sheet = .settings
            case "search": sheet = .search
            case "logbook": sheet = .logbook
            case "sky": sky = SkyRequest(targetID: defaults.bool(forKey: "wtf.debugFind") ? model.focus.focusedID : nil)
            case "welcome": sheet = .welcome
            case "tvlink": sheet = .tvLink
            case "appicon": sheet = .appIcon
            case "detail": if let id = model.focus.focusedID { sheet = .detail(id) }
            default: break
            }
        }
    }
    #endif
}

/// Keeps the widgets' snapshot fresh without asking WidgetKit to reload on every poll.
@MainActor
final class WidgetPublisher {
    private var lastReload = Date.distantPast
    private var lastNearest: String?

    func publish(model: RadarModel, settings: RadarSettings, placeName: String) {
        guard !settings.demoTraffic else { return }
        let store = SharedRadarStore()
        store.snapshot = RadarSnapshot(placeName: placeName, radiusMiles: settings.radiusMiles, contacts: model.contacts)
        let nearest = model.contacts.first?.id
        let elapsed = Date().timeIntervalSince(lastReload)
        if (nearest != lastNearest && elapsed > 60) || elapsed > 300 {
            lastReload = Date()
            lastNearest = nearest
            WidgetCenter.shared.reloadTimelines(ofKind: SharedRadarStore.widgetKind)
        }
    }
}

/// iPhone stays in portrait — the radar is a compass, and a compass doesn't rotate.
final class RadarAppDelegate: NSObject, UIApplicationDelegate {
    private let notifications = AlertNotificationDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notifications
        UNUserNotificationCenter.current().setNotificationCategories([AlertNotifier.trafficCategory])
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .phone ? .portrait : .all
    }
}
#endif
