//
//  Onboarding.swift
//  WhatTheFlight
//
//  The first-run tour, shared by iPhone (`OnboardingView`) and Apple TV (`TVOnboardingView`):
//  one idea per page — the edge is a compass, the number is miles, the nearest takes the
//  center, tap it for details, Sky View, the logbook — each with a small animated drawing
//  made from the radar's own pieces and some made-up traffic. Replayable from Settings.
//

#if os(iOS) || os(tvOS)
import SwiftUI

struct TourPage: Identifiable {
    enum Art: String {
        case radar, edge, distance, center, details, sky, logbook, remote, ready
    }

    let art: Art
    let eyebrow: String
    let title: String
    let body: String

    var id: Art { art }

    #if os(tvOS)
    static let all: [TourPage] = [
        TourPage(art: .radar, eyebrow: "Welcome to What The Flight?", title: "Every aircraft around you",
                 body: "A live radar of the sky over your home, out to the radius you choose. Here's a one minute tour."),
        TourPage(art: .edge, eyebrow: "Reading the radar", title: "The edge is a compass",
                 body: "Each icon sits on the edge of the screen in the direction of a real aircraft. The top of the screen is the way you face when you watch the TV: set it in Settings, or let the iPhone app measure it for you."),
        TourPage(art: .distance, eyebrow: "The icons", title: "The number is miles away",
                 body: "Beside each icon is how far that aircraft is from you, in whole miles. The nose points the way it's flying. Military aircraft are olive, and a colored dot means something notable."),
        TourPage(art: .remote, eyebrow: "The Siri Remote", title: "The nearest takes the center",
                 body: "The closest aircraft fills the middle and stays there until it leaves your radius. Press ◀ ▶ to step through the others, play/pause to pin one, and ▼ for the dock: Nearest, Aircraft, Logbook and Settings."),
        TourPage(art: .details, eyebrow: "Details", title: "Click for the full story",
                 body: "Click the center for a photo, the airline and aircraft type, where it's from and where it's going, how far along the route it is, and a map. If you've seen that exact plane before, it says so."),
        TourPage(art: .logbook, eyebrow: "Logbook", title: "Every plane gets logged",
                 body: "Anything that comes inside your radius goes in the logbook: totals, records like closest and fastest, and badges to earn. Press ▼ and choose Logbook."),
        TourPage(art: .ready, eyebrow: "One last thing", title: "Where is home?",
                 body: "An Apple TV has no GPS, so tell it where it is: search for an address, send your spot from the iPhone app, or use this Apple TV's own location."),
    ]
    #else
    static let all: [TourPage] = [
        TourPage(art: .radar, eyebrow: "Welcome to What The Flight?", title: "Every aircraft around you",
                 body: "A live radar of the sky over you, out to the radius you choose. Here's a one minute tour."),
        TourPage(art: .edge, eyebrow: "Reading the radar", title: "The edge is a compass",
                 body: "Each icon sits on the edge of the screen in the direction of a real aircraft. Turn around and they slide around the edge, so whatever is at the top is in front of you."),
        TourPage(art: .distance, eyebrow: "The icons", title: "The number is miles away",
                 body: "Beside each icon is how far that aircraft is from you, in whole miles. The nose points the way it's flying. Military aircraft are olive, and a colored dot means something notable."),
        TourPage(art: .center, eyebrow: "The center", title: "The nearest takes the center",
                 body: "The closest aircraft fills the middle and stays there until it leaves your radius. Swipe left for the next one out, right to come back to the nearest. Tap an icon to bring it in; hold the center to pin it."),
        TourPage(art: .details, eyebrow: "Details", title: "Tap the center for the full story",
                 body: "A photo, the airline and aircraft type, where it's from and where it's going, how far along the route it is, and a map. If you've seen that exact plane before, it says so."),
        TourPage(art: .sky, eyebrow: "Sky View", title: "Point your phone at the sky",
                 body: "Point your phone at the sky and the camera opens with every aircraft labeled where it really is. Line one up in the circle to lock on; lower the phone to go back. \"Find in the Sky\" on a flight's details points you right to it."),
        TourPage(art: .logbook, eyebrow: "Logbook", title: "Every plane gets logged",
                 body: "Anything that comes inside your radius goes in your logbook: totals, records like closest and fastest, and badges to earn. Swipe down and tap Logbook, or find it in Settings."),
        TourPage(art: .ready, eyebrow: "One last thing", title: "Let's find some planes",
                 body: "What The Flight? uses your location to ask for the aircraft around you. Indoors, or just looking around? Try demo traffic — you can switch it off in Settings."),
    ]
    #endif
}

