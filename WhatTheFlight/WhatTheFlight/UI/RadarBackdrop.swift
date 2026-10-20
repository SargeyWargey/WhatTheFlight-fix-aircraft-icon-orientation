//
//  RadarBackdrop.swift
//  WhatTheFlight
//
//  Paper + topographic contours + faint range rings + a slow radar sweep, and the compass
//  bezel that hugs the screen edge and turns with the phone.
//

#if os(iOS) || os(tvOS)
import SwiftUI

struct RadarBackdrop: View {
    let showTopography: Bool
    let showSweep: Bool
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                Palette.paper

                if showTopography {
                    topography
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }

                RangeRings()
                    .stroke(Palette.ink.opacity(colorScheme == .dark ? 0.10 : 0.07),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 5]))

                if showSweep && !reduceMotion && isActive {
                    RadarSweep()
                        .frame(width: side * 1.25, height: side * 1.25)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }

                RadialGradient(
                    colors: [.clear, Palette.paperShade.opacity(colorScheme == .dark ? 0.85 : 0.45)],
                    center: .center,
                    startRadius: side * 0.25,
                    endRadius: side * 0.75
                )
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var topography: some View {
        if colorScheme == .dark {
            Image("Topography")
                .resizable()
                .scaledToFill()
                .colorInvert()
                .blendMode(.screen)
                .opacity(0.22)
        } else {
            Image("Topography")
                .resizable()
                .scaledToFill()
                .blendMode(.multiply)
                .opacity(0.42)
        }
    }
}

/// Concentric scope rings centred on the screen.
struct RangeRings: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let unit = min(rect.width, rect.height) / 2
        for fraction in [0.42, 0.72, 1.02, 1.32] {
            let r = unit * fraction
            path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

/// A soft wedge that rotates once every few seconds.
struct RadarSweep: View {
    @State private var angle: Double = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Circle()
            .fill(
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.82),
                        .init(color: Palette.sweep.opacity(colorScheme == .dark ? 0.10 : 0.05), location: 0.995),
                        .init(color: .clear, location: 1),
                    ],
                    center: .center
                )
            )
            .mask(RadialGradient(colors: [.black, .black.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 600))
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}

/// Tick marks and N / E / S / W around the edge of the screen, rotated by the compass so
/// "N" always points at real north.
struct CompassBezel: View, Animatable {
    let track: PerimeterTrack
    var heading: Double
    var scale: CGFloat = 1

    var animatableData: Double {
        get { heading }
        set { heading = newValue }
    }

    var body: some View {
        Canvas { context, _ in
            let tickColor = Palette.caption
            for degree in stride(from: 0, to: 360, by: 5) {
                let screenAngle = Double(degree) - heading
                let point = track.point(forScreenAngle: screenAngle)
                let inward = track.inwardDirection(from: point)
                let isCardinal = degree % 90 == 0
                let isMajor = degree % 30 == 0
                guard !isCardinal else { continue }
                let length: CGFloat = (isMajor ? 8 : 4) * scale
                var tick = Path()
                tick.move(to: point)
                tick.addLine(to: CGPoint(x: point.x + inward.dx * length, y: point.y + inward.dy * length))
                context.stroke(tick, with: .color(tickColor.opacity(isMajor ? 0.75 : 0.4)), lineWidth: (isMajor ? 1.4 : 1) * scale)
            }
            for (degree, letter) in [(0, "N"), (90, "E"), (180, "S"), (270, "W")] {
                let point = track.point(forScreenAngle: Double(degree) - heading)
                let inward = track.inwardDirection(from: point)
                let at = CGPoint(x: point.x + inward.dx * 6 * scale, y: point.y + inward.dy * 6 * scale)
                let text = Text(letter)
                    .font(.mono(11 * scale, .bold))
                    .foregroundStyle(degree == 0 ? Palette.signal : Palette.caption)
                context.draw(text, at: at, anchor: .center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
