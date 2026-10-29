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

extension EnvironmentValues {
    /// The favourite aircraft, called out in yellow: the radar edge and the map (here, on
    /// every platform), the hero, search and the logbook. Set at each app's root from
    /// `RadarSettings.favoriteSet`.
    @Entry var favoriteAircraft = FavoriteSet()
    /// Adds or removes a favourite from screens without the radar model (the logbook's
    /// aircraft and sighting pages). nil hides the button.
    @Entry var toggleFavorite: FavoriteToggle? = nil
}

/// `\.toggleFavorite`'s action. Each app has one, always toggling through its radar model, so
/// any two are equal and handing it down never redraws what reads it.
struct FavoriteToggle: Equatable {
    let action: (FavoriteAircraft) -> Void

    func callAsFunction(_ favorite: FavoriteAircraft) { action(favorite) }

    static func == (_: FavoriteToggle, _: FavoriteToggle) -> Bool { true }
}

struct PerimeterLayer: View {
    let placements: [PerimeterPlacement]
    let focusedID: String?
    /// The aircraft a spoken alert is reading out (Apple TV), pulsed in purple.
    var announcedID: String? = nil
    /// Pinned aircraft: a yellow mile label (`Palette.pinned`), never faded however far away.
    var pinnedIDs: Set<String> = []
    let radiusMiles: Double
    var scale: CGFloat = 1
    let onTap: (RadarContact) -> Void
    let onLongPress: (RadarContact) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.favoriteAircraft) private var favorites

    var body: some View {
        ZStack {
            ForEach(placements) { placement in
                let isFocused = placement.id == focusedID
                let isAnnounced = placement.id == announcedID
                let isPinned = pinnedIDs.contains(placement.id)
                let isFavorite = favorites.contains(placement.contact.flight)
                let fade = isPinned ? 1 : 1 - 0.4 * min(1, placement.contact.distanceMiles / max(radiusMiles, 1))

                DistanceLabel(miles: placement.contact.distanceMiles, isFocused: isFocused, isPinned: isPinned,
                              profile: placement.contact.profile, scale: scale)
                    .opacity(isFocused ? 1 : fade)
                    .position(placement.labelPoint)
                    .animation(reduceMotion ? nil : .interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.labelPoint)
                    .transition(edgeTransition(for: placement))
                    .zIndex(3)

                AircraftBlip(
                    profile: placement.contact.profile,
                    screenTrack: placement.screenTrack,
                    isFocused: isFocused,
                    isAnnounced: isAnnounced,
                    isFavorite: isFavorite,
                    scale: scale
                )
                .opacity(isFocused || isAnnounced ? 1 : fade)
                .position(placement.point)
                .animation(reduceMotion ? nil : .interactiveSpring(response: 0.6, dampingFraction: 0.85), value: placement.point)
                .onTapGesture { onTap(placement.contact) }
                .onLongPressGesture(minimumDuration: 0.4) { onLongPress(placement.contact) }
                .accessibilityElement()
                .accessibilityLabel(accessibilityText(for: placement.contact))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Shows this aircraft in the center")
                .transition(edgeTransition(for: placement))
                .zIndex(isAnnounced ? 2.5 : isFocused ? 2 : 1)
            }
        }
        .animation(.smooth(duration: 0.9), value: placements.map(\.id))
    }

    /// Aircraft entering the radius float in from beyond the screen edge at their bearing
    /// (and drift back out the same way when they leave), rather than growing out of the
    /// centre: a scale transition on a positioned view is anchored to the whole layer.
    private func edgeTransition(for placement: PerimeterPlacement) -> AnyTransition {
        // Reduce Motion: fade in place instead.
        guard !reduceMotion else { return .opacity }
        let distance = 110 * scale
        return .offset(x: -placement.inward.dx * distance, y: -placement.inward.dy * distance)
            .combined(with: .opacity)
    }

    private func accessibilityText(for contact: RadarContact) -> String {
        let dir = GeoMath.cardinal(contact.bearing)
        let motion = contact.isApproaching ? "approaching" : "moving away"
        let badge = contact.profile.notable.first.map { ", \($0.badge.capitalized)" } ?? ""
        let pinned = pinnedIDs.contains(contact.id) ? ", pinned" : ""
        let favorite = favorites.contains(contact.flight) ? ", favorite" : ""
        return "\(contact.flight.displayIdentifier)\(badge)\(favorite)\(pinned), \(RadarFormat.spokenDistance(contact.distanceMiles)) \(dir), \(motion)"
    }
}

