//
//  TVLink.swift
//  WhatTheFlight
//
//  iPhone → Apple TV hand-off over the local network (MultipeerConnectivity, Bonjour
//  service `_wtf-radar._tcp`). The TV advertises itself with a short pairing code; the
//  iPhone finds it, connects, and sends where the TV is and which way it faces. The TV
//  answers with an acknowledgement so the phone can confirm success.
//

import Foundation
@preconcurrency import MultipeerConnectivity
import Observation

enum TVLink {
    static let serviceType = "wtf-radar"

    struct Payload: Codable, Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        /// Compass direction from the viewer toward the TV. `nil` = location only.
        var facingDegrees: Double?
        var senderName: String
        var sentAt: Date
    }

    struct Ack: Codable, Equatable, Sendable {
        var ok: Bool
        var message: String
    }

    static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Apple TV side

#if os(tvOS)
@MainActor
@Observable
final class TVLinkReceiver: NSObject {
    enum Status: Equatable {
        case idle
        case listening
        case connected
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastPayload: TVLink.Payload?
    private(set) var lastReceivedAt: Date?
    /// Shown on the TV so you can pick the right Apple TV on the phone.
    let code: String

    @ObservationIgnored var onPayload: ((TVLink.Payload) -> Void)?
    @ObservationIgnored private let peer: MCPeerID
    @ObservationIgnored private let session: MCSession
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?

    override init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: "wtf.tvLinkCode"), saved.count == 4 {
            code = saved
        } else {
            code = String(format: "%04d", Int.random(in: 1000...9999))
            defaults.set(code, forKey: "wtf.tvLinkCode")
        }
        peer = MCPeerID(displayName: "Apple TV")
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func start() {
        guard advertiser == nil else { return }
        let advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: ["code": code], serviceType: TVLink.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        status = .listening
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        session.disconnect()
        status = .idle
    }

    /// After a failure (Local Network refused, then allowed in tvOS Settings): advertise afresh.
    func retry() {
        stop()
        start()
    }

    /// Forgets the last hand-off (the "Received 8:41 PM" line), e.g. when the location is cleared.
    func forgetLastPayload() {
        lastPayload = nil
        lastReceivedAt = nil
    }

    fileprivate func handle(_ payload: TVLink.Payload, from peerID: MCPeerID) {
        lastPayload = payload
        lastReceivedAt = Date()
        onPayload?(payload)
        let ack = TVLink.Ack(ok: true, message: "Apple TV updated")
        if let data = TVLink.encode(ack) {
            try? session.send(data, toPeers: [peerID], with: .reliable)
        }
    }

    fileprivate func update(connected: Bool) {
        status = connected ? .connected : (advertiser == nil ? .idle : .listening)
    }

    fileprivate func fail(_ message: String) {
        Log.link.error("Apple TV link: \(message, privacy: .public)")
        // Drop the dead advertiser, or `start()` would think it's still listening.
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        status = .failed(message)
    }

    fileprivate var sessionForInvites: MCSession { session }
}

extension TVLinkReceiver: MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { invitationHandler(true, self.sessionForInvites) }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        let message = error.localizedDescription
        DispatchQueue.main.async { MainActor.assumeIsolated { self.fail(message) } }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let connected = !session.connectedPeers.isEmpty
        DispatchQueue.main.async { MainActor.assumeIsolated { self.update(connected: connected) } }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = TVLink.decode(TVLink.Payload.self, from: data) else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.handle(payload, from: peerID) } }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif

// MARK: - iPhone side

#if os(iOS)
import UIKit

@MainActor
@Observable
final class TVLinkSender: NSObject {
    struct FoundTV: Identifiable, Hashable {
        let peer: MCPeerID
        let code: String
        var id: String { "\(peer.hash)-\(code)" }
        var title: String { "\(peer.displayName) · \(code)" }
    }

    enum Phase: Equatable {
        case idle
        case searching
        case sending
        case sent(Date)
        case failed(String)
    }

    private(set) var tvs: [FoundTV] = []
    private(set) var phase: Phase = .idle

    @ObservationIgnored private let peer = MCPeerID(displayName: UIDevice.current.name)
    @ObservationIgnored private let session: MCSession
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    @ObservationIgnored private var connected: Set<MCPeerID> = []
    @ObservationIgnored private var ackReceived = false

    override init() {
        session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func startBrowsing() {
        guard browser == nil else { return }
        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: TVLink.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        if case .idle = phase { phase = .searching }
    }

    func stop() {
        browser?.stopBrowsingForPeers()
        browser = nil
        session.disconnect()
        connected.removeAll()
        tvs.removeAll()
        phase = .idle
    }

    /// Connects (if needed), sends the payload, and waits for the TV to confirm. Cancelling
    /// the calling task (the screen went away) stops it without touching `phase`.
    func send(_ payload: TVLink.Payload, to tv: FoundTV) async {
        guard let data = TVLink.encode(payload) else { return }
        phase = .sending
        ackReceived = false

        if !connected.contains(tv.peer) {
            browser?.invitePeer(tv.peer, to: session, withContext: nil, timeout: 12)
            let reached = await waitUntil(seconds: 12, { self.connected.contains(tv.peer) })
            guard !Task.isCancelled else { return }
            guard reached else {
                Log.link.notice("Couldn't connect to the Apple TV")
                phase = .failed("Couldn't reach the Apple TV. Make sure What The Flight? is open on it.")
                return
            }
        }
        do {
            try session.send(data, toPeers: [tv.peer], with: .reliable)
        } catch {
            Log.link.error("Couldn't send to the Apple TV: \(error.localizedDescription, privacy: .public)")
            phase = .failed(error.localizedDescription)
            return
        }
        let confirmed = await waitUntil(seconds: 8, { self.ackReceived })
        guard !Task.isCancelled else { return }
        if !confirmed { Log.link.notice("The Apple TV didn't confirm the hand-off") }
        phase = confirmed ? .sent(Date()) : .failed("The Apple TV didn't confirm. Try again.")
    }

    /// Polls `condition` until it holds, the time is up, or the task is cancelled.
    private func waitUntil(seconds: Double, _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            // A cancelled sleep returns at once: stop rather than spin until the deadline.
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return false }
        }
        return condition()
    }

    fileprivate func found(_ peerID: MCPeerID, code: String) {
        let tv = FoundTV(peer: peerID, code: code)
        if !tvs.contains(tv) { tvs.append(tv) }
    }

    fileprivate func lost(_ peerID: MCPeerID) {
        tvs.removeAll { $0.peer == peerID }
    }

    fileprivate func setConnected(_ peerID: MCPeerID, _ isConnected: Bool) {
        if isConnected { connected.insert(peerID) } else { connected.remove(peerID) }
    }

    fileprivate func receivedAck() {
        ackReceived = true
    }
}

extension TVLinkSender: MCNearbyServiceBrowserDelegate, MCSessionDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let code = info?["code"] ?? "----"
        DispatchQueue.main.async { MainActor.assumeIsolated { self.found(peerID, code: code) } }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.lost(peerID) } }
    }

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let isConnected = state == .connected
        DispatchQueue.main.async { MainActor.assumeIsolated { self.setConnected(peerID, isConnected) } }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let ack = TVLink.decode(TVLink.Ack.self, from: data), ack.ok else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { self.receivedAck() } }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
#endif
