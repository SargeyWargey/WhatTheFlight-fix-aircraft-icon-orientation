//
//  WatchRadarView.swift
//  WhatTheFlightWatch
//
//  The wrist radar. Same rules as the iPhone: the nearest aircraft takes the centre and keeps
//  it until it leaves the radius; the others ride the screen edge at their compass bearing,
//  turning with the wrist. Swipe left (or turn the Digital Crown) for farther aircraft, swipe
//  right to come back in; double tap (or "Nearest") returns to the closest one. Settings sit
//  above the radar and the Nearby list below it (vertical pages, see `WatchRootView`). The
//  pointer button opens Identify; holding it switches between Point and Aim.
//

import SwiftUI
import WatchKit

struct WatchRadarView: View {
    let model: RadarModel
    let settings: RadarSettings
    let watchSettings: WatchSettings
    let location: WatchLocationService
    /// The radar is the visible page; the crown goes back to it.
    let isActive: Bool
    let open: (WatchRootView.Screen) -> Void
    /// Turns to the Nearby page below the radar.
    let showNearby: () -> Void

    @State private var crown = 0
    @FocusState private var crownFocused: Bool
    /// The long press that switched aim styles also ends as a tap; that tap is ignored.
    @State private var ignoreNextPointerTap = false
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// "Up" on screen, in compass degrees.
    private var heading: Double {
        guard !watchSettings.northUp, let heading = location.heading else { return 0 }
        return heading
    }

    private var isOnNearest: Bool {
        model.focus.focusedID == nil || model.focus.focusedID == model.contacts.first?.id
    }

    /// What the centre shows when no aircraft owns it. Worked out here rather than in the
    /// root view: it reads the contacts, which change every second, and only the radar
    /// should redraw for that.
    private var centerState: WatchCenterState.Kind? {
        if model.observer == nil {
            if watchSettings.locationSource == .phone && watchSettings.phoneObserver == nil {
                return .noPhoneSpot
            }
            return location.isAuthorized ? .scanning : .needsLocation(denied: location.isDenied)
        }
        if model.focusedContact != nil { return nil }
        if let staleFor {
            if case .error(let message) = model.status { return .error(message) }
            return .error("Nothing from the feed for \(RadarFormat.countdown(staleFor)).")
        }
        switch model.status {
        case .error(let message) where !model.hasLoadedOnce: return .error(message)
        case .idle, .loading: return .scanning
        default: return model.hasLoadedOnce ? .clearSkies(radius: settings.radiusMiles) : .scanning
        }
    }

    /// How long the feed has been quiet, when the screen should say so. Not in Always-On:
    /// the model is paused on purpose there, and a poll follows the wrist coming up.
    private var staleFor: TimeInterval? {
        model.isStale && !isLuminanceReduced ? model.sinceLastUpdate : nil
    }

