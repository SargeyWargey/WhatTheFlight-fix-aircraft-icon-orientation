//
//  WatchRadarView.swift
//  WhatTheFlightWatch
//
//  The wrist radar. Same rules as the iPhone: the nearest aircraft takes the centre and keeps
//  it until it leaves the radius; the others ride the screen edge at their compass bearing,
//  turning with the wrist. The Digital Crown steps out to farther aircraft and back in;
//  double tap (or "Nearest") returns to the closest one.
//

import SwiftUI
import WatchKit

struct WatchRadarView: View {
    let model: RadarModel
    let settings: RadarSettings
    let watchSettings: WatchSettings
    let location: WatchLocationService
    let centerState: WatchCenterState.Kind?
    let open: (WatchRootView.Screen) -> Void
    let retry: () -> Void

    @State private var crown = 0
    @FocusState private var crownFocused: Bool
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

    var body: some View {
        GeometryReader { geo in
            let layout = WatchRadarLayout(size: geo.size)
            ZStack {
                backdrop(layout)

                if !isLuminanceReduced {
                    CompassBezel(track: layout.bezelTrack, heading: heading, scale: 0.75)
                        .opacity(0.8)
                }

                Group {
                    if let contact = model.focusedContact {
                        WatchFlightHero(contact: contact, isPinned: model.focus.isPinned, isCompact: layout.isCompact,
                                        showNearest: !isOnNearest && !isLuminanceReduced,
                                        onNearest: backToNearest)
                            .onTapGesture { open(.detail(contact.id)) }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                model.togglePin()
                                WatchHaptics.play(.click, enabled: settings.hapticsEnabled)
                            }
                    } else if let centerState {
                        WatchCenterState(kind: centerState, action: retry)
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
                        }
                    )
                    .opacity(isLuminanceReduced ? 0.6 : 1)
                }

                if let notice = model.notice, !isLuminanceReduced {
                    NoticeCapsule(notice: notice)
                        .frame(maxWidth: max(0, geo.size.width - 40))
                        .position(x: geo.size.width / 2, y: layout.noticeY)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .task(id: notice.id) {
                            try? await Task.sleep(for: .seconds(3.5))
                            withAnimation { model.dismissNotice(notice.id) }
                        }
                }
            }
            .animation(.smooth, value: model.notice)
        }
        .ignoresSafeArea()
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(detent: $crown, from: -100_000, through: 100_000, by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in step(by: new - old) }
        .onAppear { crownFocused = true }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { open(.settings) } label: { Image(systemName: "gearshape.fill") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { open(.nearby) } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Nearby aircraft")
                Spacer()
                Button { open(.identify) } label: { Image(systemName: watchSettings.aimStyle.symbol) }
                    .accessibilityLabel("Identify: \(watchSettings.aimStyle == .point ? "point" : "aim") at a plane")
            }
        }
        .accessibilityAction(named: "Nearest aircraft", backToNearest)
        .accessibilityAction(named: "Next aircraft") { step(by: 1) }
    }

    /// At accessibility text sizes the edge icons would crowd the hero; the list takes over.
    private var perimeterHidden: Bool { dynamicTypeSize.isAccessibilitySize }

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
}

// MARK: - Layout

/// Geometry for the Watch's rounded-rectangle screen.
struct WatchRadarLayout {
    static let maxIcons = 8

    let size: CGSize

    /// 40–42 mm Watches.
    var isCompact: Bool { size.width < 185 }
    var blipScale: CGFloat { isCompact ? 0.56 : 0.62 }
    /// Mile labels on the nearest few only on small screens.
    var labelCount: Int { isCompact ? 4 : Self.maxIcons }
    private var iconInset: CGFloat { 22 * blipScale }
    /// The display's own corner radius, roughly.
    private var displayCorner: CGFloat { min(size.width, size.height) * 0.25 }

