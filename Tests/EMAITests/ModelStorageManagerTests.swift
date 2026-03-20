import Testing
import Foundation
@testable import EMAI

@Suite("ModelStorageManager")
struct ModelStorageManagerTests {

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-storage-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Directory Management

    @Test("ensureDirectoryExists creates directory")
    func ensureDirectoryCreation() throws {
        let dir = makeTempDir().appendingPathComponent("Models")
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    // MARK: - Model Presence

    @Test("isModelPresent returns false when no model file")
    func modelNotPresent() {
        let storage = ModelStorageManager(modelDirectory: makeTempDir())
        #expect(storage.isModelPresent == false)
    }

    @Test("isModelPresent returns true when model file exists")
    func modelPresent() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        FileManager.default.createFile(atPath: storage.modelFileURL.path, contents: Data("model".utf8))
        #expect(storage.isModelPresent == true)
    }

    // MARK: - Model Size

    @Test("modelSizeOnDisk returns nil when no model")
    func sizeNilWhenMissing() {
        let storage = ModelStorageManager(modelDirectory: makeTempDir())
        #expect(storage.modelSizeOnDisk == nil)
    }

    @Test("modelSizeOnDisk returns correct size")
    func sizeCorrect() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        let data = Data(repeating: 0x42, count: 1024)
        try data.write(to: storage.modelFileURL)
        #expect(storage.modelSizeOnDisk == 1024)
    }

    // MARK: - Partial Download (AC-2)

    @Test("hasPartialDownload returns false when no temp file")
    func noPartialDownload() {
        let storage = ModelStorageManager(modelDirectory: makeTempDir())
        #expect(storage.hasPartialDownload == false)
    }

    @Test("hasPartialDownload returns true when temp file exists")
    func hasPartialDownload() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        try Data("partial".utf8).write(to: storage.tempDownloadURL)
        #expect(storage.hasPartialDownload == true)
    }

    @Test("partialDownloadSize returns correct byte count")
    func partialDownloadSize() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        let data = Data(repeating: 0x42, count: 2048)
        try data.write(to: storage.tempDownloadURL)
        #expect(storage.partialDownloadSize == 2048)
    }

    @Test("partialDownloadSize returns 0 when no partial download")
    func partialDownloadSizeZero() {
        let storage = ModelStorageManager(modelDirectory: makeTempDir())
        #expect(storage.partialDownloadSize == 0)
    }

    @Test("deletePartialDownload removes temp file")
    func deletePartialDownload() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        try Data("partial".utf8).write(to: storage.tempDownloadURL)
        #expect(storage.hasPartialDownload == true)
        storage.deletePartialDownload()
        #expect(storage.hasPartialDownload == false)
    }

    // MARK: - Finalize Download

    @Test("finalizeDownload moves temp file to model location")
    func finalizeDownload() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        let data = Data("completed-model".utf8)
        try data.write(to: storage.tempDownloadURL)
        #expect(storage.isModelPresent == false)

        try storage.finalizeDownload()

        #expect(storage.isModelPresent == true)
        #expect(storage.hasPartialDownload == false)
        let loaded = try Data(contentsOf: storage.modelFileURL)
        #expect(loaded == data)
    }

    // MARK: - Model Deletion (AC-7)

    @Test("deleteModel removes model file and partial download")
    func deleteModelCleansUp() throws {
        let dir = makeTempDir()
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()

        // Create model file and partial download
        try Data("model".utf8).write(to: storage.modelFileURL)
        try Data("partial".utf8).write(to: storage.tempDownloadURL)

        #expect(storage.isModelPresent == true)

        try storage.deleteModel()

        #expect(storage.isModelPresent == false)
        #expect(storage.hasPartialDownload == false)
    }

    // MARK: - Storage Check (AC-7)

    @Test("hasStorageSpace returns a result")
    func storageCheckReturns() {
        let storage = ModelStorageManager(modelDirectory: makeTempDir())
        let result = storage.hasStorageSpace()
        switch result {
        case .sufficient:
            #expect(result.hasSufficientSpace == true)
            #expect(result.userMessage == nil)
        case .insufficient:
            #expect(result.hasSufficientSpace == false)
            #expect(result.userMessage != nil)
        case .checkFailed:
            #expect(result.hasSufficientSpace == false)
            #expect(result.userMessage != nil)
        }
    }

    @Test("StorageCheckResult.insufficient provides user-facing message")
    func insufficientStorageMessage() {
        let result = StorageCheckResult.insufficient(
            availableBytes: 100 * 1024 * 1024,
            neededBytes: 2500 * 1024 * 1024
        )
        #expect(result.hasSufficientSpace == false)
        let message = result.userMessage
        #expect(message != nil)
        #expect(message!.contains("Not enough storage"))
    }
}
