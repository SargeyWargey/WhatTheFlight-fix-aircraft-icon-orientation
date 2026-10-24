//
//  WristPointing.swift
//  WhatTheFlight
//
//  Point & Find on Apple Watch: which way the wearer's arm points in the sky, and how far
//  that is from an aircraft. The forearm runs along the watch's x axis; which end of it
//  faces the hand depends on the wrist and crown settings. World vectors are east-north-up.
//

import Foundation
import simd

enum WristPointing {
    /// Within this many degrees, you're pointing at it.
    static let lockDegrees = 8.0

    /// +1 when the watch's +x axis (the crown side of the hardware) faces the hand, else -1.
    /// Core Motion reports in the hardware frame, so the crown's side is what matters: on the
    /// left wrist with the crown on the right, or the right wrist with the crown on the left,
    /// the crown faces the fingers. `flipped` is the user's escape hatch if that's wrong.
    static func axisSign(leftWrist: Bool, crownOnRight: Bool, flipped: Bool = false) -> Double {
        let crownTowardHand = leftWrist == crownOnRight
        return (crownTowardHand ? 1 : -1) * (flipped ? -1 : 1)
    }

    // MARK: Attitude → pointing

    /// Core Motion's reference frame (X = north, Y = west, Z = up) to east-north-up.
    static func enu(fromNorthWestUp v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(-v.y, v.x, v.z)
    }

    /// The device's x, y, z axes as east-north-up vectors, from the attitude rotation matrix
    /// given as its three rows. Whether the axes are the matrix's rows or columns is settled
    /// at runtime by `axesAreRows(rows:gravity:)`.
    static func deviceAxes(rows: [SIMD3<Double>], axesAreRows: Bool) -> (x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>) {
        precondition(rows.count == 3)
        func axis(_ i: Int) -> SIMD3<Double> {
            axesAreRows ? rows[i] : SIMD3(rows[0][i], rows[1][i], rows[2][i])
        }
        return (enu(fromNorthWestUp: axis(0)), enu(fromNorthWestUp: axis(1)), enu(fromNorthWestUp: axis(2)))
    }

    /// Which matrix convention reproduces the measured gravity (device frame, in g)? `nil`
    /// while the device is too flat to tell the two apart.
    static func axesAreRows(rows: [SIMD3<Double>], gravity g: SIMD3<Double>) -> Bool? {
        guard abs(g.z) < 0.9 else { return nil }
        let rowsError = abs(-rows[0].z - g.x) + abs(-rows[1].z - g.y) + abs(-rows[2].z - g.z)
        let colsError = abs(-rows[2].x - g.x) + abs(-rows[2].y - g.y) + abs(-rows[2].z - g.z)
        guard abs(rowsError - colsError) > 0.3 else { return nil }
        return rowsError <= colsError
    }

    /// Where the arm points, from the full attitude (true- or magnetic-north frame).
    static func pointing(rows: [SIMD3<Double>], axesAreRows: Bool, axisSign: Double) -> SIMD3<Double> {
        simd_normalize(deviceAxes(rows: rows, axesAreRows: axesAreRows).x * axisSign)
    }

    /// Fallback without a north-referenced attitude: elevation from gravity alone, azimuth
    /// from the compass heading of the watch's 12 o'clock edge, turned 90° toward the forearm.
    static func pointing(gravity g: SIMD3<Double>, headingOfTop: Double, axisSign: Double) -> SIMD3<Double> {
        let length = simd_length(g)
        let upX = length > 0.01 ? -g.x / length : 0
        let elevation = asin(max(-1, min(1, upX * axisSign))).degrees
        return SkyProjector.direction(azimuth: headingOfTop + 90 * axisSign, elevation: elevation)
    }

    /// Turns a direction clockwise about the vertical: magnetic-north attitude plus the local
    /// declination (true − magnetic heading) gives true north.
    static func rotateAzimuth(_ v: SIMD3<Double>, by degrees: Double) -> SIMD3<Double> {
        let d = degrees.radians
        return SIMD3(v.x * cos(d) + v.y * sin(d), v.y * cos(d) - v.x * sin(d), v.z)
    }

