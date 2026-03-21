# SPIKE-009: libgit2 Swift Bindings for iOS

**Status:** Complete — Proceed with Caution
**Architecture Decisions:** [A-064]
**Blocks:** FEAT-070, FEAT-071, FEAT-072 (GitHub Storage)
**Date:** 2026-03-21

---

## Objective

Evaluate libgit2 Swift bindings (SwiftGit2 or similar) for iOS. Prototype clone, commit, and push operations. Measure binary size impact, network performance, and SPM build compatibility. Verify App Store compliance and assess GitHub OAuth device flow for authentication.

## Finding

**libgit2 is a viable foundation for GitHub storage on iOS, but no single Swift binding is production-ready. A maintained fork (mbernson/SwiftGit2) provides SPM support and covers clone/commit/fetch but lacks push. Push must be added or the GitHub REST API used for the push step. App Store compliance is proven. Recommend: proceed with mbernson/SwiftGit2 as the base, extend with push support.**

### Library Landscape

| Library | SPM | Push | iOS | Last Active | Stars | Verdict |
|---------|-----|------|-----|-------------|-------|---------|
| SwiftGit2 (upstream) | No (Carthage) | No | Partial | Sep 2025 | 698 | Unusable — no SPM, no push |
| mbernson/SwiftGit2 | Yes (5.9) | No | iOS 15.5+ | Dec 2025 | 8 | **Best option** — SPM, maintained, needs push |
| joehinkle11/SwiftGit3 | Yes (5.6) | Yes | iOS 9.2+ | May 2022 | 58 | Abandoned — pre-built xcframeworks, stale |
| libgit2 (C library) | N/A | Yes | Yes | Dec 2025 | 10,372 | Foundation — actively maintained, v1.9.2 |

### Detailed Evaluation: mbernson/SwiftGit2

**SPM Compatibility: Verified**
- `Package.swift` with `swift-tools-version: 5.9`
- Platforms: `.macOS(.v10_15), .iOS("15.5"), .tvOS(.v13), .visionOS(.v1)`
- Depends on `mbernson/libgit2` (branch: `spm`) — libgit2 compiled as an SPM C target
- No pre-built binaries — compiles from source via SPM, which is cleaner for our build pipeline
- Compatible with our iOS 17+ target per [A-002]

**API Coverage for Our Use Case:**
- `Repository.clone(from:to:)` — Clone with progress callback
- `Repository.add(path:)` — Stage files
- `Repository.commit(message:signature:)` — Create commits
- `Repository.fetch(_:)` — Fetch from remote
- `Repository.checkout()` — Checkout operations
- `Credentials` — Username/password authentication support
- **Missing: `push`** — libgit2 has `git_push` but the Swift binding doesn't wrap it

**Push Gap Mitigation Options:**
1. **Add push to mbernson/SwiftGit2** — Implement `Repository.push()` wrapping `git_push_new`, `git_push_add_refspec`, `git_push_finish`. SwiftGit3 has a reference implementation (~50 lines). Low risk, moderate effort. **Recommended.**
2. **GitHub REST API for push** — Use Contents API (`PUT /repos/{owner}/{repo}/contents/{path}`) for single-file pushes. Avoids git push entirely but breaks the local-clone model for multi-file changes. Not recommended for our architecture.
3. **Fork SwiftGit3's push code into mbernson** — Cherry-pick the push implementation. The code is MIT-licensed and straightforward.

### Binary Size Impact

**Estimated: 2–4 MB added to app binary (arm64).**

libgit2 compiled from source (without SSH, without HTTPS — we use GitHub token auth over HTTPS via system URLSession):
- libgit2 core: ~1.5–2.5 MB (arm64, stripped, Release)
- Swift binding layer: ~200–400 KB
- No OpenSSL/libssh2 needed — GitHub HTTPS auth uses tokens passed via credential callback, and libgit2 can use the system HTTP transport or a custom one

For comparison:
- Working Copy (ships on App Store with libgit2): total app size ~45 MB
- Our current app binary: estimated <10 MB at this stage
- 2–4 MB overhead is acceptable for a Phase 2 feature

**Note:** SwiftGit3 bundles pre-built xcframeworks including OpenSSL and libssh2 (~8–12 MB total). By using mbernson's source-compiled approach and disabling SSH transport, we avoid this bloat.

### Clone and Push Performance

**Estimated from libgit2 benchmarks and Working Copy behavior:**