// MARK: - Drawings

/// The drawing for one page, laid out on a 300-point square (`unit` 1 on iPhone, larger on TV).
struct TourArt: View {
    let art: TourPage.Art
    var unit: CGFloat = 1

    var body: some View {
        Group {
            switch art {
            case .radar: TourRadar(unit: unit)
            case .edge: TourEdge(unit: unit)
            case .distance: TourDistance(unit: unit)
            case .center: TourCenter(unit: unit)
            case .details: TourDetails(unit: unit)
            case .sky: TourSky(unit: unit)
            case .logbook: TourLogbook(unit: unit)
            case .remote: TourRemote(unit: unit)
            case .ready: TourReady(unit: unit)
            }
        }
        .accessibilityHidden(true)
    }

    /// Width in points of the real screen the miniature stands for.
    static var screenWidth: CGFloat {
        #if os(tvOS)
        1920
        #else
        402
        #endif
    }

    /// The device the miniature radar is drawn in: a portrait phone, or a landscape TV.
    static var deviceSize: CGSize {
        #if os(tvOS)
        CGSize(width: 300, height: 170)
        #else
        CGSize(width: 150, height: 300)
        #endif
    }
}

/// Made-up traffic for the drawings, nearest first.
private struct TourTraffic {
    let flight: String
    let route: String
    let bearing: Double
    let miles: Int
    let track: Double
    let silhouette: AircraftSilhouette

    static let all: [TourTraffic] = [
        TourTraffic(flight: "DL1199", route: "ATL → ORD", bearing: 35, miles: 4, track: 250, silhouette: .airliner),
        TourTraffic(flight: "N911LF", route: "LOCAL FLIGHT", bearing: 250, miles: 6, track: 80, silhouette: .helicopter),
        TourTraffic(flight: "UA482", route: "EWR → SFO", bearing: 170, miles: 11, track: 15, silhouette: .widebody),
        TourTraffic(flight: "AA2207", route: "DFW → CLT", bearing: 110, miles: 14, track: 320, silhouette: .regional),
        TourTraffic(flight: "N88JX", route: "PDK → TEB", bearing: 315, miles: 18, track: 150, silhouette: .bizjet),
    ]
}

/// A phone (or TV) showing the radar: icons on the edge at their bearing, mile labels, and
/// the focused aircraft in the middle.
private struct MiniRadar: View {
    var unit: CGFloat
    var heading: Double = 0
    var focused: Int? = 0
    var showHero = true
    var showNorth = false
    var sweep = false
    /// Drawn on top of the radar, inside the screen.
    var screen: AnyView? = nil

