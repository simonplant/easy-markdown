/// Manages on-device speech recognition per FEAT-068 AC-2, AC-3, AC-6.
/// Wraps `SFSpeechRecognizer` with on-device recognition (no network required on iOS 17+).
/// Streams real-time transcription updates to the caller.
/// Lives in EMEditor (supporting package per [A-050]).

#if canImport(Speech)
import Speech
import AVFoundation
import Observation
import os

/// The current state of the speech recognition session.
public enum SpeechRecognitionState: Sendable, Equatable {
    /// Not recording.
    case idle
    /// Requesting permissions.
    case requestingPermission
    /// Audio engine is starting up.
    case starting
    /// Actively recording and transcribing.
    case recording
    /// Recording stopped, finalizing transcription.
    case finishing
    /// Session completed with a final transcript.
    case completed(transcript: String)
    /// An error occurred.
    case failed(String)
    /// Permission was denied.
    case permissionDenied
}

/// Manages speech recognition lifecycle: permissions, audio session, recognition.
/// Uses on-device recognition per AC-6 — works offline on iOS 17+.
@MainActor
@Observable
public final class SpeechRecognitionManager {
    /// Current recognition state.
    public private(set) var state: SpeechRecognitionState = .idle

    /// Real-time transcription text, updated as the user speaks per AC-3.
    public private(set) var liveTranscript: String = ""

    /// Whether speech recognition is available on this device.
    public var isAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "speech-recognition")

    /// Signpost for measuring speech recognition latency per [A-037].
    private let signposter = OSSignposter(subsystem: "com.easymarkdown.emeditor", category: "speech")

    public init() {
        // Use the device's locale for recognition
        speechRecognizer = SFSpeechRecognizer()
    }

    /// Starts speech recognition.
    /// Requests permissions if not yet granted, configures the audio session,
    /// and begins streaming recognized text per AC-2 (within 200ms).
    public func startRecording() {
        guard state == .idle || state == .completed(transcript: "") || isTerminalState else {
            logger.debug("Cannot start recording in state: \(String(describing: self.state))")
            return
        }

        liveTranscript = ""
        state = .requestingPermission

        // Check speech recognition authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.checkMicrophoneAndStart()
                case .denied, .restricted:
                    self.state = .permissionDenied
                    self.logger.warning("Speech recognition permission denied")
                case .notDetermined:
                    self.state = .permissionDenied
                @unknown default:
                    self.state = .permissionDenied
                }
            }
        }
    }

    /// Stops recording and finalizes the transcription.
    public func stopRecording() {
        guard state == .recording || state == .starting else { return }

        state = .finishing

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    /// Cancels the current recording session without waiting for final results.
    public func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        deactivateAudioSession()

        liveTranscript = ""
        state = .idle
    }

    /// Resets the manager to idle state.
    public func reset() {
        cancel()
        state = .idle
    }

    // MARK: - Private

    private var isTerminalState: Bool {
        switch state {
        case .completed, .failed, .permissionDenied:
            return true
        default:
            return false
        }
    }

    /// Checks microphone permission and starts recording if granted.
    private func checkMicrophoneAndStart() {
        #if os(iOS)
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if granted {
                    self.beginRecording()
                } else {
                    self.state = .permissionDenied
                    self.logger.warning("Microphone permission denied")
                }
            }
        }
        #else
        // macOS: check microphone access
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginRecording()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.beginRecording()
                    } else {
                        self.state = .permissionDenied
                    }
                }
            }
        default:
            state = .permissionDenied
        }
        #endif
    }

    /// Begins the actual recording and recognition session.
    private func beginRecording() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .failed("Speech recognition is not available on this device.")
            return
        }

        state = .starting

        let startSignpostID = signposter.makeSignpostID()
        let startState = signposter.beginInterval("speech-start", id: startSignpostID)

        // Configure recognition request for on-device recognition per AC-6
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        // Force on-device recognition for offline support per AC-6
        if #available(iOS 17.0, macOS 14.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        // Prevent sending audio to Apple servers per privacy requirements
        request.addsPunctuation = true

        recognitionRequest = request

        // Configure audio engine
        let engine = AVAudioEngine()
        audioEngine = engine

        // Configure audio session
        do {
            try configureAudioSession()
        } catch {
            state = .failed("Could not configure audio session: \(error.localizedDescription)")
            logger.error("Audio session configuration failed: \(error.localizedDescription)")
            signposter.endInterval("speech-start", startState)
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap on the audio input to feed the recognizer
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    // Update live transcript per AC-3
                    self.liveTranscript = result.bestTranscription.formattedString

                    if result.isFinal {
                        let transcript = result.bestTranscription.formattedString
                        self.cleanupRecording()
                        self.state = .completed(transcript: transcript)
                        self.logger.debug("Final transcript: \(transcript)")
                    }
                }

                if let error {
                    // Ignore cancellation errors
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // User cancelled — not an error
                        return
                    }
                    self.cleanupRecording()
                    self.state = .failed("Recognition failed: \(error.localizedDescription)")
                    self.logger.error("Recognition error: \(error.localizedDescription)")
                }
            }
        }

        // Start the audio engine
        do {
            engine.prepare()
            try engine.start()
            state = .recording
            signposter.endInterval("speech-start", startState)
            logger.debug("Speech recognition started")
        } catch {
            cleanupRecording()
            state = .failed("Could not start audio engine: \(error.localizedDescription)")
            logger.error("Audio engine start failed: \(error.localizedDescription)")
            signposter.endInterval("speech-start", startState)
        }
    }

    /// Configures the audio session for recording.
    private func configureAudioSession() throws {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        // macOS doesn't require explicit audio session configuration
    }

    /// Deactivates the audio session after recording.
    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Cleans up recording resources.
    private func cleanupRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        deactivateAudioSession()
    }
}
#endif
