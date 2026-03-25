import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("EasyMarkdown_EMCore.bundle").path
        let buildPath = "/Users/simonp/Library/Mobile Documents/com~apple~CloudDocs/dev/easy-markdown/.build/index-build/arm64-apple-macosx/debug/EasyMarkdown_EMCore.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}