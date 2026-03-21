/// Tests for SPIKE-007: tree-sitter syntax highlighting prototype.
///
/// Validates tree-sitter integration for Swift, Python, and JavaScript.
/// Includes parse correctness, highlight query output, and performance benchmarks.

import XCTest
@testable import EMEditor
import SwiftTreeSitter

@MainActor
final class TreeSitterHighlighterTests: XCTestCase {

    private let highlighter = TreeSitterHighlighter()

    // MARK: - Language Configuration

    func testSwiftLanguageConfigLoads() {
        let config = highlighter.languageConfig(for: "swift")
        XCTAssertNotNil(config, "Swift language config should load")
    }

    func testPythonLanguageConfigLoads() {
        let config = highlighter.languageConfig(for: "python")
        XCTAssertNotNil(config, "Python language config should load")
    }

    func testJavaScriptLanguageConfigLoads() {
        let config = highlighter.languageConfig(for: "javascript")
        XCTAssertNotNil(config, "JavaScript language config should load")
    }

    func testUnsupportedLanguageReturnsNil() {
        let config = highlighter.languageConfig(for: "haskell")
        XCTAssertNil(config, "Unsupported language should return nil")
    }

    // MARK: - Tokenization

    func testSwiftTokenization() {
        let code = """
        func greet(_ name: String) -> String {
            let message = "Hello, \\(name)!"
            return message
        }
        """
        let config = highlighter.languageConfig(for: "swift")!
        let tokens = highlighter.tokenize(code, language: "swift", config: config)

        XCTAssertFalse(tokens.isEmpty, "Swift tokenization should produce tokens")

        let tokenTypes = Set(tokens.map(\.type))
        XCTAssertTrue(tokenTypes.contains(.keyword), "Should detect keywords (func, let, return)")
        XCTAssertTrue(tokenTypes.contains(.string), "Should detect strings")
    }

    func testPythonTokenization() {
        let code = """
        def fibonacci(n):
            if n <= 1:
                return n
            return fibonacci(n - 1) + fibonacci(n - 2)
        """
        let config = highlighter.languageConfig(for: "python")!
        let tokens = highlighter.tokenize(code, language: "python", config: config)

        XCTAssertFalse(tokens.isEmpty, "Python tokenization should produce tokens")

        let tokenTypes = Set(tokens.map(\.type))
        XCTAssertTrue(tokenTypes.contains(.keyword), "Should detect keywords (def, if, return)")
        XCTAssertTrue(tokenTypes.contains(.number), "Should detect numbers")
    }

    func testJavaScriptTokenization() {
        let code = """
        async function fetchData(url) {
            const response = await fetch(url);
            const data = await response.json();
            return data;
        }
        """
        let config = highlighter.languageConfig(for: "javascript")!
        let tokens = highlighter.tokenize(code, language: "javascript", config: config)

        XCTAssertFalse(tokens.isEmpty, "JavaScript tokenization should produce tokens")

        let tokenTypes = Set(tokens.map(\.type))
        XCTAssertTrue(tokenTypes.contains(.keyword), "Should detect keywords (async, function, const)")
    }

    func testEmptyCodeProducesNoTokens() {
        let config = highlighter.languageConfig(for: "swift")!
        let tokens = highlighter.tokenize("", language: "swift", config: config)
        XCTAssertTrue(tokens.isEmpty, "Empty code should produce no tokens")
    }

    func testCommentDetection() {
        let code = """
        // This is a comment
        /* Block comment */
        let x = 42
        """
        let config = highlighter.languageConfig(for: "swift")!
        let tokens = highlighter.tokenize(code, language: "swift", config: config)

        let commentTokens = tokens.filter { $0.type == .comment }
        XCTAssertFalse(commentTokens.isEmpty, "Should detect comments")
    }

    // MARK: - Performance Benchmarks (SPIKE-007 AC)

    func testBenchmarkSwift500Lines() {
        let code = generate500LineSwift()
        let result = highlighter.benchmark(code: code, language: "swift")

        XCTAssertNotNil(result, "Swift benchmark should succeed")
        if let result {
            print("═══ SPIKE-007 BENCHMARK: Swift ═══")
            print("Lines: \(result.codeLines)")
            print("Cold parse: \(String(format: "%.2f", result.coldParseMs)) ms")
            print("Warm parse avg (\(result.iterations) iterations): \(String(format: "%.2f", result.warmParseAvgMs)) ms")
            print("Highlight query: \(String(format: "%.2f", result.highlightQueryMs)) ms")
            print("Total highlight: \(String(format: "%.2f", result.totalHighlightMs)) ms")
            print("Token count: \(result.tokenCount)")
            print("═══════════════════════════════════")
        }
    }

