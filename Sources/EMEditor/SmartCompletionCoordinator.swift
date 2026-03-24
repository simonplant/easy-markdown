/// Coordinates the AI Smart Completions flow per FEAT-025.
/// Detects markdown structure patterns on Enter and triggers context-aware ghost text.
/// Reuses GhostTextRenderer for dimmed inline suggestions, Tab to accept, typing to dismiss.
/// Lives in EMEditor (supporting package per [A-050]).

import Foundation
import Observation
import os
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import EMCore

/// The type of markdown structure detected for smart completion.
/// Mirrors SmartCompletionPromptTemplate.StructureType but lives in EMEditor
/// to avoid EMEditor importing EMAI per [A-015].
public enum SmartCompletionStructure: Sendable, Equatable {
    /// Table header row: `| col1 | col2 |`
    case tableHeader(columns: [String])
    /// List item: `- item` or `1. item`
    case listItem(prefix: String, items: [String])
    /// YAML front matter block
    case frontMatter(existingKeys: [String])
}

/// Coordinates the full AI Smart Completions lifecycle per FEAT-025.
///
/// Usage flow:
/// 1. User types a markdown structure (table header, list item, front matter) and presses Enter
/// 2. Coordinator detects the structure pattern on the previous line
/// 3. Triggers AI generation immediately (no pause timer — structures are unambiguous)
/// 4. Ghost text appears dimmed inline at cursor position via GhostTextRenderer
/// 5. Tab accepts (ghost text becomes real text, undo registered)
/// 6. Typing any character dismisses ghost text immediately
/// 7. VoiceOver announces "AI suggestion available" when ghost text appears
@MainActor
@Observable
public final class SmartCompletionCoordinator {
    /// Current phase of the smart completion session.
    public private(set) var phase: GhostTextPhase = .inactive

    /// The accumulated ghost text (grows as tokens stream in).
    public private(set) var ghostText: String = ""

    /// The cursor position where ghost text was inserted.
    public private(set) var insertionPoint: Int = 0

    /// Weak reference to the text view delegate (same protocol as ghost text).
    public weak var textViewDelegate: GhostTextViewDelegate?

    /// Whether smart completions are enabled (follows ghost text setting per spec).
    public var isEnabled: Bool = true

    /// The editor state for undo manager access.
    private let editorState: EditorState

    /// The streaming task.
    private var streamingTask: Task<Void, Never>?

    /// Closure called when a markdown structure is detected and smart completion should generate.
    /// Set by the composition root (EMApp) to start the EMAI service and return the stream.
    /// Parameters: (structureType, precedingText) → AsyncStream<GhostTextUpdate>?
    /// This keeps EMEditor decoupled from EMAI per [A-015].
    public var onRequestSmartCompletion: ((SmartCompletionStructure, String) -> AsyncStream<GhostTextUpdate>?)?

    /// Tracks the last replacement text to detect Enter presses.
    private var lastReplacementText: String?

    private let logger = Logger(subsystem: "com.easymarkdown.emeditor", category: "smart-completion")

    /// Creates a smart completion coordinator.
    /// - Parameter editorState: The editor state for undo manager access.
    public init(editorState: EditorState) {
        self.editorState = editorState
    }

    // MARK: - Enter Detection

    /// Called by TextViewCoordinator in `shouldChangeTextIn` to record the replacement text.
    /// This lets us know if the next `textDidChange` was triggered by an Enter press.
    public func willChangeText(replacementText: String) {
        lastReplacementText = replacementText
    }

    /// Called on every text change to check for smart completion triggers.
    /// Must be called AFTER the text has been inserted.
    public func textDidChange() {
        // Dismiss any active smart completion when user types
        if phase == .streaming || phase == .ready {
            dismiss()
        }

        guard isEnabled else { return }

        // Only trigger on Enter (newline insertion)
        guard let replacement = lastReplacementText, replacement == "\n" else {
            lastReplacementText = nil
            return
        }
        lastReplacementText = nil

        guard let delegate = textViewDelegate else { return }

        // Don't trigger inside code blocks
        if delegate.isCursorInsideCodeBlock() {
            return
        }

        let text = delegate.currentText()
        let selectedRange = delegate.currentSelectedRange()

        // Only trigger with no selection (just a cursor)
        guard selectedRange.length == 0 else { return }

        let cursorLocation = selectedRange.location
        guard cursorLocation > 0 else { return }

        // Detect the markdown structure on the line above the cursor
        guard let structure = detectStructure(in: text, cursorAt: cursorLocation) else {
            return
        }

        // Get preceding text for AI context (last 500 chars)
        let startIndex = max(0, cursorLocation - 500)
        let nsRange = NSRange(location: startIndex, length: cursorLocation - startIndex)
        guard let swiftRange = Range(nsRange, in: text) else { return }
        let precedingText = String(text[swiftRange])

        logger.debug("Detected markdown structure for smart completion")

        // Request smart completion from the composition root
        guard let stream = onRequestSmartCompletion?(structure, precedingText) else {
            logger.debug("No smart completion handler configured")
            return
        }

        startStreaming(updateStream: stream, at: cursorLocation)
    }

