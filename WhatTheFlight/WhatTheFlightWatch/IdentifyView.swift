//
//  IdentifyView.swift
//  WhatTheFlightWatch
//
//  Identify: "what's that plane?" Point your fingers at an aircraft you can see (or aim the
//  Watch's top edge at it, in Aim style) and the Watch names it. Anything within 15 mi and a few degrees above the horizon counts; the one
//  closest to your arm (inside a 10° cone) gets a light tick, and after a half-second hold a
//  firm tap, its details on screen and — if switched on — a spoken call-out. The crown flips
//  between aircraft that are close together in the sky; tap the card for full details.
//

import SwiftUI
import WatchKit

struct IdentifyView: View {
    let model: RadarModel
    let settings: RadarSettings
    let watchSettings: WatchSettings
    let location: WatchLocationService
    let open: (WatchRootView.Screen) -> Void

    @State private var pointer = WristPointer()
    @State private var tracker = IdentifyTracker()
    @State private var speaker = IdentifySpeaker()
    @State private var candidates: [WristPointing.Candidate] = []
    @State private var lastSpoken: (id: String, at: Date)?
    @State private var crown = 0
    @FocusState private var crownFocused: Bool

    /// Everything you could plausibly be pointing at.
    private var visible: [RadarContact] {
        model.allContacts.filter {
            $0.distanceMiles <= WristPointing.identifyRangeMiles
                && GeoMath.elevationDegrees(groundDistanceMiles: $0.distanceMiles, altitudeFeet: Double($0.flight.altitudeFeet)) >= WristPointing.minimumElevation
        }
    }

    /// Aim is always upright; Point follows the sensors (and "Turn screen around").
    private var screenTurn: WristPointing.ScreenTurn {
        guard watchSettings.aimStyle == .point else { return .upright }
        return watchSettings.flipScreen ? pointer.screenTurn.reversed : pointer.screenTurn
    }

    private var current: RadarContact? { tracker.currentID.flatMap(model.contact(id:)) }

    private var armDirection: WristPointing.Direction? {
        pointer.pointing.map(WristPointing.direction(of:))
    }

    private var currentDirection: WristPointing.Direction? {
        current.map { WristPointing.direction(of: WristPointing.target(for: $0)) }
    }

