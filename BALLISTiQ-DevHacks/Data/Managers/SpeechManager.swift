//
//  SpeechManager.swift
//  BALLISTiQ-DevHacks
//
//  Created by Gerasim Israyelyan on 04.07.25.
//

import Foundation
import AVFAudio
import Speech

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        synthesizer.delegate = self
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Use a clear, authoritative male voice that suits firing‑range commands
        if let voice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.siri_Mark_en-US_compact") {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = 0.4
        synthesizer.speak(utterance)
    }
    
    // Delegate methods for additional feedback
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("Finished speaking.")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("Speech was cancelled.")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("ASDASD", utterance.voice?.identifier)
    }
}
