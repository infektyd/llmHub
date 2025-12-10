//
//  SettingsViewModel.swift
//  llmHub
//
//  Created by AI Assistant on 12/07/25.
//

import SwiftUI
import Combine

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
    
    // MARK: - Private Properties
    
    private let keychainStore = KeychainStore()
    private var statusTimer: Timer?
    
    // MARK: - Provider Configuration
    
    struct ProviderInfo {
        let provider: KeychainStore.ProviderKey
        let name: String
        let icon: String
        let description: String?
        let docsURL: URL?
        
        static let allProviders: [ProviderInfo] = [
            ProviderInfo(
                provider: .openAI,
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
                provider: .openRouter,
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
        openAIKey = keychainStore.apiKey(for: .openAI) ?? ""
        anthropicKey = keychainStore.apiKey(for: .anthropic) ?? ""
        googleKey = keychainStore.apiKey(for: .google) ?? ""
        mistralKey = keychainStore.apiKey(for: .mistral) ?? ""
        xaiKey = keychainStore.apiKey(for: .xai) ?? ""
        openRouterKey = keychainStore.apiKey(for: .openRouter) ?? ""
    }
    
    /// Save an API key to Keychain for a specific provider.
    func saveKey(for provider: KeychainStore.ProviderKey) {
        savingProvider = provider
        
        let key = keyValue(for: provider)
        
        do {
            try keychainStore.updateKey(key.isEmpty ? nil : key, for: provider)
            
            // Success feedback
            showStatus(message: "\(providerName(for: provider)) API key saved successfully", isError: false)
            
            // Haptic feedback (macOS doesn't have haptics, but we can add sound or visual feedback)
            NSSound.beep()
            
        } catch {
            // Error feedback
            showStatus(message: "Failed to save \(providerName(for: provider)) key: \(error.localizedDescription)", isError: true)
        }
        
        savingProvider = nil
    }
    
    /// Delete an API key from Keychain for a specific provider.
    func deleteKey(for provider: KeychainStore.ProviderKey) {
        do {
            try keychainStore.updateKey(nil, for: provider)
            
            // Clear the text field
            setKeyValue("", for: provider)
            
            // Success feedback
            showStatus(message: "\(providerName(for: provider)) API key deleted", isError: false)
            
        } catch {
            // Error feedback
            showStatus(message: "Failed to delete \(providerName(for: provider)) key: \(error.localizedDescription)", isError: true)
        }
    }
    
    /// Check if a provider has an API key configured.
    func hasKey(for provider: KeychainStore.ProviderKey) -> Bool {
        return keychainStore.apiKey(for: provider) != nil
    }
    
    /// Get a binding for a specific provider's API key.
    func binding(for provider: KeychainStore.ProviderKey) -> Binding<String> {
        switch provider {
        case .openAI:
            return $openAIKey
        case .anthropic:
            return $anthropicKey
        case .google:
            return $googleKey
        case .mistral:
            return $mistralKey
        case .xai:
            return $xaiKey
        case .openRouter:
            return $openRouterKey
        }
    }
    
    // MARK: - Private Methods
    
    private func keyValue(for provider: KeychainStore.ProviderKey) -> String {
        switch provider {
        case .openAI: return openAIKey
        case .anthropic: return anthropicKey
        case .google: return googleKey
        case .mistral: return mistralKey
        case .xai: return xaiKey
        case .openRouter: return openRouterKey
        }
    }
    
    private func setKeyValue(_ value: String, for provider: KeychainStore.ProviderKey) {
        switch provider {
        case .openAI: openAIKey = value
        case .anthropic: anthropicKey = value
        case .google: googleKey = value
        case .mistral: mistralKey = value
        case .xai: xaiKey = value
        case .openRouter: openRouterKey = value
        }
    }
    
    private func providerName(for provider: KeychainStore.ProviderKey) -> String {
        ProviderInfo.allProviders.first(where: { $0.provider == provider })?.name ?? provider.rawValue
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
