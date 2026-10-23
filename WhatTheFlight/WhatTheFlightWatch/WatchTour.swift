//
//  WatchTour.swift
//  WhatTheFlightWatch
//
//  The Watch's first-run tour, vertical pages turned with the Digital Crown. The radar
//  works like the iPhone's, so those pages are quick (swipes, taps). The pointer button
//  gets more: a working copy to tap and hold, then Point and Aim acted out — the arm comes
//  up, the Watch taps your wrist, names the plane and says what it would read aloud —
//  and Find. The last page picks a style and can open Identify for real.
//

import SwiftUI
import WatchKit

struct WatchTourView: View {
    let settings: RadarSettings
    @Bindable var watchSettings: WatchSettings
    let onDone: () -> Void
    let onTryIdentify: () -> Void

    enum Page: Int, CaseIterable, Hashable {
        case welcome, swipes, taps, pointer, point, aim, find, done
    }

    #if DEBUG
    /// `-wtf.debugTourPage 4` opens the tour on that page (screenshots).
    @State private var page = Page(rawValue: UserDefaults.standard.integer(forKey: "wtf.debugTourPage")) ?? .welcome
    #else
    @State private var page: Page = .welcome
    #endif

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                welcome.tag(Page.welcome)
                swipes.tag(Page.swipes)
                taps.tag(Page.taps)
                pointer.tag(Page.pointer)
                point.tag(Page.point)
                aim.tag(Page.aim)
                find.tag(Page.find)
                done.tag(Page.done)
            }
            .tabViewStyle(.verticalPage)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip", action: onDone)
                        .accessibilityLabel("Skip the tour")
                }
            }
        }
    }

    // MARK: Quick pages

    private var welcome: some View {
        TourCard(title: "Your wrist radar",
                 text: "The same radar as your iPhone: icons on the edge point at real aircraft, the number is miles, the nearest takes the center. Turn the Crown for the rest.") {
            MiniWatchRadar()
        }
    }

    private var swipes: some View {
        TourCard(title: "Swipe around",
                 text: "Left (or turn the Crown) for the next aircraft out, right to come back in. Up for the Nearby list, down for Settings.") {
            SwipeDemo()
        }
    }

    private var taps: some View {
        TourCard(title: "Tap, hold, double tap", text: nil) {
            VStack(alignment: .leading, spacing: 8) {
                row("hand.tap.fill", "Tap the center", "details")
                row("lock.fill", "Hold the center", "pin it")
                row("hand.pinch.fill", "Double tap", "back to nearest")
            }
            .padding(.top, 4)
        }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.signal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.mono(12, .bold)).foregroundStyle(Palette.value)
                Text(detail).font(.mono(10)).foregroundStyle(Palette.caption)
            }
        }
    }

    // MARK: The pointer button

    private var pointer: some View {
        TourCard(title: "The pointer button",
                 text: "Bottom right of the radar. Tap it and the Watch names the plane you point at. Hold it to switch between Point and Aim. Try it here.") {
            PointerButtonDemo(watchSettings: watchSettings) {
                withAnimation { page = watchSettings.aimStyle == .point ? .point : .aim }
            }
        }
    }

    private var point: some View {
        TourCard(title: "Point",
                 text: "Arm out, fingers at the plane: your forearm is the pointer. Hold still for half a second — a tap on your wrist, its name on screen, and it's read aloud. The screen turns so you can read it, but watchOS may dim it.") {
            IdentifyScene(style: .point, hapticsEnabled: settings.hapticsEnabled)
        }
    }

    private var aim: some View {
        TourCard(title: "Aim",
                 text: "Hold the Watch as if reading the time and line up its top edge — the red arrow — with the plane. Turn your body to swing round, tilt your wrist to go higher. The screen faces you, so it stays bright.") {
            IdentifyScene(style: .aim, hapticsEnabled: settings.hapticsEnabled)
        }
    }

    private var find: some View {
        TourCard(title: "Find in the Sky",
                 text: "From a flight's details or an alert, Find guides you to that one plane: clicks as you swing round, up and down taps for height, one firm tap when you're on it.") {
            FindDemo()
        }
    }

    private var done: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Pick your style")
                    .font(.mono(15, .heavy))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 6) {
                    ForEach([WristPointing.AimStyle.point, .aim], id: \.self) { style in
                        let selected = watchSettings.aimStyle == style
                        Button {
                            withAnimation(.snappy) { watchSettings.aimStyle = style }
                            WatchHaptics.play(.click)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: style.symbol).font(.system(size: 18, weight: .semibold))
                                Text(style.title).font(.mono(11, .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selected ? Color.white : Palette.ink)
                            .background(selected ? Palette.ink : Palette.ink.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Text("Change it any time: hold the pointer button.")
                    .font(.mono(9))
                    .foregroundStyle(Palette.caption)
                    .multilineTextAlignment(.center)
                Button(action: onTryIdentify) {
                    Label("Try Identify", systemImage: watchSettings.aimStyle.symbol)
                }
                .tint(Palette.ink)
                .padding(.top, 4)
                Button("Start Watching", action: onDone)
                    .tint(Palette.signal)
            }
            .padding(.horizontal, 4)
        }
    }
}

