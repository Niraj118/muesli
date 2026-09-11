import Foundation

/// Turns the user's dictionary into the short text Whisper is shown before it
/// listens. Whisper treats that text as what was said just before the
/// recording, so it leans toward those spellings when a sound is ambiguous
/// (an acronym such as "ENG" that would otherwise come out as "and").
///
/// The dictionary's fuzzy replacement still runs afterwards; this only nudges
/// the model up front. The list is kept short because a long prompt makes
/// Whisper repeat itself.
public enum WhisperVocabularyHint {
    /// Whisper's prompt window holds roughly 220 tokens; this keeps well clear of it.
    public static let maximumWords = 40

    /// The correct spellings to hint, or `nil` when the dictionary has none.
    public static func text(for words: [CustomWord]) -> String? {
        var seen = Set<String>()
        var picked: [String] = []
        for entry in words {
            let target = entry.targetWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !target.isEmpty, seen.insert(target.lowercased()).inserted else { continue }
            picked.append(target)
            if picked.count == maximumWords { break }
        }
        guard !picked.isEmpty else { return nil }
        return picked.joined(separator: ", ") + "."
    }
}
