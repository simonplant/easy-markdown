import Testing
import Foundation
@testable import EMAI

@MainActor
@Suite("ModelDownloadManager")
struct ModelDownloadManagerTests {

    private func makeComponents() -> (ModelDownloadManager, ModelStorageManager) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-download-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        let networkMonitor = NetworkMonitor()
        let modelURL = URL(string: "https://models.easymarkdown.app/v1/test-model")!
        let manager = ModelDownloadManager(
            modelURL: modelURL,
            storage: storage,
            networkMonitor: networkMonitor
        )
        return (manager, storage)
    }

    // MARK: - Initial State

    @Test("Initial state is idle when no model or partial download")
    func initialStateIdle() {
        let (manager, _) = makeComponents()
        #expect(manager.state == .idle)
        #expect(manager.progress == 0.0)
        #expect(manager.bytesDownloaded == 0)
        #expect(manager.lastError == nil)
    }

    @Test("Initial state is completed when model already present")
    func initialStateCompleted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-download-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        try Data("model".utf8).write(to: storage.modelFileURL)

        let manager = ModelDownloadManager(
            modelURL: URL(string: "https://example.com/model")!,
            storage: storage,
            networkMonitor: NetworkMonitor()
        )
        #expect(manager.state == .completed)
    }

    @Test("Initial state is paused when partial download exists (AC-2)")
    func initialStatePaused() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-download-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        let partialData = Data(repeating: 0x42, count: 50_000)
        try partialData.write(to: storage.tempDownloadURL)

        let manager = ModelDownloadManager(
            modelURL: URL(string: "https://example.com/model")!,
            storage: storage,
            networkMonitor: NetworkMonitor()
        )
        #expect(manager.state == .paused)
        #expect(manager.bytesDownloaded == 50_000, "Should restore byte count from partial file")
    }

    // MARK: - Cellular Policy (AC-3)

    @Test("allowsCellularDownload defaults to false")
    func cellularDefaultOff() {
        let (manager, _) = makeComponents()
        #expect(manager.allowsCellularDownload == false)
    }

    // MARK: - Cancel

    @Test("cancelDownload resets state to idle and removes partial file")
    func cancelResetsState() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-download-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        try Data("partial".utf8).write(to: storage.tempDownloadURL)

        let manager = ModelDownloadManager(
            modelURL: URL(string: "https://example.com/model")!,
            storage: storage,
            networkMonitor: NetworkMonitor()
        )
        manager.cancelDownload()
        #expect(manager.state == .idle)
        #expect(manager.progress == 0.0)
        #expect(manager.bytesDownloaded == 0)
        #expect(storage.hasPartialDownload == false)
    }

    // MARK: - Delete Model (AC-7)

    @Test("deleteModel resets state and removes files")
    func deleteModelResets() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-download-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        try Data("model".utf8).write(to: storage.modelFileURL)

        let manager = ModelDownloadManager(
            modelURL: URL(string: "https://example.com/model")!,
            storage: storage,
            networkMonitor: NetworkMonitor()
        )
        #expect(manager.state == .completed)

        try manager.deleteModel()
        #expect(manager.state == .idle)
        #expect(storage.isModelPresent == false)
    }

    // MARK: - Download State Machine

    @Test("DownloadState cases are distinct")
    func downloadStateCases() {
        let states: [DownloadState] = [
            .idle, .downloading, .paused,
            .waitingForWiFi, .failed, .insufficientStorage, .completed,
        ]
        for (i, a) in states.enumerated() {
            for (j, b) in states.enumerated() {
                if i == j {
                    #expect(a == b)
                } else {
                    #expect(a != b)
                }
            }
        }
    }

    // MARK: - Guard Conditions

    @Test("startDownload does nothing when already completed")
    func startDoesNothingWhenCompleted() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("emai-download-test-\(UUID().uuidString)")
        let storage = ModelStorageManager(modelDirectory: dir)
        try storage.ensureDirectoryExists()
        try Data("model".utf8).write(to: storage.modelFileURL)

        let manager = ModelDownloadManager(
            modelURL: URL(string: "https://example.com/model")!,
            storage: storage,
            networkMonitor: NetworkMonitor()
        )
        manager.startDownload()
        #expect(manager.state == .completed, "Should remain completed")
    }
}
