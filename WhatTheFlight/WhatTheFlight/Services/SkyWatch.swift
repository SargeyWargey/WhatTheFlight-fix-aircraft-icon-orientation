//
//  SkyWatch.swift
//  WhatTheFlight
//
//  "Keep watching while my phone's locked." Starts a Live Activity (Lock Screen + Dynamic
//  Island) for the next aircraft heading your way, keeps the radar running in the
//  background through location updates, and lets overhead / notable alerts arrive as
//  notifications. Ends itself after two hours to spare the battery.
//

#if os(iOS)
import Foundation
import ActivityKit
import Observation

@MainActor
@Observable
final class SkyWatch {
    static let shared = SkyWatch()
    static let duration: TimeInterval = 2 * 3600

    private(set) var isActive = false
    private(set) var endsAt: Date?
    private(set) var problem: String?

    @ObservationIgnored weak var location: RadarLocationService?
    @ObservationIgnored private var activity: Activity<SkyWatchAttributes>?
    @ObservationIgnored private var lastState: SkyWatchAttributes.ContentState?
    @ObservationIgnored private var lastPush = Date.distantPast
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    var liveActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start(placeName: String, radiusMiles: Double, contacts: [RadarContact]) async {
        guard !isActive else { return }
        problem = nil
        guard let location, location.isAuthorized else {
            location?.requestPermission()
            problem = "Sky Watch needs location access to keep running while your phone is locked."
            return
        }
        _ = await AlertNotifier.requestAuthorization()
        location.setBackgroundTracking(true)

        let ends = Date().addingTimeInterval(Self.duration)
        if liveActivitiesEnabled {
            let attributes = SkyWatchAttributes(placeName: placeName, radiusMiles: Int(radiusMiles.rounded()), endsAt: ends)
            let state = Self.state(for: contacts)
            do {
                activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: Date().addingTimeInterval(180)))
                lastState = state
                lastPush = Date()
            } catch {
                Log.alerts.error("Couldn't start the Sky Watch Live Activity: \(error.localizedDescription, privacy: .public)")
                problem = "Live Activities are unavailable: \(error.localizedDescription)"
            }
        } else {
            problem = "Live Activities are off for What The Flight? in iOS Settings — alerts will still arrive."
        }
        isActive = true
        endsAt = ends
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.duration))
            guard !Task.isCancelled else { return }
            await self?.stop()
        }
    }

    /// Call as the radar ticks; pushes to the Live Activity when something changes.
    func update(contacts: [RadarContact]) {
        guard isActive, let activity else { return }
        let state = Self.state(for: contacts)
        let newAircraft = state.flight?.id != lastState?.flight?.id || state.inRangeCount != lastState?.inRangeCount
        guard newAircraft || Date().timeIntervalSince(lastPush) > 15 else { return }
        lastState = state
        lastPush = Date()
        Task { await activity.update(.init(state: state, staleDate: Date().addingTimeInterval(180))) }
    }

    func stop() async {
        stopTask?.cancel()
        stopTask = nil
        location?.setBackgroundTracking(false)
        for running in Activity<SkyWatchAttributes>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
        activity = nil
        lastState = nil
        isActive = false
        endsAt = nil
    }

    /// A Live Activity left over from a previous run can't be updated any more: end it.
    func endOrphanedActivities() {
        guard !isActive else { return }
        Task {
            for running in Activity<SkyWatchAttributes>.activities {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func state(for contacts: [RadarContact], now: Date = Date()) -> SkyWatchAttributes.ContentState {
        let pick = contacts.first { $0.isApproaching && $0.closestApproach.secondsFromNow < 1800 } ?? contacts.first
        let passAt = pick.flatMap { $0.isApproaching ? now.addingTimeInterval($0.closestApproach.secondsFromNow) : nil }
        return .init(flight: pick.map(SnapshotFlight.init), passAt: passAt, inRangeCount: contacts.count, updatedAt: now)
    }
}
#endif