    var body: some View {
        let size = CGSize(width: TourArt.deviceSize.width * unit, height: TourArt.deviceSize.height * unit)
        DeviceFrame(unit: unit) {
            ZStack {
                // A whole screen's worth of contours, shrunk to the miniature.
                RadarBackdrop(showTopography: true, showSweep: sweep, isActive: true,
                              topographyZoom: TourArt.screenWidth / size.width)
                if showNorth {
                    Text("N")
                        .font(.mono(11 * unit, .heavy))
                        .foregroundStyle(Palette.signal)
                        .position(Self.edgePoint(-heading, in: size, inset: 8 * unit))
                }
                ForEach(Array(TourTraffic.all.enumerated()), id: \.offset) { index, traffic in
                    let angle = traffic.bearing - heading
                    let isFocused = index == focused
                    Text("\(traffic.miles)")
                        .font(.mono((isFocused ? 10 : 9) * unit, .bold))
                        .foregroundStyle(isFocused ? Palette.signal : Palette.blip)
                        .paperHalo()
                        .position(Self.edgePoint(angle, in: size, inset: 34 * unit))
                    ZStack {
                        if isFocused {
                            Circle().fill(Palette.signal.opacity(0.16)).frame(width: 26 * unit, height: 26 * unit)
                        }
                        AircraftGlyph(silhouette: traffic.silhouette, size: 20 * unit)
                            .foregroundStyle(isFocused ? Palette.signal : Palette.blip)
                            .rotationEffect(.degrees(traffic.track - heading))
                    }
                    .position(Self.edgePoint(angle, in: size, inset: 17 * unit))
                }
                if showHero, let focused {
                    MiniHero(traffic: TourTraffic.all[focused], unit: unit)
                        .id(focused)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if let screen { screen }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    /// Where a ray from the center at `angle` (0 = up, clockwise) meets the edge, `inset` in.
    /// On the phone the top edge sits lower, clear of the Dynamic Island, as on the real radar.
    static func edgePoint(_ angle: Double, in size: CGSize, inset: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        let dx = sin(radians), dy = -cos(radians)
        #if os(tvOS)
        let island: CGFloat = 0
        #else
        let island = size.height * 0.06
        #endif
        let halfW = size.width / 2 - inset
        let halfH = size.height / 2 - inset - (dy < 0 ? island : 0)
        let t = min(abs(dx) > 0.0001 ? halfW / abs(dx) : .infinity, abs(dy) > 0.0001 ? halfH / abs(dy) : .infinity)
        return CGPoint(x: size.width / 2 + t * dx, y: size.height / 2 + t * dy)
    }
}

private struct MiniHero: View {
    let traffic: TourTraffic
    let unit: CGFloat

    var body: some View {
        VStack(spacing: 2 * unit) {
            Text(traffic.flight)
                .font(.mono(19 * unit, .heavy))
                .foregroundStyle(Palette.ink)
            Text(traffic.route)
                .font(.mono(8 * unit, .semibold))
                .foregroundStyle(Palette.route)
            Text("\(traffic.miles) MI")
                .font(.mono(8 * unit, .bold))
                .foregroundStyle(Palette.signal)
                .padding(.top, 4 * unit)
        }
        .paperHalo()
    }
}

/// The drawn devices are dark in both appearances, with a hairline so they show up at night.
private enum DeviceColor {
    static let body = Color(white: 0.13)
    static let edge = Palette.faint.opacity(0.7)
}

/// Phone outline with a Dynamic Island, or a TV on a small stand.
private struct DeviceFrame<Content: View>: View {
    let unit: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        #if os(tvOS)
        VStack(spacing: 0) {
            content
                .clipShape(RoundedRectangle(cornerRadius: 4 * unit, style: .continuous))
                .padding(4 * unit)
                .background(DeviceColor.body, in: RoundedRectangle(cornerRadius: 7 * unit, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7 * unit, style: .continuous).stroke(DeviceColor.edge, lineWidth: unit))
            Capsule()
                .fill(DeviceColor.body)
                .overlay(Capsule().stroke(DeviceColor.edge, lineWidth: unit))
                .frame(width: 70 * unit, height: 5 * unit)
                .padding(.top, 6 * unit)
        }
        .shadow(color: .black.opacity(0.18), radius: 14 * unit, y: 6 * unit)
        #else
        content
            .clipShape(RoundedRectangle(cornerRadius: 22 * unit, style: .continuous))
            .overlay(alignment: .top) {
                Capsule().fill(DeviceColor.body).frame(width: 40 * unit, height: 11 * unit).padding(.top, 6 * unit)
            }
            .padding(5 * unit)
            .background(DeviceColor.body, in: RoundedRectangle(cornerRadius: 27 * unit, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 27 * unit, style: .continuous).stroke(DeviceColor.edge, lineWidth: unit))
            .shadow(color: .black.opacity(0.18), radius: 14 * unit, y: 6 * unit)
        #endif
    }
}

// MARK: Pages

private struct TourRadar: View {
    let unit: CGFloat
    var body: some View {
        MiniRadar(unit: unit, sweep: true)
    }
}

/// The phone turns; the icons slide around the edge to stay pointed at their aircraft.
private struct TourEdge: View {
    let unit: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let heading = reduceMotion ? 0 : GeoMath.normalize(55 * sin(t * 0.55))
            VStack(spacing: 14 * unit) {
                MiniRadar(unit: unit, heading: heading, focused: nil, showHero: false, showNorth: true)
                    .overlay {
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 22 * unit, weight: .bold))
                            .foregroundStyle(Palette.ink)
                    }
                Text("FACING \(String(format: "%03d", Int(heading.rounded()) % 360))° \(GeoMath.cardinal(heading))")
                    .font(.mono(11 * unit, .bold))
                    .tracking(1.5 * unit)
                    .foregroundStyle(Palette.caption)
                    .monospacedDigit()
            }
        }
    }
}