    // MARK: - Structure Detection

    /// Detects a markdown structure pattern on the line above the cursor.
    /// Returns the structure type if a smart completion trigger is found, nil otherwise.
    func detectStructure(in text: String, cursorAt cursorLocation: Int) -> SmartCompletionStructure? {
        // Get the line above the cursor (the line before the newline just inserted)
        guard let previousLine = extractPreviousLine(from: text, cursorAt: cursorLocation) else {
            return nil
        }

        let trimmed = previousLine.trimmingCharacters(in: .whitespaces)

        // Check table header pattern: | col1 | col2 | ...
        if let tableStructure = detectTableHeader(line: trimmed, fullText: text, cursorAt: cursorLocation) {
            return tableStructure
        }

        // Check if we're inside front matter
        if let frontMatterStructure = detectFrontMatter(fullText: text, cursorAt: cursorLocation) {
            return frontMatterStructure
        }

        // Check list item pattern
        if let listStructure = detectListItem(line: trimmed, fullText: text, cursorAt: cursorLocation) {
            return listStructure
        }

        return nil
    }

    /// Extracts the line immediately above the cursor position.
    /// After the user presses Enter, cursor is right after the new newline.
    /// We skip back past trailing newlines to find the actual content line.
    private func extractPreviousLine(from text: String, cursorAt cursorLocation: Int) -> String? {
        guard let cursorIndex = text.index(text.startIndex, offsetBy: cursorLocation, limitedBy: text.endIndex) else {
            return nil
        }

        // Skip backwards past any trailing newlines to find the end of the content line.
        // After Enter, the cursor is after `\n`. The previous line may also end with `\n`.
        var searchEnd = cursorIndex
        while searchEnd > text.startIndex {
            let before = text.index(before: searchEnd)
            if text[before] == "\n" {
                searchEnd = before
            } else {
                break
            }
        }

        guard searchEnd > text.startIndex else { return nil }

        // Find the start of the previous line
        let lineStart: String.Index
        if let newlineIndex = text[text.startIndex..<searchEnd].lastIndex(of: "\n") {
            lineStart = text.index(after: newlineIndex)
        } else {
            lineStart = text.startIndex
        }

        return String(text[lineStart..<searchEnd])
    }

    /// Detects a table header pattern: `| col1 | col2 | col3 |`
    /// Only triggers if this is the first row (no separator row already exists).
    private func detectTableHeader(line: String, fullText: String, cursorAt cursorLocation: Int) -> SmartCompletionStructure? {
        // Must start and end with pipe, have at least two pipes total
        guard line.hasPrefix("|"), line.hasSuffix("|") else { return nil }

        let columns = parseTableColumns(from: line)
        guard columns.count >= 2 else { return nil }

        // Check that the next line isn't already a separator row (avoid double-suggesting)
        if let nextLine = extractNextLine(from: fullText, cursorAt: cursorLocation) {
            let trimmedNext = nextLine.trimmingCharacters(in: .whitespaces)
            if trimmedNext.hasPrefix("|") && trimmedNext.contains("---") {
                return nil
            }
        }

        return .tableHeader(columns: columns)
    }

