//
//  FlightHero.swift
//  WhatTheFlight
//
//  The focused aircraft, front and centre — laid out after the mockup:
//  flight number, ORIGIN → DEST, type, altitude & speed, distance.
//

#if os(iOS) || os(tvOS)
import SwiftUI

struct FlightHero: View {
    let contact: RadarContact
    let isPinned: Bool
    /// Continuous device heading, for the "look this way" pointer.
    let heading: Double
    /// Landscape (TV) layout: altitude, speed and distance on one row.
    var wideStats = false
    /// Enlarges the type, stats and approach chip (the TV reads them from across the room).
    var detailScale: CGFloat = 1
    /// A short radar (the iPhone Duo's standing half in tabletop): no type line or approach
    /// chip, so the rest stays full size.
    var compact = false
    /// Where the aircraft's Planespotters photo goes, if anywhere. It only appears once there's
    /// a photo to show.
    var photo: PhotoPlacement = .none

    enum PhotoPlacement: Equatable {
        case none
        /// Under everything else, the stats and approach included (the radar's centre).
        case bottom
        /// Beside the flight number and route, the stats running full width underneath (the
        /// map card, whose single row of stats needs the room).
        case beside
        /// To the right of everything else, in a slot that's always there (the TV's radar): the
        /// details sit in a column of their own fixed width, so stepping from aircraft to
        /// aircraft never moves them, photo or not. Until the photo arrives, and for aircraft
        /// without one, the slot shows the aircraft's silhouette.
        case trailing(width: CGFloat)
    }

    /// `.trailing`: the details column's width, room for the widest row of TV stats.
    static let trailingDetailsWidth: CGFloat = 480
    static let trailingGap: CGFloat = 40

    private var flight: Flight { contact.flight }

    var body: some View {
        if case .trailing(let width) = photo {
            HStack(spacing: Self.trailingGap) {
                details
                    .frame(width: Self.trailingDetailsWidth)
                photoSlot(width: width)
            }
            .multilineTextAlignment(.center)
        } else {
            details
                .multilineTextAlignment(.center)
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            if let top = contact.profile.notable.first {
                NotableBadge(info: top, scale: detailScale)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
            }

            if photo == .beside {
                HStack(spacing: 0) {
                    identity
                        .frame(maxWidth: .infinity)
                    AircraftPhotoTile(registration: flight.registration, hex: flight.hex, width: 120, height: 80, gap: 12)
                }
            } else {
                identity
            }

            if !compact {
                typeLine
                    .padding(.top, 12)
            }

            stats
                .padding(.top, compact ? 18 : 26)

            if !compact {
                ApproachChip(contact: contact, scale: detailScale)
                    .padding(.top, 18)
            }

            if photo == .bottom {
                // A little bigger with the TV's larger details (150 × 100 on a phone, 180 × 120 on TV).
                let size = min(detailScale, 1.2)
                AircraftPhotoTile(registration: flight.registration, hex: flight.hex, width: 150 * size, height: 100 * size,
                                  gap: 18 * size, edge: .top, outline: Palette.ink.opacity(0.15))
            }
        }
    }

