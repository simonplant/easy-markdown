import Testing
import Foundation
@testable import EMFile

@Suite("OpenFileRegistry")
struct OpenFileRegistryTests {

    let testURL1 = URL(fileURLWithPath: "/tmp/test1.md")
    let testURL2 = URL(fileURLWithPath: "/tmp/test2.md")

    @Test("Initially empty")
    func initiallyEmpty() {
        let registry = OpenFileRegistry()
        #expect(registry.count == 0)
        #expect(registry.isOpen(testURL1) == false)
    }

    @Test("Registers and detects open file")
    func registerAndDetect() {
        let registry = OpenFileRegistry()
        registry.register(testURL1)

        #expect(registry.isOpen(testURL1) == true)
        #expect(registry.count == 1)
    }

    @Test("Unregisters file")
    func unregister() {
        let registry = OpenFileRegistry()
        registry.register(testURL1)
        registry.unregister(testURL1)

        #expect(registry.isOpen(testURL1) == false)
        #expect(registry.count == 0)
    }

    @Test("Distinguishes between different files")
    func distinguishesFiles() {
        let registry = OpenFileRegistry()
        registry.register(testURL1)

        #expect(registry.isOpen(testURL1) == true)
        #expect(registry.isOpen(testURL2) == false)
    }

    @Test("Tracks multiple open files")
    func multipleFiles() {
        let registry = OpenFileRegistry()
        registry.register(testURL1)
        registry.register(testURL2)

        #expect(registry.count == 2)
        #expect(registry.isOpen(testURL1) == true)
        #expect(registry.isOpen(testURL2) == true)

        registry.unregister(testURL1)
        #expect(registry.count == 1)
        #expect(registry.isOpen(testURL1) == false)
        #expect(registry.isOpen(testURL2) == true)
    }

    @Test("Unregistering non-registered URL is safe")
    func unregisterNonExistent() {
        let registry = OpenFileRegistry()
        registry.unregister(testURL1) // Should not crash
        #expect(registry.count == 0)
    }

    @Test("Duplicate registration is idempotent")
    func duplicateRegistration() {
        let registry = OpenFileRegistry()
        registry.register(testURL1)
        registry.register(testURL1)

        #expect(registry.count == 1)
    }
}
