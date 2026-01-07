//
//  CanvasRootView.swift
//  llmHub
//
//  Canvas-first UI root (Claude desktop style)
//  No glass effects, flat matte surfaces, floating sidebars
//

import SwiftData
import SwiftUI

// Root view for the canvas-based UI.
// Layout: ZStack with canvas background, center transcript, overlay sidebars, bottom composer.
// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
struct CanvasRootView: View {
    @State private var viewModel: WorkbenchViewModel
    @State private var chatVM: ChatViewModel

    @EnvironmentObject private var modelRegistry: ModelRegistry
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse)
    private var sessions: [ChatSessionEntity]

    @Query(sort: \ChatFolderEntity.orderIndex, order: .forward)
    private var folders: [ChatFolderEntity]

    @State private var leftSidebarVisible: Bool
    @State private var rightSidebarVisible: Bool
    @State private var showSettings: Bool = false
    @State private var composerHeight: CGFloat = 100  // Measured dynamically

    init(
        viewModel: WorkbenchViewModel = WorkbenchViewModel(),
        chatVM: ChatViewModel = ChatViewModel(),
        leftSidebarVisible: Bool = true,
        rightSidebarVisible: Bool = false
    ) {
        _viewModel = State(initialValue: viewModel)
        _chatVM = State(initialValue: chatVM)
        _leftSidebarVisible = State(initialValue: leftSidebarVisible)
        _rightSidebarVisible = State(initialValue: rightSidebarVisible)
    }

    var body: some View {
        ZStack {
            // Canvas background (flat matte)
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            // Center: Transcript canvas
            VStack(spacing: 0) {
                if let session = selectedSession {
                    ChatHeaderBar(
                        title: Binding(
                            get: { session.displayTitle },
                            set: {
                                session.title = $0
                                session.afmTitle = nil
                                try? modelContext.save()
                            }
                        ),
                        selectedProviderID: Binding(
                            get: { session.providerID },
                            set: {
                                session.providerID = $0
                                hydrateSelection(from: session)
                                try? modelContext.save()
                            }
                        ),
                        selectedModelID: Binding(
                            get: { session.model },
                            set: {
                                session.model = $0
                                hydrateSelection(from: session)
                                try? modelContext.save()
                            }
                        ),
                        leftSidebarVisible: $leftSidebarVisible
                    )
                    .environmentObject(modelRegistry)

                    TranscriptCanvasSessionView(session: session)
                        .environment(viewModel)
                        .environment(\.composerHeight, composerHeight)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tap-to-dismiss layer: click canvas to collapse the left sidebar.
            // Excludes both sidebar regions so their controls remain interactive.
            if leftSidebarVisible {
                Color.clear
                    .contentShape(Rectangle())
                    .padding(.leading, 352)  // 320 sidebar + ~padding
                    .padding(.trailing, rightSidebarVisible ? 352 : 0)
                    .onTapGesture {
                        withAnimation {
                            leftSidebarVisible = false
                        }
                    }
                    .ignoresSafeArea()
            }

            // Overlay left: Floating sidebar (chat threads)
            if leftSidebarVisible {
                ModernSidebarLeft(
                    isVisible: $leftSidebarVisible,
                    rightSidebarVisible: $rightSidebarVisible,
                    sessions: sessions,
                    folders: folders,
                    selectedConversationID: $viewModel.selectedConversationID,
                    onNewConversation: createAndSelectConversation
                )
                .frame(width: 320)
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
                    state: inspectorState
                )
                .frame(width: 320)
                .padding(.trailing, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(100)
            }

            VStack(spacing: 0) {
                Spacer(minLength: 0)

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
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ComposerHeightPreferenceKey.self,
                                value: geo.size.height
                            )
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

#if os(macOS)
            if showSettings {
                SettingsOverlay(
                    isPresented: $showSettings,
                    modelRegistry: modelRegistry
                )
                .zIndex(1000)
            }
#endif
        }
        .onPreferenceChange(ComposerHeightPreferenceKey.self) { height in
            guard abs(composerHeight - height) > 0.5 else { return }
            composerHeight = height
        }
        // Rationale: ChatViewModel is owned once at the CanvasRootView level and must be available
        // throughout the canvas UI tree (composer, transcript, diagnostics) via SwiftUI's
        // @Environment(ChatViewModel.self) injection.
        .environment(chatVM)
        .animation(.easeInOut(duration: 0.2), value: leftSidebarVisible)
        .animation(.easeInOut(duration: 0.2), value: rightSidebarVisible)
#if !os(macOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                showSettings = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                        }

                        ToolbarItem(placement: .primaryAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                    .environmentObject(modelRegistry)
            }
        }
#endif
        .onAppear {
            print("DEBUG: CanvasRootView chatVM ID: \(ObjectIdentifier(chatVM))")
            ensureDefaultConversationSelection()
        }
        .onChange(of: viewModel.selectedConversationID) { _, newValue in
            guard let id = newValue, let session = sessions.first(where: { $0.id == id }) else {
                return
            }
            hydrateSelection(from: session)
            if !PreviewMode.isRunning {
                viewModel.updateStats(for: session)
            }
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

            // Debug helpers
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
            contextWindow: model.contextWindow,
            maxOutputTokens: model.maxOutputTokens,
            supportsToolUse: model.supportsToolUse
        )
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

    private var inspectorState: CanvasInspectorState {
        guard let session = selectedSession else { return .empty() }

        let artifacts: [ArtifactPayload] =
            session.messages
            .sorted { $0.createdAt < $1.createdAt }
            .flatMap { entity -> [ArtifactPayload] in
                let message = entity.asDomain()
                return message.artifactMetadatas.map { meta in
                    ArtifactPayload(
                        id: Canvas2StableIDs.artifactID(messageID: message.id, metadata: meta),
                        title: meta.filename,
                        kind: {
                            switch meta.language {
                            case .json, .swift, .python, .javascript: return .code
                            case .markdown, .text: return .text
                            }
                        }(),
                        status: .success,
                        previewText: meta.content,
                        actions: [.copy, .open],
                        metadata: [
                            "filename": meta.filename,
                            "language": meta.language.rawValue,
                            "sizeBytes": "\(meta.sizeBytes)"
                        ]
                    )
                }
            }

        let logs: [String] = [
            "isGenerating=\(chatVM.isGenerating)",
            "executingTools=\(chatVM.executingToolNames.sorted().joined(separator: ","))",
            "streamingTokenEstimate=\(chatVM.streamingTokenEstimate)",
            "isTruncated=\(chatVM.isTruncated)"
        ]

        let contextSummary: [String] = [
            "providerID=\(session.providerID)",
            "model=\(session.model)",
            "messages=\(session.messages.count)"
        ]

        let tokenStats = CanvasInspectorState.TokenStats(
            tokens: viewModel.currentSessionTokens,
            costUSD: viewModel.currentSessionCost,
            percentOfContext: viewModel.tokenPercentage
        )

        return CanvasInspectorState(
            toolExecution: viewModel.activeToolExecution,
            artifacts: artifacts,
            tokenStats: tokenStats,
            logs: logs,
            contextSummary: contextSummary
        )
    }
}
    #if os(macOS)
    private struct SettingsOverlay: View {
        @Binding var isPresented: Bool
        let modelRegistry: ModelRegistry

        var body: some View {
            ZStack {
                AppColors.shadowSmoke
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isPresented = false
                    }

                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Settings")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)

                        Spacer()

                        Button {
                            isPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close Settings")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppColors.backgroundSecondary)

                    Divider()

                    SettingsView()
                        .environmentObject(modelRegistry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 920, height: 640)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.backgroundPrimary)
                        .shadow(color: AppColors.shadowSmoke, radius: 18, x: 0, y: 4)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
                }
                .onTapGesture { }
                .onExitCommand {
                    isPresented = false
                }
                .accessibilityAddTraits(.isModal)
            }
        }
    }
    #endif

