/// Per-scene editor state per [A-004] and §3.
/// Owns platform-specific state that should not pollute EMCore.
/// Each scene (window) creates its own EditorState instance.

import Foundation
import EMCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
public final class EditorState {
    /// Current selected range in the text view.
    public var selectedRange: NSRange

    /// Whether the editor is showing raw source (true) or rich view (false).
    public var isSourceView: Bool

    /// Current scroll offset (points from top).
    public var scrollOffset: CGFloat

    /// Undo manager for this editor scene. Unlimited depth per [D-EDIT-6].
    public let undoManager: UndoManager

    /// Word count for the current selection, nil when no selection.
    public private(set) var selectionWordCount: Int?

    /// Full document statistics per [A-055]. Updated on text changes.
    public private(set) var documentStats: DocumentStats = .zero

    /// Active diagnostics from the Document Doctor per FEAT-005.
    /// Updated after each doctor evaluation cycle.
    public private(set) var diagnostics: [Diagnostic] = []

    /// Keys of diagnostics dismissed by the user this session per FEAT-005.
    /// Format: "ruleID:line". Cleared on file close.
    public private(set) var dismissedDiagnosticKeys: Set<String> = []

    public init() {
        self.selectedRange = NSRange(location: 0, length: 0)
        self.isSourceView = false
        self.scrollOffset = 0
        self.undoManager = UndoManager()
        self.undoManager.levelsOfUndo = 0 // 0 = unlimited per [A-022]
        self.selectionWordCount = nil
    }

    /// Update selection word count. Pass nil to clear.
    public func updateSelectionWordCount(_ count: Int?) {
        selectionWordCount = count
    }

    /// Update full document statistics.
    public func updateDocumentStats(_ stats: DocumentStats) {
        documentStats = stats
    }

    /// Update selected range from the text view.
    public func updateSelectedRange(_ range: NSRange) {
        selectedRange = range
    }

    /// Update scroll offset from the text view.
    public func updateScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
    }

    /// Replace the current diagnostics with new results from the doctor engine.
    public func updateDiagnostics(_ newDiagnostics: [Diagnostic]) {
        diagnostics = newDiagnostics
    }

    /// Dismiss a diagnostic for this session. It will not reappear until
    /// the file is closed and reopened per FEAT-005 AC-3.
    public func dismissDiagnostic(_ diagnostic: Diagnostic) {
        let key = "\(diagnostic.ruleID):\(diagnostic.line)"
        dismissedDiagnosticKeys.insert(key)
        diagnostics.removeAll { $0.id == diagnostic.id }
    }

    /// Clear all diagnostics and dismissals (called on file close).
    public func clearDiagnostics() {
        diagnostics = []
        dismissedDiagnosticKeys = []
    }
}
