//
//  Onboarding.swift
//  WhatTheFlight
//
//  The first-run tour, shared by iPhone / iPad (`OnboardingView`) and Apple TV
//  (`TVOnboardingView`): a handful of short pages — the radar, the center, details, the map,
//  Sky View, the logbook — each with a small animated drawing made from the radar's own
//  pieces and some made-up traffic. Every drawing shows the device you're holding: an iPhone,
//  the iPhone Duo (folded, and opened like a book for the map), an iPad (turning on its side
//  for the map) or a TV. Replayable from Settings.
//

#if os(iOS) || os(tvOS)
import SwiftUI

/// The device the tour is drawn for.
enum TourDevice: String {
    case phone, duo, pad, tv
}

extension EnvironmentValues {
    #if os(tvOS)
    @Entry var tourDevice: TourDevice = .tv
    #else
    @Entry var tourDevice: TourDevice = .phone
    #endif
}

struct TourPage: Identifiable {
    enum Art: String {
        case radar, center, details, map, sky, logbook, remote, ready
    }

    let art: Art
    let eyebrow: String
    let title: String
    let body: String

    var id: Art { art }

    static func pages(for device: TourDevice) -> [TourPage] {
        if device == .tv { return tv }
        let name = switch device {
        case .duo: "iPhone Duo"
        case .pad: "iPad"
        default: "iPhone"
        }
        return [
            TourPage(art: .radar, eyebrow: "Welcome to What The Flight?", title: "Every aircraft around you",
                     body: "Each icon on the edge is a real aircraft in that direction, with how far away it is. Turn around and they turn with you."),
            TourPage(art: .center, eyebrow: "The center", title: "The nearest takes the center",
                     body: "Swipe left for the next one out and right to come back, or tap any icon. Hold the center to pin an aircraft and follow it anywhere."),
            TourPage(art: .details, eyebrow: "Details", title: "Tap for the full story",
                     body: "A photo, the airline and aircraft, the route and how far along it is. If you've seen that exact plane before, it says so."),
            mapPage(device),
            TourPage(art: .sky, eyebrow: "Sky View", title: "Point at the sky",
                     body: "Raise your \(name), or tap Sky View, and the camera labels every aircraft where it really is. Lock on to one to take its photo."),
            TourPage(art: .logbook, eyebrow: "Logbook", title: "Every plane gets logged",
                     body: "Everything that flies through your radius: totals, records, and badges to earn. Swipe down on the radar to open it."),
            TourPage(art: .ready, eyebrow: "One last thing", title: "Let's find some planes",
                     body: "Your location finds the aircraft around you, and you'll hear when one's about to pass overhead. Just looking? Try demo traffic."),
        ]
    }

    private static func mapPage(_ device: TourDevice) -> TourPage {
        switch device {
        case .pad:
            TourPage(art: .map, eyebrow: "The map", title: "Radar, split or map",
                     body: "Tap Split for a live map of the same traffic alongside the radar, Map for the map alone, and Radar to come back. A pinned aircraft leaves a yellow trail.")
        case .duo:
            TourPage(art: .map, eyebrow: "The map", title: "Unfold for the map",
                     body: "Open iPhone Duo halfway: the radar takes one side and a live map the other. A pinned aircraft leaves a yellow trail.")
        default:
            TourPage(art: .map, eyebrow: "The map", title: "Radar or map",
                     body: "Tap Map for a live map of the same traffic, and Radar to come back. A pinned aircraft leaves a yellow trail.")
        }
    }

    private static let tv: [TourPage] = [
        TourPage(art: .radar, eyebrow: "Welcome to What The Flight?", title: "Every aircraft around you",
                 body: "Each icon on the edge is a real aircraft in that direction, with how far away it is. The top of the screen is the way you face when you watch."),
        TourPage(art: .remote, eyebrow: "The Siri Remote", title: "The nearest takes the center",
                 body: "◀ ▶ step through the aircraft, click for the full story, play/pause pins one, and ▼ opens the dock."),
        TourPage(art: .map, eyebrow: "The map", title: "Radar, split or map",
                 body: "Press ▲ to switch views. A pinned aircraft leaves a yellow trail on the map."),
        TourPage(art: .logbook, eyebrow: "Logbook", title: "Every plane gets logged",
                 body: "Everything that flies through your radius: totals, records, and badges to earn. Press ▼, then Logbook."),
        TourPage(art: .ready, eyebrow: "One last thing", title: "Where is home?",
                 body: "An Apple TV has no GPS, so tell it where it is: search for an address, send your spot from the iPhone app, or use this Apple TV's location."),
    ]
}

// MARK: - Drawings

/// The drawing for one page, laid out on a 300-point square (`unit` 1 on iPhone and iPad,
/// larger on TV), for the device in `\.tourDevice`.
struct TourArt: View {
    let art: TourPage.Art
    var unit: CGFloat = 1

    @Environment(\.tourDevice) private var device