    // MARK: Targets & guidance

    struct Direction: Equatable {
        /// Degrees from north, clockwise.
        var azimuth: Double
        /// Degrees above the horizon.
        var elevation: Double
    }

    static func direction(of v: SIMD3<Double>) -> Direction {
        let n = simd_normalize(v)
        return Direction(azimuth: GeoMath.normalize(atan2(n.x, n.y).degrees),
                         elevation: asin(max(-1, min(1, n.z))).degrees)
    }

    /// The aircraft's direction in the sky from the observer.
    static func target(for contact: RadarContact) -> SIMD3<Double> {
        let elevation = GeoMath.elevationDegrees(groundDistanceMiles: contact.distanceMiles,
                                                 altitudeFeet: Double(contact.altitudeFeet))
        return SkyProjector.direction(azimuth: contact.bearing, elevation: elevation)
    }

    struct Guidance: Equatable {
        /// Total angle between the arm and the aircraft, degrees.
        var error: Double
        /// Swing this far clockwise (negative: anticlockwise), degrees of azimuth.
        var turn: Double
        /// Raise the arm this far (negative: lower it), degrees.
        var raise: Double
        /// Which way to move on a flat dial: 0 = raise, 90 = swing right.
        var arrowAngle: Double
        /// The left-right miss as the arm feels it: near the zenith a big azimuth difference
        /// is a small swing of the arm.
        var sideways: Double

        var isOnTarget: Bool { error <= WristPointing.lockDegrees }
        /// Swung round far enough: only the height is left to fix.
        var isFacing: Bool { abs(sideways) <= WristPointing.lockDegrees }
        /// At the right height: only the direction is left to fix.
        var isLevel: Bool { abs(raise) <= WristPointing.lockDegrees }
    }

    static func guidance(pointing: SIMD3<Double>, target: SIMD3<Double>) -> Guidance {
        let p = simd_normalize(pointing), t = simd_normalize(target)
        let error = acos(max(-1, min(1, simd_dot(p, t)))).degrees
        let from = direction(of: p), to = direction(of: t)
        let turn = GeoMath.shortestDelta(from: from.azimuth, to: to.azimuth)
        let raise = to.elevation - from.elevation
        let sideways = turn * cos(from.elevation.radians)
        let arrow = GeoMath.normalize(atan2(sideways, raise).degrees)
        return Guidance(error: error, turn: turn, raise: raise, arrowAngle: arrow, sideways: sideways)
    }

    /// What the wrist should feel, so you can keep your eyes on the sky: clicks that speed up
    /// while you swing round to face it, then "up" / "down" taps for the height, then one
    /// firm tap when you're on it.
    enum Cue: Equatable {
        case warmer(every: TimeInterval)
        case raise(every: TimeInterval)
        case lower(every: TimeInterval)
        case onTarget
    }

    static func cue(for g: Guidance) -> Cue {
        if g.isOnTarget { return .onTarget }
        if !g.isFacing {
            return .warmer(every: clickInterval(forError: abs(g.sideways)) ?? 0.15)
        }
        // The up / down taps are longer than a click; don't let them run together.
        let every = max(0.45, clickInterval(forError: abs(g.raise)) ?? 0.45)
        return g.raise > 0 ? .raise(every: every) : .lower(every: every)
    }

    /// Seconds between "warmer" clicks: slow when far off, quick when close, nil on target.
    static func clickInterval(forError degrees: Double) -> TimeInterval? {
        guard degrees > lockDegrees else { return nil }
        let t = min(1, (degrees - lockDegrees) / (120 - lockDegrees))
        return 0.12 + t * (1.1 - 0.12)
    }
}

// MARK: - Identify

extension WristPointing {
    /// Identify looks further than the radar (an airliner is easy to see well past 10 mi)…
    static let identifyRangeMiles = 15.0
    /// …skips anything this low (trees and buildings, and the angles get unreliable)…
    static let minimumElevation = 3.0
    /// …except helicopters, which fly low enough that 3° would drop any more than about
    /// 3 mi away (800 ft up); 1° keeps them out to about 9 mi…
    static let helicopterMinimumElevation = 1.0
    /// …and calls out whatever lies within this cone around the arm.
    static let identifyCone = 10.0

