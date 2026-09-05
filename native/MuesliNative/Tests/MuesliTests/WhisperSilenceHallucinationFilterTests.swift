import Testing
import Foundation
import MuesliCore

@Suite("WhisperSilenceHallucinationFilter")
struct WhisperSilenceHallucinationFilterTests {

    @Test("silence-only output becomes empty")
    func wholeOutput() {
        #expect(WhisperSilenceHallucinationFilter.apply("Thank you.") == "")
        #expect(WhisperSilenceHallucinationFilter.apply("  thank you ") == "")
        #expect(WhisperSilenceHallucinationFilter.apply("Thanks for watching!") == "")
        #expect(WhisperSilenceHallucinationFilter.apply("Subtitles by the Amara.org community") == "")
    }

    @Test("a stock sentence opening the output is removed")
    func leadingSentence() {
        #expect(
            WhisperSilenceHallucinationFilter.apply("Thank you. For the remaining items, you need to give me more context.")
                == "For the remaining items, you need to give me more context."
        )
    }

    @Test("a stock sentence closing the output is removed")
    func trailingSentence() {
        #expect(
            WhisperSilenceHallucinationFilter.apply("When does the system rescore old reports? Thank you.")
                == "When does the system rescore old reports?"
        )
    }

    @Test("repeated stock sentences at either end are all removed")
    func repeatedSentences() {
        #expect(
            WhisperSilenceHallucinationFilter.apply("Thank you. Thank you. Why aren't we merging them? Thank you. Thanks for watching.")
                == "Why aren't we merging them?"
        )
    }

    @Test("a stock sentence in the middle of the output is kept")
    func middleSentenceKept() {
        let text = "For one yes do that. Thank you. Now for number two, are those phrases for Darren only?"
        #expect(WhisperSilenceHallucinationFilter.apply(text) == text)
    }

    @Test("thank you inside a sentence is kept")
    func insideSentenceKept() {
        #expect(WhisperSilenceHallucinationFilter.apply("Thank you for the update.") == "Thank you for the update.")
        #expect(WhisperSilenceHallucinationFilter.apply("Thank you for the update, Darren.") == "Thank you for the update, Darren.")
    }

    @Test("thank you after a comma is kept")
    func afterCommaKept() {
        #expect(WhisperSilenceHallucinationFilter.apply("Send it to Darren, thank you.") == "Send it to Darren, thank you.")
    }

    @Test("a leading phrase without sentence punctuation is kept")
    func leadingWithoutPunctuationKept() {
        #expect(WhisperSilenceHallucinationFilter.apply("Thanks that looks right to me") == "Thanks that looks right to me")
    }

    @Test("ordinary text and empty input pass through")
    func passThrough() {
        #expect(WhisperSilenceHallucinationFilter.apply("Hello world.") == "Hello world.")
        #expect(WhisperSilenceHallucinationFilter.apply("") == "")
        #expect(WhisperSilenceHallucinationFilter.apply("   ") == "")
    }
}