    /// `.trailing`: a 3 : 2 tile holding the aircraft's silhouette, which its photo covers once
    /// it has loaded.
    private func photoSlot(width: CGFloat) -> some View {
        let height = width * 2 / 3
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            shape.fill(Palette.ink.opacity(0.05))
            AircraftGlyph(silhouette: contact.profile.silhouette, size: height * 0.55, spinsRotor: false)
                .rotationEffect(.degrees(90))
                .foregroundStyle(Palette.ink.opacity(0.16))
            AircraftPhotoTile(registration: flight.registration, hex: flight.hex, width: width, height: height,
                              outline: .clear)
        }
        .frame(width: width, height: height)
        .overlay(shape.strokeBorder(Palette.ink.opacity(0.15), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    /// Who's flying, the flight number and the route.
    private var identity: some View {
        VStack(spacing: 0) {
            operatorLine
                .padding(.bottom, 4)

            Text(flight.displayIdentifier)
                .font(.mono(64, .heavy))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .paperHalo()
                .accessibilityAddTraits(.isHeader)

            if flight.hasRoute {
                RouteLine(flight: flight)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var operatorLine: some View {
        HStack(spacing: 6) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.signal)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(contact.profile.operatorInfo.headline)
                .radarCaption()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .animation(.snappy, value: isPinned)
    }

    @ViewBuilder
    private var typeLine: some View {
        VStack(spacing: 5 * detailScale) {
            // Unidentified aircraft already show their type code as the title.
            if let code = flight.typeCode, code != flight.displayIdentifier {
                Text(code)
                    .font(.mono(15 * detailScale, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10 * detailScale)
                    .padding(.vertical, 3 * detailScale)
                    .background(Palette.chip, in: Capsule())
            }
            if let name = contact.profile.typeName {
                Text(name)
                    .font(.mono(12 * detailScale, .medium))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        if wideStats {
            HStack(alignment: .top, spacing: 44 * detailScale) {
                altitudeStat
                speedStat
                distanceStat
            }
        } else {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 30) {
                    altitudeStat
                    speedStat
                }
                distanceStat
            }
        }
    }

    private var altitudeStat: some View {
        StatBlock(
            title: "Altitude",
            value: RadarFormat.wholeNumber(contact.altitudeFeet),
            numeric: Double(contact.altitudeFeet),
            unit: "ft",
            scale: detailScale,
            accessory: altitudeTrend
        )
    }

    private var speedStat: some View {
        StatBlock(
            title: "Speed",
            value: RadarFormat.wholeNumber(flight.groundSpeedKnots),
            numeric: Double(flight.groundSpeedKnots),
            unit: "kts",
            scale: detailScale
        )
    }

    private var distanceStat: some View {
        StatBlock(
            title: "Distance",
            value: RadarFormat.miles(contact.distanceMiles),
            numeric: contact.distanceMiles.rounded(),
            unit: "mi",
            scale: detailScale,
            accessory: AnyView(
                Image(systemName: "location.north.fill")
                    .font(.system(size: 12 * detailScale, weight: .bold))
                    .foregroundStyle(Palette.signal)
                    .continuousRotation(contact.bearing - heading)
                    .accessibilityLabel("Toward \(GeoMath.cardinal(contact.bearing))")
            )
        )
    }

    private var altitudeTrend: AnyView? {
        switch flight.verticalTrend {
        case .climbing:
            return AnyView(Image(systemName: "arrow.up.right").font(.system(size: 11 * detailScale, weight: .heavy)).foregroundStyle(Palette.live).accessibilityLabel("Climbing"))
        case .descending:
            return AnyView(Image(systemName: "arrow.down.right").font(.system(size: 11 * detailScale, weight: .heavy)).foregroundStyle(Palette.warning).accessibilityLabel("Descending"))
        case .level:
            return nil
        }
    }
}

struct RouteLine: View {
    let flight: Flight

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            endpoint(code: flight.originIATA ?? "—", city: flight.origin?.city)
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.signal)
                .padding(.top, 6)
            endpoint(code: flight.destinationIATA ?? "—", city: flight.destination?.city)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("From \(flight.origin?.city ?? flight.originIATA ?? "unknown") to \(flight.destination?.city ?? flight.destinationIATA ?? "unknown")")
    }

    private func endpoint(code: String, city: String?) -> some View {
        VStack(spacing: 1) {
            Text(code)
                .font(.mono(32, .bold))
                .foregroundStyle(Palette.route)
                .paperHalo()
            if let city {
                Text(city)
                    .font(.mono(10, .medium))
                    .foregroundStyle(Palette.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 96)
            }
        }
    }
}

struct StatBlock: View {
    let title: String
    let value: String
    let numeric: Double
    let unit: String
    var scale: CGFloat = 1
    var accessory: AnyView? = nil

    var body: some View {
        VStack(spacing: 3 * scale) {
            Text(title)
                .font(.mono(11 * scale, .semibold))
                .tracking(1.6 * scale)
                .foregroundStyle(Palette.caption)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                Text(value)
                    .font(.mono(22 * scale, .semibold))
                    .foregroundStyle(Palette.value)
                    .contentTransition(.numericText(value: numeric))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.mono(12 * scale, .medium))
                    .foregroundStyle(Palette.caption)
                if let accessory {
                    accessory
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 5 * scale }
                }
            }
            .paperHalo()
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Closest pass 2 mi in 1:12" / "OVERHEAD" / "Moving away".
struct ApproachChip: View {
    let contact: RadarContact
    var scale: CGFloat = 1
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if contact.distanceMiles < 0.75 {
                HStack(spacing: 6 * scale) {
                    Circle().fill(Palette.signal).frame(width: 7 * scale, height: 7 * scale)
                        .opacity(glow ? 0.25 : 1)
                    Text("OVERHEAD")
                        .font(.mono(13 * scale, .heavy))
                        .tracking(2 * scale)
                }
                .foregroundStyle(Palette.signal)
                .padding(.horizontal, 14 * scale)
                .padding(.vertical, 7 * scale)
                .background(Palette.signal.opacity(0.12), in: Capsule())
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever()) { glow = true }
                }
            } else if contact.isApproaching, contact.closestApproach.secondsFromNow < 3600 {
                HStack(spacing: 6 * scale) {
                    Image(systemName: "scope")
                        .font(.system(size: 11 * scale, weight: .bold))
                    Text("Closest pass \(RadarFormat.miles(contact.closestApproach.distanceMiles)) mi in \(RadarFormat.countdown(contact.closestApproach.secondsFromNow))")
                        .font(.mono(12 * scale, .semibold))
                        .contentTransition(.numericText(countsDown: true))
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 6 * scale)
                .background(Palette.ink.opacity(0.09), in: Capsule())
            } else {
                HStack(spacing: 6 * scale) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10 * scale, weight: .bold))
                    Text("Moving away")
                        .font(.mono(12 * scale, .medium))
                }
                .foregroundStyle(Palette.caption)
                .padding(.horizontal, 12 * scale)
                .padding(.vertical, 6 * scale)
            }
        }
        .animation(.snappy, value: contact.distanceMiles < 0.75)
    }
}