    func testBenchmarkPython500Lines() {
        let code = generate500LinePython()
        let result = highlighter.benchmark(code: code, language: "python")

        XCTAssertNotNil(result, "Python benchmark should succeed")
        if let result {
            print("═══ SPIKE-007 BENCHMARK: Python ═══")
            print("Lines: \(result.codeLines)")
            print("Cold parse: \(String(format: "%.2f", result.coldParseMs)) ms")
            print("Warm parse avg (\(result.iterations) iterations): \(String(format: "%.2f", result.warmParseAvgMs)) ms")
            print("Highlight query: \(String(format: "%.2f", result.highlightQueryMs)) ms")
            print("Total highlight: \(String(format: "%.2f", result.totalHighlightMs)) ms")
            print("Token count: \(result.tokenCount)")
            print("════════════════════════════════════")
        }
    }

    func testBenchmarkJavaScript500Lines() {
        let code = generate500LineJavaScript()
        let result = highlighter.benchmark(code: code, language: "javascript")

        XCTAssertNotNil(result, "JavaScript benchmark should succeed")
        if let result {
            print("═══ SPIKE-007 BENCHMARK: JavaScript ═══")
            print("Lines: \(result.codeLines)")
            print("Cold parse: \(String(format: "%.2f", result.coldParseMs)) ms")
            print("Warm parse avg (\(result.iterations) iterations): \(String(format: "%.2f", result.warmParseAvgMs)) ms")
            print("Highlight query: \(String(format: "%.2f", result.highlightQueryMs)) ms")
            print("Total highlight: \(String(format: "%.2f", result.totalHighlightMs)) ms")
            print("Token count: \(result.tokenCount)")
            print("════════════════════════════════════════")
        }
    }

    // MARK: - Code Generators

    /// Generates a realistic ~500-line Swift code block for benchmarking.
    private func generate500LineSwift() -> String {
        var lines: [String] = []
        lines.append("import Foundation")
        lines.append("import UIKit")
        lines.append("")

        // Generate structs, enums, classes with methods
        for i in 0..<10 {
            lines.append("/// A model representing item \(i).")
            lines.append("struct Item\(i): Codable, Hashable, Identifiable {")
            lines.append("    let id: UUID")
            lines.append("    let name: String")
            lines.append("    let value: Double")
            lines.append("    var isActive: Bool")
            lines.append("    let createdAt: Date")
            lines.append("")
            lines.append("    func formatted() -> String {")
            lines.append("        return \"\\(name): \\(value)\"")
            lines.append("    }")
            lines.append("")
            lines.append("    mutating func toggle() {")
            lines.append("        isActive = !isActive")
            lines.append("    }")
            lines.append("")
            lines.append("    static func random() -> Item\(i) {")
            lines.append("        Item\(i)(")
            lines.append("            id: UUID(),")
            lines.append("            name: \"Item \\(Int.random(in: 0...999))\",")
            lines.append("            value: Double.random(in: 0...100),")
            lines.append("            isActive: Bool.random(),")
            lines.append("            createdAt: Date()")
            lines.append("        )")
            lines.append("    }")
            lines.append("}")
            lines.append("")
        }

        // Add an enum
        lines.append("enum Status: String, CaseIterable {")
        lines.append("    case active = \"active\"")
        lines.append("    case inactive = \"inactive\"")
        lines.append("    case pending = \"pending\"")
        lines.append("")
        lines.append("    var displayName: String {")
        lines.append("        switch self {")
        lines.append("        case .active: return \"Active\"")
        lines.append("        case .inactive: return \"Inactive\"")
        lines.append("        case .pending: return \"Pending\"")
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        lines.append("")

        // Add functions with control flow
        for i in 0..<15 {
            lines.append("/// Processes batch \(i).")
            lines.append("func processBatch\(i)(items: [String], threshold: Int) -> [String] {")
            lines.append("    var results: [String] = []")
            lines.append("    for item in items {")
            lines.append("        guard item.count > threshold else { continue }")
            lines.append("        let processed = item.uppercased()")
            lines.append("        if processed.hasPrefix(\"A\") {")
            lines.append("            results.append(processed + \" [priority]\")")
            lines.append("        } else {")
            lines.append("            results.append(processed)")
            lines.append("        }")
            lines.append("    }")
            lines.append("    return results.sorted()")
            lines.append("}")
            lines.append("")
        }

        // Pad to ~500 lines
        while lines.count < 500 {
            let idx = lines.count
            lines.append("// Line \(idx): additional code for benchmark sizing")
            lines.append("let constant\(idx) = \(idx) * 42")
        }

        return lines.joined(separator: "\n")
    }

