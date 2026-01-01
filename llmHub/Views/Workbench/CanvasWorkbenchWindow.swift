//
//  CanvasWorkbenchWindow.swift
//  llmHub
//
//  New workbench layout: a single canvas with floating panels (sidebar + inspector)
//  instead of a 3-column NavigationSplitView.
//

import SwiftData
import SwiftUI

struct CanvasWorkbenchWindow: View {
    @State private var viewModel = WorkbenchViewModel()

    @EnvironmentObject private var modelRegistry: ModelRegistry
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse)
    private var sessions: [ChatSessionEntity]

    @State private var sidebarVisible: Bool = true
    @State private var inspectorVisible: Bool = false
    @State private var showSettings: Bool = false

    #if os(iOS)
    @State private var sidebarSheetVisible: Bool = false
    @State private var inspectorSheetVisible: Bool = false
    #endif

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Group {
                    if let session = selectedSession {
                        CanvasChatView(session: session)
                            .environment(viewModel)
                    } else {
                        CanvasEmptyState(onNewConversation: { createAndSelectConversation() })
                            .environment(viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            #if os(macOS)
            if sidebarVisible {
                CanvasFloatingPanel(title: "Conversations") {
                    CanvasSidebarView(
                        sessions: sessions,
                        selectedConversationID: $viewModel.selectedConversationID,
                        onNewConversation: { createAndSelectConversation() }
                    )
                    .frame(width: 300)
                }
                .padding(.leading, 12)
                .padding(.top, 54)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if inspectorVisible {
                CanvasFloatingPanel(title: "Inspector") {
                    NeonToolInspector(
                        isVisible: $inspectorVisible,
                        toolExecution: $viewModel.activeToolExecution
                    )
                    .frame(width: 360, height: 520)
                }
                .padding(.trailing, 12)
                .padding(.top, 54)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.20), value: sidebarVisible)
        .animation(.easeInOut(duration: 0.20), value: inspectorVisible)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSettings = false }
                        }
                    }
                    #else
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                    #endif
                    .environmentObject(modelRegistry)
            }
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
        #if os(iOS)
        .sheet(isPresented: $sidebarSheetVisible) {
            NavigationStack {
                CanvasSidebarView(
                    sessions: sessions,
                    selectedConversationID: $viewModel.selectedConversationID,
                    onNewConversation: { createAndSelectConversation() }
                )
                .navigationTitle("Conversations")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { sidebarSheetVisible = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $inspectorSheetVisible) {
            NavigationStack {
                NeonToolInspector(
                    isVisible: $inspectorSheetVisible,
                    toolExecution: $viewModel.activeToolExecution
                )
                .navigationTitle("Inspector")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { inspectorSheetVisible = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        .onAppear {
            ensureDefaultSelection()
            ensureDefaultConversationSelection()
        }
        .onChange(of: viewModel.selectedConversationID) { _, newValue in
            guard let id = newValue, let session = sessions.first(where: { $0.id == id }) else { return }
            hydrateSelection(from: session)
        }
        .onChange(of: sessions.count) { _, _ in
            ensureDefaultConversationSelection()
        }
    }

    private var selectedSession: ChatSessionEntity? {
        guard let id = viewModel.selectedConversationID else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                #if os(iOS)
                sidebarSheetVisible = true
                #else
                sidebarVisible.toggle()
                #endif
            } label: {
                Image(systemName: "sidebar.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)

            if let session = selectedSession {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text("\(displayProviderName(session.providerID)) / \(session.model)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textTertiary)
                        .lineLimit(1)
                }
            } else {
                Text("llmHub")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }

            Spacer()

            CanvasModelMenu(
                modelRegistry: modelRegistry,
                selectedProvider: $viewModel.selectedProvider,
                selectedModel: $viewModel.selectedModel,
                onSelectionChange: { providerID, modelID in
                    if let session = selectedSession {
                        persistSessionModel(session: session, providerID: providerID, modelID: modelID)
                    }
                }
            )

            Button {
                #if os(iOS)
                inspectorSheetVisible = true
                #else
                inspectorVisible.toggle()
                #endif
            } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: AppColors.cornerRadius, style: .continuous)
                .fill(AppColors.backgroundSecondary.opacity(0.65))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppColors.cornerRadius, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: AppColors.borderWidth)
        }
    }

    private func ensureDefaultSelection() {
        guard viewModel.selectedProvider == nil || viewModel.selectedModel == nil else { return }

        let providers = modelRegistry.availableProviders()
        if let firstProviderID = providers.first,
            let firstModel = modelRegistry.models(for: firstProviderID).first
        {
            let uiProvider = CanvasModelMenu.makeProvider(
                providerID: firstProviderID,
                models: modelRegistry.models(for: firstProviderID)
            )
            viewModel.selectedProvider = uiProvider
            viewModel.selectedModel = CanvasModelMenu.makeModel(firstModel)
            return
        }

        // Fallback if ModelRegistry is empty (e.g. before async fetch completes)
        viewModel.selectedProvider = UILLMProvider(
            id: UUID(),
            name: "OpenAI",
            icon: "sparkles",
            models: [UILLMModel(id: UUID(), modelID: "gpt-4o", name: "GPT-4o", contextWindow: 128_000)],
            isActive: true
        )
        viewModel.selectedModel = viewModel.selectedProvider?.models.first
    }

    private func ensureDefaultConversationSelection() {
        if viewModel.selectedConversationID == nil, let first = sessions.first {
            viewModel.selectedConversationID = first.id
        }
    }

    private func createAndSelectConversation() {
        viewModel.createNewConversation(modelContext: modelContext)
        try? modelContext.save()
    }

    private func hydrateSelection(from session: ChatSessionEntity) {
        let canonicalProviderID = ProviderID.canonicalID(from: session.providerID)
        let models = modelRegistry.models(for: canonicalProviderID)

        if let model = models.first(where: { $0.id == session.model }) {
            viewModel.selectedProvider = CanvasModelMenu.makeProvider(
                providerID: canonicalProviderID,
                models: models
            )
            viewModel.selectedModel = CanvasModelMenu.makeModel(model)
            return
        }

        // If the stored model is not a valid model ID (older sessions stored display names),
        // fall back to the first available model and persist the correction.
        if let firstModel = models.first {
            viewModel.selectedProvider = CanvasModelMenu.makeProvider(
                providerID: canonicalProviderID,
                models: models
            )
            viewModel.selectedModel = CanvasModelMenu.makeModel(firstModel)
            persistSessionModel(session: session, providerID: canonicalProviderID, modelID: firstModel.id)
            return
        }
    }

    private func persistSessionModel(session: ChatSessionEntity, providerID: String, modelID: String) {
        session.providerID = providerID
        session.model = modelID
        session.updatedAt = Date()
        try? modelContext.save()
    }

    private func displayProviderName(_ providerID: String) -> String {
        switch ProviderID.canonicalID(from: providerID) {
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        case "google": return "Google"
        case "mistral": return "Mistral"
        case "xai": return "xAI"
        case "openrouter": return "OpenRouter"
        default: return providerID
        }
    }
}

private struct CanvasEmptyState: View {
    let onNewConversation: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("No conversation selected")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Button("New Conversation") {
                onNewConversation()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CanvasSidebarView: View {
    let sessions: [ChatSessionEntity]
    @Binding var selectedConversationID: UUID?
    let onNewConversation: () -> Void

    @State private var searchText = ""

    private var filteredSessions: [ChatSessionEntity] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return sessions.filter { !$0.isArchived } }
        return sessions.filter { !$0.isArchived && $0.displayTitle.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Conversations")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Button {
                    onNewConversation()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.accent)
            }

            TextField("Search conversations…", text: $searchText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppColors.surface.opacity(0.9))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: AppColors.borderWidth)
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredSessions) { session in
                        Button {
                            selectedConversationID = session.id
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.displayTitle)
                                    .font(.system(size: 13, weight: selectedConversationID == session.id ? .semibold : .regular))
                                    .foregroundStyle(selectedConversationID == session.id ? AppColors.textPrimary : AppColors.textSecondary)
                                    .lineLimit(1)
                                Text(session.updatedAt, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedConversationID == session.id ? AppColors.surface.opacity(0.92) : Color.clear)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(2)
    }
}