    var body: some View {
        let screen = TourScreen(device: device, unit: unit)
        Group {
            switch art {
            case .radar: TourRadar(screen: screen)
            case .center: TourCenter(screen: screen)
            case .details: TourDetails(screen: screen)
            case .map: TourMap(screen: screen)
            case .sky: TourSky(screen: screen)
            case .logbook: TourLogbook(unit: unit)
            case .remote: TourRemote(unit: unit)
            case .ready: TourReady(unit: unit)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A device's screen in a drawing, taken from the real layout and shrunk: an iPhone 17
/// (402 × 874), the iPhone Duo's cover screen (466 × 678, the system's strip down its right
/// side), an iPad Pro 11-inch (834 × 1210) and a 1080p TV.
private struct TourScreen {
    let device: TourDevice
    let unit: CGFloat
    var landscape = false
    /// iPad: the radar and the map together, the radar on the top half and the map below,
    /// under the bar (the map beside the radar on its side), as `RadarRootView` lays them out.
    var split = false

    /// The real screen, in points.
    var real: CGSize {
        switch device {
        case .phone: CGSize(width: 402, height: 874)
        case .duo: CGSize(width: 466, height: 678)
        case .pad: landscape ? CGSize(width: 1210, height: 834) : CGSize(width: 834, height: 1210)
        case .tv: CGSize(width: 1920, height: 1080)
        }
    }

    /// Drawing points per real point.
    var k: CGFloat {
        let base: CGFloat = switch device {
        case .phone: 0.32
        case .duo: 0.4
        case .pad: 0.22
        case .tv: 300.0 / 1920
        }
        return base * unit
    }

    /// The bar and the strip, drawn larger than life on the iPad, or they'd vanish.
    var chromeK: CGFloat { device == .pad ? 0.3 * unit : k }

    var size: CGSize { CGSize(width: real.width * k, height: real.height * k) }

    var splitting: TourScreen {
        var screen = self
        screen.split = true
        return screen
    }

    /// The Duo's strip down the right side (the vertical bar), in real points.
    static let strip: CGFloat = 84
    /// The radar's bar (`RadarControlBar.height`, `.sideMargin`, `.maxWidth`, iOS only), in
    /// real points.
    static let barHeight: CGFloat = 62
    static let barSideMargin: CGFloat = 21
    static let barMaxWidth: CGFloat = 480

    /// Where the radar's backdrop goes: the whole screen, or with the iPad's split the top half
    /// (the square on the left on its side).
    var radarPane: CGRect {
        guard device == .pad && split else { return CGRect(origin: .zero, size: size) }
        return landscape
            ? CGRect(x: 0, y: 0, width: size.height, height: size.height)
            : CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
    }

    /// The iPad's split: the map on the bottom half, or beside the radar on its side.
    var mapPane: CGRect? {
        guard device == .pad && split else { return nil }
        return landscape
            ? CGRect(x: size.height, y: 0, width: size.width - size.height, height: size.height)
            : CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
    }

    /// Where the icons and the hero go, in the radar pane's own coordinates: above the bar (or
    /// all the top half, the bar being over the map), left of the Duo's strip, or all of it.
    var face: CGRect {
        switch device {
        case .phone, .pad:
            CGRect(x: 0, y: 0, width: radarPane.width, height: min(radarPane.maxY, barTop - 3 * chromeK) - radarPane.minY)
        case .duo:
            CGRect(x: 0, y: 0, width: size.width - Self.strip * k, height: size.height)
        case .tv:
            CGRect(origin: .zero, size: size)
        }
    }

    /// The bar's top edge: 22 points off the bottom with a home indicator, as on the radar.
    var barTop: CGFloat { size.height - (22 + Self.barHeight) * chromeK }
    var barMid: CGPoint {
        CGPoint(x: radarPane.midX, y: size.height - (22 + Self.barHeight / 2) * chromeK)
    }

    /// Clear of the Dynamic Island.
    var islandClearance: CGFloat { device == .phone ? 40 * k : 0 }

    var iconSize: CGFloat {
        let base: CGFloat = switch device {
        case .phone: 16
        case .duo: 17
        case .pad: 14
        case .tv: 20
        }
        return base * unit
    }

    /// The flight number's point size.
    var heroSize: CGFloat {
        let base: CGFloat = switch device {
        case .phone: 16
        case .duo: 17
        case .pad: 18
        case .tv: 19
        }
        return base * unit
    }

    var cornerRadius: CGFloat {
        switch device {
        case .phone: 55 * k
        case .duo: 40 * k
        case .pad: 26 * k
        case .tv: 4 * unit
        }
    }

    var bezel: CGFloat {
        switch device {
        case .phone: 4.5 * unit
        case .duo: 5 * unit
        case .pad: 6 * unit
        case .tv: 4 * unit
        }
    }
}

/// Made-up traffic for the drawings, nearest first.
private struct TourTraffic {
    let flight: String
    let airline: String
    let route: String
    let bearing: Double
    let miles: Int
    let track: Double
    let silhouette: AircraftSilhouette

    static let all: [TourTraffic] = [
        TourTraffic(flight: "DL1199", airline: "Delta Air Lines", route: "ATL → ORD", bearing: 35, miles: 4, track: 250, silhouette: .airliner),
        TourTraffic(flight: "N911LF", airline: "Life Flight", route: "LOCAL FLIGHT", bearing: 250, miles: 6, track: 80, silhouette: .helicopter),
        TourTraffic(flight: "UA482", airline: "United Airlines", route: "EWR → SFO", bearing: 170, miles: 11, track: 15, silhouette: .widebody),
        TourTraffic(flight: "AA2207", airline: "American Airlines", route: "DFW → CLT", bearing: 110, miles: 14, track: 320, silhouette: .regional),
        TourTraffic(flight: "N88JX", airline: "Private", route: "PDK → TEB", bearing: 315, miles: 18, track: 150, silhouette: .bizjet),
    ]

    /// The map pages' pinned aircraft, with its yellow trail.
    static let pinnedOnMap = 2
}

/// Where a ray from the middle of `rect` at `angle` (0 = up, clockwise) meets its edge,
/// `inset` in; the top edge sits `top` lower still (the Dynamic Island).
private func edgePoint(_ angle: Double, in rect: CGRect, inset: CGFloat, top: CGFloat = 0) -> CGPoint {
    let radians = angle * .pi / 180
    let dx = sin(radians), dy = -cos(radians)
    let halfW = rect.width / 2 - inset
    let halfH = rect.height / 2 - inset - (dy < 0 ? top : 0)
    let t = min(abs(dx) > 0.0001 ? halfW / abs(dx) : .infinity, abs(dy) > 0.0001 ? halfH / abs(dy) : .infinity)
    return CGPoint(x: rect.midX + t * dx, y: rect.midY + t * dy)
}

/// The drawn devices are dark in both appearances, with a hairline so they show up at night.
private enum DeviceColor {
    static let body = Color(white: 0.13)
    static let edge = Palette.faint.opacity(0.7)
}

/// The radar's glass, drawn small.
private struct MiniGlass: ViewModifier {
    let shape: AnyShape

    func body(content: Content) -> some View {
        content
            .background(Palette.paper.opacity(0.78), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
    }
}

private extension View {
    func miniGlass<S: Shape>(_ shape: S) -> some View { modifier(MiniGlass(shape: AnyShape(shape))) }
}

// MARK: Devices

/// The device around a drawn screen: an iPhone with its Dynamic Island, the iPhone Duo
/// folded (its hinge down the left side, the camera at the top of its strip), an iPad with
/// the camera on its long edge, or a TV on a stand.
private struct DeviceShell<Content: View>: View {
    let screen: TourScreen
    @ViewBuilder let content: Content

    var body: some View {
        let u = screen.unit
        let size = screen.size
        if screen.device == .tv {
            VStack(spacing: 0) {
                content
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: screen.cornerRadius, style: .continuous))
                    .padding(screen.bezel)
                    .background(DeviceColor.body, in: RoundedRectangle(cornerRadius: 7 * u, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7 * u, style: .continuous).stroke(DeviceColor.edge, lineWidth: u))
                Capsule()
                    .fill(DeviceColor.body)
                    .overlay(Capsule().stroke(DeviceColor.edge, lineWidth: u))
                    .frame(width: 70 * u, height: 5 * u)
                    .padding(.top, 6 * u)
            }
            .shadow(color: .black.opacity(0.18), radius: 14 * u, y: 6 * u)
        } else {
            let outer = RoundedRectangle(cornerRadius: screen.cornerRadius + screen.bezel, style: .continuous)
            content
                .frame(width: size.width, height: size.height)
                .overlay(alignment: .topLeading) { camera }
                .clipShape(RoundedRectangle(cornerRadius: screen.cornerRadius, style: .continuous))
                .padding(screen.bezel)
                // Folded, the Duo's hinge is its left side.
                .padding(.leading, screen.device == .duo ? 3 * u : 0)
                .background(DeviceColor.body, in: outer)
                .overlay(outer.stroke(DeviceColor.edge, lineWidth: u))
                .overlay(alignment: .leading) {
                    if screen.device == .duo {
                        Capsule()
                            .fill(DeviceColor.edge.opacity(0.6))
                            .frame(width: 0.8 * u, height: size.height * 0.86)
                            .padding(.leading, 2.6 * u)
                    }
                }
                .overlay { padCamera }
                .shadow(color: .black.opacity(0.18), radius: 14 * u, y: 6 * u)
        }
    }

    /// The Dynamic Island, or the Duo's camera at the top of its strip.
    @ViewBuilder private var camera: some View {
        let k = screen.k
        switch screen.device {
        case .phone:
            Capsule()
                .fill(DeviceColor.body)
                .frame(width: 126 * k, height: 37 * k)
                .position(x: screen.size.width / 2, y: (11 + 18.5) * k)
        case .duo:
            Circle()
                .fill(DeviceColor.body)
                .frame(width: 37 * k, height: 37 * k)
                .position(x: screen.size.width - 48 * k, y: 47 * k)
        default:
            EmptyView()
        }
    }

    /// The iPad's camera, in the bezel on the long edge: the top on its side, the right
    /// edge upright (so a quarter turn to the left brings it to the top).
    @ViewBuilder private var padCamera: some View {
        if screen.device == .pad {
            let dot = Circle().fill(Color(white: 0.28)).frame(width: 2.4 * screen.unit, height: 2.4 * screen.unit)
            if screen.landscape {
                dot.frame(maxHeight: .infinity, alignment: .top).padding(.top, screen.bezel / 2 - 1.2 * screen.unit)
            } else {
                dot.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, screen.bezel / 2 - 1.2 * screen.unit)
            }
        }
    }
}

/// The radar's bar, drawn small: the view button (Map, Radar, or on iPad Split), Sky View, the
/// live count, Logbook and Settings, sharing a glass capsule as wide as the real one (the
/// system tab bar's margins).
private struct MiniBar: View {
    /// The view the first button goes to.
    enum First {
        case map, split, radar, none

        /// The radar's: Split on iPad, where the button steps Radar → Split → Map.
        static func fromRadar(on device: TourDevice) -> First { device == .pad ? .split : .map }
    }

    let screen: TourScreen
    var first = First.map
    /// A finger on the first button.
    var tapped = false

    var body: some View {
        let c = screen.chromeK
        let width = min(screen.radarPane.width - 12 * c,
                        min(TourScreen.barMaxWidth, screen.real.width - 2 * TourScreen.barSideMargin) * c)
        HStack(spacing: 0) {
            if first != .none {
                item(symbol(for: first), tapped: tapped)
            }
            item("camera.viewfinder")
            HStack(spacing: 3 * c) {
                Circle().fill(Palette.live).frame(width: 6 * c, height: 6 * c)
                Text("5").font(.mono(17 * c, .heavy)).foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            item("book.closed.fill")
            item("gearshape.fill")
        }
        .padding(.horizontal, 6 * c)
        .frame(width: max(0, width), height: TourScreen.barHeight * c)
        .miniGlass(Capsule())
    }

    private func symbol(for first: First) -> String {
        switch first {
        case .radar: "scope"
        case .split: screen.landscape ? "rectangle.split.2x1.fill" : "rectangle.split.1x2.fill"
        case .map, .none: "map.fill"
        }
    }

    private func item(_ symbol: String, tapped: Bool = false) -> some View {
        let c = screen.chromeK
        return Image(systemName: symbol)
            .font(.system(size: 21 * c, weight: .medium))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 54 * c)
            .background {
                // The tab bar's lens under the finger.
                Capsule()
                    .fill(Palette.value.opacity(0.12))
                    .scaleEffect(tapped ? 1 : 0.6)
                    .opacity(tapped ? 1 : 0)
            }
    }
}

/// The iPhone Duo's strip, drawn small: the clock, the round Map and Sky View buttons, and
/// the count, Logbook and Settings grouped at the bottom, as the system lays out its own.
private struct MiniRail: View {
    let screen: TourScreen
    /// The strip's top, the clock's middle and the first round button's top, in real points
    /// from the top of the strip's screen (the cover screen puts its camera above the clock).
    var clockY: CGFloat = 96
    var firstButtonTop: CGFloat = 169
    var height: CGFloat? = nil
    var showsMap = true
    var showsRadar = false
    var tapped = false

    var body: some View {
        let k = screen.k
        let button = 48 * k
        let total = height ?? screen.size.height
        ZStack(alignment: .top) {
            Text("9:41")
                .font(.system(size: 15 * k, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .position(x: button / 2, y: clockY * k)
            VStack(spacing: 10 * k) {
                if showsMap {
                    round(showsRadar ? "scope" : "map.fill", tapped: tapped)
                }
                round("camera.viewfinder")
            }
            .padding(.top, firstButtonTop * k)
            VStack(spacing: 2 * k) {
                VStack(spacing: 1 * k) {
                    Circle().fill(Palette.live).frame(width: 5 * k, height: 5 * k)
                    Text("5").font(.mono(15 * k, .heavy)).foregroundStyle(Palette.ink)
                }
                .frame(width: button, height: button)
                symbol("book.closed.fill").frame(width: button, height: button)
                symbol("gearshape.fill").frame(width: button, height: button)
            }
            .padding(.vertical, 2 * k)
            .miniGlass(Capsule())
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 27 * k)
        }
        .frame(width: button, height: total)
    }

    private func round(_ name: String, tapped: Bool = false) -> some View {
        let k = screen.k
        return symbol(name)
            .frame(width: 48 * k, height: 48 * k)
            .background {
                Circle().fill(Palette.ink.opacity(0.25)).scaleEffect(tapped ? 1 : 0.5).opacity(tapped ? 1 : 0)
            }
            .miniGlass(Circle())
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 19 * screen.k, weight: .semibold))
            .foregroundStyle(Palette.ink)
    }
}

/// A screen and its chrome: the bar along the bottom (iPhone, iPad) or the strip (iPhone Duo).
private struct MiniScreen<Content: View>: View {
    let screen: TourScreen
    /// The bar's first button; nil, the radar's.
    var first: MiniBar.First? = nil
    var tapped = false
    /// Over the bar too: a sheet.
    var cover: AnyView? = nil
    @ViewBuilder let content: Content

