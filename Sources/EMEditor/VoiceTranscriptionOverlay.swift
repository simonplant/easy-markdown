/// Overlay that shows real-time transcription during voice recording per FEAT-068 AC-3.
/// Displays a pulsing mic indicator and the live transcript text.
/// Also serves as the mic button for activating voice control per AC-1.
/// Lives in EMEditor (supporting package per [A-050]).

#if canImport(Speech)
import SwiftUI

/// Overlay shown during voice recording with live transcription per AC-3.
public struct VoiceTranscriptionOverlay: View {
    /// The current phase of the voice flow.
    public let phase: VoicePhase
    /// The live transcription text.
    public let transcript: String
    /// Whether voice is available on this device.
    public let isAvailable: Bool
    /// Called when the user presses and holds the mic button.
    public let onStartListening: () -> Void
    /// Called when the user releases the mic button.
    public let onStopListening: () -> Void

    @State private var isPulsing = false

    public init(
        phase: VoicePhase,
        transcript: String,
        isAvailable: Bool,
        onStartListening: @escaping () -> Void,
        onStopListening: @escaping () -> Void
    ) {
        self.phase = phase
        self.transcript = transcript
        self.isAvailable = isAvailable
        self.onStartListening = onStartListening
        self.onStopListening = onStopListening
    }

    public var body: some View {
        VStack(spacing: 12) {
            if phase == .listening {
                listeningView
            } else if phase == .interpreting {
                interpretingView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: phase)
    }

    /// View shown while actively recording per AC-3.
    private var listeningView: some View {
        VStack(spacing: 8) {
            // Pulsing mic indicator
            Image(systemName: "mic.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .scaleEffect(isPulsing ? 1.15 : 1.0)
                .animation(
                    .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }
                .onDisappear { isPulsing = false }
                .accessibilityLabel("Recording voice command")

            if !transcript.isEmpty {
                Text(transcript)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .accessibilityLabel("Transcription: \(transcript)")
            } else {
                Text("Listening...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Listening for voice command")
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityLabel(
            transcript.isEmpty
                ? "Voice recording active, listening for command"
                : "Voice recording active, heard: \(transcript)"
        )
        .accessibilityHint("Release the mic button to process your command")
    }

    /// View shown while AI is interpreting the transcript.
    private var interpretingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                #if canImport(UIKit)
                .controlSize(.small)
                #endif

            Text("Interpreting...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .accessibilityLabel("AI is interpreting your voice command")
    }
}

/// Mic button for activating voice control per FEAT-068 AC-1.
/// Hold to record, release to process.
/// Placed in the toolbar alongside other editor actions.
public struct VoiceMicButton: View {
    /// Whether voice is available on this device.
    public let isAvailable: Bool
    /// Whether currently listening.
    public let isListening: Bool
    /// Called when the user presses down (starts recording).
    public let onStartListening: () -> Void
    /// Called when the user releases (stops recording).
    public let onStopListening: () -> Void

    public init(
        isAvailable: Bool,
        isListening: Bool,
        onStartListening: @escaping () -> Void,
        onStopListening: @escaping () -> Void
    ) {
        self.isAvailable = isAvailable
        self.isListening = isListening
        self.onStartListening = onStartListening
        self.onStopListening = onStopListening
    }

    public var body: some View {
        Button {
            // Tap toggles: if not listening, start; if listening, stop
            if isListening {
                onStopListening()
            } else {
                onStartListening()
            }
        } label: {
            Image(systemName: isListening ? "mic.fill" : "mic")
                .foregroundStyle(isListening ? .red : .primary)
                .imageScale(.medium)
        }
        .disabled(!isAvailable)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.2)
                .onEnded { _ in
                    if !isListening {
                        onStartListening()
                    }
                }
        )
        .accessibilityLabel(
            isListening
                ? "Stop voice command"
                : "Voice command"
        )
        .accessibilityHint(
            isListening
                ? "Tap to stop recording and process your voice command"
                : "Hold or tap to speak an editing command. Say what you want to change, like 'make this shorter' or 'add a conclusion'. Voice editing mode — separate from VoiceOver navigation."
        )
        .accessibilityAddTraits(isListening ? .isSelected : [])
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }
}
#endif
