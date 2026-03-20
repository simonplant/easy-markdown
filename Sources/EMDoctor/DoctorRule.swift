import EMCore
import EMParser
import Foundation

/// Context passed to doctor rules for evaluation.
///
/// Contains the document text, AST, and file URL for rules that need
/// to resolve relative paths (e.g., broken link detection).
public struct DoctorContext: Sendable {
    /// The full document text.
    public let text: String
    /// The parsed AST. Rules should use this for structural analysis.
    public let ast: MarkdownAST
    /// The file URL of the document, if saved. Used by link rules to
    /// resolve relative paths. `nil` for unsaved documents.
    public let fileURL: URL?

    public init(text: String, ast: MarkdownAST, fileURL: URL?) {
        self.text = text
        self.ast = ast
        self.fileURL = fileURL
    }
}

/// A discrete document doctor rule per [A-035].
///
/// Each rule inspects the document context and returns zero or more diagnostics.
/// Rules are individually identifiable by `ruleID` so dismissals can be tracked.
public protocol DoctorRule: Sendable {
    /// Unique identifier for this rule (e.g., "heading-hierarchy").
    var ruleID: String { get }

    /// Evaluate the document and return any diagnostics found.
    func evaluate(_ context: DoctorContext) -> [Diagnostic]
}