    var body: some View {
        DeviceShell(screen: screen) {
            ZStack(alignment: .topLeading) {
                content
                chrome
                if let cover { cover }
            }
            .frame(width: screen.size.width, height: screen.size.height, alignment: .topLeading)
        }
    }

    @ViewBuilder private var chrome: some View {
        switch screen.device {
        case .phone, .pad:
            MiniBar(screen: screen, first: first ?? .fromRadar(on: screen.device), tapped: tapped)
                .position(screen.barMid)
        case .duo:
            MiniRail(screen: screen, showsMap: first != MiniBar.First.none, showsRadar: first == .radar, tapped: tapped)
                .position(x: screen.size.width - 48 * screen.k, y: screen.size.height / 2)
        case .tv:
            EmptyView()
        }
    }
}

// MARK: The radar and the map

/// The radar in one pane: paper and contours, the icons on the edge at their bearings with
/// their miles, and the focused aircraft in the middle.
private struct RadarFace: View {
    let screen: TourScreen
    /// The pane, and the part of it the icons ride around, in the pane's own coordinates.
    let size: CGSize
    let face: CGRect
    var heading: Double = 0
    var focused: Int? = 0
    var pinned: Int? = nil
    var showHero = true
    var showNorth = false
    var sweep = false

    var body: some View {
        let top = screen.islandClearance
        let icon = screen.iconSize
        ZStack {
            // A whole screen's worth of contours, shrunk to the miniature.
            RadarBackdrop(showTopography: true, showSweep: sweep, isActive: true, topographyZoom: 1 / screen.k)
                .frame(width: size.width, height: size.height)
            if showNorth {
                Text("N")
                    .font(.mono(icon * 0.55, .heavy))
                    .foregroundStyle(Palette.signal)
                    .position(edgePoint(-heading, in: face, inset: icon * 0.4, top: top))
            }
            ForEach(Array(TourTraffic.all.enumerated()), id: \.offset) { index, traffic in
                blip(traffic, isFocused: index == focused, isPinned: index == pinned, top: top)
            }
            if showHero, let focused {
                MiniHero(traffic: TourTraffic.all[focused], size: screen.heroSize, pinned: focused == pinned)
                    .id(focused)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .position(x: face.midX, y: face.midY)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func blip(_ traffic: TourTraffic, isFocused: Bool, isPinned: Bool, top: CGFloat) -> some View {
        let angle = traffic.bearing - heading
        let icon = screen.iconSize
        let tint = isFocused ? Palette.signal : Palette.blip
        return ZStack {
            // A pinned aircraft's miles are yellow, like the pin on the hero.
            Text(RadarFormat.distance(Double(traffic.miles)))
                .font(.mono(icon * (isFocused ? 0.6 : 0.55), .bold))
                .foregroundStyle(isPinned ? Palette.pinned : tint)
                .paperHalo()
                .position(edgePoint(angle, in: face, inset: icon * 1.75, top: top))
            ZStack {
                if isFocused {
                    Circle().fill(Palette.signal.opacity(0.16)).frame(width: icon * 1.3, height: icon * 1.3)
                }
                AircraftGlyph(silhouette: traffic.silhouette, size: icon)
                    .foregroundStyle(tint)
                    .rotationEffect(.degrees(traffic.track - heading))
            }
            .position(edgePoint(angle, in: face, inset: icon * 0.85, top: top))
        }
    }
}

private struct MiniHero: View {
    let traffic: TourTraffic
    /// The flight number's point size.
    let size: CGFloat
    var pinned = false

    var body: some View {
        VStack(spacing: size * 0.12) {
            HStack(spacing: size * 0.15) {
                if pinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(Palette.pinned)
                        .transition(.scale.combined(with: .opacity))
                }
                Text(traffic.airline)
                    .tracking(size * 0.04)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.caption)
            }
            .font(.mono(size * 0.3, .bold))
            Text(traffic.flight)
                .font(.mono(size, .heavy))
                .foregroundStyle(Palette.ink)
            Text(traffic.route)
                .font(.mono(size * 0.42, .semibold))
                .foregroundStyle(Palette.route)
            Text(RadarFormat.distanceText(Double(traffic.miles)).uppercased())
                .font(.mono(size * 0.42, .bold))
                .foregroundStyle(Palette.signal)
                .padding(.top, size * 0.2)
        }
        .paperHalo()
        .fixedSize()
    }
}

/// A device showing the radar, with its bar or strip.
private struct MiniRadarScreen: View {
    let screen: TourScreen
    var heading: Double = 0
    var focused: Int? = 0
    var pinned: Int? = nil
    var showHero = true
    var showNorth = false
    var sweep = false
    var first: MiniBar.First? = nil
    var tapped = false
    /// Drawn over the radar, in screen coordinates.
    var overlay: AnyView? = nil
    /// Drawn over the bar as well.
    var cover: AnyView? = nil

