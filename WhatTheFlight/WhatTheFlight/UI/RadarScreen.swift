//
//  RadarScreen.swift
//  WhatTheFlight
//
//  The main screen. No cards on the radar: the focused flight in the middle, every other
//  aircraft on the edge, and a floating glass bar along the bottom (`RadarControlBar`): Map /
//  Radar, Sky View, the aircraft count (Aircraft search), the logbook and settings. With Map
//  view on and no map pane beside it, Map swaps the radar for the live map and a card for the
//  focused flight; the bar stays put, so getting around works the same on both. Demo traffic
//  (a solid DEMO count) and a custom spot each get a tag just above the bar.
//
//  Gestures (radar)
//    swipe →   back to the nearest aircraft      tap centre   flight details
//    swipe ←   next aircraft farther out         hold centre  pin / unpin
//    swipe ↓   logbook                           tap an icon  focus it
//    swipe ↑   settings                          hold an icon details
//  On the map drags pan it, so the card takes the sideways swipes; tap a glyph to focus it.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import CoreLocation

#if os(iOS)
struct RadarScreen: View {
    let model: RadarModel
    let settings: RadarSettings
    let location: RadarLocationService
    /// Read in this view's body, so the per-tick traffic it depends on redraws the radar
    /// screen only, not the root view and whatever sheet it's presenting.
    let centerState: () -> CenterStateView.Kind?
    /// Map view on with no map pane beside the radar: the bar offers Map / Radar.
    let offersMap: Bool
    /// "Up" on the map: the compass in steps (`RadarRootView.mapHeading`).
    let mapHeading: Double?
    let actions: Actions

    struct Actions {
        var openSettings: () -> Void
        /// Swipe down, or Logbook on the bar.
        var openLogbook: () -> Void
        var openDetail: (String) -> Void
        /// The count on the bar: Aircraft search, full height.
        var openSearchFullHeight: () -> Void
        /// Map / Radar on the bar.
        var toggleMap: () -> Void
        /// Sky View on the bar (lifting the phone opens it too).
        var openSkyView: () -> Void
        var openSpotPicker: () -> Void
        var centerPrimary: () -> Void
        var centerSecondary: () -> Void
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmLiveTraffic = false
    /// The hero's height before scaling, so it can shrink to fit a short radar.
    @State private var heroHeight: CGFloat = 0
    /// The demo / custom-spot tags above the bar (0 = none showing).
    @State private var tagsHeight: CGFloat = 0
    /// The focused flight's card on the map, so the map keeps its ring clear of it.
    @State private var cardHeight: CGFloat = 0
    /// The bar's natural width, so it can shrink to fit a narrow window (iPad Split View).
    @State private var barWidth: CGFloat = 0

    private var heading: Double { location.heading ?? 0 }

    /// The map in place of the radar. It needs a spot to centre on.
    private var showsMap: Bool { offersMap && settings.mapScreen && model.observer != nil }

    var body: some View {
        GeometryReader { geo in
            let chrome = RadarChrome(size: geo.size, safeBottom: geo.safeAreaInsets.bottom, tagsHeight: tagsHeight)
            let layout = RadarLayout(size: chrome.radarSize)
            let showsMap = showsMap

            ZStack {
                if showsMap, let observer = model.observer {
                    mapView(observer: observer, chrome: chrome, geo: geo)
                        .transition(.opacity)
                } else {
                    radarFace(layout)
                        .frame(width: chrome.radarSize.width, height: chrome.radarSize.height)
                        .position(x: chrome.radarSize.width / 2, y: chrome.radarSize.height / 2)
                        .transition(.opacity)
                }

                NoticeBanner(model: model)
                    .frame(width: layout.heroWidth + 40)
                    .position(x: geo.size.width / 2, y: layout.noticeY)

                tags
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tagsHeight = $0 }
                    .position(x: geo.size.width / 2, y: chrome.tagsMidY)

                RadarControlBar(model: model, offersMap: offersMap, showsMap: showsMap,
                                onToggleMap: actions.toggleMap, onSkyView: actions.openSkyView,
                                onSearch: actions.openSearchFullHeight,
                                onLogbook: actions.openLogbook, onSettings: actions.openSettings)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
                    .scaleEffect(barWidth > 0 ? min(1, (geo.size.width - 16) / barWidth) : 1)
                    .position(x: geo.size.width / 2, y: chrome.barMidY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.smooth(duration: 0.35), value: showsMap)
        }
        .confirmationDialog("Demo traffic", isPresented: $confirmLiveTraffic, titleVisibility: .visible) {
            Button("Switch to Live Traffic") { settings.demoTraffic = false }
        } message: {
            Text("These aircraft are simulated, not what's really overhead, and they aren't logged.")
        }
        .background {
            // Kept (still) under the map, so it fades in over the contours rather than a gap.
            RadarBackdrop(
                showTopography: settings.showTopography,
                showSweep: settings.radarSweep,
                isActive: scenePhase == .active && !showsMap,
                topographyMotion: settings.topographyMotion
            )
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .gesture(swipe, isEnabled: !showsMap)
        .sensoryFeedback(.selection, trigger: model.focus.focusedID) { _, _ in settings.hapticsEnabled }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.pins.count) { _, _ in settings.hapticsEnabled }
    }