/// One icon up close, then a key: the number, the nose, the colors.
private struct TourDistance: View {
    let unit: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 22 * unit) {
            ZStack {
                // Dashed path ahead of the nose.
                Path { path in
                    path.move(to: CGPoint(x: 60 * unit, y: 40 * unit))
                    path.addLine(to: CGPoint(x: 120 * unit, y: 0))
                }
                .stroke(Palette.blip.opacity(0.5), style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round, dash: [3 * unit, 6 * unit]))
                AircraftGlyph(silhouette: .airliner, size: 70 * unit)
                    .foregroundStyle(Palette.blip)
                    .rotationEffect(.degrees(56))
                    .position(x: 40 * unit, y: 54 * unit)
                Text("7")
                    .font(.mono(44 * unit, .bold))
                    .foregroundStyle(Palette.blip)
                    .paperHalo()
                    .scaleEffect(pulse ? 1.1 : 1)
                    .position(x: 112 * unit, y: 90 * unit)
                callout("miles away", at: CGPoint(x: 182 * unit, y: 96 * unit))
                callout("flying this way", at: CGPoint(x: 172 * unit, y: 6 * unit))
            }
            .frame(width: 240 * unit, height: 130 * unit)

            HStack(spacing: 14 * unit) {
                key(.airliner, Palette.blip, "Aircraft")
                key(.helicopter, Palette.blip, "Helicopter")
                key(.fighter, Palette.military, "Military")
                VStack(spacing: 6 * unit) {
                    ZStack(alignment: .topTrailing) {
                        AircraftGlyph(silhouette: .fourEngine, size: 30 * unit).foregroundStyle(Palette.blip)
                        Circle().fill(Palette.notable).frame(width: 9 * unit, height: 9 * unit)
                            .overlay(Circle().stroke(Palette.paper, lineWidth: 1.5 * unit))
                    }
                    keyLabel("Notable")
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true }
        }
    }

    private func callout(_ text: String, at point: CGPoint) -> some View {
        Text(text)
            .font(.mono(11 * unit, .semibold))
            .foregroundStyle(Palette.caption)
            .fixedSize()
            .position(point)
    }

    private func key(_ silhouette: AircraftSilhouette, _ tint: Color, _ title: String) -> some View {
        VStack(spacing: 6 * unit) {
            AircraftGlyph(silhouette: silhouette, size: 30 * unit, spinsRotor: false).foregroundStyle(tint)
            keyLabel(title)
        }
    }

    private func keyLabel(_ title: String) -> some View {
        Text(title)
            .font(.mono(9 * unit, .semibold))
            .textCase(.uppercase)
            .foregroundStyle(Palette.caption)
            .fixedSize()
    }
}

/// Swipe left twice to step out through the traffic, then right to snap back to the nearest.
private struct TourCenter: View {
    let unit: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 2.4

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let step = reduceMotion ? 0 : Int(t / Self.period) % 3
            let phase = (t / Self.period).truncatingRemainder(dividingBy: 1)
            // The swipe that leads to the next step: left (farther) twice, then right (nearest).
            let leftward = step < 2
            let swipe = max(0, min(1, (phase - 0.55) / 0.3))
            let size = TourArt.deviceSize
            MiniRadar(unit: unit, focused: step, screen: AnyView(
                ZStack {
                    if !reduceMotion && swipe > 0 && swipe < 1 {
                        Circle()
                            .fill(Palette.ink.opacity(0.28))
                            .overlay(Circle().stroke(Palette.ink.opacity(0.6), lineWidth: 1.5 * unit))
                            .frame(width: 26 * unit, height: 26 * unit)
                            .offset(x: (leftward ? 1 - 2 * swipe : -1 + 2 * swipe) * size.width * 0.22 * unit,
                                    y: size.height * 0.14 * unit)
                            .opacity(sin(swipe * .pi))
                    }
                    if !reduceMotion {
                        Text(leftward ? "SWIPE ←  NEXT OUT" : "SWIPE →  NEAREST")
                            .font(.mono(8 * unit, .bold))
                            .foregroundStyle(Palette.caption)
                            .padding(.horizontal, 8 * unit)
                            .padding(.vertical, 4 * unit)
                            .background(Palette.paperShade.opacity(0.7), in: Capsule())
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 44 * unit)
                    }
                }
            ))
            .animation(.snappy, value: step)
        }
    }
}

