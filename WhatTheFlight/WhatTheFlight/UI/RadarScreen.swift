//
//  RadarScreen.swift
//  WhatTheFlight
//
//  The main screen. No cards, no chrome in the way: the focused flight in the middle,
//  every other aircraft on the edge, a status pill bottom-left (tap the count: Aircraft
//  search; tap the book: the logbook) and settings bottom-right. Demo traffic (a solid DEMO
//  pill) and a custom spot each get a tag along the bottom.
//
//  Gestures
//    swipe →   back to the nearest aircraft      tap centre   flight details
//    swipe ←   next aircraft farther out         hold centre  pin / unpin
//    swipe ↓   logbook                           tap an icon  focus it
//    swipe ↑   settings                          hold an icon details
//

#if os(iOS) || os(tvOS)
import SwiftUI

#if os(iOS)
struct RadarScreen: View {
    let model: RadarModel
    let settings: RadarSettings
    let location: RadarLocationService
    /// Read in this view's body, so the per-tick traffic it depends on redraws the radar
    /// screen only, not the root view and whatever sheet it's presenting.
    let centerState: () -> CenterStateView.Kind?
    let actions: Actions

    struct Actions {
        var openSettings: () -> Void
        /// Swipe down, or the book on the status pill.
        var openLogbook: () -> Void
        var openDetail: (String) -> Void
        /// The count on the status pill: Aircraft search, full height.
        var openSearchFullHeight: () -> Void
        var openSpotPicker: () -> Void
        var centerPrimary: () -> Void
        var centerSecondary: () -> Void
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusWidth: CGFloat = 52
    @State private var confirmLiveTraffic = false
    /// The hero's height before scaling, so it can shrink to fit a short radar.
    @State private var heroHeight: CGFloat = 0
    /// The demo / custom-spot tags along the bottom (0 = none showing).
    @State private var tagsHeight: CGFloat = 0
    /// Without a home-indicator strip the tags sit this far up from the bottom, inside the bezel.
    private static let tagsLift: CGFloat = 46

    private var heading: Double { location.heading ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let layout = RadarLayout(size: geo.size)
            let obstacles = layout.obstacles(statusWidth: statusWidth)
            let placements = PerimeterPlanner.plan(contacts: model.perimeterContacts, heading: heading, track: layout.iconTrack, obstacles: obstacles)

            ZStack {
                if settings.showCompassBezel {
                    CompassBezel(track: layout.bezelTrack, heading: heading)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.45, dampingFraction: 0.86), value: heading)
                }

                // Tags inside the bezel (no home-indicator strip, e.g. the iPhone Duo's standing
                // half in tabletop) push the hero up out of their way.
                let tagsInside = geo.safeAreaInsets.bottom < 20 && tagsHeight > 0
                let bottomRoom = tagsInside ? max(layout.heroClearance, Self.tagsLift + tagsHeight + 8) : layout.heroClearance
                let heroScale = layout.heroScale(fitting: heroHeight, room: geo.size.height - layout.heroClearance - bottomRoom)
                center(layout)
                    .frame(width: layout.heroWidth / heroScale)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
                    .scaleEffect(heroScale)
                    .position(x: geo.size.width / 2, y: (layout.heroClearance + geo.size.height - bottomRoom) / 2)

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

                RadarStatusPill(model: model, onSearch: actions.openSearchFullHeight, onLogbook: actions.openLogbook)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { statusWidth = $0 }
                // Pinned by its left edge so a wider badge grows into the screen, not off it.
                .frame(width: geo.size.width / 2, alignment: .leading)
                .position(x: layout.statusLeading + geo.size.width / 4, y: layout.statusPoint.y)

                SettingsButton(action: actions.openSettings)
                    .position(layout.gearPoint)