    /// Close enough and high enough to point at.
    static func isIdentifiable(_ contact: RadarContact, rangeMiles: Double = identifyRangeMiles) -> Bool {
        guard contact.distanceMiles <= rangeMiles else { return false }
        let floor = contact.flight.kind == .helicopter ? helicopterMinimumElevation : minimumElevation
        return GeoMath.elevationDegrees(groundDistanceMiles: contact.distanceMiles,
                                        altitudeFeet: Double(contact.altitudeFeet)) >= floor
    }

    struct Candidate: Equatable {
        let id: String
        /// Degrees between the arm and the aircraft.
        let error: Double
    }

    /// Aircraft within `cone` of the arm, best match first.
    static func candidates(pointing: SIMD3<Double>, contacts: [RadarContact], cone: Double = identifyCone,
                           rangeMiles: Double = identifyRangeMiles) -> [Candidate] {
        let arm = simd_normalize(pointing)
        return contacts.compactMap { contact -> Candidate? in
            guard isIdentifiable(contact, rangeMiles: rangeMiles) else { return nil }
            let error = acos(max(-1, min(1, simd_dot(arm, target(for: contact))))).degrees
            return error <= cone ? Candidate(id: contact.id, error: error) : nil
        }
        .sorted { $0.error < $1.error }
    }

    /// While you swing round, the height gauge shows the aircraft nearest your arm on the
    /// compass, so you know whether to raise or lower before it's in the cone.
    static let leadSpan = 30.0
    /// A new aircraft takes the lead only when it's this much nearer, so two neighbours
    /// don't flicker on a shaky arm.
    static let leadMargin = 4.0

    /// The aircraft nearest `armAzimuth` (within `leadSpan`), keeping `current` unless
    /// another is clearly nearer.
    static func lead(armAzimuth: Double, contacts: [RadarContact], current: String? = nil) -> String? {
        let offsets = contacts.map { (id: $0.id, offset: abs(GeoMath.shortestDelta(from: armAzimuth, to: $0.bearing))) }
            .filter { $0.offset <= leadSpan }
        guard let best = offsets.min(by: { $0.offset < $1.offset }) else { return nil }
        if let current, let kept = offsets.first(where: { $0.id == current }), kept.offset - best.offset < leadMargin {
            return current
        }
        return best.id
    }
}

/// Turns "best match right now" into a steady call-out. An aircraft has to stay in the cone
/// for `hold` before it's named; once named it keeps the name while it stays within the
/// wider `keepCone`, so a neighbour can't snatch it on a tremor. The crown can prefer one.
struct IdentifyTracker: Equatable {
    enum State: Equatable {
        case searching
        case acquiring(id: String, since: Date)
        case locked(id: String)
    }

    enum Event: Equatable {
        /// Something came into the cone (a light tick).
        case acquiring(String)
        /// Held long enough: name it (a firm tap, and speak).
        case named(String)
        /// Nothing in the cone any more.
        case lost
    }

    static let hold: TimeInterval = 0.5
    static let keepCone = 15.0

    private(set) var state: State = .searching
    /// Chosen with the crown: wins whenever it's in the cone.
    var preferredID: String?

    var currentID: String? {
        switch state {
        case .searching: return nil
        case .acquiring(let id, _), .locked(let id): return id
        }
    }

    var isLocked: Bool {
        if case .locked = state { return true }
        return false
    }

    /// `candidates` are everything within `keepCone`, best first.
    mutating func update(_ candidates: [WristPointing.Candidate], now: Date) -> Event? {
        let inCone = candidates.filter { $0.error <= WristPointing.identifyCone }
        let preferred = preferredID.flatMap { id in inCone.first { $0.id == id } }

        if case .locked(let id) = state, candidates.contains(where: { $0.id == id }) {
            if let preferred, preferred.id != id {
                state = .locked(id: preferred.id)
                return .named(preferred.id)
            }
            return nil
        }

        guard let pick = preferred ?? inCone.first else {
            let wasSearching = state == .searching
            state = .searching
            return wasSearching ? nil : .lost
        }
        if case .acquiring(let id, let since) = state, id == pick.id {
            guard now.timeIntervalSince(since) >= Self.hold else { return nil }
            state = .locked(id: id)
            return .named(id)
        }
        state = .acquiring(id: pick.id, since: now)
        return .acquiring(pick.id)
    }
}

