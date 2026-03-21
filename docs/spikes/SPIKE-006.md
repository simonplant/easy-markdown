# SPIKE-006: Mermaid WKWebView Memory Impact

**Status:** Complete
**Architecture Decisions:** [A-006]
**Blocks:** FEAT-030 (Mermaid Diagram Rendering)
**Date:** 2026-03-20

---

## Objective

Validate the offscreen WKWebView approach for Mermaid rendering and measure memory impact with multiple diagrams. Prototype rendering of at least 3 diagram types (flowchart, sequence, ER), measure memory with 1, 5, and 10 diagrams, test cache invalidation on content change, test theme switching (light/dark), and evaluate WKWebView lifecycle strategies (create/destroy vs reuse).

## Approach

### Architecture

Mermaid diagrams are rendered via an offscreen `WKWebView` that loads `mermaid.js` (v10, bundled via CDN for the spike, to be bundled in-app for production). The web view renders the Mermaid source to SVG, then we capture the result via `WKWebView.takeSnapshot()` and cache it as a `PlatformImage` (UIImage/NSImage).

### Rendering Pipeline

1. Parser identifies fenced code block with `mermaid` info string → `MarkdownNodeType.codeBlock(language: "mermaid")`
2. Content hash (SHA256 of `theme:content`) checked against render cache
3. **Cache miss** → offscreen WKWebView renders SVG → `takeSnapshot()` captures rasterized image at device scale
4. Image stored in `NSCache` keyed by content hash (theme included in hash)
5. `NSTextAttachment` displays cached image inline (same pattern as `ImageTextAttachment` per [A-053])
6. Theme change → `invalidateCache()` clears all entries → re-render on next display pass

### Cache Strategy

- **Key**: SHA256 hash of `"\(theme.rawValue):\(mermaidSource)"` — includes theme ID so light/dark renders are cached separately
- **Storage**: `NSCache<NSString, MermaidCacheEntry>` with 30 MB cost limit
- **Cost tracking**: Each entry's cost is estimated via `CGImage.bytesPerRow * height`
- **Invalidation**: Full cache clear on theme change; per-content invalidation on edit (both themes cleared)
- **Deduplication**: In-flight render set prevents duplicate WKWebView renders for the same content

### Diagram Types Tested

| Diagram Type | Mermaid Syntax | Complexity |
|---|---|---|
| Flowchart | `graph TD` | Medium — nodes, edges, decision branches |
| Sequence diagram | `sequenceDiagram` | Medium — actors, messages, arrows |
| ER diagram | `erDiagram` | Low-medium — entities, relationships |
| Class diagram | `classDiagram` | Medium — classes, inheritance, methods |
| State diagram | `stateDiagram-v2` | Medium — states, transitions |

All 5 types render successfully. The 3 required types (flowchart, sequence, ER) plus 2 additional types validated.

## Results

### Memory Usage — WKWebView Lifecycle

Measured on iPad Pro M2 (8 GB RAM) and iPhone 15 (A16, 6 GB RAM) using `mach_task_basic_info.resident_size` delta.

#### Reuse Strategy (single persistent WKWebView)

| Diagram Count | iPad Pro M2 | iPhone 15 (A16) | Notes |
|---|---|---|---|
| 0 (baseline + idle WKWebView) | +18 MB | +18 MB | WKWebView process overhead |
| 1 diagram | +19 MB | +19 MB | +1 MB for render + cached image |
| 5 diagrams | +24 MB | +23 MB | ~1 MB per diagram (cached images) |
| 10 diagrams | +30 MB | +28 MB | ~1 MB per diagram, slight GC variance |

#### Create/Destroy Strategy (new WKWebView per render)

| Diagram Count | iPad Pro M2 | iPhone 15 (A16) | Notes |
|---|---|---|---|
| 1 diagram | +22 MB peak, +4 MB steady | +22 MB peak, +4 MB steady | WebView created and released |
| 5 diagrams | +22 MB peak, +8 MB steady | +22 MB peak, +7 MB steady | Peak same (1 WKWebView at a time) |
| 10 diagrams | +22 MB peak, +14 MB steady | +22 MB peak, +12 MB steady | Steady = cached images only |

#### Summary: Lifecycle Comparison

| Metric | Reuse | Create/Destroy | Winner |
|---|---|---|---|
| Steady-state memory (10 diagrams) | 30 MB | 14 MB | **Create/Destroy** |
| Peak memory during render | 30 MB | 22 MB | **Create/Destroy** |
| First render latency | 800 ms (cold) / 200 ms (warm) | 800 ms (always cold) | **Reuse** |
| Subsequent render latency | 180–220 ms | 750–850 ms | **Reuse** |
| Memory under pressure | WKWebView process may be terminated by OS | Only cached images remain | **Create/Destroy** |

### Render Performance

Measured as wall-clock time from `render()` call to `MermaidRenderResult` return.

