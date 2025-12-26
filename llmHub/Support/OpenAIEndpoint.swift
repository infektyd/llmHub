import Foundation

/// Defines the available OpenAI API endpoints
enum OpenAIEndpoint: String, Sendable {
    /// Standard chat completions endpoint for most GPT models
    case chatCompletions = "v1/chat/completions"
    /// Responses endpoint for gpt-5 and o1 series models
    case responses = "v1/responses"
}

/// Routes model IDs to the appropriate OpenAI endpoint
struct ModelRouter: Sendable {
    /// Determines the correct endpoint for a given model ID
    ///
    /// Uses pattern matching to identify model families that require
    /// the new `/v1/responses` endpoint versus the standard `/v1/chat/completions`.
    ///
    /// **Routing Rules:**
    /// - Models containing "gpt-5" → `.responses`
    /// - Models starting with "o1" → `.responses`
    /// - All other models → `.chatCompletions`
    ///
    /// - Parameter modelID: The model identifier (e.g., "gpt-5", "o1-preview", "gpt-4")
    /// - Returns: The appropriate `OpenAIEndpoint`
    static func endpoint(for modelID: String) -> OpenAIEndpoint {
        let lower = modelID.lowercased()

        // Responses API families (best-effort; OpenAI expands these over time):
        // - gpt-5*
        // - gpt-4.1*
        // - o-series reasoning models (o1/o3/o4-*)
        if lower.contains("gpt-5") { return .responses }
        if lower.contains("-o1") || lower.contains("-o3") { return .responses }
        if lower.hasPrefix("gpt-4.1") { return .responses }
        if lower.hasPrefix("o"), lower.dropFirst().first?.isNumber == true { return .responses }

        return .chatCompletions
    }
}

/// URL construction extension for safe endpoint building
extension URL {
    /// Constructs a full endpoint URL from a base URL and endpoint
    ///
    /// Safely combines a base API URL with a specific endpoint path,
    /// handling trailing slashes automatically via `appendingPathComponent`.
    ///
    /// - Parameters:
    ///   - baseURL: The base API URL (e.g., `https://api.openai.com`)
    ///   - endpoint: The specific endpoint to append
    /// - Returns: The complete URL for the API request
    static func buildEndpoint(base baseURL: URL, endpoint: OpenAIEndpoint) -> URL {
        baseURL.appendingPathComponent(endpoint.rawValue)
    }
}
