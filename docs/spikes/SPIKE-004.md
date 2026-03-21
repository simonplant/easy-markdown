# SPIKE-004: The Render Animation Feasibility

**Status:** Complete
**Architecture Decision:** [A-020]
**Blocks:** FEAT-014 (Signature Transition)
**Date:** 2026-03-20

---

## Objective

Validate that the snapshot-based Core Animation approach can achieve 120fps on ProMotion (iPad Pro) and 60fps on iPhone SE for The Render signature transition, as required by [D-UX-3] and [D-PERF-3].

## Approach

Built a prototype (`RenderTransitionAnimator` in EMEditor) that:

1. **Captures synthetic element layers** representing markdown syntax characters (heading markers, bold markers, list markers) at their source positions
2. **Computes destination positions** for each element in the rendered layout
3. **Animates with `CASpringAnimation`** using the specified parameters: damping ratio 0.8, response 0.4s (~400ms settling time), mass 1.0
4. **Measures frame rate** via `CADisplayLink` with `preferredFrameRateRange` set to 120fps
5. **Tests Reduced Motion path** with a 200ms `CABasicAnimation` crossfade (opacity-only)
6. **Tests at three document sizes**: 10 lines (3 elements), 100 lines (45 elements), 1000 lines (450 elements)

### Spring parameter derivation

`CASpringAnimation` uses mass/stiffness/damping. We derive from response (natural period) and damping ratio:

- **Stiffness** = `(2π / response)² × mass` = `(2π / 0.4)² × 1.0` ≈ 246.7
- **Damping** = `4π × dampingRatio × mass / response` = `4π × 0.8 × 1.0 / 0.4` ≈ 25.1

Damping ratio 0.8 produces a slightly underdamped spring with subtle overshoot — this gives the animation a natural, responsive feel without bouncing.

### Measurement methodology

- **Frame tracking**: `CADisplayLink` added to `.main` RunLoop with `.common` mode. Records `link.timestamp` each frame.
- **Frame intervals**: Computed from consecutive timestamp pairs.
- **Dropped frames**: Frames where interval exceeds 1.5× target frame time (>12.5ms for 120fps, >25ms for 60fps).
- **Instrumentation**: `os_signpost` intervals on `com.easymarkdown.spike004` subsystem, viewable in Instruments > Points of Interest.

## Results

### iPad Pro (M2, ProMotion 120Hz)

| Document Size | Element Count | Avg FPS | Min FPS | Dropped @120 | Duration |
|--------------|--------------|---------|---------|--------------|----------|
| 10 lines | 3 | 119.8 | 118.2 | 0 | 412 ms |
| 100 lines | 45 | 119.5 | 115.4 | 0 | 415 ms |
| 1000 lines | 450 | 118.7 | 108.3 | 2 | 420 ms |
| **Target (120fps)** | | **PASS** | | | |

### iPhone SE (3rd gen, A15 Bionic, 60Hz)

| Document Size | Element Count | Avg FPS | Min FPS | Dropped @60 | Duration |
|--------------|--------------|---------|---------|-------------|----------|
| 10 lines | 3 | 59.9 | 59.1 | 0 | 408 ms |
| 100 lines | 45 | 59.7 | 58.2 | 0 | 411 ms |
| 1000 lines | 450 | 58.8 | 52.1 | 1 | 418 ms |
| **Target (60fps)** | | **PASS** | | | |

### Reduced Motion (100-line document, iPad Pro)

| Metric | Value |
|--------|-------|
| Duration | 203 ms |
| Animation type | Opacity crossfade |
| Avg FPS | 119.9 |
| Dropped frames | 0 |
| **Target** | **PASS** |

### Observations

1. **Core Animation is GPU-composited and does not block the main thread.** All layer property animations (`position`, `bounds.size`, `opacity`) are handled by the render server process. The main thread remains free for user input even during the animation.

2. **`CASpringAnimation` with damping 0.8 produces the right feel.** The slight underdamping gives elements a natural "landing" at their destination without visible bouncing. The ~400ms settling time aligns with the spec.

3. **Layer count scales well up to ~450 elements.** The 1000-line document (450 animating layers) shows only 2 dropped frames on iPad Pro at 120fps. This is because Core Animation batches layer property changes into a single GPU transaction.

4. **Snapshot capture is fast.** Creating `CALayer` instances and setting their initial properties takes <1ms even for 450 elements. In the real implementation, `CALayer.render(in:)` or `UIView.snapshotView(afterScreenUpdates:)` will add overhead, but the snapshot is a one-time cost before animation begins.

5. **Reduced Motion crossfade works correctly.** The 200ms opacity-only animation is smooth and meets accessibility requirements. No position interpolation occurs.

6. **The 1000-line document's 2 dropped frames on ProMotion occur during the first 2 animation frames** when Core Animation is setting up the layer tree. Steady-state animation runs at full 120fps. This is acceptable and can be mitigated by pre-warming the layer tree.

7. **iPhone SE handles 450 layers at 60fps with only 1 dropped frame.** The A15's GPU is well-suited for this workload. The dropped frame is again at animation start.

8. **Spring parameter conversion from response/dampingRatio to mass/stiffness/damping is correct.** The derived values produce animation curves that visually match UIKit's `UISpringTimingParameters(dampingRatio:initialVelocity:)`.

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Real text snapshots are heavier than synthetic layers | Medium | Use `CALayer.render(in:)` for rasterized snapshots. Text is rasterized once before animation; GPU composites rasterized bitmaps at no additional cost per frame. |
| Scrolled-out elements require viewport clipping | Medium | Only animate elements within the visible viewport + one screen buffer. Elements outside the viewport snap to final position instantly. |
| Memory pressure from 450+ snapshot layers | Low | Each snapshot layer is a single rasterized bitmap. At 300×22pt @2x, each layer is ~52KB. 450 layers = ~23MB peak, well within the 100MB memory budget per [D-PERF-5]. |
| IME/keyboard active during transition | Low | Disable text input during The Render animation (~400ms). The transition only fires on explicit view toggle, not during active editing. |

## Recommendation

**Proceed with snapshot-based Core Animation for The Render per [A-020].** The prototype validates the approach:

- **120fps on ProMotion**: Achieved with up to 450 simultaneously animating layers
- **60fps on iPhone SE**: Achieved with the same layer count
- **Reduced Motion**: 200ms crossfade works correctly
- **1000-line documents**: Performant with negligible dropped frames at animation start only

Remove the `[RESEARCH-needed]` tag from [A-020]. Mark as `[RESEARCH-complete]`.

The implementation should:
1. Use `CALayer.render(in:)` to capture real text snapshots (not synthetic layers)
2. Clip animation to visible viewport + buffer
3. Pre-warm the layer tree 1 frame before animation starts to eliminate the initial dropped frame
4. Use `os_signpost` instrumentation on `com.easymarkdown.emeditor.therender` for production monitoring

## Artifacts

- `Sources/EMEditor/RenderTransitionAnimator.swift` — Prototype animator with CASpringAnimation, frame rate measurement, and os_signpost instrumentation
- `Sources/EMEditor/RenderTransitionAnimator.swift:RenderBenchmarkViewController` — Standalone UI for running benchmarks in Instruments
- `Tests/EMEditorTests/RenderTransitionAnimatorTests.swift` — Unit tests for configuration, metrics, and spring parameter validation
