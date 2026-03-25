/// Regex-based syntax highlighting for fenced code blocks per [A-005] fallback.
///
/// Tokenizes code block content into semantic categories (keyword, string, comment,
/// number, type, function) and maps them to `ThemeColors` syntax colors.
/// Supports 15+ languages per FEAT-006 requirements.
///
/// This is the interim approach until SPIKE-007 evaluates tree-sitter integration.
/// When tree-sitter is adopted, this file is replaced — the public API surface
/// (`SyntaxHighlighter.highlight`) remains the same.

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

// MARK: - Token Types

/// Semantic token categories for syntax highlighting.
enum SyntaxTokenType: Sendable {
    case keyword
    case string
    case comment
    case number
    case type
    case function
}

/// A highlighted token with its range and type.
struct SyntaxToken: Sendable {
    let range: NSRange
    let type: SyntaxTokenType
}

// MARK: - Syntax Highlighter

/// Tokenizes source code and applies syntax highlighting colors.
///
/// Regex patterns are compiled once and cached per language.
/// Thread safety: all callers go through @MainActor MarkdownRenderer.render().
struct SyntaxHighlighter {

    /// Applies syntax highlighting attributes to a code block's content range.
    ///
    /// - Parameters:
    ///   - attrStr: The mutable attributed string to style.
    ///   - contentRange: The NSRange of the code content (excluding fence lines).
    ///   - language: The language identifier from the info string, or nil.
    ///   - colors: The current theme's color palette.
    ///   - codeFont: The monospace font for code.
    func highlight(
        in attrStr: NSMutableAttributedString,
        contentRange: NSRange,
        language: String?,
        colors: ThemeColors,
        codeFont: PlatformFont
    ) {
        guard contentRange.length > 0 else { return }

        let normalizedLang = normalizeLanguage(language)
        guard let rules = highlightRules(for: normalizedLang) else {
            // Unknown language — plain monospace, no broken rendering (AC-3)
            return
        }

        let text = attrStr.string
        guard let swiftRange = Range(contentRange, in: text) else { return }
        let codeText = String(text[swiftRange])

        let tokens = tokenize(codeText, rules: rules)

        for token in tokens {
            // Offset token range to the content range within the full attributed string
            let absoluteRange = NSRange(
                location: contentRange.location + token.range.location,
                length: token.range.length
            )
            guard absoluteRange.location + absoluteRange.length <= attrStr.length else { continue }

            let color = color(for: token.type, colors: colors)
            attrStr.addAttribute(.foregroundColor, value: color, range: absoluteRange)
        }
    }

    // MARK: - Language Normalization

    /// Maps common language aliases to canonical identifiers.
    private func normalizeLanguage(_ language: String?) -> String? {
        guard let lang = language?.lowercased().trimmingCharacters(in: .whitespaces) else {
            return nil
        }
        if lang.isEmpty { return nil }

        switch lang {
        case "python", "py", "python3":
            return "python"
        case "javascript", "js":
            return "javascript"
        case "typescript", "ts":
            return "typescript"
        case "swift":
            return "swift"
        case "go", "golang":
            return "go"
        case "rust", "rs":
            return "rust"
        case "html":
            return "html"
        case "css":
            return "css"
        case "json":
            return "json"
        case "yaml", "yml":
            return "yaml"
        case "sql":
            return "sql"
        case "bash", "sh", "shell", "zsh":
            return "bash"
        case "ruby", "rb":
            return "ruby"
        case "java":
            return "java"
        case "kotlin", "kt":
            return "kotlin"
        case "c":
            return "c"
        case "cpp", "c++", "cxx":
            return "cpp"
        case "php":
            return "php"
        case "objc", "objective-c", "objectivec":
            return "objc"
        default:
            return nil
        }
    }

    // MARK: - Token Color Mapping

    private func color(for tokenType: SyntaxTokenType, colors: ThemeColors) -> PlatformColor {
        switch tokenType {
        case .keyword:  return colors.syntaxKeyword
        case .string:   return colors.syntaxString
        case .comment:  return colors.syntaxComment
        case .number:   return colors.syntaxNumber
        case .type:     return colors.syntaxType
        case .function: return colors.syntaxFunction
        }
    }

    // MARK: - Tokenization

