//
//  PerimeterTrack.swift
//  WhatTheFlight
//
//  The rounded-rectangle path the aircraft icons ride on. It mirrors the shape of the
//  phone, is parameterised by arc length (`s`, clockwise from top-centre), and can map a
//  screen angle (0° = up, clockwise) to the point where a ray from the centre meets it.
//

import Foundation
import CoreGraphics

struct PerimeterTrack: Equatable {
    let rect: CGRect
    let cornerRadius: CGFloat
    let length: CGFloat
    private let sampleAngles: [Double]

    private static let sampleCount = 1440

    init(rect: CGRect, cornerRadius: CGFloat) {
        self.rect = rect
        let r = max(0, min(cornerRadius, rect.width / 2, rect.height / 2))
        self.cornerRadius = r
        let straight = 2 * (rect.width - 2 * r) + 2 * (rect.height - 2 * r)
        let length = max(1, straight + 2 * .pi * r)
        self.length = length
        self.sampleAngles = Self.samples.angles(for: SampleKey(rect: rect, r: r)) {
            Self.buildSamples(rect: rect, r: r, length: length)
        }
    }

    private static func buildSamples(rect: CGRect, r: CGFloat, length: CGFloat) -> [Double] {
        var angles: [Double] = []
        angles.reserveCapacity(sampleCount + 1)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0...sampleCount {
            let s = length * CGFloat(i) / CGFloat(sampleCount)
            let p = point(at: s, rect: rect, r: r, length: length)
            var angle = screenAngle(of: p, from: center)
            // Keep the sequence monotonic: the last sample closes the loop at 360°.
            if i > 0, angle < (angles.last ?? 0) - 180 { angle += 360 }
            if i == sampleCount { angle = 360 }
            angles.append(angle)
        }
        return angles
    }

    // MARK: - Sample cache

    /// Screens rebuild their layout on every tick and heading change, but only ever ask for
    /// a handful of tracks (bezel and icons, per screen size), so the samples are shared.
    private static let samples = SampleCache()

    /// How many times the samples have actually been computed (tests).
    static var sampleBuilds: Int { samples.builds }

    private struct SampleKey: Hashable {
        let x, y, width, height, r: CGFloat

        init(rect: CGRect, r: CGFloat) {
            x = rect.minX; y = rect.minY; width = rect.width; height = rect.height
            self.r = r
        }
    }

    private final class SampleCache: @unchecked Sendable {
        private let lock = NSLock()
        private var store: [SampleKey: [Double]] = [:]
        private(set) var builds = 0

        func angles(for key: SampleKey, build: () -> [Double]) -> [Double] {
            if let hit = lock.withLock({ store[key] }) { return hit }
            let built = build()
            lock.withLock {
                // Sizes change rarely (rotation, Split View); a full cache is just stale ones.
                if store.count >= 16 { store.removeAll() }
                store[key] = built
                builds += 1
            }
            return built
        }
    }

    var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// Point on the track at arc length `s` (wraps).
    func point(at s: CGFloat) -> CGPoint {
        Self.point(at: wrap(s), rect: rect, r: cornerRadius, length: length)
    }

