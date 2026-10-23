//
//  CameraZoom.swift
//  WhatTheFlight
//
//  Zoom maths for Sky View. The camera is Apple's multi-lens "virtual" device: one zoom
//  factor across the ultra-wide, wide and telephoto lenses, with iOS switching lenses
//  itself. Factor 1 is the widest lens; the label the user sees ("0.5×", "1×", "5×") is
//  the factor times the device's display multiplier. Labels stay on the aircraft at every
//  zoom because the projection uses the field of view the factor leaves on screen.
//

import Foundation

struct CameraZoom: Equatable, Sendable {
    /// Horizontal field of view of the widest lens at factor 1, in degrees.
    var baseFieldOfView: Double
    /// Display label = factor × this (0.5 on cameras whose factor 1 is the ultra-wide).
    var displayMultiplier: Double
    /// Factors where the device changes to the next lens, ascending.
    var lensSwitchFactors: [Double]
    var minFactor: Double
    var maxFactor: Double

    /// Cap on the displayed zoom: past roughly twice the longest lens it's only digital
    /// crop, and labels jitter more than the picture improves.
    static let maxDisplayZoom = 15.0

    init(baseFieldOfView: Double, displayMultiplier: Double = 1, lensSwitchFactors: [Double] = [],
         minFactor: Double = 1, maxFactor: Double = 10) {
        self.baseFieldOfView = baseFieldOfView
        self.displayMultiplier = displayMultiplier > 0 ? displayMultiplier : 1
        self.lensSwitchFactors = lensSwitchFactors.sorted()
        self.minFactor = max(1, minFactor)
        self.maxFactor = max(self.minFactor, min(maxFactor, Self.maxDisplayZoom / self.displayMultiplier))
    }

    /// Field of view left on screen at `factor`: zooming narrows the tangent, not the angle.
    func fieldOfView(at factor: Double) -> Double {
        let half = baseFieldOfView.radians / 2
        return 2 * atan(tan(half) / max(1, factor)).degrees
    }

    func displayZoom(for factor: Double) -> Double { factor * displayMultiplier }

    func factor(forDisplay zoom: Double) -> Double { clamp(zoom / displayMultiplier) }

    func clamp(_ factor: Double) -> Double { min(maxFactor, max(minFactor, factor)) }

    /// The 1× lens: the wide camera, whatever the widest lens is.
    var standardFactor: Double { clamp(1 / displayMultiplier) }

    /// Quick-pick stops, as factors: each lens, plus 2× when there's a wide gap between the
    /// main lens and the telephoto (the Camera app's 2× crop).
    var stops: [Double] {
        var stops = [minFactor] + lensSwitchFactors.filter { $0 > minFactor && $0 <= maxFactor }
        if !stops.contains(where: { abs(displayZoom(for: $0) - 1) < 0.05 }) {
            stops.append(standardFactor)
        }
        let longest = stops.map(displayZoom(for:)).max() ?? 1
        let two = factor(forDisplay: 2)
        if longest >= 3, !stops.contains(where: { abs($0 - two) < 0.05 }) { stops.append(two) }
        return Array(Set(stops.map { ($0 * 1000).rounded() / 1000 })).sorted()
    }

    /// "0.5", "1", "2", "5", "2.4" — the zoom chip text without the ×.
    static func label(_ displayZoom: Double) -> String {
        let rounded = (displayZoom * 10).rounded() / 10
        if abs(rounded - rounded.rounded()) < 0.05 { return String(Int(rounded.rounded())) }
        return String(format: "%.1f", rounded)
    }

    /// The stop nearest `factor`, for highlighting the active chip.
    func nearestStop(to factor: Double) -> Double? {
        stops.min { abs(log($0 / factor)) < abs(log($1 / factor)) }
    }
}
