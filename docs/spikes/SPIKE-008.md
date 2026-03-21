# SPIKE-008: Apple Platform AI — WWDC 2026 Evaluation

**Status:** Deferred
**Architecture Decisions:** [A-007], [A-029]
**Blocks:** FEAT-041 (AI Pipeline) — non-blocking; LocalModelProvider covers interim
**Date:** 2026-03-20

---

## Objective

Evaluate Apple platform AI APIs after WWDC 2026 and prototype `ApplePlatformAIProvider` if on-device writing assistance APIs are available. Assess whether platform AI replaces or supplements `LocalModelProvider` (MLX Swift).

## Finding

**WWDC 2026 has not yet occurred.** As of the evaluation date (2026-03-20), WWDC 2026 is expected in June 2026. No Apple platform AI APIs for on-device text generation or writing assistance have been announced or made available in developer documentation.

### Current State of Apple AI APIs (Pre-WWDC 2026)

Apple's existing AI-adjacent frameworks as of iOS 17 / macOS 14:

| Framework | Capability | Relevant to easy-markdown? |
|---|---|---|
| Natural Language (NLP) | Tokenization, NER, sentiment, embeddings | No — not text generation |
| Create ML / Core ML | Custom model training and inference | Partially — but SPIKE-005 already validated MLX Swift as superior for LLM inference |
| Apple Intelligence (iOS 18.1+) | System-level writing tools, summarization | Possibly — but these are system UI features, not developer APIs for custom text generation |
| Writing Tools API (iOS 18.1+) | System writing overlay on text views | No — provides Apple's own suggestions, not customizable for our AI pipeline |

**Key observation:** Apple Intelligence (introduced at WWDC 2024, shipped iOS 18.1) provides system-level writing tools, but these are invoked via the system UI and are not programmable APIs. There is no public API for developers to perform arbitrary text generation using Apple's on-device models. The Writing Tools API allows apps to integrate with the system writing overlay but does not expose the underlying model for custom prompts.

### Impact on Architecture

The current architecture is correctly designed for this outcome:

1. **`ApplePlatformAIProvider`** remains a stub returning `isAvailable = false` — this is the intended state per [A-007]
2. **`LocalModelProvider`** (MLX Swift) continues as the primary on-device inference path — validated in SPIKE-005
3. **`CloudAPIProvider`** provides the Pro AI tier — unaffected
4. **Provider selection order** (platform → local → cloud) is correct and will automatically prefer Apple platform AI when/if it becomes available

No code changes are needed. The abstraction layer is already designed to accommodate a future `ApplePlatformAIProvider` implementation with minimal friction.

## Resolution

**Defer.** Re-evaluate after WWDC 2026 (expected June 2026).

### Re-evaluation Criteria

This spike should be re-opened if any of the following are announced at WWDC 2026:

1. A public framework for on-device text generation (not just the system Writing Tools overlay)
2. An API that allows developers to use Apple's on-device LLM with custom prompts
3. Extensions to Core ML or Create ML that provide LLM inference comparable to MLX Swift performance
4. A developer-facing API for Apple Intelligence features (summarization, rewriting) with custom input/output control

If none of these are announced, close the spike as "not applicable" and continue with the MLX Swift path per [A-008].

### Actions

- [A-007] and [A-029]: No changes needed — current design already accommodates future platform AI
- `ApplePlatformAIProvider` stub: No changes — correctly returns `isAvailable = false`
- Re-open this spike after WWDC 2026 keynote and State of the Union sessions (expected June 2026)

## Artifacts

- `Sources/EMAI/ApplePlatformAIProvider.swift` — Existing stub, unchanged
- `docs/spikes/SPIKE-008.md` — This findings document
