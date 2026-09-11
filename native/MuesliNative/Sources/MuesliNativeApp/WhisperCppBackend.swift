import Foundation
import WhisperKit
import MuesliCore

/// Native Swift transcription backend using WhisperKit (CoreML on ANE/GPU).
actor WhisperKitTranscriber {
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    enum TranscriberError: Error, LocalizedError {
        case notLoaded
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "WhisperKit model not loaded."
            case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
            }
        }
    }

    /// Load a WhisperKit CoreML model. Downloads from HuggingFace if not cached.
    func loadModel(
        modelName: String,
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws {
        if loadedModel == modelName, whisperKit != nil { return }

        fputs("[whisperkit] loading model: \(modelName)...\n", stderr)
        let plan = ManagedASRModelPlans.whisperKit(modelName: modelName)
        let loadedWhisperKit = try await ManagedASRModelDownloader.loadValidated(
            plan,
            progress: progress,
            progressSnapshot: progressSnapshot
        ) { modelFolder in
            let preparing = ModelDownloadProgress.preparing(
                modelID: plan.modelID,
                message: "Loading WhisperKit into Core ML..."
            )
            progress?(0.95, preparing.message)
            progressSnapshot?(preparing)

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
            )
            return try await WhisperKit(config)
        }

        whisperKit = loadedWhisperKit
        loadedModel = modelName
        fputs("[whisperkit] model loaded: \(modelName)\n", stderr)
    }

    /// Transcribe a 16kHz mono WAV file.
    /// - Parameter language: `.auto` enables WhisperKit language detection; otherwise pins that ISO code.
    ///   Ignored for English-only `.en` models, which keep default English decoding.
    /// - Parameter vocabularyHint: spellings to lean toward (see `WhisperVocabularyHint`).
    func transcribe(
        wavURL: URL,
        language: WhisperKitLanguage = .defaultLanguage,
        vocabularyHint: String? = nil
    ) async throws -> (text: String, processingTime: Double) {
        guard let whisperKit else { throw TranscriberError.notLoaded }
        guard let loadedModel else { throw TranscriberError.notLoaded }

        let start = CFAbsoluteTimeGetCurrent()
        let decodeOptions = decodeOptions(language: language, modelName: loadedModel, vocabularyHint: vocabularyHint)
        let results = try await whisperKit.transcribe(audioPath: wavURL.path, decodeOptions: decodeOptions)
        return (text: Self.assembleText(results), processingTime: CFAbsoluteTimeGetCurrent() - start)
    }

    /// Transcribe 16kHz mono samples that have already been cut down to speech
    /// (see `SpeechRegionTrimmer`), so Whisper never decodes a silent window.
    func transcribe(
        samples: [Float],
        language: WhisperKitLanguage = .defaultLanguage,
        vocabularyHint: String? = nil
    ) async throws -> (text: String, processingTime: Double) {
        guard let whisperKit else { throw TranscriberError.notLoaded }
        guard let loadedModel else { throw TranscriberError.notLoaded }

        let start = CFAbsoluteTimeGetCurrent()
        let decodeOptions = decodeOptions(language: language, modelName: loadedModel, vocabularyHint: vocabularyHint)
        let results = try await whisperKit.transcribe(audioArray: samples, decodeOptions: decodeOptions)
        return (text: Self.assembleText(results), processingTime: CFAbsoluteTimeGetCurrent() - start)
    }

    /// Join Whisper's windows and drop the stock sentences it emits for silence.
    static func assembleText(_ results: [TranscriptionResult]) -> String {
        let joined = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WhisperSilenceHallucinationFilter.apply(joined)
    }

    /// Decode options plus the dictionary hint. Whisper reads the hint as the
    /// text spoken just before the recording, so it favours those spellings.
    private func decodeOptions(
        language: WhisperKitLanguage,
        modelName: String,
        vocabularyHint: String?
    ) -> DecodingOptions {
        var options = Self.makeDecodeOptions(language: language, modelName: modelName)
        guard let vocabularyHint, let tokenizer = whisperKit?.tokenizer else { return options }
        let tokens = tokenizer.encode(text: " " + vocabularyHint)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        if !tokens.isEmpty {
            options.promptTokens = tokens
        }
        return options
    }

    /// Build WhisperKit decode options for the loaded model.
    /// English-only checkpoints ignore language preference and keep default English decoding.
    static func makeDecodeOptions(
        language: WhisperKitLanguage,
        modelName: String
    ) -> DecodingOptions {
        guard let effective = WhisperKitLanguage.preferenceForLoadedModel(language, modelName: modelName) else {
            return DecodingOptions()
        }
        switch effective {
        case .auto:
            // Default DecodingOptions leaves detectLanguage false when usePrefillPrompt is true,
            // which silently forces English. Request detection explicitly for multilingual models.
            return DecodingOptions(detectLanguage: true)
        default:
            return DecodingOptions(language: effective.rawValue)
        }
    }

    /// Run a short silent transcription to trigger CoreML compilation.
    /// First-run compilation takes 10-30s; subsequent loads are instant.
    func warmup() async throws {
        guard let whisperKit else { return }
        let silence = [Float](repeating: 0, count: 16000) // 1 second of silence at 16kHz
        let start = CFAbsoluteTimeGetCurrent()
        let _: [TranscriptionResult] = try await whisperKit.transcribe(audioArray: silence)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        fputs("[whisperkit] warmup transcription took \(String(format: "%.1f", elapsed))s\n", stderr)
    }

    func shutdown() {
        whisperKit = nil
        loadedModel = nil
    }

    // MARK: - Model Storage

    /// WhisperKit stores models under ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/.
    /// Each model variant is a direct subdirectory (e.g. openai_whisper-small/).
    static func isModelDownloaded(_ modelName: String) -> Bool {
        ManagedASRModelPlans.whisperKit(modelName: modelName).isAvailableLocally()
    }

    /// Delete cached model files for a WhisperKit model variant.
    static func deleteModel(_ modelName: String) {
        try? ManagedASRModelPlans.whisperKit(modelName: modelName).delete()
    }
}