/// A tap on the center, and the details sheet slides up.
private struct TourDetails: View {
    let unit: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: CaseIterable { case idle, tap, open }

    var body: some View {
        if reduceMotion {
            scene(tap: false, open: true)
        } else {
            MiniRadar(unit: unit)
                .hidden()
                .overlay {
                    Color.clear.phaseAnimator(Phase.allCases) { _, phase in
                        scene(tap: phase == .tap, open: phase == .open)
                    } animation: { phase in
                        switch phase {
                        case .idle: .easeInOut(duration: 0.5).delay(2.6)
                        case .tap: .easeOut(duration: 0.35).delay(0.9)
                        case .open: .spring(response: 0.55, dampingFraction: 0.85).delay(0.1)
                        }
                    }
                }
        }
    }

    private func scene(tap: Bool, open: Bool) -> some View {
        let size = CGSize(width: TourArt.deviceSize.width * unit, height: TourArt.deviceSize.height * unit)
        #if os(tvOS)
        // The TV's details are a full screen; here a panel rising over the radar stands in.
        let card = CGSize(width: size.width * 0.5, height: size.height * 0.94)
        #else
        let card = CGSize(width: size.width, height: size.height * 0.68)
        #endif
        return MiniRadar(unit: unit, screen: AnyView(
            ZStack(alignment: .bottom) {
                Circle()
                    .stroke(Palette.ink.opacity(0.6), lineWidth: 2 * unit)
                    .background(Circle().fill(Palette.ink.opacity(0.18)))
                    .frame(width: 30 * unit, height: 30 * unit)
                    .scaleEffect(tap ? 1.25 : 0.6)
                    .opacity(tap ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                DetailCard(unit: unit)
                    .frame(width: card.width, height: card.height, alignment: .top)
                    .background(Palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 14 * unit, topTrailingRadius: 14 * unit))
                    .shadow(color: .black.opacity(0.2), radius: 10 * unit, y: -2 * unit)
                    .offset(y: open ? 0 : card.height + 20 * unit)
            }
        ))
    }

    private struct DetailCard: View {
        let unit: CGFloat

        var body: some View {
            VStack(alignment: .leading, spacing: 7 * unit) {
                Capsule().fill(Palette.faint).frame(width: 26 * unit, height: 3 * unit).frame(maxWidth: .infinity)
                ZStack {
                    LinearGradient(colors: [Color(red: 0.42, green: 0.62, blue: 0.9), Color(red: 0.78, green: 0.87, blue: 0.97)],
                                   startPoint: .top, endPoint: .bottom)
                    AircraftGlyph(silhouette: .airliner, size: 44 * unit).foregroundStyle(.white).rotationEffect(.degrees(90))
                }
                .frame(height: 52 * unit)
                .clipShape(RoundedRectangle(cornerRadius: 8 * unit, style: .continuous))
                Text("DL1199").font(.mono(14 * unit, .heavy)).foregroundStyle(Palette.ink)
                Text("Delta · Airbus A321neo").font(.mono(7 * unit, .medium)).foregroundStyle(Palette.caption)
                HStack(spacing: 5 * unit) {
                    Text("ATL").font(.mono(8 * unit, .bold)).foregroundStyle(Palette.route)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.faint.opacity(0.5)).frame(height: 2 * unit)
                            Capsule().fill(Palette.ink).frame(width: geo.size.width * 0.38, height: 2 * unit)
                            AircraftGlyph(silhouette: .airliner, size: 10 * unit).foregroundStyle(Palette.ink)
                                .rotationEffect(.degrees(90)).offset(x: geo.size.width * 0.38 - 5 * unit)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 10 * unit)
                    Text("ORD").font(.mono(8 * unit, .bold)).foregroundStyle(Palette.route)
                }
                Text("SEEN 3× BEFORE")
                    .font(.mono(7 * unit, .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 6 * unit)
                    .padding(.vertical, 3 * unit)
                    .background(Palette.ink.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10 * unit)
            .padding(.top, 6 * unit)
        }
    }
}

