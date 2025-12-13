//
//  NeonModelPickerButton.swift
//  llmHub
//
//  iOS-native model picker button with Liquid Glass aesthetic.
//

#if os(iOS)
    import SwiftUI

    struct NeonModelPickerButton: View {
        @Binding var selectedProvider: UILLMProvider?
        @Binding var selectedModel: UILLMModel?
        @EnvironmentObject private var modelRegistry: ModelRegistry
        @Environment(\.theme) private var theme
        @State private var showModelPicker = false

        var body: some View {
            Button(action: {
                print("🟠 MODEL PICKER: Button tapped, setting showModelPicker = true")
                print("🟠 MODEL PICKER: Current showModelPicker before: \(showModelPicker)")
                showModelPicker = true
                print("🟠 MODEL PICKER: showModelPicker after: \(showModelPicker)")
            }) {
                HStack(spacing: 6) {
                    // Provider icon
                    if let provider = selectedProvider {
                        Image(systemName: provider.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(hasAPIKey ? .neonElectricBlue : .orange)
                    } else if availableProviders.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "cpu")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.neonElectricBlue)
                    }

                    // Model name (abbreviated)
                    Text(displayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(hasAPIKey || selectedModel == nil ? .white : .orange)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(buttonBackground)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showModelPicker) {
                NeonModelPickerSheet(
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel,
                    isPresented: $showModelPicker
                )
                .environmentObject(modelRegistry)
                .onAppear {
                    print("🟠 MODEL PICKER: Sheet presenting")
                }
            }
            .onChange(of: showModelPicker) { oldValue, newValue in
                print("🟠 MODEL PICKER: showModelPicker changed: \(oldValue) → \(newValue)")
            }
        }

        // MARK: - Helper Properties

        private var displayText: String {
            if let model = selectedModel {
                return model.name
            } else if availableProviders.isEmpty {
                return "Add API Key"
            } else {
                return "Select Model"
            }
        }

        private var hasAPIKey: Bool {
            guard let provider = selectedProvider else { return false }
            return !availableProviders.isEmpty
                && availableProviders.contains(where: { $0.name == provider.name })
        }

        private var availableProviders: [UILLMProvider] {
            modelRegistry.availableProviders().compactMap { providerID in
                let models = modelRegistry.models(for: providerID)
                guard !models.isEmpty else { return nil }

                let uiModels = models.map { model in
                    UILLMModel(
                        id: UUID(),
                        modelID: model.id,
                        name: model.displayName,
                        contextWindow: model.contextWindow
                    )
                }

                return UILLMProvider(
                    id: UUID(),
                    name: providerDisplayName(for: providerID),
                    icon: providerIcon(for: providerID),
                    models: uiModels,
                    isActive: false
                )
            }
        }

        // MARK: - Styling

        private var buttonBackground: some View {
            Capsule()
                .glassEffect(GlassEffect.regular, in: .capsule)
                .overlay(
                    Capsule()
                        .stroke(
                            hasAPIKey || selectedModel == nil
                                ? Color.neonElectricBlue.opacity(0.4) : Color.orange.opacity(0.6),
                            lineWidth: 1.5
                        )
                )
                .shadow(
                    color: hasAPIKey
                        ? Color.neonElectricBlue.opacity(0.2) : Color.orange.opacity(0.2),
                    radius: 8,
                    x: 0,
                    y: 2
                )
        }

        // MARK: - Helpers

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
    }
#endif
