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
        LLMModel(id: "gpt-4o-mini", name: "GPT-4o Mini", maxOutputTokens: 16384, contextWindow: 128000),
        LLMModel(id: "o1-preview", name: "o1 Preview", maxOutputTokens: 32768, contextWindow: 128000),
        LLMModel(id: "o1-mini", name: "o1 Mini", maxOutputTokens: 65536, contextWindow: 128000),
        LLMModel(id: "gpt-4-turbo", name: "GPT-4 Turbo", maxOutputTokens: 4096, contextWindow: 128000),
        LLMModel(id: "gpt-4", name: "GPT-4", maxOutputTokens: 8192, contextWindow: 8192),
        LLMModel(id: "gpt-3.5-turbo", name: "GPT-3.5 Turbo", maxOutputTokens: 4096, contextWindow: 16384)
    ]

    // MARK: - Anthropic (Claude) Models
    // Includes Claude 4.x flagship models and Claude 3.x for backward compatibility
    config.anthropic.models = [
        // Claude 4.5 Flagship (Latest)
        LLMModel(id: "claude-opus-4-5-20251101", name: "Claude Opus 4.5", maxOutputTokens: 32000, contextWindow: 200000),
        LLMModel(id: "claude-sonnet-4-5-20250929", name: "Claude Sonnet 4.5", maxOutputTokens: 64000, contextWindow: 200000),
        LLMModel(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5", maxOutputTokens: 8192, contextWindow: 200000),
        // Claude 4 (Previous Generation)
        LLMModel(id: "claude-opus-4-20250514", name: "Claude Opus 4", maxOutputTokens: 32000, contextWindow: 200000),
        LLMModel(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", maxOutputTokens: 64000, contextWindow: 200000),
        // Claude 3.5
        LLMModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", maxOutputTokens: 8192, contextWindow: 200000),
        LLMModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", maxOutputTokens: 8192, contextWindow: 200000),
        // Claude 3 (Legacy)
        LLMModel(id: "claude-3-opus-20240229", name: "Claude 3 Opus", maxOutputTokens: 4096, contextWindow: 200000),
        LLMModel(id: "claude-3-sonnet-20240229", name: "Claude 3 Sonnet", maxOutputTokens: 4096, contextWindow: 200000),
        LLMModel(id: "claude-3-haiku-20240307", name: "Claude 3 Haiku", maxOutputTokens: 4096, contextWindow: 200000)
    ]

    // MARK: - Google AI (Gemini) Models
    config.googleAI.models = [
        LLMModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", maxOutputTokens: 8192, contextWindow: 1000000),
        LLMModel(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", maxOutputTokens: 8192, contextWindow: 1000000),
        LLMModel(id: "gemini-1.0-pro", name: "Gemini 1.0 Pro", maxOutputTokens: 2048, contextWindow: 30000),
        LLMModel(id: "gemini-1.0-ultra", name: "Gemini 1.0 Ultra", maxOutputTokens: 2048, contextWindow: 30000)
    ]

    // MARK: - Mistral Models
    config.mistral.models = [
        LLMModel(id: "mistral-large-latest", name: "Mistral Large", maxOutputTokens: 4096, contextWindow: 128000),
        LLMModel(id: "pixtral-12b-2409", name: "Pixtral 12B", maxOutputTokens: 4096, contextWindow: 128000),
        LLMModel(id: "mistral-small-latest", name: "Mistral Small", maxOutputTokens: 4096, contextWindow: 32000),
        LLMModel(id: "codestral-latest", name: "Codestral", maxOutputTokens: 4096, contextWindow: 32000),
        LLMModel(id: "mistral-7b-instruct", name: "Mistral 7B Instruct", maxOutputTokens: 4096, contextWindow: 32000),
        LLMModel(id: "mixtral-8x7b-instruct", name: "Mixtral 8x7B Instruct", maxOutputTokens: 4096, contextWindow: 32000)
    ]

    // MARK: - xAI (Grok) Models
    // Full lineup including reasoning, vision, and image generation models
    config.xai.models = [
        // Grok 4 - Reasoning
        LLMModel(id: "grok-4-1-fast-reasoning", name: "Grok 4.1 Fast Reasoning", maxOutputTokens: 16384, contextWindow: 128000),
        LLMModel(id: "grok-4-fast-non-reasoning", name: "Grok 4 Fast", maxOutputTokens: 16384, contextWindow: 128000),
        // Grok 3
        LLMModel(id: "grok-3-mini", name: "Grok 3 Mini", maxOutputTokens: 4096, contextWindow: 128000),
        // Grok 2 - Vision & Image Generation
        LLMModel(id: "grok-2-vision-1212", name: "Grok 2 Vision", maxOutputTokens: 4096, contextWindow: 32000),
        LLMModel(id: "grok-2-image-1212", name: "Grok 2 Image", maxOutputTokens: 4096, contextWindow: 32000),
        // Grok Beta (Legacy)
        LLMModel(id: "grok-beta", name: "Grok Beta", maxOutputTokens: 4096, contextWindow: 128000)
    ]

    // MARK: - OpenRouter Models (Fallback - fetches dynamically)
    config.openRouter.models = [
        LLMModel(id: "openai/gpt-4o", name: "OR: GPT-4o", maxOutputTokens: 4096, contextWindow: 128000),
        LLMModel(id: "anthropic/claude-3.5-sonnet", name: "OR: Claude 3.5 Sonnet", maxOutputTokens: 8192, contextWindow: 200000)
    ]

    return config
}
