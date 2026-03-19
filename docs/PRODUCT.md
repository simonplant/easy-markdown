# easy-markdown — Product Document

This document is the single source of truth for what we are building, why, and the decisions that constrain implementation. The backlog is derived from this document. If a decision isn't recorded here, it hasn't been made.

**How to read this document**: Section 1 is the north star (press release + why now). Sections 2–3 establish intent (who we serve, what problems we solve). Sections 4–6 establish constraints (principles, non-goals, and the decisions that bind us). Sections 7–9 define what gets built (features, journeys, phases). Sections 10–13 define how we position, price, grow, and measure.

**Ambition level**: We are not building a nice indie app. We are building **what Cursor is for code, but for every document that isn't code** — with the craft and polish of the best Apple-native apps. In 2026, markdown is the universal format for unstructured data: AI agents produce it, developers write in it, teams collaborate through it. For 99% of documents people create — briefs, reports, READMEs, blog posts, architecture docs — markdown + AI + beautiful rendering is all you need. Word is overkill. Google Docs is overkill. easy-markdown is enough. Every decision in this document should be evaluated against that bar.

---

## 1. Press Release (North Star)

This is the Amazon "working backwards" press release. It describes the product as if it has already shipped. Every decision in this document should be traceable back to making this press release true.

> **FOR IMMEDIATE RELEASE**
>
> ### easy-markdown: Cursor for Prose. Apple-Quality Craft. The Document Tool for the AI Age.
>
> *The AI-native document tool that handles everything from an AI agent's research report to your next product brief — beautifully, privately, on any device.*
>
> **2026** — Markdown has become the universal format for unstructured data. Every AI agent — Claude, ChatGPT, Perplexity, Copilot, Cursor — produces it. Every developer writes in it. Every team collaborates through it. Product briefs, architecture docs, research reports, blog posts, READMEs, meeting summaries — they're all markdown. For 99% of the documents people create, markdown + AI + beautiful rendering is all you need. Word is overkill. Google Docs is overkill.
>
> But the tools haven't caught up. You get a `.md` file from an AI agent and open it in… TextEdit? Notes? You draft a product brief with AI and it lives in… a code editor? There's no tool that treats markdown the way it deserves — as the primary document format of the AI age.
>
> **easy-markdown is that tool.** Open any `.md` file on your device — iCloud Drive, Dropbox, a Git repo, anywhere. Create new documents wherever you have access. Write with AI as your co-author or receive AI-generated content and refine it. Everything renders beautifully: rich text, tables, diagrams, code blocks. When you're done, export a polished PDF or share the `.md` file directly. No vault. No library. No sign-up. No lock-in.
>
> **The interface is outrageously good.** This is what happens when you bring Apple-level craft to a document tool built for the AI age. Intelligent auto-formatting cleans up your markdown as you type. A built-in document doctor catches broken links, inconsistent structure, and formatting issues. Every animation, every gesture, every pixel has been considered. It's the kind of app you show other people because it feels that good to use.
>
> **AI is woven into everything — and you can just talk to it.** Select text and improve it. Get a summary. Continue your thought. Or just speak: *"make this section more concise," "add a conclusion," "rewrite this for a technical audience."* Voice-driven, intent-based editing — describe what you want your document to become, and AI makes it happen. Core AI runs right on your device — private, offline, instant. For heavier tasks, optional cloud-powered Pro AI delivers state-of-the-art results. This is Cursor-level AI intelligence, purpose-built for prose and documents instead of code.
>
> **Markdown in, beautifully rendered out.** Tables, diagrams, code blocks — everything renders inline. When you need to hand a document to someone who doesn't live in markdown, export a polished PDF or print it directly. No Word documents. No proprietary formats. This is the tool that makes markdown the only document format you need.
>
> "Cursor showed what AI-native editing could be for code. easy-markdown is what it should be for everything else," said the easy-markdown team.
>
> easy-markdown launches first on iOS, with native macOS and Linux desktop to follow. The app is a one-time purchase at $9.99 — no subscription required. Pro AI is an optional $3.99/month for users who want cloud-powered capabilities, and you can cancel anytime without losing any app functionality.
>
> **Getting started is instant**: download, open a file, write. That's it.

### What this press release locks in

| Claim | Implication | Constrains |
|-------|-------------|------------|
| "Cursor for prose — the document tool for the AI age" | Must be purpose-built for both writing with AI and receiving/refining AI output. The full workflow — create, receive, refine, render, share — is first-class. Rich content (tables, diagrams, code blocks) renders beautifully. | Feature priorities, persona definitions, AI integration |
| "Apple-quality craft" | UI quality is a shipping requirement. Ship dates slip before UI quality does. This is what separates us from every Electron-based competitor. | Prioritization — quality over scope, always |
| "Opens any `.md` file your device can see" | Must use OS-level file access APIs (UIDocument, file providers), not a custom file store | Architecture, file management |
| "No vault, no library, no sign-up" | Zero-configuration first launch. No onboarding flow, no account creation to start editing. Pro AI uses App Store subscription auth — no separate account. | UX, first-run experience |
| "The interface is outrageously good" | UI quality is a shipping requirement. Ship dates slip before UI quality does. | Prioritization, resourcing |
| "The kind of app you show other people" | Must be visually remarkable enough to trigger organic sharing. This is our growth engine. | Design investment, viral coefficient |
| "You can just talk to it" | Voice-driven intent-based editing using system speech recognition. Speak what you want your document to become. Not dictation — intent interpretation. | AI architecture, speech APIs, interaction design |
| "Auto-formatting cleans up your markdown as you type" | Real-time, inline formatting — not a batch operation or separate mode | Editor architecture |
| "Document doctor catches broken links, inconsistent structure" | Background analysis with inline, non-intrusive suggestions | Editor architecture, UX |
| "Core AI features run right on your device" | On-device inference for core features (improve, summarize, continue). Must work offline with no account. | Architecture — Core ML / MLX for local inference |
| "Optional cloud-powered Pro AI" | Pro tier uses cloud APIs for advanced capabilities. Requires explicit opt-in per-request or per-session. Only selected text is sent, never full documents silently. | Privacy architecture, server infrastructure, billing |
| "The app is a one-time purchase… Pro AI is optional" | Base app is complete and excellent without Pro. Pro is a genuine enhancement, not a crippled free tier. | Pricing, feature gating, UX — no dark patterns |
| "Markdown is the first-class format" | Markdown is the native format. We render, print, and share beautifully — but we never convert to proprietary formats (Word, Pages, etc.). PDF/print is a rendered view, not a conversion. | Format philosophy, export features |
| "Launches first on iOS" | iOS is the first platform, then macOS, then Linux desktop. Not web. Not Windows-first. | Platform sequencing |
| "One-time purchase" | Base app requires no server infrastructure. Pro AI requires a lightweight API relay and App Store subscription validation — minimal server footprint, no user data storage. | Architecture, business model |

### Why now

Five things converged in 2025–2026 that make this product possible and timely:

1. **On-device AI crossed the quality threshold.** Apple's Neural Engine (A16+/M1+), Core ML, and the open-source MLX framework now run 1–4GB quantized language models with usable quality and sub-second latency. Two years ago, local AI writing assistance wasn't viable on a phone. Now it is.
2. **Subscription fatigue peaked.** The App Store is saturated with subscription-based writing tools. Users are vocally pushing back — Bear's subscription pivot, Ulysses's pricing backlash, and the rise of "pay once" indie apps signal a market ready for a premium one-time-purchase alternative.
3. **The IDE/prose split crystallized.** Cursor and GitHub Copilot proved that AI-powered editing is transformative — but only for code. The millions of developers and writers who produce prose in markdown have no equivalent. The "Cursor for prose" positioning didn't exist before Cursor existed.
4. **Incumbents are stuck.** Obsidian can't easily abandon its vault architecture. Bear can't easily open its proprietary storage. Notion can't easily go offline. iA Writer hasn't shipped AI. The market leaders are architecturally constrained from building what we're building. The window is open, but it won't stay open forever.
5. **AI agents produce markdown at scale.** Claude, ChatGPT, Cursor, Perplexity, Copilot, and dozens of specialized AI agents all output markdown — research reports, summaries, product briefs, architecture docs with diagrams. Tens of millions of knowledge workers receive these files daily and open them in TextEdit or Notes. There is no purpose-built tool for consuming, refining, and sharing AI-generated documents. That gap is the opportunity.

---

## 2. Problem Statement

### The market landscape

People who write in markdown face a fragmented, compromised landscape:

| | Great UI | Mediocre UI |
|---|---|---|
| **Locked storage** | Bear, Obsidian, Notion, Ulysses | Day One, Standard Notes |
| **Open files** | iA Writer ($50), Typora (desktop-only) | Notable (stalled), text editors |

And a second dimension no one has cracked:

| | Has AI | No AI |
|---|---|---|
| **Locked storage** | Notion AI, Craft AI | Bear, Obsidian |
| **Open files** | *empty* | iA Writer, Typora, everything else |

And a third dimension that defines our unique position:

| | Purpose-built for AI-generated markdown | Not designed for AI output |
|---|---|---|
| **Great UI** | *empty — this is us* | iA Writer, Bear, Typora |
| **Mediocre UI** | *empty* | TextEdit, Notes, VS Code preview |

**Decision [D-MKT-1]**: We are building at the intersection of five underserved positions: **Apple-quality native UI + open files + AI-native editing (local-first) + affordable + purpose-built for how markdown is actually used in 2026**. No product in the market occupies this space. We serve both directions: writing with AI as co-author AND receiving/refining AI-generated output.

**Decision [D-MKT-3]**: Markdown is the document format for 99% of knowledge work in the AI age. We are the tool that makes that true — for product briefs, architecture docs, research reports, blog posts, READMEs, and everything in between. The full workflow — create, receive, refine, render, share — is first-class. Rich content (tables, diagrams, code blocks) that AI and humans produce must render beautifully and be editable with AI assistance.

### Pain points we solve

| # | Pain point | Our response | Decision |
|---|-----------|--------------|----------|
| P1 | **Vault/library lock-in** — Obsidian requires a vault. Bear uses proprietary storage. Users don't realize they're locked in until they try to leave. | Use only OS-level file access. Never create a proprietary container. | **[D-FILE-1]** No vault, library, or proprietary file store. Ever. |
| P2 | **Platform fragmentation** — Typora is desktop-only. 1Writer is iOS-only. Bear is Apple-only. | Build for cross-platform from day one, ship platforms sequentially. | **[D-PLAT-1]** iOS first, then macOS, then Android, then desktop. |
| P3 | **Subscription fatigue** — Bear, Ulysses, and Craft charge recurring fees for a text editor. | One-time purchase for the app and local AI. Optional subscription only for cloud AI compute — and the app is fully excellent without it. | **[D-BIZ-1]** One-time paid model for the app. Subscription only for cloud compute costs. |
| P4 | **Formatting friction** — Most editors are dumb text boxes. Users manually fix indentation, align tables, chase broken links. | Auto-formatting engine + document doctor as core features, not plugins. | **[D-EDIT-1]** Intelligent editing is built-in and on by default. |
| P5 | **Bloat and complexity** — Obsidian's plugin system is powerful but overwhelming. Notion is a kitchen sink. | Focused feature set. No plugin system. No extensibility API. | **[D-SCOPE-1]** No plugin/extension system. We ship what we ship. |
| P6 | **AI requires cloud and accounts** — Notion AI, Craft AI, and every other AI writing tool sends your content to remote servers, requires an account, and often charges a separate subscription. | Core AI runs on-device with no account. Pro AI is opt-in cloud with transparent privacy. Neither requires an account to use the app. | **[D-AI-1]** Local-first AI. Cloud is opt-in enhancement, not a requirement. |
| P7 | **No purpose-built markdown tool for non-IDE users** — Developers use Cursor/VS Code for code but have no great standalone tool for prose. Writers have no tool that combines AI + open files + great UI. | Be the app developers open alongside their IDE, and the app writers open instead of one. | **[D-MKT-2]** Position as the complement to IDEs, not a competitor. |
| P8 | **No AI-native document tool for markdown** — AI agents produce `.md` files (research reports, summaries, briefs, architecture docs) and people co-author documents with AI, but there's no tool purpose-built for this workflow. Users bounce between TextEdit, Notes, Google Docs, and code editors. | Be the AI-native document tool: write with AI, receive AI output, refine, render beautifully (tables, diagrams, code blocks), share as polished PDF. One tool for the full workflow. | **[D-MKT-3]** Markdown is the document format for 99% of knowledge work in the AI age. We are the tool that makes that true. |

