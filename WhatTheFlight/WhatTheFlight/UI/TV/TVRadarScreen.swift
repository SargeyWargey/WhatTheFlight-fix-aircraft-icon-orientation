//
//  TVRadarScreen.swift
//  WhatTheFlight
//
//  The radar on the big screen. Same look as the phone, laid out for landscape and the
//  10-foot view. "Up" on the TV is the direction you face when you watch it.
//
//  Siri Remote
//    ◀ ▶      closer / farther aircraft      click      details
//    ⏯        pin / unpin                    ▼          dock: Nearest · Pin · Aircraft · Logbook · View · Settings
//
//  The remote hints sit in a footer below the bezel; the dock only appears after ▼.
//  With Map view on, the dock's view item steps Radar → Split → Map: Split narrows the radar
//  to the left 60 % of the screen and puts the live map beside it (`TVTrafficMap`); Map
//  swaps the radar face for the map full screen (`TVMapStack`). The remote works the same on
//  all three. Left alone for 30 s, the full-screen map settles: the status badge and hints
//  fade out until the next press.
//
//  With the map on screen, holding ● on the hero opens the map panel on the map's side: the
//  map's own range (`wtf.mapRadius`, independent of the radar's) and its style. Picking a
//  chip applies it and goes straight back to the hero.
//

#if os(tvOS)
import SwiftUI

struct TVRadarScreen: View {
    let model: RadarModel
    let settings: RadarSettings
    let centerState: CenterStateView.Kind?
    let actions: Actions

    struct Actions {
        var openSettings: (TVSettingsPane) -> Void
        var openDetail: (String) -> Void
        var openAircraft: () -> Void
        var openLogbook: () -> Void
        var centerPrimary: () -> Void
        var centerSecondary: () -> Void
    }

    enum Focus: Hashable {
        case radar
        case dock(DockItem)
        /// The map panel's chips.
        case mapRange(Double?)
        case mapType(RadarSettings.MapType)
    }

    enum DockItem: CaseIterable {
        case nearest, pin, aircraft, logbook, view, settings
    }

    @FocusState private var focus: Focus?
    @State private var showDock = false
    /// Hold ● with the map on screen: its range and style, on the map's side.
    @State private var showMapPanel = false
    /// Ambient settle: the last remote input, and whether the chrome has faded since.
    @State private var lastInput = Date()
    @State private var isSettled = false
    /// The dock's own width, so it can shrink to fit beside the map.
    @State private var dockWidth: CGFloat = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let scale: CGFloat = 1.7
    private static let heroScale: CGFloat = 1.55
    /// Split view: the radar's share of the screen's width; the map takes the rest.
    private static let splitRadarShare: CGFloat = 0.6

    private var heading: Double { settings.tvFacingDegrees }
    /// The map full screen, in place of the radar.
    private var showsMap: Bool { settings.effectiveTVView == .map }
    /// The radar on the left, the map on the right.
    private var showsSplit: Bool { settings.effectiveTVView == .split }
    /// Split or Map: holding ● opens the map panel.
    private var mapIsShowing: Bool { showsMap || showsSplit }
    /// The badge and hints, faded once the map has settled.
    private var chromeOpacity: Double { showsMap && isSettled && !showDock ? 0 : 1 }