    var body: some View {
        MiniScreen(screen: screen, first: first, tapped: tapped, cover: cover) {
            RadarFace(screen: screen, size: screen.radarPane.size, face: screen.face, heading: heading,
                      focused: focused, pinned: pinned, showHero: showHero, showNorth: showNorth, sweep: sweep)
                .offset(x: screen.radarPane.minX, y: screen.radarPane.minY)
            if let pane = screen.mapPane {
                MiniMap(size: pane.size, icon: screen.iconSize * 0.9, focused: focused, pinned: TourTraffic.pinnedOnMap)
                    .offset(x: pane.minX, y: pane.minY)
            }
            if let overlay { overlay }
        }
    }
}

/// The live map, drawn small: streets washed in paper, the radius ring, home and ATL, and the
/// traffic with its trails (yellow behind the pinned aircraft) and the path ahead of the
/// focused one, north up.
private struct MiniMap: View {
    let size: CGSize
    let icon: CGFloat
    var focused: Int? = 0
    var pinned: Int? = TourTraffic.pinnedOnMap
    /// The radius ring, as a share of the shorter side.
    var ring: CGFloat = 0.4

    var body: some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * ring
        ZStack(alignment: .topLeading) {
            MapStreets()
            // The wash the real map gets, so the aircraft carry it.
            Palette.paper.opacity(0.45)
            Circle()
                .fill(Palette.ink.opacity(0.06))
                .overlay(Circle().stroke(Palette.ink.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])))
                .frame(width: radius * 2, height: radius * 2)
                .position(center)
            Circle()
                .stroke(Palette.ink.opacity(0.16), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
                .frame(width: radius, height: radius)
                .position(center)
            Canvas { context, _ in
                for (index, traffic) in TourTraffic.all.enumerated() {
                    drawTrail(traffic, at: position(traffic, center: center, radius: radius),
                              pinned: index == pinned, focused: index == focused, in: &context)
                }
            }
            Text("ATL")
                .font(.mono(icon * 0.38, .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, icon * 0.22)
                .padding(.vertical, icon * 0.08)
                .background(Palette.route, in: Capsule())
                .position(x: center.x - radius * 0.22, y: center.y + radius * 0.3)
            Circle()
                .fill(Palette.ink)
                .overlay(Circle().stroke(.white, lineWidth: icon * 0.08))
                .frame(width: icon * 0.42, height: icon * 0.42)
                .position(center)
            ForEach(Array(TourTraffic.all.enumerated()), id: \.offset) { index, traffic in
                AircraftGlyph(silhouette: traffic.silhouette, size: icon, spinsRotor: false)
                    .foregroundStyle(index == focused ? Palette.signal : Palette.blip)
                    .rotationEffect(.degrees(traffic.track))
                    .background {
                        if index == focused {
                            Circle().fill(Palette.signal.opacity(0.16)).frame(width: icon * 1.3, height: icon * 1.3)
                        }
                    }
                    .position(position(traffic, center: center, radius: radius))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// The radius is 20 miles.
    private func position(_ traffic: TourTraffic, center: CGPoint, radius: CGFloat) -> CGPoint {
        let radians = traffic.bearing * .pi / 180
        let r = radius * CGFloat(traffic.miles) / 20
        return CGPoint(x: center.x + sin(radians) * r, y: center.y - cos(radians) * r)
    }

    private func drawTrail(_ traffic: TourTraffic, at point: CGPoint, pinned: Bool, focused: Bool,
                           in context: inout GraphicsContext) {
        let radians = traffic.track * .pi / 180
        let back = CGVector(dx: -sin(radians), dy: cos(radians))
        let length = icon * 1.9
        let width = max(1, icon * 0.1) * (pinned ? 1.5 : 1)
        let color = pinned ? Palette.pinned : Palette.route
        // Three bands, fading with age, as on the real map.
        for (band, opacity) in [0.9, 0.55, 0.25].enumerated() {
            let from = CGFloat(band) / 3, to = CGFloat(band + 1) / 3
            var path = Path()
            path.move(to: CGPoint(x: point.x + back.dx * length * from, y: point.y + back.dy * length * from))
            path.addLine(to: CGPoint(x: point.x + back.dx * length * to, y: point.y + back.dy * length * to))
            context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        if focused {
            var ahead = Path()
            ahead.move(to: point)
            ahead.addLine(to: CGPoint(x: point.x - back.dx * icon * 3, y: point.y - back.dy * icon * 3))
            context.stroke(ahead, with: .color(Palette.signal.opacity(0.8)),
                           style: StrokeStyle(lineWidth: max(1, icon * 0.1), lineCap: .round, dash: [icon * 0.3, icon * 0.25]))
        }
    }
}

/// A city's streets for the drawn map: a ring road, highways through the middle, a grid of
/// side streets and a lake.
private struct MapStreets: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Canvas { context, size in
            let s = max(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .color(dark ? Color(red: 0.11, green: 0.13, blue: 0.16) : Color(red: 0.90, green: 0.93, blue: 0.87)))
            // A park and a lake.
            context.fill(Path(ellipseIn: CGRect(x: c.x - 0.42 * s, y: c.y + 0.12 * s, width: 0.2 * s, height: 0.14 * s)),
                         with: .color(dark ? Color(red: 0.12, green: 0.17, blue: 0.15) : Color(red: 0.84, green: 0.90, blue: 0.80)))
            context.fill(Path(ellipseIn: CGRect(x: c.x + 0.2 * s, y: c.y - 0.42 * s, width: 0.2 * s, height: 0.12 * s)),
                         with: .color(dark ? Color(red: 0.12, green: 0.2, blue: 0.29) : Color(red: 0.74, green: 0.84, blue: 0.92)))
            let minor = dark ? Color(white: 0.2) : Color(white: 0.97)
            let major = dark ? Color(white: 0.27) : Color.white
            // Side streets, a little off square.
            var grid = Path()
            let step = 0.085 * s
            for i in -8...8 {
                let d = CGFloat(i) * step
                grid.move(to: CGPoint(x: c.x + d - 0.08 * s, y: c.y - s))
                grid.addLine(to: CGPoint(x: c.x + d + 0.08 * s, y: c.y + s))
                grid.move(to: CGPoint(x: c.x - s, y: c.y + d + 0.06 * s))
                grid.addLine(to: CGPoint(x: c.x + s, y: c.y + d - 0.06 * s))
            }
            context.stroke(grid, with: .color(minor), lineWidth: 0.6)
            // Highways through the middle and the ring road around it.
            var roads = Path()
            for degrees in [18.0, 78, 138] {
                let radians = degrees * .pi / 180
                let dx = cos(radians) * s, dy = sin(radians) * s
                roads.move(to: CGPoint(x: c.x - dx, y: c.y - dy))
                roads.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
            }
            roads.addEllipse(in: CGRect(x: c.x - 0.27 * s, y: c.y - 0.25 * s, width: 0.54 * s, height: 0.5 * s))
            context.stroke(roads, with: .color(dark ? Color(white: 0.08) : Color(white: 0.82)), lineWidth: 2.4)
            context.stroke(roads, with: .color(major), lineWidth: 1.6)
        }
    }
}

// MARK: Pages

/// The radar, turning with you: the icons slide round the edge to stay pointed at their
/// aircraft. The TV doesn't turn; its top is the way you face.
private struct TourRadar: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if screen.device == .tv {
            MiniRadarScreen(screen: screen, sweep: true)
        } else {
            TimelineView(.animation(paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let heading = reduceMotion ? 0 : GeoMath.normalize(50 * sin(t * 0.5))
                VStack(spacing: 10 * screen.unit) {
                    MiniRadarScreen(screen: screen, heading: heading, showNorth: true, sweep: true)
                    Text("FACING \(String(format: "%03d", Int(heading.rounded()) % 360))° \(GeoMath.cardinal(heading))")
                        .font(.mono(10 * screen.unit, .bold))
                        .tracking(1.5 * screen.unit)
                        .foregroundStyle(Palette.caption)
                        .monospacedDigit()
                }
            }
        }
    }
}

/// Swipe left twice to step out through the traffic, right to snap back to the nearest, then
/// hold the center to pin it.
private struct TourCenter: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let period: TimeInterval = 2.2