---

## 3. Target Users

### Primary persona: The AI-Native Knowledge Worker

> *"I write product briefs, review AI research reports, draft architecture docs — all in markdown, all with AI helping me. I need a tool that makes these documents look beautiful, helps me write and refine with AI, and lets me share polished output. I don't think of myself as 'a markdown user' — I'm someone who creates documents in the AI age."*

- **Creates** documents with AI as co-author: product briefs, reports, proposals, blog posts
- **Receives** `.md` files from AI agents (Claude, ChatGPT, Perplexity, Cursor, custom agents) — research reports, summaries, analysis
- **Refines** content: tightens prose, fixes structure, adjusts tone, updates diagrams with AI assistance
- **Shares** polished output: PDF export to stakeholders, share sheet to colleagues
- Needs rich content (tables, diagrams, code blocks) to render beautifully — not as raw syntax
- May not know or care about markdown syntax — interacts through rich view and AI assist
- **Platforms**: iPhone + Mac most common, but cross-platform matters
- **Scale**: Tens of millions of knowledge workers who create and consume markdown daily through AI tools. This is not a niche — it's everyone who does knowledge work with AI, and that number is growing exponentially.

**Decision [D-USER-1]**: This is our primary user. When trade-offs arise, optimize for this persona. They value AI-assisted writing, beautiful rendering of rich content (tables, diagrams, code blocks), and polished sharing. They may never toggle to source view — and that's fine.

### Secondary persona: The Builder

> *"I'm a product manager / engineer / technical writer. I write product briefs, architecture docs, API docs, READMEs. AI co-authors everything. I want Cursor for prose — an editor that understands my content and helps me make it better."*

- Product managers writing PRDs and briefs
- Engineers writing architecture docs, ADRs, READMEs
- Technical writers producing API docs, guides, changelogs
- AI is a co-author on everything — they write with AI, not just consume AI output
- Rich content matters: architecture diagrams, flowcharts, tables, code examples are part of their daily output
- Cares about where files live — uses Git repos, iCloud, Dropbox
- This persona is our loudest referral channel — builders recommend tools to each other

**Decision [D-USER-2]**: We serve this persona with deep investment. They overlap with our primary persona but are more hands-on with markdown syntax. Keyboard shortcuts, fast file switching, and AI that understands code-adjacent writing (changelogs, API docs) matter. We will not add Vim bindings, terminal integration, or Git integration — this is not an IDE.

### Tertiary persona: The Content Creator

> *"I'm a blogger / devrel / docs team member. Markdown is my source format. AI helps me draft, I refine, I publish."*

- Bloggers, developer relations professionals, documentation teams
- Markdown is the source format for their publishing pipeline (Hugo, Jekyll, Docusaurus, etc.)
- AI assists with drafting, but they own the final voice and structure
- Values great typography and rendering — their content needs to look good in the editor too

**Decision [D-USER-3]**: We serve this persona naturally. Our open-file model, AI assistance, and beautiful rendering serve their workflow without special investment. We will not build publishing pipelines (D-NO-4) but we make their source files look great.

### Scale consideration

The addressable market has shifted dramatically. The old framing of "markdown enthusiasts" understates the opportunity by an order of magnitude. Every knowledge worker whose AI tools produce markdown is a potential user — and that number is in the tens of millions and growing rapidly as AI agent adoption accelerates.

**Decision [D-USER-4]**: We are building for a global audience from day one. The product must work excellently for non-English writing (CJK text, RTL languages, accented characters, emoji). Localization of the UI is Phase 2; correct rendering and editing of all languages is Phase 1 / P0.

---

## 4. Design Principles

These are non-negotiable. They resolve ambiguity when the backlog doesn't have a clear answer.

### DP-1: Open by default
The file system is our storage layer. We use the OS file picker to open files and the OS file system to save them. We never create a vault, database, index, library, or proprietary container. If the user deletes easy-markdown, their files are untouched.

**What this means in practice**:
- No app-specific directory structure
- No sidecar files (`.easy-markdown/`, metadata files, etc.)
- No SQLite database for file indexing
- Recents list uses OS-provided recent file APIs or a lightweight local preference store (UserDefaults)
- Search is file-system-based, not index-based

### DP-2: UI is the product
The interface is the primary differentiator. It is not a wrapper around a markdown parser. Every screen, transition, animation, and micro-interaction is a product decision that receives disproportionate investment. **This is how we become the defacto editor** — the quality has to be so high that people can't go back.

**What this means in practice**:
- UI quality is a blocking criterion for every release. A feature does not ship if it doesn't meet the bar.
- Typography is custom, not system defaults. We choose and license typefaces intentionally.
- Animations are designed: spring curves, durations, and easing are specified per-interaction. No generic UIKit/SwiftUI defaults.
- Haptic feedback on key interactions (list completion, doctor fix accepted, file saved confirmation). Subtle and purposeful — never gratuitous.
- Touch targets, spacing, and color are treated as carefully as feature logic.
- We allocate design time for every backlog item, not just "feature" items.

**Decision [D-UI-1]**: We will not ship any feature where the UI has not been explicitly designed, reviewed, and polished. No "we'll clean it up later" — the UI ships finished or it doesn't ship.

### DP-3: The editor should be smart
The gap between "text box" and "intelligent editor" is where we differentiate. Auto-formatting, document doctor, and local AI are not secondary features — they are core to the value proposition.

**What this means in practice**:
- Auto-formatting runs inline, in real time, as the user types — not as a batch command
- Document doctor runs in the background and surfaces suggestions non-intrusively
- Local AI is available with a single gesture/shortcut — no mode switching, no menus to dig through
- All three systems are on by default. Users can disable individual rules but the default is "smart."
- We invest in these systems continuously — they get better every release

### DP-4: Native on every platform
Each app feels like it was built for that platform. We respect platform conventions for navigation, gestures, keyboard shortcuts, typography, and system integration.

**What this means in practice**:
- iOS app uses standard iOS navigation patterns (sheets, swipe gestures, SF Symbols)
- macOS app uses standard macOS patterns (menu bar, keyboard shortcuts, window management)
- We do not use a cross-platform UI framework that produces lowest-common-denominator interfaces
- Platform-specific features (e.g., Shortcuts on iOS, Services on macOS) are first-class

**Decision [D-PLAT-2]**: We use native UI frameworks (SwiftUI for Apple platforms). We do not use Electron, React Native, Flutter, or similar cross-platform UI frameworks. Shared logic (parsing, formatting engine, AI pipeline) may be cross-platform; UI is always native.

### DP-5: Simplicity is a feature
We do fewer things extraordinarily well. Every feature added is one that must be maintained, supported, and not break. The default answer to "should we add X?" is no.

**What this means in practice**:
- Features require a clear connection to a pain point in Section 2 or a claim in the press release
- "Other apps have it" is not a justification for adding a feature
- Removing a feature that isn't working is a valid product decision
- Settings and preferences are minimal. Opinionated defaults over configuration.

### DP-6: No lock-in, ever
Standard markdown in, standard markdown out. We never inject proprietary syntax, metadata, front matter, or markers into files. We support CommonMark + GFM (see [D-MD-1]) and do not extend it.

**What this means in practice**:
- We do not invent custom markdown syntax
- We do not add front matter to files
- We do not create companion/sidecar files alongside the user's files
- We render widely-adopted extended syntax (Mermaid diagrams) beautifully. AI may modify existing Mermaid blocks at user request — this is editing existing content, not generating proprietary syntax.

### DP-7: AI is local-first, private, and instant
AI is a core capability of the editor, not a bolted-on chatbot. It follows a **local-first** architecture: core AI features run on-device (private, offline, instant), while optional Pro AI uses cloud inference for advanced capabilities that exceed on-device model limits.

**What this means in practice**:
- **Local AI** (included with app purchase): Uses Apple Core ML / MLX for on-device inference. Works offline. No account needed. Covers: improve writing, summarize, continue writing, smart completions.
- **Pro AI** (optional $3.99/mo subscription): Uses cloud APIs for capabilities that need larger models — advanced translation, tone adjustment, document-level analysis, generation from prompts. Sends only the user-selected text to the API (never the full document silently). Requires explicit opt-in.
- AI never modifies the document without user consent — it suggests, the user accepts
- AI features are integrated into the editing flow (inline suggestions, selection-based actions) — not a separate chat panel
- The app is fully functional and excellent without Pro AI. There is no degraded experience, no nag screens, no feature-shaped holes that push you toward subscribing.

**Decision [D-AI-1]**: Local-first AI architecture. Core AI runs on-device. Cloud AI is opt-in enhancement. The app never requires network access for AI. If a user never subscribes to Pro, they still have a best-in-class AI-assisted editor.

**Decision [D-AI-2]**: Two-tier AI model. Local AI is included in the one-time app purchase. Pro AI is an optional monthly subscription ($3.99/mo) that covers our GPU/inference costs. This is the only recurring charge — and it's genuinely optional.

### DP-8: Graceful degradation
When things go wrong, the user should never lose work or feel confused. Errors are handled quietly and recoverably. The app always prioritizes data safety over feature availability.

**What this means in practice**:
- If AI model download fails, the editor works perfectly — AI features are simply absent
- If auto-save fails (disk full, permissions revoked), the document stays in memory and the user is notified non-modally with a retry option. Content is never silently lost.
- If an iCloud file is evicted from local storage while open, we detect it and offer to re-download or save locally
- If a Pro AI cloud request fails, we show the error inline and suggest retrying or using local AI instead
- If the device runs out of storage during model download, we cancel gracefully and explain
- Every error state has been designed — not just coded. Error messages are human, not technical.

**Decision [D-ERR-1]**: No error state is undesigned. Every feature spec must include failure modes and recovery paths. "What happens when this fails?" is a required question in every backlog item review.

### DP-9: The Render — our signature interaction
When you open a file or toggle from source to rich view, the markdown doesn't just swap — it *transforms*. Raw markdown characters gracefully animate into their rendered form: `#` markers shrink as the heading scales up, `**` markers dissolve as text boldfaces, list markers morph into styled bullets, code fences fade as the code block materializes with its background. ~400ms, spring-animated, every time.

This is the single most important "show someone" moment in the product. It demonstrates our value proposition in one gesture: we understand markdown AND we care about beauty. It's the thing people will describe when they recommend easy-markdown.

**What this means in practice**:
- The source-to-rich transition is a designed animation, not a state swap
- It uses native Core Animation for 120fps fluidity — this is something Electron apps can't match
- It has a Reduced Motion alternative (instant crossfade) per DP-8/[D-A11Y-3]
- It receives disproportionate engineering and design investment
- It works beautifully on every device class (iPhone SE through iPad Pro)

**Decision [D-UX-3]**: The Render is a named, protected design element. It is never simplified, removed, or made optional for performance reasons. If it doesn't perform at 120fps, we fix the implementation — we don't cut the feature. It is easy-markdown's brand.

### DP-10: Accessible to everyone
The best editor in the world works for everyone. Accessibility is a P0 requirement, not a P1 enhancement. This is both a moral imperative and a practical one — Apple's review process flags accessibility issues, and accessible apps have broader reach.

**What this means in practice**:
- Full VoiceOver support on all screens (iOS and macOS)
- Dynamic Type support — the editor respects the user's system text size preference
- Reduced Motion support — animations are suppressed or simplified when the user has enabled Reduce Motion
- Sufficient color contrast in all themes (WCAG AA minimum)
- All functionality reachable via keyboard (macOS) and assistive technologies
- No information conveyed by color alone (doctor indicators use shape + color)

**Decision [D-A11Y-1]**: Every feature spec (F-XXX) must include accessibility acceptance criteria. A feature that doesn't work with VoiceOver doesn't ship.

---

## 5. Non-Goals and Boundaries

These are explicit decisions about what we will **not** build. They exist to prevent scope creep and to give clear "no" answers when feature requests arrive.

