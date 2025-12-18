//
//  SettingsViewModel.swift
//  llmHub
//
//  Created by AI Assistant on 12/07/25.
//

import Combine
import SwiftUI

/// View model for managing settings and API key storage.
@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var openAIKey: String = ""
    @Published var anthropicKey: String = ""
    @Published var googleKey: String = ""
    @Published var mistralKey: String = ""
    @Published var xaiKey: String = ""
    @Published var openRouterKey: String = ""

    @Published var statusMessage: String?
    @Published var isError: Bool = false
    @Published var savingProvider: KeychainStore.ProviderKey?

    // MARK: - Tool Management
    @Published var toolToggles: [UIToolToggleItem] = []

    // MARK: - Private Properties

    private let keychainStore = KeychainStore()
    private let authService = ToolAuthorizationService()
    private var statusTimer: Timer?

    /// Optional ModelRegistry for triggering model refreshes when keys change
    /// This is set from the environment or passed in during initialization
    var modelRegistry: ModelRegistry?

    // MARK: - Provider Configuration

    struct ProviderInfo {
        let provider: KeychainStore.ProviderKey
        let name: String
        let icon: String
        let description: String?
        let docsURL: URL?

        static let allProviders: [ProviderInfo] = [
            ProviderInfo(
                provider: .openai,
                name: "OpenAI",
                icon: "sparkles",
                description: "GPT-4, GPT-4o, o1, and more",
                docsURL: URL(string: "https://platform.openai.com/api-keys")
            ),
            ProviderInfo(
                provider: .anthropic,
                name: "Anthropic",
                icon: "brain.head.profile",
                description: "Claude 4.5, Claude 3.5 Sonnet, and more",
                docsURL: URL(string: "https://console.anthropic.com/settings/keys")
            ),
            ProviderInfo(
                provider: .google,
                name: "Google AI",
                icon: "cloud.fill",
                description: "Gemini 1.5 Pro, Gemini 2.5 Flash, and more",
                docsURL: URL(string: "https://aistudio.google.com/app/apikey")
            ),
            ProviderInfo(
                provider: .mistral,
                name: "Mistral AI",
                icon: "wind",
                description: "Mistral Large, Pixtral, Codestral, and more",
                docsURL: URL(string: "https://console.mistral.ai/api-keys/")
            ),
            ProviderInfo(
                provider: .xai,
                name: "xAI",
                icon: "bolt.circle.fill",
                description: "Grok 4.1, Grok 2 Vision, and more",
                docsURL: URL(string: "https://console.x.ai/")
            ),
            ProviderInfo(
                provider: .openrouter,
                name: "OpenRouter",
                icon: "arrow.triangle.branch",
                description: "Unified access to multiple providers",
                docsURL: URL(string: "https://openrouter.ai/keys")
            ),
        ]
    }

    // MARK: - Public Methods

    /// Load all API keys from Keychain on view appear.
    func loadKeys() {
        Task { @MainActor in
            openAIKey = await keychainStore.apiKey(for: .openai) ?? ""
            anthropicKey = await keychainStore.apiKey(for: .anthropic) ?? ""
            googleKey = await keychainStore.apiKey(for: .google) ?? ""
            mistralKey = await keychainStore.apiKey(for: .mistral) ?? ""
            xaiKey = await keychainStore.apiKey(for: .xai) ?? ""
            openRouterKey = await keychainStore.apiKey(for: .openrouter) ?? ""

            // Also load tools
            await loadTools()
        }
    }

    /// Save an API key to Keychain for a specific provider.
    func saveKey(for provider: KeychainStore.ProviderKey) {
        savingProvider = provider

        let key = keyValue(for: provider)

        Task { @MainActor in
            do {
                try await keychainStore.updateKey(key.isEmpty ? nil : key, for: provider)

                // Success feedback
                showStatus(
                    message: "\(providerName(for: provider)) API key saved successfully",
                    isError: false)

                // Haptic feedback (macOS doesn't have haptics, but we can add sound or visual feedback)
                #if os(macOS)
                    NSSound.beep()
                #endif

                // Trigger model refresh in background if registry is available
                if !key.isEmpty, let modelRegistry = modelRegistry {
                    Task {
                        do {
                            // Fetch models for the specific provider
                            let _ = try await modelRegistry.fetchModelsForProvider(
                                provider, forceRefresh: true)
                        } catch {
                            // Log error but don't disrupt the UI - models can be fetched later
                            print(
                                "Failed to fetch models for \(provider.rawValue): \(error.localizedDescription)"
                            )
                        }
                    }
                }

            } catch {
                // Error feedback
                showStatus(
                    message:
                        "Failed to save \(providerName(for: provider)) key: \(error.localizedDescription)",
                    isError: true)
            }

            savingProvider = nil
        }
    }

    /// Delete an API key from Keychain for a specific provider.
    func deleteKey(for provider: KeychainStore.ProviderKey) {
        Task { @MainActor in
            do {
                try await keychainStore.updateKey(nil, for: provider)

                // Clear the text field
                setKeyValue("", for: provider)

                // Success feedback
                showStatus(
                    message: "\(providerName(for: provider)) API key deleted", isError: false)

                // Clear models for this provider from registry
                if let modelRegistry = modelRegistry {
                    modelRegistry.clearCache(for: provider.rawValue)
                }

            } catch {
                // Error feedback
                showStatus(
                    message:
                        "Failed to delete \(providerName(for: provider)) key: \(error.localizedDescription)",
                    isError: true)
            }
        }
    }

    /// Check if a provider has an API key configured.
    /// Note: This is a best-effort synchronous check using the cached @Published properties
    func hasKey(for provider: KeychainStore.ProviderKey) -> Bool {
        // Use the cached values from @Published properties instead of querying keychain
        let key = keyValue(for: provider)
        return !key.isEmpty
    }

    /// Get a binding for a specific provider's API key.
    func binding(for provider: KeychainStore.ProviderKey) -> Binding<String> {
        switch provider {
        case .openai:
            return Binding(
                get: { self.openAIKey },
                set: { self.openAIKey = $0 }
            )
        case .anthropic:
            return Binding(
                get: { self.anthropicKey },
                set: { self.anthropicKey = $0 }
            )
        case .google:
            return Binding(
                get: { self.googleKey },
                set: { self.googleKey = $0 }
            )
        case .mistral:
            return Binding(
                get: { self.mistralKey },
                set: { self.mistralKey = $0 }
            )
        case .xai:
            return Binding(
                get: { self.xaiKey },
                set: { self.xaiKey = $0 }
            )
        case .openrouter:
            return Binding(
                get: { self.openRouterKey },
                set: { self.openRouterKey = $0 }
            )
        }
    }

    /// Loads the list of available tools and their enabled state.
    func loadTools() async {
        let environment = ToolEnvironment.current

        // Manual registration of core tools
        // Ideally these should come from a central lookup or the same place ChatService gets them
        let tools: [any Tool] = [
            CalculatorTool(),
            CodeInterpreterTool(),
            DataVisualizationTool(),
            FileEditorTool(),
            HTTPRequestTool(),
            FileReaderTool(),
            ShellTool(),
            WebSearchTool(),
        ]

        let registry = await ToolRegistry(tools: tools)
        let availableTools = await registry.allTools()

        let iconMap: [String: String] = [
            "calculator": "function",
            "code_interpreter": "curlybraces",
            "data_visualization": "chart.xyaxis.line",
            "file_editor": "pencil.and.list.clipboard",
            "http_request": "network",
            "read_file": "doc.text.magnifyingglass",
            "shell": "terminal",
            "web_search": "globe",
        ]

        var toggles: [UIToolToggleItem] = []

        for tool in availableTools {
            let availability = tool.availability(in: environment)
            // Use tool.name as the ID since it's unique
            let permission = authService.checkAccess(for: tool.name)

            // Map ID or Name to icon key (using name lowercased)
            let key = tool.name.lowercased().replacingOccurrences(of: " ", with: "_")
            // Try exact key or fallback
            let icon = iconMap[key] ?? "wrench.and.screwdriver"

            // Generate display name (e.g. "code_interpreter" -> "Code Interpreter")
            let displayName = tool.name
                .replacingOccurrences(of: "_", with: " ")
                .capitalized

            let toggle = UIToolToggleItem(
                id: tool.name,
                name: displayName,
                icon: icon,
                description: tool.description,
                isEnabled: permission == .authorized,
                isAvailable: availability.isAvailable,
                unavailableReason: {
                    if case .unavailable(let reason) = availability { return reason }
                    if case .requiresAuthorization(let cap) = availability {
                        return "Requires \(cap.rawValue)"
                    }
                    return nil
                }()
            )
            toggles.append(toggle)
        }

        // Sort by name
        self.toolToggles = toggles.sorted { $0.name < $1.name }
    }

    /// Toggles the enabled state of a tool.
    func toggleTool(_ toolID: String, enabled: Bool) {
        Task { @MainActor in
            if enabled {
                authService.grantAccess(for: toolID)
            } else {
                authService.revokeAccess(for: toolID)
            }
            // Reload to update state
            await loadTools()
        }
    }

    // MARK: - Private Methods

    private func keyValue(for provider: KeychainStore.ProviderKey) -> String {
        switch provider {
        case .openai: return openAIKey
        case .anthropic: return anthropicKey
        case .google: return googleKey
        case .mistral: return mistralKey
        case .xai: return xaiKey
        case .openrouter: return openRouterKey
        }
    }

    private func setKeyValue(_ value: String, for provider: KeychainStore.ProviderKey) {
        switch provider {
        case .openai: openAIKey = value
        case .anthropic: anthropicKey = value
        case .google: googleKey = value
        case .mistral: mistralKey = value
        case .xai: xaiKey = value
        case .openrouter: openRouterKey = value
        }
    }

    private func providerName(for provider: KeychainStore.ProviderKey) -> String {
        ProviderInfo.allProviders.first(where: { $0.provider == provider })?.name
            ?? provider.rawValue
    }

    private func showStatus(message: String, isError: Bool) {
        self.statusMessage = message
        self.isError = isError

        // Clear status after 3 seconds
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                withAnimation {
                    self?.statusMessage = nil
                }
            }
        }
    }
}
