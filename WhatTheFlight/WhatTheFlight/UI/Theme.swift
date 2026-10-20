//
//  Theme.swift
//  WhatTheFlight
//
//  Colour palette and type ramp. Light mode follows the mockup (paper, indigo ink, red
//  arrow); dark mode is a night-radar variant of the same palette.
//

#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

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
    /// Stat captions.
    static let caption = dynamic(light: 0x75726C, dark: 0x8790A0)
    /// Stat values.
    static let value = dynamic(light: 0x3B3A37, dark: 0xE7EAF0)
    static let faint = dynamic(light: 0xA29E95, dark: 0x465061)
    /// Aircraft blips.
    static let blip = dynamic(light: 0x2D56B9, dark: 0x72AAFF)
    static let heliBlip = dynamic(light: 0x3F8CF0, dark: 0x7CD8FF)
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

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Font {
    /// SF Mono, the radar's voice.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Liquid Glass on iOS 26+, frosted material before that.
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, tvOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.18), lineWidth: 0.5))
        }
    }

    /// Small caps style caption used across the radar.
    func radarCaption() -> some View {
        self.font(.mono(11, .semibold))
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

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(unwrapped ?? degrees))
            .onChange(of: degrees, initial: true) { _, target in
                if let current = unwrapped {
                    withAnimation(.interactiveSpring(response: 0.45, dampingFraction: 0.86)) {
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
