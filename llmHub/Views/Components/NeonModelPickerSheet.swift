//
//  NeonModelPickerSheet.swift
//  llmHub
//
//  Cross-platform model picker sheet with DisclosureGroup and search.
//

import SwiftUI

struct NeonModelPickerSheet: View {
    @Binding var selectedProvider: UILLMProvider?
    @Binding var selectedModel: UILLMModel?
    @Binding var isPresented: Bool
    
    @EnvironmentObject private var modelRegistry: ModelRegistry
    @Environment(\.keychainStore) private var keychainStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    
    @State private var searchText = ""
    @State private var favoritesManager = ModelFavoritesManager()
    @State private var configuredProviders: Set<String> = []
    @State private var expandedProviders: Set<UUID> = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.neonMidnight
                    .ignoresSafeArea()
                
                List {
                    // Favorites section
                    if !favoriteModels.isEmpty {
                        Section {
                            ForEach(favoriteModels, id: \.model.id) { item in
                                modelRowButton(provider: item.provider, model: item.model, isFavorite: true)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.yellow)
                                Text("Favorites")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    // Provider sections with DisclosureGroup
                    ForEach(filteredProviders, id: \.id) { provider in
                        Section {
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedProviders.contains(provider.id) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedProviders.insert(provider.id)
                                        } else {
                                            expandedProviders.remove(provider.id)
                                        }
                                    }
                                )
                            ) {
                                ForEach(provider.models, id: \.id) { model in
                                    let isFavorite = favoritesManager.isFavorite(modelID: model.modelID)
                                    modelRowButton(provider: provider, model: model, isFavorite: isFavorite)
                                }
                            } label: {
                                providerHeader(provider: provider)
                            }
                            .tint(.neonElectricBlue)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .searchable(text: $searchText, prompt: "Search models...")
            }
            .navigationTitle("Select Model")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                        dismiss()
                    }
                    .foregroundColor(.neonElectricBlue)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadConfiguredProviders()
                // Auto-expand first provider if nothing expanded
                if expandedProviders.isEmpty, let first = filteredProviders.first {
                    expandedProviders.insert(first.id)
                }
            }
        }
        #if os(macOS)
        .frame(width: 450, height: 600)
        #endif
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Subviews
    
    private func providerHeader(provider: UILLMProvider) -> some View {
        HStack(spacing: 10) {
            Image(systemName: provider.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.neonElectricBlue)
                .frame(width: 24)
            
            Text(provider.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
            
            Text("\(provider.models.count)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
        }
        .padding(.vertical, 4)
    }
    
    private func modelRowButton(provider: UILLMProvider, model: UILLMModel, isFavorite: Bool) -> some View {
        let isSelected = selectedModel?.id == model.id
        let hasKey = hasAPIKey(for: provider.name)
        
        return Button(action: {
            selectedProvider = provider
            selectedModel = model
            isPresented = false
            dismiss()
        }) {
            HStack(spacing: 12) {
                // Selection indicator
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(Color.neonElectricBlue)
                            .frame(width: 8, height: 8)
                    }
                }
                .frame(width: 16)
                
                // Icon for model
                Image(systemName: "brain")
                    .font(.system(size: 12))
                    .foregroundColor(.neonGray)
                
                // Model info
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .neonElectricBlue : .white)
                        .lineLimit(1)
                    
                    HStack(spacing: 10) {
                        // Context window
                        Label(formatContextWindow(model.contextWindow), systemImage: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.6))
                        
                        // Pricing tier
                        if let tier = model.pricingTier {
                            Label(tier.displayName, systemImage: tier.icon)
                                .font(.system(size: 11))
                                .foregroundColor(tier.color)
                        }
                    }
                }
                
                Spacer()
                
                // Badges
                HStack(spacing: 8) {
                    // No Key badge
                    if !hasKey {
                        Text("No Key")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.2))
                            )
                    }
                    
                    // Favorite star
                    Button(action: {
                        toggleFavorite(modelID: model.modelID)
                    }) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(isFavorite ? .yellow : .white.opacity(0.2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .opacity(hasKey ? 1.0 : 0.6)
    }
    
    // MARK: - Data Helpers
    
    private var availableProviders: [UILLMProvider] {
        modelRegistry.availableProviders().compactMap { providerID in
            let models = modelRegistry.models(for: providerID)
            guard !models.isEmpty else { return nil }
            
            let uiModels = models.map { model in
                UILLMModel(
                    id: stableUUID(for: model.id),
                    modelID: model.id,
                    name: model.displayName,
                    contextWindow: model.contextWindow
                )
            }
            
            return UILLMProvider(
                id: stableUUID(for: providerID),
                name: providerDisplayName(for: providerID),
                icon: providerIcon(for: providerID),
                models: uiModels,
                isActive: false
            )
        }
    }
    
    private var filteredProviders: [UILLMProvider] {
        if searchText.isEmpty {
            return availableProviders
        }
        
        let searchLower = searchText.lowercased()
        return availableProviders.compactMap { provider in
            let matchedModels = provider.models.filter { model in
                model.name.lowercased().contains(searchLower) ||
                model.modelID.lowercased().contains(searchLower) ||
                provider.name.lowercased().contains(searchLower)
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
                        if !model.name.lowercased().contains(searchLower) &&
                           !model.modelID.lowercased().contains(searchLower) {
                            continue
                        }
                    }
                    results.append((provider, model))
                }
            }
        }
        
        return results
    }
    
    // MARK: - Configuration Check
    
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
    
    private func hasAPIKey(for providerName: String) -> Bool {
        configuredProviders.contains { configuredName in
            configuredName.lowercased() == providerName.lowercased()
        }
    }
    
    // MARK: - Actions
    
    private func toggleFavorite(modelID: String) {
        if favoritesManager.isFavorite(modelID: modelID) {
            favoritesManager.removeFavorite(modelID: modelID)
        } else {
            favoritesManager.addFavorite(modelID: modelID)
        }
    }
    
    // MARK: - Formatters
    
    private func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return "\(tokens / 1_000_000)M tokens"
        } else if tokens >= 1000 {
            return "\(tokens / 1000)K tokens"
        } else {
            return "\(tokens) tokens"
        }
    }
}
