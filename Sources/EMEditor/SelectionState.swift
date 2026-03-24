/// Focused state object for text selection per FEAT-076.
/// Independently observable and testable.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
public final class SelectionState {
    /// Current selected range in the text view.
    public var selectedRange: NSRange

    /// Word count for the current selection, nil when no selection.
    public private(set) var selectionWordCount: Int?

    /// Rect of the first line of the selection in the text view's coordinate space.
    /// Used by the floating action bar to position above the selection per FEAT-054.
    /// Nil when there is no selection.
    public private(set) var selectionRect: CGRect?

    public init() {
        self.selectedRange = NSRange(location: 0, length: 0)
        self.selectionWordCount = nil
    }

    /// Update selected range from the text view.
    public func updateSelectedRange(_ range: NSRange) {
        selectedRange = range
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
}
