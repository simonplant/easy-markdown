# Building Easy Markdown

How to do the first device build. Takes about 10 minutes.

## What exists

The repo is a Swift Package Manager library — all modules are in `Sources/`. An `EasyMarkdownApp/` directory contains the app entry point and Info.plist, but there is no `.xcodeproj` yet. That needs to be created once in Xcode.

## First-time Xcode setup

### 1. Open the SPM package in Xcode

```bash
open Package.swift
```

Xcode opens the package. Wait for it to resolve the `swift-markdown` dependency (~30s first time).

### 2. Create the app target

In Xcode:
1. **File → New → Target…**
2. Choose **iOS → App**
3. Fill in:
   - **Product Name:** `EasyMarkdown`
   - **Bundle Identifier:** `com.easymarkdown.app`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Minimum Deployments:** iOS 17.0
4. Click **Finish**

### 3. Replace the generated app file

Xcode creates a new `EasyMarkdownApp.swift` in your target. Replace it:
1. Delete the Xcode-generated `EasyMarkdownApp.swift` (move to trash)
2. Drag `EasyMarkdownApp/EasyMarkdownApp.swift` from this repo into the target
3. Ensure "Copy items if needed" is **unchecked** (keep it in the repo location)

### 4. Use the provided Info.plist

The generated `Info.plist` from Xcode can be replaced with the one in `EasyMarkdownApp/Info.plist`. This adds:
- Correct UTI declarations for `.md`/`.markdown` files
- Multi-scene manifest for iPad Stage Manager
- Document type registration so Files app shows the app as an option

To swap it:
1. In Xcode project settings, find the **Info.plist File** build setting
2. Set it to `EasyMarkdownApp/Info.plist` (relative to the project)

### 5. Link against EMApp

In the app target's **General** tab:
1. Scroll to **Frameworks, Libraries, and Embedded Content**
2. Click **+**
3. Select `EMApp` from the package products list
4. Click **Add**

That's it — `EMApp` pulls in all other modules transitively.

### 6. Sign the app

In the target's **Signing & Capabilities** tab:
1. Select your Apple ID team
2. Enable **Automatically manage signing**
3. Bundle ID: `com.easymarkdown.app`

### 7. Build and run

Select your device or a simulator (iPhone 17+ for AI features, any iOS 17+ device otherwise).

```
Cmd+R
```

Expected first build time: 3–5 minutes (resolves `swift-markdown`, compiles all modules).

## What to validate on first build

- [ ] App launches without crash
- [ ] Home screen shows (file list / recents)
- [ ] **+** button opens the create file sheet
- [ ] System file picker opens via "Open…"
- [ ] Create a `.md` file, type some text — renders
- [ ] Bold (`**text**`), italic, headers render correctly
- [ ] Dark mode / light mode switch works (Settings)
- [ ] Autosave — edit, background the app, reopen — content preserved
- [ ] AI features show "not available" on older devices (expected until FEAT-041 ships)

## Expected compile-time warnings

- `swift-markdown` produces some deprecation warnings — ignore them
- `EMEditor` references `@preconcurrency` for TextKit 2 — expected

## Known gaps (not yet built)

| Feature | Status | Backlog |
|---------|--------|---------|
| The Render (signature transition) | todo | FEAT-014 |
| Quick Open | todo | FEAT-016 |
| Find & Replace | todo | FEAT-017 |
| Mermaid diagrams | todo | FEAT-030 |
| AI Ghost Text | todo | FEAT-056 |
| App Store purchase flow | todo | FEAT-063 |

The app is fully functional for opening, editing, and saving markdown files. AI Improve Writing and AI Summarize are done (FEAT-011, FEAT-055).

## Troubleshooting

**"No such module 'EMApp'"** — Make sure you added EMApp to the target's linked frameworks (step 5).

**Build fails with missing `AppShell`** — Make sure you're importing `EMApp` in `EasyMarkdownApp.swift`.

**"Could not resolve package"** — Xcode needs network access to fetch `swift-markdown` from GitHub. Check your connection.

**Signing error** — You need a paid Apple Developer account for device builds. Simulators work with a free account.