    /// Arc length where a ray from the centre at `angle` (0° = up, clockwise) meets the track.
    func arcLength(forScreenAngle angle: Double) -> CGFloat {
        let a = GeoMath.normalize(angle)
        var lo = 0, hi = sampleAngles.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if sampleAngles[mid] <= a { lo = mid } else { hi = mid }
        }
        let a0 = sampleAngles[lo], a1 = sampleAngles[hi]
        let t = a1 > a0 ? (a - a0) / (a1 - a0) : 0
        let s = (Double(lo) + t) / Double(Self.sampleCount) * Double(length)
        return CGFloat(s)
    }

    func point(forScreenAngle angle: Double) -> CGPoint {
        point(at: arcLength(forScreenAngle: angle))
    }

    /// Unit vector from `point` toward the centre of the track.
    func inwardDirection(from point: CGPoint) -> CGVector {
        let dx = center.x - point.x, dy = center.y - point.y
        let len = max(0.0001, sqrt(dx * dx + dy * dy))
        return CGVector(dx: dx / len, dy: dy / len)
    }

    func wrap(_ s: CGFloat) -> CGFloat {
        let r = s.truncatingRemainder(dividingBy: length)
        return r < 0 ? r + length : r
    }

    /// Signed shortest arc-length offset from `a` to `b`.
    func delta(from a: CGFloat, to b: CGFloat) -> CGFloat {
        var d = wrap(b) - wrap(a)
        if d > length / 2 { d -= length } else if d < -length / 2 { d += length }
        return d
    }

    enum Corner { case topRight, bottomRight, bottomLeft, topLeft }

    /// Arc length of the midpoint of a rounded corner.
    func arcLength(of corner: Corner) -> CGFloat {
        let r = cornerRadius
        let quarter = CGFloat.pi / 2 * r
        let topHalf = rect.width / 2 - r
        let side = rect.height - 2 * r
        let bottom = rect.width - 2 * r
        switch corner {
        case .topRight: return topHalf + quarter / 2
        case .bottomRight: return topHalf + quarter + side + quarter / 2
        case .bottomLeft: return topHalf + quarter + side + quarter + bottom + quarter / 2
        case .topLeft: return topHalf + quarter + side + quarter + bottom + quarter + side + quarter / 2
        }
    }

    // MARK: - Collision avoidance

    struct Obstacle: Equatable {
        var s: CGFloat
        var halfWidth: CGFloat
    }

    /// Spaces icons along the track so neighbours keep at least `minGap` between centres and
    /// nothing sits on an obstacle (the settings button, the status badge…), while keeping
    /// every icon as close as possible — in the least-squares sense — to its true bearing.
    ///
    /// Obstacles are cut out of the loop, leaving a shorter "free" loop. On that loop the
    /// classic cluster-merging algorithm gives the optimal spacing exactly (no iteration, so
    /// a dozen aircraft stacked toward the same airport still fan out cleanly). Positions are
    /// then mapped back onto the real track.
    func spread(_ desired: [CGFloat], minGap: CGFloat, obstacles: [Obstacle] = []) -> [CGFloat] {
        let n = desired.count
        guard n > 0 else { return [] }

        let blocked = blockedIntervals(obstacles, padding: minGap / 2)
        let blockedLength = blocked.reduce(CGFloat(0)) { $0 + ($1.upperBound - $1.lowerBound) }
        let freeLength = length - blockedLength
        guard freeLength > 1 else { return desired.map(wrap) }

        func toFree(_ s: CGFloat) -> CGFloat {
            let s = wrap(s)
            var removed: CGFloat = 0
            for interval in blocked {
                if s >= interval.upperBound {
                    removed += interval.upperBound - interval.lowerBound
                } else if s > interval.lowerBound {
                    // Inside an obstacle: snap to its edge (both edges are the same free point).
                    return interval.lowerBound - removed
                }
            }
            return s - removed
        }

        func toTrack(_ r: CGFloat) -> CGFloat {
            var s = r
            for interval in blocked where s > interval.lowerBound {
                s += interval.upperBound - interval.lowerBound
            }
            return wrap(s)
        }

        let gap = min(minGap, freeLength / CGFloat(n))
        let spaced = Self.spreadOnLoop(desired.map(toFree), loopLength: freeLength, gap: gap)
        return spaced.map(toTrack)
    }

    /// Obstacle zones as sorted, merged, non-wrapping intervals of arc length.
    private func blockedIntervals(_ obstacles: [Obstacle], padding: CGFloat) -> [ClosedRange<CGFloat>] {
        var pieces: [ClosedRange<CGFloat>] = []
        for o in obstacles {
            let half = min(length / 2, o.halfWidth + padding)
            let start = wrap(o.s - half)
            let end = start + 2 * half
            if end <= length {
                pieces.append(start...end)
            } else {
                pieces.append(start...length)
                pieces.append(0...(end - length))
            }
        }
        pieces.sort { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<CGFloat>] = []
        for piece in pieces {
            if let last = merged.last, piece.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, piece.upperBound)
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// Optimal 1-D spacing on a loop: cut the loop at the widest empty stretch, merge
    /// overlapping runs into blocks centred on their members' mean, then wrap back.
    static func spreadOnLoop(_ x: [CGFloat], loopLength: CGFloat, gap: CGFloat) -> [CGFloat] {
        let n = x.count
        guard n > 1 else { return x }
        func wrapLoop(_ v: CGFloat) -> CGFloat {
            let r = v.truncatingRemainder(dividingBy: loopLength)
            return r < 0 ? r + loopLength : r
        }
        let order = (0..<n).sorted { wrapLoop(x[$0]) < wrapLoop(x[$1]) }
        let sorted = order.map { wrapLoop(x[$0]) }

        // Cut after the widest gap so the seam falls in empty sky.
        var cutAfter = n - 1
        var widest = sorted[0] + loopLength - sorted[n - 1]
        for k in 0..<(n - 1) where sorted[k + 1] - sorted[k] > widest {
            widest = sorted[k + 1] - sorted[k]
            cutAfter = k
        }
        var sequence: [CGFloat] = []
        var indices: [Int] = []
        for m in 0..<n {
            let k = (cutAfter + 1 + m) % n
            sequence.append(cutAfter != n - 1 && k <= cutAfter ? sorted[k] + loopLength : sorted[k])
            indices.append(order[k])
        }

        // Pool-adjacent-violators style block merging. A block stores the sum of
        // (x_m - gap * offset_m); its optimal first position is that sum / count.
        struct Block { var start: Int; var count: Int; var sum: CGFloat }
        var blocks: [Block] = []
        for i in 0..<n {
            blocks.append(Block(start: i, count: 1, sum: sequence[i]))
            while blocks.count >= 2 {
                let b = blocks[blocks.count - 1], a = blocks[blocks.count - 2]
                let aLast = a.sum / CGFloat(a.count) + gap * CGFloat(a.count - 1)
                let bFirst = b.sum / CGFloat(b.count)
                guard bFirst - aLast < gap else { break }
                blocks.removeLast(2)
                blocks.append(Block(start: a.start, count: a.count + b.count,
                                    sum: a.sum + b.sum - gap * CGFloat(a.count * b.count)))
            }
        }
        var positions = [CGFloat](repeating: 0, count: n)
        for block in blocks {
            let first = block.sum / CGFloat(block.count)
            for m in 0..<block.count {
                positions[block.start + m] = first + gap * CGFloat(m)
            }
        }
        // If the ends now collide across the seam, treat the whole sky as one evenly spaced block.
        if positions[0] + loopLength - positions[n - 1] < gap - 0.001 {
            let total = (0..<n).reduce(CGFloat(0)) { $0 + sequence[$1] - gap * CGFloat($1) }
            let first = total / CGFloat(n)
            for m in 0..<n { positions[m] = first + gap * CGFloat(m) }
        }

        var result = [CGFloat](repeating: 0, count: n)
        for m in 0..<n {
            result[indices[m]] = wrapLoop(positions[m])
        }
        return result
    }

    // MARK: - Geometry

    private static func screenAngle(of p: CGPoint, from c: CGPoint) -> Double {
        GeoMath.normalize(atan2(Double(p.x - c.x), Double(c.y - p.y)).degrees)
    }

    private static func point(at sIn: CGFloat, rect: CGRect, r: CGFloat, length: CGFloat) -> CGPoint {
        var s = sIn.truncatingRemainder(dividingBy: length)
        if s < 0 { s += length }
        let w = rect.width, h = rect.height
        let quarter = CGFloat.pi / 2 * r

        // 1. top edge, centre → right
        let topHalf = w / 2 - r
        if s <= topHalf { return CGPoint(x: rect.midX + s, y: rect.minY) }
        s -= topHalf
        // 2. top-right corner
        if s <= quarter { return arc(CGPoint(x: rect.maxX - r, y: rect.minY + r), r, -.pi / 2 + s / max(r, 0.0001)) }
        s -= quarter
        // 3. right edge
        let side = h - 2 * r
        if s <= side { return CGPoint(x: rect.maxX, y: rect.minY + r + s) }
        s -= side
        // 4. bottom-right corner
        if s <= quarter { return arc(CGPoint(x: rect.maxX - r, y: rect.maxY - r), r, s / max(r, 0.0001)) }
        s -= quarter
        // 5. bottom edge
        let bottom = w - 2 * r
        if s <= bottom { return CGPoint(x: rect.maxX - r - s, y: rect.maxY) }
        s -= bottom
        // 6. bottom-left corner
        if s <= quarter { return arc(CGPoint(x: rect.minX + r, y: rect.maxY - r), r, .pi / 2 + s / max(r, 0.0001)) }
        s -= quarter
        // 7. left edge
        if s <= side { return CGPoint(x: rect.minX, y: rect.maxY - r - s) }
        s -= side
        // 8. top-left corner
        if s <= quarter { return arc(CGPoint(x: rect.minX + r, y: rect.minY + r), r, .pi + s / max(r, 0.0001)) }
        s -= quarter
        // 9. top edge, left → centre
        return CGPoint(x: rect.minX + r + s, y: rect.minY)
    }

    private static func arc(_ c: CGPoint, _ r: CGFloat, _ theta: CGFloat) -> CGPoint {
        CGPoint(x: c.x + r * cos(theta), y: c.y + r * sin(theta))
    }

    static func == (lhs: PerimeterTrack, rhs: PerimeterTrack) -> Bool {
        lhs.rect == rhs.rect && lhs.cornerRadius == rhs.cornerRadius
    }
}

