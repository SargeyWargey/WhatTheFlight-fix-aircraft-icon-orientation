//
//  TVMapStack.swift
//  WhatTheFlight
//
//  The Apple TV's map view: the live map full screen and, bottom-right, a card for the
//  focused aircraft. It is a layer `TVRadarScreen` swaps in for the radar face; the status
//  badge, remote hints, dock and every remote command stay there, so the remote works the
//  same on both views. The card is passed in for the same reason: it is the focus anchor.
//
//  `TVTrafficMap` is the map on its own, also the right-hand pane of the Split view.
//

#if os(tvOS)
import SwiftUI

struct TVMapStack<Card: View>: View {
    let model: RadarModel
    let settings: RadarSettings
    let card: Card

    init(model: RadarModel, settings: RadarSettings, @ViewBuilder card: () -> Card) {
        self.model = model
        self.settings = settings
        self.card = card()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TVTrafficMap(model: model, settings: settings, cardInset: CGSize(width: TVMapLayout.cardWidth + 60, height: 0))

            card
                .frame(width: TVMapLayout.cardWidth)
                .padding(.vertical, 30)
                .padding(.horizontal, 20)
                .glassSurface(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
    }
}

/// The live map of the model's traffic, turned to the TV's facing (or north up), bleeding
/// into the overscan on every side it touches.
struct TVTrafficMap: View {
    let model: RadarModel
    let settings: RadarSettings
    /// Keeps the ring clear of a card laid over the map.
    var cardInset: CGSize = .zero

    var body: some View {
        if let observer = model.observer {
            TrafficMap(
                observer: observer,
                radiusMiles: settings.radiusMiles,
                contacts: model.contacts,
                fringe: model.outsideContacts,
                focused: model.focusedContact,
                isPinned: model.focus.isPinned,
                announcedID: AlertSpeaker.shared.speakingFlightID,
                pinnedIDs: model.pinnedIDs,
                trail: model.trail(for:),
                trailVersion: model.trailVersion,
                headingUp: settings.mapNorthUp ? nil : settings.tvFacingDegrees,
                options: .init(scale: TVMapLayout.scale, placeName: placeName, cardInset: cardInset)
            )
            .ignoresSafeArea()
            // Decorative, like the radar face: the hero and the dock's Aircraft list are the
            // VoiceOver path.
            .accessibilityHidden(true)
        } else {
            Palette.paper.ignoresSafeArea()
        }
    }

    /// "Atlanta" for "You · Atlanta" by the observer dot.
    private var placeName: String? {
        let name = settings.locationMode == .custom ? settings.customPlaceName : model.logPlaceName
        return name?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

enum TVMapLayout {
    /// The hero card's width, bottom-right; the map keeps the ring clear of it.
    static let cardWidth: CGFloat = 640
    /// Glyphs, labels and lines on the map, like the radar's `scale`.
    static let scale: CGFloat = 1.7
}

/// Lays content out at `width / scale` and blows it up to `width`, reporting its real height
/// (a plain `scaleEffect` leaves the layout at the unscaled size).
struct TVScaledContent<Content: View>: View {
    let width: CGFloat
    let scale: CGFloat
    @ViewBuilder let content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        content
            .frame(width: width / scale)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .scaleEffect(scale)
            .frame(width: width, height: height * scale)
    }
}
#endif
