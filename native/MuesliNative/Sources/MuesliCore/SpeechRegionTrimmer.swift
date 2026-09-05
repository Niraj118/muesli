import Foundation

/// Cuts a recording down to the stretches where someone is actually speaking.
///
/// Whisper-family models invent text such as "Thank you." whenever a decoding
/// window is mostly silence: a pause before the first word, a long think in the
/// middle, or the tail after the last word. Handing the model speech-only audio
/// removes the silence it hallucinates over. Short pauses are kept as recorded
/// so phrasing survives; long ones are replaced with a fixed short gap so
/// sentences stay apart without giving the model a silent window.
///
/// Pure sample arithmetic: the caller supplies per-chunk speech probabilities
/// from whatever voice-activity detector it uses.
public enum SpeechRegionTrimmer {

    public struct Configuration: Sendable, Equatable {
        /// Chunk probability at or above which a chunk counts as speech.
        public var speechThreshold: Float
        /// Audio kept before and after each speech region so soft onsets and tails survive.
        public var padding: TimeInterval
        /// Gaps up to this length are kept exactly as recorded.
        public var maximumPreservedGap: TimeInterval
        /// Silence inserted in place of a gap longer than `maximumPreservedGap`.
        public var collapsedGap: TimeInterval

        public init(
            speechThreshold: Float,
            padding: TimeInterval,
            maximumPreservedGap: TimeInterval,
            collapsedGap: TimeInterval
        ) {
            self.speechThreshold = speechThreshold
            self.padding = padding
            self.maximumPreservedGap = maximumPreservedGap
            self.collapsedGap = collapsedGap
        }

        public static let `default` = Configuration(
            speechThreshold: 0.5,
            padding: 0.35,
            maximumPreservedGap: 1.0,
            collapsedGap: 0.6
        )
    }

    /// A half-open sample range `[start, end)` that contains speech.
    public struct Region: Sendable, Equatable {
        public let start: Int
        public let end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    public struct Result: Sendable, Equatable {
        /// Speech-only audio, or `nil` when no chunk reached the speech threshold.
        public let samples: [Float]?
        public let regions: [Region]
        /// How much of the recording was silence that no longer reaches the model.
        public let removedDuration: TimeInterval
    }

    /// Work out where speech is, from one probability per fixed-size chunk.
    ///
    /// Chunk `i` covers samples `[i * chunkSize, (i + 1) * chunkSize)`, clamped to
    /// `sampleCount`. Regions are padded, then any two closer than
    /// `maximumPreservedGap` are merged so the recorded pause between them is kept.
    public static func speechRegions(
        chunkProbabilities: [Float],
        chunkSize: Int,
        sampleCount: Int,
        sampleRate: Int,
        configuration: Configuration = .default
    ) -> [Region] {
        guard chunkSize > 0, sampleCount > 0, sampleRate > 0 else { return [] }

        let padding = Int(configuration.padding * Double(sampleRate))
        let preservedGap = Int(configuration.maximumPreservedGap * Double(sampleRate))

        var regions: [Region] = []
        for (index, probability) in chunkProbabilities.enumerated() where probability >= configuration.speechThreshold {
            let start = max(0, index * chunkSize - padding)
            let end = min(sampleCount, (index + 1) * chunkSize + padding)
            guard start < end else { continue }
            if let last = regions.last, start - last.end <= preservedGap {
                regions[regions.count - 1] = Region(start: last.start, end: max(last.end, end))
            } else {
                regions.append(Region(start: start, end: end))
            }
        }
        return regions
    }

    /// Keep only the speech regions of `samples`, separated by a short fixed gap.
    public static func trim(
        samples: [Float],
        chunkProbabilities: [Float],
        chunkSize: Int,
        sampleRate: Int,
        configuration: Configuration = .default
    ) -> Result {
        let regions = speechRegions(
            chunkProbabilities: chunkProbabilities,
            chunkSize: chunkSize,
            sampleCount: samples.count,
            sampleRate: sampleRate,
            configuration: configuration
        )
        guard !regions.isEmpty else {
            return Result(
                samples: nil,
                regions: [],
                removedDuration: Double(samples.count) / Double(max(sampleRate, 1))
            )
        }

        let gap = [Float](repeating: 0, count: Int(configuration.collapsedGap * Double(sampleRate)))
        var trimmed: [Float] = []
        trimmed.reserveCapacity(regions.reduce(0) { $0 + ($1.end - $1.start) } + gap.count * regions.count)
        for (index, region) in regions.enumerated() {
            if index > 0 { trimmed.append(contentsOf: gap) }
            trimmed.append(contentsOf: samples[region.start..<region.end])
        }

        let kept = regions.reduce(0) { $0 + ($1.end - $1.start) }
        return Result(
            samples: trimmed,
            regions: regions,
            removedDuration: Double(samples.count - kept) / Double(max(sampleRate, 1))
        )
    }
}
