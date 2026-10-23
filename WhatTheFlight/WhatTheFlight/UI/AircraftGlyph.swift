//
//  AircraftGlyph.swift
//  WhatTheFlight
//
//  Top-down aircraft silhouettes drawn as SwiftUI shapes. Each one sits on a 64 × 64 grid
//  with the nose pointing up (north), so every icon turns to its track the same way. Wings,
//  tailplanes and engines are half outlines mirrored down the centre line. Propeller discs
//  and helicopter rotors are a separate, translucent layer; the rotor spins unless Reduce
//  Motion or the Always-On display is in effect.
//

#if os(iOS) || os(tvOS) || os(watchOS)
import SwiftUI

struct AircraftGlyph: View {
    let silhouette: AircraftSilhouette
    /// Edge length of the 64-point grid. The airliner fills about 86% of it.
    var size: CGFloat
    var spinsRotor = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        ZStack {
            translucentLayer
            AircraftSilhouetteShape(silhouette: silhouette, layer: .solid)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var translucentLayer: some View {
        let shape = AircraftSilhouetteShape(silhouette: silhouette, layer: .translucent)
        if silhouette == .helicopter {
            if spinsRotor && !reduceMotion && !isLuminanceReduced {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    shape.opacity(0.55)
                        .rotationEffect(.degrees(Self.rotorAngle(at: context.date)), anchor: Self.rotorHub)
                }
            } else {
                shape.opacity(0.55)
            }
        } else {
            shape.opacity(0.34)
        }
    }

    /// The rotor hub on the 64-point grid.
    private static let rotorHub = UnitPoint(x: 0.5, y: 27.0 / 64)
    private static let rotorPeriod: TimeInterval = 1.2

    private static func rotorAngle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: rotorPeriod) / rotorPeriod * 360
    }
}

struct AircraftSilhouetteShape: Shape {
    enum Layer: Sendable { case solid, translucent }

    let silhouette: AircraftSilhouette
    var layer: Layer = .solid

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = layer == .solid ? Self.paths[silhouette]?.solid : Self.paths[silhouette]?.translucent
        guard let unit else { return Path() }
        let transform = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: side / 64, y: side / 64)
        return unit.applying(transform)
    }

    private static let paths: [AircraftSilhouette: (solid: Path, translucent: Path)] = {
        var table: [AircraftSilhouette: (solid: Path, translucent: Path)] = [:]
        for silhouette in AircraftSilhouette.allCases {
            var drawing = SilhouetteDrawing()
            drawing.draw(silhouette)
            table[silhouette] = (drawing.solid, drawing.translucent)
        }
        return table
    }()
}

/// Builds one silhouette from mirrored parts. The parts overlap, so each one is unioned into
/// its layer as it's added (a plain `addPath` could leave holes where windings disagree).
private struct SilhouetteDrawing {
    var solid = Path()
    var translucent = Path()

    private static let centre: CGFloat = 32

    private static func mirror(_ x: CGFloat) -> CGFloat { 64 - x }

