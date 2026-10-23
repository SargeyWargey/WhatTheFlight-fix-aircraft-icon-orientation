//
//  SkyProjector.swift
//  WhatTheFlight
//
//  Pinhole camera maths for Sky View: turns an aircraft's azimuth / elevation into a point
//  on screen, given which way the camera looks. World vectors are east-north-up.
//

import Foundation
import CoreGraphics
import simd

struct SkyProjector: Equatable, Sendable {
    /// Unit vectors, east-north-up, for the screen's right and up edges and the view direction.
    var right: SIMD3<Double>
    var up: SIMD3<Double>
    var forward: SIMD3<Double>
    /// Focal length in points: the on-screen distance at which 45° off-axis lands.
    var focalLength: Double
    var size: CGSize

    /// A camera pointed at `azimuth` (0 = north, clockwise) and tilted `pitch` degrees above
    /// the horizon, with no roll. Used when there are no motion sensors (simulator, drag mode).
    init(azimuth: Double, pitch: Double, focalLength: Double, size: CGSize) {
        let az = azimuth.radians, el = pitch.radians
        forward = SIMD3(cos(el) * sin(az), cos(el) * cos(az), sin(el))
        right = SIMD3(cos(az), -sin(az), 0)
        up = simd_cross(right, forward)
        self.focalLength = focalLength
        self.size = size
    }

    init(right: SIMD3<Double>, up: SIMD3<Double>, forward: SIMD3<Double>, focalLength: Double, size: CGSize) {
        self.right = simd_normalize(right)
        self.up = simd_normalize(up)
        self.forward = simd_normalize(forward)
        self.focalLength = focalLength
        self.size = size
    }

    /// Focal length that shows `degrees` across the screen's shorter side.
    static func focalLength(fieldOfView degrees: Double, across points: Double) -> Double {
        (points / 2) / tan(degrees.radians / 2)
    }

    /// The same camera seen through a different frame: a captured photo or video frame whose
    /// long side spans `longSideFieldOfView` degrees (the full sensor, uncropped).
    func reframed(to size: CGSize, longSideFieldOfView: Double) -> SkyProjector {
        var copy = self
        copy.size = size
        copy.focalLength = Self.focalLength(fieldOfView: longSideFieldOfView, across: Double(max(size.width, size.height)))
        return copy
    }

    /// East-north-up unit vector for a direction in the sky.
    static func direction(azimuth: Double, elevation: Double) -> SIMD3<Double> {
        let az = azimuth.radians, el = elevation.radians
        return SIMD3(cos(el) * sin(az), cos(el) * cos(az), sin(el))
    }

    struct Projection: Equatable {
        /// Screen position (may be off-screen).
        let point: CGPoint
        let isInFront: Bool
        /// Screen-space direction from the centre toward the target, for edge arrows (radians,
        /// 0 = up, clockwise). Valid even when the target is behind the camera.
        let screenAngle: Double

        func isOnScreen(_ size: CGSize, margin: CGFloat = 0) -> Bool {
            isInFront && CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin).contains(point)
        }
    }

    func project(azimuth: Double, elevation: Double) -> Projection {
        project(Self.direction(azimuth: azimuth, elevation: elevation))
    }

    func project(_ target: SIMD3<Double>) -> Projection {
        let x = simd_dot(target, right)
        let y = simd_dot(target, up)
        let z = simd_dot(target, forward)
        let angle = atan2(x, y)
        let cx = size.width / 2, cy = size.height / 2
        guard z > 0.01 else {
            // Behind: park it far out along its direction so edge arrows still point the right way.
            let far = Double(max(size.width, size.height)) * 4
            return Projection(point: CGPoint(x: cx + far * sin(angle), y: cy - far * cos(angle)), isInFront: false, screenAngle: angle)
        }
        let point = CGPoint(x: cx + focalLength * x / z, y: cy - focalLength * y / z)
        return Projection(point: point, isInFront: true, screenAngle: angle)
    }

    /// The sky direction behind a screen point (the inverse of `project`).
    func unproject(_ point: CGPoint) -> SIMD3<Double> {
        let x = (Double(point.x) - Double(size.width) / 2) / focalLength
        let y = (Double(size.height) / 2 - Double(point.y)) / focalLength
        return simd_normalize(forward + right * x + up * y)
    }

    /// Compass azimuth and elevation of an east-north-up direction.
    static func azimuthElevation(_ v: SIMD3<Double>) -> (azimuth: Double, elevation: Double) {
        (GeoMath.normalize(atan2(v.x, v.y).degrees), asin(max(-1, min(1, v.z))).degrees)
    }

    /// Where the camera is looking, as compass azimuth and elevation.
    var lookAzimuth: Double { GeoMath.normalize(atan2(forward.x, forward.y).degrees) }
    var lookElevation: Double { asin(max(-1, min(1, forward.z))).degrees }
}