    /// Generates a realistic ~500-line Python code block for benchmarking.
    private func generate500LinePython() -> String {
        var lines: [String] = []
        lines.append("import os")
        lines.append("import sys")
        lines.append("from typing import List, Dict, Optional")
        lines.append("from dataclasses import dataclass")
        lines.append("")

        for i in 0..<10 {
            lines.append("@dataclass")
            lines.append("class Model\(i):")
            lines.append("    \"\"\"A model representing entity \(i).\"\"\"")
            lines.append("    name: str")
            lines.append("    value: float")
            lines.append("    active: bool = True")
            lines.append("")
            lines.append("    def formatted(self) -> str:")
            lines.append("        return f\"{self.name}: {self.value}\"")
            lines.append("")
            lines.append("    def toggle(self) -> None:")
            lines.append("        self.active = not self.active")
            lines.append("")
            lines.append("    @classmethod")
            lines.append("    def create(cls, name: str) -> 'Model\(i)':")
            lines.append("        return cls(name=name, value=0.0)")
            lines.append("")
        }

        for i in 0..<20 {
            lines.append("def process_batch_\(i)(items: List[str], threshold: int = 3) -> List[str]:")
            lines.append("    \"\"\"Process batch \(i) of items.\"\"\"")
            lines.append("    results = []")
            lines.append("    for item in items:")
            lines.append("        if len(item) <= threshold:")
            lines.append("            continue")
            lines.append("        processed = item.upper()")
            lines.append("        if processed.startswith('A'):")
            lines.append("            results.append(f\"{processed} [priority]\")")
            lines.append("        else:")
            lines.append("            results.append(processed)")
            lines.append("    return sorted(results)")
            lines.append("")
        }

        while lines.count < 500 {
            let idx = lines.count
            lines.append("# Line \(idx): additional code")
            lines.append("CONSTANT_\(idx) = \(idx) * 42")
        }

        return lines.joined(separator: "\n")
    }

    /// Generates a realistic ~500-line JavaScript code block for benchmarking.
    private func generate500LineJavaScript() -> String {
        var lines: [String] = []
        lines.append("'use strict';")
        lines.append("")
        lines.append("const http = require('http');")
        lines.append("const fs = require('fs');")
        lines.append("")

        for i in 0..<10 {
            lines.append("/**")
            lines.append(" * Class representing entity \(i).")
            lines.append(" */")
            lines.append("class Model\(i) {")
            lines.append("    constructor(name, value) {")
            lines.append("        this.name = name;")
            lines.append("        this.value = value;")
            lines.append("        this.active = true;")
            lines.append("    }")
            lines.append("")
            lines.append("    formatted() {")
            lines.append("        return `${this.name}: ${this.value}`;")
            lines.append("    }")
            lines.append("")
            lines.append("    toggle() {")
            lines.append("        this.active = !this.active;")
            lines.append("    }")
            lines.append("")
            lines.append("    static create(name) {")
            lines.append("        return new Model\(i)(name, 0);")
            lines.append("    }")
            lines.append("}")
            lines.append("")
        }

        for i in 0..<15 {
            lines.append("/**")
            lines.append(" * Process batch \(i).")
            lines.append(" */")
            lines.append("async function processBatch\(i)(items, threshold = 3) {")
            lines.append("    const results = [];")
            lines.append("    for (const item of items) {")
            lines.append("        if (item.length <= threshold) continue;")
            lines.append("        const processed = item.toUpperCase();")
            lines.append("        if (processed.startsWith('A')) {")
            lines.append("            results.push(`${processed} [priority]`);")
            lines.append("        } else {")
            lines.append("            results.push(processed);")
            lines.append("        }")
            lines.append("    }")
            lines.append("    return results.sort();")
            lines.append("}")
            lines.append("")
        }

        while lines.count < 500 {
            let idx = lines.count
            lines.append("// Line \(idx): additional code")
            lines.append("const CONSTANT_\(idx) = \(idx) * 42;")
        }

        return lines.joined(separator: "\n")
    }
}
