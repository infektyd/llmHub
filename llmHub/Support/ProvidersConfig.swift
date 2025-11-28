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
