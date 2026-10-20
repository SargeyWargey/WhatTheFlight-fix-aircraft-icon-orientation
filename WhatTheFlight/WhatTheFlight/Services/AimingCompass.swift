//
//  AimingCompass.swift
//  WhatTheFlight
//
//  "Which way is the phone pointing?" — in 3D. Held upright, it's the direction the back
//  camera looks; held flat, it's the direction the top edge points. Uses Core Motion's
//  attitude against true north, smoothed over the last few samples.
//

#if os(iOS)
import Foundation
import CoreMotion
import Observation

@MainActor
@Observable
final class AimingCompass {
    /// Smoothed aim direction in degrees (0 = north, clockwise), or nil until the sensors settle.
    private(set) var heading: Double?
    /// Held up like a camera (vs. lying flat).
    private(set) var isUpright = false
    /// How steady the aim is, 0…1 (1 = rock solid).
    private(set) var steadiness: Double = 0
    private(set) var usesTrueNorth = true
    let isAvailable: Bool

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var samples: [(north: Double, east: Double)] = []
    /// Whether the device axes are the rows (default) or columns of `rotationMatrix`;
    /// confirmed at runtime against measured gravity.
    @ObservationIgnored private var axesAreRows = true
    @ObservationIgnored private var conventionChecked = false

    init() {
        isAvailable = motion.isDeviceMotionAvailable
    }

    func start() {
        guard isAvailable, !motion.isDeviceMotionActive else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame = frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        usesTrueNorth = frame == .xTrueNorthZVertical
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.process(data) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        samples.removeAll()
    }

    private func process(_ data: CMDeviceMotion) {
        let r = data.attitude.rotationMatrix
        let g = data.gravity
        checkConvention(r, gravity: g)

        // Reference frame: X = north, Y = west, Z = up.
        // Device axes expressed in that frame are the rows (or columns) of the matrix.
        func axis(_ i: Int) -> (Double, Double, Double) {
            switch (i, axesAreRows) {
            case (1, true): return (r.m21, r.m22, r.m23)
            case (2, true): return (r.m31, r.m32, r.m33)
            case (1, false): return (r.m12, r.m22, r.m32)
            default: return (r.m13, r.m23, r.m33)
            }
        }

        let upright = abs(g.z) < 0.75
        isUpright = upright
        // Upright: the back camera looks along -Z. Flat: the top edge is +Y.
        let pointing: (Double, Double, Double) = {
            if upright {
                let z = axis(2)
                return (-z.0, -z.1, -z.2)
            }
            return axis(1)
        }()
        let north = pointing.0, east = -pointing.1
        let length = hypot(north, east)
        guard length > 0.25 else { return } // pointing at the floor or ceiling

        samples.append((north / length, east / length))
        if samples.count > 15 { samples.removeFirst(samples.count - 15) }
        let n = samples.reduce(0) { $0 + $1.north } / Double(samples.count)
        let e = samples.reduce(0) { $0 + $1.east } / Double(samples.count)
        steadiness = min(1, hypot(n, e))
        heading = GeoMath.normalize(atan2(e, n).degrees)
    }

    /// Picks the matrix convention that reproduces the measured gravity, once the phone is
    /// tilted enough for the two to differ.
    private func checkConvention(_ r: CMRotationMatrix, gravity g: CMAcceleration) {
        guard !conventionChecked, abs(g.z) < 0.9 else { return }
        let rowsError = abs(-r.m13 - g.x) + abs(-r.m23 - g.y) + abs(-r.m33 - g.z)
        let colsError = abs(-r.m31 - g.x) + abs(-r.m32 - g.y) + abs(-r.m33 - g.z)
        if abs(rowsError - colsError) > 0.3 {
            axesAreRows = rowsError <= colsError
            conventionChecked = true
            samples.removeAll()
        }
    }
}
#endif