/// A title, a drawing and a few lines underneath. Scrolls when the text runs long.
private struct TourCard<Art: View>: View {
    let title: String
    let text: String?
    @ViewBuilder let art: Art

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(title)
                    .font(.mono(15, .heavy))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                art
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                if let text {
                    Text(text)
                        .font(.mono(11))
                        .foregroundStyle(Palette.value)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Drawings

/// Made-up traffic around the little Watch radar: bearing, miles, track.
private let tourBlips: [(bearing: Double, miles: Int, track: Double, silhouette: AircraftSilhouette)] = [
    (35, 4, 250, .airliner), (215, 6, 80, .helicopter), (160, 11, 15, .widebody), (322, 14, 140, .regional),
]

/// A Watch-shaped radar with the nearest aircraft in the middle.
private struct MiniWatchRadar: View {
    var body: some View {
        WatchOutline(width: 92, height: 110) { size in
            ZStack {
                RangeRings().stroke(Palette.ink.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                ForEach(Array(tourBlips.enumerated()), id: \.offset) { index, blip in
                    let focused = index == 0
                    AircraftGlyph(silhouette: blip.silhouette, size: 15, spinsRotor: false)
                        .foregroundStyle(focused ? Palette.signal : Palette.blip)
                        .rotationEffect(.degrees(blip.track))
                        .position(edgePoint(blip.bearing, size: size, inset: 10))
                    Text("\(blip.miles)")
                        .font(.mono(8, .bold))
                        .foregroundStyle(focused ? Palette.signal : Palette.blip)
                        .position(edgePoint(blip.bearing, size: size, inset: 23))
                }
                VStack(spacing: 1) {
                    Text("DL1199").font(.mono(14, .heavy)).foregroundStyle(Palette.ink)
                    Text("ATL → ORD").font(.mono(7, .semibold)).foregroundStyle(Palette.route)
                    Text("4 MI").font(.mono(7, .bold)).foregroundStyle(Palette.signal)
                }
            }
        }
    }
}

/// Where a ray from the middle at `bearing` (0 = up) meets the edge, `inset` in.
private func edgePoint(_ bearing: Double, size: CGSize, inset: CGFloat) -> CGPoint {
    let radians = bearing * .pi / 180
    let dx = sin(radians), dy = -cos(radians)
    let halfW = size.width / 2 - inset, halfH = size.height / 2 - inset
    let t = min(abs(dx) > 0.001 ? halfW / abs(dx) : .infinity, abs(dy) > 0.001 ? halfH / abs(dy) : .infinity)
    return CGPoint(x: size.width / 2 + t * dx, y: size.height / 2 + t * dy)
}

/// A little Watch: rounded screen, a case around it, a crown on the right.
private struct WatchOutline<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        content(CGSize(width: width, height: height))
            .frame(width: width, height: height)
            .background(Palette.paper)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.24, style: .continuous))
            .padding(4)
            .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: width * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: width * 0.28, style: .continuous).stroke(Color(white: 0.4), lineWidth: 1))
            .overlay(alignment: .trailing) {
                Capsule().fill(Color(white: 0.4)).frame(width: 4, height: 16).offset(x: 3, y: -height * 0.18)
            }
    }
}

