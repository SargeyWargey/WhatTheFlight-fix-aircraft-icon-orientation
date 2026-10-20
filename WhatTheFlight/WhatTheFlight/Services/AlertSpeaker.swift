//
//  AlertSpeaker.swift
//  WhatTheFlight
//
//  Reads traffic alerts aloud ("Delta Air Lines flight 1199 is approaching overhead…") with
//  the best English voice installed, ducking any other audio while it speaks.
//

#if os(tvOS) || os(iOS)
import AVFoundation

@MainActor
final class AlertSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = AlertSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var pending = 0
    /// Activating or deactivating the audio session can block for a while, so it never runs on
    /// the main thread. A serial queue keeps activate/deactivate in order.
    private static let sessionQueue = DispatchQueue(label: "wtf.alert-speaker.session", qos: .userInitiated)

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Premium, then enhanced, then the default voice for the user's English variant.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode().hasPrefix("en") ? AVSpeechSynthesisVoice.currentLanguageCode() : "en-US"
        let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return english.first { $0.quality == .premium }
            ?? english.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: language)
    }()

    func speak(_ text: String) {
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
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        pending = max(0, pending - 1)
        if pending == 0 {
            Self.sessionQueue.async {
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
        }
    }
}
#endif