    private enum Step: Int, CaseIterable {
        case nearest, next, farther, hold, pinned

        var focused: Int { [0, 1, 2, 0, 0][rawValue] }

        var caption: String {
            switch self {
            case .nearest, .next: "SWIPE ←  NEXT OUT"
            case .farther: "SWIPE →  NEAREST"
            case .hold: "HOLD TO PIN"
            case .pinned: "PINNED"
            }
        }
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let step = reduceMotion ? Step.pinned : Step(rawValue: Int(t / Self.period) % Step.allCases.count) ?? .nearest
            let phase = reduceMotion ? 1 : (t / Self.period).truncatingRemainder(dividingBy: 1)
            MiniRadarScreen(screen: screen, focused: step.focused, pinned: step == .pinned ? 0 : nil,
                            overlay: AnyView(gesture(step, phase: phase)))
                .animation(.snappy, value: step)
        }
    }

    private func gesture(_ step: Step, phase: Double) -> some View {
        let face = screen.face
        let finger = 26 * screen.iconSize / 16
        let swipe = max(0, min(1, (phase - 0.55) / 0.3))
        let leftward = step == .nearest || step == .next
        let hold = max(0, min(1, (phase - 0.15) / 0.65))
        return ZStack {
            if !reduceMotion && (step == .nearest || step == .next || step == .farther) && swipe > 0 && swipe < 1 {
                Circle()
                    .fill(Palette.ink.opacity(0.28))
                    .overlay(Circle().stroke(Palette.ink.opacity(0.6), lineWidth: 1.5 * screen.unit))
                    .frame(width: finger, height: finger)
                    .position(x: face.midX + (leftward ? 1 - 2 * swipe : -1 + 2 * swipe) * face.width * 0.22,
                              y: face.midY + face.height * 0.2)
                    .opacity(sin(swipe * .pi))
            }
            if step == .hold && !reduceMotion {
                // A finger on the hero, with a ring filling as it holds.
                ZStack {
                    Circle().fill(Palette.ink.opacity(0.22))
                    Circle()
                        .trim(from: 0, to: hold)
                        .stroke(Palette.pinned, style: StrokeStyle(lineWidth: 2 * screen.unit, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: finger * 1.2, height: finger * 1.2)
                .position(x: face.midX, y: face.midY + screen.heroSize * 0.3)
                .opacity(phase < 0.1 ? 0 : 1)
            }
            HStack(spacing: 4 * screen.unit) {
                if step == .pinned {
                    Image(systemName: "pin.fill").foregroundStyle(Palette.pinned)
                }
                Text(step.caption)
            }
            .font(.mono(7.5 * screen.unit, .bold))
            .foregroundStyle(Palette.caption)
            .padding(.horizontal, 7 * screen.unit)
            .padding(.vertical, 3.5 * screen.unit)
            .background(Palette.paperShade.opacity(0.7), in: Capsule())
            .fixedSize()
            .position(x: face.midX, y: face.maxY - 14 * screen.unit)
        }
        .frame(width: screen.size.width, height: screen.size.height)
    }
}

/// A tap on the center, and the details come up: a sheet from the bottom on a phone, a card
/// in the middle on iPad.
private struct TourDetails: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: CaseIterable { case idle, tap, open }

    var body: some View {
        if reduceMotion {
            scene(tap: false, open: true)
        } else {
            scene(tap: false, open: false)
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
        let size = screen.size
        let finger = 30 * screen.iconSize / 16
        let touch = Circle()
            .stroke(Palette.ink.opacity(0.6), lineWidth: 2 * screen.unit)
            .background(Circle().fill(Palette.ink.opacity(0.18)))
            .frame(width: finger, height: finger)
            .scaleEffect(tap ? 1.25 : 0.6)
            .opacity(tap ? 1 : 0)
            .position(x: screen.face.midX, y: screen.face.midY)
        return MiniRadarScreen(screen: screen, overlay: AnyView(touch), cover: AnyView(
            ZStack {
                if screen.device == .pad {
                    Color.black.opacity(open ? 0.25 : 0)
                    DetailCard(width: size.width * 0.64)
                        .frame(width: size.width * 0.64, height: size.height * 0.64, alignment: .top)
                        .background(Palette.paper, in: RoundedRectangle(cornerRadius: 9 * screen.unit, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 10 * screen.unit, y: 3 * screen.unit)
                        .scaleEffect(open ? 1 : 0.9)
                        .opacity(open ? 1 : 0)
                        .position(x: size.width / 2, y: size.height / 2)
                } else {
                    let card = CGSize(width: size.width, height: size.height * 0.66)
                    DetailCard(width: card.width, grabber: true)
                        .frame(width: card.width, height: card.height, alignment: .top)
                        .background(Palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 14 * screen.unit, topTrailingRadius: 14 * screen.unit))
                        .shadow(color: .black.opacity(0.2), radius: 10 * screen.unit, y: -2 * screen.unit)
                        .position(x: size.width / 2, y: size.height - card.height / 2 + (open ? 0 : card.height + 20 * screen.unit))
                }
            }
            .frame(width: size.width, height: size.height)
        ))
    }

    private struct DetailCard: View {
        let width: CGFloat
        var grabber = false

        var body: some View {
            // Laid out for a 130-point-wide card.
            let s = width / 130
            VStack(alignment: .leading, spacing: 6 * s) {
                if grabber {
                    Capsule().fill(Palette.faint).frame(width: 24 * s, height: 3 * s).frame(maxWidth: .infinity)
                }
                ZStack {
                    LinearGradient(colors: [Color(red: 0.42, green: 0.62, blue: 0.9), Color(red: 0.78, green: 0.87, blue: 0.97)],
                                   startPoint: .top, endPoint: .bottom)
                    AircraftGlyph(silhouette: .airliner, size: 40 * s).foregroundStyle(.white).rotationEffect(.degrees(90))
                }
                .frame(height: 46 * s)
                .clipShape(RoundedRectangle(cornerRadius: 7 * s, style: .continuous))
                Text("DL1199").font(.mono(13 * s, .heavy)).foregroundStyle(Palette.ink)
                Text("Delta · Airbus A321neo").font(.mono(6.5 * s, .medium)).foregroundStyle(Palette.caption)
                HStack(spacing: 5 * s) {
                    Text("ATL").font(.mono(7.5 * s, .bold)).foregroundStyle(Palette.route)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.faint.opacity(0.5)).frame(height: 2 * s)
                            Capsule().fill(Palette.ink).frame(width: geo.size.width * 0.38, height: 2 * s)
                            AircraftGlyph(silhouette: .airliner, size: 9 * s).foregroundStyle(Palette.ink)
                                .rotationEffect(.degrees(90)).offset(x: geo.size.width * 0.38 - 4.5 * s)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    .frame(height: 9 * s)
                    Text("ORD").font(.mono(7.5 * s, .bold)).foregroundStyle(Palette.route)
                }
                Text("SEEN 3× BEFORE")
                    .font(.mono(6.5 * s, .bold))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 6 * s)
                    .padding(.vertical, 3 * s)
                    .background(Palette.ink.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 9 * s)
            .padding(.top, 7 * s)
        }
    }
}

/// The map, the way each device shows it: the iPhone's Map button, the iPad's Split and Map,
/// the iPhone Duo opening like a book, the TV's ▲.
private struct TourMap: View {
    let screen: TourScreen