/// The phone lifts from flat (radar) to upright (camera, every aircraft labeled).
private struct TourSky: View {
    let unit: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            phone(raised: true)
        } else {
            phone(raised: true)
                .hidden()
                .overlay {
                    Color.clear.phaseAnimator([false, true]) { _, raised in
                        phone(raised: raised)
                    } animation: { raised in
                        raised ? .spring(response: 0.9, dampingFraction: 0.8).delay(0.8) : .easeInOut(duration: 0.9).delay(2.2)
                    }
                }
        }
    }

    private func phone(raised: Bool) -> some View {
        let size = CGSize(width: 140 * unit, height: 260 * unit)
        return ZStack {
            Palette.paper
            RangeRings().stroke(Palette.ink.opacity(0.12), style: StrokeStyle(lineWidth: unit, dash: [2, 5]))
            skyCamera(size: size)
                .opacity(raised ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 20 * unit, style: .continuous))
        .padding(5 * unit)
        .background(DeviceColor.body, in: RoundedRectangle(cornerRadius: 25 * unit, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 25 * unit, style: .continuous).stroke(DeviceColor.edge, lineWidth: unit))
        .rotation3DEffect(.degrees(raised ? 0 : 62), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
        .shadow(color: .black.opacity(0.2), radius: 14 * unit, y: 8 * unit)
        .overlay(alignment: .top) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18 * unit, weight: .bold))
                .foregroundStyle(Palette.signal)
                .offset(y: -26 * unit)
                .opacity(raised ? 0 : 1)
        }
    }

    private func skyCamera(size: CGSize) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.24, green: 0.45, blue: 0.82), Color(red: 0.62, green: 0.79, blue: 0.96)],
                           startPoint: .top, endPoint: .bottom)
            // Horizon with compass ticks.
            VStack(spacing: 3 * unit) {
                Rectangle().fill(.white.opacity(0.7)).frame(height: unit)
                HStack {
                    ForEach(["NW", "N", "NE"], id: \.self) { mark in
                        Text(mark).font(.mono(7 * unit, .bold)).foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity)
                    }
                }
            }
            .offset(y: size.height * 0.34)

            AircraftGlyph(silhouette: .airliner, size: 18 * unit)
                .foregroundStyle(.white)
                .rotationEffect(.degrees(70))
                .offset(x: -6 * unit, y: -size.height * 0.08)
            Circle()
                .stroke(.white, lineWidth: 1.5 * unit)
                .frame(width: 40 * unit, height: 40 * unit)
                .offset(x: -6 * unit, y: -size.height * 0.08)
            VStack(spacing: 1 * unit) {
                Text("DL1199").font(.mono(10 * unit, .heavy))
                Text("4 MI · 9,500 FT").font(.mono(7 * unit, .semibold)).opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2 * unit)
            .offset(x: -6 * unit, y: -size.height * 0.08 + 36 * unit)

            Text("UA482")
                .font(.mono(8 * unit, .bold))
                .foregroundStyle(.white.opacity(0.85))
                .offset(x: size.width * 0.26, y: -size.height * 0.3)
            Image(systemName: "chevron.left")
                .font(.system(size: 12 * unit, weight: .heavy))
                .foregroundStyle(.white.opacity(0.8))
                .offset(x: -size.width * 0.42, y: size.height * 0.1)
        }
    }
}

