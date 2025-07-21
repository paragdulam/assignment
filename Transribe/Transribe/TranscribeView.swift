//
//  RecordingView.swift
//  Transribe
//
//  Created by Parag Dulam on 18/07/25.
//

import SwiftUI
import AVFoundation



// MARK: - Audio Recording Manager
class AudioRecordingManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var recordingPermissionGranted = false
    @Published var currentRecordingURL: URL?
    
    private var audioRecorder: AVAudioRecorder?
    private var audioSession: AVAudioSession = AVAudioSession.sharedInstance()
    
    override init() {
        super.init()
        requestRecordingPermission()
    }
    
    func requestRecordingPermission(calledFromPermissionCheck: Bool = false) {
        audioSession.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.recordingPermissionGranted = granted
                if granted {
                    self.setupAudioSession()
                    if calledFromPermissionCheck {
                        self.startRecording()
                    }
                }
            }
        }
    }
    
    private func setupAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }
    
    private func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    private func createRecordingURL() -> URL {
        let documentsPath = getDocumentsDirectory()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "recording_\(timestamp).m4a"
        return documentsPath.appendingPathComponent(filename)
    }
    
    func startRecording() {
        guard recordingPermissionGranted else {
            requestRecordingPermission(calledFromPermissionCheck: true)
            return
        }
        
        let recordingURL = createRecordingURL()
        currentRecordingURL = recordingURL
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
            print("Started recording to: \(recordingURL.path)")
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    
    
    
    
    
    
    
    
    
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        if let url = currentRecordingURL {
            print("Recording saved to: \(url.path)")
        }
    }
    
    func pauseRecording() {
        audioRecorder?.pause()
        isRecording = false
    }
    
    func resumeRecording() {
        audioRecorder?.record()
        isRecording = true
    }
    
    func getSavedRecordings() -> [URL] {
        let documentsPath = getDocumentsDirectory()
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil)
            return files.filter { $0.pathExtension == "m4a" }
        } catch {
            print("Error reading documents directory: \(error)")
            return []
        }
    }
    
    func deleteRecording(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("Deleted recording: \(url.lastPathComponent)")
        } catch {
            print("Error deleting recording: \(error)")
        }
    }
    
    // MARK: - AVAudioRecorderDelegate
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag {
            print("Recording finished successfully")
        } else {
            print("Recording failed")
        }
    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Recording encode error: \(error)")
        }
    }
}


struct TranscribeView: View {
    @State private var currentState: RecordingState = .recording
    @State private var isRecording = true
    @State private var seconds = 0
    @State private var timer: Timer?
    @State private var hasChanges = false
    @State private var currentTranscriptText = ""
    @State private var currentSegmentIndex = 0
    @State private var transcriptTimer: Timer?
    @State private var transcriptText = ""
    @State private var waveAnimationPhase = 0.0
    
    // Audio recording manager
    @StateObject private var audioManager = AudioRecordingManager()
    
    private var transcriptSegments: [String] = []
    
    @ObservedObject private var speechAnalyzer = SpeechAnalyzer()
    
    enum RecordingState {
        case recording, paused
    }
    
    
    func toggleSpeechRecognition() {
        if speechAnalyzer.isProcessing {
            speechAnalyzer.stop()
        } else {
            speechAnalyzer.start()
        }
    }

    var statusBarHeight: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.statusBarManager?.statusBarFrame.height ?? 44
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Section
                headerSection
                
                // Content Area
                ScrollView {
                    VStack(spacing: 16) {
                        transcriptionBox
                        aiNotesBox
                        voiceWavesView
                    }
                    .padding(24)
                }
                .background(Color(.systemGroupedBackground))
                