    mutating func draw(_ silhouette: AircraftSilhouette) {
        switch silhouette {
        case .airliner:
            fuselage(nose: 5, tail: 60, halfWidth: 3.6, noseLength: 7, tailHalfWidth: 1.2, taperFrom: 46)
            mirrored([(32.5, 25), (57, 37.5), (57.5, 40.5), (32.5, 36)])
            pods(x: 42.5, from: 25.5, to: 33, width: 4.6)
            mirrored([(32.5, 51), (43, 56.5), (43.3, 59), (32.5, 57)])
        case .widebody:
            fuselage(nose: 3, tail: 61, halfWidth: 4.6, noseLength: 8, tailHalfWidth: 1.4, taperFrom: 46)
            mirrored([(32.5, 22), (61.5, 39), (62, 42.5), (32.5, 37)])
            pods(x: 44, from: 22.5, to: 33, width: 6.2)
            mirrored([(32.5, 50.5), (46, 57), (46.3, 60), (32.5, 57)])
        case .fourEngine:
            fuselage(nose: 2.5, tail: 61.5, halfWidth: 5, noseLength: 9, tailHalfWidth: 1.5, taperFrom: 47)
            mirrored([(32.5, 21), (62, 40.5), (62.5, 44), (32.5, 37)])
            pods(x: 41.5, from: 22.5, to: 31, width: 4.8)
            pods(x: 52, from: 29, to: 37, width: 4.4)
            mirrored([(32.5, 50.5), (47, 57.5), (47.3, 60.5), (32.5, 57)])
        case .regional:
            fuselage(nose: 6, tail: 59, halfWidth: 3.2, noseLength: 6.5, tailHalfWidth: 1.1, taperFrom: 47)
            mirrored([(32.5, 28), (54, 38), (54.5, 41), (32.5, 37)])
            blocks(x: 34.5, y: 46, width: 2.6, height: 2.5)
            pods(x: 38.3, from: 43, to: 51.5, width: 4.4)
            mirrored([(32.5, 53.5), (42, 56.5), (42.2, 59), (32.5, 59)])
        case .bizjet:
            fuselage(nose: 7, tail: 57, halfWidth: 2.8, noseLength: 6.5, tailHalfWidth: 1, taperFrom: 46)
            mirrored([(32.5, 30), (51.5, 40), (52.5, 43.5), (32.5, 38.5)])
            blocks(x: 34, y: 44.5, width: 2.2, height: 2)
            pods(x: 37.6, from: 41.5, to: 49, width: 4)
            mirrored([(32.5, 51), (40.5, 54.5), (40.8, 57), (32.5, 56.5)])
        case .twinProp:
            fuselage(nose: 6, tail: 59, halfWidth: 3.3, noseLength: 6, tailHalfWidth: 1.1, taperFrom: 46)
            mirrored([(32.5, 27), (61, 28.2), (61, 32.5), (32.5, 34)])
            pods(x: 42, from: 22, to: 35, width: 4.2)
            propeller(x: 42, y: 22, radius: 7.5)
            mirrored([(32.5, 51.5), (44, 52), (44, 56), (32.5, 56.5)])
        case .light:
            fuselage(nose: 9, tail: 58, halfWidth: 3.8, noseLength: 4, tailHalfWidth: 0.9, taperFrom: 30)
            mirrored([(32.5, 21), (61, 21.3), (61, 28.5), (32.5, 28.5)])
            propeller(x: 32, y: 8.5, radius: 8)
            mirrored([(32.5, 49.5), (42.5, 49.8), (42.5, 55), (32.5, 55.5)])
        case .fighter:
            fuselage(nose: 2, tail: 60, halfWidth: 3.6, noseLength: 15, tailHalfWidth: 2.4, taperFrom: 54, sharp: true)
            mirrored([(33, 14), (37.5, 27), (37.5, 33), (32.5, 33)])
            mirrored([(34, 27), (56, 42), (56, 46.5), (34, 46.5)])
            mirrored([(34, 50), (45, 57), (45, 60.5), (34, 60)])
        case .militaryTransport:
            fuselage(nose: 4, tail: 59, halfWidth: 5.6, noseLength: 7, tailHalfWidth: 1.6, taperFrom: 45)
            mirrored([(32.5, 24), (62, 32), (62, 35.5), (32.5, 34.5)])
            pods(x: 42, from: 19.5, to: 29, width: 4.6)
            pods(x: 52.5, from: 22.5, to: 31.5, width: 4.2)
            mirrored([(32.5, 52.5), (47, 54), (47, 57.5), (32.5, 59)])
        case .helicopter:
            let hub = CGPoint(x: 32, y: 27)
            for angle in [45.0, -45.0] {
                let blade = Path(roundedRect: CGRect(x: 3, y: 25.3, width: 58, height: 3.4), cornerRadius: 1.7)
                let turn = CGAffineTransform(translationX: hub.x, y: hub.y)
                    .rotated(by: angle * .pi / 180)
                    .translatedBy(x: -hub.x, y: -hub.y)
                translucent = translucent.union(blade.applying(turn))
            }
            var boom = Path()
            boom.move(to: CGPoint(x: 30.2, y: 36))
            boom.addLine(to: CGPoint(x: 33.8, y: 36))
            boom.addLine(to: CGPoint(x: 33, y: 57))
            boom.addLine(to: CGPoint(x: 31, y: 57))
            boom.closeSubpath()
            solid = solid.union(boom)
            solid = solid.union(Path(roundedRect: CGRect(x: 25, y: 49, width: 14, height: 3), cornerRadius: 1.2))
            solid = solid.union(Path(roundedRect: CGRect(x: 33.6, y: 52.5, width: 2.6, height: 9), cornerRadius: 1))
            solid = solid.union(Path(ellipseIn: CGRect(x: 25.5, y: 16, width: 13, height: 22)))
        }
    }