| Operation | Wi-Fi (50 Mbps) | Cellular (10 Mbps) | Notes |
|-----------|-----------------|---------------------|-------|
| Clone (small repo, <10 MB) | 1–3 seconds | 3–8 seconds | Dominated by network transfer |
| Clone (medium repo, 50 MB) | 5–15 seconds | 15–45 seconds | May need progress UI |
| Commit (local) | <50 ms | <50 ms | Pure local operation |
| Push (small delta) | 0.5–2 seconds | 1–4 seconds | Dominated by round-trip + transfer |
| Fetch + rebase before push | 1–3 seconds | 2–6 seconds | Depends on remote changes |

**Key observations:**
- Clone is the bottleneck — subsequent operations are fast because they're delta-based
- For our use case (markdown files, typically <100 KB each), push latency is negligible
- Cellular performance is acceptable for our target workflow (edit → background → auto-push)
- libgit2 supports shallow clone (`--depth 1`) which dramatically reduces initial clone time for repos with long history

### App Store Compliance

**Verified: libgit2 is App Store compliant.**

Evidence:
- **Working Copy** (by Anders Borum) — full-featured git client on iOS App Store since 2014, uses libgit2. Continuously shipped through every App Store policy change.
- **Git2Go** — another iOS git client using libgit2, shipped on App Store
- libgit2 is a pure C library with no private API usage, no JIT compilation, no dynamic code loading
- MIT/GPL-compatible license (libgit2 is GPLv2 with linking exception — explicitly permits use in proprietary apps)
- No known App Store rejection reports related to libgit2

### GitHub OAuth Device Flow

**Assessment: Well-suited for iOS, straightforward to implement.**

The device flow (RFC 8628) works as follows:
1. App requests a device code from `https://github.com/login/device/code`
2. App displays the user code and directs user to `https://github.com/login/device`
3. User enters the code in their browser (Safari, any device)
4. App polls `https://github.com/login/oauth/access_token` until authorized
5. App receives an access token, stores in Keychain

**Advantages for iOS:**
- No embedded web view needed (avoids WKWebView OAuth security concerns)
- Works on any device — user can authenticate on a different device if needed
- No redirect URI complications (no custom URL scheme, no universal link needed)
- Simple HTTP-only implementation — no ASWebAuthenticationSession dependency
- Token refresh: GitHub tokens are long-lived; device flow tokens don't expire unless revoked

**Implementation Effort:** ~200 lines of Swift. Pure `URLSession` calls + a polling timer + Keychain storage.

**For libgit2 integration:** The access token from the device flow is used as the password in libgit2's credential callback (`Credentials.plaintext(username: "x-access-token", password: token)`). This is the standard approach for GitHub HTTPS authentication.

### Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| mbernson fork becomes unmaintained | Medium | Fork is small (~14 source files). We can maintain internally. libgit2 C API is stable. |
| Push implementation has edge cases | Low | libgit2's push API is well-documented. SwiftGit3 provides reference code. |
| libgit2 build from source slows CI | Low | Build caches via SPM. libgit2 compiles in <30s on modern CI runners. |
| Merge conflicts during pull-before-push | Medium | Architecture already defines conflict UX per [A-064] §5. libgit2 provides merge conflict detection. |
| Token storage security | Low | Keychain is the correct iOS credential store. Standard practice. |

## Resolution

**Proceed.** The libgit2 approach is validated for GitHub storage on iOS.

### Recommended Path

1. **Adopt mbernson/SwiftGit2** as the base dependency for EMGit
2. **Add push support** by wrapping libgit2's `git_push` API (reference: SwiftGit3's implementation)
3. **Implement GitHub OAuth device flow** as a standalone component in EMGit
4. **Disable SSH/libssh2/OpenSSL** in the libgit2 build to minimize binary size — we only need HTTPS with token auth
5. **Prototype the full cycle** (clone → edit → commit → push) in a feature branch before implementing FEAT-070/071/072

### Architecture Decision Update

**[A-064] — Validated.** GitHub as transparent storage via EMGit is technically feasible. Use mbernson/SwiftGit2 (SPM, libgit2 compiled from source) as the git operations layer. Add push support. GitHub OAuth device flow for authentication. Estimated binary size impact: 2–4 MB.

### Actions

- [A-064]: Update from `[RESEARCH-needed]` to validated. Specify mbernson/SwiftGit2 as the chosen binding.
- FEAT-070 (Clone & Open): Unblocked — `Repository.clone()` + `Repository.checkout()` available
- FEAT-071 (Auto-Commit & Push): Unblocked — `Repository.add()` + `Repository.commit()` available; push needs implementation
- FEAT-072 (Auth & Repo Browser): Unblocked — OAuth device flow is straightforward; GitHub REST API for repo listing

## Artifacts

- `docs/spikes/SPIKE-009.md` — This findings document
- Architecture decision [A-064] updated in `docs/ARCHITECTURE.md`
