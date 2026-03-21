import EMCore
import EMParser
import Foundation

/// Runs all registered doctor rules against a document snapshot per [A-035].
///
/// The engine is `Sendable` — it is created once and shared. Evaluation runs
/// on a background thread; the caller is responsible for debouncing and
/// posting results back to the main actor.
public struct DoctorEngine: Sendable {
    /// The ordered list of rules to evaluate.
    public let rules: [any DoctorRule]

    /// Creates a doctor engine with the default MVP rule set.
    public init() {
        self.rules = Self.structuralRules
    }

    /// Creates a doctor engine with structural rules plus prose suggestion rules per FEAT-022.
    public init(includingProseSuggestions: Bool) {
        if includingProseSuggestions {
            self.rules = Self.structuralRules + Self.proseRules
        } else {
            self.rules = Self.structuralRules
        }
    }

    /// The default structural rules (MVP).
    private static var structuralRules: [any DoctorRule] {
        [
            HeadingHierarchyRule(),
            DuplicateHeadingRule(),
            BrokenRelativeLinkRule(),
            TrailingWhitespaceRule(),
            MissingBlankLineRule(),
        ]
    }

    /// Prose suggestion rules per FEAT-022 (opt-in).
    private static var proseRules: [any DoctorRule] {
        [
            LongSentenceRule(),
            PassiveVoiceRule(),
            RepeatedWordRule(),
        ]
    }

    /// Creates a doctor engine with custom rules (for testing).
    public init(rules: [any DoctorRule]) {
        self.rules = rules
    }

    /// Evaluate all rules against the given context.
    ///
    /// This method is safe to call from a background thread. It returns
    /// diagnostics sorted by line number.
    public func evaluate(_ context: DoctorContext) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []
        for rule in rules {
            diagnostics.append(contentsOf: rule.evaluate(context))
        }
        diagnostics.sort { $0.line < $1.line }
        return diagnostics
    }
}
