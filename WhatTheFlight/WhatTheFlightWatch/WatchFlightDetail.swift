//
//  WatchFlightDetail.swift
//  WhatTheFlightWatch
//
//  Everything about one aircraft, live: route progress, where it is from you, the airframe
//  and its photo. Handoff carries the flight to the iPhone.
//

import SwiftUI
import UIKit
import ImageIO
import WatchKit

struct WatchFlightDetail: View {
    let flightID: String
    let model: RadarModel
    let settings: RadarSettings
    let watchSettings: WatchSettings
    let location: WatchLocationService
    let open: (WatchRootView.Screen) -> Void
    /// The Watch's logbook, for "Seen 3× before".
    var logbook: Logbook? = nil

    private var heading: Double {
        watchSettings.northUp ? 0 : (location.heading ?? 0)
    }

    var body: some View {
        Group {
            if let contact = model.contact(id: flightID) {
                content(contact)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 26, weight: .light))
                    Text("Dropped off radar").font(.mono(13, .bold))
                    Text("This aircraft is no longer in the feed.").font(.mono(10)).foregroundStyle(Palette.caption)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.ink)
            }
        }
        .navigationTitle(model.contact(id: flightID)?.flight.displayIdentifier ?? "Flight")
        .userActivity(WatchSync.handoffActivityType) { activity in
            activity.title = model.contact(id: flightID)?.flight.displayIdentifier
            activity.userInfo = [WatchSync.handoffFlightKey: flightID]
            activity.isEligibleForHandoff = true
        }
    }

    private func content(_ contact: RadarContact) -> some View {
        let f = contact.flight
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                header(f)
                if let seen = logbook?.seenBeforeSummary(for: f) {
                    Label(seen, systemImage: "book.closed.fill")
                        .font(.mono(10, .semibold))
                        .foregroundStyle(Palette.route)
                        .lineLimit(2)
                }
                if let progress = RouteProgress(flight: f, position: contact.coordinate) {
                    routeProgress(progress)
                }
                live(contact)
                aircraft(f)
                if settings.showPhotos {
                    WatchAircraftPhoto(registration: f.registration, hex: f.hex, allowCellular: watchSettings.photosOnCellular)
                }
                actions(contact)
                Text("Open on iPhone from the Handoff icon in its app switcher.")
                    .font(.mono(9))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 2)
        }
        .background(Palette.paper.ignoresSafeArea())
    }

    // MARK: Sections

    private func header(_ f: Flight) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if !f.notable.isEmpty {
                ForEach(f.notable, id: \.tag) { NotableBadge(info: $0, scale: 0.72) }
            }
            Text(f.operatorInfo.headline)
                .font(.mono(10, .semibold))
                .foregroundStyle(Palette.caption)
                .lineLimit(2)
            Text(f.displayIdentifier)
                .font(.mono(24, .heavy))
                .foregroundStyle(Palette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if f.hasRoute {
                HStack(alignment: .top, spacing: 6) {
                    endpoint(code: f.originIATA, city: f.origin?.city)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Palette.signal)
                        .padding(.top, 3)
                    endpoint(code: f.destinationIATA, city: f.destination?.city)
                }
            }
        }
    }

    private func endpoint(code: String?, city: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(code ?? "—").font(.mono(16, .bold)).foregroundStyle(Palette.route)
            if let city {
                Text(city).font(.mono(9)).foregroundStyle(Palette.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

    private func routeProgress(_ p: RouteProgress) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: p.fraction)
                .tint(Palette.signal)
            HStack {
                Text("\(RadarFormat.wholeNumber(Int(p.flownMiles.rounded()))) mi flown")
                Spacer()
                Text("\(RadarFormat.wholeNumber(Int(p.remainingMiles.rounded()))) to go")
            }
            .font(.mono(9))
            .foregroundStyle(Palette.caption)
            if let seconds = p.remainingSeconds {
                Text("\(RouteProgress.duration(seconds)) to \(p.destination.city)")
                    .font(.mono(10, .semibold))
                    .foregroundStyle(Palette.value)
            }
        }
    }

    private func live(_ contact: RadarContact) -> some View {
        let f = contact.flight
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Right now")
            HStack(alignment: .top) {
                stat("Distance", "\(RadarFormat.distanceText(contact.distanceMiles))") {
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.signal)
                        .continuousRotation(contact.bearing - heading)
                }
                Spacer()
                stat("Altitude", "\(RadarFormat.altitudeText(contact.altitudeFeet))") {
                    switch f.verticalTrend {
                    case .climbing: Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .heavy)).foregroundStyle(Palette.live)
                    case .descending: Image(systemName: "arrow.down.right").font(.system(size: 8, weight: .heavy)).foregroundStyle(Palette.warning)
                    case .level: EmptyView()
                    }
                }
            }
            HStack(alignment: .top) {
                stat("Speed", "\(RadarFormat.speedText(f.groundSpeedKnots))") { EmptyView() }
                Spacer()
                stat("Look", GeoMath.cardinal(contact.bearing)) { EmptyView() }
            }
            if model.isStale {
                WatchStaleChip(since: model.sinceLastUpdate, retry: { model.refreshNow() })
            } else {
                WatchApproachChip(contact: contact)
            }
        }
    }

    private func aircraft(_ f: Flight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Aircraft")
            HStack(spacing: 5) {
                if let code = f.typeCode {
                    Text(code)
                        .font(.mono(11, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Palette.chip, in: Capsule())
                }
                if let name = f.typeName {
                    Text(name).font(.mono(10)).foregroundStyle(Palette.value).lineLimit(2)
                }
            }
            if let reg = f.registration {
                let country = f.registrationCountryCode
                Text([reg, country.map { "\(RegistrationCountry.flag(forCode: $0)) \(RegistrationCountry.countryName(forCode: $0))" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.mono(10))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(2)
            }
            if let squawk = f.squawk {
                Text("Squawk \(squawk)").font(.mono(9)).foregroundStyle(Palette.faint)
            }
        }
    }

    private func actions(_ contact: RadarContact) -> some View {
        VStack(spacing: 6) {
            Button {
                model.focus(on: contact.id)
                open(.find(contact.id))
            } label: {
                Label("Find in the Sky", systemImage: "hand.point.up.left.fill")
                    .font(.mono(12, .bold))
                    .frame(maxWidth: .infinity)
            }
            .tint(Palette.signal)

            let pinned = model.focus.focusedID == contact.id && model.focus.isPinned
            Button {
                if model.focus.focusedID != contact.id { model.focus(on: contact.id) }
                if model.focus.isPinned != !pinned { model.togglePin() }
            } label: {
                Label(pinned ? "Unpin" : "Pin to Center", systemImage: pinned ? "lock.open" : "lock")
                    .font(.mono(11, .semibold))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.mono(9, .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Palette.caption)
    }

    private func stat<Accessory: View>(_ title: String, _ value: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.mono(8, .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Palette.caption)
            HStack(spacing: 3) {
                Text(value).font(.mono(14, .semibold)).foregroundStyle(Palette.value).monospacedDigit()
                accessory()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Planespotters photo with the credit their terms require. Without "Photos on cellular" it
/// only loads over Wi-Fi or the iPhone's connection.
struct WatchAircraftPhoto: View {
    let registration: String?
    let hex: String?
    let allowCellular: Bool

    nonisolated static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map(UIImage.init(cgImage:))
    }

    @State private var photo: AircraftPhoto?
    @State private var image: UIImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                VStack(alignment: .leading, spacing: 2) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("© \(photo?.photographer ?? "Unknown") · Planespotters.net")
                        .font(.mono(8))
                        .foregroundStyle(Palette.faint)
                        .lineLimit(1)
                }
            } else if !loaded {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.chip.opacity(0.4))
                    .frame(height: 90)
                    .overlay(ProgressView())
            }
        }
        .task(id: registration ?? hex) {
            let provider = allowCellular ? AircraftPhotoProvider.shared : AircraftPhotoProvider.noCellular
            guard let found = await provider.photo(registration: registration, hex: hex),
                  let data = await provider.imageData(for: found) else {
                loaded = true
                return
            }
            photo = found
            // Decoded off the main thread at the screen's width, not the photo's.
            let maxPixels = Int(WKInterfaceDevice.current().screenBounds.width * WKInterfaceDevice.current().screenScale)
            image = await Task.detached(priority: .userInitiated) { Self.downsample(data, maxPixels: maxPixels) }.value
            loaded = true
        }
    }
}