    /// Tokenizes code text using the given rules. Later rules do not override
    /// ranges already claimed by earlier rules (priority ordering).
    private func tokenize(_ code: String, rules: [HighlightRule]) -> [SyntaxToken] {
        let codeNS = code as NSString
        let fullRange = NSRange(location: 0, length: codeNS.length)
        var tokens: [SyntaxToken] = []
        var claimed = IndexSet()

        for rule in rules {
            let matches = rule.regex.matches(in: code, range: fullRange)
            for match in matches {
                let range = rule.captureGroup > 0 && rule.captureGroup < match.numberOfRanges
                    ? match.range(at: rule.captureGroup)
                    : match.range

                guard range.location != NSNotFound, range.length > 0 else { continue }

                // Skip if any part of this range is already claimed
                let tokenIndexRange = range.location..<(range.location + range.length)
                if claimed.intersects(integersIn: tokenIndexRange) { continue }

                claimed.insert(integersIn: tokenIndexRange)
                tokens.append(SyntaxToken(range: range, type: rule.tokenType))
            }
        }

        return tokens
    }

    // MARK: - Highlight Rules

    /// A single highlighting rule: a compiled regex mapped to a token type.
    private struct HighlightRule {
        let regex: NSRegularExpression
        let tokenType: SyntaxTokenType
        let captureGroup: Int

