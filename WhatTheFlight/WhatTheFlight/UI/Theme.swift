//
//  Theme.swift
//  WhatTheFlight
//
//  Colour palette and type ramp. Light mode follows the mockup (paper, indigo ink, red
//  arrow); dark mode is a night-radar variant of the same palette. Apple Watch is always
//  dark, so it uses the night-radar values alone.
//

#if os(iOS) || os(tvOS) || os(watchOS)
import SwiftUI
#if !os(watchOS)
import UIKit
#endif

enum Palette {
    /// Background paper.
    static let paper = dynamic(light: 0xE9E7E2, dark: 0x0A0E14)
    static let paperShade = dynamic(light: 0xD3D0C8, dark: 0x020306)
    /// Flight number.
    static let ink = dynamic(light: 0x3A33D6, dark: 0xA8A4FF)
    /// Airport codes.
    static let route = dynamic(light: 0x7C83E8, dark: 0x8C9BFF)
    /// The red arrow, focus halo, north marker.
    static let signal = dynamic(light: 0xE5483B, dark: 0xFF6B5E)
    /// Apple TV: the pulse on the aircraft a spoken alert is about.
    static let announce = dynamic(light: 0x8E3FD9, dark: 0xC48CFF)
    /// Stat captions.
    static let caption = dynamic(light: 0x75726C, dark: 0x8790A0)
    /// Stat values.
    static let value = dynamic(light: 0x3B3A37, dark: 0xE7EAF0)
    static let faint = dynamic(light: 0xA29E95, dark: 0x465061)
    /// Aircraft blips.
    static let blip = dynamic(light: 0x2D56B9, dark: 0x72AAFF)
    /// Pinned aircraft: the pin by the flight number and the mile label on the radar edge.
    static let pinned = dynamic(light: 0xD9A200, dark: 0xFFD60A)
    /// Favourite aircraft, in the pin's yellow: the whole icon on the radar and the map, the
    /// heart by the flight number, their names in search and the logbook.
    static var favorite: Color { pinned }
    /// Favourites' names in lists (search, the logbook, stats): the same yellow at night, a
    /// deeper gold by day so it still reads on paper.
    static let favoriteText = dynamic(light: 0xA67C00, dark: 0xFFD60A)
    /// Type-code chip.
    static let chip = dynamic(light: 0x8F8B84, dark: 0x273042)
    static let sweep = dynamic(light: 0x3A33D6, dark: 0x4CF0C0)
    static let live = dynamic(light: 0x23A55A, dark: 0x3DDC84)
    static let warning = dynamic(light: 0xD98B00, dark: 0xFFB020)
    /// Rare / iconic aircraft.
    static let notable = dynamic(light: 0xB7860B, dark: 0xFFCB45)
    static let military = dynamic(light: 0x55692A, dark: 0xA9C76B)

    static func color(for tag: NotableTag) -> Color {
        switch tag {
        case .hijack, .emergency, .radioFailure, .medical: return signal
        case .military: return military
        case .government: return ink
        case .rare: return notable
        }
    }

    #if os(watchOS)
    fileprivate static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(red: Double((dark >> 16) & 0xFF) / 255, green: Double((dark >> 8) & 0xFF) / 255, blue: Double(dark & 0xFF) / 255)
    }
    #else
    fileprivate static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
    #endif
}

/// The logbook's colours: the indigo ink plus complements around it (sky, teal, amber, coral,
/// pink), so stats and charts read in more than one hue. The ramps blend them by hour of the
/// day, altitude and heading, and make taller bars warmer. Light values are deep enough to
/// read as text on paper.
struct ChartTone: Sendable {
    let light: UInt32
    let dark: UInt32

    var color: Color { Palette.dynamic(light: light, dark: dark) }

    static let night = ChartTone(light: 0x2A2494, dark: 0x6F64EC)
    static let violet = ChartTone(light: 0x3A33D6, dark: 0xA8A4FF)   // Palette.ink
    static let sky = ChartTone(light: 0x2A78C8, dark: 0x6CB8FF)
    static let teal = ChartTone(light: 0x0B8573, dark: 0x4FDCC4)
    static let amber = ChartTone(light: 0xB47200, dark: 0xFFC247)
    static let coral = ChartTone(light: 0xC9502A, dark: 0xFF9466)
    static let pink = ChartTone(light: 0xC2347E, dark: 0xFF7BC4)

    /// Busier is warmer: violet at the baseline, pink, then amber at the top.
    static let heat = Gradient(stops: [.init(color: violet.color, location: 0),
                                       .init(color: pink.color, location: 0.5),
                                       .init(color: amber.color, location: 0.9)])

