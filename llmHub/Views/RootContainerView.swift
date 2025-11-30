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
}

private final class ViewModelHolder: ObservableObject {
    @Published var viewModel: ChatViewModel?
}
