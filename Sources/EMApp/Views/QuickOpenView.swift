/// Quick Open (Cmd+P) — fuzzy file search over recent files per FEAT-016.
///
/// Invoked via Cmd+P from the editor or home screen. Presents a modal search
/// palette that fuzzy-matches recent file entries by filename and path.
/// Results are ranked by match quality first, then recency.
/// Selecting a result opens the file immediately.
///
/// Acceptance criteria (FEAT-016):
/// - Cmd+P invokes the palette
/// - Typing 3+ characters returns results within 200ms (local filter, no I/O)
/// - Empty state shown when no recent files exist
/// - Stale (inaccessible) entries are excluded from results

import SwiftUI
import EMCore

// MARK: - Quick Open Sheet

/// Modal search palette for Quick Open (FEAT-016).
struct QuickOpenView: View {
    @Environment(RecentsManager.self) private var recentsManager
    @Environment(FileOpenCoordinator.self) private var fileOpenCoordinator
    @Environment(AppRouter.self) private var router

    @Binding var isPresented: Bool

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFieldFocused: Bool

    // MARK: - Filtered results

    /// Fuzzy-matched + ranked results. Computed synchronously — all data is in-memory,
    /// satisfying the 200ms AC even for 20 entries on the oldest supported device.
    private var results: [QuickOpenResult] {
        let items = recentsManager.recentItems

        // No query → return all recents sorted by recency (most recent first)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return items.map { QuickOpenResult(item: $0, score: 0, ranges: []) }
        }

        // Build fuzzy-matched results
        let q = query.lowercased()
        var scored: [QuickOpenResult] = []

        for item in items {
            let filename = item.filename.lowercased()
            let folder = item.parentFolder.lowercased()
            let path = item.urlPath.lowercased()

            // Try exact prefix match on filename (highest score)
            if filename.hasPrefix(q) {
                let range = NSRange(location: 0, length: q.count)
                scored.append(QuickOpenResult(item: item, score: 1000, ranges: [range]))
                continue
            }

            // Try substring match on filename
            if let range = filename.range(of: q) {
                let nsRange = NSRange(range, in: filename)
                scored.append(QuickOpenResult(item: item, score: 500 + nsRange.location, ranges: [nsRange]))
                continue
            }

            // Try fuzzy match on filename (sequential char matching)
            if let (fScore, fRanges) = fuzzyMatch(q, in: item.filename) {
                scored.append(QuickOpenResult(item: item, score: fScore, ranges: fRanges))
                continue
            }

            // Try substring match on folder name
            if folder.contains(q) {
                scored.append(QuickOpenResult(item: item, score: 100, ranges: []))
                continue
            }

            // Try substring match on full path
            if path.contains(q) {
                scored.append(QuickOpenResult(item: item, score: 50, ranges: []))
            }
        }

