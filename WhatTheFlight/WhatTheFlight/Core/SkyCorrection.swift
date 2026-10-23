//
//  SkyCorrection.swift
//  WhatTheFlight
//
//  Sky View's visual lock-on. Zoomed in, the compass is the weak link: a 7° heading error
//  is invisible at 1× but puts the label half a 5× frame away. Against open sky an aircraft
//  is a small dot that stands out from its surroundings, so the camera looks for that dot
//  near where the feed says the aircraft is (`SkyBlobDetector`). A match snaps the marker
//  onto the real aircraft (`VisualFix`), and `SkyCorrection` learns the compass offset from
//  it so every other label shifts too.
//

import Foundation
import CoreGraphics
import simd

/// A learned compass offset added to every aircraft's azimuth before projecting.
struct SkyCorrection: Equatable, Sendable {
    /// Degrees added to every azimuth (positive: things are further clockwise than the
    /// compass thinks).
    private(set) var yaw: Double = 0
    private(set) var observations = 0

    static let limit = 20.0
    /// A match further than this from the prediction is probably something else.
    static let gate = 12.0

    func azimuth(_ raw: Double) -> Double { GeoMath.normalize(raw + yaw) }

    /// Folds in one sighting of an aircraft predicted at `predicted` (already corrected) and
    /// seen at `observed`, both east-north-up. Returns false when it was rejected.
    @discardableResult
    mutating func observe(predicted: SIMD3<Double>, observed: SIMD3<Double>) -> Bool {
        let separation = acos(max(-1, min(1, simd_dot(simd_normalize(predicted), simd_normalize(observed))))).degrees
        guard separation <= Self.gate else { return false }
        let p = SkyProjector.azimuthElevation(predicted), o = SkyProjector.azimuthElevation(observed)
        // Near the zenith azimuth swings wildly for tiny movements: it says nothing about
        // the compass there, so weight by how far from straight up it is.
        guard p.elevation < 75 else { return false }
        let weight = pow(cos(p.elevation.radians), 2)
        // Quick at first, then steadier once a few sightings agree.
        let gain = (observations < 5 ? 0.45 : 0.2) * weight
        let residual = GeoMath.shortestDelta(from: p.azimuth, to: o.azimuth)
        yaw = min(Self.limit, max(-Self.limit, yaw + residual * gain))
        observations += 1
        return true
    }

    mutating func reset() { self = SkyCorrection() }
}

/// The camera found the tracked aircraft: where it really is, at a moment in time.
struct VisualFix: Equatable, Sendable {
    let flightID: String
    /// East-north-up direction to the dot.
    let direction: SIMD3<Double>
    let time: Date

    /// Fixes go stale quickly: the aircraft and the phone both move.
    static let lifetime: TimeInterval = 0.6

    func isFresh(at date: Date) -> Bool { date.timeIntervalSince(time) < Self.lifetime }
}

/// Finds a small, compact dot that stands out from the sky around it, in an 8-bit
/// luminance image (the Y plane of a camera frame).
enum SkyBlobDetector {
    struct Blob: Equatable {
        /// Centre of the dot, in image pixels.
        let point: CGPoint
        /// How far it stands out, in noise units.
        let contrast: Double
    }

    /// Samples per side of the search grid: big windows are searched coarsely, then refined.
    static let gridSize = 96
    /// More than this share of the window standing out means cloud edges, buildings or the
    /// horizon: no clean dot to trust.
    static let clutterShare = 0.06

    static func detect(luma: UnsafePointer<UInt8>, width: Int, height: Int, bytesPerRow: Int,
                       around center: CGPoint, radius: Double) -> Blob? {
        let x0 = max(0, Int(Double(center.x) - radius)), x1 = min(width - 1, Int(Double(center.x) + radius))
        let y0 = max(0, Int(Double(center.y) - radius)), y1 = min(height - 1, Int(Double(center.y) + radius))
        guard x1 - x0 >= 8, y1 - y0 >= 8 else { return nil }
        let step = max(1, Int((Double(max(x1 - x0, y1 - y0)) / Double(gridSize)).rounded(.up)))
        @inline(__always) func value(_ x: Int, _ y: Int) -> Int { Int(luma[y * bytesPerRow + x]) }

        // Robust sky level and noise: median and median absolute deviation.
        var histogram = [Int](repeating: 0, count: 256)
        var samples: [(x: Int, y: Int, v: Int)] = []
        samples.reserveCapacity((gridSize + 1) * (gridSize + 1))
        for y in stride(from: y0, through: y1, by: step) {
            for x in stride(from: x0, through: x1, by: step) {
                let v = value(x, y)
                histogram[v] += 1
                samples.append((x, y, v))
            }
        }
        let median = Self.median(histogram, count: samples.count)
        var deviations = [Int](repeating: 0, count: 256)
        for s in samples { deviations[min(255, abs(s.v - median))] += 1 }
        let sigma = max(2, 1.4826 * Double(Self.median(deviations, count: samples.count)))
        let threshold = max(6 * sigma, 18)

        var strong: [(x: Int, y: Int, d: Double)] = []
        for s in samples {
            let d = Double(s.v - median)
            if abs(d) >= threshold { strong.append((s.x, s.y, d)) }
        }
        guard !strong.isEmpty, Double(strong.count) <= Double(samples.count) * clutterShare else { return nil }

        // Prefer strong dots near the prediction.
        func score(_ s: (x: Int, y: Int, d: Double)) -> Double {
            let distance = hypot(Double(s.x) - Double(center.x), Double(s.y) - Double(center.y))
            return abs(s.d) / threshold - 0.6 * distance / radius
        }
        guard let best = strong.max(by: { score($0) < score($1) }) else { return nil }
        let clusterRadius = Double(max(step * 3, 6))
        // A second, equally strong dot well away from the first: can't tell which is ours.
        let rival = strong.contains { s in
            hypot(Double(s.x - best.x), Double(s.y - best.y)) > clusterRadius * 2 && score(s) >= score(best) * 0.85 && s.d.sign == best.d.sign
        }
        guard !rival else { return nil }

        // Refine at full resolution: weighted centroid of the pixels on the dot's side.
        let r = Int(clusterRadius)
        var sx = 0.0, sy = 0.0, sw = 0.0
        for y in max(0, best.y - r)...min(height - 1, best.y + r) {
            for x in max(0, best.x - r)...min(width - 1, best.x + r) {
                let d = Double(value(x, y) - median)
                guard d.sign == best.d.sign else { continue }
                let w = abs(d) - threshold / 2
                guard w > 0 else { continue }
                sx += Double(x) * w
                sy += Double(y) * w
                sw += w
            }
        }
        guard sw > 0 else { return nil }
        return Blob(point: CGPoint(x: sx / sw, y: sy / sw), contrast: abs(best.d) / sigma)
    }

    private static func median(_ histogram: [Int], count: Int) -> Int {
        var seen = 0
        for (value, n) in histogram.enumerated() {
            seen += n
            if seen * 2 >= count { return value }
        }
        return 0
    }
}
