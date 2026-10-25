//
//  PointAndFindView.swift
//  WhatTheFlightWatch
//
//  Find: you picked an aircraft (from its details or an alert); point at the sky (or aim the
//  Watch's top edge, in Aim style) and the Watch guides you to it. Direction and height are shown and
//  felt separately — the compass strip and clicks while you swing round, the elevation gauge
//  and "up" / "down" taps for the height, then one firm tap when you're on it. The screen is
//  laid out by `PointingLayout`. The crown picks another aircraft. Pointing arm-out, watchOS
//  judges the wrist down (screen dimmed, app inactive): the lock then also goes out as a
//  wrist-tap notification, and the dimmed screen draws the cue large.
//

import SwiftUI
import WatchKit

struct PointAndFindView: View {
    let model: RadarModel
    let settings: RadarSettings
    let watchSettings: WatchSettings
    let location: WatchLocationService
    let initialTargetID: String

    @LazyState private var pointer = WristPointer()
    @State private var targetID: String?
    @State private var crown = 0
    @State private var locked = false
    @FocusState private var crownFocused: Bool
    /// Always-On, wrist judged down: bigger cue, no readout.
    @Environment(\.isLuminanceReduced) private var isDimmed

    private var target: RadarContact? {
        targetID.flatMap(model.contact(id:)) ?? model.focusedContact ?? model.contacts.first
    }

    private var targetDirection: WristPointing.Direction? {
        target.map { WristPointing.direction(of: WristPointing.target(for: $0)) }
    }

    private var armDirection: WristPointing.Direction? {
        pointer.pointing.map(WristPointing.direction(of:))
    }

    /// Aim is always upright; Point follows the sensors (and "Turn screen around").
    private var screenTurn: WristPointing.ScreenTurn {
        guard watchSettings.aimStyle == .point else { return .upright }
        return watchSettings.flipScreen ? pointer.screenTurn.reversed : pointer.screenTurn
    }

    private var guidance: WristPointing.Guidance? {
        guard let target, let pointing = pointer.pointing else { return nil }
        return WristPointing.guidance(pointing: pointing, target: WristPointing.target(for: target))
    }