    var body: some View {
        switch screen.device {
        case .phone: PhoneMap(screen: screen)
        case .pad: PadMap(screen: screen)
        case .duo: DuoMap(screen: screen)
        case .tv: TVMap(screen: screen)
        }
    }
}

/// Tap Map: the map takes the radar's place under a one-row card, and Radar brings it back.
private struct PhoneMap: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: CaseIterable { case radar, tap, map, tapBack }

    var body: some View {
        if reduceMotion {
            scene(.map)
        } else {
            scene(.radar)
                .hidden()
                .overlay {
                    Color.clear.phaseAnimator(Phase.allCases) { _, phase in
                        scene(phase)
                    } animation: { phase in
                        switch phase {
                        case .radar: .easeInOut(duration: 0.4).delay(0.3)
                        case .tap: .easeOut(duration: 0.3).delay(1.6)
                        case .map: .easeInOut(duration: 0.4).delay(0.2)
                        case .tapBack: .easeOut(duration: 0.3).delay(3.2)
                        }
                    }
                }
        }
    }

    private func scene(_ phase: Phase) -> some View {
        let showsMap = phase == .map || phase == .tapBack
        let face = screen.face
        return MiniScreen(screen: screen, first: showsMap ? .radar : .map, tapped: phase == .tap || phase == .tapBack) {
            RadarFace(screen: screen, size: screen.size, face: face, pinned: TourTraffic.pinnedOnMap)
                .opacity(showsMap ? 0 : 1)
            ZStack(alignment: .topLeading) {
                MiniMap(size: screen.size, icon: screen.iconSize * 0.9, ring: 0.42)
                MapCard(width: face.width - 16 * screen.k, size: screen.heroSize)
                    .position(x: face.midX, y: face.maxY - 30 * screen.k)
            }
            .opacity(showsMap ? 1 : 0)
        }
    }
}

/// The compact one-row hero over the map.
private struct MapCard: View {
    let width: CGFloat
    /// The flight number's point size on the radar.
    let size: CGFloat

    var body: some View {
        let traffic = TourTraffic.all[0]
        HStack(spacing: size * 0.3) {
            Text(traffic.flight).font(.mono(size * 0.55, .heavy)).foregroundStyle(Palette.ink)
            Text(traffic.route).font(.mono(size * 0.32, .semibold)).foregroundStyle(Palette.route)
            Spacer(minLength: 0)
            Text(RadarFormat.distanceText(Double(traffic.miles)).uppercased()).font(.mono(size * 0.32, .bold)).foregroundStyle(Palette.signal)
        }
        .lineLimit(1)
        .padding(.horizontal, size * 0.5)
        .frame(width: width, height: size * 1.6)
        .miniGlass(RoundedRectangle(cornerRadius: size * 0.5, style: .continuous))
    }
}