        // Sort by score descending, then recency descending
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.item.lastOpenedDate > $1.item.lastOpenedDate
        }

        return scored
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Open file…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18))
                    .focused($searchFieldFocused)
                    .autocorrectionDisabled(true)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .accessibilityLabel("Quick Open search")
                    .accessibilityHint("Type to filter recent files. Use arrow keys to select, Return to open.")
                    .onSubmit {
                        openSelected()
                    }

                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            // Results list
            if recentsManager.recentItems.isEmpty {
                emptyStateView
            } else if results.isEmpty {
                noResultsView
            } else {
                resultsList
            }
        }
        #if os(iOS)
        .background(.regularMaterial)
        #else
        .background(.windowBackground)
        #endif
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 8)
        .frame(maxWidth: 560)
        .onAppear {
            searchFieldFocused = true
        }
        .onChange(of: results.count) { _, _ in
            selectedIndex = 0
        }
        #if os(iOS)
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 { selectedIndex -= 1 }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if selectedIndex < results.count - 1 { selectedIndex += 1 }
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        #endif
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    QuickOpenResultRow(
                        result: result,
                        isSelected: index == selectedIndex
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndex = index
                        openSelected()
                    }
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif

                    if index < results.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .frame(maxHeight: 340)
        .accessibilityLabel("Recent files")
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No recent files")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Open a file first, then use Quick Open to switch between files fast.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var noResultsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No matches for "\(query)"")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func openSelected() {
        guard !results.isEmpty, selectedIndex < results.count else { return }
        let result = results[selectedIndex]
        openResult(result)
    }

    private func openResult(_ result: QuickOpenResult) {
        isPresented = false
        query = ""

        guard let url = recentsManager.resolveRecentItem(result.item) else {
            // Stale entry — already removed by resolveRecentItem (AC-3)
            return
        }

        let attempt = fileOpenCoordinator.openFile(url: url)
        switch attempt {
        case .opened, .alreadyOpen:
            router.openEditor()
        case .failed:
            break
        }
    }

    // MARK: - Fuzzy Matching

    /// Sequential character fuzzy match. Returns (score, highlight ranges) or nil if no match.
    ///
    /// Higher score = tighter match (fewer gaps between matched chars).
    /// Ranges are in terms of the original (non-lowercased) string for highlight rendering.
    private func fuzzyMatch(_ query: String, in target: String) -> (Int, [NSRange])? {
        let targetLower = target.lowercased()
        var qi = query.startIndex
        var ti = targetLower.startIndex
        var matchPositions: [String.Index] = []

        while qi < query.endIndex && ti < targetLower.endIndex {
            if query[qi] == targetLower[ti] {
                matchPositions.append(ti)
                qi = query.index(after: qi)
            }
            ti = targetLower.index(after: ti)
        }

        guard qi == query.endIndex else { return nil }

        // Score: start with max, penalise gaps between matches
        var score = 200
        for i in 1 ..< matchPositions.count {
            let gap = targetLower.distance(from: matchPositions[i - 1], to: matchPositions[i])
            score -= gap
        }
        // Bonus if match starts at beginning of a word
        if let first = matchPositions.first {
            let idx = targetLower.distance(from: targetLower.startIndex, to: first)
            if idx == 0 { score += 50 }
            else {
                let prevIdx = targetLower.index(before: first)
                let prev = targetLower[prevIdx]
                if prev == " " || prev == "-" || prev == "_" || prev == "/" { score += 30 }
            }
        }

        // Convert to NSRanges for highlight rendering
        let nsRanges = matchPositions.map { pos -> NSRange in
            NSRange(pos ..< targetLower.index(after: pos), in: targetLower)
        }

        return (max(score, 1), nsRanges)
    }
}

// MARK: - Result Row

private struct QuickOpenResultRow: View {
    let result: QuickOpenResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.body)
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HighlightedText(text: result.item.filename, ranges: result.ranges, isSelected: isSelected)
                    .font(.body.weight(.medium))

                Text(result.item.parentFolder)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }

            Spacer()

            Text(relativeDate(result.item.lastOpenedDate))
                .font(.caption)
                .foregroundStyle(isSelected ? .white.opacity(0.7) : .tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.item.filename) in \(result.item.parentFolder), opened \(relativeDate(result.item.lastOpenedDate))")
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Highlighted Text

/// Text view that renders highlight ranges (fuzzy match highlights) over a string.
private struct HighlightedText: View {
    let text: String
    let ranges: [NSRange]
    let isSelected: Bool

    var body: some View {
        Text(attributedString)
    }

    private var attributedString: AttributedString {
        var attributed = AttributedString(text)

        // Default: unselected foreground
        attributed.foregroundColor = isSelected ? .white : .primary

        // Apply highlight to matched ranges
        let ns = text as NSString
        for range in ranges {
            guard range.location != NSNotFound,
                  range.location + range.length <= ns.length,
                  let swiftRange = Range(range, in: text) else { continue }
            attributed[swiftRange].foregroundColor = isSelected ? .white : .accentColor
            attributed[swiftRange].font = .body.weight(.semibold)
        }

        return attributed
    }
}

// MARK: - Data Model

/// A scored Quick Open result wrapping a RecentItem.
struct QuickOpenResult: Identifiable {
    let item: RecentItem
    let score: Int
    /// Highlight ranges within `item.filename` for fuzzy match display.
    let ranges: [NSRange]

    var id: UUID { item.id }
}
