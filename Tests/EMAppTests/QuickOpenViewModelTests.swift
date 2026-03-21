import Testing
import Foundation
@testable import EMApp
@testable import EMSettings

@MainActor
@Suite("QuickOpenViewModel")
struct QuickOpenViewModelTests {

    private func makeSetup(items: [RecentItem] = []) -> (QuickOpenViewModel, RecentsManager, UserDefaults) {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsManager(defaults: defaults)
        let manager = RecentsManager(defaults: defaults, settings: settings)

        // Inject test items via UserDefaults
        if !items.isEmpty {
            let data = try! JSONEncoder().encode(items)
            defaults.set(data, forKey: "em_recentFiles")
            // Re-create manager to pick up the items
            let freshManager = RecentsManager(defaults: defaults, settings: settings)
            let vm = QuickOpenViewModel(recentsManager: freshManager)
            return (vm, freshManager, defaults)
        }

        let vm = QuickOpenViewModel(recentsManager: manager)
        return (vm, manager, defaults)
    }

    private func makeItem(
        filename: String,
        parentFolder: String = "Documents",
        urlPath: String? = nil,
        lastOpenedDate: Date = Date()
    ) -> RecentItem {
        RecentItem(
            filename: filename,
            parentFolder: parentFolder,
            urlPath: urlPath ?? "/Users/test/\(parentFolder)/\(filename)",
            lastOpenedDate: lastOpenedDate,
            bookmarkData: Data([0x01, 0x02])
        )
    }

    @Test("Empty query produces no results")
    func emptyQuery() {
        let items = [makeItem(filename: "test.md")]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = ""
        #expect(vm.results.isEmpty)
    }

    @Test("Whitespace-only query produces no results")
    func whitespaceQuery() {
        let items = [makeItem(filename: "test.md")]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "   "
        #expect(vm.results.isEmpty)
    }

    @Test("Matching query returns results")
    func matchingQuery() {
        let items = [
            makeItem(filename: "readme.md"),
            makeItem(filename: "notes.md"),
        ]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "read"
        #expect(vm.results.count == 1)
        #expect(vm.results.first?.recentItem.filename == "readme.md")
    }

    @Test("Non-matching query returns empty results")
    func nonMatchingQuery() {
        let items = [makeItem(filename: "readme.md")]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "xyz"
        #expect(vm.results.isEmpty)
    }

    @Test("Results ranked by match quality")
    func rankingByMatchQuality() {
        let items = [
            makeItem(filename: "some-readme.md"),
            makeItem(filename: "readme.md"),
        ]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "readme"
        #expect(vm.results.count == 2)
        // Exact filename match should rank first (shorter target, better score)
        #expect(vm.results.first?.recentItem.filename == "readme.md")
    }

    @Test("hasNoRecentFiles is true when recents empty")
    func emptyRecents() {
        let (vm, _, _) = makeSetup()
        #expect(vm.hasNoRecentFiles == true)
    }

    @Test("hasNoRecentFiles is false when recents exist")
    func nonEmptyRecents() {
        let items = [makeItem(filename: "test.md")]
        let (vm, _, _) = makeSetup(items: items)
        #expect(vm.hasNoRecentFiles == false)
    }

    @Test("Reset clears query and results")
    func reset() {
        let items = [makeItem(filename: "readme.md")]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "read"
        #expect(!vm.results.isEmpty)

        vm.reset()
        #expect(vm.query.isEmpty)
        #expect(vm.results.isEmpty)
    }

    @Test("Fuzzy matching on partial characters")
    func fuzzyMatch() {
        let items = [
            makeItem(filename: "architecture.md"),
            makeItem(filename: "readme.md"),
        ]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "arc"
        #expect(vm.results.count == 1)
        #expect(vm.results.first?.recentItem.filename == "architecture.md")
    }

    @Test("Multiple matches returned and sorted")
    func multipleMatches() {
        let items = [
            makeItem(filename: "main.md"),
            makeItem(filename: "manifest.md"),
            makeItem(filename: "readme.md"),
        ]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "ma"
        // "main.md" and "manifest.md" should match, "readme.md" also has 'm' and 'a'
        #expect(vm.results.count >= 2)
    }

    @Test("Recency affects ranking")
    func recencyRanking() {
        let oldDate = Date(timeIntervalSinceNow: -86400 * 30) // 30 days ago
        let recentDate = Date(timeIntervalSinceNow: -60) // 1 minute ago
        let items = [
            makeItem(filename: "old-notes.md", lastOpenedDate: oldDate),
            makeItem(filename: "new-notes.md", lastOpenedDate: recentDate),
        ]
        let (vm, _, _) = makeSetup(items: items)

        vm.query = "notes"
        #expect(vm.results.count == 2)
        // More recent file should rank higher when match quality is similar
        #expect(vm.results.first?.recentItem.filename == "new-notes.md")
    }
}