/// Tap Split: the map joins the radar on the bottom half. Map: the map alone under a one-row
/// card. Radar: back again.
private struct PadMap: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One loop, in seconds: radar, split, map, each tapped away from on the bar.
    private static let loop: TimeInterval = 9
    /// When each tap lands: Split, Map, Radar. Each view fades into the next just after.
    private static let taps: [TimeInterval] = [1.6, 4.6, 7.4]

    var body: some View {
        // Worked out from the clock rather than with `phaseAnimator`, which stalls on a long
        // delay while the sheet behind keeps redrawing.
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = reduceMotion ? 3.5 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop)
            scene(at: t)
        }
    }

    private func scene(at t: TimeInterval) -> some View {
        func ease(_ from: TimeInterval) -> Double {
            let x = max(0, min(1, (t - from - 0.3) / 0.5))
            return x * x * (3 - 2 * x)
        }
        let (toSplit, toMap, toRadar) = (ease(Self.taps[0]), ease(Self.taps[1]), ease(Self.taps[2]))
        // Named for where it goes, swapping halfway through each fade.
        let next: MiniBar.First = toRadar > 0.5 || toSplit < 0.5 ? .split : toMap < 0.5 ? .map : .radar
        let tapped = Self.taps.contains { t >= $0 && t < $0 + 0.3 }
        let split = screen.splitting
        let face = screen.face
        return MiniScreen(screen: screen, first: next, tapped: tapped) {
            RadarFace(screen: screen, size: screen.size, face: face, pinned: TourTraffic.pinnedOnMap)
                .opacity(1 - toSplit + toRadar)
            if let pane = split.mapPane {
                ZStack(alignment: .topLeading) {
                    RadarFace(screen: split, size: split.radarPane.size, face: split.face, pinned: TourTraffic.pinnedOnMap)
                        .offset(y: split.radarPane.minY)
                    MiniMap(size: pane.size, icon: screen.iconSize * 0.9, ring: 0.4)
                        .offset(x: pane.minX, y: pane.minY)
                }
                .opacity(toSplit - toMap)
            }
            ZStack(alignment: .topLeading) {
                MiniMap(size: screen.size, icon: screen.iconSize * 0.9, ring: 0.42)
                MapCard(width: face.width - 48 * screen.k, size: screen.heroSize)
                    .position(x: face.midX, y: face.maxY - screen.heroSize)
            }
            .opacity(toMap - toRadar)
        }
        .transaction { $0.animation = nil }
    }
}

/// The iPhone Duo, folded, opens halfway like a book: the radar on the left page, the map on
/// the right with the system's strip down its edge.
private struct DuoMap: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The inner screen, 951 × 669 held as a book, at the scale that fits it in the drawing.
    private var inner: TourScreen { TourScreen(device: .duo, unit: screen.unit * 0.75) }
    private var page: CGSize { CGSize(width: 455.5 * inner.k, height: 669 * inner.k) }
    /// The fold strip between the pages.
    private var gutter: CGFloat { 40 * inner.k }

    private enum Phase: CaseIterable { case closed, unfolding, open, folding }

    var body: some View {
        Group {
            if reduceMotion {
                scene(.open)
            } else {
                Color.clear.phaseAnimator(Phase.allCases) { _, phase in
                    scene(phase)
                } animation: { phase in
                    switch phase {
                    case .closed: .easeOut(duration: 0.25)
                    case .unfolding: .easeIn(duration: 0.25).delay(1.8)
                    case .open: .spring(response: 0.8, dampingFraction: 0.85)
                    case .folding: .easeIn(duration: 0.45).delay(3.2)
                    }
                }
            }
        }
        .frame(width: 300 * screen.unit, height: 300 * screen.unit)
    }

    private func scene(_ phase: Phase) -> some View {
        let isClosed = phase == .closed
        return ZStack {
            MiniRadarScreen(screen: inner, pinned: TourTraffic.pinnedOnMap)
                .scaleEffect(isClosed ? 1 : 0.9)
                .opacity(isClosed ? 1 : 0)
            book(angle: phase == .open ? 14 : 62)
                .opacity(isClosed ? 0 : 1)
        }
    }

    private func book(angle: Double) -> some View {
        let u = inner.unit
        let radius = 40 * inner.k
        return HStack(spacing: 0) {
            RadarFace(screen: inner, size: page, face: CGRect(origin: .zero, size: page), pinned: TourTraffic.pinnedOnMap)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius))
                .padding([.vertical, .leading], inner.bezel)
                .background(DeviceColor.body, in: UnevenRoundedRectangle(topLeadingRadius: radius + inner.bezel, bottomLeadingRadius: radius + inner.bezel))
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .trailing, perspective: 0.45)
            // The fold.
            LinearGradient(colors: [DeviceColor.body, Color(white: 0.28), DeviceColor.body], startPoint: .leading, endPoint: .trailing)
                .frame(width: gutter, height: page.height + 2 * inner.bezel)
            ZStack(alignment: .topLeading) {
                MiniMap(size: page, icon: inner.iconSize * 0.9, ring: 0.36)
                // The strip: the clock at its top, Sky View, then the group at the bottom.
                MiniRail(screen: inner, clockY: 60, firstButtonTop: 120, height: page.height, showsMap: false)
                    .position(x: page.width - 48 * inner.k, y: page.height / 2)
            }
            .frame(width: page.width, height: page.height)
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: radius, topTrailingRadius: radius))
            .padding([.vertical, .trailing], inner.bezel)
            .background(DeviceColor.body, in: UnevenRoundedRectangle(bottomTrailingRadius: radius + inner.bezel, topTrailingRadius: radius + inner.bezel))
            .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
        }
        .shadow(color: .black.opacity(0.18), radius: 14 * u, y: 6 * u)
    }
}

/// ▲ steps the TV through its views: radar, split, map.
private struct TVMap: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum View3: Int, CaseIterable {
        case radar, split, map

