//
//  NeonModelPickerPanel.swift
//  llmHub
//
//  Enhanced model picker with search, scrolling, favorites, and metadata display.
//

import SwiftUI

/// A comprehensive model picker panel with search, scrolling, favorites, and metadata display.
@MainActor
struct NeonModelPickerPanel: View {
    @Binding var selectedProvider: UILLMProvider?
    @Binding var selectedModel: UILLMModel?
    @Binding var isPresented: Bool

    let availableProviders: [UILLMProvider]

    @State private var searchText = ""
    @State private var favoritesManager = ModelFavoritesManager()
    @FocusState private var isSearchFocused: Bool
    @Environment(\.keychainStore) private var keychainStore
    @State private var configuredProviders: Set<String> = []

    init(
        selectedProvider: Binding<UILLMProvider?>, selectedModel: Binding<UILLMModel?>,
        isPresented: Binding<Bool>, availableProviders: [UILLMProvider]
    ) {
        self._selectedProvider = selectedProvider
        self._selectedModel = selectedModel
        self._isPresented = isPresented
        self.availableProviders = availableProviders
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Select Model")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 08)
            .background(headerBackground)

            Divider()
                .background(AppColors.textSecondary.opacity(0.2))

            // Search bar
            HStack(spacing: 06) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)

                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPrimary)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 08)
            .padding(.vertical, 05)
            .background(searchBarBackground)
            .padding(.horizontal, 10)
            .padding(.vertical, 06)

            // Model list with proper scrolling
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 06, pinnedViews: [.sectionHeaders]) {
                    // Favorites section (if any)
                    if !favoriteModels.isEmpty {
                        Section {
                            ForEach(favoriteModels, id: \.model.id) { item in
                                modelRow(
                                    provider: item.provider, model: item.model, isFavorite: true)
                            }
                        } header: {
                            sectionHeader(title: "Favorites", icon: "star.fill")
                        }
                    }

                    // Provider sections
                    ForEach(filteredProviders, id: \.id) { provider in
                        Section {
                            ForEach(provider.models, id: \.id) { model in
                                let isFavorite = favoritesManager.isFavorite(modelID: model.modelID)
                                modelRow(provider: provider, model: model, isFavorite: isFavorite)
                            }
                        } header: {
                            sectionHeader(title: provider.name, icon: provider.icon)
                        }
                    }
                }
                .padding(.horizontal, 08)
                .padding(.vertical, 06)
            }
            .frame(height: 300)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 300)
        .background(panelBackground)
        .onAppear {
            isSearchFocused = true
            loadConfiguredProviders()
        }
    }

    // MARK: - Configuration Check

    /// Checks which providers have API keys configured
    private func loadConfiguredProviders() {
        Task { @MainActor in
            configuredProviders.removeAll()
            for providerCase in KeychainStore.ProviderKey.allCases {
                if await keychainStore.apiKey(for: providerCase) != nil {
                    configuredProviders.insert(providerCase.rawValue)
                }
            }
        }
    }

    /// Checks if a provider has an API key configured
    private func hasAPIKey(for providerName: String) -> Bool {
        configuredProviders.contains { configuredName in
            configuredName.lowercased() == providerName.lowercased()
        }
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 04) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(title == "Favorites" ? .yellow : AppColors.accent)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 01)
        .padding(.vertical, 01)
        .background(sectionHeaderBackground)
    }

    // MARK: - Model Row

    private func modelRow(provider: UILLMProvider, model: UILLMModel, isFavorite: Bool) -> some View
    {
        let hasKey = hasAPIKey(for: provider.name)

        return Button(action: {
            selectedProvider = provider
            selectedModel = model
            isPresented = false
        }) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(
                            isSelected(model)
                                ? AppColors.accent : AppColors.textSecondary.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)

                    if isSelected(model) {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 05, height: 05)
                    }
                }

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 06) {
                        // Context window
                        Label(formatContextWindow(model.contextWindow), systemImage: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textSecondary)

                        // Pricing tier
                        if let tier = model.pricingTier {
                            Label(tier.displayName, systemImage: tier.icon)
                                .font(.system(size: 11))
                                .foregroundColor(tier.color)
                        }
                    }
                }

                Spacer()

                // Badge for unavailable models
                if !hasKey {
                    Text("No Key")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.15))
                        .clipShape(Capsule())
                }

                // Favorite button
                Button(action: {
                    toggleFavorite(modelID: model.modelID)
                }) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .opacity(hasKey ? 1.0 : 0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(modelRowBackground(isSelected: isSelected(model)))
            .opacity(hasKey ? 1.0 : 0.5)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isSelected(model))
    }

    // MARK: - Helpers

    private func isSelected(_ model: UILLMModel) -> Bool {
        selectedModel?.id == model.id
    }

    private func toggleFavorite(modelID: String) {
        if favoritesManager.isFavorite(modelID: modelID) {
            favoritesManager.removeFavorite(modelID: modelID)
        } else {
            favoritesManager.addFavorite(modelID: modelID)
        }
    }

    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M tokens"
        } else if tokens >= 1000 {
            return "\(tokens / 1000)K tokens"
        } else {
            return "\(tokens) tokens"
        }
    }

    // MARK: - Subviews

    private var panelBackground: some View {
        Color.clear.glassEffect(.regular, in: Rectangle())
    }

    private var headerBackground: some View {
        Color.clear
            .glassEffect(GlassEffect.regular, in: .rect)
    }

    private var searchBarBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            #if os(macOS)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
            #else
                .fill(Color(uiColor: .tertiarySystemBackground).opacity(0.3))
            #endif
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSearchFocused
                            ? AppColors.accent.opacity(0.5) : AppColors.accent.opacity(0.3),
                        lineWidth: 1
                    )
            )
    }

    private var sectionHeaderBackground: some View {
        Color.clear
            .glassEffect(GlassEffect.regular, in: .rect)
    }

    private func modelRowBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? AppColors.accent.opacity(0.1) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? AppColors.accent.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Filtered Data

    private var filteredProviders: [UILLMProvider] {
        if searchText.isEmpty {
            return availableProviders
        }

        let searchLower = searchText.lowercased()
        return availableProviders.compactMap { provider in
            let matchedModels = provider.models.filter { model in
                model.name.lowercased().contains(searchLower)
                    || model.modelID.lowercased().contains(searchLower)
            }

            if matchedModels.isEmpty {
                return nil
            }

            return UILLMProvider(
                id: provider.id,
                name: provider.name,
                icon: provider.icon,
                models: matchedModels,
                isActive: provider.isActive
            )
        }
    }

    private var favoriteModels: [(provider: UILLMProvider, model: UILLMModel)] {
        var results: [(UILLMProvider, UILLMModel)] = []

        for provider in availableProviders {
            for model in provider.models {
                if favoritesManager.isFavorite(modelID: model.modelID) {
                    // Apply search filter
                    if !searchText.isEmpty {
                        let searchLower = searchText.lowercased()
                        if !model.name.lowercased().contains(searchLower)
                            && !model.modelID.lowercased().contains(searchLower)
                        {
                            continue
                        }
                    }
                    results.append((provider, model))
                }
            }
        }

        return results
    }
}
// MARK: - Previews

#Preview("Model Picker Panel") {
    NeonModelPickerPanel(
        selectedProvider: .constant(UILLMProvider.mockOpenAI()),
        selectedModel: .constant(UILLMModel.mockGPT4()),
        isPresented: .constant(true),
        availableProviders: [
            UILLMProvider.mockOpenAI(),
            UILLMProvider.mockAnthropic()
        ]
    )
    .environmentObject(MockData.modelRegistry())
    .previewEnvironment()
}

// MARK: - Mocks for Panel

extension UILLMProvider {
    static func mockAnthropic() -> UILLMProvider {
        UILLMProvider(
            id: UUID(),
            name: "Anthropic",
            icon: "brain.head.profile",
            models: [
                UILLMModel(id: UUID(), modelID: "claude-3-opus", name: "Claude 3 Opus", contextWindow: 200000),
                UILLMModel(id: UUID(), modelID: "claude-3-sonnet", name: "Claude 3 Sonnet", contextWindow: 200000)
            ],
            isActive: true
        )
    }
}