    // MARK: Radar

    /// The compass bezel, the hero and the icons on the edge, laid out in the screen above the
    /// bar.
    private func radarFace(_ layout: RadarLayout) -> some View {
        let placements = PerimeterPlanner.plan(contacts: model.perimeterContacts, heading: heading, track: layout.iconTrack, obstacles: [])
        let heroScale = layout.heroScale(fitting: heroHeight, room: layout.size.height - 2 * layout.heroClearance)
        return ZStack {
            if settings.showCompassBezel {
                CompassBezel(track: layout.bezelTrack, heading: heading)
                    .animation(reduceMotion ? nil : .interactiveSpring(response: 0.45, dampingFraction: 0.86), value: heading)
            }

            center(wideStats: layout.prefersWideStats, compact: layout.prefersCompactHero)
                .frame(width: layout.heroWidth / heroScale)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
                .scaleEffect(heroScale)
                .position(x: layout.size.width / 2, y: layout.size.height / 2)

            PerimeterLayer(
                placements: placements,
                focusedID: model.focus.focusedID,
                pinnedIDs: model.pinnedIDs,
                radiusMiles: settings.radiusMiles,
                onTap: { contact in
                    withAnimation(.snappy) { model.focus(on: contact.id) }
                },
                onLongPress: { contact in actions.openDetail(contact.id) }
            )
        }
    }

    // MARK: Map

    /// The live map under everything and the focused flight's card above the bar: across the
    /// bottom on a phone, bottom-right on a wide screen (the iPhone Duo open flat).
    private func mapView(observer: CLLocationCoordinate2D, chrome: RadarChrome, geo: GeometryProxy) -> some View {
        let size = geo.size
        let beside = size.width > size.height * 1.15
        let cardWidth = beside ? min(400, size.width * 0.42) : min(520, size.width - 24)
        let cardBottom = chrome.radarSize.height
        // The map runs under the home indicator, so its insets count from the screen's edge.
        let screenBottom = size.height + geo.safeAreaInsets.bottom
        let inset = beside
            ? CGSize(width: cardWidth + 24, height: screenBottom - cardBottom)
            : CGSize(width: 0, height: screenBottom - cardBottom + cardHeight)
        return ZStack(alignment: beside ? .bottomTrailing : .bottom) {
            RadarMapPane(model: model, settings: settings, observer: observer, mapHeading: mapHeading, cardInset: inset)

            mapCard
                .frame(width: cardWidth)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .padding(.trailing, beside ? 12 : 0)
                .padding(.bottom, size.height - cardBottom)
        }
        .frame(width: size.width, height: size.height)
    }

    /// The hero on glass, kept short (one row of stats, no type line or approach chip) so
    /// the map keeps the screen.
    private var mapCard: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return center(wideStats: true, compact: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .glassSurface(in: shape)
            .contentShape(shape)
            .gesture(cardSwipe)
    }

    // MARK: Centre

