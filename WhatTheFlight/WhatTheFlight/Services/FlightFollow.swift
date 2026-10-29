//
//  FlightFollow.swift
//  WhatTheFlight
//
//  Starts, updates and ends the "Follow on Lock Screen" Live Activity
//  (`FlightFollowAttributes`). Following pins the aircraft, so the radar keeps looking it up
//  worldwide however far it flies; each feed update refreshes the activity (at most every
//  20 s), and it ends itself once the aircraft lands or after it was due.
//

#if os(iOS)
import Foundation
import ActivityKit
import Observation

@MainActor
@Observable
final class FlightFollow {
    static let shared = FlightFollow()

    /// The flight on the Lock Screen, if any.
    private(set) var followingID: String?
    private(set) var problem: String?

    @ObservationIgnored private var activity: Activity<FlightFollowAttributes>?
    @ObservationIgnored private var registration: String?
    @ObservationIgnored private var callsign: String?
    @ObservationIgnored private var lastPush = Date.distantPast
    @ObservationIgnored private var lastSeen = Date()

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func isFollowing(_ flight: Flight) -> Bool {
        guard followingID != nil else { return false }
        if followingID == flight.id { return true }
        if let registration, flight.registration == registration { return true }
        return false
    }

    /// Puts this flight on the Lock Screen, replacing any other.
    func start(_ contact: RadarContact, model: RadarModel) async {
        await stop()
        problem = nil
        guard isAvailable else {
            problem = "Live Activities are off for What The Flight? in iOS Settings."
            return
        }
        let f = contact.flight
        if !model.isPinned(f.id) { model.pin(f) }
        let attributes = FlightFollowAttributes(
            flightID: f.id, identifier: f.displayIdentifier, operatorName: contact.profile.operatorInfo.compact,
            originIATA: f.originIATA, originCity: f.origin?.city, destinationIATA: f.destinationIATA, destinationCity: f.destination?.city,
            typeName: contact.profile.typeName ?? f.typeCode, silhouette: contact.profile.silhouette)
        let state = Self.state(for: contact)
        do {
            activity = try Activity.request(attributes: attributes, content: .init(state: state, staleDate: Self.staleDate(state)))
            followingID = f.id
            registration = f.registration
            callsign = f.callsign
            lastPush = Date()
            lastSeen = Date()
        } catch {
            Log.alerts.error("Couldn't start following: \(error.localizedDescription, privacy: .public)")
            problem = "Couldn't start the Live Activity: \(error.localizedDescription)"
        }
    }

    /// Call when the feed updates.
    func update(from model: RadarModel) {
        guard let activity, let id = followingID else { return }
        let contact = model.contact(id: id)
            ?? model.allContacts.first { c in registration.map { c.flight.registration == $0 } ?? (c.flight.callsign == callsign) }
        if let contact {
            if contact.id != id { followingID = contact.id }
            lastSeen = Date()
            guard Date().timeIntervalSince(lastPush) > 20 else { return }
            lastPush = Date()
            let state = Self.state(for: contact)
            Task { await activity.update(.init(state: state, staleDate: Self.staleDate(state))) }
            return
        }
        // Gone from the feed: on the ground at the end of its flight, or out of coverage.
        let pin = model.pins.first { $0.flightID == id || ($0.registration != nil && $0.registration == registration) }
        if let pin, case .onGround = model.state(of: pin) {
            Task { await finish(landed: true) }
        } else if Date().timeIntervalSince(lastSeen) > 45 * 60 {
            Task { await finish(landed: false) }
        }
    }

    func stop() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        clear()
    }

    private func finish(landed: Bool) async {
        guard let activity else { return }
        var state = activity.content.state
        state.hasLanded = landed
        state.phase = landed ? "Landed" : "Out of coverage"
        state.updatedAt = Date()
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(30 * 60)))
        clear()
    }

    private func clear() {
        activity = nil
        followingID = nil
        registration = nil
        callsign = nil
    }

    static func state(for contact: RadarContact) -> FlightFollowAttributes.ContentState {
        let f = contact.flight
        let progress = RouteProgress(flight: f, position: contact.coordinate)
        let mph = Double(f.groundSpeedKnots) * GeoMath.milesPerKnotHour
        let now = Date()
        let arrives = progress?.remainingSeconds.map { now.addingTimeInterval($0) }
        let departed: Date? = progress.flatMap { p in mph > 30 ? now.addingTimeInterval(-p.flownMiles / mph * 3600) : nil }
        return .init(altitudeFeet: contact.altitudeFeet, speedKnots: f.groundSpeedKnots,
                     remainingMiles: progress?.remainingMiles, departedAt: departed, arrivesAt: arrives,
                     phase: contact.phase?.text, distanceFromYouMiles: contact.distanceMiles,
                     hasLanded: f.isOnGround, updatedAt: now)
    }

    /// Past its arrival, an untouched activity reads as out of date.
    private static func staleDate(_ state: FlightFollowAttributes.ContentState) -> Date {
        (state.arrivesAt ?? Date().addingTimeInterval(3600)).addingTimeInterval(20 * 60)
    }
}
#endif
