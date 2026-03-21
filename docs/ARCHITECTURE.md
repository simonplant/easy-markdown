# easy-markdown — Architecture Document

This document is the technical governance for easy-markdown. It tells the developer agent (and any human contributor): **what framework to use, where code goes, what patterns to follow, and what rules are non-negotiable.**

**Relationship to PRODUCT.md**: PRODUCT.md defines *what* we build and *why*. This document defines *how* and *with what*. Every architectural decision here traces back to a product decision `[D-XXX]` or design principle `DP-X` in PRODUCT.md.

**Decision convention**: Architectural decisions use `[A-XXX]` IDs. Product decisions are cross-referenced as `[D-XXX]`. Items requiring prototyping before implementation are marked `[RESEARCH-needed]` — each has a corresponding `SPIKE-XXX` backlog entry that must complete before dependent features can be implemented.

**Living document**: Update this file when architectural decisions change. If a decision here conflicts with PRODUCT.md, PRODUCT.md wins — update this document to match.

---

## 1. Technology Stack

Concrete technology choices with rationale and product decision traceability.

### Project Structure

**[A-001]** Use Swift Package Manager (SPM) with a modular workspace structure. Per `[D-PLAT-2]`: SwiftUI for all UI on Apple platforms, Swift for core logic.

```
EasyMarkdown.xcworkspace
├── Package.swift          — Root package manifest, defines all modules
├── EMCore/                — Shared types, protocols, errors, typography
├── EMParser/              — Markdown parser wrapper, AST types
├── EMFormatter/           — Auto-formatting rules engine
├── EMDoctor/              — Document doctor rules and diagnostics
├── EMEditor/              — TextKit 2 text view, rendering, The Render
├── EMFile/                — File coordination, bookmarks, auto-save
├── EMAI/                  — AI provider protocol, all provider implementations
├── EMCloud/               — StoreKit 2 purchases, subscription management
├── EMGit/                 — Git operations, GitHub auth, clone/pull/commit/push (Phase 2)
├── EMSettings/            — Settings model, UserDefaults persistence, counters
├── EMApp/                 — SwiftUI app shell, navigation, scenes, error presentation
└── Tests/                 — Test targets per package
```

**Rationale**: SPM packages enforce dependency boundaries at compile time. Each module has a clear responsibility. No circular dependencies possible — the compiler catches violations.

### Minimum Deployment

**[A-002]** iOS 17+ per `[D-PLAT-3]`. macOS 14+ (Sonoma) for Phase 2 per `[D-PLAT-1]`.

### Markdown Parser

**[A-003]** Use Apple's `swift-markdown` package (wraps cmark-gfm). Provides CommonMark + GFM parsing per `[D-MD-1]`. Produces a strongly-typed Swift AST with visitor pattern.

`[RESEARCH-complete]` **SPIKE-002**: Round-trip fidelity validated. Structural fidelity is 100% — parse → format → re-parse always produces an identical AST. `MarkupRewriter` enables targeted AST modifications (heading level, link URL, checkbox state, code language, paragraph text) with surrounding structure preserved. `MarkupFormatter` normalizes syntax (setext → ATX headings, `_em_` → `*em*`, etc.) but all normalizations are purely cosmetic. Acceptable for auto-formatting and AI operations. See `docs/spikes/SPIKE-002.md` for full results.

`[RESEARCH-needed]` **SPIKE-003**: Evaluate incremental parsing capability. `swift-markdown` currently re-parses the full document. For large files, we may need a strategy to debounce re-parses and apply lightweight local updates between full parses. Design a workaround if full incremental parsing is not feasible.

**Alternatives considered**: cmark-gfm direct C binding (lower-level, less Swift-idiomatic), custom parser (too much investment), tree-sitter markdown (better incremental but weaker GFM support).

### Text Engine

**[A-004]** TextKit 2 with `NSTextLayoutManager` and `NSTextContentStorage`. Use `UITextView` (iOS) / `NSTextView` (macOS) as the hosting view. Per `[D-PERF-2]`: <16ms keystroke-to-render.

`[RESEARCH-complete]` **SPIKE-001**: TextKit 2 keystroke latency validated. Benchmark on iPhone 15 (p95: 6.8ms) and iPhone SE 3rd gen (p95: 10.3ms) confirms <16ms target is met with per-paragraph attributed string updates. No TextKit 1 fallback needed. See `docs/spikes/SPIKE-001.md` for full results.

**Rationale**: TextKit 2 is Apple's modern text layout system, designed for performance with large documents. It supports custom `NSTextLayoutFragment` subclasses for block-level rendering (code blocks, tables, diagrams). Required for 120fps scroll per `[D-PERF-3]`.

### Syntax Highlighting

**[A-005]** Use tree-sitter for syntax highlighting of fenced code blocks. Tree-sitter provides incremental parsing and supports all 15+ required languages per F-006.

`[RESEARCH-complete]` **SPIKE-007** ✅: `swift-tree-sitter` (v0.9.0+) validated. SPM-compatible, iOS 12+/macOS 10.13+. Binary size: ~1.8 MB for 3 grammars, ~6.6 MB for 18 grammars (acceptable). Parse+highlight performance: ~1-2.5 ms for 500-line blocks (well under 16ms budget). Incremental re-parsing supported for sub-millisecond edits. Highlighting accuracy significantly better than regex for nested constructs (string interpolation, generics). Grammars maintained upstream. See `docs/spikes/SPIKE-007.md`.

**Fallback**: Regex-based `SyntaxHighlighter` retained as fallback for languages without tree-sitter grammars.

### Mermaid Rendering

**[A-006]** Render Mermaid diagrams using `mermaid.js` in an offscreen `WKWebView`. Capture the rendered SVG, convert to a cached `UIImage` / `NSImage`, and display as a text attachment in the editor. Per `[D-MD-2]`: Mermaid rendering is P1, core to AI-generated markdown.

`[RESEARCH-complete]` **SPIKE-006** ✅: Offscreen WKWebView validated. Hybrid reuse lifecycle recommended: ~30 MB for 10 diagrams (18 MB WKWebView + 12 MB cached images). Render latency 180–220 ms (warm, within 500 ms budget). Cache keyed by SHA256(theme + content). See `docs/spikes/SPIKE-006.md`.

**Rendering pipeline**:
1. Parser identifies fenced code block with `mermaid` info string
2. Content hash checked against render cache
3. Cache miss → offscreen `WKWebView` renders SVG → rasterize to image at appropriate scale
4. Image stored in in-memory cache keyed by content hash
5. `NSTextAttachment` displays cached image inline
6. Theme change invalidates all cached renders

### AI Abstraction Layer

**[A-007]** Define an `AIProvider` protocol in EMAI that abstracts all AI inference. Three concrete providers. Per `[D-AI-1]`: local-first, cloud opt-in.

**Design strategy — platform-first**: Assume Apple will ship system-level AI capabilities (on-device LLM APIs, similar to how they ship speech recognition). Design the abstraction layer so that an `ApplePlatformAIProvider` can be implemented with minimal friction when/if those APIs become available. Don't overinvest in custom model management — it may become a platform feature.

Provider implementations:
1. **`ApplePlatformAIProvider`** — Future: wraps Apple's system AI when available. Highest priority at runtime (if present).
2. **`LocalModelProvider`** — Interim: our own on-device model via MLX Swift. Fills the gap until platform AI ships. Per `[D-AI-5]`: A16+/M1+ minimum.
3. **`CloudAPIProvider`** — Pro AI: `URLSession` + SSE streaming to our lightweight relay server. Per `[D-AI-7]`, `[D-AI-8]`.

**Provider selection at runtime**: Check availability in order: platform AI → local model → cloud (if subscribed and user opted in). User always controls cloud opt-in. Subscription status is provided to EMAI via the `SubscriptionStatus` protocol defined in EMCore (see §6 for details).

### AI Inference (Local, Interim)

**[A-008]** Use **MLX Swift** for on-device inference. Per `[D-AI-5]` and `[D-AI-9]`. Model size: 1–4GB quantized. Recommended initial model: Qwen2.5-3B-Instruct (Q4_K_M).

`[RESEARCH-complete]` **SPIKE-005**: MLX Swift selected over Core ML. First token 380ms on A16 (vs 620ms Core ML), 12.4 t/s (vs 8.1). Memory-mapped loading keeps resident memory at ~42 MB for a 3B model (vs 1,850 MB Core ML). App Store compliant. Device capability detection validated. See `docs/spikes/SPIKE-005.md`.

`[RESEARCH-needed]` **SPIKE-008**: Evaluate Apple platform AI APIs after WWDC 2026. If on-device writing assistance APIs ship, prototype `ApplePlatformAIProvider`. Scoped to WWDC 2026 evaluation window.

**Model download** (for `LocalModelProvider` only): Use Background Assets framework or On-Demand Resources (ODR) per `[D-AI-9]`. Wi-Fi default, cellular opt-in. Resumable downloads. This entire subsystem may become unnecessary if Apple ships platform AI.

### AI Inference (Cloud)

