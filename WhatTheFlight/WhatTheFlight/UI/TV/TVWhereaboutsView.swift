//
//  TVWhereaboutsView.swift
//  WhatTheFlight
//
//  Apple TV: "Where is it now?" for an aircraft outside the radius. Status on the left, a
//  big map of it relative to you (and along its route) on the right; refreshes every 30 s.
//

#if os(tvOS)
import SwiftUI
import CoreLocation

struct TVWhereaboutsView: View {
    let title: String
    let registration: String?
    let callsign: String?
    var seenFlightID: String?
    var observer: CLLocationCoordinate2D?
    var showTopography = true

    @LazyState private var lookup = WhereaboutsLookup()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            RadarBackdrop(showTopography: showTopography, showSweep: false, isActive: true)
                .ignoresSafeArea()
            HStack(alignment: .top, spacing: 70) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Where is it now?").radarCaptionTV()
                    Text(title)
                        .font(.mono(72, .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    status
                    Spacer(minLength: 0)
                    HStack(spacing: 24) {
                        Button("Refresh") {
                            Task { await refresh() }
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: lookup.whereabouts == nil))
                        Button("Close") { dismiss() }
                            .buttonStyle(TVPillButtonStyle(prominent: false))
                    }
                    .focusSection()
                }
                .frame(width: 640, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .top)

                Group {
                    if let w = lookup.whereabouts {
                        WhereaboutsMap(whereabouts: w, observer: observer, height: 860, iconScale: 1.8)
                    } else {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Palette.paperShade.opacity(0.35))
                            .overlay {
                                if lookup.state == .loading { ProgressView() }
                            }
                            .frame(height: 860)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 90)
            .padding(.vertical, 70)
        }
        .task {
            await lookup.track(registration: registration, callsign: callsign, seenFlightID: seenFlightID, observer: observer)
        }
    }

    private func refresh() async {
        await lookup.refresh(registration: registration, callsign: callsign, seenFlightID: seenFlightID, observer: observer)
    }

    @ViewBuilder
    private var status: some View {
        switch lookup.state {
        case .loading:
            Text("Looking for it on Flightradar24…")
                .font(.mono(28))
                .foregroundStyle(Palette.caption)
        case .notFound:
            Text("Can't see it right now")
                .font(.mono(40, .bold))
                .foregroundStyle(Palette.value)
            Text(Whereabouts.notFoundText)
                .font(.mono(24))
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let message):
            Text("Couldn't check")
                .font(.mono(40, .bold))
                .foregroundStyle(Palette.value)
            Text(message)
                .font(.mono(24))
                .foregroundStyle(Palette.caption)
        case .found(let w):
            found(w)
        }
    }

    private func found(_ w: Whereabouts) -> some View {
        let f = w.flight
        return VStack(alignment: .leading, spacing: 18) {
            Text(w.headline)
                .font(.mono(48, .heavy))
                .foregroundStyle(Palette.signal)
            if let detail = w.detail {
                Text(detail)
                    .font(.mono(28, .bold))
                    .foregroundStyle(Palette.route)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let distance = w.distanceText {
                Text(distance)
                    .font(.mono(28, .medium))
                    .foregroundStyle(Palette.value)
            }
            if !f.isOnGround, let progress = RouteProgress(flight: f, position: w.coordinate) {
                RouteProgressView(progress: progress, scale: 1.8)
                    .padding(.top, 6)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
                stat("Altitude", f.isOnGround ? "On ground" : "\(RadarFormat.wholeNumber(f.altitudeFeet)) ft")
                stat("Speed", "\(RadarFormat.wholeNumber(f.groundSpeedKnots)) kts")
                stat("Flight", f.displayIdentifier)
                stat("Heading", "\(Int(f.track.rounded()) % 360)° \(GeoMath.cardinal(f.track))")
            }
            .padding(.top, 6)
            if let updated = lookup.updatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · refreshes every 30 s")
                    .font(.mono(18))
                    .foregroundStyle(Palette.caption)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).radarCaptionTV()
            Text(value)
                .font(.mono(28, .semibold))
                .foregroundStyle(Palette.value)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
#endif