    @ViewBuilder
    private func center(wideStats: Bool, compact: Bool) -> some View {
        let centerState = centerState()
        ZStack {
            if let centerState {
                CenterStateView(kind: centerState, onPrimary: actions.centerPrimary, onSecondary: actions.centerSecondary)
                    .transition(.opacity)
            } else if let contact = model.focusedContact {
                FlightHero(contact: contact, isPinned: model.focus.isPinned, heading: heading,
                           wideStats: wideStats, compact: compact)
                    .id(contact.id)
                    // A scale-in here could get stuck part-way and leave the hero off-centre.
                    .transition(.opacity)
                    .contentShape(Rectangle())
                    .onTapGesture { actions.openDetail(contact.id) }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        withAnimation(.snappy) { model.togglePin() }
                    }
                    .accessibilityAction(named: model.focus.isPinned ? "Unpin" : "Pin") { model.togglePin() }
                    .accessibilityHint("Double-tap for details")
            }
        }
        .animation(.smooth(duration: 0.35), value: model.focus.focusedID)
        .animation(.smooth(duration: 0.35), value: centerState)
    }

    /// Demo traffic and a custom spot, one line each, just above the bar.
    private var tags: some View {
        VStack(spacing: 0) {
            if model.isDemo {
                DemoTrafficTag { confirmLiveTraffic = true }
            }
            if settings.locationMode == .custom {
                CustomSpotTag(name: settings.customPlaceName ?? settings.customCoordinate?.shortDescription,
                              action: actions.openSpotPicker)
            }
        }
    }

    // MARK: Gestures

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                if abs(dx) > abs(dy) {
                    step(dx)
                } else if dy > Self.swipeThreshold {
                    actions.openLogbook()
                } else if dy < -Self.swipeThreshold {
                    actions.openSettings()
                }
            }
    }

    /// On the map drags pan it: the card takes the sideways swipes instead.
    private var cardSwipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                step(value.translation.width)
            }
    }

    private static let swipeThreshold: CGFloat = 60

    /// Right: back to the nearest. Left: the next one farther out.
    private func step(_ dx: CGFloat) {
        if dx > Self.swipeThreshold {
            withAnimation(.snappy) { model.focusNearest() }
        } else if dx < -Self.swipeThreshold {
            withAnimation(.snappy) { model.focusNext() }
        }
    }
}

/// Where the bar and the tags go, and the room left above them for the radar, in the
/// screen's safe-area coordinates. The bar dips into the home-indicator strip like a tab bar.
struct RadarChrome {
    let barMidY: CGFloat
    let tagsMidY: CGFloat
    /// From the top of the safe area down to just above the tags (or the bar).
    let radarSize: CGSize

    init(size: CGSize, safeBottom: CGFloat, tagsHeight: CGFloat) {
        // As far off the screen's bottom edge as a tab bar: clear of the home indicator when
        // there is one, a small margin when there isn't (a Home button, the Duo's standing half).
        let barBottom = size.height + safeBottom - (safeBottom >= 20 ? 22 : 10)
        let barTop = barBottom - RadarControlBar.height
        barMidY = barBottom - RadarControlBar.height / 2
        let tagsBottom = barTop - 6
        tagsMidY = tagsBottom - tagsHeight / 2
        let radarBottom = tagsHeight > 0 ? tagsBottom - tagsHeight - 2 : barTop - 4
        radarSize = CGSize(width: size.width, height: max(0, radarBottom))
    }
}

/// iPhone / iPad: the floating glass bar along the bottom. First the ways of looking: Map /
/// Radar swaps the view in place (named for where it goes, like the TV's view button) and Sky
/// View opens the camera. Then the live dot and the aircraft count (Aircraft search), the
/// logbook and settings. Demo traffic turns the count into a solid ink "DEMO 12", so nobody
/// mistakes simulated aircraft for the real sky.
struct RadarControlBar: View {
    let model: RadarModel
    /// Map view on, with no map pane beside the radar.
    let offersMap: Bool
    let showsMap: Bool
    let onToggleMap: () -> Void
    let onSkyView: () -> Void
    let onSearch: () -> Void
    let onLogbook: () -> Void
    let onSettings: () -> Void

    static let height: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            if offersMap {
                BarButton(title: showsMap ? "Radar" : "Map", action: onToggleMap) {
                    Image(systemName: showsMap ? "scope" : "map.fill")
                }
                .disabled(model.observer == nil)
                .accessibilityLabel(showsMap ? "Radar" : "Map")
                .accessibilityHint(showsMap ? "Shows the radar instead of the map" : "Shows a live map of the traffic instead of the radar")
                .accessibilityIdentifier("mapButton")
            }