    var body: some View {
        GeometryReader { screen in
            HStack(spacing: 0) {
                face
                    .frame(width: showsSplit ? Self.splitRadarWidth(in: screen) : nil)
                if showsSplit {
                    TVTrafficMap(model: model, settings: settings)
                        .overlay {
                            if showMapPanel { mapPanel.transition(.opacity.combined(with: .scale(scale: 0.96))) }
                        }
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .defaultFocus($focus, .radar)
        .onChange(of: focus) { _, newValue in
            noteInput()
            // Leaving the dock (MENU, or ▲ back to the aircraft) tucks it away again.
            if case .dock = newValue { return }
            withAnimation(.smooth(duration: 0.25)) { showDock = false }
        }
        .onChange(of: centerState) { _, _ in showDock = false }
        .onChange(of: settings.mapView) { _, isOn in
            // Switching Map view off while the map shows goes straight back to the radar.
            guard !isOn, settings.tvView != .radar else { return }
            withAnimation(.smooth(duration: 0.6)) { settings.tvView = .radar }
        }
        .onChange(of: mapIsShowing, initial: true) { _, isShowing in
            if isShowing { suggestKeepingAwake() } else if showMapPanel { closeMapPanel() }
        }
        .task(id: SettleKey(lastInput: lastInput, showsMap: showsMap)) {
            guard showsMap else { return }
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) { isSettled = true }
        }
        #if DEBUG
        .task {
            // `-wtf.debugDock YES` opens the dock for screenshots.
            guard UserDefaults.standard.bool(forKey: "wtf.debugDock") else { return }
            try? await Task.sleep(for: .seconds(4))
            openDock()
        }
        .task(id: model.focusedContact == nil) {
            // `-wtf.debugMapPanel YES` opens the map panel (Split or Map) for screenshots, once
            // there's an aircraft on the hero, as for a real hold.
            guard UserDefaults.standard.bool(forKey: "wtf.debugMapPanel"), model.focusedContact != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            openMapPanel()
        }
        #endif
    }

    /// The radar pane's width in Split view: its share of the whole screen, overscan
    /// included, less the left overscan it bleeds into.
    private static func splitRadarWidth(in screen: GeometryProxy) -> CGFloat {
        let insets = screen.safeAreaInsets
        return (screen.size.width + insets.leading + insets.trailing) * splitRadarShare - insets.leading
    }

    /// The radar face (or the full-screen map) with the hero, badge, hints and dock laid
    /// over it. In Split view it fills the left pane.
    private var face: some View {
        GeometryReader { geo in
            let layout = RadarLayout(size: geo.size, scale: Self.scale)
            let placements = PerimeterPlanner.plan(
                contacts: model.perimeterContacts,
                heading: heading,
                track: layout.iconTrack,
                obstacles: [
                    .init(s: layout.iconTrack.arcLength(of: .bottomRight), halfWidth: 84),
                    .init(s: layout.iconTrack.arcLength(of: .bottomLeft), halfWidth: 70),
                ],
                scale: Self.scale
            )
            // Beside the map the pane is narrower, so the hero takes more of it to keep its stats
            // on one line.
            let heroWidth = geo.size.width * (showsSplit ? 0.8 : 0.62)

            ZStack {
                if showsMap {
                    TVMapStack(model: model, settings: settings) { mapCard }
                        .transition(.opacity)
                } else {
                    Group {
                        if settings.showCompassBezel {
                            CompassBezel(track: layout.bezelTrack, heading: heading, scale: Self.scale)
                                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: heading)
                        }

                        PerimeterLayer(
                            placements: placements,
                            focusedID: model.focus.focusedID,
                            announcedID: AlertSpeaker.shared.speakingFlightID,
                            pinnedIDs: model.pinnedIDs,
                            radiusMiles: settings.radiusMiles,
                            scale: Self.scale,
                            onTap: { _ in },
                            onLongPress: { _ in }
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: heading)

                        center(width: heroWidth)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.47)
                    }
                    .transition(.opacity)
                }

                if centerState == nil {
                    if showDock {
                        // Laid out at its natural width, then shrunk to fit the pane if need be,
                        // so the labels never wrap.
                        dock
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { dockWidth = $0 }
                            .scaleEffect(dockWidth > 0 ? min(1, (geo.size.width - 40) / dockWidth) : 1)
                            .position(x: geo.size.width / 2, y: geo.size.height - 130)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    RemoteHints(dockIsOpen: showDock || showMapPanel, isPinned: model.focus.isPinned, holdsForMap: mapIsShowing)
                        .opacity(chromeOpacity)
                        .position(x: geo.size.width / 2, y: Self.footerY(in: geo))
                }

                if showsMap {
                    mapStatus
                        .opacity(chromeOpacity)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if showMapPanel {
                        // Left of centre, clear of the hero card bottom-right.
                        mapPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.leading, 60)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                } else {
                    StatusBadge(model: model)
                        .scaleEffect(1.6)
                        .position(layout.statusPoint)
                }

                NoticeBanner(model: model)
                    .scaleEffect(1.6)
                    .frame(width: min(700, geo.size.width / 1.6 - 20))
                    .position(x: geo.size.width / 2, y: 70)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background {
            if !showsMap {
                RadarBackdrop(showTopography: settings.showTopography, showSweep: settings.radarSweep, isActive: scenePhase == .active,
                              topographyMotion: settings.topographyMotion)
                    .ignoresSafeArea()
            }
        }
    }

    /// The footer lives in the bottom overscan margin, below the bezel and the aircraft icons.
    private static func footerY(in geo: GeometryProxy) -> CGFloat {
        let margin = geo.safeAreaInsets.bottom
        return margin >= 40 ? geo.size.height + margin / 2 : geo.size.height - 22
    }

    // MARK: Centre

    @ViewBuilder
    private func center(width: CGFloat) -> some View {
        ZStack {
            if let centerState {
                CenterStateView(kind: centerState, onPrimary: actions.centerPrimary, onSecondary: actions.centerSecondary)
                    .frame(width: width * 0.8)
                    .transition(.opacity)
            } else if let contact = model.focusedContact {
                heroButton(contact) {
                    FlightHero(contact: contact, isPinned: model.focus.isPinned, heading: heading, wideStats: true, detailScale: 1.4)
                        .id(contact.id)
                        .frame(width: width / Self.heroScale)
                        .scaleEffect(Self.heroScale)
                        .frame(width: width, height: 640)
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.focus.focusedID)
        .animation(.smooth(duration: 0.35), value: centerState)
    }

    /// The map's card: the same hero, smaller, or the same empty-state copy as the radar.
    @ViewBuilder
    private var mapCard: some View {
        ZStack {
            if let centerState {
                TVScaledContent(width: TVMapLayout.cardWidth, scale: 0.72) {
                    CenterStateView(kind: centerState, onPrimary: actions.centerPrimary, onSecondary: actions.centerSecondary)
                }
                .transition(.opacity)
            } else if let contact = model.focusedContact {
                heroButton(contact) {
                    TVScaledContent(width: TVMapLayout.cardWidth, scale: 1.35) {
                        FlightHero(contact: contact, isPinned: model.focus.isPinned, heading: heading, wideStats: true, detailScale: 0.9)
                    }
                    .id(contact.id)
                    .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.35), value: model.focus.focusedID)
        .animation(.smooth(duration: 0.35), value: centerState)
    }

    /// The focus anchor, on the radar and on the map alike: ◀ ▶ change aircraft, click opens
    /// the details, ⏯ pins, ▼ opens the dock.
    private func heroButton<Label: View>(_ contact: RadarContact, @ViewBuilder label: () -> Label) -> some View {
        Button {
            noteInput()
            actions.openDetail(contact.id)
        } label: {
            label()
        }
        .buttonStyle(TVQuietButtonStyle())
        .focused($focus, equals: .radar)
        // While the map panel is open the remote stays in it.
        .disabled(showMapPanel)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in openMapPanel() })
        .onMoveCommand { direction in
            noteInput()
            switch direction {
            case .left: withAnimation(.snappy) { model.focusPrevious() }
            case .right: withAnimation(.snappy) { model.focusNext() }
            case .down: openDock()
            default: break
            }
        }
        .onPlayPauseCommand {
            noteInput()
            withAnimation(.snappy) { model.togglePin() }
        }
        .accessibilityHint(mapIsShowing ? "Left and right change aircraft. Click for details. Hold for the map's range and style."
                                        : "Left and right change aircraft. Click for details.")
        .accessibilityAction(named: "Map range and style") { openMapPanel() }
    }

    // MARK: Map chrome

    /// Top-left on the map: the live badge, then where and how far.
    private var mapStatus: some View {
        HStack(spacing: 18) {
            StatusBadge(model: model)
                .scaleEffect(1.6)
                .frame(width: 140, height: 52, alignment: .leading)
            if let caption = mapCaption {
                Text(caption)
                    .font(.mono(22, .bold))
                    .foregroundStyle(Palette.value)
                    .paperHalo()
            }
        }
    }

    /// "Atlanta, GA · 20 mi": the map's range, which can differ from the radar's.
    private var mapCaption: String? {
        let place = settings.locationMode == .custom ? settings.customPlaceName : model.logPlaceName
        return [place, "\(Int(settings.effectiveMapRadius)) mi"].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Map panel

    /// Hold ● on the hero (Split or Map): the map's range and style. Picking one applies it
    /// and hands the remote straight back to the hero; MENU closes it unchanged.
    private var mapPanel: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Map")
                .font(.mono(34, .heavy))
                .foregroundStyle(Palette.ink)
            HStack(alignment: .top, spacing: 40) {
                panelColumn("Range") {
                    ForEach(RadarSettings.mapRadiusChoices, id: \.self) { miles in
                        panelChip(miles.map { "\(Int($0)) mi" } ?? "Same as radar",
                                  isSelected: settings.mapRadiusMiles == miles, focus: .mapRange(miles)) {
                            settings.mapRadiusMiles = miles
                        }
                    }
                }
                panelColumn("Style") {
                    ForEach(RadarSettings.MapType.allCases) { type in
                        panelChip(type.title, isSelected: settings.mapType == type, focus: .mapType(type)) {
                            settings.mapType = type
                        }
                    }
                }
            }
        }
        .padding(36)
        .glassSurface(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        .focusSection()
        .onExitCommand { closeMapPanel() }
        .accessibilityIdentifier("tv_map_panel")
    }

    private func panelColumn<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.mono(20, .bold))
                .tracking(3)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
            content()
        }
    }

    private func panelChip(_ title: String, isSelected: Bool, focus item: Focus, action: @escaping () -> Void) -> some View {
        Button(title) {
            noteInput()
            withAnimation(.snappy) { action() }
            closeMapPanel()
        }
        .buttonStyle(TVChipButtonStyle(isSelected: isSelected))
        .focused($focus, equals: item)
    }

    private func openMapPanel() {
        guard mapIsShowing, centerState == nil, !showMapPanel else { return }
        noteInput()
        withAnimation(.smooth(duration: 0.25)) {
            showDock = false
            showMapPanel = true
        }
        // Focus can only move once the panel is on screen: start on the current range.
        let range = RadarSettings.mapRadiusChoices.contains(settings.mapRadiusMiles) ? settings.mapRadiusMiles : nil
        Task { @MainActor in focus = .mapRange(range) }
    }

    private func closeMapPanel() {
        withAnimation(.smooth(duration: 0.25)) { showMapPanel = false }
        // The hero is enabled again once the panel has gone: then it can take focus.
        Task { @MainActor in focus = .radar }
    }

    // MARK: Ambient settle

    private struct SettleKey: Equatable {
        let lastInput: Date
        let showsMap: Bool
    }

    /// Any remote input brings the badge and hints back and restarts the 30 s timer.
    private func noteInput() {
        lastInput = Date()
        guard isSettled else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { isSettled = false }
    }

    /// The map is meant to be left on; the first time it opens, mention the screen saver.
    private func suggestKeepingAwake() {
        let key = "wtf.mapAwakeHintShown"
        guard !settings.keepScreenAwake, !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        model.post(notice: "Turn on Keep screen awake in Settings to leave the map running", symbol: "sun.max.fill")
    }

    // MARK: Dock

    private func openDock() {
        withAnimation(.smooth(duration: 0.25)) { showDock = true }
        // Focus can only move once the dock is on screen.
        Task { @MainActor in focus = .dock(.nearest) }
    }

    private var dock: some View {
        HStack(spacing: 26) {
            dockButton(.nearest, title: "Nearest", symbol: "scope") {
                withAnimation(.snappy) { model.focusNearest() }
                focus = .radar
            }
            dockButton(.pin, title: model.focus.isPinned ? "Unpin" : "Pin", symbol: model.focus.isPinned ? "pin.slash.fill" : "pin.fill") {
                withAnimation(.snappy) { model.togglePin() }
            }
            dockButton(.aircraft, title: "Aircraft", symbol: "list.bullet") {
                actions.openAircraft()
            }
            dockButton(.logbook, title: "Logbook", symbol: "book.closed.fill") {
                actions.openLogbook()
            }
            if settings.mapView {
                // Named for the view it switches to: Radar → Split → Map → Radar.
                let next = settings.effectiveTVView.next
                dockButton(.view, title: next.title, symbol: next.symbol) {
                    withAnimation(.smooth(duration: 0.6)) { settings.tvView = next }
                    // The hero is rebuilt for the other view: focus it once it's there.
                    Task { @MainActor in focus = .radar }
                }
            }
            dockButton(.settings, title: "Settings", symbol: "gearshape.fill") {
                actions.openSettings(.radar)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .glassSurface(in: Capsule())
        .focusSection()
        .onExitCommand {
            noteInput()
            focus = .radar
        }
    }

    private func dockButton(_ item: DockItem, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            noteInput()
            action()
        } label: {
            // The dock is laid out at its natural width; without this, rounding can leave a
            // label a hair short and wrap it ("Aircraf / t").
            Label(title, systemImage: symbol)
                .fixedSize()
        }
        .buttonStyle(TVPillButtonStyle(prominent: false, compact: true))
        .focused($focus, equals: .dock(item))
    }
}

/// "◀ ▶ Aircraft · ● Details · ⏯ Pin · ▼ More" (plus "● Hold: Map" with the map on screen),
/// drawn with SF Symbols in key caps.
private struct RemoteHints: View {
    /// The dock or the map panel: MENU goes back.
    let dockIsOpen: Bool
    let isPinned: Bool
    var holdsForMap = false

    var body: some View {
        HStack(spacing: 40) {
            if dockIsOpen {
                hint(["chevron.backward"], "Back")
            } else {
                hint(["arrowtriangle.left.fill", "arrowtriangle.right.fill"], "Aircraft")
                hint(["circle.circle"], "Details")
                if holdsForMap { hint(["circle.circle"], "Hold: Map") }
                hint(["playpause.fill"], isPinned ? "Unpin" : "Pin")
                hint(["arrowtriangle.down.fill"], "More")
            }
        }
        .font(.mono(20, .semibold))
        .foregroundStyle(Palette.caption)
        .paperHalo()
        .animation(.smooth(duration: 0.25), value: dockIsOpen)
        .accessibilityHidden(true)
    }

    private func hint(_ symbols: [String], _ title: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    Image(systemName: symbol)
                }
            }
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Palette.value)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Palette.paperShade.opacity(0.6), in: Capsule())
            .overlay(Capsule().stroke(Palette.caption.opacity(0.35), lineWidth: 1.5))
            Text(title)
        }
    }
}
#endif
