import Testing
@testable import MuesliCore

@Suite("WhisperVocabularyHint")
struct WhisperVocabularyHintTests {
    @Test("hints the correct spelling of every dictionary entry")
    func hintsCorrectSpellings() {
        let words = [
            CustomWord(word: "ENG", replacement: nil),
            CustomWord(word: "clod", replacement: "Claude"),
            CustomWord(word: "muesli", replacement: "muesli"),
        ]
        #expect(WhisperVocabularyHint.text(for: words) == "ENG, Claude, muesli.")
    }

    @Test("drops duplicates and blank entries")
    func dropsDuplicatesAndBlanks() {
        let words = [
            CustomWord(word: "ENG", replacement: nil),
            CustomWord(word: "eng", replacement: nil),
            CustomWord(word: "   ", replacement: nil),
            CustomWord(word: "x", replacement: "ENG"),
        ]
        #expect(WhisperVocabularyHint.text(for: words) == "ENG.")
    }

    @Test("an empty dictionary gives no hint")
    func emptyDictionaryGivesNoHint() {
        #expect(WhisperVocabularyHint.text(for: []) == nil)
        #expect(WhisperVocabularyHint.text(for: [CustomWord(word: " ", replacement: nil)]) == nil)
    }

    @Test("keeps the hint short")
    func keepsTheHintShort() {
        let words = (0..<100).map { CustomWord(word: "word\($0)", replacement: nil) }
        let hint = WhisperVocabularyHint.text(for: words) ?? ""
        #expect(hint.split(separator: ",").count == WhisperVocabularyHint.maximumWords)
        #expect(hint.hasPrefix("word0, word1,"))
    }
}
