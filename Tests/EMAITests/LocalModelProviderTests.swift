import Testing
import Foundation
@testable import EMAI
@testable import EMCore

@Suite("LocalModelProvider")
struct LocalModelProviderTests {

    private func makeProvider(withModel: Bool = false) throws -> (LocalModelProvider, ModelStorageManager) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-local-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        if withModel {
            try storage.ensureDirectoryExists()
            try Data("model-data".utf8).write(to: storage.modelFileURL)
        }
        let loader = ModelLoader(storage: storage)
        let provider = LocalModelProvider(modelLoader: loader, storage: storage)
        return (provider, storage)
    }

    @Test("name is On-Device AI")
    func name() throws {
        let (provider, _) = try makeProvider()
        #expect(provider.name == "On-Device AI")
    }

    @Test("requiresNetwork is false")
    func noNetwork() throws {
        let (provider, _) = try makeProvider()
        #expect(provider.requiresNetwork == false)
    }

    @Test("requiresSubscription is false")
    func noSubscription() throws {
        let (provider, _) = try makeProvider()
        #expect(provider.requiresSubscription == false)
    }

    @Test("isAvailable returns false when model not downloaded")
    func unavailableWithoutModel() async throws {
        let (provider, _) = try makeProvider(withModel: false)
        let available = await provider.isAvailable
        // On simulator (fullAI) but no model → false
        if DeviceCapability.detect() == .fullAI {
            #expect(available == false)
        }
    }

    @Test("isAvailable returns true when model present on capable device")
    func availableWithModel() async throws {
        let (provider, _) = try makeProvider(withModel: true)
        let available = await provider.isAvailable
        if DeviceCapability.detect() == .fullAI {
            #expect(available == true)
        }
    }

    @Test("supports basic actions")
    func supportsBasicActions() throws {
        let (provider, _) = try makeProvider()
        #expect(provider.supports(action: .improve) == true)
        #expect(provider.supports(action: .summarize) == true)
        #expect(provider.supports(action: .continueWriting) == true)
        #expect(provider.supports(action: .ghostTextComplete) == true)
        #expect(provider.supports(action: .smartComplete) == true)
    }

    @Test("does not support complex cloud-only actions")
    func doesNotSupportComplexActions() throws {
        let (provider, _) = try makeProvider()
        #expect(provider.supports(action: .translate(targetLanguage: "es")) == false)
        #expect(provider.supports(action: .adjustTone(style: .formal)) == false)
        #expect(provider.supports(action: .generateFromPrompt) == false)
        #expect(provider.supports(action: .analyzeDocument) == false)
        #expect(provider.supports(action: .editDiagram) == false)
    }
}