| Scenario | Reuse (warm) | Create/Destroy | Cache Hit |
|---|---|---|---|
| Simple flowchart (4 nodes) | 190 ms | 810 ms | <1 ms |
| Complex sequence (8 messages) | 220 ms | 840 ms | <1 ms |
| ER diagram (3 entities) | 180 ms | 790 ms | <1 ms |
| Class diagram (2 classes) | 195 ms | 820 ms | <1 ms |
| State diagram (6 states) | 210 ms | 830 ms | <1 ms |

All renders meet the 500ms target per [D-PERF-1] with the **reuse** strategy (warm). Create/Destroy exceeds 500ms due to WKWebView initialization overhead (~600ms).

### Cache Validation

| Test | Result |
|---|---|
| Same content + same theme → cache hit | PASS — second render returns in <1ms |
| Same content + different theme → cache miss | PASS — theme included in hash, separate entries |
| Modified content → cache miss | PASS — new hash generated |
| `invalidateCache()` clears all entries | PASS — subsequent renders are all cache misses |
| `invalidate(content:)` clears both themes for that content | PASS — targeted invalidation works |
| Content hash is deterministic (SHA256) | PASS — same input always produces same key |

### Theme Switching

| Test | Result |
|---|---|
| Light theme renders with mermaid.js "default" theme | PASS |
| Dark theme renders with mermaid.js "dark" theme | PASS |
| Theme change triggers full cache invalidation | PASS |
| Re-render after theme change produces correct colors | PASS |
| Theme ID included in cache key prevents stale images | PASS |

### Image Quality

- Rasterization at 2x scale produces sharp images on Retina displays
- SVG rendering via WKWebView preserves text clarity and edge sharpness
- Transparent background allows diagrams to sit naturally on editor background
- For PDF export: re-render at print scale or extract SVG string directly from the web view for vector output (preferred per [A-006] rendering pipeline step 3)

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| WKWebView process killed under memory pressure (reuse) | Medium on 6GB devices | Detect process termination via `webViewWebContentProcessDidTerminate`, re-create web view on next render. Cached images survive (they're in our process). |
| mermaid.js CDN unavailable | N/A for production | Bundle mermaid.js as a local resource in EMEditor. CDN used only for spike convenience. |
| Large/complex diagrams exceed 500ms render time | Low | Diagrams in typical markdown documents are simple. For outliers, show a placeholder and render async. |
| WKWebView security: malicious mermaid content | Low | `securityLevel: 'strict'` in mermaid config. WKWebView sandboxed. No network access needed for local JS bundle. |
| Memory leak from retained WKWebViews | Low | Single instance with reuse strategy. `NSCache` handles eviction under memory pressure. |

## Recommendation

**The offscreen WKWebView approach is validated per [A-006]. Proceed with FEAT-030 implementation.**

### Lifecycle: Hybrid Reuse Strategy

Neither pure reuse nor pure create/destroy is ideal. Recommend a **hybrid approach**:

1. **Default: Reuse** — keep a single offscreen WKWebView alive while a document with Mermaid blocks is open. This gives 180–220ms render latency (within 500ms budget) and avoids repeated cold-start overhead.
2. **Release on document close** — when the user closes the document or navigates away, release the WKWebView. Cached images remain in `NSCache` for quick re-display if the user returns.
3. **Re-create on web process termination** — if iOS kills the web content process under memory pressure, detect via delegate and lazily re-create on next render.

This approach keeps steady-state memory at ~30 MB for a 10-diagram document (18 MB WKWebView + ~12 MB cached images), which fits within the [D-PERF-5] budget alongside the editor and AI model.

### Memory Budget Assessment

| Component | Memory |
|---|---|
| Editor baseline (TextKit 2, document) | ~15 MB |
| MLX Swift AI model (memory-mapped, per SPIKE-005) | ~42 MB resident |
| Mermaid WKWebView (reuse, 10 diagrams) | ~30 MB |
| Image loader cache | up to 50 MB |
| **Total estimated peak** | **~137 MB** |

On a 6 GB device, this leaves ample headroom (iOS typically allows 1.5–2 GB per app before jetsam). The Mermaid WKWebView is the second-largest consumer after the image cache, but both use `NSCache` which automatically evicts under memory pressure.

### Actions

- Remove `[RESEARCH-needed]` from [A-006]. Mark as `[RESEARCH-complete]`.
- Update [A-006] to specify: "Offscreen WKWebView with hybrid reuse lifecycle. Bundle mermaid.js locally. Cache rendered images keyed by SHA256(theme + content)."
- For FEAT-030: Use `MermaidRenderer` as the starting point. Add `NSTextAttachment` integration (same pattern as `ImageTextAttachment`).
- Bundle `mermaid.js` v10 as a local resource in EMEditor (not CDN).
- Implement `webViewWebContentProcessDidTerminate` recovery in production code.

## Artifacts

- `Sources/EMEditor/MermaidRenderer.swift` — Prototype renderer with WKWebView, cache, and memory measurement
- `Tests/EMEditorTests/MermaidRendererTests.swift` — Unit tests for cache keys, initialization, and memory measurement
- `docs/spikes/SPIKE-006.md` — This findings document
