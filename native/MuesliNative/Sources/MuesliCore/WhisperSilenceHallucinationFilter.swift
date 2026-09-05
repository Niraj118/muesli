import Foundation

/// Drops the stock sentences Whisper produces when it is decoding silence.
///
/// Whisper was trained on captioned video, where silence at the end is usually
/// captioned "Thank you." or "Thanks for watching." The model reproduces those
/// captions when a window has nothing to transcribe. Speech-only audio (see
/// `SpeechRegionTrimmer`) removes most of them at source; this is the backstop
/// for the ones that still slip through at the edges of a recording.
///
/// Only a whole sentence that is the entire output, opens it, or closes it is
/// removed. A phrase inside a sentence ("Thank you for the update.") or one
/// following a comma ("Send it to Darren, thank you.") is left alone, because
/// that is how a person actually dictates it.
public enum WhisperSilenceHallucinationFilter {

    /// Sentences documented as Whisper's output on silent audio. Compared
    /// case-insensitively; internal spaces match any run of whitespace.
    static let phrases: [String] = [
        "thank you",
        "thank you very much",
        "thank you so much",
        "thanks",
        "thank you for watching",
        "thanks for watching",
        "thank you so much for watching",
        "thank you for listening",
        "thanks for listening",
        "subtitles by the amara.org community",
        "subtitles by amara.org",
    ]

    private static let alternation: String = phrases
        .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#) }
        .joined(separator: "|")

    /// Whole output is one of the phrases, with or without punctuation.
    private static let wholePattern = #"(?i)^\s*(?:"# + alternation + #")[.!?]*\s*$"#
    /// Phrase opens the output as its own sentence.
    private static let leadingPattern = #"(?i)^\s*(?:"# + alternation + #")[.!?]+\s+"#
    /// Phrase closes the output as its own sentence, after a sentence ending.
    private static let trailingPattern = #"(?i)(?<=[.!?])\s+(?:"# + alternation + #")[.!?]*\s*$"#

    public static func apply(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        if result.range(of: wholePattern, options: .regularExpression) != nil {
            return ""
        }

        var changed = true
        while changed {
            changed = false
            for pattern in [leadingPattern, trailingPattern] {
                let stripped = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                if stripped != result {
                    result = stripped
                    changed = true
                }
            }
            if result.range(of: wholePattern, options: .regularExpression) != nil {
                return ""
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
