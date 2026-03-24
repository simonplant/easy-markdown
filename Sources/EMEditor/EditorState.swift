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

    /// Rect of the first line of the selection in the text view's coordinate space.
    /// Used by the floating action bar to position above the selection per FEAT-054.
    /// Nil when there is no selection.
    public private(set) var selectionRect: CGRect?

    // MARK: - Floating Action Bar actions per FEAT-054

    /// Formatting action closures wired by TextViewBridge so the floating bar
    /// can dispatch Bold/Italic/Link without direct access to the text view.
    public var performBold: (() -> Void)?
    public var performItalic: (() -> Void)?
    public var performLink: (() -> Void)?

    /// When set to true, the floating action bar should move focus to its AI section.
    /// Reset to false after the bar consumes the request.
    public var focusAISection: Bool = false

    /// Full document statistics per [A-055]. Updated on text changes.
    public private(set) var documentStats: DocumentStats = .zero

    /// Target word count for the writing goal per FEAT-022. Zero means no goal.
    /// Set by EMApp from SettingsManager.
    public var writingGoalWordCount: Int = 0

    /// Active diagnostics from the Document Doctor per FEAT-005.
    /// Updated after each doctor evaluation cycle.
    public private(set) var diagnostics: [Diagnostic] = []

    /// Keys of diagnostics dismissed by the user this session per FEAT-005.
    /// Format: "ruleID:line". Cleared on file close.
    public private(set) var dismissedDiagnosticKeys: Set<String> = []

    /// Whether an image is currently being saved per FEAT-020 AC-4.
    /// When true, EMApp shows a progress indicator overlay.
    public var isImageSaving: Bool = false

    /// Find and replace state per FEAT-017.
    public let findReplaceState = FindReplaceState()

    /// Handler for find bar invocation (Cmd+F) per FEAT-017.
    public var onFindReplace: (() -> Void)?

    /// Replaces all document text as a single undo group per FEAT-017 AC-3.
    /// Wired by TextViewBridge to a coordinator method that modifies text storage
    /// so the replacement is tracked by the undo manager.
    public var performReplaceText: ((_ newText: String) -> Void)?

    /// Applies find match highlighting to the document per FEAT-017.
    /// Called with match ranges and the current match index.
    /// Pass empty array to clear highlights.
    public var applyFindHighlights: ((_ matches: [FindMatch], _ currentIndex: Int?) -> Void)?

    /// Navigates the cursor to a 1-based line number and scrolls it into view per FEAT-022 AC-2.
    /// Wired by TextViewBridge to the text view coordinator.
    public var navigateToLine: ((_ line: Int) -> Void)?

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

    /// Update selection rect for floating action bar positioning per FEAT-054.
    /// Pass nil to clear when selection is empty.
    public func updateSelectionRect(_ rect: CGRect?) {
        selectionRect = rect
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
