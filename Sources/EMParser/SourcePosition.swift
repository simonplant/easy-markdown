import Foundation

/// A position within a markdown document, identified by line and column.
/// Lines and columns are 1-based to match editor conventions.
public struct SourcePosition: Sendable, Equatable, Hashable {
    /// 1-based line number.
    public let line: Int
    /// 1-based column number (UTF-8 offset within the line).
    public let column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }
}

extension SourcePosition: Comparable {
    public static func < (lhs: SourcePosition, rhs: SourcePosition) -> Bool {
        if lhs.line != rhs.line { return lhs.line < rhs.line }
        return lhs.column < rhs.column
    }
}

extension SourcePosition: CustomStringConvertible {
    public var description: String { "\(line):\(column)" }
}

/// A range of positions within a markdown document.
/// Represents the span of an AST node from its start to its end.
public struct SourceRange: Sendable, Equatable, Hashable {
    /// The start position (inclusive).
    public let start: SourcePosition
    /// The end position (inclusive).
    public let end: SourcePosition

    public init(start: SourcePosition, end: SourcePosition) {
        self.start = start
        self.end = end
    }
}

extension SourceRange: CustomStringConvertible {
    public var description: String { "\(start)-\(end)" }
}
