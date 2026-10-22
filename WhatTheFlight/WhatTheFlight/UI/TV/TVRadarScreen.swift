//
//  TVRadarScreen.swift
//  WhatTheFlight
//
//  The radar on the big screen. Same look as the phone, laid out for landscape and the
//  10-foot view. "Up" on the TV is the direction you face when you watch it.
//
//  Siri Remote
//    ◀ ▶      closer / farther aircraft      click      details
//    ⏯        pin / unpin                    ▼          dock: Nearest · Pin · Aircraft · Logbook · Settings
//
//  The remote hints sit in a footer below the bezel; the dock only appears after ▼.
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
    }

    enum DockItem: CaseIterable {
        case nearest, pin, aircraft, logbook, settings
    }

    @FocusState private var focus: Focus?
    @State private var showDock = false
    @Environment(\.scenePhase) private var scenePhase

    private static let scale: CGFloat = 1.7
    private static let heroScale: CGFloat = 1.55

    private var heading: Double { settings.tvFacingDegrees }

    var body: some View {
        GeometryReader { geo in
            let layout = RadarLayout(size: geo.size, scale: Self.scale)
            let placements = PerimeterPlanner.plan(
                contacts: model.contacts,
                heading: heading,
                track: layout.iconTrack,
                obstacles: [
                    .init(s: layout.iconTrack.arcLength(of: .bottomRight), halfWidth: 84),
                    .init(s: layout.iconTrack.arcLength(of: .bottomLeft), halfWidth: 70),
                ],
                scale: Self.scale
            )
            let heroWidth = geo.size.width * 0.62

            ZStack {
                if settings.showCompassBezel {
                    CompassBezel(track: layout.bezelTrack, heading: heading, scale: Self.scale)
                        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: heading)
                }

                PerimeterLayer(
                    placements: placements,
                    focusedID: model.focus.focusedID,
                    radiusMiles: settings.radiusMiles,
                    scale: Self.scale,
                    onTap: { _ in },
                    onLongPress: { _ in }
                )
                .animation(.spring(response: 0.6, dampingFraction: 0.85), value: heading)

                center(width: heroWidth)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.47)

                if centerState == nil {
                    if showDock {
                        dock
                            .position(x: geo.size.width / 2, y: geo.size.height - 130)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    RemoteHints(dockIsOpen: showDock, isPinned: model.focus.isPinned)
                        .position(x: geo.size.width / 2, y: Self.footerY(in: geo))
                }

                StatusBadge(model: model)
                    .scaleEffect(1.6)
                    .position(layout.statusPoint)

                NoticeBanner(model: model)
                    .scaleEffect(1.6)
                    .frame(width: 700)
                    .position(x: geo.size.width / 2, y: 70)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background {
            RadarBackdrop(showTopography: settings.showTopography, showSweep: settings.radarSweep, isActive: scenePhase == .active)
                .ignoresSafeArea()
        }
        .defaultFocus($focus, .radar)
        .onChange(of: focus) { _, newValue in
            // Leaving the dock (MENU, or ▲ back to the aircraft) tucks it away again.
            if case .dock = newValue { return }
            withAnimation(.smooth(duration: 0.25)) { showDock = false }
        }
        .onChange(of: centerState) { _, _ in showDock = false }
        #if DEBUG
        .task {
            // `-wtf.debugDock YES` opens the dock for screenshots.
            guard UserDefaults.standard.bool(forKey: "wtf.debugDock") else { return }
            try? await Task.sleep(for: .seconds(4))
            openDock()
        }
        #endif
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
                Button {
                    actions.openDetail(contact.id)
                } label: {
                    FlightHero(contact: contact, isPinned: model.focus.isPinned, heading: heading, wideStats: true, detailScale: 1.4)
                        .id(contact.id)
                        .frame(width: width / Self.heroScale)
                        .scaleEffect(Self.heroScale)
                        .frame(width: width, height: 640)
                        .transition(.opacity)
                }
                .buttonStyle(TVQuietButtonStyle())
                .focused($focus, equals: .radar)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: withAnimation(.snappy) { model.focusPrevious() }
                    case .right: withAnimation(.snappy) { model.focusNext() }
                    case .down: openDock()
                    default: break
                    }
                }
                .onPlayPauseCommand {
                    withAnimation(.snappy) { model.togglePin() }
                }
                .accessibilityHint("Left and right change aircraft. Click for details.")
            }
        }
        .animation(.smooth(duration: 0.35), value: model.focus.focusedID)
        .animation(.smooth(duration: 0.35), value: centerState)
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
            dockButton(.pin, title: model.focus.isPinned ? "Unpin" : "Pin", symbol: model.focus.isPinned ? "lock.open.fill" : "lock.fill") {
                withAnimation(.snappy) { model.togglePin() }
            }
            dockButton(.aircraft, title: "Aircraft", symbol: "list.bullet") {
                actions.openAircraft()
            }
            dockButton(.logbook, title: "Logbook", symbol: "book.closed.fill") {
                actions.openLogbook()
            }
            dockButton(.settings, title: "Settings", symbol: "gearshape.fill") {
                actions.openSettings(.location)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
        .glassSurface(in: Capsule())
        .focusSection()
        .onExitCommand { focus = .radar }
    }

    private func dockButton(_ item: DockItem, title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(TVPillButtonStyle(prominent: false, compact: true))
        .focused($focus, equals: .dock(item))
    }
}

/// "◀ ▶ Aircraft · ● Details · ⏯ Pin · ▼ More", drawn with SF Symbols in key caps.
private struct RemoteHints: View {
    let dockIsOpen: Bool
    let isPinned: Bool

    var body: some View {
        HStack(spacing: 40) {
            if dockIsOpen {
                hint(["chevron.backward"], "Back")
            } else {
                hint(["arrowtriangle.left.fill", "arrowtriangle.right.fill"], "Aircraft")
                hint(["circle.circle"], "Details")
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
