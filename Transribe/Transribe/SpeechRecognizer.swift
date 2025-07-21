//
//  SpeechRecognizer.swift
//  Transribe
//
//  Created by Parag Dulam on 18/07/25.
//
import SwiftUI
import Speech

final class SpeechAnalyzer: NSObject, ObservableObject, SFSpeechRecognizerDelegate {
    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var recognizedText: String?
    @Published var isProcessing: Bool = false

    func start() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Couldn't configure the audio session properly")
        }
        
        inputNode = audioEngine.inputNode
        
        speechRecognizer = SFSpeechRecognizer()
        print("Supports on device recognition: \(speechRecognizer?.supportsOnDeviceRecognition == true ? "✅" : "🔴")")

        // Force specified locale
        // self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "pl_PL"))
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // Disable partial results
        // recognitionRequest?.shouldReportPartialResults = false
        
        // Enable on-device recognition
        // recognitionRequest?.requiresOnDeviceRecognition = true

        guard let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable,
              let recognitionRequest = recognitionRequest,
              let inputNode = inputNode
        else {
            assertionFailure("Unable to start the speech recognition!")
            return
        }
        
        speechRecognizer.delegate = self
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            recognitionRequest.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            self?.recognizedText = result?.bestTranscription.formattedString
            
            guard error != nil || result?.isFinal == true else { return }
            self?.stop()
        }

        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isProcessing = true
        } catch {
            print("Coudn't start audio engine!")
            stop()
        }
    }
    
    func stop() {
        recognitionTask?.cancel()
        
        self.audioEngine.stop()
        inputNode?.removeTap(onBus: 0)
        
        isProcessing = false
        
        recognitionRequest = nil
        recognitionTask = nil
        speechRecognizer = nil
        inputNode = nil
    }
    
    public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if available {
            print("✅ Available")
        } else {
            print("🔴 Unavailable")
            recognizedText = "Text recognition unavailable. Sorry!"
            stop()
        }
    }
}