/// Stat tiles, a record and a row of badges.
private struct TourLogbook: View {
    let unit: CGFloat
    @State private var unlocked = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * unit) {
            Text("Logbook")
                .font(.mono(22 * unit, .heavy))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 8 * unit) {
                LogbookStatTile(title: "Spotted", value: "128", scale: unit * 0.85)
                LogbookStatTile(title: "Types", value: "31", scale: unit * 0.85)
                LogbookStatTile(title: "Airlines", value: "17", scale: unit * 0.85)
            }
            HStack(spacing: 10 * unit) {
                Image(systemName: "scope").foregroundStyle(Palette.signal)
                Text("Closest").foregroundStyle(Palette.caption)
                Spacer()
                Text("DL1199 · <1 mi").foregroundStyle(Palette.value)
            }
            .font(.mono(11 * unit, .semibold))
            .padding(10 * unit)
            .background(Palette.paperShade.opacity(0.35), in: RoundedRectangle(cornerRadius: 12 * unit, style: .continuous))
            HStack(spacing: 12 * unit) {
                badge("crown.fill", Palette.notable, earned: unlocked)
                badge("airplane", Palette.ink, earned: true)
                badge("scope", Palette.signal, earned: true)
                badge("moon.stars.fill", Palette.route, earned: true)
                badge("binoculars.fill", Palette.faint, earned: false)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4 * unit)
        }
        .frame(width: 280 * unit)
        .onAppear {
            guard !reduceMotion else { unlocked = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.6)) { unlocked = true }
        }
    }

    private func badge(_ symbol: String, _ tint: Color, earned: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18 * unit, weight: .bold))
            .foregroundStyle(earned ? tint : Palette.faint)
            .frame(width: 44 * unit, height: 44 * unit)
            .background(Circle().fill(earned ? tint.opacity(0.14) : Palette.paperShade.opacity(0.35)))
            .overlay(Circle().stroke(earned ? tint.opacity(0.6) : Palette.faint.opacity(0.4), lineWidth: 1.5 * unit))
            .scaleEffect(earned ? 1 : 0.88)
    }
}

/// A Siri Remote with the radar's keys, lighting up one at a time.
private struct TourRemote: View {
    let unit: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Key: Int, CaseIterable { case sides, click, playPause, down }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.6)) { context in
            let lit = reduceMotion ? nil : Key(rawValue: Int(context.date.timeIntervalSinceReferenceDate / 1.6) % Key.allCases.count)
            HStack(spacing: 34 * unit) {
                remote(lit: lit)
                VStack(alignment: .leading, spacing: 16 * unit) {
                    row(["arrowtriangle.left.fill", "arrowtriangle.right.fill"], "Other aircraft", lit: lit == .sides)
                    row(["circle.circle"], "Details", lit: lit == .click)
                    row(["playpause.fill"], "Pin", lit: lit == .playPause)
                    row(["arrowtriangle.down.fill"], "Dock", lit: lit == .down)
                }
            }
            .animation(.smooth(duration: 0.3), value: lit)
        }
    }

    private func remote(lit: Key?) -> some View {
        VStack(spacing: 14 * unit) {
            ZStack {
                Circle().fill(Palette.paperShade).frame(width: 74 * unit, height: 74 * unit)
                Circle().fill(lit == .click ? Palette.signal.opacity(0.35) : Palette.paper).frame(width: 34 * unit, height: 34 * unit)
                arrow("arrowtriangle.left.fill", lit: lit == .sides).offset(x: -26 * unit)
                arrow("arrowtriangle.right.fill", lit: lit == .sides).offset(x: 26 * unit)
                arrow("arrowtriangle.up.fill", lit: false).offset(y: -26 * unit)
                arrow("arrowtriangle.down.fill", lit: lit == .down).offset(y: 26 * unit)
            }
            HStack(spacing: 12 * unit) {
                button("chevron.backward", lit: false)
                button("tv", lit: false)
            }
            HStack(spacing: 12 * unit) {
                button("playpause.fill", lit: lit == .playPause)
                button("speaker.slash.fill", lit: false)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10 * unit)
        .frame(width: 94 * unit, height: 230 * unit)
        .background(Palette.value.opacity(0.88), in: RoundedRectangle(cornerRadius: 30 * unit, style: .continuous))
    }

    private func arrow(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8 * unit, weight: .bold))
            .foregroundStyle(lit ? Palette.signal : Palette.caption)
            .scaleEffect(lit ? 1.5 : 1)
    }

    private func button(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9 * unit, weight: .bold))
            .foregroundStyle(lit ? Color.white : Palette.paper)
            .frame(width: 26 * unit, height: 26 * unit)
            .background(Circle().fill(lit ? Palette.signal : Palette.caption.opacity(0.6)))
    }

    private func row(_ symbols: [String], _ title: String, lit: Bool) -> some View {
        HStack(spacing: 10 * unit) {
            HStack(spacing: 4 * unit) {
                ForEach(symbols, id: \.self) { Image(systemName: $0) }
            }
            .font(.system(size: 9 * unit, weight: .bold))
            .foregroundStyle(lit ? Color.white : Palette.value)
            .padding(.horizontal, 8 * unit)
            .frame(height: 22 * unit)
            .background(lit ? Palette.signal : Palette.paperShade.opacity(0.6), in: Capsule())
            Text(title)
                .font(.mono(12 * unit, .semibold))
                .foregroundStyle(lit ? Palette.value : Palette.caption)
        }
    }
}