private struct CanvasModelMenu: View {
    let modelRegistry: ModelRegistry
    @Binding var selectedProvider: UILLMProvider?
    @Binding var selectedModel: UILLMModel?
    let onSelectionChange: (_ providerID: String, _ modelID: String) -> Void

    var body: some View {
        Menu {
            let providers = modelRegistry.availableProviders()
            if providers.isEmpty {
                Text("No providers loaded")
            } else {
                ForEach(providers, id: \.self) { providerID in
                    Menu(title(for: providerID)) {
                        let models = modelRegistry.models(for: providerID)
                        if models.isEmpty {
                            Text("No models")
                        } else {
                            ForEach(models, id: \.id) { model in
                                Button {
                                    let uiProvider = Self.makeProvider(providerID: providerID, models: models)
                                    selectedProvider = uiProvider
                                    selectedModel = Self.makeModel(model)
                                    onSelectionChange(providerID, model.id)
                                } label: {
                                    Text(model.displayName)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedModel?.name ?? "Choose model")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppColors.surface.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: AppColors.borderWidth)
            }
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #endif
    }

    private func title(for providerID: String) -> String {
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

    static func makeProvider(providerID: String, models: [LLMModel]) -> UILLMProvider {
        let uiModels = models.map { makeModel($0) }
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
        return UILLMProvider(id: UUID(), name: titleStatic(for: providerID), icon: icon, models: uiModels, isActive: true)
    }

    static func makeModel(_ model: LLMModel) -> UILLMModel {
        UILLMModel(id: UUID(), modelID: model.id, name: model.displayName, contextWindow: model.contextWindow)
    }

    private static func titleStatic(for providerID: String) -> String {
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
}