| Non-goal | Why | Decision |
|----------|-----|----------|
| **Personal knowledge management** (graph views, backlinks, bidirectional links) | Obsidian owns this space. Competing here dilutes our focus and pulls us toward vault-based storage. | **[D-NO-1]** No PKM features. |
| **Note-taking database** (tags DB, search index, metadata layer) | Requires a proprietary data layer, violating DP-1 and DP-6. | **[D-NO-2]** No database. Files are the source of truth. |
| **Real-time collaboration** (co-editing, shared workspaces, comments) | Requires server infrastructure and accounts, violating the press release promise. | **[D-NO-3]** No collaboration. Personal tool only. |
| **Publishing pipelines** (CMS integration, static site generation, blog deployment) | We render, print, and share markdown beautifully — but we don't build publishing pipelines. Write here, publish via your own tools. | **[D-NO-4]** No publishing pipelines. Render/print/share are in scope. |
| **Proprietary document formats** (Word, Pages, Google Docs, RTF conversion) | Markdown is the format. We never convert to or from proprietary formats. PDF/print is a rendered view of markdown, not a format conversion. | **[D-NO-12]** No proprietary format import/export. |
| **General-purpose code editing** (multi-language support, LSP, terminal) | We are a markdown editor, not an IDE. Developers have Cursor/VS Code. | **[D-NO-5]** Markdown-first. No general editing. |
| **Plugin/extension system** | Complexity multiplier. Breaks UI quality guarantee. Obsidian already won this. | **[D-NO-6]** No plugins. No extension API. |
| **Free tier or ad-supported model** | Misaligns incentives. We work for the user, not advertisers. | **[D-NO-7]** Paid only. |
| **Cloud sync** | We don't build sync. Users bring their own (iCloud, Dropbox, Git). | **[D-NO-8]** No proprietary sync. |
| **Accounts required to use the app** | The editor and local AI work without any account. App Store receipt validates purchase. Pro AI subscribers authenticate via App Store subscription — no separate account system we build/maintain. | **[D-NO-9]** No proprietary account system. App Store handles auth for subscriptions. |
| **Cloud AI as a requirement** | The app must be fully excellent without cloud AI. Cloud is an opt-in enhancement for users who want more, not a crutch for missing local capability. | **[D-NO-10]** Cloud AI is never required. Never silently defaults to cloud. User opts in explicitly. |
| **AI chat/conversational interface** | We're an editor with AI assistance, not a chatbot. AI surfaces inline, not in a side panel. | **[D-NO-11]** No chat panel. AI is woven into the editing experience. |

---

## 6. Decision Log

All significant product and technical decisions are recorded here. Each decision has an ID, is referenced throughout the document, and includes rationale and alternatives considered.

### Markdown

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-MD-1** | Support **CommonMark + GitHub Flavored Markdown (GFM)** as the baseline spec. | GFM is the de facto standard. It covers tables, task lists, strikethrough, and autolinks — features users expect. CommonMark alone is too limited. | CommonMark only (too restrictive); MultiMarkdown (less adoption); Custom superset (violates DP-6). |
| **D-MD-2** | **Mermaid diagram rendering is P1 (v1.0). AI-assisted Mermaid editing is P1. KaTeX math and footnotes remain render-only, Phase 3.** Mermaid is core to AI-generated markdown — architecture diagrams, flowcharts, sequence diagrams, ER diagrams appear constantly in AI output. We render Mermaid beautifully inline. AI can modify Mermaid blocks from natural language (select block → describe change → AI rewrites the Mermaid code). We do not build a visual diagram editor — AI is the interface, code is the source, render is the output. | AI agents frequently produce Mermaid diagrams in markdown output. Rendering them is essential for our primary persona (AI-Native Knowledge Worker). AI-assisted editing of Mermaid blocks is a natural extension of our AI assist pattern. KaTeX and footnotes are less common in AI output and can wait. | Ignore Mermaid (broken experience for AI output); Visual diagram editor (different product, violates DP-5); All extended syntax at once (scope creep). |
| **D-MD-3** | We do not invent or support custom syntax extensions. | Violates DP-6 (no lock-in). If we generate syntax only easy-markdown understands, we've created lock-in through content. | Proprietary extensions for features like callouts (rejected — use standard blockquotes). |

### Editor

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-EDIT-1** | Intelligent editing (auto-format + document doctor + local AI) is **built-in, on by default**. | This is our core differentiator. It must be a first-run experience, not something users discover in settings. | Plugin-based (rejected — violates D-NO-6); Off by default (rejected — undermines positioning). |
| **D-EDIT-2** | Editor mode is **rich text with markdown source access**. Primary experience is a styled, WYSIWYG-like view. Users can toggle to raw markdown. | Our target user wants to write, not wrangle syntax. Rich text with source toggle serves both primary and secondary personas. | Source-only with preview pane (developer-centric, not our primary user); Pure WYSIWYG (hides markdown completely, breaks mental model); Side-by-side split (wastes screen real estate on mobile). |
| **D-EDIT-3** | Auto-formatting operates **inline and in real time** as the user types. Not a batch/on-save operation. | The "smart editor" promise requires immediate feedback. Batch formatting feels like a linter, not an intelligent editor. | On-save formatting (too late, breaks flow); Manual trigger (too hidden); Background with undo (confusing when text changes unexpectedly). User can undo any auto-format action. |
| **D-EDIT-4** | Document doctor suggestions are **non-modal, inline indicators** (e.g., subtle underlines, margin icons). User taps/clicks to see the suggestion and accept/dismiss. | Must not interrupt writing flow. Modal dialogs or toasts that demand attention violate DP-2 and DP-5. | Modal dialog (disruptive); Bottom panel (takes space); Separate mode (too hidden). |
| **D-EDIT-5** | Auto-save is **always on, automatic, with no manual save action**. Files saved continuously as user types (debounced). | Matches modern iOS/macOS expectations. Eliminates data loss anxiety. | Manual save (outdated UX); Save on close (risk of data loss); Prompt to save (unnecessary friction). |
| **D-EDIT-6** | **Undo/redo is per-session, in-memory, unlimited depth.** Closing a file clears undo history. | Persistent undo requires a sidecar file or database, violating DP-1 and DP-6. | Persistent undo (requires sidecar storage); Limited undo depth (arbitrary, frustrating). |
| **D-EDIT-7** | **Use the system spell checker (UITextChecker / NSSpellChecker).** Red underline squiggles on misspelled words, standard right-click/tap correction menu. Spell check is on by default, respects the user's system language settings. We do not build a custom spell checker. | Users expect spell check in any writing tool. The OS spell checker is free, mature, multilingual, and already integrated with the text system. Building our own adds complexity for no benefit. | Custom spell checker (unnecessary, violates DP-5); AI-only grammar correction (too slow for real-time spell check, not a replacement for squiggles); No spell check (unacceptable for "best in the world"). |

### AI

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-AI-1** | **Local-first AI.** Core AI (improve, summarize, continue, smart completions) runs on-device via Core ML / MLX. Works offline. No account. Pro AI uses cloud inference for advanced features. User must explicitly opt in to cloud. | Local-first preserves privacy as the default while allowing us to ship advanced capabilities (translation, generation, document analysis) that exceed on-device model limits. Gets better features to market faster without waiting for hardware to catch up. Pure-local limits us to what a phone can run; pure-cloud violates privacy positioning. Hybrid is the pragmatic path. | Pure local only (limits capability, slower to market for advanced features); Pure cloud (violates privacy promise, requires account); No AI (rejected — in 2026 this is expected, and AI is a differentiator). |
| **D-AI-2** | **Two-tier AI pricing.** Local AI included in $9.99 one-time purchase. Pro AI is $3.99/month optional subscription. | Cloud inference has real GPU costs we can't absorb in a one-time purchase. A modest subscription for the cloud tier is honest pricing — the user is paying for compute, not for the app. The base app with local AI is genuinely excellent on its own. This model is proven (Obsidian: free app + paid sync; iA Writer: app + no recurring). | All AI included in one-time price (unsustainable — GPU costs are per-use); AI subscription for everything (alienates users who just want local); Token/usage limits on free tier (creates anxiety, dark pattern); No cloud tier (limits capability, slower to market). |
| **D-AI-3** | **AI surfaces inline in the editing flow.** Select text → AI action menu. Place cursor → AI can suggest. No chat panel, no sidebar, no separate mode. | AI should feel like a native capability of the editor, like spell check feels native to the OS. Separate panels create a mode switch that breaks writing flow. | Chat sidebar (rejected — [D-NO-11]); Floating palette (considered — may use for some actions); Command bar only (too hidden). |
| **D-AI-4** | **AI never modifies the document without explicit user action.** Suggestions appear as previews/diffs. User accepts, edits, or dismisses. | User agency is paramount. Unsolicited text changes break trust and flow. This is the difference between "AI-assisted" and "AI-possessed." | Auto-apply suggestions (rejected — too aggressive); Background rewriting (rejected — violates user trust). |
| **D-AI-5** | **Use Apple Core ML / MLX framework for on-device inference.** Target model size: 1–4GB quantized. Minimum device: iPhone 15 / M1 Mac for local AI features. Older devices get auto-format and doctor but not generative AI. | Apple's on-device ML stack is mature and optimized for their silicon. Limiting generative AI to capable hardware ensures quality — a bad AI experience is worse than none. | ONNX Runtime (less Apple-optimized); llama.cpp (viable alternative, evaluate during implementation); Ship to all devices regardless of quality (rejected — quality bar). |
| **D-AI-6** | **AI capabilities ship incrementally.** MVP ships with local AI (improve, summarize, continue). Pro AI cloud tier ships in v1.0 with translation, tone, generation. | Ship what works well first. Local AI validates the concept. Cloud AI extends it for users who want more. Shipping cloud in v1.0 (not MVP) gives us time to build the infrastructure without delaying launch. | Ship everything at once (risk of low quality); Wait until AI is "complete" (delays launch); Ship cloud in MVP (too much infrastructure for launch). |
| **D-AI-7** | **Pro AI cloud provider: use best-available API (initially Anthropic Claude or equivalent).** Evaluate on quality, latency, cost, and privacy policy. Provider can be swapped without user-facing changes. | We are not building our own inference infrastructure. Using a managed API gets us to market fast. Provider abstraction means we're not locked in. | Self-hosted inference (too expensive at our scale); OpenAI only (single vendor risk); Build our own (premature). |
| **D-AI-8** | **Pro AI privacy: only user-selected text is sent. No full-document context unless user explicitly includes it. No data retained by provider beyond request processing.** | Trust is earned. Users must feel confident that Pro AI isn't silently reading their files. Minimal data transmission + contractual no-retention from the provider. | Send full document for context (better AI quality, but privacy violation); Log prompts for improvement (violates trust); Allow provider training on data (violates trust). |
| **D-AI-9** | **AI model is downloaded separately from the app, on-demand, over Wi-Fi by default.** App ships at < 50MB (no model bundled). On first launch on a capable device, a non-blocking prompt offers to download the AI model (~2–4GB). Download happens in the background — the editor is fully usable (minus AI) during download. Cellular download requires explicit user opt-in. Model updates ship independently from app updates via on-demand resources (ODR) or background asset download. | App Store has a 200MB cellular download limit. Bundling a 4GB model would make the app undownloadable on cellular and slow to install. Separating the model respects the user's bandwidth and storage while keeping the editor instantly usable. | Bundle model with app (too large, bad first install); Download on first AI invocation only (surprise 4GB download when user wants to use a feature); Require Wi-Fi for app download (too restrictive). |

### Platform

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-PLAT-1** | Ship order: **iOS → macOS → Linux desktop → Android**. | iOS validates the core thesis mobile-first. macOS follows because SwiftUI shares well and our primary users are in the Apple ecosystem. Linux desktop is next because developers (our secondary persona) live on Linux and markdown is a developer-native format — this audience is underserved and vocal. Android follows based on demand. Windows is not a priority (developers on Windows increasingly use WSL/Linux). | macOS first (larger screen, but mobile-first validates simplicity); Web first (wide reach, but violates DP-4); Windows before Linux (rejected — our developer audience skews Linux). |
| **D-PLAT-2** | **SwiftUI for all UI** on Apple platforms. Shared logic (parser, formatter, doctor, AI pipeline) in **Swift** with potential future extraction to cross-platform (Kotlin Multiplatform or Rust) when Android ships. | SwiftUI delivers native feel with significant iOS/macOS code sharing. Premature cross-platform adds complexity before validation. | UIKit (more mature but harder to share with macOS); Flutter (violates DP-4); React Native (violates DP-4); KMP from day one (premature). |
| **D-PLAT-3** | **iOS 17+ minimum deployment target.** | iOS 17 has 90%+ adoption. Modern SwiftUI APIs, document-based app improvements, file provider enhancements. | iOS 16 (limits SwiftUI); iOS 18 (too restrictive). |