/// A finger swipes each way in turn; the caption says what that swipe does.
private struct SwipeDemo: View {
    private static let moves: [(dx: CGFloat, dy: CGFloat, arrow: String, label: String)] = [
        (-1, 0, "arrow.left", "Next out"),
        (1, 0, "arrow.right", "Back in"),
        (0, -1, "arrow.up", "Nearby list"),
        (0, 1, "arrow.down", "Settings"),
    ]
    private static let period = 1.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let index = reduceMotion ? 0 : Int(t / Self.period) % Self.moves.count
            let progress = reduceMotion ? 0.5 : (t / Self.period).truncatingRemainder(dividingBy: 1)
            let move = Self.moves[index]
            VStack(spacing: 4) {
                WatchOutline(width: 70, height: 84) { _ in
                    ZStack {
                        RangeRings().stroke(Palette.ink.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        Circle()
                            .fill(Palette.ink.opacity(0.3))
                            .overlay(Circle().stroke(Palette.ink.opacity(0.7), lineWidth: 1.5))
                            .frame(width: 18, height: 18)
                            .offset(x: move.dx * (-22 + 44 * progress), y: move.dy * (-26 + 52 * progress))
                            .opacity(sin(progress * .pi))
                    }
                }
                Label(move.label, systemImage: move.arrow)
                    .font(.mono(11, .bold))
                    .foregroundStyle(Palette.signal)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: index)
            }
        }
    }
}

/// A working copy of the radar's pointer button: tap goes to its page, hold switches style.
private struct PointerButtonDemo: View {
    @Bindable var watchSettings: WatchSettings
    let onTap: () -> Void
    @State private var ignoreNextTap = false