// MARK: - Planning icon positions

struct PerimeterPlacement: Identifiable {
    let contact: RadarContact
    let point: CGPoint
    let labelPoint: CGPoint
    /// Track relative to the top of the screen.
    let screenTrack: Double
    /// Unit vector from the icon toward the centre of the screen. New aircraft float in
    /// along it from beyond the edge, and leave the same way.
    var inward = CGVector(dx: 0, dy: -1)

    var id: String { contact.id }
}

enum PerimeterPlanner {
    static let iconSpacing: CGFloat = 40
    static let labelOffset: CGFloat = 30
    static let maxIcons = 32

    static func plan(contacts: [RadarContact], heading: Double, track: PerimeterTrack, obstacles: [PerimeterTrack.Obstacle], scale: CGFloat = 1, maxIcons: Int = maxIcons) -> [PerimeterPlacement] {
        let shown = Array(contacts.prefix(maxIcons))
        let desired = shown.map { track.arcLength(forScreenAngle: $0.bearing - heading) }
        let spread = track.spread(desired, minGap: iconSpacing * scale, obstacles: obstacles)
        let labelOffset = Self.labelOffset * scale
        return zip(shown, spread).map { contact, s in
            let point = track.point(at: s)
            let inward = track.inwardDirection(from: point)
            let label = CGPoint(x: point.x + inward.dx * labelOffset, y: point.y + inward.dy * labelOffset)
            return PerimeterPlacement(contact: contact, point: point, labelPoint: label,
                                      screenTrack: contact.flight.track - heading, inward: inward)
        }
    }
}
