import Foundation

/// Severity level for a document diagnostic per [A-035].
public enum DiagnosticSeverity: Sendable, Equatable {
    /// A structural issue that should be fixed (e.g., broken link, heading skip).
    case warning
    /// A definite error (e.g., malformed syntax). Reserved for future use.
    case error
}

/// A fix action that can be applied to resolve a diagnostic.
///
/// Value type (no closures) so it is `Sendable` and can cross actor boundaries.
/// The fix is described as a text replacement — the consumer applies it.
public struct DiagnosticFix: Sendable, Equatable {
    /// Short label for the fix button (e.g., "Remove whitespace", "Insert blank line").
    public let label: String

    /// The range in the source text to replace, expressed as 1-based line:column positions.
    public let range: DiagnosticTextRange

    /// The replacement text. Empty string means deletion.
    public let replacement: String

    public init(label: String, range: DiagnosticTextRange, replacement: String) {
        self.label = label
        self.range = range
        self.replacement = replacement
    }
}

/// A range within the source text for diagnostic fixes, using string indices.
///
/// Uses start offset and length (UTF-8) rather than SourcePosition so that
/// consumers can apply fixes without needing the AST or line-index mapping.
public struct DiagnosticTextRange: Sendable, Equatable {
    /// UTF-8 offset from the start of the document.
    public let startOffset: Int
    /// Length in UTF-8 bytes.
    public let length: Int

    public init(startOffset: Int, length: Int) {
        self.startOffset = startOffset
        self.length = length
    }
}

/// A diagnostic produced by the Document Doctor per [A-035].
///
/// Diagnostics are `Sendable` value types — produced on a background thread
/// and posted to the main actor for display in the editor.
public struct Diagnostic: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Which rule produced this diagnostic (e.g., "heading-hierarchy").
    public let ruleID: String
    /// Human-readable summary of the issue.
    public let message: String
    /// Severity level.
    public let severity: DiagnosticSeverity
    /// The 1-based line number where the issue occurs.
    public let line: Int
    /// Optional fix that can be applied automatically.
    public let fix: DiagnosticFix?

    public init(
        id: UUID = UUID(),
        ruleID: String,
        message: String,
        severity: DiagnosticSeverity,
        line: Int,
        fix: DiagnosticFix? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.message = message
        self.severity = severity
        self.line = line
        self.fix = fix
    }
}
