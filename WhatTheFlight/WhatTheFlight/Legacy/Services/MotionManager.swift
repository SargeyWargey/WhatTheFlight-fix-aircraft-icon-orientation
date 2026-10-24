// Legacy: only the macOS (and visionOS) app runs this. iOS, tvOS and watchOS run radar v2;
// see Enhancements Spec B4. Delete with the rest of Legacy/ once the Mac runs the iPad app (C11).
#if os(macOS) || os(visionOS)
//
//  MotionManager.swift
//  WhatTheFlight
//
//  Created by Kiro on 8/2/25.
//

import Foundation
import Combine

#if os(iOS)
import CoreMotion
import CoreLocation
#endif

/// Cross-platform motion manager for compass functionality
class MotionManager: NSObject, ObservableObject {
    @Published var currentHeading: Double = 0.0
    
    #if os(iOS)
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    #endif
    
    override init() {
        super.init()
        #if os(iOS)
        setupLocationManager()
        #endif
    }
    
    func startMotionUpdates() {
        #if os(iOS)
        startLocationHeading()
        #else
        // On macOS and tvOS, compass functionality is not available
        // Keep heading at 0 (North)
        currentHeading = 0.0
        #endif
    }
    
    func stopMotionUpdates() {
        #if os(iOS)
        locationManager.stopUpdatingHeading()
        #endif
    }
    
    #if os(iOS)
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    private func startLocationHeading() {
        guard CLLocationManager.headingAvailable() else {
            print("Heading not available on this device")
            return
        }
        
        locationManager.startUpdatingHeading()
    }
    #endif
}

#if os(iOS)
// MARK: - CLLocationManagerDelegate
extension MotionManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // Use magnetic heading for compass functionality
        let heading = newHeading.magneticHeading
        
        // Ensure heading is valid (negative values indicate invalid readings)
        if heading >= 0 {
            DispatchQueue.main.async {
                self.currentHeading = heading
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
}
#endif
#endif