    var body: some View {
        GeometryReader { geo in
            let layout = WatchRadarLayout(size: geo.size)
            ZStack {
                backdrop(layout)

                if !isLuminanceReduced {
                    CompassBezel(track: layout.bezelTrack, heading: heading, scale: 0.75)
                        .opacity(0.8)
                }

                VStack(spacing: 6) {
                    if let contact = model.focusedContact {
                        WatchFlightHero(contact: contact, isPinned: model.focus.isPinned, isCompact: layout.isCompact,
                                        showNearest: !isOnNearest && !isLuminanceReduced,
                                        onNearest: backToNearest,
                                        staleFor: staleFor, onRetry: { model.refreshNow() })
                            .onTapGesture { open(.detail(contact.id)) }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                model.togglePin()
                                WatchHaptics.play(.click, enabled: settings.hapticsEnabled)
                            }
                    } else if let centerState {
                        WatchCenterState(kind: centerState, action: centerAction)
                    }
                    // At accessibility text sizes the edge icons are hidden: say what else is
                    // there, and go to the list.
                    if perimeterHidden, otherCount > 0 {
                        Button(action: showNearby) {
                            Text("\(otherCount) more nearby")
                                .font(.system(.footnote, design: .monospaced, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(Palette.signal)
                        .accessibilityHint("Shows the nearby list")
                    }
                }
                .frame(width: layout.centerWidth)
                .position(x: geo.size.width / 2, y: geo.size.height / 2 + layout.centerNudge)

                if !perimeterHidden {
                    WatchPerimeterLayer(
                        placements: PerimeterPlanner.plan(contacts: model.contacts, heading: heading, track: layout.iconTrack,
                                                          obstacles: layout.obstacles, scale: layout.blipScale,
                                                          maxIcons: WatchRadarLayout.maxIcons),
                        focusedID: model.focus.focusedID,
                        radiusMiles: settings.radiusMiles,
                        labelCount: layout.labelCount,
                        blipScale: layout.blipScale,
                        onTap: { contact in
                            withAnimation(.snappy) { model.focus(on: contact.id) }
                            WatchHaptics.play(.click, enabled: settings.hapticsEnabled)
                        },
                        onShowList: showNearby
                    )
                    .opacity(isLuminanceReduced ? 0.6 : 1)
                }
            }
            .contentShape(Rectangle())
            // Simultaneous, so the vertical page swipes still reach the TabView.
            .simultaneousGesture(swipe)
        }
        .ignoresSafeArea()
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(detent: $crown, from: -100_000, through: 100_000, by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in step(by: new - old) }
        .onAppear { crownFocused = true }
        .onChange(of: isActive) { _, active in
            if active { crownFocused = true }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
                pointerButton
            }
        }
        .accessibilityAction(named: "Nearest aircraft", backToNearest)
        .accessibilityAction(named: "Next aircraft") { step(by: 1) }
        .accessibilityAction(named: "Previous aircraft") { step(by: -1) }
    }

    /// Left: next aircraft farther out. Right: back toward the nearest. Mostly-vertical
    /// swipes are left to the pages.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 30, abs(dx) > abs(dy) * 1.5, !model.contacts.isEmpty else { return }
                step(by: dx < 0 ? 1 : -1)
                WatchHaptics.play(.click, enabled: settings.hapticsEnabled)
            }
    }

    private var pointerButton: some View {
        let style = watchSettings.aimStyle
        return Button {
            if ignoreNextPointerTap {
                ignoreNextPointerTap = false
                return
            }
            open(.identify)
        } label: {
            Image(systemName: style.symbol)
                .contentTransition(.symbolEffect(.replace))
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in toggleAimStyle() }
        )
        .accessibilityLabel("Identify: \(style == .point ? "point" : "aim") at a plane")
        .accessibilityHint("Hold to switch to \(style == .point ? "Aim" : "Point")")
        .accessibilityAction(named: "Switch to \(style == .point ? "Aim" : "Point")", toggleAimStyle)
    }

    private func toggleAimStyle() {
        ignoreNextPointerTap = true
        withAnimation(.snappy) {
            watchSettings.aimStyle = watchSettings.aimStyle == .point ? .aim : .point
        }
        // Always felt, even with alert haptics off: it's the only sign the mode changed.
        WatchHaptics.play(watchSettings.aimStyle == .aim ? .start : .stop)
        AccessibilityNotification.Announcement("Aim with \(watchSettings.aimStyle.title)").post()
        // If the press ended outside the button no tap follows; don't swallow the next one.
        Task {
            try? await Task.sleep(for: .seconds(1))
            ignoreNextPointerTap = false
        }
    }

    /// At accessibility text sizes the edge icons would crowd the hero; the list takes over.
    private var perimeterHidden: Bool { dynamicTypeSize.isAccessibilitySize }

    /// In range, not counting the aircraft in the centre.
    private var otherCount: Int {
        model.contacts.filter { $0.id != model.focus.focusedID }.count
    }

    @ViewBuilder
    private func backdrop(_ layout: WatchRadarLayout) -> some View {
        ZStack {
            Palette.paper
            RangeRings()
                .stroke(Palette.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            if settings.radarSweep && !reduceMotion && !isLuminanceReduced {
                RadarSweep()
                    .frame(width: layout.size.height * 1.3, height: layout.size.height * 1.3)
                    .position(x: layout.size.width / 2, y: layout.size.height / 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func step(by steps: Int) {
        guard steps != 0, !model.contacts.isEmpty else { return }
        withAnimation(.snappy) {
            for _ in 0..<abs(steps) {
                if steps > 0 { model.focusNext() } else { model.focusPrevious() }
            }
        }
    }

    private func backToNearest() {
        withAnimation(.snappy) { model.focusNearest() }
        WatchHaptics.play(.click, enabled: settings.hapticsEnabled)
    }

    private func centerAction() {
        switch centerState {
        case .needsLocation: location.requestPermission()
        case .noPhoneSpot: watchSettings.locationSource = .here
        case .error: model.refreshNow()
        default: break
        }
    }
}

// MARK: - Layout

/// Geometry for the Watch's rounded-rectangle screen.
struct WatchRadarLayout {
    static let maxIcons = 8

    let size: CGSize
    let iconTrack: PerimeterTrack
    let bezelTrack: PerimeterTrack

    init(size: CGSize) {
        self.size = size
        let isCompact = size.width < 185
        let iconInset: CGFloat = 22 * (isCompact ? 0.56 : 0.62)
        // The display's own corner radius, roughly.
        let displayCorner = min(size.width, size.height) * 0.25
        iconTrack = PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: iconInset, dy: iconInset),
                                   cornerRadius: max(0, displayCorner - iconInset * 0.6))
        bezelTrack = PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerRadius: displayCorner - 2)
    }

    /// 40–42 mm Watches.
    var isCompact: Bool { size.width < 185 }
    var blipScale: CGFloat { isCompact ? 0.56 : 0.62 }
    /// Mile labels on the nearest few only on small screens.
    var labelCount: Int { isCompact ? 4 : Self.maxIcons }
    private var iconInset: CGFloat { 22 * blipScale }

    /// The clock and the pointer button sit in the corners; icons go around them.
    var obstacles: [PerimeterTrack.Obstacle] {
        // The clock is wider than the round button.
        let corners: [(PerimeterTrack.Corner, CGFloat)] = [(.topRight, 34), (.bottomRight, 26)]
        return corners.map { PerimeterTrack.Obstacle(s: iconTrack.arcLength(of: $0.0), halfWidth: $0.1) }
    }

    /// Room for the hero between the edge icons and their labels.
    /// Never negative: the first layout pass can arrive with a zero size.
    var centerWidth: CGFloat { max(0, size.width - 2 * (iconInset + 22)) }
    var centerNudge: CGFloat { 2 }
}

// MARK: - Hero

struct WatchFlightHero: View {
    let contact: RadarContact
    let isPinned: Bool
    let isCompact: Bool
    let showNearest: Bool
    let onNearest: () -> Void
    /// Set while the feed is quiet: the approach chip gives way to "No signal", which
    /// retries on tap.
    var staleFor: TimeInterval? = nil
    var onRetry: () -> Void = {}

    private var flight: Flight { contact.flight }

    var body: some View {
        VStack(spacing: 1) {
            if let top = contact.profile.notable.first {
                NotableBadge(info: top, scale: 0.72)
                    .padding(.bottom, 2)
            }
            Text(contact.profile.operatorInfo.compact)
                .font(.mono(9, .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 3) {
                if isPinned {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.signal)
                }
                Text(flight.displayIdentifier)
                    .font(.mono(isCompact ? 22 : 26, .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if flight.hasRoute {
                HStack(spacing: 4) {
                    Text(flight.originIATA ?? "—")
                    Image(systemName: "arrow.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(Palette.signal)
                    Text(flight.destinationIATA ?? "—")
                }
                .font(.mono(13, .bold))
                .foregroundStyle(Palette.route)
            } else if let type = contact.profile.typeName ?? flight.typeCode {
                Text(type)
                    .font(.mono(10, .medium))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // One Text, so the whole line shrinks together on small screens.
            (Text("\(RadarFormat.wholeNumber(contact.altitudeFeet)) ft") + trend
                + Text(" · \(RadarFormat.miles(contact.distanceMiles)) mi"))
                .font(.mono(isCompact ? 10 : 11, .semibold))
                .foregroundStyle(Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 2)
            if !isCompact {
                Text("\(RadarFormat.wholeNumber(flight.groundSpeedKnots)) kts · \(GeoMath.cardinal(contact.bearing))")
                    .font(.mono(10))
                    .foregroundStyle(Palette.caption)
            }
            if let staleFor {
                WatchStaleChip(since: staleFor, retry: onRetry)
                    .padding(.top, 3)
            } else {
                WatchApproachChip(contact: contact)
                    .padding(.top, 3)
            }
            if showNearest {
                Button(action: onNearest) {
                    Label("Nearest", systemImage: "arrow.uturn.backward")
                        .font(.mono(10, .bold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.signal)
                .handGestureShortcut(.primaryAction)
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows details. Turn the crown for other aircraft.")
    }

    private var trend: Text {
        switch flight.verticalTrend {
        case .climbing: return Text(" \(Image(systemName: "arrow.up.right"))").font(.system(size: 8, weight: .heavy)).foregroundColor(Palette.live)
        case .descending: return Text(" \(Image(systemName: "arrow.down.right"))").font(.system(size: 8, weight: .heavy)).foregroundColor(Palette.warning)
        case .level: return Text("")
        }
    }

    private var accessibilityText: String {
        var parts = [contact.profile.operatorInfo.title, flight.displayIdentifier]
        if let from = flight.origin?.city ?? flight.originIATA, let to = flight.destination?.city ?? flight.destinationIATA {
            parts.append("\(from) to \(to)")
        }
        parts.append("\(RadarFormat.miles(contact.distanceMiles)) miles \(GeoMath.cardinal(contact.bearing))")
        parts.append("\(RadarFormat.wholeNumber(contact.altitudeFeet)) feet")
        if let staleFor {
            parts.append("no signal for \(RadarFormat.countdown(staleFor))")
        } else if contact.isApproaching, contact.closestApproach.secondsFromNow < 3600 {
            parts.append("closest pass in \(RadarFormat.countdown(contact.closestApproach.secondsFromNow))")
        }
        return parts.joined(separator: ", ")
    }
}

/// "OVERHEAD", "◎ 0:48 · 1 mi" (closest pass), or "Moving away".
struct WatchApproachChip: View {
    let contact: RadarContact
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        Group {
            if contact.distanceMiles < 0.75 {
                HStack(spacing: 4) {
                    Circle().fill(Palette.signal).frame(width: 5, height: 5).opacity(glow ? 0.25 : 1)
                    Text("OVERHEAD").font(.mono(10, .heavy)).tracking(1.2)
                }
                .foregroundStyle(Palette.signal)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.signal.opacity(0.16), in: Capsule())
                .onChange(of: [reduceMotion, isLuminanceReduced], initial: true) { _, _ in startGlow() }
            } else if contact.isApproaching, contact.closestApproach.secondsFromNow < 3600 {
                HStack(spacing: 3) {
                    Image(systemName: "scope").font(.system(size: 8, weight: .bold))
                    Text("\(RadarFormat.countdown(contact.closestApproach.secondsFromNow)) · \(RadarFormat.miles(contact.closestApproach.distanceMiles)) mi")
                        .font(.mono(10, .semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Palette.ink.opacity(0.14), in: Capsule())
            } else {
                Label("Moving away", systemImage: "arrow.up.forward")
                    .font(.mono(9, .medium))
                    .foregroundStyle(Palette.caption)
            }
        }
    }

    /// Stops while the wrist is down (Always-On): a repeating animation would otherwise
    /// keep running on the dimmed screen.
    private func startGlow() {
        glow = false
        guard !reduceMotion, !isLuminanceReduced else { return }
        withAnimation(.easeInOut(duration: 0.7).repeatForever()) { glow = true }
    }
}

/// The feed has gone quiet (`RadarModel.isStale`): what's on screen is dead-reckoned from
/// its last word, and the countdown would be a guess. Shows how long, and retries on tap.
struct WatchStaleChip: View {
    let since: TimeInterval
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            HStack(spacing: 3) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 8, weight: .bold))
                Text("NO SIGNAL · \(RadarFormat.countdown(since))")
                    .font(.mono(10, .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Palette.warning)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.warning.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No signal for \(RadarFormat.countdown(since))")
        .accessibilityHint("Retries the feed")
    }
}

// MARK: - Perimeter

struct WatchPerimeterLayer: View {
    let placements: [PerimeterPlacement]
    let focusedID: String?
    let radiusMiles: Double
    let labelCount: Int
    let blipScale: CGFloat
    let onTap: (RadarContact) -> Void
    /// VoiceOver's way into the list: the icons themselves aren't separate elements.
    let onShowList: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.favoriteAircraft) private var favorites

    var body: some View {
        ZStack {
            ForEach(Array(placements.enumerated()), id: \.element.id) { index, placement in
                let isFocused = placement.id == focusedID
                let fade = 1 - 0.4 * min(1, placement.contact.distanceMiles / max(radiusMiles, 1))

                if index < labelCount || isFocused {
                    DistanceLabel(miles: placement.contact.distanceMiles, isFocused: isFocused,
                                  profile: placement.contact.profile, scale: 0.78)
                        .opacity(isFocused ? 1 : fade)
                        .position(placement.labelPoint)
                        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.labelPoint)
                }

                AircraftBlip(profile: placement.contact.profile, screenTrack: placement.screenTrack, isFocused: isFocused,
                             isFavorite: favorites.contains(placement.contact.flight), scale: blipScale)
                    .opacity(isFocused ? 1 : fade)
                    .position(placement.point)
                    .animation(reduceMotion ? nil : .interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.point)
                    .onTapGesture { onTap(placement.contact) }
                    .zIndex(isFocused ? 2 : 1)
            }
        }
        .animation(.smooth(duration: 0.5), value: placements.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(placements.count > 1 ? "\(placements.count - 1) more aircraft. Use the list for details." : "")
        .accessibilityAction(named: "Show nearby list", onShowList)
    }
}

// MARK: - Empty states

struct WatchCenterState: View {
    enum Kind: Equatable {
        case needsLocation(denied: Bool)
        case noPhoneSpot
        case scanning
        case clearSkies(radius: Double)
        case error(String)
    }

    let kind: Kind
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            icon
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.ink)
            Text(title)
                .font(.mono(14, .bold))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.mono(10))
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
            if let button = buttonTitle {
                Button(button, action: action)
                    .font(.mono(11, .bold))
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ink)
                    .controlSize(.mini)
            }
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .needsLocation: Image(systemName: "location.slash")
        case .noPhoneSpot: Image(systemName: "iphone.slash")
        case .scanning: ProgressView().tint(Palette.ink)
        case .clearSkies: Image(systemName: "sun.haze")
        case .error: Image(systemName: "antenna.radiowaves.left.and.right.slash")
        }
    }

    private var title: String {
        switch kind {
        case .needsLocation: return "Where are you?"
        case .noPhoneSpot: return "No iPhone spot"
        case .scanning: return "Scanning…"
        case .clearSkies: return "Clear skies"
        case .error: return "No signal"
        }
    }

    private var message: String {
        switch kind {
        case .needsLocation(let denied):
            return denied ? "Turn on Location for What The Flight? in the Watch app on iPhone." : "Allow location to see what's overhead."
        case .noPhoneSpot: return "Open What The Flight? on your iPhone once to share its spot."
        case .scanning: return "Listening for aircraft"
        case .clearSkies(let radius): return "Nothing airborne within \(Int(radius)) mi."
        case .error(let text): return text
        }
    }

    private var buttonTitle: String? {
        switch kind {
        case .needsLocation(let denied): return denied ? nil : "Allow"
        case .noPhoneSpot: return "Use Here"
        case .error: return "Retry"
        default: return nil
        }
    }
}
