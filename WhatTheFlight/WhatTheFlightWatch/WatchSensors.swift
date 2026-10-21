//
//  WatchSensors.swift
//  WhatTheFlightWatch
//
//  GPS + compass for the wrist radar, Core Motion for Point & Find, and the Watch's
//  haptic vocabulary.
//

import Foundation
import CoreLocation
import CoreMotion
import Observation
import WatchKit
import AVFoundation
import simd

// MARK: - Location & heading

@MainActor
@Observable
final class WatchLocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    /// True heading (magnetic when true isn't known) of the watch's 12 o'clock edge, 0..<360.
    private(set) var heading: Double?
    /// True minus magnetic heading: the local declination, when both are known.
    private(set) var declination: Double?
    private(set) var headingAccuracy: Double?
    let headingAvailable = CLLocationManager.headingAvailable()

    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 40
        manager.headingFilter = 2
    }

    var isAuthorized: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
        if headingAvailable { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }
}

extension WatchLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        Task { @MainActor in self.location = latest }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let magnetic = newHeading.magneticHeading
        let trueHeading = newHeading.trueHeading
        let accuracy = newHeading.headingAccuracy
        Task { @MainActor in
            self.heading = trueHeading >= 0 ? trueHeading : magnetic
            self.declination = trueHeading >= 0 ? GeoMath.shortestDelta(from: magnetic, to: trueHeading) : nil
            self.headingAccuracy = accuracy
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

// MARK: - Point & Find

/// Where the wearer is aiming, as an east-north-up unit vector: the forearm (Point) or the
/// Watch's top edge (Aim).
@MainActor
@Observable
final class WristPointer {
    enum Mode: Equatable {
        case trueNorth, magneticNorth, compassOnly, unavailable

        var label: String {
            switch self {
            case .trueNorth: return "True north"
            case .magneticNorth: return "Magnetic north"
            case .compassOnly: return "Compass + tilt"
            case .unavailable: return "No motion sensors"
            }
        }
    }

    private(set) var pointing: SIMD3<Double>?
    private(set) var mode: Mode = .unavailable
    /// How the arm-out screen should be turned: its top toward whichever edge is highest.
    private(set) var screenTurn: WristPointing.ScreenTurn = .clockwise

    /// Point (the forearm) or Aim (the top edge). Aim keeps the screen upright.
    @ObservationIgnored var style: WristPointing.AimStyle = .point
    /// +1 / -1: which end of the watch's x axis faces the hand.
    @ObservationIgnored var axisSign: Double = 1
    /// +1 / -1: whether the screen's axes match Core Motion's (see `WristPointing.displaySign`).
    @ObservationIgnored var displaySign: Double = 1
    /// For the compass-only fallback: heading of the watch's 12 o'clock edge.
    @ObservationIgnored var heading: () -> Double? = { nil }
    /// True − magnetic, to correct a magnetic-north attitude.
    @ObservationIgnored var declination: () -> Double? = { nil }

    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var axesAreRows = true
    @ObservationIgnored private var conventionChecked = false
    @ObservationIgnored private var gravity: SIMD3<Double>?
    /// A new screen turn has to hold for a moment before the screen follows it.
    @ObservationIgnored private var pendingTurn: (turn: WristPointing.ScreenTurn, since: Date)?

    func start() {
        #if DEBUG
        // `-wtf.debugTurn 0|90|180|270`: force the arm-out screen's turn (simulator).
        if UserDefaults.standard.object(forKey: "wtf.debugTurn") != nil,
           let turn = WristPointing.ScreenTurn(rawValue: UserDefaults.standard.integer(forKey: "wtf.debugTurn")) {
            screenTurn = turn
        }
        // `-wtf.debugPointing 120,30`: pretend the arm points there (simulator, screenshots).
        if let spec = UserDefaults.standard.string(forKey: "wtf.debugPointing") {
            let parts = spec.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2 {
                mode = .trueNorth
                pointing = SkyProjector.direction(azimuth: parts[0], elevation: parts[1])
                return
            }
        }
        #endif
        guard motion.isDeviceMotionAvailable else {
            mode = .unavailable
            return
        }
        guard !motion.isDeviceMotionActive else { return }
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        if frames.contains(.xTrueNorthZVertical) {
            frame = .xTrueNorthZVertical
            mode = .trueNorth
        } else if frames.contains(.xMagneticNorthZVertical) {
            frame = .xMagneticNorthZVertical
            mode = .magneticNorth
        } else {
            frame = .xArbitraryCorrectedZVertical
            mode = .compassOnly
        }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated { self?.process(data) }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        pointing = nil
        gravity = nil
        pendingTurn = nil
    }

    private func updateScreenTurn(gravity raw: SIMD3<Double>) {
        let smoothed = gravity.map { $0 + (raw - $0) * 0.2 } ?? raw
        gravity = smoothed
        let candidate = WristPointing.screenTurn(gravity: smoothed, displaySign: displaySign, current: screenTurn)
        guard candidate != screenTurn else {
            pendingTurn = nil
            return
        }
        if let pending = pendingTurn, pending.turn == candidate {
            if Date().timeIntervalSince(pending.since) >= 0.35 {
                screenTurn = candidate
                pendingTurn = nil
            }
        } else {
            pendingTurn = (candidate, Date())
        }
    }

    private func process(_ data: CMDeviceMotion) {
        let g = SIMD3(data.gravity.x, data.gravity.y, data.gravity.z)
        if style == .point { updateScreenTurn(gravity: g) }
        let target: SIMD3<Double>
        switch mode {
        case .trueNorth, .magneticNorth:
            let m = data.attitude.rotationMatrix
            let rows = [SIMD3(m.m11, m.m12, m.m13), SIMD3(m.m21, m.m22, m.m23), SIMD3(m.m31, m.m32, m.m33)]
            if !conventionChecked, let rowsWin = WristPointing.axesAreRows(rows: rows, gravity: g) {
                axesAreRows = rowsWin
                conventionChecked = true
                pointing = nil
            }
            var p = style == .point
                ? WristPointing.pointing(rows: rows, axesAreRows: axesAreRows, axisSign: axisSign)
                : WristPointing.sightLine(rows: rows, axesAreRows: axesAreRows, displaySign: displaySign)
            if mode == .magneticNorth, let d = declination() { p = WristPointing.rotateAzimuth(p, by: d) }
            target = p
        case .compassOnly:
            guard let heading = heading() else { return }
            target = style == .point
                ? WristPointing.pointing(gravity: g, headingOfTop: heading, axisSign: axisSign)
                : WristPointing.sightLine(gravity: g, headingOfTop: heading, displaySign: displaySign)
        case .unavailable:
            return
        }
        // Low-pass so the arrow doesn't shimmer with every tremor.
        guard let current = pointing else { pointing = target; return }
        pointing = simd_normalize(current + (target - current) * 0.3)
    }
}

extension WristPointer {
    /// Which end of the forearm is the hand (from the wrist and crown settings), and where the
    /// compass fallback and magnetic correction come from.
    func configure(style: WristPointing.AimStyle, flipped: Bool, location: WatchLocationService) {
        self.style = style
        let device = WKInterfaceDevice.current()
        let leftWrist = device.wristLocation == .left
        axisSign = WristPointing.axisSign(leftWrist: leftWrist, crownOnRight: device.crownOrientation == .right, flipped: flipped)
        displaySign = WristPointing.displaySign(leftWrist: leftWrist, axisSign: axisSign)
        // Aim reads like any other screen; Point starts with the text's top toward the hand
        // until the sensors say otherwise.
        screenTurn = style == .aim ? .upright : WristPointing.handTurn(leftWrist: leftWrist)
        heading = { [location] in location.heading }
        declination = { [location] in location.declination }
    }
}

// MARK: - Speech

/// Reads Identify's call-outs aloud, through the Watch speaker or connected headphones.
@MainActor
final class IdentifySpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private var sessionReady = false

    func say(_ text: String) {
        if !sessionReady {
            // Playback (not ambient) so a call-out isn't lost to the silent switch.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            sessionReady = true
        }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .word) }
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if sessionReady {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionReady = false
        }
    }
}

// MARK: - Haptics

enum WatchHaptics {
    static func play(_ type: WKHapticType, enabled: Bool = true) {
        guard enabled else { return }
        WKInterfaceDevice.current().play(type)
    }

    /// Overhead soon: "look up"; notable or overhead now: a full tap.
    static func play(for alert: TrafficAlert, enabled: Bool) {
        play(alert.reason == .overhead ? .directionUp : .notification, enabled: enabled)
    }
}
