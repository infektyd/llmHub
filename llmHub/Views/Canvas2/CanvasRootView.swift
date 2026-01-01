//
//  CanvasRootView.swift
//  llmHub
//
//  Canvas-first UI root (Claude desktop style)
//  No glass effects, flat matte surfaces, floating sidebars
//

import SwiftData
import SwiftUI

/// Root view for the canvas-based UI
/// Layout: ZStack with canvas background, center transcript, overlay sidebars, bottom composer
struct CanvasRootView: View {
    @State private var viewModel = WorkbenchViewModel()
    @State private var chatVM = ChatViewModel()

    @EnvironmentObject private var modelRegistry: ModelRegistry
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse)
    private var sessions: [ChatSessionEntity]

    @State private var leftSidebarVisible: Bool = true
    @State private var rightSidebarVisible: Bool = false
    @State private var showSettings: Bool = false

    var body: some View {
        ZStack {
            // Canvas background (flat matte)
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            // Center: Transcript canvas
            VStack(spacing: 0) {
                if let session = selectedSession {
                    TranscriptCanvasView(session: session)
                        .environment(viewModel)
                        .environment(chatVM)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Overlay left: Floating sidebar (chat threads)
            if leftSidebarVisible {
                FloatingSidebarLeft(
                    sessions: sessions,
                    selectedConversationID: $viewModel.selectedConversationID,
                    onNewConversation: createAndSelectConversation
                )
                .frame(width: 280)
                .padding(.leading, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(100)
            }

            // Overlay right: Floating sidebar (inspector)
            if rightSidebarVisible {
                FloatingSidebarRight(
                    isVisible: $rightSidebarVisible,
                    toolExecution: $viewModel.activeToolExecution
                )
                .frame(width: 320)
                .padding(.trailing, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(100)
            }

            // Bottom overlay: Composer bar
            ComposerBar(
                leftSidebarVisible: $leftSidebarVisible,
                rightSidebarVisible: $rightSidebarVisible,
                showSettings: $showSettings,
                selectedSession: selectedSession,
                modelRegistry: modelRegistry,
                viewModel: viewModel
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.easeInOut(duration: 0.2), value: leftSidebarVisible)
        .animation(.easeInOut(duration: 0.2), value: rightSidebarVisible)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                    .environmentObject(modelRegistry)
            }
        }
        .onAppear {
            print("DEBUG: CanvasRootView chatVM ID: \(ObjectIdentifier(chatVM))")
            ensureDefaultConversationSelection()
        }
        .onChange(of: viewModel.selectedConversationID) { _, newValue in
            guard let id = newValue, let session = sessions.first(where: { $0.id == id }) else {
                return
            }
            hydrateSelection(from: session)
        }
        .onChange(of: sessions.count) { _, _ in
            ensureDefaultConversationSelection()
        }
    }

    // MARK: - Private Computed Properties

    private var selectedSession: ChatSessionEntity? {
        guard let id = viewModel.selectedConversationID else { return nil }
        return sessions.first(where: { $0.id == id })
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("No conversation selected")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
            Button("New Conversation") {
                createAndSelectConversation()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)

            // wrappers for debug
            /*
            Button("Debug: Seed Fake Transcript") {
                seedFakeTranscript()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.gray)
            */

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Debug/Verification Helper
    // Uncomment call in emptyState to enable
    private func seedFakeTranscript() {
        print("DEBUG: Seeding fake transcript")
        let session = ChatSession(
            id: UUID(),
            title: "Debug Session",
            providerID: "openai",
            model: "gpt-4o",
            createdAt: Date(),
            updatedAt: Date(),
            messages: [],
            metadata: ChatSessionMetadata(
                lastTokenUsage: nil, totalCostUSD: .zero, referenceID: "debug")
        )
        let sessionEntity = ChatSessionEntity(session: session)
        modelContext.insert(sessionEntity)

        let msg1 = ChatMessage(
            id: UUID(),
            role: .user,
            content: "Hello, can you help me test the UI?",
            thoughtProcess: nil,
            parts: [.text("Hello, can you help me test the UI?")],
            createdAt: Date().addingTimeInterval(-60),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil
        )

        let msg2 = ChatMessage(
            id: UUID(),
            role: .assistant,
            content:
                "Certainly! I can regenerate this response to test streaming, or you can add artifacts.",
            thoughtProcess: nil,
            parts: [
                .text(
                    "Certainly! I can regenerate this response to test streaming, or you can add artifacts."
                )
            ],
            createdAt: Date().addingTimeInterval(-30),
            codeBlocks: [],
            tokenUsage: nil,
            costBreakdown: nil
        )

        let ent1 = ChatMessageEntity(message: msg1)
        ent1.session = sessionEntity
        let ent2 = ChatMessageEntity(message: msg2)
        ent2.session = sessionEntity

        modelContext.insert(ent1)
        modelContext.insert(ent2)
        try? modelContext.save()

        viewModel.selectedConversationID = sessionEntity.id
    }

    // MARK: - Private Methods

    private func createAndSelectConversation() {
        viewModel.createNewConversation(modelContext: modelContext)
        try? modelContext.save()
    }

    private func ensureDefaultConversationSelection() {
        if viewModel.selectedConversationID == nil, let first = sessions.first {
            viewModel.selectedConversationID = first.id
        }
    }

    private func hydrateSelection(from session: ChatSessionEntity) {
        let canonicalProviderID = ProviderID.canonicalID(from: session.providerID)
        let models = modelRegistry.models(for: canonicalProviderID)

        if let model = models.first(where: { $0.id == session.model }) {
            viewModel.selectedProvider = makeProvider(
                providerID: canonicalProviderID, models: models)
            viewModel.selectedModel = makeModel(model)
            return
        }

        // Fallback
        if let firstModel = models.first {
            viewModel.selectedProvider = makeProvider(
                providerID: canonicalProviderID, models: models)
            viewModel.selectedModel = makeModel(firstModel)
        }
    }

    private func makeProvider(providerID: String, models: [LLMModel]) -> UILLMProvider {
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
        let name = titleFor(providerID)
        return UILLMProvider(id: UUID(), name: name, icon: icon, models: uiModels, isActive: true)
    }

    private func makeModel(_ model: LLMModel) -> UILLMModel {
        UILLMModel(
            id: UUID(), modelID: model.id, name: model.displayName,
            contextWindow: model.contextWindow)
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
}