**[A-009]** `URLSession` with Server-Sent Events (SSE) streaming to a lightweight API relay. Per `[D-AI-7]`: use best-available cloud API (initially Anthropic Claude or equivalent). Per `[D-AI-8]`: only user-selected text sent, no retention.

The relay server validates the App Store subscription receipt (StoreKit 2 server-side verification), forwards the request to the AI provider, and streams the response back. It logs nothing — no prompts, no responses, no user data.

### State Management

**[A-010]** Use Swift's `@Observable` macro (iOS 17 Observation framework) for all state. Unidirectional data flow: state flows down, actions flow up. Per `[D-PLAT-3]`: iOS 17+ enables `@Observable`.

No Combine. No third-party reactive frameworks. `@Observable` + structured concurrency covers all state management needs.

### Persistence

**[A-011]** `UserDefaults` only. No database. No SQLite. No Core Data. No sidecar files. Per `DP-1` and `[D-NO-2]`.

What goes in UserDefaults:
- Security-scoped URL bookmarks (recents)
- User preferences (theme, font, toggle states)
- On-device aggregate counters per `[D-BIZ-6]`
- State restoration data (last file, cursor position)
- Model download state

### Purchases

**[A-012]** StoreKit 2 for all purchases. One-time app purchase ($9.99) per `[D-BIZ-2]`. Pro AI subscription ($3.99/mo or $29.99/yr) per `[D-BIZ-7]`. No proprietary account system per `[D-NO-9]`.

### Concurrency

**[A-013]** Swift structured concurrency only. `async/await`, `Task`, `TaskGroup`, `AsyncStream`, `AsyncSequence`. No Combine. No `DispatchQueue` for new code. No completion handlers.

`@MainActor` for all UI-bound types. Background work via `Task.detached` or dedicated actors.

### Third-Party Dependencies

**[A-014]** Minimize external dependencies. Current approved list:

| Dependency | Purpose | Package |
|-----------|---------|---------|
| `swift-markdown` | Markdown parser (CommonMark + GFM) | apple/swift-markdown |
| tree-sitter + grammars | Syntax highlighting for code blocks | `[RESEARCH-complete]` SPIKE-007 — `swift-tree-sitter` 0.9.0+, grammars via SPM |
| `mermaid.js` | Diagram rendering (bundled JS, not a Swift dep) | mermaid-js/mermaid |
| libgit2 (via SwiftGit2 or similar) | Git operations for GitHub storage (Phase 2) | `[RESEARCH-needed]` SPIKE-009 |

**Rule**: No third-party dependency may be added without an architecture decision record (`[A-XXX]`) documenting the rationale and alternatives. Per `DP-5`: simplicity is a feature.

---

## 2. Module Architecture

### Package Dependency Graph

```
EMApp ──────────┬─► EMEditor ──┬─► EMParser ──► EMCore
                │              ├─► EMFormatter ─┬─► EMParser
                │              │                └─► EMCore
                │              ├─► EMDoctor ────┬─► EMParser
                │              │                └─► EMCore
                │              └─► EMCore
                ├─► EMAI ──────►   EMCore
                ├─► EMCloud ───►   EMCore
                ├─► EMGit ─────►   EMFile ──► EMCore   (Phase 2)
                ├─► EMFile ────►   EMCore
                ├─► EMSettings ►   EMCore
                └─► EMCore
```

### Dependency Rules

**[A-015]** These rules are enforced by SPM package boundaries. Violating them causes a compile error.

| Package | May depend on | May NOT depend on |
|---------|--------------|-------------------|
| **EMCore** | Nothing (leaf) | Everything else |
| **EMParser** | EMCore | Everything else |
| **EMFormatter** | EMParser, EMCore | EMEditor, EMFile, EMAI, EMCloud, EMSettings, EMApp |
| **EMDoctor** | EMParser, EMCore | EMEditor, EMFile, EMAI, EMCloud, EMSettings, EMApp |
| **EMEditor** | EMParser, EMFormatter, EMDoctor, EMCore | EMFile, EMAI, EMCloud, EMSettings, EMApp |
| **EMFile** | EMCore | EMParser, EMFormatter, EMDoctor, EMEditor, EMAI, EMCloud, EMSettings, EMApp |
| **EMAI** | EMCore | EMParser, EMFormatter, EMDoctor, EMEditor, EMFile, EMCloud, EMSettings, EMApp |
| **EMCloud** | EMCore | EMParser, EMFormatter, EMDoctor, EMEditor, EMFile, EMAI, EMGit, EMSettings, EMApp |
| **EMGit** | EMFile, EMCore | EMParser, EMFormatter, EMDoctor, EMEditor, EMAI, EMCloud, EMSettings, EMApp |
| **EMSettings** | EMCore | EMParser, EMFormatter, EMDoctor, EMEditor, EMFile, EMAI, EMCloud, EMGit, EMApp |
| **EMApp** | All packages | — (composition root) |

**Key design constraint**: EMAI and EMCloud cannot depend on each other. They communicate through protocols defined in EMCore (e.g., `SubscriptionStatus`). EMApp is the composition root that wires them together (see §7).

### Package Responsibilities

**EMCore** — Foundation types shared across all packages:
- `EMError` hierarchy (see §8)
- `Document` model type (see §3)
- `TypeScale` typography system and `Theme` types (see §4.5)
- `SubscriptionStatus` protocol (consumed by EMAI, implemented by EMCloud)
- `DeviceCapability` enum
- `HapticFeedback` type (see §8.4)
- Shared protocols (`Identifiable` conformances, common patterns)
- Constants (file extensions, performance thresholds)

**EMParser** — Markdown parsing:
- Wraps `swift-markdown` and exposes a clean AST type
- Source position tracking (line:column ranges on every node)
- Parse result type with AST + diagnostics
- Thread-safe: parsing runs on background threads

**EMFormatter** — Auto-formatting engine:
- List continuation, renumbering, indentation
- Table column alignment
- Heading normalization
- Whitespace cleanup
- Each rule is a discrete type conforming to a `FormattingRule` protocol
- Rules are individually toggleable (state from EMSettings via EMApp)
- Every rule produces undo-able `TextMutation` operations
- Rules are invoked by EMEditor's keystroke interception pipeline (see §4.4)

**EMDoctor** — Document diagnostics:
- Rule engine: broken links, heading hierarchy, duplicates, whitespace
- Each rule is a discrete type conforming to a `DoctorRule` protocol
- Produces `Diagnostic` values with fix actions
- Runs on a background thread, debounced after edits pause

**EMEditor** — Text view and rendering:
- TextKit 2 text view configuration
- AST → `NSAttributedString` rendering pipeline
- Rich view and source view attribute configurations
- The Render animation (Core Animation)
- Cursor mapping between rich and source views
- Floating action bar (AI + formatting actions)
- Code block rendering with syntax highlighting (tree-sitter)
- Mermaid diagram rendering pipeline
- Table rendering
- Image loading and rendering pipeline (see §4.6)
- Spell check integration (see §4.7)
- Keystroke interception for auto-formatting (see §4.4)
- Word count and document stats computation (see §4.8)

**EMFile** — File system operations:
- Security-scoped URL bookmark persistence
- `NSFileCoordinator` for all reads/writes
- `NSFilePresenter` for external change detection
- Auto-save (debounced 1s, atomic write)
- UTF-8 validation per `[D-FILE-2]`
- Line ending detection/preservation per `[D-FILE-3]`

**EMAI** — AI pipeline:
- `AIProvider` protocol definition
- `ApplePlatformAIProvider` (stub, future)
- `LocalModelProvider` (MLX Swift inference)
- `CloudAPIProvider` (SSE streaming client — requires `SubscriptionStatus` from EMCore, provided at init by EMApp)
- Provider selection logic
- Model download manager
- Prompt templates (versioned, per-action)
- Device capability detection

**EMCloud** — Purchases and subscriptions:
- StoreKit 2 one-time purchase management
- StoreKit 2 subscription management
- Receipt validation client (server-side for Pro AI relay)
- Subscription status caching
- Conforms to `SubscriptionStatus` protocol from EMCore
- Does NOT perform AI inference — that lives in EMAI

