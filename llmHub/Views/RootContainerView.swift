import SwiftUI
import SwiftData
import Combine

struct RootContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.keychainStore) private var keychainStore

    @StateObject private var viewModelHolder = ViewModelHolder()

    var body: some View {
        Group {
            if let viewModel = viewModelHolder.viewModel {
                NavigationSplitView {
                    ChatListView(viewModel: viewModel)
                } detail: {
                    ChatDetailView(viewModel: viewModel)
                }
                .toolbar { NewChatToolbar(viewModel: viewModel) }
            } else {
                ProgressView()
            }
        }
        .task { await bootstrapIfNeeded() }
    }

    private func bootstrapIfNeeded() async {
        guard viewModelHolder.viewModel == nil else { return }
        
        let config = makeDefaultConfig()
        
        let registry = ProviderRegistry(providerBuilders: [
            { OpenAIProvider(keychain: keychainStore, config: config.openAI) },
            { AnthropicProvider(keychain: keychainStore, config: config.anthropic) },
            { GoogleAIProvider(keychain: keychainStore, config: config.googleAI) },
            { MistralProvider(keychain: keychainStore, config: config.mistral) },
            { XAIProvider(keychain: keychainStore, config: config.xai) },
            { OpenRouterProvider(keychain: keychainStore, config: config.openRouter) }
        ])
        
        let service = ChatService(modelContext: modelContext, providerRegistry: registry)
        let viewModel = ChatViewModel(service: service)
        viewModelHolder.viewModel = viewModel
        viewModel.loadSessions()
    }
    
    private func makeDefaultConfig() -> ProvidersConfig {
        var config = ProvidersConfig()
        
        // OpenAI
        config.openAI.models = [
            LLMModel(id: "gpt-4o", name: "GPT-4o", maxOutputTokens: 4096),
            LLMModel(id: "gpt-4o-mini", name: "GPT-4o Mini", maxOutputTokens: 4096),
            LLMModel(id: "o1-preview", name: "o1 Preview", maxOutputTokens: 8192)
        ]
        
        // Anthropic
        config.anthropic.models = [
            LLMModel(id: "claude-3-5-sonnet-20241022", name: "Claude 3.5 Sonnet", maxOutputTokens: 8192),
            LLMModel(id: "claude-3-5-haiku-20241022", name: "Claude 3.5 Haiku", maxOutputTokens: 4096)
        ]
        
        // Google (Gemini)
        config.googleAI.models = [
            LLMModel(id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", maxOutputTokens: 8192),
            LLMModel(id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", maxOutputTokens: 8192)
        ]
        
        // Mistral
        config.mistral.models = [
            LLMModel(id: "mistral-large-latest", name: "Mistral Large", maxOutputTokens: 4096),
            LLMModel(id: "pixtral-12b-2409", name: "Pixtral 12B", maxOutputTokens: 4096)
        ]
        
        // xAI
        config.xai.models = [
            LLMModel(id: "grok-beta", name: "Grok Beta", maxOutputTokens: 4096)
        ]
        
        // OpenRouter
        config.openRouter.models = [
            LLMModel(id: "openai/gpt-4o", name: "OR: GPT-4o", maxOutputTokens: 4096),
            LLMModel(id: "anthropic/claude-3.5-sonnet", name: "OR: Claude 3.5 Sonnet", maxOutputTokens: 8192)
        ]
        
        return config
    }
}

private final class ViewModelHolder: ObservableObject {
    @Published var viewModel: ChatViewModel?
}
