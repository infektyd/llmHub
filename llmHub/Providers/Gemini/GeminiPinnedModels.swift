import Foundation

/// Centralized pinned Gemini model IDs used for deterministic fallbacks.
///
/// Note: Gemini API model names are passed without the leading `models/` prefix because
/// the request URL already includes `/models/{model}`.
enum GeminiPinnedModels {
    /// Fixed remote fallback when Apple Foundation Models (AFM) are unavailable.
    ///
    /// Verified during development via the Google Gemini Models endpoint.
    static let afmFallbackFlash = "gemini-2.0-flash-001"

    /// Deterministic / rule-following default for AFM fallback.
    static let afmFallbackTemperature: Double = 0.0
}
