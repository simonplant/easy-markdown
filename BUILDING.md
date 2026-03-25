# Building easy-markdown in Xcode

This project uses Swift Package Manager. No `.xcodeproj` is checked in (per A-001). Follow these steps to create an app target in Xcode.

## Prerequisites

- Xcode 16+ (Swift 5.9+)
- iOS 17+ deployment target (per A-002)
- macOS 14+ (Sonoma) for Mac Catalyst / native macOS target

## Step-by-step setup

### 1. Open the SPM workspace

Open `Package.swift` in Xcode. It will resolve dependencies and index the package automatically.

### 2. Create an app target

1. **File > New > Target...**
2. Choose **App** (iOS or multiplatform)
3. Name it **EasyMarkdown**
4. Set the **Bundle Identifier** (e.g. `com.yourteam.easymarkdown`)
5. Select **SwiftUI** for Interface and **Swift** for Language
6. Uncheck "Include Tests" (tests already exist as SPM test targets)

### 3. Replace the generated entry point

Delete the auto-generated `ContentView.swift` and `EasyMarkdownApp.swift` that Xcode created in the new target.

Copy (or reference) the files from the `EasyMarkdownApp/` directory in this repo:

- **`EasyMarkdownApp.swift`** — the `@main` entry point. It delegates to `AppShell` from EMApp.
- **`Info.plist`** — declares UTI imports for `.md`/`.markdown` files and enables multi-window on iPad.

### 4. Add the EMApp dependency

1. In the target's **General** tab, scroll to **Frameworks, Libraries, and Embedded Content**
2. Click **+** and add **EMApp** from the package
3. EMApp transitively brings in all other modules (EMCore, EMEditor, EMFile, etc.)

### 5. Configure the Info.plist

1. In the target's **Build Settings**, search for `Info.plist File`
2. Set it to `EasyMarkdownApp/Info.plist`

### 6. Configure signing

1. In the target's **Signing & Capabilities** tab, select your Team
2. Enable **Automatically manage signing**
3. The bundle identifier must match what you set in step 2

### 7. Build and run

1. Select your target device or simulator (iOS 17+)
2. **Product > Build** (Cmd+B) to verify the build succeeds
3. **Product > Run** (Cmd+R) to launch the app

You should see the app's home screen. From there you can open or create markdown files.

## Troubleshooting

- **"Missing module" errors**: Ensure EMApp is added as a framework dependency (step 4). Xcode resolves transitive SPM dependencies automatically.
- **Signing errors**: Verify your team is selected and the bundle identifier is unique.
- **Swift version mismatch**: This project requires Swift 5.9+. Check **Build Settings > Swift Compiler - Language > Swift Language Version**.

## SPM-only builds (no Xcode target)

The SPM package builds independently of any Xcode app target:

```bash
swift build    # Build all library targets
swift test     # Run all unit tests
```

The `EasyMarkdownApp/` directory is not part of any SPM target and is ignored by `swift build`.
