//
//  PointingUI.swift
//  WhatTheFlightWatch
//
//  Shared by Identify and Find: the screen layout (turned for Point, upright for Aim, with a
//  red marker on the edge that does the aiming), the compass strip for direction and the
//  elevation gauge for height.
//

import SwiftUI
import WatchKit

/// Where things go once the content is turned.
struct PointingMetrics {
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing }

    /// The content's size (landscape when turned a quarter, portrait otherwise).
    let size: CGSize
    /// watchOS keeps its clock in the screen's top-right corner; this is where that lands
    /// in the turned content.
    let clockCorner: Corner

    init(turn: WristPointing.ScreenTurn, screen: CGSize) {
        let quarter = turn == .clockwise || turn == .anticlockwise
        size = quarter ? CGSize(width: screen.height, height: screen.width) : screen
        switch turn {
        case .upright: clockCorner = .topTrailing
        case .clockwise: clockCorner = .topLeading
        case .upsideDown: clockCorner = .bottomLeading
        case .anticlockwise: clockCorner = .bottomTrailing
        }
    }

    /// The close button takes whichever top corner the clock doesn't.
    var closeOnLeading: Bool { clockCorner == .topTrailing }
    var bottomLeadingInset: CGFloat { clockCorner == .bottomLeading ? 28 : 0 }
    var bottomTrailingInset: CGFloat { clockCorner == .bottomTrailing ? 28 : 0 }
    /// The gauge runs down the right side, into the clock when it sits bottom-right.
    var gaugeBottomInset: CGFloat { clockCorner == .bottomTrailing ? 16 : 0 }
}

/// The screen for Identify and Find. Point: the content turns like a phone does, its top
/// toward whichever screen edge is highest (`WristPointer.screenTurn`). Aim: upright, like any
/// other screen. Either way a red marker sits on the edge that's doing the aiming — the top
/// edge for Aim, the edge toward your finger for Point — so the mode shows at a glance.
struct PointingLayout<Content: View>: View {
    let style: WristPointing.AimStyle
    let turn: WristPointing.ScreenTurn
    @ViewBuilder let content: (PointingMetrics) -> Content

    var body: some View {
        GeometryReader { geo in
            let metrics = PointingMetrics(turn: turn, screen: geo.size)
            ZStack {
                content(metrics)
                    .frame(width: metrics.size.width, height: metrics.size.height)
                    .continuousRotation(turn.degrees)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                AimMarker(edge: aimEdge, screen: geo.size)
            }
        }
        .ignoresSafeArea()
        .background(Palette.paper.ignoresSafeArea())
        .toolbarVisibility(.hidden, for: .navigationBar)
        .persistentSystemOverlays(.hidden)
    }

    private var aimEdge: Edge {
        switch style {
        case .aim: return .top
        // On the left wrist the hand is off the screen's right edge, on the right wrist its left.
        case .point: return WKInterfaceDevice.current().wristLocation == .left ? .trailing : .leading
        }
    }
}

/// A solid red arrowhead on the screen edge that points at the sky.
struct AimMarker: View {
    let edge: Edge
    let screen: CGSize