        var next: String {
            switch self {
            case .radar: "SPLIT"
            case .split: "MAP"
            case .map: "RADAR"
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2.6)) { context in
            let view = reduceMotion ? View3.split : View3(rawValue: Int(context.date.timeIntervalSinceReferenceDate / 2.6) % 3) ?? .radar
            VStack(spacing: 14 * screen.unit) {
                MiniScreen(screen: screen) { content(view) }
                HStack(spacing: 8 * screen.unit) {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 9 * screen.unit, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8 * screen.unit)
                        .frame(height: 22 * screen.unit)
                        .background(Palette.signal, in: Capsule())
                    Text(view.next)
                        .font(.mono(12 * screen.unit, .semibold))
                        .foregroundStyle(Palette.value)
                }
            }
            .animation(.smooth(duration: 0.5), value: view)
        }
    }

    /// Each view's panes keep their size and cross-fade: a pane changing size would draw its
    /// contours afresh on every frame.
    private func content(_ view: View3) -> some View {
        let size = screen.size
        let split = CGSize(width: size.width * 0.6, height: size.height)
        return ZStack(alignment: .topLeading) {
            MiniMap(size: size, icon: screen.iconSize * 0.8, ring: 0.4)
                .offset(x: view == .split ? split.width / 2 : 0)
                .opacity(view == .radar ? 0 : 1)
            RadarFace(screen: screen, size: size, face: CGRect(origin: .zero, size: size), pinned: TourTraffic.pinnedOnMap)
                .opacity(view == .radar ? 1 : 0)
            RadarFace(screen: screen, size: split, face: CGRect(origin: .zero, size: split), pinned: TourTraffic.pinnedOnMap)
                .opacity(view == .split ? 1 : 0)
            MapCard(width: size.width * 0.44, size: screen.heroSize * 0.8)
                .position(x: size.width * 0.75, y: size.height - 16 * screen.unit)
                .opacity(view == .map ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// The device lifts from flat (radar) to upright (camera, every aircraft labeled).
private struct TourSky: View {
    let screen: TourScreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            device(raised: true)
        } else {
            device(raised: true)
                .hidden()
                .overlay {
                    Color.clear.phaseAnimator([false, true]) { _, raised in
                        device(raised: raised)
                    } animation: { raised in
                        raised ? .spring(response: 0.9, dampingFraction: 0.8).delay(0.8) : .easeInOut(duration: 0.9).delay(2.2)
                    }
                }
        }
    }

    private func device(raised: Bool) -> some View {
        // A touch smaller than the radar pages, so the tilt fits.
        let shown = TourScreen(device: screen.device, unit: screen.unit * 0.9)
        return DeviceShell(screen: shown) {
            ZStack {
                Palette.paper
                RangeRings().stroke(Palette.ink.opacity(0.12), style: StrokeStyle(lineWidth: shown.unit, dash: [2, 5]))
                SkyCamera(size: shown.size, scale: shown.iconSize / 16)
                    .opacity(raised ? 1 : 0)
            }
        }
        .rotation3DEffect(.degrees(raised ? 0 : 62), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
        .overlay(alignment: .top) {
            Image(systemName: "arrow.up")
                .font(.system(size: 18 * screen.unit, weight: .bold))
                .foregroundStyle(Palette.signal)
                .offset(y: -26 * screen.unit)
                .opacity(raised ? 0 : 1)
        }
    }

    /// The camera, the sky, and the aircraft labeled where they are.
    private struct SkyCamera: View {
        let size: CGSize
        let scale: CGFloat

        var body: some View {
            let s = scale
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.45, blue: 0.82), Color(red: 0.62, green: 0.79, blue: 0.96)],
                               startPoint: .top, endPoint: .bottom)
                // Horizon with compass ticks.
                VStack(spacing: 3 * s) {
                    Rectangle().fill(.white.opacity(0.7)).frame(height: s)
                    HStack {
                        ForEach(["NW", "N", "NE"], id: \.self) { mark in
                            Text(mark).font(.mono(7 * s, .bold)).foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity)
                        }
                    }
                }
                .offset(y: size.height * 0.34)

                AircraftGlyph(silhouette: .airliner, size: 18 * s)
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(70))
                    .offset(x: -6 * s, y: -size.height * 0.08)
                Circle()
                    .stroke(.white, lineWidth: 1.5 * s)
                    .frame(width: 40 * s, height: 40 * s)
                    .offset(x: -6 * s, y: -size.height * 0.08)
                VStack(spacing: 1 * s) {
                    Text("DL1199").font(.mono(10 * s, .heavy))
                    Text("4 MI · 9,500 FT").font(.mono(7 * s, .semibold)).opacity(0.85)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2 * s)
                .offset(x: -6 * s, y: -size.height * 0.08 + 36 * s)

                Text("UA482")
                    .font(.mono(8 * s, .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(x: size.width * 0.24, y: -size.height * 0.3)
                // The shutter.
                Circle()
                    .stroke(.white, lineWidth: 1.5 * s)
                    .background(Circle().fill(.white.opacity(0.85)).padding(2.5 * s))
                    .frame(width: 22 * s, height: 22 * s)
                    .offset(y: size.height * 0.5 - 22 * s)
            }
            .frame(width: size.width, height: size.height)
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
                Text("DL1199 · <1 \(RadarFormat.distanceUnit())").foregroundStyle(Palette.value)
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

    private enum Key: Int, CaseIterable { case sides, click, playPause, up, down }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.6)) { context in
            let lit = reduceMotion ? nil : Key(rawValue: Int(context.date.timeIntervalSinceReferenceDate / 1.6) % Key.allCases.count)
            HStack(spacing: 34 * unit) {
                remote(lit: lit)
                VStack(alignment: .leading, spacing: 16 * unit) {
                    row(["arrowtriangle.left.fill", "arrowtriangle.right.fill"], "Other aircraft", lit: lit == .sides)
                    row(["circle.circle"], "Details", lit: lit == .click)
                    row(["playpause.fill"], "Pin", lit: lit == .playPause)
                    row(["arrowtriangle.up.fill"], "Radar, split, map", lit: lit == .up)
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
                arrow("arrowtriangle.up.fill", lit: lit == .up).offset(y: -26 * unit)
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

// MARK: - iPhone and iPad

#if os(iOS)
struct OnboardingView: View {
    let onStart: () -> Void
    let onDemo: () -> Void

    #if DEBUG
    /// `-wtf.debugTourPage 3` opens the tour on that page (screenshots).
    @State private var page = max(UserDefaults.standard.integer(forKey: "wtf.debugTourPage"), 0)
    #else
    @State private var page = 0
    #endif

    @Environment(\.isFoldable) private var isFoldable
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Every device gets the same number of pages, so `page` holds if it changes (the Duo
    /// only knows it folds once its hinge reports).
    private var device: TourDevice {
        #if DEBUG
        // `-wtf.debugTourDevice phone|duo|pad` draws the tour for another device.
        if let name = UserDefaults.standard.string(forKey: "wtf.debugTourDevice"), let device = TourDevice(rawValue: name) {
            return device
        }
        #endif
        if UIDevice.current.userInterfaceIdiom == .pad { return .pad }
        return isFoldable ? .duo : .phone
    }

    private var pages: [TourPage] { TourPage.pages(for: device) }
    private var current: Int { min(page, pages.count - 1) }
    private var isLast: Bool { current == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { withAnimation(.smooth) { page = pages.count - 1 } }
                    .monoScaled(14, .semibold)
                    .foregroundStyle(Palette.caption)
                    .opacity(isLast ? 0 : 1)
                    .disabled(isLast)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    OnboardingPageView(page: item, artScale: horizontalSizeClass == .regular ? 1.25 : 1.12)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            TourDots(count: pages.count, current: current)
                .padding(.bottom, 18)

            VStack(spacing: 12) {
                if isLast {
                    Button(action: onStart) {
                        Text("Start Watching").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RadarButtonStyle(prominent: true))
                    Button("Try Demo Traffic", action: onDemo)
                        .monoScaled(13, .semibold)
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 4)
                } else {
                    Button {
                        withAnimation(.smooth) { page = current + 1 }
                    } label: {
                        Text("Next").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(RadarButtonStyle(prominent: true))
                    // Keeps the button where it is on the last page, which has two.
                    Text(" ").monoScaled(13, .semibold).padding(.vertical, 4).hidden()
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .background(Palette.paper.ignoresSafeArea())
        .environment(\.tourDevice, device)
        .interactiveDismissDisabled()
        .sensoryFeedback(.selection, trigger: page)
    }
}

private struct OnboardingPageView: View {
    let page: TourPage
    /// How far the drawing may grow past its 300 points when there's room (iPad's sheet has
    /// plenty); it shrinks on small screens.
    var artScale: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fit = min(artScale, geo.size.height / 320, geo.size.width / 320)
                TourArt(art: page.art)
                    .frame(width: 300, height: 300)
                    .scaleEffect(fit)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(minHeight: 200, maxHeight: 340 * artScale)

            // At large text sizes the words outgrow the space under the drawing: scroll them.
            ViewThatFits(in: .vertical) {
                pageText
                ScrollView { pageText }
            }
            // Measured after the drawing has its minimum, so the choice sees the real room.
            .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var pageText: some View {
        VStack(spacing: 10) {
            Text(page.eyebrow)
                .radarCaption(scales: true)
            Text(page.title)
                .monoScaled(25, .heavy)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Text(page.body)
                .monoScaled(13)
                .foregroundStyle(Palette.value)
                .lineSpacing(3)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .frame(maxWidth: 520)
    }
}
#endif