    var iconTrack: PerimeterTrack {
        PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: iconInset, dy: iconInset),
                       cornerRadius: max(0, displayCorner - iconInset * 0.6))
    }

    var bezelTrack: PerimeterTrack {
        PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3), cornerRadius: displayCorner - 2)
    }

    /// Settings, clock and the two bottom buttons sit in the corners; icons go around them.
    var obstacles: [PerimeterTrack.Obstacle] {
        let track = iconTrack
        // The clock is wider than the round buttons.
        let corners: [(PerimeterTrack.Corner, CGFloat)] = [(.topLeft, 26), (.topRight, 34), (.bottomLeft, 26), (.bottomRight, 26)]
        return corners.map { PerimeterTrack.Obstacle(s: track.arcLength(of: $0.0), halfWidth: $0.1) }
    }

    /// Room for the hero between the edge icons and their labels.
    /// Never negative: the first layout pass can arrive with a zero size.
    var centerWidth: CGFloat { max(0, size.width - 2 * (iconInset + 22)) }
    var centerNudge: CGFloat { 2 }
    var noticeY: CGFloat { size.height * 0.2 }
}

// MARK: - Hero

struct WatchFlightHero: View {
    let contact: RadarContact
    let isPinned: Bool
    let isCompact: Bool
    let showNearest: Bool
    let onNearest: () -> Void

    private var flight: Flight { contact.flight }

    var body: some View {
        VStack(spacing: 1) {
            if let top = flight.notable.first {
                NotableBadge(info: top, scale: 0.72)
                    .padding(.bottom, 2)
            }
            Text(flight.operatorInfo.compact)
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
            } else if let type = flight.typeName ?? flight.typeCode {
                Text(type)
                    .font(.mono(10, .medium))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // One Text, so the whole line shrinks together on small screens.
            (Text("\(RadarFormat.wholeNumber(flight.altitudeFeet)) ft") + trend
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
            WatchApproachChip(contact: contact)
                .padding(.top, 3)
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
        var parts = [flight.operatorInfo.title, flight.displayIdentifier]
        if let from = flight.origin?.city ?? flight.originIATA, let to = flight.destination?.city ?? flight.destinationIATA {
            parts.append("\(from) to \(to)")
        }
        parts.append("\(RadarFormat.miles(contact.distanceMiles)) miles \(GeoMath.cardinal(contact.bearing))")
        parts.append("\(RadarFormat.wholeNumber(flight.altitudeFeet)) feet")
        if contact.isApproaching, contact.closestApproach.secondsFromNow < 3600 {
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
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever()) { glow = true }
                }
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
}

// MARK: - Perimeter

struct WatchPerimeterLayer: View {
    let placements: [PerimeterPlacement]
    let focusedID: String?
    let radiusMiles: Double
    let labelCount: Int
    let blipScale: CGFloat
    let onTap: (RadarContact) -> Void

    var body: some View {
        ZStack {
            ForEach(Array(placements.enumerated()), id: \.element.id) { index, placement in
                let isFocused = placement.id == focusedID
                let fade = 1 - 0.4 * min(1, placement.contact.distanceMiles / max(radiusMiles, 1))

                if index < labelCount || isFocused {
                    DistanceLabel(miles: placement.contact.distanceMiles, isFocused: isFocused,
                                  kind: placement.contact.flight.kind, scale: 0.78)
                        .opacity(isFocused ? 1 : fade)
                        .position(placement.labelPoint)
                        .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.labelPoint)
                }

                AircraftBlip(kind: placement.contact.flight.kind, screenTrack: placement.screenTrack, isFocused: isFocused,
                             scale: blipScale, notable: placement.contact.flight.notable.first?.tag)
                    .opacity(isFocused ? 1 : fade)
                    .position(placement.point)
                    .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.point)
                    .onTapGesture { onTap(placement.contact) }
                    .zIndex(isFocused ? 2 : 1)
            }
        }
        .animation(.smooth(duration: 0.5), value: placements.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(placements.count > 1 ? "\(placements.count - 1) more aircraft. Use the list for details." : "")
    }
}

// MARK: - Notices & empty states

struct NoticeCapsule: View {
    let notice: RadarNotice

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: notice.symbol).font(.system(size: 10, weight: .bold))
            Text(notice.text).font(.mono(10, .semibold)).lineLimit(2).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Palette.value)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassSurface(in: Capsule())
    }
}

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
            return denied ? "Turn on Location for WhatTheFlight in the Watch app on iPhone." : "Allow location to see what's overhead."
        case .noPhoneSpot: return "Open WhatTheFlight on your iPhone once to share its spot."
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
