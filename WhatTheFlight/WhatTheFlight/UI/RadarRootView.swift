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
import CoreSpotlight

struct RadarRootView: View {
    @State private var settings: RadarSettings
    @State private var model: RadarModel
    @LazyState private var location = RadarLocationService()
    @LazyState private var logbook = Logbook(device: .current)
    @State private var logbookSync: LogbookSync?
    @State private var pinSync: PinSync?
    @State private var favoriteSync: FavoriteSync?
    @LazyState private var placeNamer = PlaceNamer()
    @LazyState private var raise = RaiseToSkyDetector()
    @LazyState private var widgets = WidgetPublisher()
    @LazyState private var logbookWidgets = LogbookWidgetPublisher()
    @State private var sheet: Sheet?
    @State private var sky: SkyRequest?
    /// A deep link that arrived before the first feed load (e.g. tapped from a widget).
    @State private var deferredRoute: AppRouter.Route?
    /// A page the logbook opens on (Spotlight's airframe results, a widget's badge).
    @State private var logbookRoute: LogbookRoute?
    /// The tab it opens on (widgets).
    @State private var logbookTab: LogbookTab?
    /// `-wtf.debugLargeSheet YES` opens the detail and search sheets full height (screenshots).
    @State private var detailDetent: PresentationDetent = UserDefaults.standard.bool(forKey: "wtf.debugLargeSheet") ? .large : .medium
    /// Search opens full height from the bar's aircraft count.
    @State private var searchDetent: PresentationDetent = UserDefaults.standard.bool(forKey: "wtf.debugLargeSheet") ? .large : .medium

    private let router = AppRouter.shared
    private let skyWatch = SkyWatch.shared
    private let watchLink = PhoneWatchLink.shared

