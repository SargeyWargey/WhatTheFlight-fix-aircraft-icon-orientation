//
//  SkyServices.swift
//  WhatTheFlight
//
//  Sensors behind Sky View: where the camera is looking in 3D (Core Motion attitude
//  against true north) and the "lift the phone to the sky" gesture that opens Sky View from
//  the radar. The camera itself is `SkyCamera`.
//

#if os(iOS)
import Foundation
import AVFoundation
import CoreMotion
import Observation
import UIKit
import simd

/// The screen's right / up edges and the camera's view direction, as east-north-up vectors.
struct SkyBasis: Equatable, Sendable {
    var right: SIMD3<Double>
    var up: SIMD3<Double>
    var forward: SIMD3<Double>
}

@MainActor
@Observable
final class SkyMotion {
    private(set) var basis: SkyBasis?
    private(set) var usesTrueNorth = true
    let isAvailable: Bool
    /// Keep in sync with the interface so "right" and "up" follow the screen on iPad.
    @ObservationIgnored var interfaceOrientation: UIInterfaceOrientation = .portrait
    /// Every new basis, as it arrives (the camera's frame tracker needs it off the main actor).
    @ObservationIgnored var onBasis: ((SkyBasis) -> Void)?

    @ObservationIgnored private let motion = CMMotionManager()
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
        motion.deviceMotionUpdateInterval = 1.0 / 60
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.process(data) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        basis = nil
    }

    private func process(_ data: CMDeviceMotion) {
        let r = data.attitude.rotationMatrix
        checkConvention(r, gravity: data.gravity)

        // Device axes in the reference frame (X = north, Y = west, Z = up) → east-north-up.
        func axis(_ i: Int) -> SIMD3<Double> {
            let v: (Double, Double, Double)
            switch (i, axesAreRows) {
            case (0, true): v = (r.m11, r.m12, r.m13)
            case (1, true): v = (r.m21, r.m22, r.m23)
            case (2, true): v = (r.m31, r.m32, r.m33)
            case (0, false): v = (r.m11, r.m21, r.m31)
            case (1, false): v = (r.m12, r.m22, r.m32)
            default: v = (r.m13, r.m23, r.m33)
            }
            return SIMD3(-v.1, v.0, v.2)
        }
        let x = axis(0), y = axis(1), z = axis(2)

        let right: SIMD3<Double>, up: SIMD3<Double>
        switch interfaceOrientation {
        case .portraitUpsideDown: right = -x; up = -y
        case .landscapeLeft: right = y; up = -x
        case .landscapeRight: right = -y; up = x
        default: right = x; up = y
        }
        let target = SkyBasis(right: right, up: up, forward: -z)

        // Low-pass the raw attitude so labels don't shimmer, then re-orthonormalise.
        guard let current = basis else { basis = target; onBasis?(target); return }
        let a = 0.3
        let f = simd_normalize(current.forward + (target.forward - current.forward) * a)
        var rt = current.right + (target.right - current.right) * a
        rt = simd_normalize(rt - simd_dot(rt, f) * f)
        let smoothed = SkyBasis(right: rt, up: simd_cross(rt, f), forward: f)
        basis = smoothed
        onBasis?(smoothed)
    }

    /// Same check as `AimingCompass`: pick the matrix convention that reproduces gravity.
    private func checkConvention(_ r: CMRotationMatrix, gravity g: CMAcceleration) {
        guard !conventionChecked, abs(g.z) < 0.9 else { return }
        let rowsError = abs(-r.m13 - g.x) + abs(-r.m23 - g.y) + abs(-r.m33 - g.z)
        let colsError = abs(-r.m31 - g.x) + abs(-r.m32 - g.y) + abs(-r.m33 - g.z)
        if abs(rowsError - colsError) > 0.3 {
            axesAreRows = rowsError <= colsError
            conventionChecked = true
            basis = nil
        }
    }
}

// MARK: - Raise to look

/// Fires when the phone is lifted so the back camera points into the sky.
@MainActor
@Observable
final class RaiseToSkyDetector {
    /// Elevation of the back camera's view, in degrees (−90 = at the floor, 90 = straight up).
    private(set) var cameraElevation: Double = -90
    @ObservationIgnored var onRaise: (() -> Void)?

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var raisedSince: Date?
    @ObservationIgnored private var armed = true

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.process(data.gravity) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        raisedSince = nil
    }

    private func process(_ g: CMAcceleration) {
        // The back camera looks along −Z, so its elevation is asin(gravity.z).
        let elevation = asin(max(-1, min(1, g.z))).degrees
        cameraElevation = elevation
        if elevation < 0 { armed = true }
        guard armed, elevation > 25 else { raisedSince = nil; return }
        let start = raisedSince ?? Date()
        raisedSince = start
        if Date().timeIntervalSince(start) > 0.6 {
            armed = false
            raisedSince = nil
            onRaise?()
        }
    }
}
#endif
