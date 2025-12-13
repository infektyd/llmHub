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
    @Environment(\.theme) private var theme
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
                    .foregroundColor(theme.textPrimary)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(headerBackground)

            Divider()
                .background(theme.textSecondary.opacity(0.2))

            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textSecondary)

                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundColor(theme.textPrimary)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(searchBarBackground)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Model list with proper scrolling
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(height: 500)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 520)
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
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(title == "Favorites" ? .yellow : theme.accent)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(theme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                            isSelected(model) ? theme.accent : theme.textSecondary.opacity(0.4),
                            lineWidth: 2
                        )
                        .frame(width: 18, height: 18)

                    if isSelected(model) {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 10, height: 10)
                    }
                }

                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        // Context window
                        Label(formatContextWindow(model.contextWindow), systemImage: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textSecondary)

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
        AdaptiveGlassBackground(target: .modelPicker)
    }

    private var headerBackground: some View {
        Group {
            if theme.usesGlassEffect {
                Color.clear
                    .glassEffect(GlassEffect.regular, in: .rect)
            } else {
                theme.backgroundSecondary
            }
        }
    }

    private var searchBarBackground: some View {
        Group {
            if theme.usesGlassEffect {
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
                                    ? theme.accent.opacity(0.5) : theme.accent.opacity(0.3),
                                lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSearchFocused
                                    ? theme.accent.opacity(0.5) : theme.textSecondary.opacity(0.2),
                                lineWidth: 1
                            )
                    )
            }
        }
    }

    private var sectionHeaderBackground: some View {
        Group {
            if theme.usesGlassEffect {
                Color.clear
                    .glassEffect(GlassEffect.regular, in: .rect)
            } else {
                theme.backgroundSecondary.opacity(0.5)
            }
        }
    }

    private func modelRowBackground(isSelected: Bool) -> some View {
        Group {
            if theme.usesGlassEffect {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accent.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? theme.accent.opacity(0.5) : Color.clear,
                                lineWidth: 1
                            )
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? theme.accent.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? theme.accent.opacity(0.3) : Color.clear,
                                lineWidth: 1
                            )
                    )
            }
        }
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

// MARK: - Pricing Tier
// PricingTier moved to UIModels.swift