    /// The direction the map turns to (the pane, or the bar's map), following the compass in steps.
    @State private var mapHeading: Double?
    /// iPhone Duo: half open, the radar and the map get half the screen each.
    @LazyState private var fold = FoldMonitor()

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
            let view = screenView
            let panes = panes(in: geo, view: view)
            let nextView = nextView
            let rail = fold.verticalBar
            ZStack {
                PaneLayout(frames: panes.frames) {
                    RadarScreen(
                        model: model,
                        settings: settings,
                        location: location,
                        centerState: { centerState },
                        showsMap: view == .map,
                        nextView: nextView,
                        showsBar: rail == nil && panes.barInset == nil,
                        mapHeading: mapHeading,
                        actions: screenActions
                    )

                    if let gutter = panes.gutter {
                        FoldGutter(axis: gutter.width < gutter.height ? .vertical : .horizontal)
                            .ignoresSafeArea()
                    }

                    if panes.map != nil, let observer = model.observer {
                        RadarMapPane(model: model, settings: settings, observer: observer, mapHeading: mapHeading,
                                     cardInset: CGSize(width: 0, height: panes.barInset ?? 0))
                            .transition(.move(edge: panes.mapEdge).combined(with: .opacity))
                    }
                }

                if let rail {
                    controlRail(rail, nextView: nextView, geo: geo)
                } else if panes.barInset != nil {
                    screenBar(nextView: nextView, geo: geo)
                }
            }
        }
        .environment(\.topographyStyle, settings.topography)
        .environment(\.favoriteAircraft, settings.favoriteSet)
        .environment(\.skyVisibility, settings.showsVisibility ? SkyVisibilityLookup { model.visibility(of: $0) } : SkyVisibilityLookup())
        .background { FoldSensor(monitor: fold).ignoresSafeArea() }
        // The compass and the 1 Hz clock change many times a minute; watching them here keeps
        // the root (and any sheet over it) from re-evaluating with them.
        .background {
            ChangeObserver(value: { [location] in location.heading }) { followHeading($0) }
            ChangeObserver(value: { [model] in model.now }) { [model, skyWatch] _ in skyWatch.update(contacts: model.contacts) }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
        .sheet(item: sheetBinding) { sheet in
            sheetContent(sheet)
                .environment(\.radarObserver, model.observer)
                .environment(\.topographyStyle, settings.topography)
                .environment(\.isFoldable, fold.isFoldable)
                .environment(\.showsAircraftPhotos, settings.showPhotos)
                .environment(\.favoriteAircraft, settings.favoriteSet)
                .environment(\.toggleFavorite, FavoriteToggle { [model] in model.toggleFavorite($0) })
        }
        // At regular width (iPad, the Duo's inner screen) the logbook fills the screen.
        .fullScreenCover(isPresented: logbookCover) {
            LogbookView(logbook: logbook, onTrack: track, isLive: { model.contact(id: $0) != nil },
                        onDone: { self.sheet = nil }, initialRoute: logbookRoute, initialTab: logbookTab)
                .id([AnyHashable(logbookRoute), AnyHashable(logbookTab)])
                .environment(\.radarObserver, model.observer)
                .environment(\.topographyStyle, settings.topography)
                .environment(\.showsAircraftPhotos, settings.showPhotos)
                .environment(\.favoriteAircraft, settings.favoriteSet)
                .environment(\.toggleFavorite, FavoriteToggle { [model] in model.toggleFavorite($0) })
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
            LogbookAccess.live = logbook
            logbook.onBadgeUnlocked = { [model, logbookWidgets] badge in
                model.post(notice: badge.unlockNotice, symbol: badge.symbol)
                logbookWidgets.publishNow()
            }
            logbookWidgets.attach(logbook)
            startPinSync()
            model.onAlert = deliver
            skyWatch.location = location
            skyWatch.endOrphanedActivities()
            raise.onRaise = { if sky == nil && sheet == nil { sky = SkyRequest(byRaise: true) } }
            watchLink.onStartSkyWatch = startSkyWatchForWatch
            watchLink.activate()
            location.start()
            model.start()
            if !settings.hasSeenWelcome {
                sheet = .welcome
            } else {
                location.requestPermission()
            }
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
                favoriteSync?.refresh()
            case .background:
                logbook.flush()
                DigestNotifier.reschedule(logbook: logbook, settings: settings)
                LogbookSpotlight.reindex(logbook, enabled: settings.keepLogbook)
                logbookWidgets.publishNow()
                // Sky Watch keeps the radar (and its alerts) running while the phone is locked.
                if !skyWatch.isActive {
                    model.stop()
                    location.stop()
                }
            default:
                break
            }
        }
        .onChange(of: keepsScreenAwake, initial: true) { _, awake in UIApplication.shared.isIdleTimerDisabled = awake }
        .onChange(of: listensForRaise, initial: true) { _, listening in
            if listening { raise.start() } else { raise.stop() }
        }
        .onChange(of: fold.interfaceOrientations, initial: true) { _, turns in location.interfaceOrientations = turns }
        .onChange(of: model.lastUpdated) { _, _ in
            widgets.publish(model: model, settings: settings, placeName: placeName)
            FlightFollow.shared.update(from: model)
        }
        .onChange(of: model.hasLoadedOnce) { _, loaded in
            if loaded, let route = deferredRoute {
                deferredRoute = nil
                handle(route)
            }
        }
        .onOpenURL { router.open($0) }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
               let airframe = LogbookSpotlight.airframe(fromIdentifier: id) {
                router.pending = .airframe(airframe)
            }
        }
        .onContinueUserActivity(WatchSync.handoffActivityType) { activity in
            if let id = activity.userInfo?[WatchSync.handoffFlightKey] as? String { router.pending = .flight(id) }
        }
        .onChange(of: router.pending, initial: true) { _, route in
            guard let route else { return }
            router.pending = nil
            handle(route)
        }
        .onChange(of: observerKey, initial: true) { _, _ in syncObserver() }
        // Restarts only on moving to a new ~5 km square, so a slow lookup isn't cancelled by
        // every GPS fix; a stale one is.
        .task(id: loggingPlaceArea) { await nameLoggingPlace() }
        .task(id: weatherArea) { await refreshWeather() }
        .onChange(of: settings.preferVisible) { _, _ in model.settingsDidChange(refetch: false) }
        .onChange(of: settings.showHelicopters) { _, _ in
            model.settingsDidChange(refetch: false)
            sendWatchContext()
        }
        .onChange(of: settings.alertRules) { _, _ in sendWatchContext() }
        .onChange(of: settings.units) { _, _ in
            logbook.formattingDidChange()
            sendWatchContext()
            WidgetCenter.shared.reloadAllTimelines()
            logbookWidgets.publishNow()
        }
        .onChange(of: settings.demoTraffic) { _, _ in model.settingsDidChange(refetch: true) }
        .onChange(of: settings.dataSource) { _, _ in model.dataSourceDidChange() }
        // A Spotlight result opens the logbook on its page once; the next opening starts fresh.
        .onChange(of: sheet) { old, new in
            if old == .logbook, new != .logbook {
                logbookRoute = nil
                logbookTab = nil
            }
        }
        .onChange(of: settings.syncLogbook, initial: true) { _, _ in
            updateLogbookSync()
            sendWatchContext()
        }
        .onChange(of: settings.keepLogbook) { _, _ in sendWatchContext() }
        .task(id: settings.radiusMiles) {
            // Re-filter instantly while the slider moves; re-query once it settles.
            model.settingsDidChange(refetch: false)
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            model.settingsDidChange(refetch: true)
        }
    }

    // MARK: Sheets

    /// The logbook gets the whole screen at regular width.
    private var logbookFillsScreen: Bool { horizontalSizeClass == .regular }

    private var sheetBinding: Binding<Sheet?> {
        Binding(get: { sheet == .logbook && logbookFillsScreen ? nil : sheet }, set: { sheet = $0 })
    }

    private var logbookCover: Binding<Bool> {
        Binding(get: { sheet == .logbook && logbookFillsScreen }, set: { if !$0 && sheet == .logbook { sheet = nil } })
    }

    /// Aircraft search: aircraft nearby, a worldwide search and a Logbook button (the
    /// logbook itself opens from the bar or a swipe down).
    private func openSearch(detent: PresentationDetent) {
        searchDetent = detent
        sheet = .search
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .settings:
            RadarSettingsSheet(settings: settings, location: location, model: model, logbook: logbook,
                               placeName: placeName, openLogbook: {
                                   self.sheet = nil
                                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.sheet = .logbook }
                               }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { self.sheet = .welcome }
            }
            .presentationDragIndicator(.visible)
        case .search:
            FlightSearchSheet(model: model, heading: location.heading ?? 0)
                .presentationDetents([.medium, .large], selection: $searchDetent)
                .presentationDragIndicator(.visible)
        case .detail(let id):
            FlightDetailSheet(flightID: id, model: model, settings: settings, logbook: logbook,
                              onFindInSky: SkyViewSupport.isAvailable ? { id in
                                  self.sheet = nil
                                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { sky = SkyRequest(targetID: id) }
                              } : nil)
            .presentationDetents([.medium, .large], selection: $detailDetent)
            .presentationDragIndicator(.visible)
        case .logbook:
            LogbookView(logbook: logbook, onTrack: track, isLive: { model.contact(id: $0) != nil },
                        onDone: { self.sheet = nil }, initialRoute: logbookRoute, initialTab: logbookTab)
                .id([AnyHashable(logbookRoute), AnyHashable(logbookTab)])
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

    private var screenActions: RadarScreen.Actions {
        .init(
            openSettings: { sheet = .settings },
            openLogbook: { sheet = .logbook },
            openDetail: { sheet = .detail($0) },
            // Even with an empty sky: search reaches the whole world.
            openSearchFullHeight: { openSearch(detent: .large) },
            showNextView: showNextView,
            openSkyView: { sky = SkyRequest() },
            openSpotPicker: { sheet = .pickSpot },
            centerPrimary: centerPrimary,
            centerSecondary: { sheet = .pickSpot }
        )
    }

    // MARK: Rail

    /// iPhone Duo in landscape: the bar's buttons in the system's vertical bar strip, the way
    /// the system lays out its own bar there: round buttons from just under the status bar,
    /// a group at the bottom, sized from the strip's width. The strip is the safe area's inset
    /// on that side, so the radar and the map pane already keep out of it. Over the whole
    /// screen, so it stays at the far edge with the map pane beside the radar (held as a book).
    private func controlRail(_ bar: FoldMonitor.VerticalBar, nextView: RadarSettings.TVView?, geo: GeometryProxy) -> some View {
        let insets = geo.safeAreaInsets
        let rail = RadarControlBar.Rail(strip: bar.edge == .leading ? insets.leading : insets.trailing)
        let actions = screenActions
        return RadarControlBar(model: model, nextView: nextView,
                               rail: rail,
                               onNextView: actions.showNextView, onSkyView: actions.openSkyView,
                               onSearch: actions.openSearchFullHeight,
                               onLogbook: actions.openLogbook, onSettings: actions.openSettings)
            .padding(.top, bar.statusBarBottom ?? insets.top + rail.spacing)
            .padding(.bottom, rail.bottomMargin)
            .padding(bar.edge == .leading ? .leading : .trailing, rail.edgeMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: bar.edge == .leading ? .leading : .trailing)
            .ignoresSafeArea()
            .transition(.opacity)
    }

    /// iPad in portrait, split: the bar along the bottom of the whole screen, over the map,
    /// just where the radar or the map alone has it, so the view button stays put between taps.
    private func screenBar(nextView: RadarSettings.TVView?, geo: GeometryProxy) -> some View {
        let chrome = RadarChrome(size: geo.size, safeBottom: geo.safeAreaInsets.bottom, tagsHeight: 0)
        let actions = screenActions
        return RadarControlBar(model: model, nextView: nextView, stacksSplit: true,
                               onNextView: actions.showNextView, onSkyView: actions.openSkyView,
                               onSearch: actions.openSearchFullHeight,
                               onLogbook: actions.openLogbook, onSettings: actions.openSettings)
            .frame(width: max(0, min(RadarControlBar.maxWidth, geo.size.width - 2 * RadarControlBar.sideMargin)))
            .position(x: geo.size.width / 2, y: chrome.barMidY)
            .transition(.opacity)
    }

    // MARK: Views

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// iPad at full width: the bar's view button steps through Radar, Split and Map. In Split
    /// View or Slide Over, and on iPhone, it's one view at a time.
    private var cyclesSplit: Bool { isPad && horizontalSizeClass == .regular }

    /// What's on screen: the iPad's chosen view (`wtf.padView`), the iPhone's radar or map
    /// (`wtf.mapScreen`), or both on the iPhone Duo half open, whatever's chosen. The map
    /// needs a spot to centre on.
    private var screenView: RadarSettings.TVView {
        guard settings.mapView, model.observer != nil else { return .radar }
        if fold.posture.isHalfOpen { return .split }
        if isPad { return settings.padView == .split && !cyclesSplit ? .radar : settings.padView }
        return settings.mapScreen ? .map : .radar
    }

    /// Where the bar's view button goes (it's named for it). None with Map view off, or with
    /// the iPhone Duo half open, which already has both.
    private var nextView: RadarSettings.TVView? {
        guard settings.mapView else { return nil }
        let view = screenView
        if cyclesSplit { return view.next }
        return view == .split ? nil : view == .map ? .radar : .map
    }

    private func showNextView() {
        guard let next = nextView else { return }
        withAnimation(.smooth(duration: 0.35)) {
            if isPad {
                settings.padView = next
            } else {
                settings.mapScreen = next == .map
            }
        }
    }

    // MARK: Map pane

    /// Where the radar, the fold and the map go, in the reader's (safe-area) coordinates.
    private struct Panes {
        var radar: CGRect
        var map: CGRect?
        var gutter: CGRect?
        /// The map slides in from this side.
        var mapEdge: Edge = .trailing
        /// iPad in portrait: the bar stands along the screen's bottom over the map rather than
        /// in the radar pane; how far up from the screen's bottom edge the map keeps clear.
        var barInset: CGFloat?

        /// In the order `body` lists the panes: radar, gutter, map.
        var frames: [CGRect] { [radar] + [gutter, map].compactMap { $0 } }
    }

    /// Split: iPhone Duo half open, a half each side of the fold (radar on the left page or the
    /// standing half); iPad in landscape, the map beside a square-ish radar; iPad in portrait,
    /// the radar on the top half and the map below, under the bar. Otherwise the radar alone,
    /// which shows the map in its place when that's the view.
    private func panes(in geo: GeometryProxy, view: RadarSettings.TVView) -> Panes {
        let size = geo.size
        let whole = CGRect(origin: .zero, size: size)
        guard view == .split else { return Panes(radar: whole) }

        // The fold strip is in window coordinates, safe areas included: split the whole
        // screen, then bring the halves into the reader's coordinates.
        let insets = geo.safeAreaInsets
        let screen = CGSize(width: size.width + insets.leading + insets.trailing,
                            height: size.height + insets.top + insets.bottom)
        if let split = FoldLayout.split(fold.posture, size: screen, division: fold.division) {
            let origin = geo.frame(in: .global).origin
            func local(_ rect: CGRect) -> CGRect {
                let clipped = rect.offsetBy(dx: -origin.x, dy: -origin.y).intersection(whole)
                return clipped.isNull ? .zero : clipped
            }
            return Panes(radar: local(split.radar), map: local(split.map), gutter: local(split.gutter),
                         mapEdge: split.posture == .tabletop ? .bottom : .trailing)
        }

        guard isPad else { return Panes(radar: whole) }
        if size.width > size.height {
            return Panes(radar: CGRect(x: 0, y: 0, width: size.height, height: size.height),
                         map: CGRect(x: size.height, y: 0, width: size.width - size.height, height: size.height))
        }
        // Halves of the whole screen, the status bar and the home indicator included. The map
        // keeps its ring and buttons above the bar, as under the map card.
        let middle = (screen.height / 2 - insets.top).rounded()
        let chrome = RadarChrome(size: size, safeBottom: insets.bottom, tagsHeight: 0)
        let barTop = chrome.barMidY - RadarControlBar.height / 2
        return Panes(radar: CGRect(x: 0, y: 0, width: size.width, height: middle),
                     map: CGRect(x: 0, y: middle, width: size.width, height: size.height - middle),
                     mapEdge: .bottom, barInset: size.height + insets.bottom - (barTop - 4))
    }

    /// The map turns with the phone, but only once the heading has moved 10°, so compass
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

    /// What `syncObserver` publishes, as one value to watch.
    private var observerKey: ObserverKey {
        ObserverKey(latitude: observerCoordinate?.latitude, longitude: observerCoordinate?.longitude, placeName: placeName)
    }

    private struct ObserverKey: Equatable {
        let latitude: Double?
        let longitude: Double?
        let placeName: String
    }

    /// The `PlaceNamer` square you're in, when sightings are being stamped with it.
    /// About 7 km squares: a new weather report only when the radar moves somewhere else (or
    /// reaches further). Nil, no reports, with every weather feature off.
    private var weatherArea: WeatherFetchKey? {
        guard settings.usesWeather, let observer = observerCoordinate else { return nil }
        return WeatherFetchKey(area: PlaceNamer.area(of: observer), reachMiles: WeatherFog.reachMiles(radius: settings.radiusMiles),
                               fog: settings.weatherFog)
    }

    /// The weather reports around now and every 15 minutes: the nearest for "Can I see it?",
    /// all of them for the clouds and fog.
    private func refreshWeather() async {
        guard let key = weatherArea else { return }
        // The radius slider changes the key many times a second: ask once it settles (each
        // Apple Weather fetch is five calls).
        try? await Task.sleep(for: .seconds(1.5))
        while !Task.isCancelled {
            if let observer = observerCoordinate {
                #if DEBUG
                if let preset = UserDefaults.standard.string(forKey: "wtf.debugWeather") {
                    model.setWeather(SkyReport.debugPreset(preset, around: observer))
                    return
                }
                #endif
                let report = await SkyConditionsProvider.shared.report(near: observer, reachMiles: key.reachMiles)
                let clouds = settings.weatherFog
                    ? await CloudCoverProvider.shared.samples(around: observer, radiusMiles: settings.radiusMiles) : nil
                model.setWeather(report, clouds: clouds)
            }
            try? await Task.sleep(for: .seconds(SkyConditionsProvider.refresh))
        }
    }

    private var loggingPlaceArea: String? {
        guard settings.locationMode == .device, let here = location.location?.coordinate else { return nil }
        return PlaceNamer.area(of: here)
    }

    private func syncObserver() {
        model.setObserver(observerCoordinate)
        let store = SharedRadarStore()
        store.observer = observerCoordinate
        store.placeName = placeName
        store.radiusMiles = settings.radiusMiles
        store.overheadMiles = settings.overheadAlertMiles
        sendWatchContext()
    }

    /// "Atlanta, GA" on sightings logged from where you really are. A custom spot isn't logged.
    private func nameLoggingPlace() async {
        guard settings.locationMode == .device, let here = location.location?.coordinate else { return }
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
            notableAlerts: settings.notableAlerts, sentAt: Date(),
            units: settings.units.rawValue, overheadAlertLeadSeconds: settings.overheadAlertLeadSeconds,
            watchlist: settings.watchlist, favoriteAlerts: settings.favoriteAlerts,
            keepLogbook: settings.keepLogbook, syncLogbook: settings.syncLogbook
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
            guard SkyViewSupport.isAvailable else { return }
            sheet = nil
            sky = SkyRequest()
        case .logbook:
            sky = nil
            logbookRoute = nil
            logbookTab = nil
            sheet = .logbook
        case .airframe(let reg):
            sky = nil
            logbookRoute = .airframe(reg)
            logbookTab = nil
            sheet = .logbook
        case .logbookTab(let name):
            sky = nil
            logbookRoute = nil
            logbookTab = LogbookTab(rawValue: name)
            sheet = .logbook
        case .badge(let id):
            sky = nil
            logbookRoute = .badge(id)
            logbookTab = .badges
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
    /// Read aloud as well when Read Alerts Aloud is on (only through headphones, AirPods or
    /// the car unless that's turned off), so a walk with Sky Watch running needs no looking.
    private func deliver(_ alert: TrafficAlert) {
        if UIApplication.shared.applicationState == .active {
            model.post(notice: alert.title, symbol: alert.symbol)
        } else {
            AlertNotifier.deliver(alert)
        }
        if settings.spokenAlerts, !settings.spokenAlertsHeadphonesOnly || AlertSpeaker.hasPrivateRoute,
           let contact = model.contact(id: alert.flightID) {
            AlertSpeaker.shared.speak(SpokenTraffic.sentence(for: contact, alert: alert), about: contact.id)
        }
    }

    /// Lifting the phone opens Sky View, except over a sheet, and not while an iPhone Duo is
    /// half open: then the camera and the motion sensors can sit in different halves, and a
    /// phone standing in tabletop keeps looking "raised".
    private var listensForRaise: Bool {
        SkyViewSupport.isAvailable && scenePhase == .active && settings.raiseToSkyView && sheet == nil && sky == nil && !fold.posture.isHalfOpen
    }

    private var keepsScreenAwake: Bool { settings.keepScreenAwake && scenePhase == .active }

    #if DEBUG
    /// `-wtf.debugSheet settings|search|detail|welcome|tvlink|logbook|sky` opens a sheet at launch and
    /// `-wtf.debugFocus DL570` focuses a flight (screenshots, UI tests).
    private func openDebugSheetIfRequested() {
        let defaults = UserDefaults.standard
        // `-wtf.debugShareCard YES` writes the newest sighting's share card to
        // tmp/ShareCard.png in the app's container, and every card of this year's and this
        // month's recaps to RecapCard-year-1.png… and RecapCard-month-1.png… (the TV's
        // landscape ones to RecapCard-wide-year-1.png…).
        if defaults.bool(forKey: "wtf.debugShareCard"), let s = logbook.sightings.last {
            Task { @MainActor in
                let dir = FileManager.default.temporaryDirectory
                if let image = await SightingCardRenderer.render(SightingCardInfo(sighting: s)) {
                    try? image.pngData()?.write(to: dir.appendingPathComponent("ShareCard.png"))
                }
                for (name, period) in zip(["year", "month"], LogbookRecap.periods()) {
                    guard let recap = LogbookRecap(logbook.sightings, period: period) else { continue }
                    for kind in RecapSlide.Kind.allCases {
                        if let card = RecapRenderer.share(kind: kind, recap: recap) {
                            try? card.image.pngData()?.write(to: dir.appendingPathComponent("RecapCard-\(name)-\(kind.rawValue + 1).png"))
                        }
                        // The TV's landscape cards, drawn here because the TV can't save them.
                        if let card = RecapRenderer.share(kind: kind, recap: recap, format: .wide) {
                            try? card.image.pngData()?.write(to: dir.appendingPathComponent("RecapCard-wide-\(name)-\(kind.rawValue + 1).png"))
                        }
                    }
                }
                Log.ui.notice("Share cards written to \(dir.path, privacy: .public)")
            }
        }
        // `-wtf.debugWidgets YES` draws every logbook widget face to tmp/Widgets-*.png.
        if defaults.bool(forKey: "wtf.debugWidgets") {
            WidgetGallery.write(live: LogbookSnapshot(digest: logbook.digest, observer: model.observer))
        }
        // `-wtf.debugIcon <concept>[.<look>]` switches the Home Screen icon (e.g. `tally.dark`,
        // `edgeRadar`, `automatic`).
        if let raw = defaults.string(forKey: "wtf.debugIcon"), let choice = AppIconChoice(debugName: raw) {
            Task { @MainActor in
                // iOS only changes the icon once the app is on screen.
                try? await Task.sleep(for: .seconds(2))
                do { try await choice.apply() } catch { Log.ui.error("debugIcon: \(error.localizedDescription, privacy: .public)") }
            }
        }
        // `-wtf.debugMapHeading 90` turns the map as if the compass read that (the simulator
        // has no compass).
        if defaults.object(forKey: "wtf.debugMapHeading") != nil {
            followHeading(defaults.double(forKey: "wtf.debugMapHeading"))
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

/// Puts each pane at its frame, in order. Unlike `.offset`, a placed pane knows where it
/// really is, so its safe area and `ignoresSafeArea()` work from its own edges.
private struct PaneLayout: Layout {
    let frames: [CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

/// iPhone Duo, half open: the strip over the fold between the radar and the map, shaded in
/// to a hairline at the crease like the gutter of a book. Nothing to tap lives here.
private struct FoldGutter: View {
    /// Which way the fold runs on screen.
    let axis: Axis

    var body: some View {
        let across: (UnitPoint, UnitPoint) = axis == .vertical ? (.leading, .trailing) : (.top, .bottom)
        ZStack {
            Palette.paper
            LinearGradient(colors: [.clear, Palette.paperShade.opacity(0.7), .clear],
                           startPoint: across.0, endPoint: across.1)
            Rectangle()
                .fill(Palette.faint.opacity(0.45))
                .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
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
            WidgetCenter.shared.reloadTimelines(ofKind: SharedRadarStore.nextOverheadKind)
        }
    }
}

/// iPhone stays in portrait — the radar is a compass, and a compass doesn't rotate. The
/// iPhone Duo turns: iOS doesn't ask on its inner screen, which turns with the phone like an
/// iPad's (book and tabletop need both ways round), and its cover screen turns to landscape
/// too, where the bar stands in the system's vertical bar strip. The compass follows both
/// (`RadarLocationService.interfaceOrientations`).
final class RadarAppDelegate: NSObject, UIApplicationDelegate {
    private let notifications = AlertNotificationDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notifications
        UNUserNotificationCenter.current().setNotificationCategories([AlertNotifier.trafficCategory])
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        return FoldMonitor.phoneFolds ? .allButUpsideDown : .portrait
    }
}
/// Runs `action` when `value()` changes. The value is read in this empty view's own body,
/// so a source that changes many times a second (the compass, the 1 Hz clock) re-evaluates
/// only this view, not the caller.
private struct ChangeObserver<Value: Equatable>: View {
    let value: () -> Value
    let action: (Value) -> Void

    var body: some View {
        Color.clear
            .onChange(of: value()) { _, new in action(new) }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

/// The live map of the model's traffic: the iPad's and the iPhone Duo's pane beside (or below)
/// the radar, and the map the bar swaps in for the radar (`RadarScreen`). Its own view, so
/// per-tick traffic redraws the map rather than whatever holds it. It runs to the screen's
/// edges on its own, after noting its safe area, so MapKit's compass stays out of the status
/// bar and the recentre button out of the iPhone Duo's vertical bar strip.
struct RadarMapPane: View {
    let model: RadarModel
    let settings: RadarSettings
    let observer: CLLocationCoordinate2D
    let mapHeading: Double?
    /// Keeps the ring and the recentre button clear of the hero card and the bar.
    var cardInset: CGSize = .zero

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
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
                // Only a pane at the top of the screen has the status bar over it (not the
                // Duo's half lying on the table). The card's width counts from the safe area's
                // trailing edge, the vertical bar strip being outside it.
                options: .init(interactive: true,
                               cardInset: CGSize(width: cardInset.width + geo.safeAreaInsets.trailing, height: cardInset.height),
                               topInset: geo.safeAreaInsets.top,
                               fog: settings.weatherFog ? model.weatherFog : nil,
                               fogDrifts: scenePhase == .active,
                               fogAttribution: settings.weatherFog && model.weatherFog != nil && model.fogFromAppleWeather),
                // Browsing the map never pins: an aircraft outside the radius is only held.
                onTap: { id in withAnimation(.snappy) { model.focus(on: id, pinning: false) } }
            )
            .ignoresSafeArea()
        }
    }
}
#endif
