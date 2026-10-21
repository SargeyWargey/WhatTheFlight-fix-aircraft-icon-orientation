//
//  PerimeterLayer.swift
//  WhatTheFlight
//
//  Aircraft icons riding the screen edge. Each sits where its real-world bearing meets the
//  edge (rotated by the compass), faces its actual track, and carries a whole-mile distance
//  label tucked between it and the centre of the screen.
//

#if os(iOS) || os(tvOS) || os(watchOS)
import SwiftUI

struct PerimeterLayer: View {
    let placements: [PerimeterPlacement]
    let focusedID: String?
    let radiusMiles: Double
    var scale: CGFloat = 1
    let onTap: (RadarContact) -> Void
    let onLongPress: (RadarContact) -> Void

    var body: some View {
        ZStack {
            ForEach(placements) { placement in
                let isFocused = placement.id == focusedID
                let fade = 1 - 0.4 * min(1, placement.contact.distanceMiles / max(radiusMiles, 1))

                DistanceLabel(miles: placement.contact.distanceMiles, isFocused: isFocused, kind: placement.contact.flight.kind, scale: scale)
                    .opacity(isFocused ? 1 : fade)
                    .position(placement.labelPoint)
                    .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.labelPoint)
                    .transition(edgeTransition(for: placement))
                    .zIndex(3)

                AircraftBlip(
                    kind: placement.contact.flight.kind,
                    screenTrack: placement.screenTrack,
                    isFocused: isFocused,
                    scale: scale,
                    notable: placement.contact.flight.notable.first?.tag
                )
                .opacity(isFocused ? 1 : fade)
                .position(placement.point)
                .animation(.interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.point)
                .onTapGesture { onTap(placement.contact) }
                .onLongPressGesture(minimumDuration: 0.4) { onLongPress(placement.contact) }
                .accessibilityElement()
                .accessibilityLabel(accessibilityText(for: placement.contact))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows this aircraft in the centre")
                .transition(edgeTransition(for: placement))
                .zIndex(isFocused ? 2 : 1)
            }
        }
        .animation(.smooth(duration: 0.9), value: placements.map(\.id))
    }

    /// Aircraft entering the radius float in from beyond the screen edge at their bearing
    /// (and drift back out the same way when they leave), rather than growing out of the
    /// centre: a scale transition on a positioned view is anchored to the whole layer.
    private func edgeTransition(for placement: PerimeterPlacement) -> AnyTransition {
        let distance = 110 * scale
        return .offset(x: -placement.inward.dx * distance, y: -placement.inward.dy * distance)
            .combined(with: .opacity)
    }

    private func accessibilityText(for contact: RadarContact) -> String {
        let dir = GeoMath.cardinal(contact.bearing)
        let motion = contact.isApproaching ? "approaching" : "moving away"
        let badge = contact.flight.notable.first.map { ", \($0.badge.capitalized)" } ?? ""
        return "\(contact.flight.displayIdentifier)\(badge), \(RadarFormat.miles(contact.distanceMiles)) miles \(dir), \(motion)"
    }
}

struct AircraftBlip: View {
    let kind: AircraftKind
    let screenTrack: Double
    let isFocused: Bool
    var scale: CGFloat = 1
    /// Notable traffic gets a coloured marker; emergencies turn the whole blip red.
    var notable: NotableTag? = nil

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        if isFocused || notable?.isEmergency == true { return Palette.signal }
        return kind == .helicopter ? Palette.heliBlip : Palette.blip
    }

    var body: some View {
        ZStack {
            if isFocused {
                Circle()
                    .stroke(Palette.signal.opacity(0.55), lineWidth: 1.5 * scale)
                    .frame(width: 40 * scale, height: 40 * scale)
                    .scaleEffect(pulse ? 1.35 : 0.85)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .fill(Palette.signal.opacity(0.16))
                    .frame(width: 40 * scale, height: 40 * scale)
            }
            glyph
                .foregroundStyle(tint)
                // The SF Symbol points east; the helicopter artwork points north.
                .continuousRotation(kind == .helicopter ? screenTrack : screenTrack - 90)
                .shadow(color: tint.opacity(0.35), radius: 3 * scale, y: scale)
            if let notable {
                Circle()
                    .fill(Palette.color(for: notable))
                    .frame(width: 9 * scale, height: 9 * scale)
                    .overlay(Circle().stroke(Palette.paper, lineWidth: 1.5 * scale))
                    .offset(x: 13 * scale, y: -13 * scale)
            }
        }
        .frame(width: 44 * scale, height: 44 * scale)
        .contentShape(Circle())
        .onAppear { startPulse() }
        .onChange(of: isFocused) { _, _ in startPulse() }
    }

    @ViewBuilder
    private var glyph: some View {
        switch kind {
        case .airplane:
            Image(systemName: "airplane")
                .font(.system(size: (isFocused ? 25 : 21) * scale, weight: .semibold))
        case .helicopter:
            Image("helicopter-bottom-view")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: (isFocused ? 28 : 24) * scale, height: (isFocused ? 28 : 24) * scale)
        }
    }

    private func startPulse() {
        pulse = false
        guard isFocused, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

struct DistanceLabel: View {
    let miles: Double
    let isFocused: Bool
    let kind: AircraftKind
    var scale: CGFloat = 1

    var body: some View {
        Text(RadarFormat.miles(miles))
            .font(.mono((isFocused ? 15 : 13) * scale, .bold))
            .monospacedDigit()
            .foregroundStyle(isFocused ? Palette.signal : (kind == .helicopter ? Palette.heliBlip : Palette.blip))
            .contentTransition(.numericText(value: miles))
            .paperHalo()
            .fixedSize()
            .accessibilityHidden(true)
    }
}
#endif
