import Foundation

/// Splits audio into pieces Qwen3-ASR can actually accept.
///
/// The converted CoreML decoder has a fixed 512-slot attention cache, and audio
/// costs roughly 13 slots a second, so the model refuses anything past ~30
/// seconds. That ceiling cannot be raised from here, so longer recordings are
/// transcribed piece by piece and the text joined back together.
public enum MuesliQwen3AudioSegmenter {

    /// Usable audio per pass, well under the model's own ~30s ceiling.
    ///
    /// The 512-slot cache holds the audio *and* the words being written. Audio
    /// costs ~13 slots a second, so a full 30s pass leaves too few slots for the
    /// transcript and the decoder stops mid-sentence, silently losing the tail.
    /// 20s leaves comfortable room even for fast, dense speech.
    public static let usableSeconds: Double = 20.0

    /// How far back from a hard boundary to hunt for a gap between words.
    private static let searchSeconds: Double = 4.0
    /// Granularity of the quiet-point search.
    private static let frameSeconds: Double = 0.05

    /// Segments `samples` into runs no longer than `maxSeconds`.
    ///
    /// Cuts land at the quietest point near each boundary rather than exactly on
    /// it, so a word is far less likely to be sliced in half and lost from both
    /// sides. Audio already short enough comes back as a single segment.
    public static func segments(
        _ samples: [Float],
        maxSeconds: Double = usableSeconds,
        sampleRate: Int = MuesliQwen3AsrConfig.sampleRate
    ) -> [[Float]] {
        let maxSamples = Int(maxSeconds * Double(sampleRate))
        guard maxSamples > 0, samples.count > maxSamples else {
            return samples.isEmpty ? [] : [samples]
        }

        var segments: [[Float]] = []
        var start = 0

        while start < samples.count {
            let remaining = samples.count - start
            if remaining <= maxSamples {
                segments.append(Array(samples[start...]))
                break
            }
            let hardEnd = start + maxSamples
            let cut = quietestCut(
                in: samples,
                segmentStart: start,
                hardEnd: hardEnd,
                sampleRate: sampleRate
            )
            segments.append(Array(samples[start..<cut]))
            start = cut
        }

        return segments
    }

    /// Finds the lowest-energy frame in the last `searchSeconds` before the hard
    /// boundary. Falls back to the boundary itself when the window is unusable.
    private static func quietestCut(
        in samples: [Float],
        segmentStart: Int,
        hardEnd: Int,
        sampleRate: Int
    ) -> Int {
        let frame = max(1, Int(frameSeconds * Double(sampleRate)))
        let searchSamples = Int(searchSeconds * Double(sampleRate))
        let searchStart = max(segmentStart + frame, hardEnd - searchSamples)
        guard searchStart + frame <= hardEnd else { return hardEnd }

        var bestCut = hardEnd
        var bestEnergy = Float.greatestFiniteMagnitude
        var offset = searchStart

        while offset + frame <= hardEnd {
            var energy: Float = 0
            for i in offset..<(offset + frame) {
                energy += abs(samples[i])
            }
            // `<` keeps the earliest of equally quiet frames; ties in true silence
            // then cut at the start of the gap rather than the end of it.
            if energy < bestEnergy {
                bestEnergy = energy
                bestCut = offset + frame / 2
            }
            offset += frame
        }

        return bestCut
    }
}