    /// Nose at `nose`, tail at `tail`; straight sides from the end of the nose curve down to
    /// `taperFrom`, then tapering to `tailHalfWidth`.
    private mutating func fuselage(nose n: CGFloat, tail t: CGFloat, halfWidth w: CGFloat, noseLength l: CGFloat,
                                   tailHalfWidth tw: CGFloat, taperFrom taper: CGFloat, sharp: Bool = false) {
        let c = Self.centre
        var p = Path()
        p.move(to: CGPoint(x: c, y: n))
        if sharp {
            p.addCurve(to: CGPoint(x: c + w, y: n + l),
                       control1: CGPoint(x: c + w * 0.15, y: n + l * 0.35),
                       control2: CGPoint(x: c + w * 0.9, y: n + l * 0.75))
        } else {
            p.addCurve(to: CGPoint(x: c + w, y: n + l),
                       control1: CGPoint(x: c + w * 0.55, y: n),
                       control2: CGPoint(x: c + w, y: n + l * 0.45))
        }
        p.addLine(to: CGPoint(x: c + w, y: taper))
        p.addLine(to: CGPoint(x: c + tw, y: t))
        p.addLine(to: CGPoint(x: c - tw, y: t))
        p.addLine(to: CGPoint(x: c - w, y: taper))
        p.addLine(to: CGPoint(x: c - w, y: n + l))
        if sharp {
            p.addCurve(to: CGPoint(x: c, y: n),
                       control1: CGPoint(x: c - w * 0.9, y: n + l * 0.75),
                       control2: CGPoint(x: c - w * 0.15, y: n + l * 0.35))
        } else {
            p.addCurve(to: CGPoint(x: c, y: n),
                       control1: CGPoint(x: c - w, y: n + l * 0.45),
                       control2: CGPoint(x: c - w * 0.55, y: n))
        }
        p.closeSubpath()
        solid = solid.union(p)
    }

    /// A right-hand outline (root leading edge → tip → root trailing edge) joined to its
    /// mirror image on the left.
    private mutating func mirrored(_ right: [(CGFloat, CGFloat)]) {
        let points = right.map { CGPoint(x: $0.0, y: $0.1) }
            + right.reversed().map { CGPoint(x: Self.mirror($0.0), y: $0.1) }
        var p = Path()
        p.addLines(points)
        p.closeSubpath()
        solid = solid.union(p)
    }

    /// A pair of engine nacelles, centred at `x` and its mirror.
    private mutating func pods(x: CGFloat, from top: CGFloat, to bottom: CGFloat, width: CGFloat) {
        for cx in [x, Self.mirror(x)] {
            solid = solid.union(Path(roundedRect: CGRect(x: cx - width / 2, y: top, width: width, height: bottom - top),
                                     cornerRadius: width / 2))
        }
    }

    /// A pair of small blocks (engine pylons), the left edge of the right-hand one at `x`.
    private mutating func blocks(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        for left in [x, Self.mirror(x + width)] {
            solid = solid.union(Path(roundedRect: CGRect(x: left, y: y, width: width, height: height), cornerRadius: 0.6))
        }
    }

    /// Spinning disc (translucent), blade and spinner. Mirrored unless on the centre line.
    private mutating func propeller(x: CGFloat, y: CGFloat, radius r: CGFloat) {
        let centres = x == Self.centre ? [x] : [x, Self.mirror(x)]
        for cx in centres {
            translucent = translucent.union(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: 2 * r, height: 2 * r)))
            solid = solid.union(Path(roundedRect: CGRect(x: cx - r, y: y - 0.9, width: 2 * r, height: 1.8), cornerRadius: 0.9))
            solid = solid.union(Path(ellipseIn: CGRect(x: cx - 1.9, y: y - 1.9, width: 3.8, height: 3.8)))
        }
    }
}

extension Palette {
    /// Resting colour for an aircraft's icon and distance label: military olive, otherwise
    /// the standard blip.
    static func blip(for profile: FlightProfile) -> Color {
        blip(isMilitary: profile.notable.contains { $0.tag == .military })
    }

    static func blip(isMilitary: Bool) -> Color {
        isMilitary ? military : blip
    }
}
#endif
