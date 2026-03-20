import SwiftUI
import EMEditor

/// Bottom status bar showing word count, reading time, and expandable document stats
/// per FEAT-012 and [A-055].
///
/// Compact mode: word count + reading time (always visible).
/// Expanded mode (tap): paragraph count, sentence count, Flesch-Kincaid readability.
/// Selection-aware: shows selection word count alongside total when text is selected.
struct StatusBar: View {
    let stats: DocumentStats
    let selectionWordCount: Int?
    let diagnosticCount: Int

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                Divider()
            }
            compactContent
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Compact Row

    private var compactContent: some View {
        HStack {
            Button(action: { isExpanded.toggle() }) {
                HStack(spacing: 12) {
                    Text(wordCountLabel)
                    Text(readingTimeLabel)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compactAccessibilityLabel)
            .accessibilityHint(isExpanded
                ? "Tap to hide detailed statistics"
                : "Tap to show detailed statistics")

            Spacer()

            if diagnosticCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "stethoscope")
                        .imageScale(.small)
                    Text("\(diagnosticCount)")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(diagnosticAccessibilityLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Expanded Row

    private var expandedContent: some View {
        HStack(spacing: 16) {
            statItem(
                label: "Paragraphs",
                value: "\(stats.paragraphCount)"
            )
            statItem(
                label: "Sentences",
                value: "\(stats.sentenceCount)"
            )
            statItem(
                label: "Characters",
                value: "\(stats.characterCount)"
            )
            statItem(
                label: "No spaces",
                value: "\(stats.characterCountNoSpaces)"
            )
            if let grade = stats.fleschKincaidGradeLevel {
                statItem(
                    label: "Readability",
                    value: readabilityLabel(grade: grade)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: - Labels

    private var wordCountLabel: String {
        if let selection = selectionWordCount {
            return "\(selection)/\(stats.wordCount) \(stats.wordCount == 1 ? "word" : "words")"
        }
        return "\(stats.wordCount) \(stats.wordCount == 1 ? "word" : "words")"
    }

    private var readingTimeLabel: String {
        let seconds = stats.readingTimeSeconds
        if seconds < 60 {
            return "< 1 min read"
        }
        let minutes = seconds / 60
        return "\(minutes) min read"
    }

    private func readabilityLabel(grade: Double) -> String {
        if grade < 0 {
            return "Pre-K"
        } else if grade > 18 {
            return "18+"
        }
        return String(format: "%.1f", grade)
    }

    // MARK: - Accessibility

    private var compactAccessibilityLabel: String {
        var parts: [String] = []

        if let selection = selectionWordCount {
            parts.append("\(selection) of \(stats.wordCount) words selected")
        } else {
            parts.append("\(stats.wordCount) \(stats.wordCount == 1 ? "word" : "words")")
        }

        parts.append(readingTimeLabel)

        return parts.joined(separator: ", ")
    }

    private var diagnosticAccessibilityLabel: String {
        "\(diagnosticCount) document \(diagnosticCount == 1 ? "issue" : "issues")"
    }
}
