import Testing
import Foundation
@testable import MuesliCore
@testable import MuesliNativeApp

@Suite
struct Qwen3VendorTests {

    @available(macOS 15, *)
    @Test("default int8 cache directory matches the managed plan's install directory")
    func defaultCacheMatchesManagedPlan() {
        let plan = ManagedASRModelPlans.qwen3ASRInt8()
        let cache = MuesliQwen3AsrModels.defaultCacheDirectory(variant: .int8)
        #expect(cache.standardizedFileURL == plan.cacheDirectory.standardizedFileURL)
    }

    @available(macOS 15, *)
    @Test("qwen3ASRInt8(cacheDirectory:) honors an explicit install directory")
    func explicitCacheDirectoryIsHonored() {
        let custom = URL(fileURLWithPath: "/tmp/qwen3-custom-install")
        let plan = ManagedASRModelPlans.qwen3ASRInt8(cacheDirectory: custom)
        #expect(plan.cacheDirectory == custom)
        #expect(plan.modelID == "FluidInference/qwen3-asr-0.6b-coreml")
    }
}

@Suite
struct Qwen3LanguageTests {

    @Test("Language init parses ISO codes and English names")
    func languageInitParsesCodesAndNames() {
        #expect(MuesliQwen3AsrConfig.Language(from: "en") == .english)
        #expect(MuesliQwen3AsrConfig.Language(from: "English") == .english)
        #expect(MuesliQwen3AsrConfig.Language(from: "ENGLISH") == .english)
        #expect(MuesliQwen3AsrConfig.Language(from: "hi") == .hindi)
    }

    @Test("Language init rejects unknown input")
    func languageInitRejectsUnknownInput() {
        #expect(MuesliQwen3AsrConfig.Language(from: "eng") == nil)
        #expect(MuesliQwen3AsrConfig.Language(from: "") == nil)
        #expect(MuesliQwen3AsrConfig.Language(from: "chinese (simplified)") == nil)
    }
}

@Suite
struct Qwen3AudioSegmenterTests {

    private func tone(seconds: Double, level: Float = 0.5) -> [Float] {
        [Float](repeating: level, count: Int(seconds * 16000))
    }

    @Test("audio inside the window is left whole")
    func shortAudioUntouched() {
        let samples = tone(seconds: 10)
        let segments = MuesliQwen3AudioSegmenter.segments(samples)
        #expect(segments.count == 1)
        #expect(segments[0].count == samples.count)
    }

    @Test("empty audio yields no segments")
    func emptyAudio() {
        #expect(MuesliQwen3AudioSegmenter.segments([]).isEmpty)
    }

    @Test("long audio is split into acceptable pieces that lose nothing")
    func longAudioSplit() {
        let samples = tone(seconds: 95)
        let segments = MuesliQwen3AudioSegmenter.segments(samples)
        #expect(segments.count >= 4)
        for segment in segments {
            #expect(segment.count <= Int(MuesliQwen3AudioSegmenter.usableSeconds * 16000))
            #expect(!segment.isEmpty)
        }
        // Every sample survives exactly once: no gaps, no duplication.
        #expect(segments.reduce(0) { $0 + $1.count } == samples.count)
    }

    @Test("cuts prefer a silent gap over the hard boundary")
    func cutsFallInSilence() {
        // Loud up to 18s, silent for a second, loud again: the cut belongs in the gap.
        var samples = tone(seconds: 18)
        samples += [Float](repeating: 0, count: 16000)
        samples += tone(seconds: 12)

        let segments = MuesliQwen3AudioSegmenter.segments(samples)
        #expect(segments.count == 2)
        let cut = segments[0].count
        #expect(cut > 18 * 16000)
        #expect(cut < 19 * 16000)
    }

    @Test("audio stays under the model's own hard ceiling")
    func usableWindowLeavesRoomForText() {
        #expect(MuesliQwen3AudioSegmenter.usableSeconds < MuesliQwen3AsrConfig.maxAudioSeconds)
    }
}

@Suite
struct Qwen3LanguageSelectionTests {

    @available(macOS 15, *)
    @Test("Qwen3AsrLanguage resolves auto and pinned languages")
    func resolvesAutoAndPinned() {
        #expect(Qwen3AsrLanguage.resolved("auto") == .auto)
        #expect(Qwen3AsrLanguage.resolved("AUTO") == .auto)
        #expect(Qwen3AsrLanguage.resolved("en") == .pinned(.english))
        #expect(Qwen3AsrLanguage.resolved("English") == .pinned(.english))
    }

    /// Nothing may resolve to `auto` by accident: an empty language instruction
    /// lets Qwen3-ASR answer in Chinese when the speaker is talking English.
    @available(macOS 15, *)
    @Test("Qwen3AsrLanguage falls back to a real language, never auto")
    func fallsBackToSystemLanguage() {
        #expect(Qwen3AsrLanguage.resolved(nil) == Qwen3AsrLanguage.systemLanguage)
        #expect(Qwen3AsrLanguage.resolved("") == Qwen3AsrLanguage.systemLanguage)
        #expect(Qwen3AsrLanguage.resolved("bogus") == Qwen3AsrLanguage.systemLanguage)
        #expect(Qwen3AsrLanguage.systemLanguage != .auto)
        #expect(Qwen3AsrLanguage.systemLanguage.pinnedCode != nil)
        #expect(Qwen3AsrLanguage.defaultLanguage == Qwen3AsrLanguage.systemLanguage)
    }

    @available(macOS 15, *)
    @Test("Qwen3AsrLanguage exposes codes and labels")
    func exposesCodesAndLabels() {
        #expect(Qwen3AsrLanguage.auto.pinnedCode == nil)
        #expect(Qwen3AsrLanguage.auto.rawValue == "auto")
        #expect(Qwen3AsrLanguage.auto.label == "Auto-detect")
        #expect(Qwen3AsrLanguage.pinned(.english).pinnedCode == "en")
        #expect(Qwen3AsrLanguage.pinned(.english).label == "English")
        #expect(Qwen3AsrLanguage.allCases.count == MuesliQwen3AsrConfig.Language.allCases.count + 1)
    }

    @available(macOS 15, *)
    @Test("Qwen3AsrLanguage selection survives config encode/decode round-trip")
    func persistenceRoundTrip() throws {
        let selection = Qwen3AsrLanguage.pinned(.english)
        var config = AppConfig()
        config.qwen3AsrLanguage = selection.rawValue

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        #expect(decoded.resolvedQwen3AsrLanguage == .pinned(.english))
    }
}
