//
//  RadarLocationService.swift
//  WhatTheFlight
//
//  GPS position + compass heading in one place. The heading is "unwrapped" (it can go past
//  360 or below 0) so rotations animate the short way round instead of spinning backwards.
//

#if os(iOS)
import Foundation
import CoreLocation
import Observation
import UIKit

@MainActor
@Observable
final class RadarLocationService: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    /// Continuous true heading in degrees (not wrapped to 0..<360). `nil` until the compass reports.
    private(set) var heading: Double?
    /// Estimated compass error in degrees, when known.
    private(set) var headingAccuracy: Double?
    let headingAvailable = CLLocationManager.headingAvailable()

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var orientationObserver: NSObjectProtocol?
    @ObservationIgnored private var isRunning = false

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 40
        manager.headingFilter = 1
        manager.activityType = .other
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    /// Heading wrapped to 0..<360 (0 when no compass is available, i.e. "north up").
    var normalizedHeading: Double {
        GeoMath.normalize(heading ?? 0)
    }

    func requestPermission() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        isRunning = true
        if isAuthorized { manager.startUpdatingLocation() }
        if headingAvailable { manager.startUpdatingHeading() }
        syncHeadingOrientation()
        if orientationObserver == nil {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncHeadingOrientation() }
            }
        }
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    /// Sky Watch: keep location (and so the app) running while the phone is locked, with
    /// the system's blue location indicator showing.
    private(set) var isTrackingInBackground = false

    func setBackgroundTracking(_ enabled: Bool) {
        guard enabled != isTrackingInBackground else { return }
        isTrackingInBackground = enabled
        manager.allowsBackgroundLocationUpdates = enabled
        manager.showsBackgroundLocationIndicator = enabled
        manager.pausesLocationUpdatesAutomatically = !enabled
        // Coarser fixes are plenty in the background and much kinder to the battery.
        manager.desiredAccuracy = enabled ? kCLLocationAccuracyHundredMeters : kCLLocationAccuracyNearestTenMeters
        if enabled, isAuthorized { manager.startUpdatingLocation() }
    }

    /// The compass is relative to the top of the *interface*, so keep Core Location in sync
    /// on iPad, which rotates. iPhone is portrait-only.
    private func syncHeadingOrientation() {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            manager.headingOrientation = .portrait
            return
        }
        switch UIDevice.current.orientation {
        case .portrait: manager.headingOrientation = .portrait
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft: manager.headingOrientation = .landscapeLeft
        case .landscapeRight: manager.headingOrientation = .landscapeRight
        default: break // face up / down: keep the last interface orientation
        }
    }

    fileprivate func apply(heading newValue: Double, accuracy: Double) {
        if let current = heading {
            heading = current + GeoMath.shortestDelta(from: current, to: newValue)
        } else {
            heading = newValue
        }
        headingAccuracy = accuracy >= 0 ? accuracy : nil
    }
}

extension RadarLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if isRunning, isAuthorized { self.manager.startUpdatingLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        MainActor.assumeIsolated {
            location = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        let accuracy = newHeading.headingAccuracy
        guard value >= 0 else { return }
        MainActor.assumeIsolated {
            apply(heading: value, accuracy: accuracy)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. no fix yet) are expected; the last good fix stays in use.
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}
#endif
