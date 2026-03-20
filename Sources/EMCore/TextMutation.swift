/// Describes a text mutation produced by a formatting rule per [A-051].
/// Applied as a single undo group.
public struct TextMutation: Sendable {
    /// The range in the source string to replace.
    public let range: Range<String.Index>
    /// The replacement text.
    public let replacement: String
    /// Where the cursor should be placed after applying the mutation.
    public let cursorAfter: String.Index
    /// Haptic feedback to trigger on application, or nil for none.
    public let hapticStyle: HapticStyle?

    public init(
        range: Range<String.Index>,
        replacement: String,
        cursorAfter: String.Index,
        hapticStyle: HapticStyle? = nil
    ) {
        self.range = range
        self.replacement = replacement
        self.cursorAfter = cursorAfter
        self.hapticStyle = hapticStyle
    }
}