    var body: some View {
        VStack(spacing: 5) {
            WatchOutline(width: 92, height: 72) { size in
                ZStack(alignment: .bottomTrailing) {
                    RangeRings().stroke(Palette.ink.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    Text("DL1199")
                        .font(.mono(12, .heavy))
                        .foregroundStyle(Palette.ink.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Button {
                        if ignoreNextTap { ignoreNextTap = false; return }
                        onTap()
                    } label: {
                        Image(systemName: watchSettings.aimStyle.symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.ink.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in toggle() })
                    .padding(6)
                    .accessibilityLabel("Pointer button")
                    .accessibilityHint("Hold to switch to \(watchSettings.aimStyle == .point ? "Aim" : "Point")")
                }
            }
            HStack(spacing: 6) {
                ForEach([WristPointing.AimStyle.point, .aim], id: \.self) { style in
                    Text(style.title)
                        .font(.mono(10, .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .foregroundStyle(watchSettings.aimStyle == style ? Color.white : Palette.caption)
                        .background(watchSettings.aimStyle == style ? Palette.signal : Color.clear, in: Capsule())
                }
            }
            .animation(.snappy, value: watchSettings.aimStyle)
        }
    }

    private func toggle() {
        ignoreNextTap = true
        withAnimation(.snappy) { watchSettings.aimStyle = watchSettings.aimStyle == .point ? .aim : .point }
        // Same feel as the radar's button.
        WatchHaptics.play(watchSettings.aimStyle == .aim ? .start : .stop)
        Task {
            try? await Task.sleep(for: .seconds(1))
            ignoreNextTap = false
        }
    }
}

/// Point or Aim acted out: someone raises their arm (or tilts the Watch) at a plane, holds
/// it, and the Watch names it. The first time round it also taps your wrist like the real
/// thing: a tick on acquiring, a firm tap on naming.
private struct IdentifyScene: View {
    let style: WristPointing.AimStyle
    let hapticsEnabled: Bool

    private enum Phase: Equatable { case idle, aiming, holding, named }

    @State private var phase: Phase = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The scene, on a 150 × 90 grid.
    private static let shoulder = CGPoint(x: 30, y: 42)
    private static let plane = CGPoint(x: 128, y: 13)
    private static let wrist = CGPoint(x: 49, y: 47)

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                figure
                if style == .point { pointingArm } else { aimingArm }
                planeMark
            }
            .frame(width: 150, height: 90)
            // Small enough that the name shows without scrolling on a 40 mm Watch.
            .scaleEffect(0.82)
            .frame(width: 123, height: 74)
            screen
        }
        .task(id: style) { await play() }
    }

    // MARK: Figure

    private var figure: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 87)); p.addLine(to: CGPoint(x: 150, y: 87))
            }
            .stroke(Palette.faint, lineWidth: 1)
            Circle().fill(Palette.value).frame(width: 14, height: 14).position(x: 30, y: 29)
            Path { p in
                p.move(to: CGPoint(x: 30, y: 37)); p.addLine(to: CGPoint(x: 30, y: 65))
                p.move(to: CGPoint(x: 30, y: 65)); p.addLine(to: CGPoint(x: 23, y: 86))
                p.move(to: CGPoint(x: 30, y: 65)); p.addLine(to: CGPoint(x: 37, y: 86))
                p.move(to: CGPoint(x: 30, y: 43)); p.addLine(to: CGPoint(x: 25, y: 62))
            }
            .stroke(Palette.value, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private var targetAngle: Double {
        let from = style == .point ? Self.shoulder : Self.wrist
        return atan2(from.y - Self.plane.y, Self.plane.x - from.x) * 180 / .pi
    }

    /// Point: the whole arm swings up from the side until the forearm lines up with the plane.
    private var pointingArm: some View {
        let angle = phase == .idle ? -55 : targetAngle
        let radians = angle * .pi / 180
        let length: CGFloat = 36
        let hand = CGPoint(x: Self.shoulder.x + length * cos(radians), y: Self.shoulder.y - length * sin(radians))
        let watch = CGPoint(x: Self.shoulder.x + length * 0.7 * cos(radians), y: Self.shoulder.y - length * 0.7 * sin(radians))
        return ZStack {
            if phase != .idle {
                sightLine(from: hand, angle: angle)
            }
            Path { p in p.move(to: Self.shoulder); p.addLine(to: hand) }
                .stroke(Palette.value, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Palette.ink)
                .frame(width: 7, height: 8)
                .rotationEffect(.degrees(-angle))
                .position(watch)
        }
    }

    /// Aim: the forearm is held across the chest like reading the time; the Watch tilts until
    /// its top edge (the red arrow) points at the plane.
    private var aimingArm: some View {
        let angle = phase == .idle ? 0 : targetAngle
        let radians = angle * .pi / 180
        let half: CGFloat = 7
        let top = CGPoint(x: Self.wrist.x + half * cos(radians), y: Self.wrist.y - half * sin(radians))
        let bottom = CGPoint(x: Self.wrist.x - half * cos(radians), y: Self.wrist.y + half * sin(radians))
        return ZStack {
            if phase != .idle {
                sightLine(from: top, angle: angle)
            }
            Path { p in
                p.move(to: Self.shoulder); p.addLine(to: CGPoint(x: 36, y: 58)); p.addLine(to: Self.wrist)
            }
            .stroke(Palette.value, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            // The Watch, edge on: its screen faces the eyes, its top edge leads.
            Path { p in p.move(to: bottom); p.addLine(to: top) }
                .stroke(Palette.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Palette.signal)
                .rotationEffect(.degrees(90 - angle))
                .position(x: top.x + 4 * cos(radians), y: top.y - 4 * sin(radians))
            // Eye line: looking down at the screen.
            Path { p in p.move(to: CGPoint(x: 34, y: 29)); p.addLine(to: Self.wrist) }
                .stroke(Palette.caption.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [1.5, 2.5]))
        }
    }

    private func sightLine(from start: CGPoint, angle: Double) -> some View {
        let radians = angle * .pi / 180
        let reach = hypot(Self.plane.x - start.x, Self.plane.y - start.y) - 10
        let end = CGPoint(x: start.x + reach * cos(radians), y: start.y - reach * sin(radians))
        return Path { p in p.move(to: start); p.addLine(to: end) }
            .stroke(phase == .named ? Palette.live : Palette.signal.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [3, 4]))
    }

    private var planeMark: some View {
        ZStack {
            if phase == .holding || phase == .named {
                Circle()
                    .stroke(phase == .named ? Palette.live : Palette.signal, lineWidth: 1.5)
                    .frame(width: phase == .named ? 26 : 32, height: phase == .named ? 26 : 32)
            }
            AircraftGlyph(silhouette: .airliner, size: 18)
                .foregroundStyle(phase == .named ? Palette.live : Palette.blip)
                .rotationEffect(.degrees(80))
        }
        .position(Self.plane)
    }

    // MARK: What the Watch shows

    private var screen: some View {
        VStack(spacing: 1) {
            Text(caption)
                .font(.mono(8, .semibold))
                .tracking(1)
                .textCase(.uppercase)
                .foregroundStyle(phase == .named ? Palette.live : Palette.caption)
            Text(phase == .named ? "DL1199" : (style == .point ? "Point at a plane" : "Aim at a plane"))
                .font(.mono(phase == .named ? 16 : 11, phase == .named ? .heavy : .bold))
                .foregroundStyle(Palette.ink)
            if phase == .named {
                Text("ATL → ORD · A321neo")
                    .font(.mono(9, .bold))
                    .foregroundStyle(Palette.route)
                Label("\"Delta 1199, Atlanta to Chicago\"", systemImage: "speaker.wave.2.fill")
                    .font(.mono(8))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .top)
        .padding(.vertical, 5)
        .background(Palette.paperShade.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: style == .aim ? .top : .trailing) {
            // The red arrow on the edge that aims, as on the real screen.
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Palette.signal)
                .rotationEffect(.degrees(style == .aim ? 0 : 90))
                .offset(x: style == .aim ? 0 : 3, y: style == .aim ? -3 : 0)
        }
        .animation(.snappy, value: phase)
    }

    private var caption: String {
        switch phase {
        case .idle, .aiming: return "Identify"
        case .holding: return "Hold steady…"
        case .named: return "That's"
        }
    }

    // MARK: Timing

    private func play() async {
        if reduceMotion {
            phase = .named
            return
        }
        var firstRound = true
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 0.5)) { phase = .idle }
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85)) { phase = .aiming }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { phase = .holding }
            if firstRound { WatchHaptics.play(.click, enabled: hapticsEnabled) }
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { phase = .named }
            if firstRound { WatchHaptics.play(.success, enabled: hapticsEnabled) }
            firstRound = false
            try? await Task.sleep(for: .seconds(3.2))
        }
    }
}

