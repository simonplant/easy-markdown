/// The type of content being edited, used for AI provider selection and prompt building.
public enum ContentType: Sendable {
    case prose
    case codeBlock(language: String?)
    case table
    case mermaid
    case mixed
}