#if DEBUG
    #Preview("CanvasRoot • Wide") {
        let container = PreviewContainer.shared
        Canvas2PreviewFixtures.ensureSeeded(into: container.context)

        return CanvasRootView(chatVM: ChatViewModel.preview())
            .environmentObject(ModelRegistry())
            .modelContainer(container.container)
            .frame(width: 1200, height: 800)
    }

    #Preview("CanvasRoot • Compact") {
        let container = PreviewContainer.shared
        Canvas2PreviewFixtures.ensureSeeded(into: container.context)

        return CanvasRootView(
            chatVM: ChatViewModel.preview(),
            leftSidebarVisible: false,
            rightSidebarVisible: false
        )
        .environmentObject(ModelRegistry())
        .modelContainer(container.container)
        .frame(width: 520, height: 820)
    }

    #Preview("CanvasRoot • Streaming ON") {
        let container = PreviewContainer.shared
        Canvas2PreviewFixtures.ensureSeeded(into: container.context)

        let viewModel = ChatViewModel.preview(
            isGenerating: true,
            streamingText: Canvas2PreviewFixtures.streamingRow().content,
            generationID: Canvas2PreviewFixtures.IDs.streamingGeneration,
            streamingMessageID: Canvas2PreviewFixtures.IDs.streamingMessage
        )

        return CanvasRootView(chatVM: viewModel, leftSidebarVisible: true, rightSidebarVisible: true)
            .environmentObject(ModelRegistry())
            .modelContainer(container.container)
            .frame(width: 1200, height: 800)
    }

    #Preview("CanvasRoot • Sidebars Expanded") {
        let container = PreviewContainer.shared
        Canvas2PreviewFixtures.ensureSeeded(into: container.context)

        return CanvasRootView(
            chatVM: ChatViewModel.preview(),
            leftSidebarVisible: true,
            rightSidebarVisible: true
        )
        .environmentObject(ModelRegistry())
        .modelContainer(container.container)
        .frame(width: 1200, height: 800)
    }
#endif