                // Bottom Control Bar
                bottomControlBar
            }
            .navigationBarHidden(true)
            .ignoresSafeArea(edges: .top)
        }
        .onAppear {
            startRecording()
        }
        .onDisappear {
            stopAllTimers()
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: handleBack) {
                    Image(systemName: "arrow.left")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 20))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recording Session")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Patient: John Davis")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
            }
            
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                    Text(timeString)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                // Recording Status
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .opacity(isRecording ? 1 : 0.7)
                        .scaleEffect(isRecording ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: isRecording)
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusBackgroundColor)
                .cornerRadius(20)
            }
        }
        .padding(EdgeInsets(top: statusBarHeight + 10, leading: 24, bottom: 24, trailing: 24))
        .background(Color.blue)
    }
    
    // MARK: - Transcription Box
    private var transcriptionBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Transcription")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !currentTranscriptText.isEmpty {
                        Text(currentTranscriptText)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    
                    if isRecording {
                        // Typing animation
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                    .opacity(waveAnimationPhase == Double(index) ? 1 : 0.3)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                        value: waveAnimationPhase
                                    )
                            }
                        }
                        .onAppear {
                            withAnimation {
                                waveAnimationPhase = 2.0
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 192)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .opacity(currentState == .paused ? 0.5 : 1.0)
    }
    
    // MARK: - AI Notes Box
    private var aiNotesBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI Notes Preview")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
                
                Spacer()
                
                if isRecording {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Processing")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    aiNotesContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
        .opacity(currentState == .paused ? 0.5 : 1.0)
    }
    
    private var aiNotesContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if currentSegmentIndex >= 2 {
                Text("**S:** Lower back pain, intermittent, 1-week duration")
                Text("**O:** Pain worse in mornings, after prolonged sitting")
                Text("**A:** Mechanical back pain, possible muscle strain")
                Text("**P:** Consider NSAIDs, physical therapy evaluation")
            } else {
                Text("**S:** Patient reporting back pain symptoms")
                Text("**O:** Initial examination in progress")
                Text("**A:** Gathering data for assessment")
                Text("**P:** Will formulate based on findings")
            }
            
            if isRecording {
                Text("|")
                    .foregroundColor(.blue)
                    .opacity(waveAnimationPhase > 1 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: waveAnimationPhase)
            }
        }
        .font(.system(size: 14))
        .foregroundColor(.blue)
    }
    
    // MARK: - Voice Waves View
    private var voiceWavesView: some View {
        HStack(spacing: 4) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: 4, height: waveHeight(for: index))
                    .animation(
                        .easeInOut(duration: 1.0)
                        .repeatForever()
                        .delay(Double(index) * 0.1),
                        value: isRecording ? 1.0 : 0.0
                    )
            }
        }
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Color.clear)
        .cornerRadius(12)
        .opacity(isRecording ? 1 : 0.3)
    }
    
    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeights: [CGFloat] = [16, 24, 32, 40, 48, 40, 32, 24, 16]
        let baseHeight = baseHeights[index]
        return isRecording ? baseHeight : baseHeight * 0.3
    }
    
    // MARK: - Bottom Control Bar
    private var bottomControlBar: some View {
        HStack(spacing: 16) {
            if currentState == .paused {
                // Discard Button
                Button(action: resetAll) {
                    Image(systemName: "xmark")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.red)
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            
            // Main Recording Button
            Button(action: toggleRecordingState) {
                Image(systemName: currentState == .recording ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            
            if currentState == .recording {
                // Stop Button
                Button(action: handleStop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(Color(.systemGray))
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            } else {
                // Submit Button
                Button(action: handleSubmit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.systemGray4)),
            alignment: .top
        )
    }
    
    // MARK: - Computed Properties
    private var timeString: String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    private var statusColor: Color {
        switch currentState {
        case .recording: return .red
        case .paused: return .yellow
        }
    }
    
    private var statusText: String {
        switch currentState {
        case .recording: return "Recording"
        case .paused: return "Paused"
        }
    }
    
    private var statusBackgroundColor: Color {
        switch currentState {
        case .recording: return .red.opacity(0.2)
        case .paused: return .yellow.opacity(0.2)
        }
    }
    
    // MARK: - Functions
    private func startRecording() {
        resetAll()
        speechAnalyzer.start()
        audioManager.startRecording()
    }
    
    private func toggleRecordingState() {
        hasChanges = true
        
        switch currentState {
        case .recording:
            currentState = .paused
            isRecording = false
            stopTranscriptAnimation()
            audioManager.pauseRecording()
        case .paused:
            currentState = .recording
            isRecording = true
            startTranscriptAnimation(continueFromPrevious: true)
            audioManager.resumeRecording()
        }
    }
    
    private func resetAll() {
        stopAllTimers()
        audioManager.stopRecording()
        seconds = 0
        currentSegmentIndex = 0
        currentTranscriptText = ""
        hasChanges = false
        currentState = .recording
        isRecording = true
        
        startTimer()
        startTranscriptAnimation(continueFromPrevious: false)
        audioManager.startRecording()
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isRecording {
                seconds += 1
            }
        }
    }
    
    private func startTranscriptAnimation(continueFromPrevious: Bool) {
        if !continueFromPrevious {
            currentTranscriptText = ""
            currentSegmentIndex = 0
        }
        
        transcriptTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if isRecording {
                if !currentTranscriptText.isEmpty {
                    currentTranscriptText += "\n\n"
                }
                if isRecording {
                    if !transcriptText.isEmpty {
                        transcriptText += "\n\n"
                    }
                    currentTranscriptText = speechAnalyzer.recognizedText ?? ""
                }
            }
        }
    }
    
    private func stopTranscriptAnimation() {
        transcriptTimer?.invalidate()
        transcriptTimer = nil
    }
    
    private func stopAllTimers() {
        speechAnalyzer.stop()
        audioManager.stopRecording()
        timer?.invalidate()
        timer = nil
        transcriptTimer?.invalidate()
        transcriptTimer = nil
    }
    
    private func handleBack() {
        if hasChanges {
            // In a real app, you'd show an alert here
            // For now, just navigate back
        }
        // Navigate back to previous view
    }
    
    private func handleStop() {
        audioManager.stopRecording()
        // Navigate back to home
    }
    
    private func handleSubmit() {
        // Stop recording and save file
        audioManager.stopRecording()
        // Navigate to clinical notes view
    }
}

#Preview {
    TranscribeView()
}