                NoticeBanner(model: model)
                    .frame(width: layout.heroWidth + 40)
                    .position(x: geo.size.width / 2, y: layout.noticeY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if model.isDemo {
                        DemoTrafficTag { confirmLiveTraffic = true }
                    }
                    if settings.locationMode == .custom {
                        CustomSpotTag(name: settings.customPlaceName ?? settings.customCoordinate?.shortDescription,
                                      action: actions.openSpotPicker)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tagsHeight = $0 }
                // In the home-indicator strip when there is one, else just above the bezel.
                .offset(y: geo.safeAreaInsets.bottom >= 20 ? geo.safeAreaInsets.bottom - 6 : -Self.tagsLift)
            }
        }
        .confirmationDialog("Demo traffic", isPresented: $confirmLiveTraffic, titleVisibility: .visible) {
            Button("Switch to Live Traffic") { settings.demoTraffic = false }
        } message: {
            Text("These aircraft are simulated, not what's really overhead, and they aren't logged.")
        }
        .background {
            RadarBackdrop(
                showTopography: settings.showTopography,
                showSweep: settings.radarSweep,
                isActive: scenePhase == .active,
                topographyMotion: settings.topographyMotion
            )
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.selection, trigger: model.focus.focusedID) { _, _ in settings.hapticsEnabled }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.pins.count) { _, _ in settings.hapticsEnabled }
    }

    // MARK: Centre

    @ViewBuilder
    private func center(_ layout: RadarLayout) -> some View {
        let centerState = centerState()
        ZStack {
            if let centerState {
                CenterStateView(kind: centerState, onPrimary: actions.centerPrimary, onSecondary: actions.centerSecondary)
                    .transition(.opacity)
            } else if let contact = model.focusedContact {
                FlightHero(contact: contact, isPinned: model.focus.isPinned, heading: heading,
                           wideStats: layout.prefersWideStats, compact: layout.prefersCompactHero)
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

    // MARK: Gestures

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                let threshold: CGFloat = 60
                if abs(dx) > abs(dy) {
                    if dx > threshold {
                        withAnimation(.snappy) { model.focusNearest() }
                    } else if dx < -threshold {
                        withAnimation(.snappy) { model.focusNext() }
                    }
                } else if dy > threshold {
                    actions.openLogbook()
                } else if dy < -threshold {
                    actions.openSettings()
                }
            }
    }
}
#endif

#if os(iOS)
/// The bottom-left pill on iPhone and iPad: the aircraft count (tap: Aircraft search) and a
/// book (tap: the logbook), one capsule so the radar keeps a single control in that corner.
struct RadarStatusPill: View {
    let model: RadarModel
    let onSearch: () -> Void
    let onLogbook: () -> Void

    var body: some View {
        let demo = model.isDemo
        HStack(spacing: 0) {
            Button(action: onSearch) {
                StatusBadge(model: model, highlightsDemo: true, drawsCapsule: false)
                    .padding(.leading, 11)
                    .padding(.trailing, 9)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Search aircraft")

            Rectangle()
                .fill((demo ? Palette.paper : Palette.value).opacity(0.25))
                .frame(width: 1, height: 16)
                .accessibilityHidden(true)

            Button(action: onLogbook) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(demo ? Palette.paper : Palette.ink)
                    .frame(width: 38, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Logbook")
            .accessibilityIdentifier("logbookButton")
        }
        .background {
            Capsule()
                .fill(Palette.ink)
                .shadow(color: Palette.ink.opacity(0.45), radius: 8)
                .opacity(demo ? 1 : 0)
        }
        .glassSurface(in: Capsule())
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

    var gearPoint: CGPoint { iconTrack.point(at: iconTrack.arcLength(of: .bottomRight)) }
    var statusPoint: CGPoint { iconTrack.point(at: iconTrack.arcLength(of: .bottomLeft)) }
    /// iPhone / iPad: the status badge's left edge, mirroring the gear's right edge. The badge
    /// grows rightward from here ("DEMO 12" is twice as wide as "12"), so it never runs off.
    var statusLeading: CGFloat { statusPoint.x - 22 * scale }
    var noticeY: CGFloat { 84 * scale }

    /// The gear, and the status badge as far along the bottom edge as it actually reaches.
    func obstacles(statusWidth: CGFloat) -> [PerimeterTrack.Obstacle] {
        let corner = iconTrack.arcLength(of: .bottomLeft)
        let halfCorner = CGFloat.pi / 4 * iconTrack.cornerRadius
        let curveEnds = iconTrack.rect.minX + iconTrack.cornerRadius
        // Up the left side the badge never reaches past the corner; along the bottom
        // (lower arc length) it reaches its right end plus room for an icon.
        let up = 38 * scale
        let along = max(up, halfCorner + statusLeading + statusWidth + 14 * scale - curveEnds)
        return [
            .init(s: iconTrack.arcLength(of: .bottomRight), halfWidth: 26 * scale),
            .init(s: corner + (up - along) / 2, halfWidth: (up + along) / 2),
        ]
    }
}

// MARK: - Chrome

struct SettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.caption)
                .frame(width: 44, height: 44)
                .glassSurface(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("settingsButton")
    }
}

struct StatusBadge: View {
    let model: RadarModel
    /// iPhone / iPad: demo traffic turns the badge into a solid ink pill so nobody mistakes
    /// simulated aircraft for the real sky. The TV keeps the plain glass badge.
    var highlightsDemo = false
    /// Off when it sits inside a bigger pill that draws the capsule (`RadarStatusPill`).
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

/// A one-line note along the bottom of the radar, clear of the badge and the gear.
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
        .padding(.horizontal, 60)
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
