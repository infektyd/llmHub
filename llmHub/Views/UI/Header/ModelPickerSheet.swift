//
//  ModelPickerSheet.swift
//  llmHub
//
//  Model selection sheet with provider hierarchy
//

import SwiftUI

struct ModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var modelRegistry: ModelRegistry

    @Environment(\.uiScale) private var uiScale

    @Binding var selectedProviderID: String
    @Binding var selectedModelID: String

    @State private var configuredProviders: Set<String> = []
    @State private var expandedProviders: Set<String>

    private let providers: [KeychainStore.ProviderKey] = KeychainStore.ProviderKey.allCases

    init(selectedProviderID: Binding<String>, selectedModelID: Binding<String>) {
        self._selectedProviderID = selectedProviderID
        self._selectedModelID = selectedModelID
        self._expandedProviders = State(initialValue: [selectedProviderID.wrappedValue])
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(providers, id: \.rawValue) { providerKey in
                    let providerID = providerKey.rawValue
                    let isConfigured = configuredProviders.contains(providerID)
                    let models = modelRegistry.models(for: providerID)

                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedProviders.contains(providerID) },
                            set: {
                                if $0 {
                                    expandedProviders.insert(providerID)
                                } else {
                                    expandedProviders.remove(providerID)
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 0) {
                            if isConfigured {
                                if models.isEmpty {
                                    Text("No models available")
                                        .font(.system(size: 13 * uiScale))
                                        .foregroundStyle(AppColors.textTertiary)
                                        .padding(.leading, 24)
                                        .padding(.vertical, 8)
                                } else {
                                    ForEach(models, id: \.id) { model in
                                        modelRow(providerID: providerID, model: model)
                                    }
                                }
                            } else {
                                HStack {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12 * uiScale))
                                    Text("Not configured")
                                        .font(.system(size: 13 * uiScale))
                                    Spacer()
                                    Text("Configure in Settings")
                                        .font(.system(size: 11 * uiScale))
                                        .foregroundStyle(AppColors.accent)
                                }
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(.leading, 24)
                                .padding(.vertical, 8)
                            }
                        }
                    } label: {
                        HStack {
                            providerIcon(providerID: providerID)
                                .font(.system(size: 14 * uiScale))
                            Text(titleFor(providerID))
                                .font(.system(size: 14 * uiScale, weight: .bold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Select Model")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await checkConfiguredProviders()
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private func modelRow(providerID: String, model: LLMModel) -> some View {
        Button {
            selectedProviderID = providerID
            selectedModelID = model.id
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.system(size: 13 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)

                    if model.contextWindow > 0 {
                        Text("\(formatContextWindow(model.contextWindow)) context window")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    } else {
                        Text("Context window unknown")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Spacer()

                if selectedProviderID == providerID && selectedModelID == model.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .padding(.leading, 8)
    }

    private func providerIcon(providerID: String) -> some View {
        let icon: String
        switch providerID.lowercased() {
        case "openai": icon = "sparkles"
        case "anthropic": icon = "brain.head.profile"
        case "google": icon = "cloud.fill"
        case "mistral": icon = "wind"
        case "xai": icon = "x.circle.fill"
        case "openrouter": icon = "arrow.triangle.branch"
        default: icon = "server.rack"
        }
        return Image(systemName: icon)
    }

    private func titleFor(_ providerID: String) -> String {
        switch providerID.lowercased() {
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "google": return "Google"
        case "mistral": return "Mistral"
        case "xai": return "xAI"
        case "openrouter": return "OpenRouter"
        default: return providerID.capitalized
        }
    }

    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
        } else if tokens >= 1_000 {
            return "\(tokens / 1_000)k"
        } else {
            return "\(tokens)"
        }
    }

    private func checkConfiguredProviders() async {
        let keychain = KeychainStore()
        var configured = Set<String>()
        for provider in providers where await keychain.apiKey(for: provider) != nil {
            configured.insert(provider.rawValue)
        }
        configuredProviders = configured
    }
}
#if DEBUG
    #Preview {
        @Previewable @State var provider = "openai"
        @Previewable @State var model = "gpt-4o"

        ModelPickerSheet(
            selectedProviderID: $provider,
            selectedModelID: $model
        )
        .environmentObject(ModelRegistry())
    }
#endif