    var body: some View {
        PointingLayout(style: watchSettings.aimStyle, turn: screenTurn) { metrics in
            VStack(spacing: 4) {
                PointingTopBar(metrics: metrics) {
                    if let target { header(target) }
                }
                if pointer.mode == .unavailable {
                    message(symbol: "gyroscope", title: "No motion sensors", text: "Point & Find needs the Watch's motion sensors.")
                } else if pointer.status == .waitingForCompass {
                    message(symbol: "location.north.circle", title: "Waiting for the compass", text: "Move your arm in a figure eight.")
                } else if let targetDirection {
                    HStack(spacing: 10) {
                        VStack(spacing: 2) {
                            cueGlyph
                            cueText
                        }
                        .frame(maxWidth: .infinity)
                        ElevationGauge(target: targetDirection.elevation, arm: armDirection?.elevation,
                                       isLevel: guidance?.isLevel == true, isOnTarget: guidance?.isOnTarget == true,
                                       silhouette: target?.flight.silhouette ?? .airliner)
                            .frame(width: 30)
                        .padding(.bottom, metrics.gaugeBottomInset)
                    }
                    .frame(maxHeight: .infinity)
                    AzimuthStrip(arm: armDirection?.azimuth,
                                 marks: target.map { [AzimuthStrip.Mark($0, isHighlighted: true)] } ?? [],
                                 isFacing: guidance?.isFacing == true, isOnTarget: guidance?.isOnTarget == true)
                        .frame(height: 26)
                        .clearOfClock(metrics)
                    if !isDimmed {
                        PointingReadout(arm: armDirection, target: targetDirection, mode: pointer.mode)
                            .clearOfClock(metrics)
                    }
                } else {
                    message(symbol: "sun.haze", title: "It's gone", text: "That aircraft has left the area.")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(detent: $crown, from: -100_000, through: 100_000, by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in switchTarget(by: new - old) }
        .onAppear {
            targetID = initialTargetID
            pointer.configure(style: watchSettings.aimStyle, flipped: watchSettings.flipPointing, location: location)
            pointer.start()
            crownFocused = true
            if watchSettings.aimStyle == .point { WristTapNotification.requestPermissionIfNeeded() }
        }
        .onDisappear {
            pointer.stop()
            WristTapNotification.clear()
        }
        .task { await guideByTouch() }
    }

    // MARK: Pieces

    private func header(_ target: RadarContact) -> some View {
        VStack(spacing: 0) {
            Text(target.flight.displayIdentifier)
                .font(.mono(isDimmed ? 20 : 16, .heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("\(RadarFormat.miles(target.distanceMiles)) mi \(GeoMath.cardinal(target.bearing)) · \(RadarFormat.wholeNumber(target.altitudeFeet)) ft")
                .font(.mono(9, .semibold))
                .foregroundStyle(Palette.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The one thing to do next: swing left / right, then raise / lower, then you're on it.
    private var cueGlyph: some View {
        Group {
            if let g = guidance {
                if g.isOnTarget {
                    Image(systemName: "scope")
                        .foregroundStyle(Palette.live)
                        .symbolEffect(.pulse, options: .repeating)
                } else if !g.isFacing {
                    Image(systemName: g.sideways > 0 ? "arrow.right" : "arrow.left")
                        .foregroundStyle(Palette.signal)
                } else {
                    Image(systemName: g.raise > 0 ? "arrow.up" : "arrow.down")
                        .foregroundStyle(Palette.signal)
                }
            } else {
                ProgressView().tint(Palette.ink)
            }
        }
        .font(.system(size: isDimmed ? 50 : 38, weight: .heavy))
        .frame(height: isDimmed ? 58 : 46)
        .contentTransition(.symbolEffect(.replace))
        .animation(.snappy(duration: 0.2), value: cueKey)
        .accessibilityElement()
        .accessibilityLabel(instructionText)
    }

    private var cueKey: Int {
        guard let g = guidance else { return 0 }
        if g.isOnTarget { return 1 }
        if !g.isFacing { return g.sideways > 0 ? 2 : 3 }
        return g.raise > 0 ? 4 : 5
    }

    private var cueText: some View {
        Text(instructionText)
            .font(.mono(isDimmed ? 14 : 11, .bold))
            .foregroundStyle(guidance?.isOnTarget == true ? Palette.live : Palette.value)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.7)
    }

    private var instructionText: String {
        guard let g = guidance else {
            return watchSettings.aimStyle == .point ? "Point your fingers at the sky" : "Aim the top of your Watch at the sky"
        }
        if g.isOnTarget { return watchSettings.aimStyle == .point ? "On it — look along your arm" : "On it — look past the red arrow" }
        if !g.isFacing { return "\(g.sideways > 0 ? "Right" : "Left") \(Int(abs(g.turn).rounded()))°" }
        return "\(g.raise > 0 ? "Up" : "Down") \(Int(abs(g.raise).rounded()))°"
    }

    private func message(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Palette.ink)
            Text(title).font(.mono(13, .bold)).foregroundStyle(Palette.ink)
            Text(text).font(.mono(10)).foregroundStyle(Palette.caption).multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Behaviour

    private func switchTarget(by steps: Int) {
        let contacts = model.contacts
        guard steps != 0, !contacts.isEmpty else { return }
        let current = contacts.firstIndex { $0.id == target?.id } ?? 0
        let next = (current + steps % contacts.count + contacts.count) % contacts.count
        targetID = contacts[next].id
        model.focus(on: contacts[next].id)
        locked = false
    }

    /// Plays `WristPointing.cue`: one firm tap on lock, re-armed once the arm wanders well off.
    private func guideByTouch() async {
        let haptics = settings.hapticsEnabled
        while !Task.isCancelled {
            guard let g = guidance else {
                try? await Task.sleep(for: .milliseconds(300))
                continue
            }
            if g.error > WristPointing.lockDegrees + 7 { locked = false }
            switch WristPointing.cue(for: g) {
            case .onTarget:
                if !locked {
                    locked = true
                    WatchHaptics.play(.success, enabled: haptics)
                    // Arm out, the wrist counts as down and that tap may go unplayed: a
                    // notification always reaches the wrist.
                    if haptics, WKApplication.shared().applicationState != .active, let target {
                        let look = watchSettings.aimStyle == .point ? "Look along your arm" : "Look past the red arrow"
                        WristTapNotification.post(
                            title: "On it: \(target.flight.displayIdentifier)",
                            body: "\(look) · \(RadarFormat.miles(target.distanceMiles)) mi \(GeoMath.cardinal(target.bearing)) · \(RadarFormat.wholeNumber(target.altitudeFeet)) ft",
                            contact: target)
                    }
                }
                try? await Task.sleep(for: .milliseconds(200))
            case .warmer(let every):
                if !locked { WatchHaptics.play(.click, enabled: haptics) }
                try? await Task.sleep(for: .seconds(every))
            case .raise(let every):
                if !locked { WatchHaptics.play(.directionUp, enabled: haptics) }
                try? await Task.sleep(for: .seconds(every))
            case .lower(let every):
                if !locked { WatchHaptics.play(.directionDown, enabled: haptics) }
                try? await Task.sleep(for: .seconds(every))
            }
        }
    }
}