// MARK: - Which way up the screen goes

extension WristPointing {
    /// How the arm-out content is turned on the screen, clockwise.
    enum ScreenTurn: Int, Equatable {
        case upright = 0, clockwise = 90, upsideDown = 180, anticlockwise = 270

        var degrees: Double { Double(rawValue) }

        /// Half a turn more (the "Turn screen around" setting).
        var reversed: ScreenTurn { ScreenTurn(rawValue: (rawValue + 180) % 360)! }
    }

    /// The screen's x axis in Core Motion's frame: +1 when they match, -1 when watchOS shows
    /// the screen turned round. Taken from the arm direction (which the wearer can verify by
    /// pointing) and one fact: on the left wrist the hand is at the screen's right edge, on the
    /// right wrist at its left.
    static func displaySign(leftWrist: Bool, axisSign: Double) -> Double {
        leftWrist ? axisSign : -axisSign
    }

    /// The turn that puts the top of the text toward the hand: right on the left wrist.
    static func handTurn(leftWrist: Bool) -> ScreenTurn {
        leftWrist ? .clockwise : .anticlockwise
    }

    /// Like a phone turning to landscape: the content's top goes to whichever screen edge is
    /// highest. Arm raised palm-down puts it toward the hand; turned thumb-up, the text runs
    /// upright along the arm. Keeps `current` while the screen lies too flat to tell, or
    /// until another edge is clearly higher.
    static func screenTurn(gravity g: SIMD3<Double>, displaySign: Double, current: ScreenTurn,
                           minimumTilt: Double = 0.3, margin: Double = 0.25) -> ScreenTurn {
        let length = simd_length(g)
        guard length > 0.01 else { return current }
        // "Up" in screen terms: +x is the right edge, +y the top (12 o'clock).
        let upX = -g.x / length * displaySign
        let upY = -g.y / length * displaySign
        func height(_ turn: ScreenTurn) -> Double {
            switch turn {
            case .upright: return upY
            case .clockwise: return upX
            case .upsideDown: return -upY
            case .anticlockwise: return -upX
            }
        }
        let best = [ScreenTurn.upright, .clockwise, .upsideDown, .anticlockwise].max { height($0) < height($1) }!
        guard best != current, height(best) >= minimumTilt, height(best) - height(current) >= margin else { return current }
        return best
    }
}

// MARK: - Aim: sighting along the top edge

extension WristPointing {
    /// How you aim in Identify and Find.
    enum AimStyle: String, CaseIterable, Identifiable {
        /// Arm out, finger at the plane: the forearm is the pointer.
        case point
        /// Hold the Watch as if reading it and sight along its top (12 o'clock) edge: turn your
        /// body to swing round, tilt your wrist for height. The screen faces you, so it stays bright.
        case aim

        var id: String { rawValue }
    }

    /// Where the Watch's top edge points, from the full attitude. `displaySign` turns Core
    /// Motion's y axis into the screen's (see `displaySign(leftWrist:axisSign:)`).
    static func sightLine(rows: [SIMD3<Double>], axesAreRows: Bool, displaySign: Double) -> SIMD3<Double> {
        simd_normalize(deviceAxes(rows: rows, axesAreRows: axesAreRows).y * displaySign)
    }

    /// Fallback without a north-referenced attitude: the top edge's tilt from gravity, its
    /// direction from the compass heading (which is the heading of the top edge).
    static func sightLine(gravity g: SIMD3<Double>, headingOfTop: Double, displaySign: Double) -> SIMD3<Double> {
        let length = simd_length(g)
        let upY = length > 0.01 ? -g.y / length * displaySign : 0
        let elevation = asin(max(-1, min(1, upY))).degrees
        return SkyProjector.direction(azimuth: headingOfTop, elevation: elevation)
    }
}
