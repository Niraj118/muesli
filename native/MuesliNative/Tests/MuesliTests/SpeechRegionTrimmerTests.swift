import Testing
import Foundation
import MuesliCore

@Suite("SpeechRegionTrimmer")
struct SpeechRegionTrimmerTests {
    private let rate = 16000
    private let chunk = 4096 // 256ms, FluidAudio's VAD chunk

    private func samples(chunks: Int, value: Float = 1) -> [Float] {
        [Float](repeating: value, count: chunks * chunk)
    }

    @Test("silence-only audio yields no speech")
    func silentAudio() {
        let result = SpeechRegionTrimmer.trim(
            samples: samples(chunks: 30),
            chunkProbabilities: [Float](repeating: 0.1, count: 30),
            chunkSize: chunk,
            sampleRate: rate
        )
        #expect(result.samples == nil)
        #expect(result.regions.isEmpty)
        #expect(abs(result.removedDuration - 30 * 0.256) < 0.001)
    }

    @Test("leading and trailing silence are cut, speech is padded")
    func leadingTrailingSilence() {
        // 10 silent chunks, 4 speech, 10 silent.
        var probabilities = [Float](repeating: 0, count: 24)
        for index in 10..<14 { probabilities[index] = 0.9 }
        let regions = SpeechRegionTrimmer.speechRegions(
            chunkProbabilities: probabilities,
            chunkSize: chunk,
            sampleCount: 24 * chunk,
            sampleRate: rate
        )
        let padding = Int(0.35 * Double(rate))
        #expect(regions == [.init(start: 10 * chunk - padding, end: 14 * chunk + padding)])

        let result = SpeechRegionTrimmer.trim(
            samples: samples(chunks: 24),
            chunkProbabilities: probabilities,
            chunkSize: chunk,
            sampleRate: rate
        )
        #expect(result.samples?.count == 4 * chunk + 2 * padding)
    }

    @Test("a short pause is kept as recorded")
    func shortPausePreserved() {
        // speech, 3 silent chunks (768ms), speech: below the 1s preserved-gap limit.
        let probabilities: [Float] = [0.9, 0.9, 0, 0, 0, 0.9, 0.9]
        let regions = SpeechRegionTrimmer.speechRegions(
            chunkProbabilities: probabilities,
            chunkSize: chunk,
            sampleCount: 7 * chunk,
            sampleRate: rate
        )
        #expect(regions.count == 1)
        #expect(regions.first?.start == 0)
        #expect(regions.first?.end == 7 * chunk)
    }

    @Test("a long pause is collapsed to the fixed gap")
    func longPauseCollapsed() {
        // speech, 20 silent chunks (5.1s), speech.
        var probabilities = [Float](repeating: 0, count: 24)
        probabilities[0] = 0.9
        probabilities[1] = 0.9
        probabilities[22] = 0.9
        probabilities[23] = 0.9
        let result = SpeechRegionTrimmer.trim(
            samples: samples(chunks: 24),
            chunkProbabilities: probabilities,
            chunkSize: chunk,
            sampleRate: rate
        )
        let padding = Int(0.35 * Double(rate))
        let gap = Int(0.6 * Double(rate))
        #expect(result.regions.count == 2)
        #expect(result.samples?.count == (2 * chunk + padding) * 2 + gap)
        // The inserted gap is silent; the kept audio is not.
        let firstRegionLength = 2 * chunk + padding
        let gapSlice = result.samples?[firstRegionLength..<(firstRegionLength + gap)] ?? []
        #expect(gapSlice.allSatisfy { $0 == 0 })
    }

    @Test("padding never runs past the ends of the recording")
    func paddingClamped() {
        let regions = SpeechRegionTrimmer.speechRegions(
            chunkProbabilities: [0.9, 0.9],
            chunkSize: chunk,
            sampleCount: 2 * chunk,
            sampleRate: rate
        )
        #expect(regions == [.init(start: 0, end: 2 * chunk)])
    }

    @Test("a final partial chunk is clamped to the sample count")
    func partialLastChunk() {
        let sampleCount = 2 * chunk + 100
        let regions = SpeechRegionTrimmer.speechRegions(
            chunkProbabilities: [0, 0, 0.9],
            chunkSize: chunk,
            sampleCount: sampleCount,
            sampleRate: rate
        )
        #expect(regions.last?.end == sampleCount)
    }

    @Test("threshold is inclusive and configurable")
    func thresholdConfigurable() {
        var configuration = SpeechRegionTrimmer.Configuration.default
        configuration.speechThreshold = 0.7
        let regions = SpeechRegionTrimmer.speechRegions(
            chunkProbabilities: [0.69, 0.7],
            chunkSize: chunk,
            sampleCount: 2 * chunk,
            sampleRate: rate,
            configuration: configuration
        )
        let padding = Int(0.35 * Double(rate))
        #expect(regions == [.init(start: chunk - padding, end: 2 * chunk)])
    }

    @Test("degenerate inputs produce nothing")
    func degenerateInputs() {
        #expect(SpeechRegionTrimmer.speechRegions(chunkProbabilities: [], chunkSize: chunk, sampleCount: 0, sampleRate: rate).isEmpty)
        #expect(SpeechRegionTrimmer.speechRegions(chunkProbabilities: [0.9], chunkSize: 0, sampleCount: 10, sampleRate: rate).isEmpty)
        let empty = SpeechRegionTrimmer.trim(samples: [], chunkProbabilities: [], chunkSize: chunk, sampleRate: rate)
        #expect(empty.samples == nil)
    }
}
