//
//  NeonModelPicker.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

#if os(macOS)
    struct NeonModelPicker: View {
        @Binding var selectedProvider: UILLMProvider?
        @Binding var selectedModel: UILLMModel?
        @EnvironmentObject private var modelRegistry: ModelRegistry
        @Environment(\.theme) private var theme
        @State private var showPickerPanel = false

        var body: some View {
            Button(action: {
                if availableProviders.isEmpty {
                    openSettings()
                } else {
                    showPickerPanel.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    if let provider = selectedProvider {
                        Image(systemName: provider.icon)
                            .font(.system(size: 14))
                            .foregroundColor(theme.accent)
                    } else if availableProviders.isEmpty {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundColor(theme.error)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        if let provider = selectedProvider {
                            Text(provider.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(theme.textSecondary)
                        } else if availableProviders.isEmpty {
                            Text("No providers")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(theme.textSecondary)
                        }

                        if let model = selectedModel {
                            Text(model.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                        } else if availableProviders.isEmpty {
                            Text("Add API keys")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(theme.error)
                        } else {
                            Text("Select model")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(theme.textSecondary)
                        }
                    }

                    Image(systemName: showPickerPanel ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(theme.textSecondary)
                        .animation(.snappy, value: showPickerPanel)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(pickerButtonBackground)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPickerPanel) {
                NeonModelPickerSheet(
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel,
                    isPresented: $showPickerPanel
                )
                .environmentObject(modelRegistry)
            }
        }

        // MARK: - Helper Properties

        /// Builds a list of UILLMProviders from the ModelRegistry data.
        private var availableProviders: [UILLMProvider] {
            modelRegistry.availableProviders().compactMap { providerID in
                // Get models for this provider
                let models = modelRegistry.models(for: providerID)
                guard !models.isEmpty else { return nil }

                // Map LLMModel to UILLMModel
                let uiModels = models.map { model in
                    UILLMModel(
                        id: UUID(),  // Generate a UI-specific ID
                        modelID: model.id,  // ✅ Store actual API model ID
                        name: model.displayName,
                        contextWindow: model.contextWindow
                    )
                }

                // Map provider ID to UI provider info
                return UILLMProvider(
                    id: UUID(),
                    name: providerDisplayName(for: providerID),
                    icon: providerIcon(for: providerID),
                    models: uiModels,
                    isActive: false  // Not used in picker context
                )
            }
        }

        /// Maps provider IDs to display names.
        private func providerDisplayName(for providerID: String) -> String {
            switch providerID.lowercased() {
            case "openai": return "OpenAI"
            case "anthropic": return "Anthropic"
            case "google": return "Google AI"
            case "mistral": return "Mistral AI"
            case "xai": return "xAI"
            case "openrouter": return "OpenRouter"
            default: return providerID.capitalized
            }
        }

        /// Maps provider IDs to SF Symbol icons.
        private func providerIcon(for providerID: String) -> String {
            switch providerID.lowercased() {
            case "openai": return "sparkles"
            case "anthropic": return "brain.head.profile"
            case "google": return "cloud.fill"
            case "mistral": return "wind"
            case "xai": return "bolt.circle.fill"
            case "openrouter": return "arrow.triangle.branch"
            default: return "cpu"
            }
        }

        /// Opens the Settings window.
        private func openSettings() {
            #if os(macOS)
                if #available(macOS 14, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            #endif
        }

        // MARK: - Subviews

        private var pickerButtonBackground: some View {
            Group {
                if theme.usesGlassEffect {
                    Capsule()
                        .glassEffect(.regular, in: .capsule)
                        .overlay(
                            Capsule()
                                .stroke(
                                    availableProviders.isEmpty
                                        ? theme.error.opacity(0.8)
                                        : theme.accentSecondary.opacity(0.5),
                                    lineWidth: 1.5
                                )
                        )
                } else {
                    Capsule()
                        .fill(theme.surface)
                        .overlay(
                            Capsule()
                                .stroke(
                                    availableProviders.isEmpty
                                        ? theme.error.opacity(0.5)
                                        : theme.textSecondary.opacity(0.2),
                                    lineWidth: theme.borderWidth
                                )
                        )
                        .shadow(
                            color: theme.shadowStyle.color,
                            radius: theme.shadowStyle.radius / 2,
                            x: 0,
                            y: 2
                        )
                }
            }
        }
    }

// MARK: - Previews

#if os(macOS)
#Preview("Model Picker - Selected") {
    NeonModelPicker(
        selectedProvider: .constant(UILLMProvider.mockOpenAI()),
        selectedModel: .constant(UILLMModel.mockGPT4())
    )
    .environmentObject(MockData.modelRegistry())
    .padding()
    .frame(width: 300)
    .previewEnvironment()
}

#Preview("Model Picker - No Provider") {
    NeonModelPicker(
        selectedProvider: .constant(nil),
        selectedModel: .constant(nil)
    )
    .environmentObject(MockData.modelRegistry())
    .padding()
    .frame(width: 300)
    .previewEnvironment()
}

// MARK: - Mocks for Model Picker

extension UILLMProvider {
    static func mockOpenAI() -> UILLMProvider {
        UILLMProvider(
            id: UUID(),
            name: "OpenAI",
            icon: "sparkles",
            models: [UILLMModel.mockGPT4()],
            isActive: true
        )
    }
}

extension UILLMModel {
    static func mockGPT4() -> UILLMModel {
        UILLMModel(
            id: UUID(),
            modelID: "gpt-4",
            name: "GPT-4",
            contextWindow: 128000
        )
    }
}
#endif
#endif