### File Handling

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-FILE-1** | **No vault, library, or proprietary file store.** All file access via OS file picker and file coordination APIs. | Core product promise. Any deviation undermines the value proposition. | App-managed library (rejected — this is what we're disrupting); Bookmarked folders (Phase 2 opt-in convenience, never required). |
| **D-FILE-2** | **File encoding: UTF-8 only.** Non-UTF-8 files show an error. No conversion or guessing. | UTF-8 is universal. Encoding detection is a source of bugs and data corruption. | Auto-detect (fragile); Multiple encodings (complexity for no benefit). |
| **D-FILE-3** | **Line endings: preserve on read, default to LF on create.** | Preserving line endings prevents unnecessary diffs in version-controlled files. | Normalize to LF (breaks Git diffs for CRLF files); Platform default (inconsistent). |
| **D-FILE-4** | **Large files: 1MB soft limit with dismissable warning. No hard limit.** | Most markdown <100KB. Warning protects against accidental opens; no hard limit respects user agency. | Hard limit (too restrictive); No limit (UI freeze risk). |
| **D-FILE-5** | **File conflict: last-write-wins with notification.** External changes detected → user chooses reload or keep. | User agency beats automatic merging. | Auto-reload (loses edits); Merge (too complex); Ignore (loses awareness). |
| **D-FILE-6** | **Supported extensions: `.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, `.mdx`.** File picker filters to these extensions. We are a markdown editor — not a general text editor. Every feature (rendering, doctor, auto-format, AI) is optimized for markdown. Opening non-markdown files is out of scope. | Stay in our lane. Markdown is our format. Opening config files and CSVs dilutes what we are and creates edge cases we don't want to maintain. If you need a text editor, use one. If you need a markdown editor, use easy-markdown. | All text files (scope creep, dilutes identity); `.md` only (too restrictive — `.markdown` and `.mdown` are common). |

### Business

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-BIZ-1** | **One-time purchase for the app. Optional subscription only for cloud AI compute.** | The editor itself is never a subscription. Subscription fatigue is a pain point we solve (P3) — so we only charge recurring for a service with genuine recurring costs (GPU inference). The app works completely without subscribing. | Full subscription (contradicts positioning); Freemium ([D-NO-7]); All-inclusive one-time (unsustainable with cloud AI costs). |
| **D-BIZ-2** | **App price: $9.99 USD one-time. Pro AI: $3.99/month.** | $9.99 signals quality for the app. $3.99/mo for Pro AI is low enough to be a no-brainer for active users, high enough to cover API costs with margin. At ~$48/year for Pro, we're still cheaper than Bear ($30/yr) + any AI tool, and dramatically cheaper than Ulysses ($50/yr) or Notion ($96/yr). | $4.99 app (too low); $7.99/mo Pro (too high, approaches full subscription apps); $1.99/mo Pro (doesn't cover costs); Usage-based/token pricing (creates anxiety). |
| **D-BIZ-3** | **Major version paid upgrades (v2, v3). Free updates within major version.** Existing version continues working indefinitely. | Sustainable without subscriptions. Rewards loyalty. Doesn't hold current version hostage. | Free forever (unsustainable); Yearly paid updates (feels like subscription); Feature tiers (complexity). |
| **D-BIZ-7** | **Pro AI offers both monthly ($3.99/mo) and annual ($29.99/yr) plans.** Annual plan saves ~37% and is prominently presented. | Annual plans increase LTV (~$21 net vs ~$2.80/mo net after Apple cut), reduce churn, and align with App Store best practices. Apple also reduces commission to 15% on subscriptions after year one. The annual plan is the better deal for both user and us. | Monthly only (higher churn, lower LTV); Annual only (too much commitment upfront); Weekly (too granular, feels exploitative). |
| **D-BIZ-4** | **No third-party analytics, no telemetry, no data exfiltration.** We use only Apple-provided App Store Connect metrics (downloads, retention, sales, crash reports) and aggregate on-device counters (see D-BIZ-6). | Aligns with privacy positioning. Third-party SDKs are a liability and a trust violation. Apple's built-in metrics are sufficient for business-level decisions. | Third-party analytics SDK (rejected — trust violation, bloat); No measurement at all (can't validate success metrics, flying blind). |
| **D-BIZ-6** | **On-device aggregate counters for feature validation.** The app tracks simple counts locally (e.g., "AI improve used 12 times this week," "doctor fixes accepted: 5") stored in UserDefaults. These are never transmitted. They power the status bar stats and inform opt-in App Store review prompts (e.g., only prompt after user has used AI 10+ times). If we ever need feature-level metrics, we may add a voluntary, opt-in "share usage summary" — but not at launch. | We need to know if AI features are being used to validate our thesis. On-device counters achieve this without any data leaving the device. | No feature tracking (can't validate AI adoption metric); Server-side analytics (violates privacy); Always-on telemetry (rejected). |

### Performance

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-PERF-1** | **Cold launch to editing-ready: < 1 second on supported devices.** App opens, last file loads, cursor is active — under 1 second. | First impression. A slow launch undermines the "just open and write" promise. "Best in the world" means best-in-class performance. | No target (too vague); 2 seconds (not competitive); 500ms (aggressive for file I/O, stretch goal). |
| **D-PERF-2** | **Keystroke-to-render latency: < 16ms (60fps).** Every keystroke renders the updated styled view within one frame. | Writing must feel instantaneous. Any perceptible input lag kills the "outrageously good" promise. | 33ms/30fps (perceptible lag on scrolling); No target (quality drift). |
| **D-PERF-3** | **Scroll performance: 120fps on ProMotion devices, 60fps on all others.** No dropped frames during scroll. | Scroll jank is the most noticeable performance flaw in a text editor. ProMotion support signals native quality. | 60fps everywhere (doesn't leverage ProMotion); No target (scroll jank creeps in). |
| **D-PERF-4** | **AI response: first token within 500ms, full response within 3 seconds** for typical operations (improve paragraph, fix grammar). | AI must feel fast enough that users don't context-switch while waiting. 500ms matches human perception of "instant." | No latency target (quality drift); 1 second first token (too slow for inline feel); Stream tokens (yes, also do this — progressive display). |
| **D-PERF-5** | **Memory: < 100MB for a typical editing session** (single file < 100KB). | iOS aggressively kills background apps. Low memory footprint improves state restoration and multitasking. | No target (memory bloat); 50MB (too aggressive with AI model loaded — model may be memory-mapped separately). |

### Quality Assurance

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-QA-1** | **Every feature passes a 4-gate review before shipping: Design Review → Implementation Review → Device Test Matrix → Accessibility Audit.** Design Review: matches the approved design spec. Implementation Review: code review with performance profiling. Device Test Matrix: tested on iPhone SE, iPhone 15 Pro, iPad Mini, iPad Pro (and macOS equivalents in Phase 2). Accessibility Audit: VoiceOver, Dynamic Type at all sizes, Reduced Motion. | D-UI-1 says "no feature ships with unfinished UI." D-A11Y-1 says "no feature ships without VoiceOver." These promises need enforcement mechanisms, not just principles. | Ship and fix later (violates D-UI-1); Manual spot checks (inconsistent); Automated-only testing (misses design quality). |
| **D-QA-2** | **Performance regression tests run on every build.** Automated tests measure cold launch time, keystroke-to-render latency, scroll FPS, and memory usage against the targets in D-PERF-1 through D-PERF-5. A regression that crosses any threshold blocks the build. | Performance degrades gradually unless actively monitored. "Best in the world" performance requires continuous measurement, not periodic audits. | Manual performance testing (inconsistent, easy to skip); No automation (performance slowly degrades). |

### App Store Risk

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-STORE-1** | **Subscription terms clearly communicated before paywall.** Pro AI subscription screen must: show price, billing frequency, and annual option prominently; state what's included and what happens on cancellation; link to terms of service. This follows Apple's App Store Review Guideline 3.1.2. | Apple rejects apps that obscure subscription terms. We also genuinely want transparency — it's our brand. | Minimal disclosure (rejected — risks rejection and violates D-BIZ-5). |
| **D-STORE-2** | **AI-generated content is not labeled in-document, but the AI origin is clear in the UX flow.** The inline diff preview makes it obvious that text was AI-suggested. We do not inject "generated by AI" markers into the markdown (violates DP-6). If Apple requires content labeling in the future, we comply via UX, not file modification. | Apple's AI guidelines are evolving. Our inline-diff UX already makes AI involvement transparent to the user. Injecting metadata into files would violate our no-lock-in principle. | Add "AI-generated" metadata to files (rejected — violates DP-6); Hide AI origin (rejected — dishonest). |
| **D-STORE-3** | **App is fully functional at download (minus model download).** The editor, auto-formatting, document doctor, themes, keyboard support, and all non-AI features work immediately. AI features become available after model download. The app is never a "shell" that requires a download to function. This satisfies Apple's minimum functionality requirement (Guideline 4.2). | Apple rejects apps that are not functional at download. Our architecture naturally satisfies this because the editor doesn't depend on the AI model. | Bundle model (app too large); Require download before any use (rejected — violates D-UX-1 and Apple guidelines). |

### Accessibility

| ID | Decision | Rationale | Alternatives considered |
|----|----------|-----------|------------------------|
| **D-A11Y-1** | **Full VoiceOver support is P0 for every feature.** No feature ships without VoiceOver working correctly. | The best editor in the world works for everyone. Accessibility is not optional. Apple's review process also flags VoiceOver issues. | P1 accessibility (rejected — creates debt that never gets paid); Partial support (rejected — incomplete VoiceOver is worse than none). |
| **D-A11Y-2** | **Dynamic Type support.** Editor and UI chrome scale with the system text size preference. | Large text users are a significant population. An editor that doesn't respect their preference is broken. | Fixed font sizes (rejected); Partial Dynamic Type (rejected — either it works or it doesn't). |
| **D-A11Y-3** | **Reduced Motion support.** All animations have a reduced-motion alternative (crossfade, instant, or suppressed). | Motion sensitivity is real. Our investment in animation must not exclude people. | Ignore Reduce Motion (rejected — violates HIG and excludes users). |

---

## 7. Feature Specifications

Features are organized by priority tier. Each feature has acceptance criteria that define "done" for backlog purposes. Every feature implicitly includes: VoiceOver works correctly, Dynamic Type respected, Reduced Motion alternative exists.

### P0 — Must ship in MVP (blocks launch)

#### F-001: Open File
Open any markdown file on the device via the system file picker.

- Uses `UIDocumentPickerViewController` for file selection
- Supports extensions per [D-FILE-6]
- Opens file, reads contents as UTF-8 per [D-FILE-2]
- Shows error if file is not valid UTF-8 (does not crash, does not corrupt)
- Shows warning if file > 1MB per [D-FILE-4]
- File is editable immediately after opening
- **Performance**: File open → editing ready < 500ms for files < 100KB
- **Accessibility**: VoiceOver announces "File opened, [filename], editing" on successful open
- **Acceptance**: User can open a `.md` file from iCloud Drive, edit it, and the edit is saved back to the same file in place.

#### F-002: Create File
Create a new markdown file at any location the user has write access.

- User chooses save location via system file picker
- New file created with LF line endings per [D-FILE-3]
- Default filename: `Untitled.md` (user can rename in picker)
- File is immediately opened for editing after creation
- **Acceptance**: User can create a new `.md` file in any accessible location and begin writing immediately.

#### F-003: Rich Text Editor
Primary editing experience — styled, WYSIWYG-like view per [D-EDIT-2].

- Headings rendered at appropriate sizes and weights
- Bold, italic, strikethrough rendered inline (not as syntax characters)
- Links rendered as tappable text with subtle indicator
- Code spans and fenced code blocks rendered with monospace font and background
- Lists rendered with proper indentation and bullets/numbers
- Blockquotes rendered with visual left border
- Images rendered inline (from relative and absolute paths)
- Tables rendered as formatted tables
- Task lists rendered with interactive checkboxes (toggling updates the markdown)
- **Source toggle**: user can switch to raw markdown view and back. Cursor position preserved across toggles.
- **Performance**: Meets [D-PERF-2] (< 16ms keystroke-to-render) and [D-PERF-3] (120fps scroll on ProMotion)
- **i18n**: Correctly renders and edits CJK text, RTL text (Arabic, Hebrew), accented characters, and emoji. Cursor navigation respects grapheme clusters.
- **Accessibility**: Full VoiceOver navigation of document structure (headings, lists, links announced semantically). Dynamic Type scales the editor content.
- **Acceptance**: User writes markdown and sees styled output in real time. Toggling to source shows valid markdown. Round-trip editing (rich → source → rich) preserves content perfectly. Works correctly with non-Latin text.

#### F-004: Auto-Formatting Engine
Intelligent, real-time formatting per [D-EDIT-1] and [D-EDIT-3].

**List formatting**:
- Enter in a list item → continues list with correct marker and indentation
- Enter on empty list item → ends the list
- Ordered lists: auto-renumber on add/remove/reorder
- Nested lists: auto-correct indentation to 2 or 4 spaces (configurable)
- Subtle haptic feedback (light tap) on list auto-continuation

**Table formatting**:
- Auto-align table columns as user types (pad cells with spaces)
- Tab key moves between cells
- Enter in last cell of last row → adds new row
- Auto-add missing header separator row

**Heading formatting**:
- Auto-add space after `#` markers if missing
- Normalize ATX heading style (remove trailing `#`)

**Whitespace**:
- Trim trailing whitespace on Enter
- Ensure single blank line between block elements
- Ensure file ends with a newline

**All auto-formatting**:
- Operates inline, in real time, as user types
- Each operation is a discrete undo step — Cmd+Z reverses any auto-format
- Individual rules can be toggled off in settings
- **Performance**: Auto-format operations complete within the same frame as the keystroke (< 16ms)
- **Accessibility**: VoiceOver announces auto-format actions (e.g., "List continued, item 3")
- **Acceptance**: User types a markdown list, table, or heading. Editor automatically corrects formatting in real time. Each auto-format action is independently undoable. Haptic confirms list actions.

#### F-005: Document Doctor
Background analysis with inline suggestions per [D-EDIT-4].

**MVP rules**:
- **Broken links**: Flag `[text](url)` where URL is a relative path that doesn't resolve to an existing file
- **Heading hierarchy**: Flag headings that skip levels (e.g., `#` → `###` with no `##`)
- **Duplicate headings**: Warn when multiple headings have identical text (ambiguous anchors)
- **Trailing whitespace**: Flag lines with trailing whitespace (unless in a code block)
- **Missing blank lines**: Flag block elements not separated by blank lines

**Presentation**:
- Subtle underline or margin indicator on affected lines (uses both shape and color — not color alone per [D-A11Y-1])
- Tap/click indicator → compact popover with issue description, "Fix" button, "Dismiss" button
- Dismissals are per-file, per-session (not persisted — no sidecar files per DP-1/DP-6)
- Non-blocking — doctor never prevents the user from writing or saving
- Light haptic feedback when fix is applied
- **Performance**: All rules evaluate within 1 second of file open; re-evaluate within 500ms after editing pauses
- **Accessibility**: VoiceOver can navigate to doctor indicators. Each announces the issue (e.g., "Warning: heading skips level 2")
- **Acceptance**: User opens a markdown file with structural issues. Doctor indicators appear within 1 second. User taps an indicator, sees the suggestion, and can accept or dismiss.

#### F-006: Syntax Highlighting
Fenced code blocks rendered with syntax highlighting.

- Language detection from info string (` ```python `)
- Minimum supported languages: Python, JavaScript/TypeScript, Swift, Go, Rust, HTML/CSS, JSON, YAML, SQL, Bash/Shell, Ruby, Java, Kotlin, C/C++, PHP
- Monospace font, background color differentiation
- Code block is editable inline (no separate mode)
- Colors adapt to dark/light theme
- **Acceptance**: User writes a fenced code block with a language tag. Code is syntax-highlighted correctly in both light and dark modes.

#### F-007: Dark and Light Mode
Full dark and light theme with system preference detection.

- Defaults to system preference
- User can override to always-light or always-dark
- All UI elements, editor chrome, and rendered markdown adapt
- Syntax highlighting colors adapt
- All themes meet WCAG AA contrast ratios per [D-A11Y-1]
- Theme transitions are animated (crossfade, 200ms) with Reduced Motion alternative (instant switch)
- **Acceptance**: User toggles iOS dark mode. App switches immediately. All text, backgrounds, and UI elements are legible and intentionally designed in both modes. Contrast ratios verified.

#### F-008: Auto-Save
Continuous, automatic saving per [D-EDIT-5].

- Save triggers: 1 second after last keystroke (debounced), on app background, on file close
- Uses file coordination APIs to avoid conflicts
- No save button, no save indicator, no save confirmation
- If save fails (disk full, permissions revoked): non-modal error with retry
- Subtle haptic pulse on background save (when app is foregrounded — confirms "your work is safe")
- **Acceptance**: User edits a file, switches to another app, switches back — all changes preserved. Force-quit — content saved up to last debounce preserved.

#### F-009: Keyboard Support
Full external keyboard support for iPad.

- Text editing: Cmd+B (bold), Cmd+I (italic), Cmd+K (link), Cmd+Shift+K (code)
- Navigation: Cmd+Up/Down (top/bottom), Option+arrows (word), Cmd+arrows (line)
- App: Cmd+O (open), Cmd+N (new), Cmd+W (close), Cmd+Shift+P (source toggle)
- AI: Cmd+J (AI assist on selection — see F-025)
- Discoverability: Cmd-hold shows shortcut overlay
- **Acceptance**: User with external keyboard performs all common editing, navigation, and AI tasks without touching the screen.

#### F-010: Typography and Layout
Intentional, beautiful typography per DP-2.

- Custom typeface(s) for editor and UI chrome — not system fonts
- Line height, paragraph spacing, and margins optimized for readability on each device class
- Responsive layout: content area adapts to screen size, never cramped or too wide
- Maximum content width on large screens (iPad landscape, external display) for comfortable reading line length (~70–80 characters)
- Respects Dynamic Type: custom fonts scale with system text size preference per [D-A11Y-2]
- **Acceptance**: A designer reviews rendered markdown on iPhone SE, iPhone 15 Pro Max, iPad Mini, and iPad Pro at default and large Dynamic Type sizes. All feel intentionally designed.

#### F-033: Word Count and Document Stats
Always-visible writing statistics in the status bar.

- Word count, character count (with and without spaces), estimated reading time
- Displayed in a compact status bar at the bottom of the editor — always visible, never intrusive
- Updates in real time as user types
- Tapping the status bar expands to show additional stats: paragraph count, sentence count, Flesch-Kincaid readability score (basic — extended analysis moves to F-017)
- Selection-aware: when text is selected, stats show selection count alongside total count
- **Accessibility**: VoiceOver can read current word count and reading time via status bar
- **Acceptance**: User is writing and can see "342 words · 2 min read" in the status bar at all times. Selecting a paragraph updates to "342 words (87 selected) · 2 min read."

#### F-034: Spell Check
System spell checking integrated into the editor.

- Uses UITextChecker (iOS) / NSSpellChecker (macOS) per [D-EDIT-7]
- Red underline on misspelled words (standard system behavior)
- Tap/right-click for correction suggestions
- Respects user's system language and custom dictionary
- Spell check indicators coexist with document doctor indicators without visual conflict
- Works in both rich text and source view
- On by default, can be toggled off in settings
- **Acceptance**: User types "recieve" — red underline appears. User taps → "receive" is the first suggestion. User accepts → word is corrected.

#### F-035: The Render (Signature Transition)
Animated source-to-rich transition per DP-9.

- When opening a file or toggling from source to rich view, markdown syntax characters animate into their rendered form:
  - `#` markers shrink and fade as headings scale to their rendered size and weight
  - `**`/`*` markers dissolve as text boldfaces/italicizes
  - `-`/`*`/`1.` list markers morph into styled bullets/numbers with proper indentation
  - `` ``` `` fences fade as code blocks materialize with background color
  - `[text](url)` compacts as links render with their styled appearance
  - `> ` blockquote markers transform into the visual left border
- Total duration: ~400ms, spring-animated
- Reverse animation plays when toggling from rich to source view
- Reduced Motion alternative: instant crossfade (200ms opacity transition)
- **Performance**: 120fps on ProMotion devices throughout the animation. No dropped frames. Uses Core Animation, not SwiftUI animation modifiers, for guaranteed performance.
- **Accessibility**: VoiceOver is not affected by the animation — it announces the rendered content immediately
- **Acceptance**: A non-technical observer watching over the user's shoulder can see the transition and finds it visually striking. The animation is smooth, purposeful, and delightful — never janky or distracting. A user toggles source/rich multiple times just to watch it.

#### F-036: iPad Optimization
Purpose-built iPad experience that goes beyond "big iPhone."

- **Stage Manager**: Full support for resizable windows and multi-window. User can have two easy-markdown documents side by side, or easy-markdown alongside Safari/Notes for reference.
- **External display**: When connected to an external display, the editor can span the full display with appropriate content width constraints. No letterboxing, no awkward scaling.
- **Split View / Slide Over**: Works correctly in 1/3, 1/2, and 2/3 split. Content reflows gracefully at every width. Slide Over is ideal for quick edits while in another app.
- **Pointer/trackpad**: Full trackpad and mouse support with hover states on interactive elements (doctor indicators, AI action bar, toolbar buttons). Right-click context menus.
- **Keyboard**: All F-009 shortcuts work, plus iPad-specific: Cmd+Option+arrows for split view management.
- **Pencil** (P2 — future, if validated): Apple Pencil for handwriting-to-markdown conversion or annotation. Not in MVP but the architecture should not preclude it.
- **Acceptance**: An iPad Pro user with Magic Keyboard and external display uses easy-markdown as their primary writing environment for a full day. It feels native to the iPad, not like an iPhone app running on a larger screen.

#### F-025: AI Assist (MVP — Local)
On-device AI writing assistance per [D-AI-1] through [D-AI-6]. Included with app purchase.

**MVP capabilities** (per [D-AI-6] — ship what works excellently first):

**Content-Aware AI** — AI understands the context of what's selected. Prose gets prose improvements. A Mermaid diagram block gets structural suggestions. A table gets formatting and content help. Dedicated diagram editing is in F-022b.

**Improve Writing** — Select text → "Improve" → AI suggests a rewritten version:
- Grammar and spelling correction
- Clarity improvements (simplify complex sentences, remove ambiguity)
- Conciseness (remove filler words, tighten prose)
- Shows inline diff preview: original text with AI suggestion overlaid. User taps to accept, edits to modify, or dismisses.

**Summarize** — Select text or full document → "Summarize":
- Generates a concise summary (1–3 sentences for a section, 1 paragraph for a full document)
- Summary appears in a popover. User can insert it at cursor, copy, or dismiss.

**Continue Writing** — Place cursor at end of text → "Continue":
- AI generates 1–3 sentences continuing the user's thought, matching their tone and style
- Suggestion appears as ghost text (dimmed, inline). User presses Tab to accept, keeps typing to dismiss.

**Interaction pattern**:
- **Selection-based**: Select text → floating action bar appears above selection with AI options (Improve, Summarize) alongside standard format actions (Bold, Italic, etc.)
- **Cursor-based**: AI can proactively suggest continuations after a natural pause (3 seconds). Ghost text appears. Tab to accept, keep typing to dismiss. Can be turned off in settings.
- **Keyboard**: Cmd+J invokes AI assist on current selection or at cursor position
- **Voice**: Hold microphone button (or Cmd+Shift+J) → speak an intent → AI interprets and executes. See F-037 for full voice control spec.
- All AI actions are undoable (Cmd+Z reverts to pre-AI text)
- **Pro AI badge**: If user is a Pro subscriber, a small indicator shows when a Pro-tier action is available in the action bar (e.g., Translate, Adjust Tone). These are seamlessly integrated — same interaction pattern, just powered by cloud instead of local model.

**Technical constraints (local)**:
- Model runs via Core ML / MLX on-device per [D-AI-5]
- Minimum device for local AI: iPhone 15 / M1 Mac (A16+ chip / Apple Silicon)
- Older devices: auto-formatting and document doctor work; generative AI is unavailable (not degraded — absent, with no broken affordance)
- Model size: 1–4GB quantized, downloaded on first launch or on-demand
- **Performance**: Per [D-PERF-4] — first token < 500ms, full response < 3 seconds for typical operations
- AI suggestions stream progressively (token by token for previews)

**Privacy (local)**:
- Zero network calls for local AI inference
- No prompt/response logging
- No model fine-tuning on user data
- Works fully offline

**Accessibility**: VoiceOver announces "AI suggestion available" when ghost text appears. Suggestion content is readable via VoiceOver. Accept/dismiss actions are VoiceOver-accessible.

**Acceptance**: User selects a paragraph, taps "Improve," sees an inline diff of the AI suggestion within 3 seconds, and accepts it with one tap. Works in airplane mode. Works on iPhone 15. Does not appear on iPhone 14.

### P1 — Ship in v1.0 (high value, not launch-blocking)

#### F-011: Quick Open
Fuzzy file finder for fast file access.

- Cmd+P (or swipe gesture on iOS) to invoke
- Searches recent files and bookmarked directories
- Fuzzy matching on filename and path
- Results ranked by recency and match quality
- **Performance**: Results appear within 200ms of typing 3 characters
- **Acceptance**: User presses Cmd+P, types 3 characters, correct file in top 3 results within 200ms.

#### F-012: Find and Replace
In-document search and replace.

- Cmd+F to invoke find bar
- Plain text and regex modes
- Match highlighting in document
- Replace one / replace all
- Case-sensitive toggle
- **Acceptance**: User searches for a regex pattern in a 500-line document. All matches highlighted. Replace-all correctly substitutes all occurrences.

#### F-013: Render, Print, and Share
Share markdown with the world — rendered beautifully, printed cleanly, or shared as the `.md` file itself.

- **Share as markdown**: Share the `.md` file via iOS share sheet to any app, AirDrop, email, Messages, etc.
- **Save to new location**: Save/copy the `.md` file to a different directory, cloud drive, or external storage
- **Print**: Print the rendered rich text view directly (matches in-editor appearance with custom typography)
- **Rendered PDF**: Export a beautifully rendered PDF of the document (same quality as print, for sharing with non-markdown users)
- **No proprietary formats**: No Word, Pages, RTF, or Google Docs export. PDF is a rendered view, not a format conversion.
- **Rich content in export**: Rendered PDF and print output include diagrams as vector graphics, tables as formatted tables, and code blocks with syntax highlighting
- **Acceptance**: User shares a `.md` file via AirDrop to a colleague. User prints a document and the output matches the in-editor rich text appearance. User exports a PDF that looks polished, not like a browser print. PDF includes all rendered rich content (tables, diagrams, code blocks).

#### F-014: Custom Themes and Fonts
User-selectable visual themes and typeface options.

- 3–5 built-in color themes (light and dark variants each)
- Font selection from a curated list (we control quality — not system font picker)
- Font size adjustment
- Theme preview: see the effect before committing
- Settings persist per-device via UserDefaults (no sidecar files per DP-1/DP-6)
- All themes meet WCAG AA contrast ratios
- **Acceptance**: User selects a different theme and font. Entire editor updates immediately. Persists across launches. All themes pass contrast check.

#### F-015: Image Handling
Drag-and-drop and paste support for images.

- Drop/paste image → prompt for save location → insert relative path markdown
- Images rendered inline in rich text mode
- Broken image paths shown with placeholder + doctor warning (F-005)
- **Acceptance**: User drags image into editor. Saved to chosen location. Relative markdown link inserted. Renders inline.

#### F-016: macOS App
Native macOS application per [D-PLAT-2].

- Native macOS window management (tabs, split view, full screen)
- Menu bar with complete keyboard shortcut coverage
- Drag-and-drop file opening
- Services menu integration
- Finder Quick Look preview for `.md` files
- Touch Bar support (if applicable)
- **Acceptance**: macOS app passes Apple HIG review. A Mac-native user would not guess it was ported from iOS.

#### F-017: Extended Document Doctor
Deeper writing analysis.

- Readability scoring (Flesch-Kincaid or similar) in status bar
- Word count, character count, estimated reading time (always visible in status bar)
- Writing goals: set target word count, progress shown visually
- Prose suggestions (opt-in): flag very long sentences, passive voice, repeated words
- **Acceptance**: User enables prose suggestions. Doctor flags a 60-word sentence with suggestion. User can accept or dismiss.

#### F-026: AI — Tone and Style Adjustment *(Pro AI)*
Select text → adjust tone (more formal, more casual, more technical, simpler).

- **Requires Pro AI subscription** — cloud-powered for quality tone shifts that exceed local model capability
- 4 preset tone adjustments + "custom instruction" option
- Same inline diff preview as F-025 Improve Writing
- Appears in the same floating action bar as local AI actions, marked with subtle Pro badge
- If user is not subscribed: action is visible but tapping shows a brief, non-intrusive explanation of Pro AI with subscribe option. Never blocks the workflow.
- **Privacy**: Only the selected text is sent to the cloud API per [D-AI-8]
- **Acceptance**: Pro subscriber selects a casual paragraph, taps "More Formal," sees a rewritten version within 3 seconds. Accepts with one tap. Non-subscriber sees a tasteful upgrade prompt.

#### F-027: AI — Translation *(Pro AI)*
Select text → translate to another language.

- **Requires Pro AI subscription** — cloud-powered for translation quality across 20+ languages
- Supports top 20 languages (EN, ES, FR, DE, ZH, JA, KO, PT, IT, RU, AR, HI, NL, SV, PL, DA, NO, FI, TR, TH)
- Translation appears as inline replacement preview
- Original text recoverable via undo
- **Privacy**: Only the selected text is sent per [D-AI-8]
- **Acceptance**: Pro subscriber selects an English paragraph, taps "Translate → Spanish." Translated text appears as preview within 3 seconds. Accepts. Undo restores English.

#### F-028: AI — Smart Completions *(Local AI)*
Context-aware autocomplete that goes beyond simple text prediction. Included with app purchase.

- Completes markdown structures: start a table header → AI suggests column layout based on content. Start a list → AI suggests next items based on pattern.
- Completes front matter patterns (if present in file — we read but don't generate per DP-6)
- Ghost text presentation, Tab to accept
- Runs on-device — works offline
- **Device floor**: Same as F-025 — requires iPhone 15 / M1 Mac (A16+ / Apple Silicon). Uses the same on-device model. Not available on older devices.
- **Acceptance**: User types `| Name | Email |` and presses Enter. AI suggests a separator row and first data row. User Tabs to accept.

#### F-037: Voice Control — Intent-Based Editing
Speak what you want your document to become. AI interprets and executes.

This is not dictation (speech-to-text for content insertion). This is **speech-to-intent for editing operations** — a fundamentally different interaction model. The user describes a change in natural language, and AI makes it happen.

- **Activation**: Hold microphone button in toolbar, or Cmd+Shift+J (keyboard shortcut). Visual indicator shows "listening" state.
- **Intent interpretation**: User speaks a command. AI interprets the intent and maps it to an editing operation:
  - *"Make this more concise"* → AI rewrites selected text (or current paragraph) for brevity
  - *"Add a conclusion to this document"* → AI generates a conclusion section at the end
  - *"Rewrite this for a technical audience"* → tone adjustment on selection
  - *"Move the second section before the first"* → structural reorder
  - *"Summarize the last three paragraphs"* → summary generated
  - *"Add a diagram showing the API flow"* → Mermaid diagram generated at cursor
  - *"What's missing from this document?"* → AI analysis surfaced as doctor-style suggestions
- **Preview before apply**: All voice-initiated changes show the same inline diff preview as touch/keyboard AI actions. User accepts, edits, or dismisses. Voice never modifies the document without confirmation.
- **Speech recognition**: Uses iOS Speech framework (on-device recognition, no network required for basic recognition on iOS 17+). Supports system language. Transcription shown in real-time as user speaks.
- **Context-aware**: Voice commands operate on the current selection (if text is selected) or the current cursor position / visible section. "Make this shorter" means different things depending on what's selected.
- **Chained commands**: User can speak multiple intents in sequence. Each produces a preview. User accepts/dismisses each.
- **Accessibility**: Voice control is itself an accessibility feature — enables hands-free document editing. Works alongside VoiceOver (distinct from VoiceOver commands — these are AI editing intents, not navigation).
- **Performance**: Speech recognition begins within 200ms of activation. Intent interpretation and first AI response within 1 second of speech completion.
- **Acceptance**: User holds the mic button, says "make this paragraph shorter and more direct," releases. AI shows an inline diff of the rewritten paragraph within 3 seconds. User taps to accept. The entire interaction takes less time than selecting text, tapping Improve, and waiting.

#### F-022a: Mermaid Diagram Rendering
Render Mermaid diagram blocks as visual diagrams inline in the editor.

- Fenced code blocks with `mermaid` language tag render as visual diagrams in rich view
- Supported diagram types: flowcharts, sequence diagrams, ER diagrams, class diagrams, Gantt charts, pie charts, state diagrams, mind maps
- Diagrams render inline, replacing the code block with the visual output
- Source view shows the raw Mermaid code (toggle preserves cursor position near the block)
- Diagrams adapt to light/dark theme
- Diagrams included in PDF export and print output (F-013) as vector graphics
- The Render animation (F-035) applies: Mermaid code block animates into the rendered diagram
- Malformed Mermaid shows the raw code with a doctor warning (F-005)
- **Performance**: Diagram renders within 500ms of file open or edit pause
- **Accessibility**: VoiceOver reads the diagram type and any text labels within it
- **Acceptance**: User opens a file with a Mermaid flowchart. It renders as a visual diagram inline. Toggling to source shows the Mermaid code. Exporting to PDF includes the rendered diagram.

#### F-022b: AI-Assisted Mermaid Diagram Editing
Select a Mermaid block → describe a change in natural language → AI rewrites the Mermaid code → diagram re-renders.

- When user selects (or taps) a rendered Mermaid diagram, a contextual action bar appears with "Edit with AI"
- User describes the change: "add a database node," "make the flow go left to right," "add an error path from step 3"
- AI rewrites the Mermaid code block, diagram re-renders with the change
- Shows inline diff of the Mermaid code (before/after) with rendered preview of the new diagram
- User accepts (diagram updates), edits the code manually, or dismisses
- Uses same AI infrastructure as F-025 (local AI for simple edits, Pro AI for complex diagram changes)
- **Acceptance**: User taps a rendered flowchart, types "add a retry loop from the error handler back to step 2," AI updates the Mermaid code, new diagram renders with the change. User accepts.

### P2 — Phase 3 / Future (validated demand required)

| ID | Feature | Ships when |
|----|---------|-----------|
| F-018 | Android app (Kotlin, native UI, shared logic via KMP or Rust) | Demand validated via waitlist |
| F-019 | Windows/Linux app | Demand validated; tech approach TBD |
| F-020 | Folder browsing sidebar (opt-in, not required) | User feedback requests it |
| F-021 | Snippet/template system | User feedback requests it |
| F-022c | Extended syntax rendering: KaTeX/math blocks, footnotes (render-only per [D-MD-2]) | User feedback requests it |
| F-023 | Shortcuts/Siri integration (Apple) | iOS/macOS stable |
| F-024 | Quick capture widget (iOS home screen) | iOS stable |
| F-029 | AI — Generate from prompt *(Pro AI)* ("write a README for…", "create a table comparing…") | MVP AI validated, cloud infrastructure stable |
| F-030 | AI — Document-level analysis *(Pro AI)* ("what's missing from this doc?", "suggest an outline") | MVP AI validated, cloud infrastructure stable |
| F-031 | AI — OCR + image-to-markdown *(Local or Pro)* (paste screenshot → AI extracts text/tables as markdown) | Hardware/model capability sufficient |
| F-032 | UI localization (translate app interface to top 10 languages) | User base warrants it |

---

## 8. User Journeys

These journeys define the critical paths through the product. Every journey must feel seamless — any friction point is a bug.

### Journey 1: First Launch → First Edit (< 30 seconds)

```
Download → Launch → "Open File" or "New File" → Editing
```

- No onboarding, no tutorial, no account creation, no permissions prompts beyond file access
- App opens to a clean state: two clear actions (Open File, New File) and nothing else
- Tapping "Open File" immediately shows system file picker
- Tapping "New File" immediately shows system save dialog
- File opens in rich text editor, cursor active, ready to type
- **First-time delight moment**: User types their first list item, presses Enter, and the editor auto-continues the list with correct formatting + subtle haptic. This is the "oh, this is different" moment.
- **Decision [D-UX-1]**: No onboarding flow. The app is self-evident. If it needs a tutorial, the UI has failed.

### Journey 2: Daily Writing Session

```
Launch → Last file auto-opens → Write (AI assists inline) → Auto-saved → Background app
```

- App restores last-open file and cursor position
- If no last file, show recents list
- User writes. Auto-formatting helps. AI ghost text occasionally suggests continuations.
- Document doctor indicators appear non-intrusively
- User switches apps. File is already saved. No prompt.
- **Decision [D-UX-2]**: Last-open file restoration is default behavior. App always returns the user to where they left off.

### Journey 3: AI-Assisted Editing

```
Select text → Floating bar appears → Tap "Improve" → See diff preview → Accept → Continue writing
```

- User selects a rough paragraph
- Floating action bar appears above selection: Bold | Italic | Link | **Improve** | **Summarize** | More...
- User taps "Improve"
- Within 500ms, first tokens of the improved version start appearing as an inline diff
- Within 3 seconds, full suggestion is shown: deleted text in red strikethrough, new text in green
- User taps "Accept" → text is replaced, haptic confirms. Or taps away to dismiss.
- Entire operation: select, tap, wait <3s, tap. Five seconds total for a better paragraph.

### Journey 4: Fixing a Document's Issues

```
Open file → See doctor indicators → Tap indicator → Read suggestion → Accept or dismiss → Continue
```

- File opens, doctor indicators appear within 1 second
- User taps indicator → compact popover with issue + "Fix" / "Dismiss"
- "Fix" applies correction inline, haptic confirms
- "Dismiss" hides indicator for this session
- Doctor re-analyzes in background after changes settle

### Journey 5: The Render — Switching Between Rich and Source View

```
Rich view → Tap toggle → Markdown animates into raw source → Edit → Tap back → Source transforms into rich view (The Render)
```

- Toggle always visible (toolbar button or gesture)
- **The Render (F-035)**: When toggling back to rich view, markdown syntax characters animate into their rendered form — headings scale up, bold markers dissolve, list markers morph into bullets, code fences materialize with backgrounds. ~400ms, spring-animated, 120fps. This is the signature moment of the app.
- Reverse plays when toggling to source (rich elements decompose back into syntax characters)
- Cursor position maps between views (same line, best effort)
- Changes in source reflected in rich view immediately
- Auto-formatting rules apply in both views
- Reduced Motion alternative: instant crossfade (per DP-9)

### Journey 6: Discovering Pro AI (Natural Upgrade)

```
Using local AI → Sees "Translate" in action bar with Pro badge → Taps → Brief explanation → Subscribes → Translates instantly
```

- User has been using local AI (Improve, Summarize, Continue) for days or weeks. They're happy.
- One day they select text and notice "Translate" and "Adjust Tone" in the floating bar, marked with a small Pro badge
- User taps "Translate" → a compact, friendly sheet explains: *"Pro AI uses cloud models for translation, tone adjustment, and more. $3.99/month. Cancel anytime. Your app and local AI always work without it."*
- User subscribes via App Store (standard iOS subscription flow — no account creation)
- Translation happens. Text appears as inline preview. User accepts.
- **Key principles**: The user discovered Pro naturally, in context, while trying to do something. No nag screens, no banners, no "you're missing out" messaging. The free experience was already great. Pro is a genuine "oh, I want that too" moment.

### Journey 7: The "Show Someone" Moment (Viral Loop)

```
User is writing → Colleague/friend sees the app → "What is that?" → User shows auto-format + AI → "Where do I get it?"
```

- This is our primary growth mechanism. The product must be visually striking enough — and the intelligent features surprising enough — that people ask about it unprompted.
- **Decision [D-GROWTH-1]**: We design for "over the shoulder" impact. The editor should look noticeably beautiful from 3 feet away. AI interactions should produce visible "wow" moments.

### Journey 8: Voice-Driven Editing

```
Reading a document → Hold mic → "Make this section shorter" → AI shows diff → Accept → "Add a diagram of the architecture" → AI generates Mermaid → Accept → Done
```

- User is reading through an AI-generated report on their iPhone
- They spot a wordy section. Instead of selecting text and navigating menus, they hold the mic button and say "make this section more concise"
- AI interprets the intent, identifies the current section, and shows an inline diff with a tighter version
- User taps Accept. Says "now add a conclusion summarizing the key findings"
- AI generates a conclusion paragraph, shows it as ghost text at the end. User accepts.
- The entire refinement session happens hands-free — perfect for iPad with keyboard, iPhone on a desk, or accessibility needs.
- **This is the "show someone" moment for voice**: a user talking to their document and watching it transform in real time.

### Journey 9: Receive from AI → Refine → Share

```
AI agent produces report.md → User opens in easy-markdown → Everything renders beautifully → Refine with AI → Export polished PDF → Share
```

- User receives a `.md` file from an AI agent (research report with tables and diagrams, analysis with code examples)
- Opens in easy-markdown (system file picker or "Open With" association)
- Rich view renders everything beautifully: headings, tables, diagrams, code blocks — the document looks professional immediately
- User reads through, selects a section that needs tightening → "Improve" → accepts
- User taps a diagram → "Edit with AI" → describes a change in natural language → diagram updates
- User exports as PDF → polished document with all rich content rendered → shares via email or AirDrop
- **Total time from AI output to polished shared document: 5–10 minutes**
- This journey is the primary value proposition for our primary persona — and the thing no other tool does well.

---

## 9. Roadmap with Exit Criteria

Each phase has explicit exit criteria — conditions that must be true before we move to the next phase.

### Phase 1: MVP — iOS

**Goal**: Ship the AI-native document tool on iOS. Validate that Apple-quality craft + open files + AI co-authoring + beautiful rendering is a product people love and recommend.

**Scope**: Features F-001 through F-010, F-022a (Mermaid Diagram Rendering), F-025 (Local AI Assist), F-033 (Word Count), F-034 (Spell Check), F-035 (The Render), F-036 (iPad Optimization).

**Performance contract**: All targets in [D-PERF-1] through [D-PERF-5] must be met before launch.

**Accessibility contract**: All features pass VoiceOver, Dynamic Type, and Reduced Motion checks per [D-A11Y-1] through [D-A11Y-3].

**Exit criteria to move to Phase 2**:
- App Store rating ≥ 4.7 (based on first 200+ ratings — "best in the world" means best-in-class ratings)
- D7 retention ≥ 60%
- Positive review mentions of editor experience, auto-formatting, AI, or UI quality in ≥ 30% of text reviews
- AI features used by ≥ 50% of users in first week (validates AI is discoverable and useful, not just present)
- < 5% of support contacts about file access confusion
- No P0 bugs open for > 48 hours
- App featured in "New Apps We Love" or equivalent App Store editorial (stretch goal, not blocking)

### Phase 2: v1.0 — Polish + macOS + Pro AI Launch

**Goal**: Expand to macOS. Launch Pro AI cloud tier. Deepen AI capabilities. Begin building toward "defacto" status.

**Scope**: F-011 through F-017, F-022b (AI-Assisted Mermaid Editing), F-026 through F-028, F-037 (Voice Control), plus Pro AI infrastructure (cloud API integration, App Store subscription management, privacy pipeline per [D-AI-8]), plus MVP refinements.

**Exit criteria to move to Phase 3**:
- macOS app rated ≥ 4.7 stars
- Combined iOS + macOS active users growing month-over-month
- AI features cited positively in ≥ 20% of reviews (not just "has AI" — "the AI is good")
- Organic referral measurable (users discovering via word-of-mouth, not just search)
- Demand signal for Android justifies investment (waitlist, reviews, support requests)

### Phase 3: Expansion + Defacto

**Goal**: Broaden platform reach. Deepen AI intelligence. Establish easy-markdown as the default document tool for the AI age.

**Scope**: F-018 through F-021, F-022c (KaTeX/Footnotes), F-023 through F-032, selected based on demand signals.

**Entry criteria (each feature independently)**:
- Quantified demand signal
- Technical approach documented and reviewed
- Does not compromise existing platform quality

---

## 10. Competitive Landscape

| App | Price | Platforms | File Access | UI Quality | AI | Our advantage |
|-----|-------|-----------|-------------|------------|-----|---------------|
| **Obsidian** | Free (sync $8/mo) | All | Vault-only | Good | No (plugins possible) | No vault. Native. Built-in AI. Simpler. |
| **Typora** | $15 | Desktop | Open files | Clean | No | Mobile. Local AI. Smart editing. |
| **iA Writer** | $50 | Apple + Android | Library-based | Excellent | No | 1/5th the price. True open access. AI. Auto-formatting. |
| **Bear** | $30/yr | Apple | Proprietary | Excellent | No | Standard files. No subscription. AI. |
| **1Writer** | $6 | iOS only | File provider | Decent | No | Cross-platform. Modern UI. AI. Intelligence. |
| **Ulysses** | $50/yr | Apple | Library-based | Excellent | Basic | No subscription. Open files. Better AI (local). |
| **Notion** | Free/$8+/mo | All | Proprietary | Good | Cloud AI | Open files. No subscription. Local/private AI. |
| **Cursor/VS Code** | Free/$20/mo | Desktop | Open files | Dev-focused | Cloud AI | Purpose-built for prose. Mobile. Native. Private AI. Complementary, not competitive. |
| **TextEdit/Notes/Preview** | Free | Apple | Open files | Minimal | No | Purpose-built for markdown. Renders beautifully. AI co-authoring. Polished PDF export. |
| **Word/Google Docs** | Free–$10/mo | All | Proprietary | Good | Cloud AI | Markdown is lighter, faster, AI-native. No subscription. No lock-in. For 99% of documents, we're enough — and better. |

**Strategic position**: Cursor showed what AI-native editing could be for code. We are what it should be for everything else — with the craft and polish of the best Apple-native apps. For 99% of the documents people create in 2026, markdown + AI + beautiful rendering is all you need. We're not just competing with markdown editors — we're the reason people stop reaching for Word and Google Docs for briefs, reports, READMEs, and everything that isn't a spreadsheet.

**Competitive moat**: Four reinforcing advantages that are hard to replicate:
1. **AI-native from the ground up** — AI co-authoring, inline refinement, diagram editing, smart completions. Not a bolt-on, not a sidebar — AI is woven into every interaction. The only document tool with high-quality AI that works offline.
2. **Apple-quality native craft** — Electron/web-based competitors (Obsidian, Notable, Notion, Google Docs) cannot match native animation performance, 120fps scroll, and platform integration. This is what happens when you build for the platform, not around it.
3. **Open files + no accounts** — competitors with proprietary storage (Bear, Obsidian, Notion, Google Docs, Word) would have to fundamentally redesign their architecture to match. Your files are yours.
4. **Purpose-built for how markdown is used in 2026** — not a 2015 text editor with AI bolted on. Built for the full workflow: create with AI, receive from AI, refine, render rich content beautifully, share as polished output.

**Relationship to Cursor / VS Code**: We are not competing with IDEs. We are the **complement** — Cursor for code, easy-markdown for everything else. This is a referral channel, not a battleground. "I use Cursor for code and easy-markdown for everything else" is the target positioning.

---

## 11. Business Model

### Revenue streams

| Stream | Type | Price | What the user gets | ID |
|--------|------|-------|--------------------|----|
| **App purchase** | One-time | $9.99 | Full editor, auto-formatting, document doctor, local on-device AI (improve, summarize, continue, smart completions). Works offline. No account. | [D-BIZ-1], [D-BIZ-2] |
| **Pro AI** | Subscription (optional) | $3.99/mo or $29.99/yr | Cloud-powered AI: advanced translation, tone/style adjustment, generation from prompts, document-level analysis, longer context window. | [D-AI-2], [D-BIZ-2], [D-BIZ-7] |
| **Major upgrades** | One-time (periodic) | ~$7.99 | v2, v3 major version upgrades. Existing version continues working indefinitely. | [D-BIZ-3] |

### What we don't charge for

| Element | Decision | ID |
|---------|----------|----|
| **Ads** | None. Never. | [D-NO-7] |
| **The editor itself as a subscription** | Never. The app is a one-time purchase. | [D-BIZ-1] |
| **Local AI features** | Included in app purchase. No token limits, no usage caps. | [D-AI-2] |
| **Updates within a major version** | Free. | [D-BIZ-3] |

### What we don't collect

| Element | Decision | ID |
|---------|----------|----|
| **Analytics/telemetry** | None. | [D-BIZ-4] |
| **Pro AI prompts/responses for training** | Never retained beyond request processing per [D-AI-8]. | [D-AI-8] |
| **Account data** | No proprietary accounts. App Store handles subscription auth. | [D-NO-9] |

### The subscription messaging

This is critical to get right. The subscription is for **cloud compute**, not for the app. The framing:

> *"easy-markdown is a one-time purchase. Local AI is included — improve your writing, get summaries, and continue your thoughts, all on-device and offline. **Pro AI** adds cloud-powered capabilities for $3.99/month: advanced translation, tone adjustment, and document analysis using state-of-the-art models. Cancel anytime — your app and local AI keep working perfectly."*

**Decision [D-BIZ-5]**: Pro AI is positioned as a power-user enhancement, not a gate. The free (included) experience must be so good that most users never feel they need Pro. Pro should feel like "I want even more" not "I need to pay to unlock what's missing." No dark patterns: no persistent upgrade banners, no feature-shaped holes, no "upgrade to unlock" on basic actions. Pro features are simply additional options that appear in the AI menu for subscribers.

### Unit economics

**App revenue**: At $9.99, Apple takes 30% year one → net ~$7/sale. Target 1,500 sales/month by month 6. Annual: 18,000 sales × $7 = ~$126K net.

**Pro AI revenue**: Assume 15% of active users subscribe (conservative for a quality AI tier). At steady-state ~10K active users, that's ~1,500 Pro subscribers. Blended revenue assuming 60% annual / 40% monthly: ~$4,500/month net (after Apple cut). Pro AI API costs estimated at $0.50–1.00/subscriber/month → $750–1,500/month cost → healthy margin. Annual plans (~$21 net each) dramatically improve LTV vs. monthly (~$2.80 net/month).

**Combined year-one target**: ~$126K (app) + ~$30K (Pro AI, ramping) = ~$156K gross. Sustainable for a small team.

**Long-term**: As user base grows, Pro AI becomes the larger revenue stream (recurring). App sales provide the base. Major version upgrades ($7.99 every 18–24 months) provide periodic boosts. This is a sustainable business without venture funding.

---

## 12. Growth Strategy

We are not relying solely on word-of-mouth. "Defacto" requires intentional growth.

**Decision [D-GROWTH-1]**: Our primary growth channel is organic virality driven by product quality. But we will actively support and amplify it.

### Organic virality (primary)

- **"Show someone" moment**: The app must be visually striking enough that people show it to others. Auto-formatting and AI "improve" are the demos that sell the product.
- **Screenshot-worthy**: Rendered markdown should look so good that users share screenshots of their writing in the app. The app is its own marketing.
- **App Store optimization**: Title, screenshots, and description optimized for "markdown editor" search. Screenshots showcase the UI difference.

### Developer community (secondary)

- **Open-source the markdown parser/formatter** as a standalone Swift package. Developers discover easy-markdown through the library. This builds credibility and community without building a plugin system.
- **Write about our technical decisions** (blog posts about SwiftUI performance, local AI, markdown parsing). Developer-writers are our secondary persona and our loudest amplifiers.
- **GitHub presence**: README files opened in easy-markdown, shown in screenshots. Normalize "I write my READMEs in easy-markdown."

### Content and press (tertiary)

- **Launch on Product Hunt, Hacker News** — target the developer-writer audience first
- **Reach out to indie app reviewers** and Apple-ecosystem bloggers (MacStories, The Sweet Setup, etc.)
- **Apple editorial**: Target "New Apps We Love" and "Apps We Love Right Now" features. Apple promotes native, well-designed apps — we check every box.
- **SEO/content**: Own the "best markdown editor" search query. Blog posts, comparison pages, and landing page content targeting "markdown editor for Mac," "markdown editor for iPhone," "best writing app," etc.

### Referral mechanics

- **Share sheet**: When exporting PDF/HTML, include a subtle "Made with easy-markdown" watermark (user can disable in settings). Tasteful, not tacky.
- **App Store review prompt**: After 7 days of active use AND 10+ AI uses (not before), prompt for review. Only once. Never again.
- **"The Render" is a built-in demo**: Users will toggle source/rich view to show others. The animation is marketing.

### Scaling to defacto (Phase 2–3)

These are the growth levers that take us from "great indie app" to "the default":

- **Education**: Partner with coding bootcamps and university CS programs. Students who learn to write markdown with easy-markdown become lifetime users. Offer education pricing ($4.99 one-time) via Apple's educational volume purchasing.
- **Enterprise/team licensing**: Companies buy writing tools for technical writers, developer relations teams, and documentation teams. Apple Business Manager volume purchasing support. No "enterprise features" (violates DP-5) — just volume licensing.
- **Integration story**: Become the default markdown previewer on iOS/macOS. Register for `.md` file associations. Build the Quick Look extension (F-016) so that even non-users see easy-markdown's rendering in Finder/Files. Every Quick Look preview is a billboard.
- **"Cursor for prose" narrative**: Co-market with the IDE ecosystem. Blog posts like "I use Cursor for code and easy-markdown for everything else." Position in developer tool roundups alongside IDE recommendations.

---

## 13. Success Metrics

| Metric | MVP target | v1.0 target | "Defacto" target | Why it matters |
|--------|-----------|-------------|-------------------|---------------|
| **App Store rating** | ≥ 4.7 | ≥ 4.8 | ≥ 4.8 sustained | Best-in-class quality signal |
| **D7 retention** | ≥ 60% | ≥ 70% | ≥ 75% | People are replacing their current editor |
| **AI feature adoption** | ≥ 50% use in week 1 | ≥ 60% weekly active | ≥ 70% | AI is landing as a differentiator. Measured via on-device counters (D-BIZ-6) informing App Store review prompt eligibility and via qualitative signals (reviews, support, TestFlight feedback). |
| **UI/AI mentions in reviews** | ≥ 30% | ≥ 40% | ≥ 50% | Positioning is landing |
| **File access confusion (support)** | < 5% | < 3% | < 2% | Open-file model works without explanation |
| **Monthly app sales** | 1,000+ | 2,000+ | 5,000+ | Viable and growing business |
| **Pro AI conversion** | N/A (not launched) | 10–15% of active users | 20%+ | Cloud AI is valuable enough to pay for |
| **Pro AI churn** | N/A | < 8%/month | < 5%/month | Pro users are getting ongoing value |
| **Organic referral rate** | Measurable | 30%+ of new installs | 50%+ | Product quality is driving growth |
| **"What app is that?" moments** | Anecdotal | Mentioned in reviews | Cultural reference | We've become the default |

---

## Appendix A: Decision Index

| ID | Summary | Section |
|----|---------|---------|
| D-MKT-1 | Cursor for prose: Apple-quality native UI + open files + AI-native editing + purpose-built for 2026 markdown workflows | §2 |
| D-MKT-2 | Cursor for code, easy-markdown for everything else — complement, not competitor | §2 |
| D-MKT-3 | Markdown is the document format for 99% of knowledge work in the AI age; full workflow (create, receive, refine, render, share) is first-class | §2 |
| D-MD-1 | CommonMark + GFM baseline | §6 |
| D-MD-2 | Mermaid P1 core (render + AI editing); KaTeX/footnotes Phase 3 | §6 |
| D-MD-3 | No custom syntax extensions | §6 |
| D-EDIT-1 | Intelligent editing built-in and on by default | §6 |
| D-EDIT-2 | Rich text editor with source toggle | §6 |
| D-EDIT-3 | Auto-formatting is inline, real-time | §6 |
| D-EDIT-4 | Doctor suggestions are non-modal inline indicators | §6 |
| D-EDIT-5 | Auto-save always on, debounced | §6 |
| D-EDIT-6 | Undo is per-session, in-memory, unlimited | §6 |
| D-EDIT-7 | System spell checker, on by default | §6 |
| D-AI-1 | Local-first AI; cloud is opt-in enhancement | §6 |
| D-AI-2 | Two-tier pricing: local included, Pro AI $3.99/mo | §6 |
| D-AI-3 | AI surfaces inline, no chat panel | §6 |
| D-AI-4 | AI never modifies without user action | §6 |
| D-AI-5 | Core ML / MLX for local, min device iPhone 15 / M1 | §6 |
| D-AI-6 | AI ships incrementally: local MVP, cloud v1.0 | §6 |
| D-AI-7 | Pro AI uses best-available cloud API (initially Anthropic/equivalent) | §6 |
| D-AI-8 | Pro AI: only selected text sent, no retention by provider | §6 |
| D-AI-9 | AI model downloaded separately, on-demand, Wi-Fi default | §6 |
| D-PLAT-1 | Ship order: iOS → macOS → Linux → Android | §6 |
| D-PLAT-2 | SwiftUI for Apple UI, Swift core logic | §6 |
| D-PLAT-3 | iOS 17+ minimum | §6 |
| D-FILE-1 | No vault/library/proprietary file store | §6 |
| D-FILE-2 | UTF-8 only | §6 |
| D-FILE-3 | Preserve line endings, default LF | §6 |
| D-FILE-4 | 1MB soft limit with warning | §6 |
| D-FILE-5 | Last-write-wins with notification on conflict | §6 |
| D-FILE-6 | Markdown extensions only (.md, .markdown, .mdown, .mkd, .mkdn, .mdx) | §6 |
| D-BIZ-1 | One-time app purchase; subscription only for cloud AI compute | §6 |
| D-BIZ-2 | App $9.99 one-time; Pro AI $3.99/mo | §6 |
| D-BIZ-3 | Paid major version upgrades | §6 |
| D-BIZ-4 | No third-party analytics; Apple metrics + on-device counters only | §6 |
| D-BIZ-6 | On-device aggregate counters for feature validation | §6 |
| D-BIZ-7 | Pro AI monthly ($3.99) and annual ($29.99) plans | §6 |
| D-PERF-1 | Cold launch < 1 second | §6 |
| D-PERF-2 | Keystroke-to-render < 16ms | §6 |
| D-PERF-3 | Scroll 120fps on ProMotion | §6 |
| D-PERF-4 | AI first token < 500ms | §6 |
| D-PERF-5 | Memory < 100MB typical session | §6 |
| D-A11Y-1 | VoiceOver is P0 for every feature | §6 |
| D-A11Y-2 | Dynamic Type support | §6 |
| D-A11Y-3 | Reduced Motion support | §6 |
| D-ERR-1 | No error state is undesigned | §4 |
| D-QA-1 | 4-gate review: design, implementation, device matrix, accessibility | §6 |
| D-QA-2 | Performance regression tests on every build | §6 |
| D-STORE-1 | Subscription terms clearly communicated per Apple guidelines | §6 |
| D-STORE-2 | AI origin clear in UX, not injected into files | §6 |
| D-STORE-3 | App fully functional at download (minus model) | §6 |
| D-UI-1 | No feature ships with unfinished UI | §4 |
| D-UX-1 | No onboarding flow | §8 |
| D-UX-2 | Last-open file restoration | §8 |
| D-UX-3 | The Render is a named, protected signature interaction | §4 |
| D-GROWTH-1 | Design for over-the-shoulder impact | §8, §12 |
| D-USER-1 | Primary persona: AI-Native Knowledge Worker | §3 |
| D-USER-2 | Secondary persona: The Builder — served with deep investment | §3 |
| D-USER-3 | Tertiary persona: Content Creator — served naturally | §3 |
| D-USER-4 | Global audience, i18n from day one | §3 |
| D-SCOPE-1 | No plugin/extension system | §2 |
| D-BIZ-5 | Pro AI positioned as enhancement, no dark patterns | §11 |
| D-NO-1 – D-NO-12 | Non-goals | §5 |
