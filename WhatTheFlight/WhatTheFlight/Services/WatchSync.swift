//
//  WatchSync.swift
//  WhatTheFlight
//
//  iPhone ↔ Apple Watch over WatchConnectivity. The iPhone shares where its radar watches
//  from (for the Watch's "iPhone's spot" mode) and the preferences both should agree on;
//  the Watch can ask the iPhone to start Sky Watch. The Watch keeps its own radius.
//

import Foundation
import CoreLocation
#if os(iOS) || os(watchOS)
import WatchConnectivity
import Observation
#endif

enum WatchSync {
    /// What the iPhone tells the Watch. Sent as application context (latest wins).
    struct Context: Codable, Equatable, Sendable {
        static let currentVersion = 1

        var v = Context.currentVersion
        var latitude: Double?
        var longitude: Double?
        var placeName: String?
        var showHelicopters: Bool
        var overheadAlerts: Bool
        var overheadAlertMiles: Double
        var notableAlerts: Bool
        var sentAt: Date

        var observer: CLLocationCoordinate2D? {
            guard let latitude, let longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        /// Same content, ignoring when it was sent.
        func matches(_ other: Context?) -> Bool {
            guard var other else { return false }
            other.sentAt = sentAt
            return other == self
        }
    }

    /// The iPhone's answer to "start Sky Watch".
    struct Reply: Codable, Equatable, Sendable {
        var ok: Bool
        var message: String
    }

    /// Handoff from the Watch's flight details to the iPhone's.
    static let handoffActivityType = "SargeyWargey.WhatTheFlight.flight"
    static let handoffFlightKey = "flightID"

    static let contextKey = "wtf.context"
    static let requestKey = "wtf.request"
    static let replyKey = "wtf.reply"
    static let startSkyWatch = "startSkyWatch"

    static func encode(_ context: Context) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(context) else { return [:] }
        return [contextKey: data]
    }

    /// Nil for anything unreadable or from a newer, incompatible version.
    static func decodeContext(_ dictionary: [String: Any]) -> Context? {
        guard let data = dictionary[contextKey] as? Data,
              let context = try? JSONDecoder().decode(Context.self, from: data),
              context.v <= Context.currentVersion else { return nil }
        return context
    }

    static func encode(_ reply: Reply) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(reply) else { return [:] }
        return [replyKey: data]
    }

    static func decodeReply(_ dictionary: [String: Any]) -> Reply? {
        (dictionary[replyKey] as? Data).flatMap { try? JSONDecoder().decode(Reply.self, from: $0) }
    }
}

// MARK: - iPhone side

#if os(iOS)
@MainActor
@Observable
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    /// A Watch is paired and has WhatTheFlight installed.
    private(set) var isWatchAppInstalled = false

    /// Handles "start Sky Watch" from the Watch.
    @ObservationIgnored var onStartSkyWatch: (() async -> WatchSync.Reply)?
    @ObservationIgnored private var lastSent: WatchSync.Context?
    @ObservationIgnored private var pending: WatchSync.Context?

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Shares the iPhone's spot and preferences, if anything changed.
    func send(_ context: WatchSync.Context) {
        guard WCSession.isSupported() else { return }
        guard !context.matches(lastSent) else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = context
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        do {
            try session.updateApplicationContext(WatchSync.encode(context))
            lastSent = context
        } catch {
            pending = context
        }
    }

    private func sessionReady(_ session: WCSession) {
        isWatchAppInstalled = session.isPaired && session.isWatchAppInstalled
        if let pending {
            self.pending = nil
            send(pending)
        }
    }

    private func handle(_ message: [String: Any]) async -> [String: Any] {
        guard message[WatchSync.requestKey] as? String == WatchSync.startSkyWatch, let onStartSkyWatch else {
            return WatchSync.encode(WatchSync.Reply(ok: false, message: "Your iPhone didn't understand that. Update What The Flight? on both devices."))
        }
        return WatchSync.encode(await onStartSkyWatch())
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.sessionReady(session) }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.sessionReady(session) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switched to a different Watch: start talking to the new one.
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let request = message[WatchSync.requestKey] as? String
        Task { @MainActor in
            replyHandler(await self.handle([WatchSync.requestKey: request as Any]))
        }
    }
}
#endif

// MARK: - Watch side

#if os(watchOS)
@MainActor
@Observable
final class WatchPhoneLink: NSObject {
    static let shared = WatchPhoneLink()

    /// The latest context from the iPhone (also persisted by whoever handles `onContext`).
    private(set) var context: WatchSync.Context?
    @ObservationIgnored var onContext: ((WatchSync.Context) -> Void)?

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone to start Sky Watch. Returns what to tell the user.
    func requestSkyWatch() async -> WatchSync.Reply {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            return WatchSync.Reply(ok: false, message: "Can't reach your iPhone. Open What The Flight? on it and start Sky Watch there.")
        }
        return await withCheckedContinuation { continuation in
            session.sendMessage([WatchSync.requestKey: WatchSync.startSkyWatch], replyHandler: { reply in
                continuation.resume(returning: WatchSync.decodeReply(reply)
                    ?? WatchSync.Reply(ok: false, message: "Your iPhone sent an answer this Watch couldn't read."))
            }, errorHandler: { _ in
                continuation.resume(returning: WatchSync.Reply(ok: false, message: "Your iPhone didn't answer. Open What The Flight? on it and start Sky Watch there."))
            })
        }
    }

    private func receive(_ dictionary: [String: Any]) {
        guard let context = WatchSync.decodeContext(dictionary) else { return }
        self.context = context
        onContext?(context)
    }
}

extension WatchPhoneLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let latest = session.receivedApplicationContext
        Task { @MainActor in self.receive(latest) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.receive(applicationContext) }
    }
}
#endif
