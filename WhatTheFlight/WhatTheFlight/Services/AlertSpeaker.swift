//
//  AlertSpeaker.swift
//  WhatTheFlight
//
//  Reads traffic alerts aloud ("Delta Air Lines flight 1199 is approaching overhead…") with
//  the best English voice installed, ducking any other audio while it speaks. While it reads
//  an alert out, `speakingFlightID` names the aircraft so the screen can highlight it.
//

#if os(tvOS) || os(iOS)
import AVFoundation
import Observation

@MainActor
@Observable
final class AlertSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AlertSpeaker()

    /// The aircraft being talked about right now, if any.
    private(set) var speakingFlightID: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var pending = 0
    /// Which aircraft each queued utterance is about.
    @ObservationIgnored private var flights: [ObjectIdentifier: String] = [:]
    /// Activating or deactivating the audio session can block for a while, so it never runs on
    /// the main thread. A serial queue keeps activate/deactivate in order.
    private static let sessionQueue = DispatchQueue(label: "wtf.alert-speaker.session", qos: .userInitiated)

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Premium, then enhanced, then the default voice for the user's English variant.
    @ObservationIgnored private lazy var voice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode().hasPrefix("en") ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US"
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }()

    #if os(iOS)
    /// Headphones, AirPods or the car are connected: somewhere an alert can be read out
    /// without the whole room hearing it.
    static var hasPrivateRoute: Bool {
        let personal: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .carAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { personal.contains($0.portType) }
    }
    #endif

    func speak(_ text: String, about flightID: String? = nil) {
        // A burst of alerts (say, on first load) shouldn't turn into a minute of talking.
        guard pending < 2 else { return }
        pending += 1
        if pending == 1 {
            Self.sessionQueue.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try? session.setActive(true)
            }
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.postUtteranceDelay = 0.3
        if let flightID { flights[ObjectIdentifier(utterance)] = flightID }
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.speakingFlightID = self.flights[key] }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(key) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(key) }
    }

    private func finished(_ key: ObjectIdentifier) {
        if let id = flights.removeValue(forKey: key), id == speakingFlightID { speakingFlightID = nil }
        pending = max(0, pending - 1)
        if pending == 0 {
            Self.sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}
#endif