    /// The sky over a day, for the middle of `hour`: indigo night, pink dawn, amber midday,
    /// coral and pink dusk.
    static func timeOfDay(_ hour: Int) -> Color {
        blend([(0, night), (4.5, night), (6.5, pink), (8.5, coral), (11, amber), (15, amber),
               (17.5, coral), (19.5, pink), (21.5, violet), (24, night)], Double(hour) + 0.5)
    }

    /// Warm near the ground, cool up high: amber, coral, pink, violet, teal. `fraction` runs
    /// from the lowest band (0) to the highest (1).
    static func altitude(_ fraction: Double) -> Color {
        blend([(0, amber), (0.3, coral), (0.55, pink), (0.8, violet), (1, teal)], fraction)
    }

    /// Round the compass: teal north, amber east, pink south, violet west. A clean green
    /// between teal and amber, which would otherwise mix to olive.
    static func heading(_ degrees: Double) -> Color {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return blend([(0, teal), (45, green), (90, amber), (180, pink), (270, violet), (360, teal)], d < 0 ? d + 360 : d)
    }

    /// Also one of the route web's airport colours.
    static let green = ChartTone(light: 0x3F8A2A, dark: 0x9BE07A)

    /// `x` along stops at ascending positions, mixed separately for light and dark.
    static func blend(_ stops: [(at: Double, tone: ChartTone)], _ x: Double) -> Color {
        guard let first = stops.first, let last = stops.last else { return violet.color }
        if x <= first.at { return first.tone.color }
        if x >= last.at { return last.tone.color }
        let i = stops.firstIndex { $0.at >= x } ?? stops.count - 1
        let a = stops[i - 1], b = stops[i]
        let t = (x - a.at) / (b.at - a.at)
        return Palette.dynamic(light: mix(a.tone.light, b.tone.light, t), dark: mix(a.tone.dark, b.tone.dark, t))
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { result, shift in
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return result | UInt32((x + (y - x) * t).rounded()) << shift
        }
    }
}

#if !os(watchOS)
extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}
#endif

extension Font {
    /// SF Mono, the radar's voice, at a fixed size: the radar face, the Watch radar and the
    /// TV are compass layouts and a ten-foot UI. Sheets and lists use `monoScaled`.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// SF Mono that follows Dynamic Type: `size` at the default text size, growing and shrinking
/// with the text style nearest it (or `relativeTo`).
struct ScaledMono: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle?) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style ?? Self.textStyle(near: size))
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.mono(size, weight))
    }

    /// The text style whose default size is closest: caption2 11, caption 12, footnote 13,
    /// subheadline 15, callout 16, body 17, title3 20, title2 22, title 28, largeTitle 34.
    static func textStyle(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<14: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18.5: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        case ..<31: return .title
        default: return .largeTitle
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26+, frosted material before that.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, tvOS 26.0, watchOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    /// SF Mono that follows Dynamic Type (see `ScaledMono`), for sheets, lists and pages.
    func monoScaled(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle? = nil) -> some View {
        modifier(ScaledMono(size: size, weight: weight, relativeTo: style))
    }

    /// Small caps style caption used across the radar. `scales` follows Dynamic Type, for
    /// sheets; the radar face keeps it fixed.
    @ViewBuilder
    func radarCaption(scales: Bool = false) -> some View {
        Group {
            if scales { self.monoScaled(11, .semibold) } else { self.font(.mono(11, .semibold)) }
        }
        .tracking(1.6)
        .foregroundStyle(Palette.caption)
        .textCase(.uppercase)
    }

    /// Keeps text legible on top of the contour background.
    func paperHalo() -> some View {
        self.shadow(color: Palette.paper, radius: 1.5)
            .shadow(color: Palette.paper, radius: 3)
    }
}

/// Rotates toward a target angle the short way round, however many times it wraps.
struct ContinuousRotation: ViewModifier {
    let degrees: Double
    @State private var unwrapped: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(unwrapped ?? degrees))
            .onChange(of: degrees, initial: true) { _, target in
                if let current = unwrapped {
                    withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.45, dampingFraction: 0.86)) {
                        unwrapped = current + GeoMath.shortestDelta(from: current, to: target)
                    }
                } else {
                    unwrapped = target
                }
            }
    }
}

extension View {
    func continuousRotation(_ degrees: Double) -> some View {
        modifier(ContinuousRotation(degrees: degrees))
    }
}
#endif