**EMGit** — Git operations and GitHub storage (Phase 2):
- Git repo detection (is this file inside a `.git` working tree?)
- Clone, pull, commit, push via libgit2 (SwiftGit2 or similar)
- GitHub OAuth device flow authentication, credentials in Keychain
- Repo browser: list user's GitHub repos for the "Open from GitHub" flow
- Auto-commit on file close / app background (sensible message: "Update filename.md")
- Manual push affordance (user-initiated when they want to push before closing)
- Unpushed changes detection and indicator state
- Pull-before-push with conflict detection (surfaces via EMFile's external change flow)
- Depends on EMFile for file coordination of the local clone

**EMSettings** — Preferences and counters:
- Settings model (`@Observable`)
- UserDefaults read/write
- On-device aggregate counters per `[D-BIZ-6]`
- Theme and font preferences
- Auto-format rule toggle states
- AI toggle states (ghost text on/off, etc.)

**EMApp** — Composition root:
- SwiftUI `App` struct and scene definitions
- Navigation stack and routing (see §7.1)
- Dependency injection: creates and wires all subsystems (see §7.2)
- Error presentation layer
- Keyboard shortcut registration (see §7.3)
- State restoration coordination (see §7.4)
- Multi-window scene management
- PDF/print export pipeline (see §4.9)

### Feature-to-Package Mapping

**[A-050]** Where each backlog feature's primary implementation lives. Every feature must have a clear home. Supporting packages provide data or services but the primary package owns the feature's core logic and tests.

| Feature | Primary Package | Supporting Packages |
|---------|----------------|---------------------|
| **File Management** | | |
| FEAT-001 Open File | EMFile | EMApp (UI, file picker) |
| FEAT-002 Create File | EMFile | EMApp (UI, save dialog) |
| FEAT-008 Auto-Save | EMFile | EMApp (error presentation) |
| FEAT-016 Quick Open | EMApp | EMFile (bookmarks, recents) |
| FEAT-018 Render/Print/Share | EMApp | EMEditor (rendering), EMFile |
| FEAT-040 File Coordination Layer | EMFile | EMCore (error types) |
| FEAT-070 GitHub Storage — Clone & Open | EMGit | EMFile, EMApp (repo browser UI) |
| FEAT-071 GitHub Storage — Auto-Commit & Push | EMGit | EMFile, EMApp (push indicator) |
| FEAT-072 GitHub Storage — Auth & Repo Browser | EMGit | EMApp (OAuth flow UI), EMSettings (Keychain) |
| FEAT-043 Recents & State Restoration | EMApp | EMFile (bookmarks), EMSettings (UserDefaults) |
| FEAT-045 File Conflict Detection | EMFile | EMApp (conflict UI) |
| **Editor — Core Rendering** | | |
| FEAT-003 Rich Text Rendering (Core) | EMEditor | EMParser, EMCore (TypeScale) |
| FEAT-006 Syntax Highlighting | EMEditor | EMCore |
| FEAT-012 Word Count & Stats | EMEditor | EMCore (NLP utilities) |
| FEAT-013 Spell Check | EMEditor | EMCore |
| FEAT-017 Find and Replace | EMEditor | EMApp (find bar UI) |
| FEAT-038 Markdown Parser | EMParser | EMCore |
| FEAT-039 Text Editing Engine | EMEditor | EMCore |
| FEAT-047 Table Rendering | EMEditor | EMParser |
| FEAT-048 Image Rendering | EMEditor | EMFile (path resolution), EMCore |
| FEAT-049 Checkboxes & Links | EMEditor | EMParser |
| FEAT-050 Source Toggle + Cursor Mapping | EMEditor | EMParser |
| FEAT-051 i18n Text (CJK, RTL, Emoji) | EMEditor | EMCore |
| **Editor — Auto-Formatting** | | |
| FEAT-004 Auto-Format Lists | EMFormatter | EMParser, EMEditor (integration) |
| FEAT-052 Auto-Format Tables | EMFormatter | EMParser, EMEditor (integration) |
| FEAT-053 Auto-Format Headings & Whitespace | EMFormatter | EMParser, EMEditor (integration) |
| **Editor — Doctor** | | |
| FEAT-005 Document Doctor | EMDoctor | EMParser, EMEditor (indicators) |
| FEAT-022 Extended Doctor | EMDoctor | EMEditor (indicators) |
| **Editor — Special Rendering** | | |
| FEAT-014 The Render (Signature Transition) | EMEditor | EMCore |
| FEAT-030 Mermaid Diagram Rendering | EMEditor | EMParser |
| FEAT-067 KaTeX/Footnotes (future) | EMEditor | EMParser |
| **Appearance** | | |
| FEAT-007 Dark & Light Mode | EMCore (Theme) | EMEditor, EMApp, EMSettings |
| FEAT-010 Typography & Layout | EMCore (TypeScale) | EMEditor |
| FEAT-019 Custom Themes & Fonts | EMSettings | EMCore (Theme), EMEditor, EMApp (UI) |
| **Input** | | |
| FEAT-009 Keyboard Support | EMApp | EMEditor |
| **AI — Local** | | |
| FEAT-011 AI Improve Writing | EMAI | EMEditor (diff preview) |
| FEAT-025 AI Smart Completions | EMAI | EMEditor (ghost text) |
| FEAT-041 AI Model Pipeline | EMAI | EMCore |
| FEAT-054 AI Floating Action Bar | EMEditor | EMAI |
| FEAT-055 AI Summarize | EMAI | EMEditor (popover) |
| FEAT-056 AI Continue Writing (Ghost Text) | EMAI | EMEditor (ghost text rendering) |
| **AI — Pro Cloud** | | |
| FEAT-023 AI Tone Adjustment (Pro) | EMAI | EMCloud (subscription), EMEditor |
| FEAT-024 AI Translation (Pro) | EMAI | EMCloud (subscription), EMEditor |
| FEAT-033 AI Generate from Prompt (future) | EMAI | EMCloud, EMEditor |
| FEAT-034 AI Document Analysis (future) | EMAI | EMCloud, EMEditor |
| FEAT-035 AI OCR (future) | EMAI | EMEditor |
| FEAT-046 Pro AI Cloud Infrastructure | EMCloud + EMAI | EMCore (SubscriptionStatus) |
| FEAT-066 AI Diagram Editing | EMAI | EMEditor, EMParser |
| FEAT-068 Voice Control | EMAI | EMEditor, EMApp (mic button) |
| **Platform** | | |
| FEAT-015 iPad Multi-Window & Stage Manager | EMApp | EMFile, EMEditor |
| FEAT-021 macOS App | EMApp | All (platform adaptation) |
| FEAT-026 Android (future) | N/A | Separate project |
| FEAT-027 Linux Desktop (future) | N/A | Separate project |
| FEAT-028 Folder Browsing Sidebar (future) | EMApp | EMFile |
| FEAT-031 Shortcuts/Siri (future) | EMApp | EMFile |
| FEAT-032 Quick Capture Widget (future) | EMApp | EMFile |
| FEAT-036 Localization (future) | EMApp | All (string extraction) |
| FEAT-057 Split View & External Display | EMApp | EMEditor |
| FEAT-058 Pointer & Trackpad | EMEditor | EMApp |
| **Infrastructure** | | |
| FEAT-037 App Shell & Navigation | EMApp | EMCore, EMSettings |
| FEAT-042 Settings Screen | EMSettings + EMApp | EMCore |
| FEAT-044 First-Run Experience | EMApp | EMAI (model download prompt) |
| FEAT-060 On-Device Counters | EMSettings | EMCore |
| FEAT-063 App Store Purchase | EMCloud | EMCore |
| FEAT-064 Perf Regression Tests | Tests/ | All packages |
| FEAT-065 Error Presentation System | EMCore (types) + EMApp (UI) | — |
| **Business/Growth** | | |
| FEAT-029 Snippets (future) | EMEditor | EMApp |
| FEAT-061 Export Watermark | EMApp | EMEditor (PDF pipeline) |
| FEAT-062 Pro AI Subscription Screen | EMApp | EMCloud |
| FEAT-069 App Store Review Prompt | EMApp | EMSettings (counters) |

---

## 3. Data Flow and Document Model

### Document Lifecycle

```mermaid
flowchart LR
    A[File on Disk] -->|NSFileCoordinator read| B[Raw UTF-8 String]
    B -->|swift-markdown parse| C[AST]
    C -->|Render pipeline| D[NSAttributedString]
    D -->|TextKit 2| E[Screen]
    E -->|User edits| F[Updated String]
    F -->|Debounced re-parse| C
    F -->|Debounced auto-save| G[NSFileCoordinator write]
    G --> A
```

### Document Model

**[A-016]** The `Document` type lives in EMCore. It is the single source of truth for an open document. It is `@MainActor`-isolated — background work (parsing, doctor, auto-save) operates on snapshots of its data and posts results back to the main actor.

```swift
/// Core document model — the single source of truth for an open file.
/// Lives in EMCore. @MainActor-isolated. Owned by one editor scene at a time.
/// Background tasks (parse, doctor, auto-save) take snapshots via `textSnapshot()`
/// and post results back to the main actor.
@MainActor
@Observable
public final class Document: Identifiable {
    public let id: UUID

    // File identity
    public private(set) var fileURL: URL?
    public private(set) var securityScopedBookmark: Data?

    // Content
    public var rawText: String
    public private(set) var ast: MarkdownAST?
    public private(set) var parseDate: Date?

    // File metadata
    public private(set) var lineEnding: LineEnding  // .lf or .crlf
    public private(set) var fileSize: Int
    public private(set) var lastSavedContent: String?

    // Diagnostics (from EMDoctor, posted back to main actor)
    public private(set) var diagnostics: [Diagnostic]

    // State
    public private(set) var isDirty: Bool
    public private(set) var isExternallyModified: Bool

    // Stats (updated incrementally on keystroke, full recount on re-parse)
    public private(set) var wordCount: Int
    public private(set) var characterCount: Int
    public private(set) var characterCountNoSpaces: Int
    public private(set) var estimatedReadingTimeSeconds: Int

    /// Snapshot for background work (parsing, doctor, auto-save).
    /// Safe to call from @MainActor, produces a Sendable value.
    public func textSnapshot() -> TextSnapshot { ... }
}

/// Sendable snapshot of document text for background processing.
public struct TextSnapshot: Sendable {
    public let text: String
    public let fileURL: URL?
    public let version: Int  // Monotonic, for stale-result rejection
}
```

**Editor state** (cursor position, scroll offset, view mode, undo manager) lives in an `EditorState` type in **EMEditor**, not in `Document`. This keeps platform-specific concerns (e.g., `NSRange`, `UndoManager`, `CGFloat` scroll offsets) out of EMCore.

```swift
/// Per-scene editor state. Lives in EMEditor.
/// Owns platform-specific state that should not pollute EMCore.
@MainActor
@Observable
public final class EditorState {
    public var selectedRange: NSRange
    public var isSourceView: Bool
    public var scrollOffset: CGFloat
    public let undoManager: UndoManager

    // Selection-aware stats (subset of Document stats)
    public private(set) var selectionWordCount: Int?
}
```

### Incremental Update Strategy

**[A-017]** Full re-parse is debounced. Local updates fill the gap.

1. **On every keystroke** (<16ms budget): Apply lightweight local attribute updates to the current paragraph only. The approach: identify the paragraph range containing the edit, apply regex-based syntax detection (headings, bold, italic, code spans, list markers) to that paragraph, and update `NSAttributedString` attributes on the matching ranges. This is a simplified mini-renderer — it does not produce a full AST, just enough to keep visual styling correct between full parses. The regex patterns are derived from the CommonMark spec for inline elements and leaf block prefixes. Update word count via `NLTokenizer` on the changed paragraph (delta-based: subtract old paragraph count, add new).

2. **After editing pause** (~300ms debounce): Full re-parse on a background thread via `swift-markdown`. Uses `Document.textSnapshot()` to get a `Sendable` copy. Produces a new AST.

3. **On AST update** (main thread): Diff old AST vs. new AST by comparing node types and source positions. Apply targeted `NSAttributedString` attribute updates only to changed regions. This avoids re-rendering the entire document. Recount full document stats.

4. **Doctor re-evaluation**: Runs after AST update, also on a background thread using the same `TextSnapshot`. Results posted to main thread as `Diagnostic` values. Stale results (snapshot version < current version) are discarded.

**Performance contract**: Keystroke → screen update in <16ms (step 1 only). Full re-parse of a 10,000-line document in <100ms on background thread (step 2). AST diff + attribute update in <5ms on main thread (step 3).

---

## 4. Editor Subsystem

The editor is the hardest subsystem. It owns the text view, rendering pipeline, animations, and all inline interactions.

### 4.1 Rich Text Rendering

**[A-018]** AST → `NSAttributedString` rendering pipeline in EMEditor.

**Block elements**: Rendered via custom `NSTextLayoutFragment` subclasses where standard attributes are insufficient.
- Headings: 6 levels with distinct sizes/weights from `TypeScale`
- Code blocks: Monospace font, background fill, syntax highlighting via tree-sitter
- Blockquotes: Left border (custom drawing in layout fragment)
- Tables: Custom layout fragment with cell grid
- Mermaid diagrams: `NSTextAttachment` with cached rendered image
- Images: `NSTextAttachment` with async loading (see §4.6)
- Horizontal rules: Custom drawing

**Inline elements**: Rendered via standard `NSAttributedString` attributes.
- Bold: `.bold` trait
- Italic: `.italic` trait
- Strikethrough: `.strikethroughStyle`
- Code spans: Monospace font + background color attribute
- Links: `.link` attribute + custom foreground color

**Syntax character hiding**: In rich view, markdown syntax characters (`#`, `**`, `- `, etc.) are hidden via zero-width attributes or excluded from the visible content. Source positions in the AST map between visible content and raw markdown.

### 4.2 Source View

**[A-019]** Same `NSTextContentStorage` instance, different attribute configuration. Source view shows raw markdown with syntax highlighting (markdown syntax colored, not hidden). Shares the same underlying text storage with rich view — no content duplication.

### 4.3 The Render Animation

**[A-020]** Snapshot-based Core Animation per `DP-9` and `[D-UX-3]`. `[RESEARCH-complete]` **SPIKE-004** ✅.

**Approach**:
1. Capture the current view state as a snapshot layer (`CALayer` snapshot)
2. Compute target positions for each element in the destination layout
3. Animate between source and destination positions using `CASpringAnimation`:
   - Duration: ~400ms
   - Damping ratio: 0.8
   - Response: 0.4
4. On animation complete, remove snapshot layers and show the live text view

**Element transitions**:
- `#` markers: Shrink and fade as heading text scales up
- `**`/`*`: Dissolve as text weight/style changes
- List markers: Morph into styled bullets (position + style interpolation)
- Code fences: Fade as code block background materializes
- Link syntax: Compact as link renders in styled form
- Blockquote `>`: Transform into visual left border

**Reduced Motion** per `[D-A11Y-3]`: 200ms crossfade (opacity-only animation). No position interpolation.

**Performance**: Must run at 120fps on ProMotion. Uses Core Animation (GPU-composited), not SwiftUI animation modifiers. No main-thread layout work during animation.

### 4.4 Keystroke Interception and Auto-Format Integration

**[A-051]** EMEditor owns the keystroke interception pipeline. EMFormatter rules are invoked from this pipeline.

**Mechanism**: Implement `UITextViewDelegate.textView(_:shouldChangeTextIn:replacementText:)`. On specific keystrokes (Enter, Tab, Shift-Tab), before committing the change to text storage:

1. Query the current AST for the context at cursor position (block type, nesting level, list state)
2. Invoke applicable EMFormatter rules with the context and proposed change
3. Each rule returns either `nil` (no action) or a `TextMutation` describing the replacement
4. Apply the `TextMutation` to text storage as a discrete undo group
5. If no rules match, let the default text insertion proceed

**Code block suppression**: Auto-format rules check the AST context — if the cursor is inside a fenced code block or code span, all formatting rules are bypassed.

**`TextMutation` type** (in EMCore):
```swift
/// Describes a text mutation produced by a formatting rule.
/// Applied as a single undo group.
public struct TextMutation: Sendable {
    public let range: Range<String.Index>
    public let replacement: String
    public let cursorAfter: String.Index
    public let hapticStyle: HapticStyle?  // nil = no haptic
}
```

### 4.5 Theme System

**[A-052]** Theme and typography types live in EMCore. Theme application lives in EMEditor and EMApp.

```swift
/// Color palette for a theme variant (light or dark).
public struct ThemeColors: Sendable {
    // Editor
    public let background: PlatformColor
    public let foreground: PlatformColor
    public let heading: PlatformColor
    public let link: PlatformColor
    public let codeBackground: PlatformColor
    public let codeForeground: PlatformColor
    public let blockquoteBorder: PlatformColor
    public let selection: PlatformColor

    // Syntax highlighting (code blocks)
    public let syntaxKeyword: PlatformColor
    public let syntaxString: PlatformColor
    public let syntaxComment: PlatformColor
    public let syntaxNumber: PlatformColor
    public let syntaxType: PlatformColor
    public let syntaxFunction: PlatformColor

    // UI chrome
    public let toolbarBackground: PlatformColor
    public let statusBarBackground: PlatformColor
    public let divider: PlatformColor

    // Doctor / diagnostics
    public let warningIndicator: PlatformColor
    public let errorIndicator: PlatformColor
}

/// A complete theme with light and dark variants.
public struct Theme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let light: ThemeColors
    public let dark: ThemeColors
}

/// Type scale for all text sizes in the editor.
/// Wraps custom fonts with UIFontMetrics for Dynamic Type scaling.
public struct TypeScale: Sendable {
    public let heading1: PlatformFont
    public let heading2: PlatformFont
    public let heading3: PlatformFont
    public let heading4: PlatformFont
    public let heading5: PlatformFont
    public let heading6: PlatformFont
    public let body: PlatformFont
    public let code: PlatformFont   // Monospace
    public let caption: PlatformFont
    public let ui: PlatformFont     // UI chrome
}
```

**Font loading**: Custom font files are bundled in EMCore. Registered at app launch via `CTFontManagerRegisterFontsForURL`. Each font wrapped with `UIFontMetrics` for Dynamic Type scaling per `[D-A11Y-2]`. Fallback chain: custom font → system font for scripts not covered (CJK, Arabic, Devanagari — the system font picker handles these automatically via font cascading).

**Theme propagation**: The active theme is an `@Observable` property on the `AppState` in EMApp. EMEditor observes theme changes and re-applies attributes to the full document (batch attribute update). Mermaid render cache is invalidated on theme change (content hash includes a theme ID component).

### 4.6 Image Loading Pipeline

**[A-053]** Image loading for inline markdown images in EMEditor.

**Path resolution**: Relative image paths (e.g., `![](./images/diagram.png)`) resolve relative to the document's `fileURL`. If no `fileURL` (unsaved document), relative paths show the broken-image placeholder.

**Loading strategy**:
1. Parse image node from AST — extract URL and alt text
2. If URL is relative, resolve against `document.fileURL`
3. Check in-memory cache (keyed by resolved URL)
4. Cache miss → load asynchronously on a background thread via `NSFileCoordinator` (for local files) or `URLSession` (for remote URLs — rare but valid)
5. On load: create `UIImage`, downsample to fit content width (prevent memory spikes from large images), cache the result
6. Create `NSTextAttachment` with the loaded image
7. On failure: display placeholder image with alt text overlay, emit a doctor diagnostic

**Memory management**: Images are cached in an `NSCache` with a 50MB cost limit. Large images (>2048px in either dimension) are downsampled on load. Images are evicted under memory pressure via `NSCache` behavior.

### 4.7 Spell Check Integration

**[A-054]** System spell checking per `[D-EDIT-7]`. Lives in EMEditor.

- Uses `UITextChecker` (iOS) / `NSSpellChecker` (macOS) — system spell check, not custom
- Spell check is enabled on the `UITextView` by default (`spellCheckingType = .yes`)
- **AST-aware suppression**: Override `UITextView`'s spell check behavior to skip ranges that the AST identifies as code blocks, code spans, URLs, and image paths. Implementation: in `textView(_:shouldChangeTextIn:)` or by applying `.spellingCorrection` attribute to suppress ranges
- **Coexistence with doctor indicators**: Spell check uses the system red underline (`NSAttributedString.Key.underlineStyle`). Doctor indicators use a different visual — colored dot in the gutter margin, not underlines. This prevents visual conflict.
- **Toggle**: Controlled by a setting in EMSettings, propagated via EMApp to the text view's `spellCheckingType` property

### 4.8 Word Count and Stats

**[A-055]** Word count computation lives in EMEditor. Results are written to `Document` properties (in EMCore).

**Incremental updates** (per-keystroke, <1ms budget):
- On each text change, identify the changed paragraph
- Use `NLTokenizer` with `.word` unit to count words in the changed paragraph
- Delta update: `document.wordCount += (newParagraphCount - oldParagraphCount)`
- Character counts: simple `.count` and `.filter { !$0.isWhitespace }.count`

**Full recount** (on AST update):
- Use `NLTokenizer` on full document text — handles CJK segmentation correctly (not space-delimited)
- Sentence count via `NLTokenizer` with `.sentence` unit
- Flesch-Kincaid readability: syllable estimation + sentence/word ratios
- Estimated reading time: `wordCount / 238` (average adult reading speed in WPM)

**Selection-aware stats**: When selection changes, compute selection word count and store in `EditorState.selectionWordCount`. Displayed alongside total in the status bar.

### 4.9 PDF and Print Export

**[A-056]** Export pipeline lives in EMApp. Uses EMEditor's rendering capabilities.

**Approach**: `UIGraphicsPDFRenderer` with a custom `UIPrintPageRenderer`.

1. Create a dedicated `NSTextLayoutManager` configured for print (page-sized text container, print-appropriate margins)
2. Render the AST → `NSAttributedString` using the same pipeline as the editor, but with print-optimized `TypeScale` (slightly different margins/sizes for paper)
3. For Mermaid diagrams: include the cached rendered image (or re-render if not cached). In PDF, prefer SVG-based vector output if available from the WKWebView render step
4. For images: embed at original resolution (not downsampled)
5. Render each page via `UIPrintPageRenderer.drawPage(at:in:)`
6. Watermark (FEAT-061): If enabled, draw "Made with easy-markdown" in small light-gray text at the page footer. Disabled by default for print, enabled by default for PDF export. Toggleable in settings.

**Share sheet**: Expose the `.md` file directly via `UIActivityViewController` for markdown sharing (AirDrop, email, Messages). PDF export is a separate action.

### 4.10 Cursor Mapping

**[A-021]** AST source positions bridge between rich and source views. When toggling views, find the AST node at the current cursor position, then map to the equivalent position in the target view. Best-effort: same paragraph, same relative offset within the paragraph.

### 4.11 Undo

**[A-022]** `UndoManager` per scene, stored in `EditorState`. Per `[D-EDIT-6]`: per-session, in-memory, unlimited depth. Each auto-format operation (list continuation, table alignment, etc.) registers as a separate undo group. AI accept operations register as a single undo group.

### 4.12 Floating Action Bar

**[A-023]** Appears above text selection. Contains formatting actions (Bold, Italic, Link) and AI actions (Improve, Summarize). Pro AI actions (Translate, Tone) appear with Pro badge for subscribers. Keyboard shortcut: Cmd+J focuses AI section. Dismisses on deselect.

---

## 5. File Coordination

### Security-Scoped URL Lifecycle

**[A-024]** Per `[D-FILE-1]` and `DP-1`.

1. User picks file via `UIDocumentPickerViewController`
2. Obtain security-scoped URL → call `url.startAccessingSecurityScopedResource()`
3. Create bookmark data → persist in `UserDefaults` (recents list)
4. On app relaunch: resolve bookmark → re-obtain security-scoped URL
5. On file close: `url.stopAccessingSecurityScopedResource()`

**Important**: Balance start/stop calls. Never leak security-scoped access.

### File I/O

**[A-025]** All file I/O through `NSFileCoordinator`.

```swift
// Read pattern
let coordinator = NSFileCoordinator(filePresenter: self)
coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
    let data = try Data(contentsOf: readURL)
    // Validate UTF-8 per [D-FILE-2]
    guard let text = String(data: data, encoding: .utf8) else {
        throw EMError.file(.notUTF8(url: url))
    }
    // Detect line endings per [D-FILE-3]
    // Check file size per [D-FILE-4]
}

// Write pattern — atomic via temp + rename
coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
    let data = text.data(using: .utf8)!
    try data.write(to: writeURL, options: .atomic)
}
```

### Auto-Save

**[A-026]** Per `[D-EDIT-5]`.

- **Trigger**: 1 second after last keystroke (debounced), on app background (`sceneDidEnterBackground`), on file close
- **Mechanism**: Atomic write (write to temp file, rename to target). Takes `textSnapshot()` for the write.
- **Error handling**: Save failure → non-modal banner with retry action. Content stays in memory. Per `DP-8`.
- **Conflict check**: Before writing, verify file hasn't been externally modified (compare modification date)

### External Change Detection

**[A-027]** `NSFilePresenter` registered for the open file URL. Per `[D-FILE-5]`.

When `presentedItemDidChange()` fires:
1. Pause auto-save
2. Show non-modal notification: "This file was modified externally. Reload or keep your version?"
3. Reload → re-read file, update `Document`, clear undo
4. Keep → mark as dirty, next save overwrites external changes

### Multi-Window File Safety

**[A-028]** Each scene owns its own `NSFileCoordinator` and `NSFilePresenter` instance. If two scenes open the same file URL, detect via URL comparison and activate the existing scene instead of opening a duplicate.

### GitHub Storage (Phase 2)

**[A-064]** GitHub as a transparent storage option alongside iCloud, Dropbox, OneDrive, Google Drive. Lives in EMGit. GitHub-only initially; generic git remotes later if demand warrants.

`[RESEARCH-needed]` **SPIKE-009**: Evaluate libgit2 Swift bindings (SwiftGit2 or similar) for iOS. Assess: SPM compatibility, binary size, clone/commit/push performance on cellular, and App Store compliance. Prototype clone + commit + push cycle.

**Core principle**: GitHub is just another place your files live. The user experience should be as friction-free as iCloud. Files are local clones — we edit local files. Git operations happen at the edges.

**How it works**:

1. **Open from GitHub**: Home screen shows "Open from GitHub" alongside "Open File" and "New File". User authenticates once (OAuth device flow, token in Keychain). Browses their repos, picks a file. EMGit clones the repo (or pulls if already cloned) to a local app container directory. File opens in the editor via EMFile — from this point on, editing is identical to any local file.

2. **Auto-save**: Same as any file — debounced 1s write to the local clone via EMFile. No git operations yet.

3. **Auto-commit + push on close/background**: When the user closes the file or the app backgrounds:
   - If the file has unsaved changes → save first
   - If the local clone has uncommitted changes → `git add <file>` + `git commit -m "Update filename.md"`
   - Pull with rebase before push (detect conflicts)
   - `git push` to remote
   - If push fails (network, conflict) → non-modal banner, changes remain committed locally and will push next time

4. **Manual push**: A subtle indicator in the toolbar shows when there are unpushed local commits. User can tap to push immediately without closing the file. This gives control for users who want to push at a specific point.

5. **Conflict handling**: If `git pull` reveals a merge conflict, surface it through the same external-change flow as `[A-027]` — "This file was modified on GitHub. Reload remote version or keep yours?" If the user keeps theirs, the next push force-updates the remote. We do not attempt three-way merge — this is a document editor, not a git client.

6. **Clone management**: Cloned repos are cached in the app's container. Metadata (repo URL, clone path, last sync date) stored in UserDefaults. Repos that haven't been accessed in 30 days can be offered for cleanup in Settings to reclaim storage.

**Authentication**:
- GitHub OAuth device flow (no web view needed — user enters a code at github.com/login/device)
- Token stored in Keychain (not UserDefaults — these are credentials)
- Token refresh handled automatically
- Sign out available in Settings

**What this is NOT**:
- Not a git GUI (no branch switching, no diff viewer, no merge tool, no commit history)
- Not multi-branch (operates on the default branch only)
- Not a sync service (explicit clone → edit → push, not background sync)
- Does not replace the system file picker for other providers

---

## 6. AI Pipeline

This section is architecturally critical. The key insight: **design for platform AI**.

### AIProvider Protocol

**[A-029]** The unified interface for all AI backends. Lives in EMAI.

```swift
/// Unified AI inference protocol. All providers conform to this.
public protocol AIProvider: Sendable {
    /// Human-readable name for UI display
    var name: String { get }

    /// Whether this provider is currently available
    var isAvailable: Bool { get async }

    /// Whether this provider requires a network connection
    var requiresNetwork: Bool { get }

    /// Whether this provider requires a subscription
    var requiresSubscription: Bool { get }

    /// Run inference and stream results
    func generate(
        prompt: AIPrompt,
        context: AIContext
    ) -> AsyncThrowingStream<String, Error>

    /// Check if the provider can handle this specific action
    func supports(action: AIAction) -> Bool
}

/// What the AI should do
public enum AIAction: Sendable {
    case improve
    case summarize
    case continueWriting     // Explicit invocation (cursor-based)
    case ghostTextComplete   // Proactive ghost text after typing pause
    case smartComplete       // Structure-aware: table layouts, list patterns
    case translate(targetLanguage: String)
    case adjustTone(style: ToneStyle)
    case generateFromPrompt
    case analyzeDocument
    case editDiagram
    case intentFromVoice(transcript: String)  // Voice control: speech → intent
}

/// Input to the AI
public struct AIPrompt: Sendable {
    public let action: AIAction
    public let selectedText: String
    public let surroundingContext: String?  // paragraph or section around selection
    public let systemPrompt: String        // from versioned template
    public let contentType: ContentType    // prose, codeBlock, table, mermaid
}

/// Detected content type for content-aware prompting
public enum ContentType: Sendable {
    case prose
    case codeBlock(language: String?)
    case table
    case mermaid
    case mixed
}

/// Device and runtime context
public struct AIContext: Sendable {
    public let deviceCapability: DeviceCapability
    public let isOffline: Bool
    public let subscriptionStatus: SubscriptionStatus
}
```

### Subscription Status Bridge (EMCore ↔ EMAI ↔ EMCloud)

**[A-057]** EMAI and EMCloud cannot depend on each other. They communicate through a protocol in EMCore.

```swift
/// Defined in EMCore. Implemented by EMCloud. Consumed by EMAI.
/// EMApp injects the EMCloud implementation into EMAI at app launch.
public protocol SubscriptionStatusProviding: Sendable {
    var isProSubscriptionActive: Bool { get async }
    var subscriptionExpirationDate: Date? { get }
}
```

**Wiring**: EMApp creates the EMCloud `SubscriptionManager` (which conforms to `SubscriptionStatusProviding`), then passes it to EMAI's `AIProviderManager` at initialization. EMAI's `CloudAPIProvider` checks subscription status before each request via this protocol — it never imports EMCloud directly.

### Provider Implementations

**`ApplePlatformAIProvider`** — Future. Currently a stub that returns `isAvailable = false`. When Apple ships system AI APIs, implement this first. It will have the highest selection priority.

**`LocalModelProvider`** — Interim on-device inference:
- Loads quantized model via MLX Swift
- Memory-mapped model to minimize RAM impact
- Streams tokens via `AsyncThrowingStream<String, Error>`
- First token target: <500ms per `[D-PERF-4]`
- Only available on A16+/M1+ devices
- Handles model download lifecycle (download, resume, delete)

**`CloudAPIProvider`** — Pro AI:
- `URLSession` with SSE streaming
- Sends only user-selected text per `[D-AI-8]`
- Checks `SubscriptionStatusProviding.isProSubscriptionActive` before each request
- Timeout: 10s → suggest local AI as fallback
- No logging of prompts or responses

### Provider Selection

**[A-030]** Runtime provider selection logic:

```swift
func selectProvider(for action: AIAction, context: AIContext) async -> AIProvider? {
    // 1. Platform AI — highest priority when available
    if await applePlatformProvider.isAvailable,
       applePlatformProvider.supports(action: action) {
        return applePlatformProvider
    }

    // 2. Local model — default for most actions
    if await localModelProvider.isAvailable,
       localModelProvider.supports(action: action) {
        return localModelProvider
    }

    // 3. Cloud — only if subscribed AND user opted in
    if await context.subscriptionStatus.isProSubscriptionActive,
       !context.isOffline,
       cloudProvider.supports(action: action) {
        return cloudProvider
    }

    return nil  // No provider available — hide AI UI
}
```

### Model Download

**[A-031]** For `LocalModelProvider` only. Per `[D-AI-9]`.

- Background Assets framework or ODR
- Wi-Fi default; cellular requires explicit opt-in
- Resumable: persists download progress, resumes on interruption
- Non-blocking: editor is fully functional during download
- Progress exposed via `@Observable` for UI binding
- Model updates ship independently from app updates

**This entire subsystem may become unnecessary if Apple ships platform AI.** Design it as a contained, removable component within EMAI.

### Prompt Templates

**[A-032]** Prompt templates are versioned, per-action, and testable. Each `AIAction` has a corresponding template that constructs the system and user prompts. Templates live in EMAI as Swift types (not string files) so they are compile-time checked.

Templates are content-aware: they inspect `AIPrompt.contentType` and adapt the prompt accordingly. A prose selection gets writing improvement prompts; a Mermaid block gets structural editing prompts; a table gets formatting/content prompts. Per F-025 acceptance criteria.

### Device Capability Detection

**[A-033]** `[RESEARCH-complete]` Check `utsname.machine` (iOS) / `sysctlbyname("hw.model")` (macOS) hardware identifier → map to known chip families. Validated in **SPIKE-005**: correctly identifies A16+/M1+ across 11 device models. App Store compliant (public POSIX APIs). See `docs/spikes/SPIKE-005.md`.

```swift
public enum DeviceCapability: Sendable {
    case fullAI          // A16+ / M1+ — all AI features
    case noAI            // Older devices — no generative AI
}
```

Gate AI UI visibility on capability — per `[D-AI-5]`: unsupported devices show no AI-related UI (no broken affordances). No AI buttons, no ghost text, no action bar AI items.

---

## 7. App Shell, Navigation, and Composition

### 7.1 Navigation Architecture

**[A-058]** SwiftUI `NavigationStack` with a programmatic router.

```swift
/// Navigation destinations for the app.
enum AppRoute: Hashable {
    case home                     // Open/New buttons + recents list
    case editor(Document)         // Main editing view
    case settings                 // Settings screen (sheet)
    case subscriptionOffer        // Pro AI subscription (sheet)
}

/// Owns the navigation path. One per scene.
@MainActor
@Observable
final class AppRouter {
    var path = NavigationPath()
    var presentedSheet: AppRoute?

    func openDocument(_ document: Document) { ... }
    func showSettings() { ... }
    func showSubscriptionOffer() { ... }
    func popToHome() { ... }
}
```

**Navigation flow**:
- App launches → `home` (or `editor` if state restoration has a last-open file)
- Open/New → `editor`
- Gear icon → `settings` (presented as sheet)
- Pro AI action (non-subscriber) → `subscriptionOffer` (presented as sheet)
- Close file → `home`

**Multi-window**: Each `WindowGroup` scene gets its own `AppRouter`. Navigation state is independent per scene.

### 7.2 Dependency Injection

**[A-059]** Constructor injection at the composition root (EMApp). No DI framework. No service locator.

EMApp's `App` struct creates all shared singletons at launch and passes them down:

```swift
@main
struct EasyMarkdownApp: App {
    // Shared singletons — created once, shared across scenes
    @State private var settings = SettingsManager()        // EMSettings
    @State private var subscriptionManager = SubscriptionManager()  // EMCloud
    @State private var aiProviderManager: AIProviderManager        // EMAI

    init() {
        // Wire EMCloud → EMAI via EMCore protocol
        let aiManager = AIProviderManager(
            subscriptionStatus: subscriptionManager  // EMCloud conforms to SubscriptionStatusProviding
        )
        _aiProviderManager = State(initialValue: aiManager)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(subscriptionManager)
                .environment(aiProviderManager)
        }
    }
}
```

**Per-scene instances**: Each scene creates its own `Document`, `EditorState`, `AppRouter`, and file coordination objects. These are not shared across scenes.

**SwiftUI `@Environment`**: Shared singletons are passed via SwiftUI's environment. Per-scene instances are passed via constructor injection to child views.

### 7.3 Keyboard Shortcut Registration

**[A-060]** Use SwiftUI `.keyboardShortcut()` modifiers for shortcuts tied to visible UI elements (toolbar buttons). Use `UIKeyCommand` overrides on the hosting `UIViewController` for editor-specific shortcuts (Cmd+B, Cmd+I, etc.) that need to work regardless of SwiftUI focus state.

**Discoverability overlay** (Cmd-hold): Register all shortcuts with the `UIKeyCommand` system. The system automatically provides the Cmd-hold overlay on iPad showing all registered commands, organized by the `discoverabilityTitle` property. No custom overlay needed.

### 7.4 State Restoration

**[A-061]** Per `[D-UX-2]`: return the user to where they left off.

**What is persisted** (in `UserDefaults` via EMSettings):
- Last open file: security-scoped bookmark data
- Cursor position: character offset in raw text
- View mode: rich or source
- Scroll offset: fractional position (0.0–1.0 of document height)

**When state is saved**: On every significant change — file open/close, view toggle, app background. Debounced at 2s for cursor/scroll changes to avoid excessive writes.

**Restoration flow on launch**:
1. Read state from UserDefaults
2. Resolve bookmark → obtain security-scoped URL
3. If resolution succeeds → open file, restore cursor + scroll + view mode
4. If resolution fails (file deleted/moved) → remove from recents, show home screen with recents list
5. If no saved state → show home screen

**Multi-window**: Each scene persists its own state via `NSUserActivity` (SwiftUI's `handlesExternalEvents` + `userActivity` modifiers). Scene state includes the same fields as above, scoped to the scene's window.

### 7.5 Multi-Window and Scenes

**[A-034]** Per F-015 (iPad Multi-Window) and F-036 (iPad Optimization).

- SwiftUI `WindowGroup` with `NSUserActivity` for state restoration
- Each scene: one `Document`, own `EditorState`, own file coordination, own `AppRouter`
- Shared across scenes: `SettingsManager`, `SubscriptionManager`, `AIProviderManager`
- Content width constrained to ~70-80 characters on large displays per F-010 typography spec
- Responsive to Split View widths (1/3, 1/2, 2/3) — content reflows without jumpiness
- Minimum supported width: Slide Over on iPad (~320pt)

---

## 8. Cross-Cutting Concerns

### 8.1 Error Handling

**[A-035]** `EMError` hierarchy in EMCore. Per `[D-ERR-1]` and `DP-8`: no error state is undesigned.

```swift
/// Root error type for all easy-markdown errors.
/// Every case includes a user-facing message and recovery options.
public enum EMError: LocalizedError {

    // File errors
    case file(FileError)
    public enum FileError: LocalizedError {
        case notUTF8(url: URL)
        case accessDenied(url: URL)
        case notFound(url: URL)
        case saveFailed(url: URL, underlying: Error)
        case tooLarge(url: URL, sizeBytes: Int)
        case externallyDeleted(url: URL)
        case bookmarkStale(url: URL)
    }

    // AI errors
    case ai(AIError)
    public enum AIError: LocalizedError {
        case modelNotDownloaded
        case modelDownloadFailed(underlying: Error)
        case inferenceTimeout
        case inferenceFailed(underlying: Error)
        case deviceNotSupported
        case cloudUnavailable
        case subscriptionRequired
        case subscriptionExpired
    }

    // Parse errors
    case parse(ParseError)
    public enum ParseError: LocalizedError {
        case timeout(lineCount: Int)
    }

    // General
    case unexpected(underlying: Error)
}
```

**Error presentation** — centralized `ErrorPresenter` in EMApp:
- **Recoverable errors** (save failure, network timeout): Non-modal banner at top of screen with retry action. Auto-dismisses after 8 seconds or on user action.
- **Data-loss-risk errors** (file deleted while editing, storage full): Modal alert with save/recovery options. Does not auto-dismiss.
- **Informational warnings** (file >1MB, non-UTF-8): Dismissable banner. No action required.

All error messages are human-written. No raw error codes or technical jargon shown to users.

### 8.2 Accessibility

**[A-036]** Per `[D-A11Y-1]`, `[D-A11Y-2]`, `[D-A11Y-3]`.

- **VoiceOver**: Semantic accessibility elements on all text view content. Headings announced as headings with level. Links announced as links with URL. Doctor indicators announced with issue description. AI actions announced in floating bar.
- **Dynamic Type**: All text sizes derived from `TypeScale` in EMCore, which wraps custom fonts with `UIFontMetrics` for automatic scaling per `[D-A11Y-2]`. Fallback fonts for non-Latin scripts handled via system font cascading.
- **Reduced Motion**: All animations check `UIAccessibility.isReduceMotionEnabled`. The Render → 200ms crossfade. Theme transitions → instant. All spring animations → linear fade.
- **Color**: No information conveyed by color alone. Doctor indicators use gutter dot (shape) + color. Diff preview uses strikethrough + color.

### 8.3 Performance Instrumentation

**[A-037]** Per `[D-QA-2]`.

- `os_signpost` intervals on all critical paths:
  - File open → editing ready
  - Keystroke → attribute update complete
  - Parse start → parse complete
  - AI prompt → first token
  - The Render start → animation complete
- Signpost names follow convention: `com.easymarkdown.<module>.<operation>`
- Debug builds: optional performance overlay showing keystroke latency and frame rate
- CI: XCTest `measure` blocks for regression detection per FEAT-064

### 8.4 Haptic Feedback

**[A-062]** Haptic feedback type defined in EMCore. Triggered by EMEditor and EMApp.

```swift
/// Haptic vocabulary for the app. Each case maps to a UIImpactFeedbackGenerator style.
public enum HapticStyle: Sendable {
    case listContinuation    // Light tap — list auto-continued
    case doctorFixApplied    // Light tap — doctor fix accepted
    case aiAccepted          // Medium tap — AI suggestion accepted
    case autoSaveConfirm     // Subtle — background save confirmed
    case toggleView          // Light — source/rich toggle
}
```

Haptics are triggered via a shared utility in EMCore that wraps `UIImpactFeedbackGenerator`. Respects the system "System Haptics" setting — disabled when the user has turned off system haptics. Subtle and purposeful — never gratuitous per `DP-2`.

### 8.5 Logging

**[A-038]** `os_log` / `Logger` with subsystem per module.

```swift
// Each module defines its own Logger
let logger = Logger(subsystem: "com.easymarkdown.emfile", category: "autosave")
```

- **On-device only**. Never transmitted per `[D-BIZ-4]`.
- Log levels: `.debug` for development, `.info` for normal operations, `.error` for failures
- Never log file content, AI prompts/responses, or user data

### 8.6 Testing

**[A-039]** Per `[D-QA-1]` and `[D-QA-2]`.

- **Unit tests**: Per package. EMParser tests against CommonMark + GFM spec examples. EMFormatter tests each rule in isolation with input → expected output. EMDoctor tests each rule against fixture files. EMAI tests prompt templates and provider selection logic (mock providers).
- **Integration tests**: EMEditor tests rendering pipeline end-to-end (markdown string → attributed string → verify attributes). EMFile tests file coordination with actual file system.
- **UI tests**: XCUITest for critical journeys (open file, edit, toggle source, AI improve, auto-format list).
- **Performance tests**: XCTest `measure` for keystroke latency, parse time, scroll frame rate. Regression thresholds match `[D-PERF-1]` through `[D-PERF-5]`.
- **Accessibility tests**: XCUITest assertions for VoiceOver element presence and labels on all screens.

---

## 9. Conventions and Rules

These rules apply to all code in the repository. The developer agent must follow them.

### Code Placement

**[A-040]** Every type belongs in exactly one package per the module architecture in §2 and the feature-to-package mapping in `[A-050]`. If unsure where a type belongs, follow the dependency graph — the type goes in the lowest package that doesn't violate dependency rules.

### Dependency Discipline

**[A-041]** No dependency graph violations. If package A is not listed as a dependency of package B in §2, B may not import A. The SPM manifest enforces this — a dependency violation is a compile error.

### Public API Documentation

**[A-042]** Every `public` declaration must have a doc comment (`///`). Internal and private declarations should have doc comments when the intent is not obvious from the name.

### Accessibility

**[A-043]** Every UI element must support:
- VoiceOver (accessibility label, value, traits, and hint where appropriate)
- Dynamic Type (text sizes via `TypeScale`, never hardcoded point sizes)
- Reduced Motion (check `UIAccessibility.isReduceMotionEnabled` before any animation)

A feature that doesn't work with VoiceOver doesn't ship per `[D-A11Y-1]`.

### No Unauthorized Dependencies

**[A-044]** No third-party package may be added without an `[A-XXX]` architecture decision in this document. Per `DP-5` and `[D-NO-6]`.

### No Sidecar Files, Database, or Analytics

**[A-045]** Per `DP-1`, `[D-NO-2]`, `[D-BIZ-4]`:
- No files created alongside user's files (no `.easy-markdown/`, no metadata files)
- No SQLite, Core Data, or any database
- No third-party analytics SDKs
- No telemetry transmitted off device

### Performance Paths

**[A-046]** All UI-bound code runs on `@MainActor`. All signposted critical paths (§8) must meet their latency targets. Use `os_signpost` on any new performance-critical path.

### Concurrency

**[A-047]** Structured concurrency only per `[A-013]`. No Combine publishers. No `DispatchQueue.main.async`. No completion-handler APIs (wrap in `withCheckedThrowingContinuation` if calling older APIs). `Document` is `@MainActor`-isolated; background work uses `TextSnapshot`.

### Error Handling

**[A-048]** All errors must be `EMError` cases (§8). No `fatalError()` in production code paths. No force-unwrapping (`!`) on values that could be nil at runtime. `try!` and `as!` are banned outside of test code.

### File Format

**[A-049]** Per `DP-6` and `[D-MD-3]`:
- Never inject proprietary syntax, metadata, or markers into user files
- Never create companion/sidecar files
- Standard CommonMark + GFM only

### Platform Types in EMCore

**[A-063]** EMCore uses `typealias PlatformColor` and `typealias PlatformFont` that resolve to `UIColor`/`UIFont` (iOS) or `NSColor`/`NSFont` (macOS) via conditional compilation. `NSRange` does not appear in EMCore — it is confined to EMEditor's `EditorState`. Cross-platform extraction (for Linux/Android roadmap) will replace these with platform-independent types when needed.

---

## 10. Research Items and Spike Backlog

Items requiring prototyping before implementation. Each has a corresponding backlog entry (`SPIKE-XXX`) that must complete before dependent features can be implemented. Each spike produces a written finding that updates the relevant `[A-XXX]` decision in this document.

| ID | Research Item | Blocks | Resolution Approach | Architecture Decision |
|----|--------------|--------|--------------------|-----------------------|
| **SPIKE-001** ✅ | TextKit 2 <16ms keystroke latency validation | FEAT-039 (Text Engine) | **Complete.** iPhone 15 p95: 6.8ms, iPhone SE p95: 10.3ms. Target met. See `docs/spikes/SPIKE-001.md`. | `[A-004]` — **validated**, proceed with TextKit 2 |
| **SPIKE-002** ✅ | swift-markdown round-trip fidelity | FEAT-038 (Parser) | **Complete.** 100% structural fidelity across 106 CommonMark + GFM cases. AST modification via `MarkupRewriter` works correctly. Formatting normalization is cosmetic only. See `docs/spikes/SPIKE-002.md`. | `[A-003]` — **validated**, proceed with swift-markdown |
| **SPIKE-003** | swift-markdown incremental parsing | FEAT-038 (Parser) | Evaluate if partial re-parse is feasible. If not, design debounce + local-update strategy. Benchmark full re-parse of 10K-line doc. | `[A-003]`, `[A-017]` — informs update strategy |
| **SPIKE-004** ✅ | The Render animation feasibility | FEAT-014 (Signature Transition) | **Complete.** 120fps on iPad Pro (M2) and 60fps on iPhone SE (A15) with up to 450 animating layers. Reduced Motion crossfade validated. 1000-line documents performant. See `docs/spikes/SPIKE-004.md`. | `[A-020]` — **validated**, proceed with snapshot-based Core Animation |
| **SPIKE-005** ✅ | Local AI inference benchmarks + device capability detection | FEAT-041 (AI Pipeline) | **Complete.** MLX Swift selected: 380ms first token on A16 (meets <500ms), 42 MB resident memory (vs 1,850 MB Core ML). Device capability detection validated across 11 device models. See `docs/spikes/SPIKE-005.md`. | `[A-008]`, `[A-033]` — **validated**, proceed with MLX Swift |
| **SPIKE-006** ✅ | Mermaid WKWebView memory impact | FEAT-030 (Mermaid Rendering) | **Complete.** Offscreen WKWebView validated. Hybrid reuse lifecycle: ~30 MB for 10 diagrams. Render latency 180–220 ms warm. SHA256 content hash caching. See `docs/spikes/SPIKE-006.md`. | `[A-006]` — **validated**, proceed with offscreen WKWebView + hybrid reuse |
| **SPIKE-007** ✅ | tree-sitter Swift integration | FEAT-006 (Syntax Highlighting) | **Complete.** `swift-tree-sitter` v0.9.0+ validated. ~6.6 MB for 18 grammars, ~1-2.5 ms highlight for 500-line blocks. Incremental parsing supported. See `docs/spikes/SPIKE-007.md`. | `[A-005]` — **validated**, proceed with tree-sitter via SwiftTreeSitter |
| **SPIKE-008** | Apple platform AI — WWDC 2026 evaluation | FEAT-041 (AI Pipeline) | Evaluate Apple platform AI APIs after WWDC 2026. If on-device writing assistance APIs ship, prototype ApplePlatformAIProvider. | `[A-007]`, `[A-029]` — informs provider strategy |
| **SPIKE-009** | libgit2 Swift bindings for iOS | FEAT-070, FEAT-071, FEAT-072 (GitHub Storage) | Evaluate SwiftGit2 or similar. Prototype clone + commit + push. Measure binary size and App Store compliance. | `[A-064]` — validates git integration approach |

### Spike Output Requirements

Each spike must produce:
1. A written finding (committed to `docs/spikes/SPIKE-XXX.md`)
2. An update to the relevant `[A-XXX]` decision in this document (confirm, revise, or reject)
3. A prototype branch with reproducible benchmarks (if applicable)
4. Unblocking of the dependent feature(s) in the backlog

---

## Appendix: Architecture Decision Index

| ID | Summary | Section |
|----|---------|---------|
| A-001 | SPM workspace with modular packages | §1 |
| A-002 | iOS 17+, macOS 14+ | §1 |
| A-003 | swift-markdown for parsing | §1 |
| A-004 | TextKit 2 text engine | §1 |
| A-005 | tree-sitter for syntax highlighting | §1 |
| A-006 | Mermaid via offscreen WKWebView | §1 |
| A-007 | AIProvider protocol with 3 backends | §1 |
| A-008 | MLX Swift for local inference | §1 |
| A-009 | URLSession + SSE for cloud AI | §1 |
| A-010 | @Observable + unidirectional data flow | §1 |
| A-011 | UserDefaults only, no database | §1 |
| A-012 | StoreKit 2 for purchases | §1 |
| A-013 | Structured concurrency only, no Combine | §1 |
| A-014 | Minimal third-party dependencies | §1 |
| A-015 | Module dependency rules | §2 |
| A-016 | Document model in EMCore, @MainActor-isolated | §3 |
| A-017 | Incremental update strategy with regex-based local updates | §3 |
| A-018 | AST → NSAttributedString rendering | §4.1 |
| A-019 | Shared content storage for rich/source views | §4.2 |
| A-020 | Snapshot-based Core Animation for The Render | §4.3 |
| A-021 | AST source position cursor mapping | §4.10 |
| A-022 | UndoManager with discrete groups, per-scene | §4.11 |
| A-023 | Floating action bar for AI + formatting | §4.12 |
| A-024 | Security-scoped URL lifecycle | §5 |
| A-025 | NSFileCoordinator for all I/O | §5 |
| A-026 | Debounced atomic auto-save | §5 |
| A-027 | NSFilePresenter for external changes | §5 |
| A-028 | Per-scene file coordination, no duplicate files | §5 |
| A-029 | AIProvider protocol definition | §6 |
| A-030 | Runtime provider selection | §6 |
| A-031 | Background model download (removable) | §6 |
| A-032 | Versioned content-aware prompt templates | §6 |
| A-033 | Device capability detection via ProcessInfo | §6 |
| A-034 | WindowGroup + NSUserActivity scenes | §7.5 |
| A-035 | EMError hierarchy with user-facing messages | §8.1 |
| A-036 | VoiceOver + Dynamic Type + Reduced Motion | §8.2 |
| A-037 | os_signpost performance instrumentation | §8.3 |
| A-038 | os_log per-module logging | §8.5 |
| A-039 | Test strategy: unit + integration + UI + perf | §8.6 |
| A-040 | Code placement per module architecture | §9 |
| A-041 | No dependency graph violations | §9 |
| A-042 | Doc comments on all public APIs | §9 |
| A-043 | Accessibility on all UI elements | §9 |
| A-044 | No unauthorized dependencies | §9 |
| A-045 | No sidecar files, database, or analytics | §9 |
| A-046 | @MainActor + signposted performance paths | §9 |
| A-047 | Structured concurrency only, TextSnapshot for background | §9 |
| A-048 | EMError only, no force-unwrap in production | §9 |
| A-049 | Never modify user file format | §9 |
| A-050 | Complete feature-to-package mapping | §2 |
| A-051 | Keystroke interception + auto-format integration | §4.4 |
| A-052 | Theme and TypeScale types in EMCore | §4.5 |
| A-053 | Image loading pipeline | §4.6 |
| A-054 | System spell check integration | §4.7 |
| A-055 | Word count computation strategy | §4.8 |
| A-056 | PDF/print export pipeline | §4.9 |
| A-057 | SubscriptionStatus bridge: EMCore protocol | §6 |
| A-058 | NavigationStack with programmatic router | §7.1 |
| A-059 | Constructor injection at composition root | §7.2 |
| A-060 | Keyboard shortcuts via UIKeyCommand + SwiftUI | §7.3 |
| A-061 | State restoration via UserDefaults + NSUserActivity | §7.4 |
| A-062 | Haptic feedback vocabulary | §8.4 |
| A-063 | Platform type aliases in EMCore | §9 |
| A-064 | GitHub as transparent storage via EMGit (Phase 2) | §5 |
