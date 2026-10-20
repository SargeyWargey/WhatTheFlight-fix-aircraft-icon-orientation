//
//  SkyServices.swift
//  WhatTheFlight
//
//  Sensors behind Sky View: where the camera is looking in 3D (Core Motion attitude
//  against true north), the back camera feed and its field of view, and the "lift the phone
//  to the sky" gesture that opens Sky View from the radar.
//

#if os(iOS)
import Foundation
import AVFoundation
import CoreMotion
import Observation
import UIKit
import simd

/// The screen's right / up edges and the camera's view direction, as east-north-up vectors.
struct SkyBasis: Equatable {
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
        guard let current = basis else { basis = target; return }
        let a = 0.3
        let f = simd_normalize(current.forward + (target.forward - current.forward) * a)
        var rt = current.right + (target.right - current.right) * a
        rt = simd_normalize(rt - simd_dot(rt, f) * f)
        basis = SkyBasis(right: rt, up: simd_cross(rt, f), forward: f)
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

// MARK: - Camera

@MainActor
@Observable
final class SkyCamera {
    enum State: Equatable { case idle, starting, running, denied, unavailable }

    private(set) var state: State = .idle
    /// Horizontal field of view of the sensor's long side, in degrees.
    private(set) var fieldOfView: Double = 0
    /// Sensor frame in pixels (long side, short side).
    private(set) var sensorSize = CGSize(width: 1920, height: 1080)

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private(set) var device: AVCaptureDevice?
    @ObservationIgnored private let queue = DispatchQueue(label: "wtf.skycamera")

    func start() async {
        guard state == .idle || state == .denied else { return }
        // No camera (simulator, some iPads): don't ask for a permission we can't use.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
        default:
            state = .denied
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            state = .unavailable
            return
        }
        state = .starting
        self.device = device
        let work = CaptureWork(session: session, input: input)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                let session = work.session
                session.beginConfiguration()
                session.sessionPreset = .high
                if let input = work.input, session.canAddInput(input) { session.addInput(input) }
                session.commitConfiguration()
                session.startRunning()
                done.resume()
            }
        }
        fieldOfView = Double(device.activeFormat.videoFieldOfView)
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        sensorSize = CGSize(width: CGFloat(max(dims.width, dims.height)), height: CGFloat(min(dims.width, dims.height)))
        state = session.isRunning ? .running : .unavailable
    }

    func stop() {
        let work = CaptureWork(session: session)
        queue.async { work.session.stopRunning() }
        if state == .running || state == .starting { state = .idle }
    }

    /// Focal length in points for a preview that aspect-fills `size`.
    func focalLength(for size: CGSize) -> Double? {
        guard state == .running, fieldOfView > 1 else { return nil }
        let long = Double(sensorSize.width), short = Double(sensorSize.height)
        let viewLong = Double(max(size.width, size.height)), viewShort = Double(min(size.width, size.height))
        let fill = max(viewLong / long, viewShort / short)
        return (long / 2) / tan(fieldOfView.radians / 2) * fill
    }
}

/// Carries the capture session onto its serial queue. AVFoundation's types aren't Sendable, but
/// Apple's guidance is exactly this: configure, start and stop the session on one dedicated
/// queue (it blocks), never on the main thread. Nothing else touches it concurrently.
private struct CaptureWork: @unchecked Sendable {
    let session: AVCaptureSession
    var input: AVCaptureDeviceInput? = nil
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