struct AircraftBlip: View {
    let profile: FlightProfile
    let screenTrack: Double
    let isFocused: Bool
    /// Being read out by a spoken alert: a purple pulse in place of the red focus one.
    var isAnnounced = false
    /// A favourite: the whole icon in yellow, focused or not (the focus keeps its red halo).
    var isFavorite = false
    var scale: CGFloat = 1

    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Apple Watch, wrist down: nothing should keep animating on the dimmed screen.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let tags = profile.notable.map(\.tag)
        // Emergencies turn the whole blip red. Military already shows in the icon's colour,
        // so the corner marker shows the next most urgent tag.
        let tint = isAnnounced
            ? Palette.announce
            : tags.first?.isEmergency == true
            ? Palette.signal
            : isFavorite
            ? Palette.favorite
            : isFocused
            ? Palette.signal
            : Palette.blip(isMilitary: tags.contains(.military))
        let halo = isAnnounced ? Palette.announce : Palette.signal
        let markerTag = tags.first { $0 != .military }
        ZStack {
            if isFocused || isAnnounced {
                Circle()
                    .stroke(halo.opacity(isAnnounced ? 0.8 : 0.55), lineWidth: (isAnnounced ? 2.5 : 1.5) * scale)
                    .frame(width: 40 * scale, height: 40 * scale)
                    .scaleEffect(pulse ? (isAnnounced ? 1.6 : 1.35) : 0.85)
                    .opacity(pulse ? 0 : 1)
                Circle()
                    .fill(halo.opacity(isAnnounced ? 0.24 : 0.16))
                    .frame(width: 40 * scale, height: 40 * scale)
            }
            AircraftGlyph(silhouette: profile.silhouette, size: (isFocused ? 34 : 30) * scale)
                .foregroundStyle(tint)
                .continuousRotation(screenTrack)
                .shadow(color: tint.opacity(0.35), radius: 3 * scale, y: scale)
            if let markerTag {
                Circle()
                    .fill(Palette.color(for: markerTag))
                    .frame(width: 9 * scale, height: 9 * scale)
                    .overlay(Circle().stroke(Palette.paper, lineWidth: 1.5 * scale))
                    .offset(x: 13 * scale, y: -13 * scale)
            }
        }
        .frame(width: 44 * scale, height: 44 * scale)
        .contentShape(Circle())
        .onChange(of: [isFocused, isAnnounced, isLuminanceReduced], initial: true) { _, _ in startPulse() }
    }

    private func startPulse() {
        pulse = false
        guard isFocused || isAnnounced, !reduceMotion, !isLuminanceReduced else { return }
        withAnimation(.easeOut(duration: isAnnounced ? 1.1 : 1.6).repeatForever(autoreverses: false)) {
            pulse = true
        }
    }
}

struct DistanceLabel: View {
    let miles: Double
    let isFocused: Bool
    /// Yellow, like the pin by the flight number on the hero.
    var isPinned = false
    let profile: FlightProfile
    var scale: CGFloat = 1

    var body: some View {
        Text(RadarFormat.distance(miles))
            .font(.mono((isFocused ? 15 : 13) * scale, .bold))
            .monospacedDigit()
            .foregroundStyle(isPinned ? Palette.pinned : isFocused ? Palette.signal : Palette.blip(for: profile))
            .contentTransition(.numericText(value: miles))
            .paperHalo()
            .fixedSize()
            .accessibilityHidden(true)
    }
}
#endif