            BarButton(title: "Sky View", action: onSkyView) {
                Image(systemName: "camera.viewfinder")
            }
            .accessibilityLabel("Sky View")
            .accessibilityHint("Opens the camera with every aircraft labeled where it is in the sky")
            .accessibilityIdentifier("skyViewButton")

            Rectangle()
                .fill(Palette.faint.opacity(0.5))
                .frame(width: 1, height: 26)
                .padding(.horizontal, 2)
                .accessibilityHidden(true)

            // The badge carries the label: "12 aircraft in range".
            BarButton(title: "Aircraft", isHighlighted: model.isDemo, action: onSearch) {
                StatusBadge(model: model, highlightsDemo: true, drawsCapsule: false)
            }
            .accessibilityHint("Search aircraft")
            .accessibilityIdentifier("aircraftButton")

            BarButton(title: "Logbook", action: onLogbook) {
                Image(systemName: "book.closed.fill")
            }
            .accessibilityLabel("Logbook")
            .accessibilityIdentifier("logbookButton")

            BarButton(title: "Settings", action: onSettings) {
                Image(systemName: "gearshape.fill")
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.horizontal, 5)
        .frame(height: Self.height)
        .glassSurface(in: Capsule())
        .fixedSize()
    }
}

/// One button on the bar: a symbol (or the live count) over a small mono caption.
private struct BarButton<Icon: View>: View {
    let title: String
    /// Demo traffic: a solid ink lozenge behind the count, paper type on it.
    var isHighlighted = false
    let action: () -> Void
    @ViewBuilder let icon: Icon

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                icon
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isHighlighted ? Palette.paper : Palette.ink)
                    .frame(height: 22)
                Text(title)
                    .font(.mono(9, .bold))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(isHighlighted ? Palette.paper.opacity(0.85) : Palette.caption)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 7)
            .frame(minWidth: 60)
            .frame(height: RadarControlBar.height - 10)
            .background {
                Capsule()
                    .fill(Palette.ink)
                    .shadow(color: Palette.ink.opacity(0.45), radius: 6)
                    .opacity(isHighlighted ? 1 : 0)
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }
}
#endif

/// All the screen geometry in one place. `scale` blows everything up for the 10-foot TV view.
struct RadarLayout {
    let size: CGSize
    let scale: CGFloat
    /// Ticks and N/E/S/W hug the safe-area edge.
    let bezelTrack: PerimeterTrack
    /// Icons ride just inside the bezel.
    let iconTrack: PerimeterTrack

    init(size: CGSize, scale: CGFloat = 1) {
        self.size = size
        self.scale = scale
        bezelTrack = PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: 5 * scale, dy: 5 * scale), cornerRadius: 40 * scale)
        iconTrack = PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: 27 * scale, dy: 27 * scale), cornerRadius: 34 * scale)
    }

    var heroWidth: CGFloat {
        max(200, size.width - 2 * 72 * scale)
    }

    /// Phones render the hero at 1×; iPads scale it up so it doesn't feel lost.
    var heroScale: CGFloat {
        min(1.7, max(1, min(size.width, size.height) / 430))
    }

    /// Room the hero leaves above and below it for the icons on the edge and their labels.
    var heroClearance: CGFloat { 64 * scale }

    /// `heroScale`, shrunk (in steps, never below 0.75) when a hero `height` tall wouldn't fit
    /// in `room` (the height between the top and bottom icons): the iPhone Duo's radar half,
    /// or its whole inner screen held flat in landscape. A height of 0 = not measured yet.
    func heroScale(fitting height: CGFloat, room: CGFloat) -> CGFloat {
        guard height > 0 else { return heroScale }
        let fit = (room / height * 20).rounded(.down) / 20
        return max(0.75, min(heroScale, fit))
    }

    /// Short and wide (the iPhone Duo's standing half in tabletop): altitude, speed and
    /// distance on one row, as on the TV.
    var prefersWideStats: Bool { size.width > size.height && size.height < 560 * scale }

    /// Shorter still (tabletop with the camera cutout along the top): drop the type line and
    /// the approach chip rather than shrink everything.
    var prefersCompactHero: Bool { size.height < 420 * scale }

    /// Apple TV: where the status badge sits, bottom-left.
    var statusPoint: CGPoint { iconTrack.point(at: iconTrack.arcLength(of: .bottomLeft)) }
    var noticeY: CGFloat { 84 * scale }
}

