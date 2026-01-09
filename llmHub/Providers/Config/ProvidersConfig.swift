import Foundation

/// Centralized configuration for all LLM providers.
/// Fill these values from the official provider documentation. No defaults are assumed here.
struct ProvidersConfig {
    struct OpenAI {
        var baseURL: URL?
        var apiVersion: String?
        var models: [LLMModel]
        var pricing: PricingMetadata?
    }

    struct Anthropic {
        var baseURL: URL?
        var apiVersion: String?
        var models: [LLMModel]
        var pricing: PricingMetadata?
    }

    struct GoogleAI {
        /// e.g. Gemini API endpoint or Vertex AI endpoint depending on your integration
        var baseURL: URL?
        var apiVersion: String?
        var models: [LLMModel]
        var pricing: PricingMetadata?
    }

    struct Mistral {
        var baseURL: URL?
        var apiVersion: String?
        var models: [LLMModel]
        var pricing: PricingMetadata?
    }

    struct XAI {
        var baseURL: URL?
        var apiVersion: String?
        var models: [LLMModel]
        var pricing: PricingMetadata?
    }

    struct OpenRouter {
        var baseURL: URL?
        var apiVersion: String?
        var models: [LLMModel]
        var pricing: PricingMetadata?
    }

    var openAI = OpenAI(baseURL: nil, apiVersion: nil, models: [], pricing: nil)
    var anthropic = Anthropic(baseURL: nil, apiVersion: nil, models: [], pricing: nil)
    var googleAI = GoogleAI(baseURL: nil, apiVersion: nil, models: [], pricing: nil)
    var mistral = Mistral(baseURL: nil, apiVersion: nil, models: [], pricing: nil)
    var xai = XAI(baseURL: nil, apiVersion: nil, models: [], pricing: nil)
    var openRouter = OpenRouter(baseURL: nil, apiVersion: nil, models: [], pricing: nil)
}

/// Creates the default provider configuration with all available models.
/// This is the single source of truth for model definitions.
func makeDefaultConfig() -> ProvidersConfig {
    var config = ProvidersConfig()

    // MARK: - OpenAI Models
    config.openAI.models = [
        LLMModel(id: "gpt-4o", name: "GPT-4o", maxOutputTokens: 16384, contextWindow: 128000),
        LLMModel(
            id: "gpt-4o-mini", name: "GPT-4o Mini", maxOutputTokens: 16384, contextWindow: 128000),
        LLMModel(
            id: "o1-preview", name: "o1 Preview", maxOutputTokens: 32768, contextWindow: 128000),
        LLMModel(id: "o1-mini", name: "o1 Mini", maxOutputTokens: 65536, contextWindow: 128000),
        LLMModel(
            id: "gpt-4-turbo", name: "GPT-4 Turbo", maxOutputTokens: 16384, contextWindow: 128000),
        LLMModel(id: "gpt-4", name: "GPT-4", maxOutputTokens: 8192, contextWindow: 8192),
        LLMModel(
            id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", maxOutputTokens: 16384, contextWindow: 16384
        )
    ]

    // MARK: - Anthropic (Claude) Models
    // Keep this list to models that are known to exist; invalid IDs will make chat "hang"
    // (the request is sent but the provider returns an error).
    config.anthropic.models = [
        // Claude 3.5
        LLMModel(
            id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", maxOutputTokens: 8192,
            contextWindow: 200000),
        LLMModel(
            id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", maxOutputTokens: 8192,
            contextWindow: 200000),
        // Claude 3
        LLMModel(
            id: "claude-3-opus-20240229", name: "Claude 3 Opus", maxOutputTokens: 8192,
            contextWindow: 200000),
        LLMModel(
            id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", maxOutputTokens: 8192,
            contextWindow: 200000),
        LLMModel(
            id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", maxOutputTokens: 8192,
            contextWindow: 200000)
    ]

    // MARK: - Google AI (Gemini) Models
    // Updated Dec 2025: Gemini 2.5 series with 65K output tokens
    config.googleAI.models = [
        // Gemini 2.5 (Latest - Dec 2025)
        LLMModel(
            id: "gemini-2.5-flash", name: "Gemini 2.5 Flash", maxOutputTokens: 65536,
            contextWindow: 1_048_576),
        LLMModel(
            id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", maxOutputTokens: 65536,
            contextWindow: 1_048_576),
        // Gemini 2.0 (Experimental)
        LLMModel(
            id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", maxOutputTokens: 8192,
            contextWindow: 1_000_000),
        // Gemini 1.5 (Stable)
        LLMModel(
            id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", maxOutputTokens: 8192,
            contextWindow: 1_000_000),
        LLMModel(
            id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", maxOutputTokens: 8192,
            contextWindow: 1_000_000)
    ]

    // MARK: - Mistral Models
    // Updated Dec 2025: Mistral Large 3 with 256K context
    config.mistral.models = [
        // Mistral Large 3 (Latest)
        LLMModel(
            id: "mistral-large-latest", name: "Mistral Large 3", maxOutputTokens: 8192,
            contextWindow: 256000),
        // Vision
        LLMModel(
            id: "pixtral-large-latest", name: "Pixtral Large", maxOutputTokens: 8192,
            contextWindow: 128000),
        LLMModel(
            id: "pixtral-12b-2409", name: "Pixtral 12B", maxOutputTokens: 8192,
            contextWindow: 128000),
        // Small/Code
        LLMModel(
            id: "mistral-small-latest", name: "Mistral Small", maxOutputTokens: 8192,
            contextWindow: 32000),
        LLMModel(
            id: "codestral-latest", name: "Codestral", maxOutputTokens: 8192, contextWindow: 256000)
    ]

    // MARK: - xAI (Grok) Models
    // Updated Dec 2025: Grok 3 with 131K context, 16K-128K output
    config.xai.models = [
        // Grok 4 - Reasoning
        LLMModel(
            id: "grok-4-1-fast-reasoning", name: "Grok 4.1 Fast Reasoning", maxOutputTokens: 16384,
            contextWindow: 131072),
        LLMModel(
            id: "grok-4-fast-non-reasoning", name: "Grok 4 Fast", maxOutputTokens: 16384,
            contextWindow: 131072),
        // Grok 3 (Feb 2025 flagship)
        LLMModel(
            id: "grok-3", name: "Grok 3", maxOutputTokens: 128000,
            contextWindow: 131072),
        LLMModel(
            id: "grok-3-mini", name: "Grok 3 Mini", maxOutputTokens: 16384, contextWindow: 131072),
        // Grok 2 - Vision & Image Generation
        LLMModel(
            id: "grok-2-vision-1212", name: "Grok 2 Vision", maxOutputTokens: 16384,
            contextWindow: 32000),
        LLMModel(
            id: "grok-2-image-1212", name: "Grok 2 Image", maxOutputTokens: 16384,
            contextWindow: 32000)
    ]

    // MARK: - OpenRouter Models (Fallback - fetches dynamically)
    config.openRouter.models = [
        LLMModel(
            id: "openai/gpt-4o", name: "OR: GPT-4o", maxOutputTokens: 16384, contextWindow: 128000),
        LLMModel(
            id: "anthropic/claude-3.5-sonnet", name: "OR: Claude 3.5 Sonnet", maxOutputTokens: 8192,
            contextWindow: 200000)
    ]

    return config
}
