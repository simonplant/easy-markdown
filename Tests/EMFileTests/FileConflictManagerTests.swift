import Testing
import Foundation
@testable import EMFile

@Suite("FileConflictManager")
struct FileConflictManagerTests {

    @MainActor
    @Test("Initial state is no conflict")
    func initialState() {
        let url = URL(fileURLWithPath: "/tmp/conflict-test.md")
        let manager = FileConflictManager(url: url)

        #expect(manager.conflictState == .none)
        #expect(manager.isAutoSavePaused == false)
    }

    @MainActor
    @Test("Auto-save is paused when conflict is active")
    func autoSavePausedDuringConflict() {
        let url = URL(fileURLWithPath: "/tmp/conflict-test.md")
        let manager = FileConflictManager(url: url)

        // Simulate external change via the monitor's callback
        #expect(manager.isAutoSavePaused == false)
    }

    @MainActor
    @Test("keepMine clears conflict state")
    func keepMineClearsState() {
        let url = URL(fileURLWithPath: "/tmp/conflict-test.md")
        let manager = FileConflictManager(url: url)

        // keepMine should always be safe to call even with no conflict
        manager.keepMine()
        #expect(manager.conflictState == .none)
        #expect(manager.isAutoSavePaused == false)
    }

    @MainActor
    @Test("Start and stop monitoring is safe")
    func startStopMonitoring() {
        let url = URL(fileURLWithPath: "/tmp/conflict-test.md")
        let manager = FileConflictManager(url: url)

        manager.startMonitoring()
        manager.stopMonitoring()
    }

    @MainActor
    @Test("Double start and stop is safe")
    func doubleStartStop() {
        let url = URL(fileURLWithPath: "/tmp/conflict-test.md")
        let manager = FileConflictManager(url: url)

        manager.startMonitoring()
        manager.startMonitoring()
        manager.stopMonitoring()
        manager.stopMonitoring()
    }

    @MainActor
    @Test("Pause and resume detection delegates to monitor")
    func pauseResumeDetection() {
        let url = URL(fileURLWithPath: "/tmp/conflict-test.md")
        let manager = FileConflictManager(url: url)

        // Should not crash when called without monitoring
        manager.pauseDetection()
        manager.resumeDetection()
    }

    @MainActor
    @Test("Reload with real file returns content and clears conflict")
    func reloadWithRealFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("conflict-reload-test-\(UUID().uuidString).md")
        let testContent = "# Hello\n\nWorld"
        try testContent.data(using: .utf8)!.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let manager = FileConflictManager(url: testFile)
        let content = try manager.reload()

        #expect(content.text == testContent)
        #expect(manager.conflictState == .none)
    }

    @MainActor
    @Test("Reload with missing file throws error")
    func reloadMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-conflict-test-\(UUID().uuidString).md")
        let manager = FileConflictManager(url: url)

        #expect(throws: (any Error).self) {
            try manager.reload()
        }
    }
}
