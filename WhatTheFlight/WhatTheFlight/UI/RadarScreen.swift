//
//  RadarScreen.swift
//  WhatTheFlight
//
//  The main screen. No cards, no chrome in the way: the focused flight in the middle,
//  every other aircraft on the edge, a status badge bottom-left and settings bottom-right.
//
//  Gestures
//    swipe →   back to the nearest aircraft      tap centre   flight details
//    swipe ←   next aircraft farther out         hold centre  pin / unpin
//    swipe ↓   search                            tap an icon  focus it
//    swipe ↑   settings                          hold an icon details
//

#if os(iOS) || os(tvOS)
import SwiftUI

#if os(iOS)
struct RadarScreen: View {
    let model: RadarModel
    let settings: RadarSettings
    let location: RadarLocationService
    let centerState: CenterStateView.Kind?
    let actions: Actions

    struct Actions {
        var openSettings: () -> Void
        var openSearch: () -> Void
        var openDetail: (String) -> Void
        var centerPrimary: () -> Void
        var centerSecondary: () -> Void
    }

    @Environment(\.scenePhase) private var scenePhase

    private var heading: Double { location.heading ?? 0 }

    var body: some View {
        GeometryReader { geo in
            let layout = RadarLayout(size: geo.size)
            let obstacles = layout.obstacles
            let placements = PerimeterPlanner.plan(contacts: model.contacts, heading: heading, track: layout.iconTrack, obstacles: obstacles)

            ZStack {
                if settings.showCompassBezel {
                    CompassBezel(track: layout.bezelTrack, heading: heading)
                        .animation(.interactiveSpring(response: 0.45, dampingFraction: 0.86), value: heading)
                }

                center
                    .frame(width: layout.heroWidth / layout.heroScale)
                    .scaleEffect(layout.heroScale)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                PerimeterLayer(
                    placements: placements,
                    focusedID: model.focus.focusedID,
                    radiusMiles: settings.radiusMiles,
                    onTap: { contact in
                        withAnimation(.snappy) { model.focus(on: contact.id) }
                    },
                    onLongPress: { contact in actions.openDetail(contact.id) }
                )

                StatusBadge(model: model)
                    .position(layout.statusPoint)

                SettingsButton(action: actions.openSettings)
                    .position(layout.gearPoint)

                NoticeBanner(model: model)
                    .frame(width: layout.heroWidth + 40)
                    .position(x: geo.size.width / 2, y: layout.noticeY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background {
            RadarBackdrop(
                showTopography: settings.showTopography,
                showSweep: settings.radarSweep,
                isActive: scenePhase == .active
            )
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .gesture(swipe)
        .sensoryFeedback(.selection, trigger: model.focus.focusedID) { _, _ in settings.hapticsEnabled }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.focus.isPinned) { _, _ in settings.hapticsEnabled }
    }

    // MARK: Centre

    @ViewBuilder
    private var center: some View {
        ZStack {
            if let centerState {
                CenterStateView(kind: centerState, onPrimary: actions.centerPrimary, onSecondary: actions.centerSecondary)
                    .transition(.opacity)
            } else if let contact = model.focusedContact {
                FlightHero(contact: contact, isPinned: model.focus.isPinned, heading: heading)
                    .id(contact.id)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity),
                        removal: .opacity
                    ))
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
                    actions.openSearch()
                } else if dy < -threshold {
                    actions.openSettings()
                }
            }
    }
}
#endif

/// All the screen geometry in one place. `scale` blows everything up for the 10-foot TV view.
struct RadarLayout {
    let size: CGSize
    var scale: CGFloat = 1

    /// Ticks and N/E/S/W hug the safe-area edge.
    var bezelTrack: PerimeterTrack {
        PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: 5 * scale, dy: 5 * scale), cornerRadius: 40 * scale)
    }

    /// Icons ride just inside the bezel.
    var iconTrack: PerimeterTrack {
        PerimeterTrack(rect: CGRect(origin: .zero, size: size).insetBy(dx: 27 * scale, dy: 27 * scale), cornerRadius: 34 * scale)
    }

    var heroWidth: CGFloat {
        max(200, size.width - 2 * 72 * scale)
    }

    /// Phones render the hero at 1×; iPads scale it up so it doesn't feel lost.
    var heroScale: CGFloat {
        min(1.7, max(1, min(size.width, size.height) / 430))
    }

    var gearPoint: CGPoint { iconTrack.point(at: iconTrack.arcLength(of: .bottomRight)) }
    var statusPoint: CGPoint { iconTrack.point(at: iconTrack.arcLength(of: .bottomLeft)) }
    var noticeY: CGFloat { 84 * scale }

    var obstacles: [PerimeterTrack.Obstacle] {
        [
            .init(s: iconTrack.arcLength(of: .bottomRight), halfWidth: 26 * scale),
            .init(s: iconTrack.arcLength(of: .bottomLeft), halfWidth: 38 * scale),
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
    @State private var blink = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var color: Color {
        switch model.status {
        case .live: return model.isDemo ? Palette.ink : Palette.live
        case .loading, .idle: return Palette.warning
        case .error: return Palette.signal
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .opacity(blink ? 0.35 : 1)
            Text(model.isDemo ? "DEMO \(model.contacts.count)" : "\(model.contacts.count)")
                .font(.mono(13, .bold))
                .foregroundStyle(Palette.value)
                .contentTransition(.numericText(value: Double(model.contacts.count)))
                .animation(.snappy, value: model.contacts.count)
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .glassSurface(in: Capsule())
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever()) { blink = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("statusBadge")
    }

    private var accessibilityText: String {
        switch model.status {
        case .live: return "\(model.contacts.count) aircraft in range\(model.isDemo ? ", demo traffic" : "")"
        case .loading, .idle: return "Connecting"
        case .error(let message): return "Connection problem: \(message)"
        }
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