// MARK: - Centre states

struct CenterStateView: View {
    enum Kind: Equatable {
        case needsLocation(denied: Bool)
        case scanning
        case clearSkies(radius: Double)
        case error(String)
    }

    let kind: Kind
    var onPrimary: () -> Void = {}
    var onSecondary: () -> Void = {}

    /// The TV draws this unscaled, at 10-foot type sizes.
    #if os(tvOS)
    private let k: CGFloat = 2.2
    #else
    private let k: CGFloat = 1
    #endif

    var body: some View {
        VStack(spacing: 14 * k) {
            icon
                .font(.system(size: 44 * k, weight: .light))
                .foregroundStyle(Palette.ink)
                .padding(.bottom, 4)
            Text(title)
                .font(.mono(24 * k, .bold))
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(.mono(13 * k))
                .foregroundStyle(Palette.caption)
                .fixedSize(horizontal: false, vertical: true)
            #if os(tvOS)
            HStack(spacing: 30) {
                if let primary = primaryTitle {
                    Button(primary, action: onPrimary)
                        .buttonStyle(TVPillButtonStyle(prominent: true))
                }
                if let secondary = secondaryTitle {
                    Button(secondary, action: onSecondary)
                        .buttonStyle(TVPillButtonStyle(prominent: false))
                }
            }
            .padding(.top, 10)
            #else
            if let primary = primaryTitle {
                Button(action: onPrimary) {
                    Text(primary)
                        .font(.mono(14, .bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(Palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            if let secondary = secondaryTitle {
                Button(secondary, action: onSecondary)
                    .font(.mono(13, .semibold))
                    .foregroundStyle(Palette.ink)
            }
            #endif
        }
        .multilineTextAlignment(.center)
        .paperHalo()
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .needsLocation: Image(systemName: "location.slash")
        case .scanning: ScanningGlyph()
        case .clearSkies: Image(systemName: "sun.haze")
        case .error: Image(systemName: "antenna.radiowaves.left.and.right.slash")
        }
    }

    private var title: String {
        switch kind {
        case .needsLocation: return "Where are you?"
        case .scanning: return "Scanning…"
        case .clearSkies: return "Clear skies"
        case .error: return "No signal"
        }
    }

    private var message: String {
        switch kind {
        case .needsLocation(let denied):
            #if os(tvOS)
            return "Tell your Apple TV where it is and which way it faces — aim your iPhone at the TV, or search for a place."
            #else
            return denied
                ? "Location access is off. Turn it on, or drop a pin to watch any spot on Earth."
                : "What The Flight? needs your position to find what's flying over you."
            #endif
        case .scanning:
            return "Listening for aircraft overhead"
        case .clearSkies(let radius):
            return "Nothing airborne within \(Int(radius)) mi right now."
        case .error(let text):
            return text
        }
    }

    private var primaryTitle: String? {
        switch kind {
        case .needsLocation(let denied):
            #if os(tvOS)
            _ = denied
            return "Set Up Location"
            #else
            return denied ? "Open Settings" : "Use My Location"
            #endif
        case .scanning: return nil
        case .clearSkies(let radius): return radius < RadarSettings.radiusRange.upperBound ? "Widen to \(Int(min(RadarSettings.radiusRange.upperBound, radius * 2))) mi" : nil
        case .error: return "Try Again"
        }
    }

    private var secondaryTitle: String? {
        switch kind {
        case .needsLocation:
            #if os(tvOS)
            return "Try Demo Traffic"
            #else
            return "Pick a Spot on the Map"
            #endif
        default: return nil
        }
    }
}

/// A tiny animated scope used while the first data loads.
struct ScanningGlyph: View {
    @State private var spin = false
    #if os(tvOS)
    static let k: CGFloat = 2.2
    #else
    static let k: CGFloat = 1
    #endif

    var body: some View {
        ZStack {
            Circle().stroke(Palette.ink.opacity(0.25), lineWidth: 1.5)
            Circle().stroke(Palette.ink.opacity(0.15), lineWidth: 1).scaleEffect(0.55)
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(AngularGradient(colors: [Palette.ink.opacity(0), Palette.ink], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: 52 * Self.k, height: 52 * Self.k)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { spin = true }
        }
    }
}
#endif
