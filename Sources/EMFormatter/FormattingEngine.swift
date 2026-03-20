import EMCore
import EMParser

/// Evaluates formatting rules against a context and returns the first matching mutation.
///
/// The engine runs rules in order and returns the first non-nil result.
/// This implements the keystroke interception pipeline described in [A-051].
public struct FormattingEngine: Sendable {

    /// The ordered list of rules to evaluate.
    public let rules: [any FormattingRule]

    public init(rules: [any FormattingRule]) {
        self.rules = rules
    }

    /// Evaluates all rules against the context, returning the first applicable mutation.
    ///
    /// - Parameter context: The current editing context (text, cursor, trigger, AST).
    /// - Returns: A `TextMutation` from the first matching rule, or `nil` if no rules apply.
    public func evaluate(_ context: FormattingContext) -> TextMutation? {
        for rule in rules {
            if let mutation = rule.evaluate(context) {
                return mutation
            }
        }
        return nil
    }

    /// Creates an engine with the default list auto-formatting rules per FEAT-004.
    public static func listFormattingEngine() -> FormattingEngine {
        FormattingEngine(rules: [
            ListContinuationRule(),
            ListIndentRule(),
        ])
    }

    /// Creates an engine with all auto-formatting rules per FEAT-004, FEAT-052, FEAT-053.
    /// Table rules are evaluated first so they take priority when the cursor is in a table.
    /// Heading and whitespace rules are placed after list rules so list/table Enter
    /// handling takes priority; WhitespaceCleanupRule only fires on non-list, non-table lines.
    ///
    /// Settings parameters control which FEAT-053 rules are active. When a setting is false,
    /// the corresponding rule is omitted or configured to skip that behavior.
    public static func defaultFormattingEngine(
        isHeadingSpacingEnabled: Bool = true,
        isBlankLineSeparationEnabled: Bool = true,
        isTrailingWhitespaceTrimEnabled: Bool = true
    ) -> FormattingEngine {
        var rules: [any FormattingRule] = [
            TableNavigationRule(),
            TableContinuationRule(),
            TableAlignmentRule(),
        ]
        if isHeadingSpacingEnabled {
            rules.append(HeadingSpacingRule())
        }
        rules.append(contentsOf: [
            ListContinuationRule(),
            ListIndentRule(),
        ])
        rules.append(WhitespaceCleanupRule(
            trimTrailingWhitespace: isTrailingWhitespaceTrimEnabled,
            removeTrailingHashes: isHeadingSpacingEnabled,
            insertBlankLineBetweenBlocks: isBlankLineSeparationEnabled
        ))
        return FormattingEngine(rules: rules)
    }
}