    /// Parses column names from a table header row.
    /// Input: `| Name | Email | Role |` → `["Name", "Email", "Role"]`
    func parseTableColumns(from line: String) -> [String] {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        // Split by pipe, filter empty, trim whitespace
        let parts = stripped.split(separator: "|", omittingEmptySubsequences: false)
        var columns: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                columns.append(trimmed)
            }
        }
        return columns
    }

    /// Extracts the line after the cursor position (if any).
    private func extractNextLine(from text: String, cursorAt cursorLocation: Int) -> String? {
        guard let cursorIndex = text.index(text.startIndex, offsetBy: cursorLocation, limitedBy: text.endIndex) else {
            return nil
        }
        guard cursorIndex < text.endIndex else { return nil }

        let remaining = text[cursorIndex...]
        if let newlineIndex = remaining.firstIndex(of: "\n") {
            return String(remaining[remaining.startIndex..<newlineIndex])
        }
        return String(remaining)
    }

    /// Detects a list item pattern and gathers recent items for context.
    private func detectListItem(line: String, fullText: String, cursorAt cursorLocation: Int) -> SmartCompletionStructure? {
        // Unordered: - item, * item, + item
        // Ordered: 1. item, 2. item, etc.
        let unorderedPattern = try! Regex(#"^(\s*[-*+]\s+).+$"#)
        let orderedPattern = try! Regex(#"^(\s*\d+\.\s+).+$"#)

        let prefix: String
        if let match = line.wholeMatch(of: unorderedPattern) {
            prefix = String(match.output[1].substring ?? "")
        } else if let match = line.wholeMatch(of: orderedPattern) {
            // Normalize ordered prefix to next number
            let trimmedPrefix = String(match.output[1].substring ?? "")
            prefix = trimmedPrefix
        } else {
            return nil
        }

        // Gather recent list items (scan backwards for items with same prefix style)
        let items = gatherRecentListItems(from: fullText, cursorAt: cursorLocation)
        guard !items.isEmpty else { return nil }

        // Only trigger if there are at least 2 items (a pattern to continue)
        guard items.count >= 2 else { return nil }

        return .listItem(prefix: prefix.trimmingCharacters(in: .whitespaces), items: items)
    }

    /// Gathers recent list items by scanning backwards from the cursor.
    private func gatherRecentListItems(from text: String, cursorAt cursorLocation: Int) -> [String] {
        guard let cursorIndex = text.index(text.startIndex, offsetBy: cursorLocation, limitedBy: text.endIndex) else {
            return []
        }

        let textBefore = text[text.startIndex..<cursorIndex]
        let lines = textBefore.split(separator: "\n", omittingEmptySubsequences: false)

        var items: [String] = []
        let listPattern = try! Regex(#"^\s*(?:[-*+]|\d+\.)\s+(.+)$"#)

        // Scan backwards through recent lines
        for line in lines.reversed() {
            let lineStr = String(line)
            if let match = lineStr.wholeMatch(of: listPattern) {
                items.insert(String(match.output[1].substring ?? ""), at: 0)
            } else if lineStr.trimmingCharacters(in: .whitespaces).isEmpty {
                // Empty line breaks the list
                break
            } else {
                // Non-list, non-empty line breaks the scan
                break
            }

            // Limit to 10 recent items for context
            if items.count >= 10 { break }
        }

        return items
    }

    /// Detects if the cursor is inside a YAML front matter block.
    private func detectFrontMatter(fullText: String, cursorAt cursorLocation: Int) -> SmartCompletionStructure? {
        guard let cursorIndex = fullText.index(fullText.startIndex, offsetBy: cursorLocation, limitedBy: fullText.endIndex) else {
            return nil
        }

        let textBefore = String(fullText[fullText.startIndex..<cursorIndex])

        // Front matter must start at the very beginning of the document with ---
        guard textBefore.hasPrefix("---") else { return nil }

        // Check we haven't passed the closing ---
        let lines = textBefore.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return nil }

        // First line must be ---
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        // Check if closing --- appears in the text before cursor (excluding the first line)
        var closingFound = false
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingFound = true
                break
            }
        }

        // If closing --- found, we're past front matter — don't trigger
        if closingFound { return nil }

        // Gather existing keys
        var existingKeys: [String] = []
        let keyPattern = try! Regex(#"^(\w[\w-]*):\s"#)
        for i in 1..<lines.count {
            let lineStr = String(lines[i])
            if let match = lineStr.prefixMatch(of: keyPattern) {
                existingKeys.append(String(match.output[1].substring ?? ""))
            }
        }

        // Need at least 1 existing key to have a pattern to continue
        guard !existingKeys.isEmpty else { return nil }

        return .frontMatter(existingKeys: existingKeys)
    }

    // MARK: - Streaming

    /// Starts streaming smart completion from EMAI.
    private func startStreaming(
        updateStream: AsyncStream<GhostTextUpdate>,
        at cursorPosition: Int
    ) {
        cancelStreaming()

        ghostText = ""
        insertionPoint = cursorPosition
        phase = .streaming

        streamingTask = Task { [weak self] in
            for await update in updateStream {
                guard let self, !Task.isCancelled else { break }

                switch update {
                case .token(let token):
                    self.ghostText += token
                    self.updateGhostTextVisuals()

                case .completed:
                    self.phase = .ready
                    self.announceForVoiceOver()

                case .failed(let error):
                    self.logger.error("Smart completion failed: \(error.localizedDescription)")
                    self.removeGhostTextVisuals()
                    self.textViewDelegate?.requestRerender()
                    self.phase = .inactive
                    self.ghostText = ""
                }
            }
        }
    }

    // MARK: - Accept (Tab)

    /// Accepts the smart completion per AC-2.
    /// Ghost text becomes real document text. Registers a single undo group per [A-022].
    public func accept() {
        guard (phase == .ready || phase == .streaming), !ghostText.isEmpty else { return }
        guard let delegate = textViewDelegate else { return }

        let acceptedText = ghostText
        let position = insertionPoint

        // Step 1: Remove ghost text visuals
        removeGhostTextVisuals()

        // Step 2: Register undo as a single group per [A-022]
        let undoManager = editorState.undoManager
        let acceptedLength = (acceptedText as NSString).length
        let acceptedRange = NSRange(location: position, length: acceptedLength)

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { coordinator in
            guard let delegate = coordinator.textViewDelegate else { return }
            delegate.replaceText(in: acceptedRange, with: "")
            delegate.requestRerender()
        }
        undoManager.endUndoGrouping()

        // Step 3: Insert the ghost text as real text
        let insertRange = NSRange(location: position, length: 0)
        delegate.replaceText(in: insertRange, with: acceptedText)

        // Step 4: Re-render
        delegate.requestRerender()

        phase = .accepted

        // Step 5: Haptic feedback per [A-062]
        #if canImport(UIKit)
        HapticFeedback.trigger(.aiAccepted)
        #endif

        logger.debug("Smart completion accepted: \(acceptedText.count) chars inserted")

        // Reset after brief delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.phase = .inactive
            self?.ghostText = ""
        }
    }

    // MARK: - Dismiss

    /// Dismisses the smart completion.
    /// Called when the user types any character while ghost text is displayed.
    public func dismiss() {
        cancelStreaming()

        if phase == .streaming || phase == .ready {
            removeGhostTextVisuals()
            textViewDelegate?.requestRerender()
        }

        phase = .dismissed
        ghostText = ""

        logger.debug("Smart completion dismissed")

        // Reset after brief delay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self?.phase = .inactive
        }
    }

    /// Cancels the current smart completion session.
    public func cancel() {
        cancelStreaming()

        if phase == .streaming || phase == .ready {
            removeGhostTextVisuals()
            textViewDelegate?.requestRerender()
        }

        phase = .inactive
        ghostText = ""
    }

    // MARK: - Private

    private func cancelStreaming() {
        streamingTask?.cancel()
        streamingTask = nil
    }

    private func updateGhostTextVisuals() {
        guard let delegate = textViewDelegate,
              let storage = delegate.textStorage() else { return }

        storage.beginEditing()
        GhostTextRenderer.updateGhostText(
            in: storage,
            at: insertionPoint,
            ghostText: ghostText,
            baseFont: delegate.baseFont()
        )
        storage.endEditing()
    }

    private func removeGhostTextVisuals() {
        guard let storage = textViewDelegate?.textStorage() else { return }

        storage.beginEditing()
        GhostTextRenderer.removeGhostText(from: storage)
        storage.endEditing()
    }

    /// Announces smart completion availability for VoiceOver.
    private func announceForVoiceOver() {
        #if canImport(UIKit)
        UIAccessibility.post(
            notification: .announcement,
            argument: NSLocalizedString(
                "AI suggestion available. Press Tab to accept.",
                comment: "VoiceOver announcement when smart completion appears per FEAT-025"
            )
        )
        #elseif canImport(AppKit)
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: NSLocalizedString(
                    "AI suggestion available. Press Tab to accept.",
                    comment: "VoiceOver announcement when smart completion appears per FEAT-025"
                ),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        #endif
    }
}
