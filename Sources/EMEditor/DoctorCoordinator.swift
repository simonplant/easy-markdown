/// Coordinates Document Doctor evaluation within the editor per FEAT-005.
///
/// Runs the doctor engine on a background thread after each parse, debounced
/// to avoid re-evaluating during rapid edits. Posts results to EditorState
/// on the main actor. Manages per-session dismissals.

import Foundation
import os
import EMCore
import EMDoctor
import EMParser

private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "doctor")

@MainActor
public final class DoctorCoordinator {

    /// The doctor engine instance. Rebuilt when prose suggestions toggle changes.
    private var engine: DoctorEngine

    /// The editor state to post diagnostics to.
    private weak var editorState: EditorState?

    /// File URL for resolving relative links. Updated by the caller.
    public var fileURL: URL?

    /// Whether prose suggestion rules are included per FEAT-022.
    /// Set by EMApp from SettingsManager. Rebuilds the engine when changed.
    public var proseSuggestionsEnabled: Bool = false {
        didSet {
            guard oldValue != proseSuggestionsEnabled else { return }
            engine = DoctorEngine(includingProseSuggestions: proseSuggestionsEnabled)
        }
    }

    /// Debounce task for doctor evaluation (500ms per spec).
    private var debounceTask: Task<Void, Never>?

    /// Debounce interval: 500ms after edits pause per spec.
    private let debounceInterval: UInt64 = 500_000_000

    /// Performance signpost per [A-037].
    private let signpost = OSSignpost(
        subsystem: "com.easymarkdown.emeditor",
        category: "doctor"
    )

    public init(editorState: EditorState, proseSuggestionsEnabled: Bool = false) {
        self.editorState = editorState
        self.proseSuggestionsEnabled = proseSuggestionsEnabled
        self.engine = DoctorEngine(includingProseSuggestions: proseSuggestionsEnabled)
    }

    /// Evaluates the document immediately (used on file open).
    /// Runs the doctor engine on a background thread and posts results.
    public func evaluateImmediately(text: String, ast: MarkdownAST) {
        debounceTask?.cancel()
        runEvaluation(text: text, ast: ast)
    }

    /// Schedules a debounced doctor evaluation after an edit pause.
    public func scheduleEvaluation(text: String, ast: MarkdownAST) {
        debounceTask?.cancel()

        let capturedText = text
        let capturedAST = ast
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.debounceInterval ?? 500_000_000)
            } catch {
                return // Cancelled
            }
            guard let self, !Task.isCancelled else { return }
            self.runEvaluation(text: capturedText, ast: capturedAST)
        }
    }

    private func runEvaluation(text: String, ast: MarkdownAST) {
        guard let editorState else { return }

        let fileURL = self.fileURL
        let engine = self.engine
        let dismissedIDs = editorState.dismissedDiagnosticKeys

        signpost.begin("doctor-evaluate")

        // Evaluate on background thread, then post results on main actor.
        // Task.detached captures only Sendable values; editorState is
        // accessed only from the outer @MainActor Task.
        Task {
            let diagnostics = await Task.detached {
                let context = DoctorContext(text: text, ast: ast, fileURL: fileURL)
                let allDiagnostics = engine.evaluate(context)
                return allDiagnostics.filter { diag in
                    let key = "\(diag.ruleID):\(diag.line)"
                    return !dismissedIDs.contains(key)
                }
            }.value

            signpost.end("doctor-evaluate")
            editorState.updateDiagnostics(diagnostics)
            logger.debug("Doctor found \(diagnostics.count) issue(s)")
        }
    }
}
