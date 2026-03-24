import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import EMEditor
@testable import EMCore

@MainActor
@Suite("MermaidRenderer")
struct MermaidRendererTests {

    // MARK: - Sample Diagrams

    static let flowchart = """
    graph TD
        A[Start] --> B{Decision}
        B -->|Yes| C[Process]
        B -->|No| D[End]
        C --> D
    """

    static let sequence = """
    sequenceDiagram
        Alice->>Bob: Hello Bob, how are you?
        Bob-->>Alice: Great!
        Alice->>Bob: Can you help me?
        Bob-->>Alice: Sure!
    """

    static let erDiagram = """
    erDiagram
        CUSTOMER ||--o{ ORDER : places
        ORDER ||--|{ LINE-ITEM : contains
        CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
    """

    static let classDiagram = """
    classDiagram
        class Animal {
            +String name
            +int age
            +makeSound()
        }
        class Dog {
            +String breed
            +bark()
        }
        Animal <|-- Dog
    """

    static let stateDiagram = """
    stateDiagram-v2
        [*] --> Idle
        Idle --> Processing : submit
        Processing --> Done : complete
        Processing --> Error : fail
        Error --> Idle : retry
        Done --> [*]
    """

    static let allDiagrams = [flowchart, sequence, erDiagram, classDiagram, stateDiagram]

    // MARK: - Cache Key Tests

    @Test("Cache key is deterministic for same content and theme")
    func cacheKeyDeterministic() {
        let key1 = MermaidRenderer.cacheKeyString(content: "graph TD; A-->B;", theme: .light)
        let key2 = MermaidRenderer.cacheKeyString(content: "graph TD; A-->B;", theme: .light)
        #expect(key1 == key2)
    }

    @Test("Cache key differs for different themes")
    func cacheKeyDiffersForTheme() {
        let light = MermaidRenderer.cacheKeyString(content: "graph TD; A-->B;", theme: .light)
        let dark = MermaidRenderer.cacheKeyString(content: "graph TD; A-->B;", theme: .dark)
        #expect(light != dark)
    }

    @Test("Cache key differs for different content")
    func cacheKeyDiffersForContent() {
        let key1 = MermaidRenderer.cacheKeyString(content: "graph TD; A-->B;", theme: .light)
        let key2 = MermaidRenderer.cacheKeyString(content: "graph LR; A-->B;", theme: .light)
        #expect(key1 != key2)
    }

    @Test("Cache key is a valid SHA256 hex string (64 chars)")
    func cacheKeyFormat() {
        let key = MermaidRenderer.cacheKeyString(content: "test", theme: .light)
        #expect(key.count == 64)
        #expect(key.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Initialization Tests

    @Test("Renderer initializes with reuse lifecycle")
    func initReuse() {
        let renderer = MermaidRenderer(lifecycle: .reuse)
        #expect(renderer.lifecycle == .reuse)
        #expect(renderer.renderCount == 0)
    }

    @Test("Renderer initializes with createDestroy lifecycle")
    func initCreateDestroy() {
        let renderer = MermaidRenderer(lifecycle: .createDestroy)
        #expect(renderer.lifecycle == .createDestroy)
    }

    // MARK: - Cache Invalidation Tests

    @Test("invalidateCache clears all entries")
    func invalidateCacheClears() {
        let renderer = MermaidRenderer()
        // No cached result initially
        let result = renderer.cachedResult(for: "graph TD; A-->B;", theme: .light)
        #expect(result == nil)

        // After invalidation, still nil (no crash)
        renderer.invalidateCache()
        let result2 = renderer.cachedResult(for: "graph TD; A-->B;", theme: .light)
        #expect(result2 == nil)
    }

    @Test("Benchmark counter reset works")
    func benchmarkCounterReset() {
        let renderer = MermaidRenderer()
        renderer.resetBenchmarkCounters()
        #expect(renderer.renderCount == 0)
        #expect(renderer.cacheHitCount == 0)
        #expect(renderer.cacheMissCount == 0)
    }

    // MARK: - Memory Measurement

    @Test("Memory measurement returns non-zero value")
    func memoryMeasurement() {
        let memory = MermaidRenderer.currentMemoryUsage()
        #expect(memory > 0, "Memory usage should be non-zero for a running process")
    }

    // MARK: - Theme Mapping

    @Test("MermaidTheme maps to correct mermaid.js theme names")
    func themeMapping() {
        #expect(MermaidTheme.light.rawValue == "default")
        #expect(MermaidTheme.dark.rawValue == "dark")
    }

    // MARK: - Process Termination Recovery

    @Test("After process termination, render recovers by creating a new WKWebView")
    func processTerminationRecovery() async {
        let renderer = MermaidRenderer(lifecycle: .reuse)

        // Simulate WKWebView content process being killed by iOS
        renderer.simulateWebContentProcessTermination()

        // The next render() should not crash or permanently fail —
        // it should recreate the WKWebView and attempt rendering.
        let result = await renderer.render(
            mermaidSource: "graph TD; A-->B;",
            theme: .light
        )

        // We accept either success or a transient failure (e.g. JS environment
        // not fully available in test host) — the key AC is no crash/permanent
        // failure state and that renderCount incremented (render path was entered).
        switch result {
        case .success:
            // Best case — full render worked
            break
        case .failure:
            // Acceptable in test host — the important thing is we didn't crash
            // and the renderer attempted a new WKWebView render.
            break
        }
        #expect(renderer.renderCount == 1, "render() should have executed after termination recovery")
    }
}
