/// Versioned prompt template for the AI Smart Completions action per [A-032] and FEAT-025.
/// Context-aware autocomplete: suggests table layouts, list continuations, and front matter patterns.

import EMCore

/// Builds system and user prompts for the AI Smart Completions action per FEAT-025.
/// Templates are Swift types (compile-time checked) per [A-032].
public struct SmartCompletionPromptTemplate: Sendable {
    /// Current template version. Increment when prompt content changes.
    public static let version = 1

    /// The type of markdown structure detected at the cursor.
    public enum StructureType: Sendable, Equatable {
        /// Table header row detected — suggest separator and first data row.
        case tableHeader(columns: [String])
        /// List item detected — suggest next items based on pattern.
        case listItem(prefix: String, items: [String])
        /// Front matter block detected — suggest next key-value pair.
        case frontMatter(existingKeys: [String])
    }

    /// Builds an AIPrompt for smart completion of the given structure.
    /// - Parameters:
    ///   - structureType: The detected markdown structure type.
    ///   - precedingText: The text before the cursor (last ~500 chars for context).
    ///   - surroundingContext: Optional broader document context.
    /// - Returns: A fully constructed AIPrompt ready for provider inference.
    public static func buildPrompt(
        structureType: StructureType,
        precedingText: String,
        surroundingContext: String? = nil
    ) -> AIPrompt {
        let systemPrompt = systemPrompt(for: structureType)
        let contentType: ContentType = switch structureType {
        case .tableHeader: .table
        case .listItem: .prose
        case .frontMatter: .prose
        }

        return AIPrompt(
            action: .smartComplete,
            selectedText: precedingText,
            surroundingContext: surroundingContext,
            systemPrompt: systemPrompt,
            contentType: contentType
        )
    }

    /// System prompt tailored to the detected structure type.
    static func systemPrompt(for structureType: StructureType) -> String {
        switch structureType {
        case .tableHeader(let columns):
            let columnList = columns.joined(separator: ", ")
            return """
                You are a markdown editor assistant. The user just typed a table header row \
                with columns: \(columnList). \
                Generate ONLY the markdown table separator row and ONE example data row. \
                Match the exact number of columns (\(columns.count)). \
                Use appropriate separator alignment (e.g., |---|---|). \
                The data row should contain realistic placeholder values based on the column names. \
                Do NOT include the header row — only the separator and one data row. \
                Do NOT add explanations or extra text. Return ONLY the two lines of markdown.
                """

        case .listItem(let prefix, let items):
            let recentItems = items.suffix(5).joined(separator: ", ")
            return """
                You are a markdown editor assistant. The user is writing a list \
                using the prefix "\(prefix)". Recent items: \(recentItems). \
                Continue the list with 1-3 natural next items that follow the pattern. \
                Use the same prefix style ("\(prefix)"). \
                Each item on its own line. \
                Do NOT repeat existing items. \
                Do NOT add explanations or extra text. Return ONLY the list items.
                """

        case .frontMatter(let existingKeys):
            let keyList = existingKeys.joined(separator: ", ")
            return """
                You are a markdown editor assistant. The user is editing YAML front matter \
                with existing keys: \(keyList). \
                Suggest 1-2 additional key-value pairs that commonly accompany these keys. \
                Use the same YAML formatting style. \
                Do NOT repeat existing keys. \
                Do NOT add explanations or extra text. Return ONLY the YAML key-value lines.
                """
        }
    }
}