/// A location pin with rings rippling out and aircraft circling.
private struct TourReady: View {
    let unit: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { ring in
                    let progress = (t / 3 + Double(ring) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Palette.signal.opacity(0.5 * (1 - progress)), lineWidth: 2 * unit)
                        .frame(width: (60 + 200 * progress) * unit, height: (60 + 200 * progress) * unit)
                }
                Circle().stroke(Palette.ink.opacity(0.15), style: StrokeStyle(lineWidth: unit, dash: [2, 5]))
                    .frame(width: 220 * unit, height: 220 * unit)
                ForEach(Array([0.0, 130, 245].enumerated()), id: \.offset) { index, start in
                    let angle = start + t * (index == 1 ? -14 : 10)
                    let radians = angle * .pi / 180
                    AircraftGlyph(silhouette: index == 1 ? .regional : .airliner, size: 24 * unit)
                        .foregroundStyle(Palette.blip)
                        .rotationEffect(.degrees(angle + (index == 1 ? -90 : 90)))
                        .offset(x: sin(radians) * 110 * unit, y: -cos(radians) * 110 * unit)
                }
                Image(systemName: Self.symbol)
                    .font(.system(size: 26 * unit, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 62 * unit, height: 62 * unit)
                    .background(Circle().fill(Palette.signal))
                    .shadow(color: Palette.signal.opacity(0.4), radius: 10 * unit, y: 4 * unit)
            }
            .frame(width: 280 * unit, height: 280 * unit)
        }
    }

    #if os(tvOS)
    private static let symbol = "house.fill"
    #else
    private static let symbol = "location.fill"
    #endif
}

// MARK: - Page dots

struct TourDots: View {
    let count: Int
    let current: Int
    var unit: CGFloat = 1

    var body: some View {
        HStack(spacing: 7 * unit) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.signal : Palette.faint.opacity(0.6))
                    .frame(width: (index == current ? 20 : 7) * unit, height: 7 * unit)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
#endif

// MARK: - iPhone

#if os(iOS)
struct OnboardingView: View {
    let onStart: () -> Void
    let onDemo: () -> Void

    #if DEBUG
    /// `-wtf.debugTourPage 3` opens the tour on that page (screenshots).
    @State private var page = min(max(UserDefaults.standard.integer(forKey: "wtf.debugTourPage"), 0), TourPage.all.count - 1)
    #else
    @State private var page = 0
    #endif

    private let pages = TourPage.all
    private var isLast: Bool { page == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { withAnimation(.smooth) { page = pages.count - 1 } }
                    .font(.mono(14, .semibold))
                    .foregroundStyle(Palette.caption)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    OnboardingPageView(page: item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            TourDots(count: pages.count, current: page)
                .padding(.bottom, 18)

            VStack(spacing: 12) {
                if isLast {
                    Button(action: onStart) {
                        Text("Start Watching").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RadarButtonStyle(prominent: true))
                    Button("Try Demo Traffic", action: onDemo)
                        .font(.mono(13, .semibold))
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 4)
                } else {
                    Button {
                        withAnimation(.smooth) { page += 1 }
                    } label: {
                        Text("Next").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RadarButtonStyle(prominent: true))
                    // Keeps the button where it is on the last page, which has two.
                    Text(" ").font(.mono(13, .semibold)).padding(.vertical, 4).hidden()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .background(Palette.paper.ignoresSafeArea())
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: page)
    }
}

private struct OnboardingPageView: View {
    let page: TourPage

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fit = min(1, geo.size.height / 320, geo.size.width / 320)
                TourArt(art: page.art)
                    .frame(width: 300, height: 300)
                    .scaleEffect(fit)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(minHeight: 200, maxHeight: 340)

            VStack(spacing: 10) {
                Text(page.eyebrow)
                    .radarCaption()
                Text(page.title)
                    .font(.mono(25, .heavy))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Text(page.body)
                    .font(.mono(13))
                    .foregroundStyle(Palette.value)
                    .lineSpacing(3)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