        init?(_ pattern: String, _ type: SyntaxTokenType, options: NSRegularExpression.Options = [], captureGroup: Int = 0) {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
                return nil
            }
            self.regex = compiled
            self.tokenType = type
            self.captureGroup = captureGroup
        }
    }

    /// Helper to build a rule array from optional rules, filtering any that failed to compile.
    private static func rules(_ items: HighlightRule?...) -> [HighlightRule] {
        items.compactMap { $0 }
    }

    /// Compiled rules per language, lazily cached.
    /// Thread safety: lock protects concurrent read/write from background render tasks.
    private static let ruleCacheLock = NSLock()
    nonisolated(unsafe) private static var ruleCache: [String: [HighlightRule]] = [:]

    /// Returns compiled highlight rules for a language, or nil if unsupported.
    private func highlightRules(for language: String?) -> [HighlightRule]? {
        guard let lang = language else { return nil }

        Self.ruleCacheLock.lock()
        if let cached = Self.ruleCache[lang] {
            Self.ruleCacheLock.unlock()
            return cached
        }
        Self.ruleCacheLock.unlock()

        let rules: [HighlightRule]?
        switch lang {
        case "python":    rules = pythonRules
        case "javascript": rules = javascriptRules
        case "typescript": rules = typescriptRules
        case "swift":     rules = swiftRules
        case "go":        rules = goRules
        case "rust":      rules = rustRules
        case "html":      rules = htmlRules
        case "css":       rules = cssRules
        case "json":      rules = jsonRules
        case "yaml":      rules = yamlRules
        case "sql":       rules = sqlRules
        case "bash":      rules = bashRules
        case "ruby":      rules = rubyRules
        case "java":      rules = javaRules
        case "kotlin":    rules = kotlinRules
        case "c":         rules = cRules
        case "cpp":       rules = cppRules
        case "php":       rules = phpRules
        case "objc":      rules = objcRules
        default:          rules = nil
        }

        if let rules {
            Self.ruleCacheLock.lock()
            Self.ruleCache[lang] = rules
            Self.ruleCacheLock.unlock()
        }
        return rules
    }

    // MARK: - Common Patterns

    // Comments must come first so they take priority over keywords inside comments.
    // These are force-unwrapped because they are compile-time-constant patterns
    // verified by tests. Using `!` here is safe and avoids optional chaining noise.
    private static let cLineComment = HighlightRule(#"//[^\n]*"#, .comment)!
    private static let cBlockComment = HighlightRule(#"/\*[\s\S]*?\*/"#, .comment, options: .dotMatchesLineSeparators)!
    private static let hashComment = HighlightRule(#"#[^\n]*"#, .comment)!
    private static let doubleQuoteString = HighlightRule(#""(?:[^"\\]|\\.)*""#, .string)!
    private static let singleQuoteString = HighlightRule(#"'(?:[^'\\]|\\.)*'"#, .string)!
    private static let backtickString = HighlightRule(#"`(?:[^`\\]|\\.)*`"#, .string)!
    private static let tripleDoubleQuoteString = HighlightRule(#"\"\"\"[\s\S]*?\"\"\""#, .string, options: .dotMatchesLineSeparators)!
    private static let number = HighlightRule(#"\b(?:0[xX][0-9a-fA-F_]+|0[oO][0-7_]+|0[bB][01_]+|\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?)\b"#, .number)!
    // Function calls: identifier followed by (
    private static let functionCall = HighlightRule(#"\b([a-zA-Z_]\w*)\s*\("#, .function, captureGroup: 1)!

    // MARK: - Language-Specific Rules

    private var pythonRules: [HighlightRule] {
        Self.rules(
            Self.tripleDoubleQuoteString,
            HighlightRule(#"'''[\s\S]*?'''"#, .string, options: .dotMatchesLineSeparators),
            Self.hashComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:False|None|True|and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b"#, .keyword),
            HighlightRule(#"\b(?:int|float|str|bool|list|dict|tuple|set|bytes|type|object|Exception|ValueError|TypeError|KeyError|IndexError|RuntimeError|StopIteration)\b"#, .type)
        )
    }

    private var javascriptRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.backtickString,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:async|await|break|case|catch|class|const|continue|debugger|default|delete|do|else|export|extends|finally|for|function|if|import|in|instanceof|let|new|of|return|super|switch|this|throw|try|typeof|var|void|while|with|yield)\b"#, .keyword),
            HighlightRule(#"\b(?:Array|Boolean|Date|Error|Function|JSON|Map|Math|Number|Object|Promise|Proxy|RegExp|Set|String|Symbol|WeakMap|WeakSet|console|undefined|null|NaN|Infinity)\b"#, .type)
        )
    }

    private var typescriptRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.backtickString,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:abstract|as|async|await|break|case|catch|class|const|continue|debugger|declare|default|delete|do|else|enum|export|extends|finally|for|from|function|get|if|implements|import|in|instanceof|interface|keyof|let|module|namespace|new|of|override|private|protected|public|readonly|return|set|static|super|switch|this|throw|try|type|typeof|var|void|while|with|yield)\b"#, .keyword),
            HighlightRule(#"\b(?:any|bigint|boolean|never|null|number|object|string|symbol|undefined|unknown|void|Array|Date|Error|Function|Map|Object|Promise|Record|Set|Partial|Required|Readonly|Pick|Omit)\b"#, .type)
        )
    }

    private var swiftRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            HighlightRule(#"\"\"\"[\s\S]*?\"\"\""#, .string, options: .dotMatchesLineSeparators),
            Self.doubleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:actor|as|associatedtype|async|await|break|case|catch|class|continue|convenience|deinit|default|defer|do|dynamic|else|enum|extension|fallthrough|fileprivate|final|for|func|get|guard|if|import|in|indirect|infix|init|inout|internal|is|isolated|lazy|let|mutating|nonisolated|nonmutating|open|operator|optional|override|postfix|precedencegroup|prefix|private|protocol|public|repeat|required|rethrows|return|set|some|static|struct|subscript|super|switch|throw|throws|try|typealias|unowned|var|weak|where|while|willSet|didSet)\b"#, .keyword),
            HighlightRule(#"@\w+"#, .keyword),
            HighlightRule(#"\b(?:Any|AnyObject|Bool|Character|Double|Float|Int|Int8|Int16|Int32|Int64|Never|Optional|Self|String|UInt|UInt8|UInt16|UInt32|UInt64|Void|Array|Dictionary|Set|Result|Error|Codable|Equatable|Hashable|Identifiable|Sendable|Observable|MainActor)\b"#, .type)
        )
    }

    private var goRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.backtickString,
            Self.doubleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:break|case|chan|const|continue|default|defer|else|fallthrough|for|func|go|goto|if|import|interface|map|package|range|return|select|struct|switch|type|var)\b"#, .keyword),
            HighlightRule(#"\b(?:bool|byte|complex64|complex128|error|float32|float64|int|int8|int16|int32|int64|rune|string|uint|uint8|uint16|uint32|uint64|uintptr|nil|true|false|iota)\b"#, .type)
        )
    }

    private var rustRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:as|async|await|break|const|continue|crate|dyn|else|enum|extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|pub|ref|return|self|Self|static|struct|super|trait|true|type|unsafe|use|where|while|yield)\b"#, .keyword),
            HighlightRule(#"\b(?:bool|char|f32|f64|i8|i16|i32|i64|i128|isize|str|u8|u16|u32|u64|u128|usize|Box|String|Vec|Option|Result|Some|None|Ok|Err)\b"#, .type)
        )
    }

    private var htmlRules: [HighlightRule] {
        Self.rules(
            HighlightRule(#"<!--[\s\S]*?-->"#, .comment, options: .dotMatchesLineSeparators),
            Self.doubleQuoteString,
            Self.singleQuoteString,
            HighlightRule(#"</?[a-zA-Z][\w-]*"#, .keyword),
            HighlightRule(#"/?\s*>"#, .keyword),
            HighlightRule(#"\b[a-zA-Z-]+(?=\s*=)"#, .function)
        )
    }

    private var cssRules: [HighlightRule] {
        Self.rules(
            Self.cBlockComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            HighlightRule(#"#[0-9a-fA-F]{3,8}\b"#, .number),
            HighlightRule(#"[.#][\w-]+"#, .keyword),
            HighlightRule(#"\b(?:important|inherit|initial|unset|none|auto|block|flex|grid|inline|relative|absolute|fixed|sticky)\b"#, .keyword),
            HighlightRule(#"[\w-]+(?=\s*:)"#, .function),
            HighlightRule(#"\b(?:px|em|rem|vh|vw|%|s|ms|deg|fr)\b"#, .type)
        )
    }

    private var jsonRules: [HighlightRule] {
        Self.rules(
            HighlightRule(#""(?:[^"\\]|\\.)*"\s*(?=:)"#, .function),
            Self.doubleQuoteString,
            Self.number,
            HighlightRule(#"\b(?:true|false|null)\b"#, .keyword)
        )
    }

    private var yamlRules: [HighlightRule] {
        Self.rules(
            Self.hashComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            HighlightRule(#"^[\w.-]+(?=\s*:)"#, .function, options: .anchorsMatchLines),
            HighlightRule(#"\b(?:true|false|null|yes|no|on|off)\b"#, .keyword, options: .caseInsensitive)
        )
    }

    private var sqlRules: [HighlightRule] {
        Self.rules(
            HighlightRule(#"--[^\n]*"#, .comment),
            Self.cBlockComment,
            Self.singleQuoteString,
            Self.doubleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:SELECT|FROM|WHERE|INSERT|INTO|UPDATE|SET|DELETE|CREATE|DROP|ALTER|TABLE|INDEX|VIEW|JOIN|INNER|LEFT|RIGHT|OUTER|CROSS|ON|AND|OR|NOT|IN|EXISTS|BETWEEN|LIKE|IS|NULL|AS|ORDER|BY|GROUP|HAVING|LIMIT|OFFSET|UNION|ALL|DISTINCT|CASE|WHEN|THEN|ELSE|END|BEGIN|COMMIT|ROLLBACK|GRANT|REVOKE|PRIMARY|KEY|FOREIGN|REFERENCES|CONSTRAINT|DEFAULT|VALUES|COUNT|SUM|AVG|MIN|MAX|WITH|RECURSIVE)\b"#, .keyword, options: .caseInsensitive),
            HighlightRule(#"\b(?:INTEGER|INT|BIGINT|SMALLINT|FLOAT|DOUBLE|DECIMAL|NUMERIC|VARCHAR|CHAR|TEXT|BLOB|DATE|TIMESTAMP|BOOLEAN|SERIAL|UUID)\b"#, .type, options: .caseInsensitive)
        )
    }

    private var bashRules: [HighlightRule] {
        Self.rules(
            Self.hashComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\$\{?[\w@#?$!-]+\}?"#, .type),
            HighlightRule(#"\b(?:if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|local|export|readonly|declare|typeset|unset|shift|break|continue|exit|trap|source|eval|exec)\b"#, .keyword),
            HighlightRule(#"\b(?:echo|printf|cd|ls|cp|mv|rm|mkdir|rmdir|cat|grep|sed|awk|find|sort|uniq|wc|head|tail|chmod|chown|curl|wget|tar|gzip|ssh|git|docker|make|test)\b"#, .function)
        )
    }

    private var rubyRules: [HighlightRule] {
        Self.rules(
            Self.hashComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:alias|and|begin|break|case|class|def|defined\?|do|else|elsif|end|ensure|false|for|if|in|module|next|nil|not|or|redo|rescue|retry|return|self|super|then|true|undef|unless|until|when|while|yield)\b"#, .keyword),
            HighlightRule(#":[a-zA-Z_]\w*"#, .string),
            HighlightRule(#"\b[A-Z]\w*\b"#, .type)
        )
    }

    private var javaRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:abstract|assert|break|case|catch|class|const|continue|default|do|else|enum|extends|final|finally|for|goto|if|implements|import|instanceof|interface|native|new|package|private|protected|public|return|static|strictfp|super|switch|synchronized|this|throw|throws|transient|try|void|volatile|while)\b"#, .keyword),
            HighlightRule(#"@\w+"#, .keyword),
            HighlightRule(#"\b(?:boolean|byte|char|double|float|int|long|short|var|null|true|false|String|Integer|Long|Double|Float|Boolean|Object|List|Map|Set|ArrayList|HashMap|Optional|Stream|Exception|Throwable)\b"#, .type)
        )
    }

    private var kotlinRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            HighlightRule(#"\"\"\"[\s\S]*?\"\"\""#, .string, options: .dotMatchesLineSeparators),
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\b(?:abstract|actual|annotation|as|break|by|catch|class|companion|const|constructor|continue|crossinline|data|delegate|do|dynamic|else|enum|expect|external|final|finally|for|fun|get|if|import|in|infix|init|inline|inner|interface|internal|is|lateinit|noinline|object|open|operator|out|override|package|private|protected|public|reified|return|sealed|set|super|suspend|tailrec|this|throw|try|typealias|val|var|vararg|when|where|while|yield)\b"#, .keyword),
            HighlightRule(#"\b(?:Any|Boolean|Byte|Char|Double|Float|Int|Long|Nothing|Short|String|Unit|Array|List|Map|MutableList|MutableMap|Set|Pair|Triple|null|true|false)\b"#, .type)
        )
    }

    private var cRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"#\s*(?:include|define|undef|ifdef|ifndef|if|elif|else|endif|pragma|error|warning)\b[^\n]*"#, .keyword),
            HighlightRule(#"\b(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while|_Bool|_Complex|_Imaginary)\b"#, .keyword),
            HighlightRule(#"\b(?:NULL|EOF|stdin|stdout|stderr|size_t|ptrdiff_t|FILE|true|false)\b"#, .type)
        )
    }

    private var cppRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"#\s*(?:include|define|undef|ifdef|ifndef|if|elif|else|endif|pragma|error|warning)\b[^\n]*"#, .keyword),
            HighlightRule(#"\b(?:alignas|alignof|and|and_eq|asm|auto|bitand|bitor|bool|break|case|catch|char|char8_t|char16_t|char32_t|class|compl|concept|const|consteval|constexpr|constinit|const_cast|continue|co_await|co_return|co_yield|decltype|default|delete|do|double|dynamic_cast|else|enum|explicit|export|extern|false|float|for|friend|goto|if|inline|int|long|mutable|namespace|new|noexcept|not|not_eq|nullptr|operator|or|or_eq|private|protected|public|register|reinterpret_cast|requires|return|short|signed|sizeof|static|static_assert|static_cast|struct|switch|template|this|thread_local|throw|true|try|typedef|typeid|typename|union|unsigned|using|virtual|void|volatile|wchar_t|while|xor|xor_eq)\b"#, .keyword),
            HighlightRule(#"\b(?:string|vector|map|set|unordered_map|unordered_set|array|deque|list|queue|stack|pair|tuple|optional|variant|any|shared_ptr|unique_ptr|weak_ptr|size_t|nullptr_t|std)\b"#, .type)
        )
    }

    private var phpRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            Self.hashComment,
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"\$[a-zA-Z_]\w*"#, .type),
            HighlightRule(#"\b(?:abstract|and|as|break|callable|case|catch|class|clone|const|continue|declare|default|do|echo|else|elseif|empty|enddeclare|endfor|endforeach|endif|endswitch|endwhile|enum|extends|final|finally|fn|for|foreach|function|global|goto|if|implements|include|include_once|instanceof|insteadof|interface|isset|list|match|namespace|new|or|print|private|protected|public|readonly|require|require_once|return|static|switch|this|throw|trait|try|unset|use|var|while|xor|yield)\b"#, .keyword),
            HighlightRule(#"\b(?:array|bool|float|int|mixed|null|object|string|void|false|true|self|parent|iterable|never)\b"#, .type)
        )
    }

    private var objcRules: [HighlightRule] {
        Self.rules(
            Self.cLineComment,
            Self.cBlockComment,
            HighlightRule(#"@"(?:[^"\\]|\\.)*""#, .string),
            Self.doubleQuoteString,
            Self.singleQuoteString,
            Self.number,
            Self.functionCall,
            HighlightRule(#"#\s*(?:include|import|define|undef|ifdef|ifndef|if|elif|else|endif|pragma)\b[^\n]*"#, .keyword),
            HighlightRule(#"\b(?:auto|break|case|char|const|continue|default|do|double|else|enum|extern|float|for|goto|if|inline|int|long|register|restrict|return|short|signed|sizeof|static|struct|switch|typedef|union|unsigned|void|volatile|while)\b"#, .keyword),
            HighlightRule(#"@(?:interface|implementation|end|protocol|property|synthesize|dynamic|class|public|private|protected|try|catch|throw|finally|autoreleasepool|selector|encode|synchronized|optional|required)\b"#, .keyword),
            HighlightRule(#"\b(?:BOOL|YES|NO|nil|NULL|id|SEL|IMP|Class|NSObject|NSString|NSArray|NSDictionary|NSNumber|NSInteger|NSUInteger|CGFloat|CGRect|CGPoint|CGSize)\b"#, .type)
        )
    }
}
