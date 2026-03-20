/// Per-scene editor state per [A-004] and §3.
/// Owns platform-specific state that should not pollute EMCore.
/// Each scene (window) creates its own EditorState instance.

import Foundation
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

    /// Update selected range from the text view.
    public func updateSelectedRange(_ range: NSRange) {
        selectedRange = range
    }

    /// Update scroll offset from the text view.
    public func updateScrollOffset(_ offset: CGFloat) {
        scrollOffset = offset
    }
}
