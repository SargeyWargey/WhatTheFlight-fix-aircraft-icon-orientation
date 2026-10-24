//
//  WhereaboutsView.swift
//  WhatTheFlight
//
//  iPhone: "Where is it now?" for an aircraft outside the radius (from its details or a
//  logbook entry). Finds the airframe anywhere in the world and keeps it updated.
//

#if os(iOS)
import SwiftUI
import CoreLocation

struct WhereaboutsView: View {
    let title: String
    let registration: String?
    let callsign: String?
    /// The leg you saw, so the screen can say "still on" or "now flying".
    var seenFlightID: String?
    var observer: CLLocationCoordinate2D?

    @LazyState private var lookup = WhereaboutsLookup()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch lookup.state {
                case .loading:
                    ProgressView("Looking for \(title)…")
                        .monoScaled(13)
                        .padding(.top, 80)
                case .notFound:
                    ContentUnavailableView("Can't see it right now", systemImage: "antenna.radiowaves.left.and.right.slash",
                                           description: Text(Whereabouts.notFoundText))
                        .padding(.top, 40)
                    refreshButton
                case .failed(let message):
                    ContentUnavailableView("Couldn't check", systemImage: "wifi.exclamationmark", description: Text(message))
                        .padding(.top, 40)
                    refreshButton
                case .found(let w):
                    found(w)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("Where Is It Now?")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.monospaced)
        .task {
            await lookup.track(registration: registration, callsign: callsign, seenFlightID: seenFlightID, observer: observer)
        }
    }

    private func found(_ w: Whereabouts) -> some View {
        let f = w.flight
        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(f.operatorInfo.title).radarCaption(scales: true)
                Text(w.headline)
                    .monoScaled(30, .heavy)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                if let detail = w.detail {
                    Text(detail)
                        .monoScaled(14, .semibold)
                        .foregroundStyle(Palette.route)
                        .multilineTextAlignment(.center)
                }
                if let distance = w.distanceText {
                    Text(distance)
                        .monoScaled(13)
                        .foregroundStyle(Palette.caption)
                }
            }
            .padding(.top, 10)

            WhereaboutsMap(whereabouts: w, observer: observer, height: 360, interactive: true)

            if !f.isOnGround, let progress = RouteProgress(flight: f, position: w.coordinate) {
                RouteProgressView(progress: progress)
                    .padding(14)
                    .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                stat("Altitude", f.isOnGround ? "On ground" : "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                stat("Speed", "\(RadarFormat.wholeNumber(f.groundSpeedKnots)) kts")
                stat("Flight", f.displayIdentifier)
                stat("Heading", "\(Int(f.track.rounded()) % 360)° \(GeoMath.cardinal(f.track))")
            }

            if let updated = lookup.updatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard)) · refreshes every 30 s")
                    .monoScaled(10)
                    .foregroundStyle(Palette.faint)
            }
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await lookup.refresh(registration: registration, callsign: callsign, seenFlightID: seenFlightID, observer: observer) }
        } label: {
            Label("Refresh", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(RadarButtonStyle(prominent: false))
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).radarCaption(scales: true)
            Text(value)
                .monoScaled(15, .semibold)
                .foregroundStyle(Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
#endif