    var body: some View {
        let (position, rotation): (CGPoint, Double) = {
            switch edge {
            case .top: return (CGPoint(x: screen.width / 2, y: 7), 0)
            case .trailing: return (CGPoint(x: screen.width - 7, y: screen.height / 2), 90)
            case .bottom: return (CGPoint(x: screen.width / 2, y: screen.height - 7), 180)
            case .leading: return (CGPoint(x: 7, y: screen.height / 2), 270)
            }
        }()
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(Palette.signal)
            .shadow(color: Palette.signal.opacity(0.6), radius: 3)
            .rotationEffect(.degrees(rotation))
            .position(position)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The top row: a title in the middle, the close button in whichever top corner is free of
/// the clock. Upright, the clock is as wide as the gap beside the title (and the Aim arrow
/// sits between them), so the title drops to its own row underneath.
struct PointingTopBar<Title: View>: View {
    let metrics: PointingMetrics
    @ViewBuilder let title: () -> Title

    var body: some View {
        if metrics.clockCorner == .topTrailing {
            VStack(spacing: 2) {
                HStack {
                    PointingCloseButton()
                    Spacer()
                }
                title()
            }
        } else {
            ZStack {
                title().padding(.horizontal, 34)
                HStack {
                    if metrics.closeOnLeading {
                        PointingCloseButton()
                        Spacer()
                    } else {
                        Spacer()
                        PointingCloseButton()
                    }
                }
            }
        }
    }
}

extension View {
    /// Keeps the bottom row clear of the clock.
    func clearOfClock(_ metrics: PointingMetrics) -> some View {
        padding(.leading, metrics.bottomLeadingInset).padding(.trailing, metrics.bottomTrailingInset)
    }
}

/// The navigation bar is hidden in Identify and Find (it can't turn with the content).
struct PointingCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.value)
                .frame(width: 30, height: 30)
                .background(Palette.ink.opacity(0.16), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

/// Raw numbers, for checking the sensors outdoors against a flight you can see.
struct PointingReadout: View {
    let arm: WristPointing.Direction?
    let target: WristPointing.Direction?
    let mode: WristPointer.Mode

    var body: some View {
        let you = arm.map { "You \(Int($0.azimuth))° ↑\(Int($0.elevation))°" } ?? "You —"
        let it = target.map { " · It \(Int($0.azimuth))° ↑\(Int($0.elevation))°" } ?? ""
        let device = WKInterfaceDevice.current()
        let wearing = "\(device.wristLocation == .left ? "Left" : "Right") wrist, crown \(device.crownOrientation == .left ? "left" : "right")"
        VStack(spacing: 0) {
            Text("\(you)\(it)")
            Text("\(mode.label) · \(wearing)")
        }
        .font(.mono(8))
        .foregroundStyle(Palette.faint)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Direction

/// A compass strip centred on where your arm points. It slides as you swing round; aircraft
/// ride on it at their real bearing. The highlighted one waits at the edge with chevrons
/// when it's further round than the strip shows.
struct AzimuthStrip: View {
    struct Mark: Equatable {
        var azimuth: Double
        var isHighlighted: Bool
    }

    let arm: Double?
    let marks: [Mark]
    /// Your arm is swung round to the highlighted aircraft.
    let isFacing: Bool
    let isOnTarget: Bool

    /// Degrees either side of centre.
    static let span = 60.0

    var body: some View {
        Canvas { context, size in
            let mid = size.width / 2
            let center = arm ?? marks.first(where: \.isHighlighted)?.azimuth ?? 0
            func x(_ azimuth: Double) -> CGFloat {
                mid + CGFloat(GeoMath.shortestDelta(from: center, to: azimuth) / Self.span) * (mid - 8)
            }

            // Ticks every 15°, letters on the compass points.
            let first = Int((center - Self.span) / 15) * 15 - 15
            for degree in stride(from: first, through: Int(center + Self.span) + 15, by: 15) {
                guard abs(GeoMath.shortestDelta(from: center, to: Double(degree))) <= Self.span else { continue }
                let px = x(Double(degree))
                let normalized = Int(GeoMath.normalize(Double(degree)))
                if let letter = ["N": 0, "E": 90, "S": 180, "W": 270].first(where: { $0.value == normalized })?.key {
                    context.draw(Text(letter).font(.mono(9, .bold)).foregroundStyle(letter == "N" ? Palette.signal : Palette.caption),
                                 at: CGPoint(x: px, y: 6))
                } else {
                    var tick = Path()
                    let major = normalized % 45 == 0
                    tick.move(to: CGPoint(x: px, y: major ? 2 : 4))
                    tick.addLine(to: CGPoint(x: px, y: 10))
                    context.stroke(tick, with: .color(Palette.caption.opacity(major ? 0.8 : 0.45)), lineWidth: 1)
                }
            }

            // Your arm: the centre line.
            var line = Path()
            line.move(to: CGPoint(x: mid, y: 0))
            line.addLine(to: CGPoint(x: mid, y: size.height))
            context.stroke(line, with: .color(isFacing || isOnTarget ? Palette.live : Palette.ink), lineWidth: 2)

            // Everyone else first, faint, so the highlighted aircraft draws on top.
            for mark in marks where !mark.isHighlighted && abs(GeoMath.shortestDelta(from: center, to: mark.azimuth)) <= Self.span {
                context.draw(context.resolve(Image(systemName: "airplane")).tinted(Palette.blip.opacity(0.55)),
                             in: CGRect(x: x(mark.azimuth) - 5, y: size.height - 12, width: 10, height: 10))
            }
            for mark in marks where mark.isHighlighted {
                let delta = GeoMath.shortestDelta(from: center, to: mark.azimuth)
                let tint = isOnTarget || isFacing ? Palette.live : Palette.signal
                if abs(delta) <= Self.span {
                    context.draw(context.resolve(Image(systemName: "airplane")).tinted(tint),
                                 in: CGRect(x: x(mark.azimuth) - 7, y: size.height - 15, width: 14, height: 14))
                } else {
                    let right = delta > 0
                    context.draw(Text(Image(systemName: right ? "chevron.right.2" : "chevron.left.2"))
                                    .font(.system(size: 12, weight: .heavy)).foregroundStyle(tint),
                                 at: CGPoint(x: right ? size.width - 8 : 8, y: size.height - 8))
                }
            }
        }
        .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

private extension GraphicsContext.ResolvedImage {
    func tinted(_ color: Color) -> GraphicsContext.ResolvedImage {
        var copy = self
        copy.shading = .color(color)
        return copy
    }
}

// MARK: - Height

/// From the horizon (bottom) to straight up (top): the aircraft's height as a band, your arm
/// as a pointer. Line the pointer up with the band.
struct ElevationGauge: View {
    /// The highlighted aircraft's elevation, if there is one.
    let target: Double?
    let arm: Double?
    let isLevel: Bool
    let isOnTarget: Bool

    private static let lowest = -10.0
    private static let highest = 90.0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let trackX = geo.size.width - 8
            let y = { (elevation: Double) -> CGFloat in
                let clamped = min(Self.highest, max(Self.lowest, elevation))
                return h - CGFloat((clamped - Self.lowest) / (Self.highest - Self.lowest)) * h
            }
            let band = WristPointing.lockDegrees / (Self.highest - Self.lowest) * h
            let tint = isOnTarget || isLevel ? Palette.live : Palette.signal

            ZStack {
                Capsule()
                    .fill(Palette.ink.opacity(0.12))
                    .frame(width: 8)
                    .position(x: trackX, y: h / 2)
                Rectangle()
                    .fill(Palette.caption.opacity(0.7))
                    .frame(width: 14, height: 1)
                    .position(x: trackX, y: y(0))
                if let target {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.45))
                        .frame(width: 12, height: max(6, band * 2))
                        .position(x: trackX, y: y(target))
                    Image(systemName: "airplane")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(-90))
                        .foregroundStyle(tint)
                        .position(x: trackX, y: y(target))
                }
                if let arm {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isLevel || isOnTarget ? Palette.live : Palette.ink)
                        .position(x: trackX - 11, y: y(arm))
                        .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.9), value: arm)
                }
                Text("90°").font(.mono(7)).foregroundStyle(Palette.faint).position(x: trackX - 12, y: 4)
                Text("0°").font(.mono(7)).foregroundStyle(Palette.faint).position(x: trackX - 12, y: y(0))
            }
        }
        .accessibilityHidden(true)
    }
}
