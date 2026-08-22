import Foundation

/// The language Qwen3-ASR is told to transcribe into when nobody has chosen one.
///
/// Qwen3-ASR only receives a task instruction when a language is supplied; given
/// none it picks a language itself and returns Chinese for English speech. Every
/// caller therefore needs a real language rather than a nil "let it decide", so
/// the rule lives here instead of being restated per call site.
public enum MuesliQwen3AsrSystemLanguage {
    /// The Mac's current language when Qwen3-ASR supports it, English otherwise.
    public static let current: MuesliQwen3AsrConfig.Language = {
        if let code = Locale.current.language.languageCode?.identifier,
           let language = MuesliQwen3AsrConfig.Language(rawValue: code.lowercased()) {
            return language
        }
        return .english
    }()
}