    var body: some View {
        PointingLayout(style: watchSettings.aimStyle, turn: screenTurn) { metrics in
            VStack(spacing: 4) {
                PointingTopBar(metrics: metrics) {
                    Text(statusTitle)
                        .font(.mono(9, .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(tracker.isLocked ? Palette.live : Palette.caption)
                }
                HStack(spacing: 10) {
                    Group {
                        if pointer.mode == .unavailable {
                            prompt(symbol: "gyroscope", title: "No motion sensors", text: "Identify needs the Watch's motion sensors.")
                        } else if let current {
                            card(current)
                        } else if visible.isEmpty {
                            prompt(symbol: "sun.haze", title: "Nothing nearby",
                                   text: "No aircraft within \(Int(WristPointing.identifyRangeMiles)) mi right now.")
                        } else {
                            prompt(symbol: watchSettings.aimStyle == .point ? "hand.point.up.left.fill" : "scope",
                                   title: watchSettings.aimStyle == .point ? "Point at a plane" : "Aim at a plane",
                                   text: "\(visible.count) aircraft within \(Int(WristPointing.identifyRangeMiles)) mi")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    ElevationGauge(target: currentDirection?.elevation, arm: armDirection?.elevation,
                                   isLevel: tracker.isLocked, isOnTarget: tracker.isLocked)
                        .frame(width: 30)
                        .padding(.bottom, metrics.gaugeBottomInset)
                }
                .frame(maxHeight: .infinity)
                AzimuthStrip(arm: armDirection?.azimuth, marks: marks, isFacing: tracker.isLocked, isOnTarget: tracker.isLocked)
                    .frame(height: 26)
                    .clearOfClock(metrics)
                PointingReadout(arm: armDirection, target: currentDirection, mode: pointer.mode)
                    .clearOfClock(metrics)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .focusable()
        .focused($crownFocused)
        .digitalCrownRotation(detent: $crown, from: -100_000, through: 100_000, by: 1,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onChange(of: crown) { old, new in cycle(by: new - old) }
        .onAppear {
            pointer.configure(style: watchSettings.aimStyle, flipped: watchSettings.flipPointing, location: location)
            pointer.start()
            crownFocused = true
        }
        .onDisappear {
            pointer.stop()
            speaker.stop()
        }
        .task { await track() }
    }

    // MARK: Pieces

    private var statusTitle: String {
        switch tracker.state {
        case .searching: return "Identify"
        case .acquiring: return "Hold steady…"
        case .locked: return "That's"
        }
    }

    private var marks: [AzimuthStrip.Mark] {
        visible.map { contact in
            AzimuthStrip.Mark(azimuth: contact.bearing, isHighlighted: contact.id == tracker.currentID)
        }
    }

    private func card(_ contact: RadarContact) -> some View {
        let f = contact.flight
        let others = candidates.filter { $0.id != contact.id && $0.error <= WristPointing.identifyCone }
            .compactMap { model.contact(id: $0.id)?.flight.displayIdentifier }
        return Button { open(.detail(contact.id)) } label: {
            VStack(spacing: 1) {
                if let top = f.notable.first {
                    NotableBadge(info: top, scale: 0.7)
                }
                Text(f.operatorInfo.compact)
                    .font(.mono(9, .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(f.displayIdentifier)
                    .font(.mono(26, .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(subtitle(f))
                    .font(.mono(11, .bold))
                    .foregroundStyle(Palette.route)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(RadarFormat.wholeNumber(f.altitudeFeet)) ft · \(RadarFormat.miles(contact.distanceMiles)) mi \(GeoMath.cardinal(contact.bearing))")
                    .font(.mono(10, .semibold))
                    .foregroundStyle(Palette.value)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !others.isEmpty {
                    Text("Also here: \(others.prefix(2).joined(separator: ", ")) · turn crown")
                        .font(.mono(8))
                        .foregroundStyle(Palette.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .multilineTextAlignment(.center)
            .opacity(tracker.isLocked ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows details")
    }

    /// "SFO → ATL · Boeing 757-200", or just the type when there's no route.
    private func subtitle(_ f: Flight) -> String {
        let type = f.typeName ?? f.typeCode
        guard f.hasRoute else { return type ?? f.operatorInfo.title }
        let route = "\(f.originIATA ?? "") → \(f.destinationIATA ?? "")"
        return type.map { "\(route) · \($0)" } ?? route
    }

    private func prompt(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(Palette.ink)
            Text(title).font(.mono(13, .bold)).foregroundStyle(Palette.ink)
            Text(text).font(.mono(9)).foregroundStyle(Palette.caption).multilineTextAlignment(.center)
        }
    }

    // MARK: Behaviour

    /// Ten times a second: who's in the cone, and does that change the call-out?
    private func track() async {
        while !Task.isCancelled {
            if let pointing = pointer.pointing {
                candidates = WristPointing.candidates(pointing: pointing, contacts: visible, cone: IdentifyTracker.keepCone)
                if let event = tracker.update(candidates, now: Date()) { handle(event) }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func handle(_ event: IdentifyTracker.Event) {
        switch event {
        case .acquiring:
            WatchHaptics.play(.click, enabled: settings.hapticsEnabled)
        case .named(let id):
            WatchHaptics.play(.success, enabled: settings.hapticsEnabled)
            guard watchSettings.speakIdentification, let contact = model.contact(id: id) else { return }
            // Don't repeat the same aircraft every time the arm wobbles off and back on.
            if let lastSpoken, lastSpoken.id == id, Date().timeIntervalSince(lastSpoken.at) < 10 { return }
            lastSpoken = (id, Date())
            speaker.say(SpokenTraffic.identification(for: contact))
        case .lost:
            tracker.preferredID = nil
        }
    }

    /// Crown: step through the aircraft in the cone, nearest the arm first.
    private func cycle(by steps: Int) {
        let inCone = candidates.filter { $0.error <= WristPointing.identifyCone }
        guard steps != 0, !inCone.isEmpty else { return }
        let index = inCone.firstIndex { $0.id == tracker.currentID } ?? 0
        let next = (index + steps % inCone.count + inCone.count) % inCone.count
        tracker.preferredID = inCone[next].id
    }
}