// MARK: - Chrome

struct StatusBadge: View {
    let model: RadarModel
    /// iPhone / iPad: demo traffic turns the badge into a solid ink pill so nobody mistakes
    /// simulated aircraft for the real sky. The TV keeps the plain glass badge.
    var highlightsDemo = false
    /// Off when it sits inside something that draws its own background (`RadarControlBar`).
    var drawsCapsule = true
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isHighlightedDemo: Bool { highlightsDemo && model.isDemo }

    private var color: Color {
        switch model.status {
        case .live: return model.isDemo ? (highlightsDemo ? Palette.paper : Palette.ink) : Palette.live
        case .loading, .idle: return Palette.warning
        case .error: return Palette.signal
        }
    }

    var body: some View {
        Group {
            if drawsCapsule {
                content
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background {
                        Capsule()
                            .fill(Palette.ink)
                            .shadow(color: Palette.ink.opacity(0.45), radius: 8)
                            .opacity(isHighlightedDemo ? 1 : 0)
                    }
                    .glassSurface(in: Capsule())
            } else {
                content
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever()) { blink = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("statusBadge")
    }

    private var content: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(blink ? 0.35 : 1)
            if isHighlightedDemo {
                Text("DEMO")
                    .font(.mono(13, .heavy))
                    .tracking(1.2)
            }
            Text(model.isDemo && !highlightsDemo ? "DEMO \(model.contacts.count)" : "\(model.contacts.count)")
                .font(.mono(13, .bold))
                .contentTransition(.numericText(value: Double(model.contacts.count)))
                .animation(.snappy, value: model.contacts.count)
        }
        .foregroundStyle(isHighlightedDemo ? Palette.paper : Palette.value)
    }

    private var accessibilityText: String {
        switch model.status {
        case .live: return "\(model.contacts.count) aircraft in range\(model.isDemo ? ", demo traffic" : "")"
        case .loading, .idle: return "Connecting"
        case .error(let message): return "Connection problem: \(message)"
        }
    }
}

/// "CUSTOM SPOT · ATLANTA, GA · NOT LOGGED" along the bottom of the screen.
struct CustomSpotTag: View {
    let name: String?
    let action: () -> Void

    var body: some View {
        BottomTag(symbol: "mappin.and.ellipse",
                  text: ["Custom spot", name, "not logged"].compactMap { $0 }.joined(separator: " · "),
                  color: Palette.warning,
                  action: action)
            .accessibilityLabel("Watching a custom spot\(name.map { ", \($0)" } ?? ""). Sightings here aren't logged.")
            .accessibilityHint("Pick a different spot")
    }
}

/// "DEMO TRAFFIC · SIMULATED AIRCRAFT · NOT LOGGED" along the bottom; tap to go live.
struct DemoTrafficTag: View {
    let action: () -> Void

    var body: some View {
        BottomTag(symbol: "theatermasks.fill",
                  text: "Demo traffic · simulated aircraft · not logged",
                  color: Palette.ink,
                  action: action)
            .accessibilityLabel("Demo traffic. These aircraft are simulated and aren't logged.")
            .accessibilityHint("Switch to live traffic")
    }
}

/// A one-line note along the bottom of the radar, just above the bar.
private struct BottomTag: View {
    let symbol: String
    let text: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(text)
                    .font(.mono(10, .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .paperHalo()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}

struct NoticeBanner: View {
    let model: RadarModel

    var body: some View {
        ZStack {
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Image(systemName: notice.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Palette.signal)
                    Text(notice.text)
                        .font(.mono(12, .semibold))
                        .foregroundStyle(Palette.value)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassSurface(in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation(.smooth) { model.dismissNotice(notice.id) }
                }
                .onTapGesture { withAnimation(.smooth) { model.dismissNotice(notice.id) } }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.notice)
    }
}
#endif
