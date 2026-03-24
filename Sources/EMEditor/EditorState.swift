/// Per-scene editor state per [A-004] and §3.
/// Owns platform-specific state that should not pollute EMCore.
/// Each scene (window) creates its own EditorState instance.
///
/// Composes focused sub-state objects (SelectionState, FormattingActions,
/// DiagnosticsState) so each concern is independently testable per FEAT-076.

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
    // MARK: - Composed sub-states per FEAT-076

    /// Selection state (selectedRange, selectionWordCount, selectionRect).
    public let selection: SelectionState

    /// Formatting action closures for the floating action bar per FEAT-054.
    public let formatting: FormattingActions

    /// Document Doctor diagnostics state per FEAT-005.
    public let diagnosticsState: DiagnosticsState

    // MARK: - View state

    /// Whether the editor is showing raw source (true) or rich view (false).
    public var isSourceView: Bool

    /// Current scroll offset (points from top).
    public var scrollOffset: CGFloat

    /// Undo manager for this editor scene. Unlimited depth per [D-EDIT-6].
    public let undoManager: UndoManager

    /// Full document statistics per [A-055]. Updated on text changes.
    public private(set) var documentStats: DocumentStats = .zero

    /// Target word count for the writing goal per FEAT-022. Zero means no goal.
    /// Set by EMApp from SettingsManager.
    public var writingGoalWordCount: Int = 0

    /// Whether an image is currently being saved per FEAT-020 AC-4.
    /// When true, EMApp shows a progress indicator overlay.
    public var isImageSaving: Bool = false

    // MARK: - Find & Replace per FEAT-017

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

    // MARK: - Line Navigation per FEAT-022

    /// Navigates the cursor to a 1-based line number and scrolls it into view per FEAT-022 AC-2.
    /// Wired by TextViewBridge to the text view coordinator.
    public var navigateToLine: ((_ line: Int) -> Void)?

    public init() {
        self.selection = SelectionState()
        self.formatting = FormattingActions()
        self.diagnosticsState = DiagnosticsState()
        self.isSourceView = false
        self.scrollOffset = 0
        self.undoManager = UndoManager()
        self.undoManager.levelsOfUndo = 0 // 0 = unlimited per [A-022]
    }

    /// Update full document statistics.
    public func updateDocumentStats(_ stats: DocumentStats) {
        documentStats = stats
    }

    /// Update scroll offset from the text view.
    public func updateScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
    }
}