/// Find's compass strip and height gauge, with a pretend arm swinging round then up.
private struct FindDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let target = (azimuth: 40.0, elevation: 24.0)
    private static let period = 6.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = reduceMotion ? 1 : (context.date.timeIntervalSinceReferenceDate / Self.period).truncatingRemainder(dividingBy: 1)
            // Swing round (0–0.4), then raise (0.4–0.7), then hold on target.
            let turn = min(1, phase / 0.4)
            let raise = max(0, min(1, (phase - 0.4) / 0.3))
            let azimuth = -50 + (Self.target.azimuth + 50) * ease(turn)
            let elevation = 3 + (Self.target.elevation - 3) * ease(raise)
            let facing = turn >= 1
            let locked = raise >= 1
            HStack(spacing: 6) {
                VStack(spacing: 4) {
                    Text(locked ? "On it" : (facing ? "Higher" : "Turn right"))
                        .font(.mono(9, .semibold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(locked ? Palette.live : Palette.caption)
                    Text("DL1199")
                        .font(.mono(16, .heavy))
                        .foregroundStyle(Palette.ink)
                    AzimuthStrip(arm: azimuth, marks: [.init(azimuth: Self.target.azimuth, isHighlighted: true)],
                                 isFacing: facing, isOnTarget: locked)
                        .frame(height: 26)
                }
                ElevationGauge(target: Self.target.elevation, arm: elevation, isLevel: locked, isOnTarget: locked)
                    .frame(width: 26, height: 80)
            }
            .padding(.horizontal, 6)
        }
    }

    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
