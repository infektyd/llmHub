//
//  NeonWorkbenchWindow.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftData
import SwiftUI

struct NeonWorkbenchWindow: View {
    @State private var viewModel = WorkbenchViewModel()
    @EnvironmentObject private var modelRegistry: ModelRegistry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.theme) private var theme
    @Query private var sessions: [ChatSessionEntity]
    @AppStorage("windowBackgroundOpacity") private var windowBackgroundOpacity: Double = 1.0
    @State private var preferredColumn: NavigationSplitViewColumn = .sidebar

    var body: some View {
        #if os(iOS)
            iosLayout
        #else
            macosLayout
        #endif
    }

    // MARK: - iOS Layout (2-column)

    /// iOS layout with 2-column NavigationSplitView.
    /// On iPhone, tapping a conversation pushes to the detail view.
    /// Tool inspector is presented as a sheet.
    @ViewBuilder
    private var iosLayout: some View {
        #if os(iOS)
            NavigationSplitView(
                columnVisibility: $viewModel.columnVisibility,
                preferredCompactColumn: $preferredColumn
            ) {
                // Sidebar (Conversation History)
                NeonSidebar()
                    .environment(viewModel)
                    .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)
            } detail: {
                // Detail (Chat View or Welcome)
                contentView
            }
            .navigationSplitViewStyle(.balanced)
            .background(LiquidFieldBackground(opacity: windowBackgroundOpacity))
            .safeAreaInset(edge: .bottom) {
                if viewModel.selectedConversationID != nil {
                    statusBar
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .onChange(of: viewModel.selectedConversationID) { oldValue, newValue in
                print(
                    "🟣 NAVIGATION: [iOS] selectedConversationID changed in view: \(String(describing: oldValue)) → \(String(describing: newValue))"
                )

                // Push to detail view on iPhone when conversation selected
                if newValue != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        preferredColumn = .detail
                    }
                    print("🟣 NAVIGATION: [iOS] Switching to detail column")
                } else {
                    // Return to sidebar when selection cleared
                    withAnimation(.easeInOut(duration: 0.3)) {
                        preferredColumn = .sidebar
                    }
                    print("🟣 NAVIGATION: [iOS] Switching to sidebar column")
                }
            }
            .onChange(of: viewModel.columnVisibility) { oldValue, newValue in
                print("🟠 VISIBILITY: [iOS] columnVisibility changed: \(oldValue) → \(newValue)")
            }
            .sheet(isPresented: $viewModel.toolInspectorVisible) {
                NeonToolInspector(
                    isVisible: $viewModel.toolInspectorVisible,
                    toolExecution: $viewModel.activeToolExecution
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .onAppear {
                print("🟣 NAVIGATION: [iOS] NeonWorkbenchWindow appeared")

                // Initialize model selection from ModelRegistry if not set
                if viewModel.selectedProvider == nil || viewModel.selectedModel == nil {
                    initializeDefaultModel()
                }

                // Set default selection if none
                if viewModel.selectedConversationID == nil, let first = sessions.first {
                    print(
                        "🟣 NAVIGATION: [iOS] Setting default selection to first session: \(first.id)"
                    )
                    viewModel.selectedConversationID = first.id
                }
            }
        #endif
    }

    // MARK: - macOS Layout (3-column)

    /// macOS layout with 3-column NavigationSplitView.
    /// Sidebar | Content | Tool Inspector (when visible)
    private var macosLayout: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            // MARK: - Sidebar (Conversation History)
            NeonSidebar()
                .environment(viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)

        } content: {
            // MARK: - Main Content (Chat View)
            contentView
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
                .safeAreaInset(edge: .bottom) {
                    if viewModel.selectedConversationID != nil {
                        statusBar
                            .padding(.bottom, 12)
                    }
                }

        } detail: {
            // MARK: - Tool Inspector (Adaptive Right Pane)
            if viewModel.toolInspectorVisible {
                NeonToolInspector(
                    isVisible: $viewModel.toolInspectorVisible,
                    toolExecution: $viewModel.activeToolExecution
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .background(LiquidFieldBackground(opacity: windowBackgroundOpacity))
        #if os(macOS)
            .transparentWindow(opacity: $windowBackgroundOpacity)
        #endif
        .onChange(of: viewModel.selectedConversationID) { oldValue, newValue in
            print(
                "🟣 NAVIGATION: [macOS] selectedConversationID changed in view: \(String(describing: oldValue)) → \(String(describing: newValue))"
            )
        }
        .onChange(of: viewModel.columnVisibility) { oldValue, newValue in
            print("🟠 VISIBILITY: [macOS] columnVisibility changed: \(oldValue) → \(newValue)")
        }
        .onAppear {
            print("🟣 NAVIGATION: [macOS] NeonWorkbenchWindow appeared")

            // Initialize model selection from ModelRegistry if not set
            if viewModel.selectedProvider == nil || viewModel.selectedModel == nil {
                initializeDefaultModel()
            }

            // Set default selection if none
            if viewModel.selectedConversationID == nil, let first = sessions.first {
                print(
                    "🟣 NAVIGATION: [macOS] Setting default selection to first session: \(first.id)")
                viewModel.selectedConversationID = first.id
            }
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var contentView: some View {
        if let conversationID = viewModel.selectedConversationID,
            let session = sessions.first(where: { $0.id == conversationID })
        {
            let _ = print(
                "🟣 NAVIGATION: Rendering NeonChatView for session: \(session.id)")
            NeonChatView(session: session)
                .environment(viewModel)
                .onChange(of: session.messages) { _, _ in
                    print("RENDER: Messages changed, updating stats for \(session.id)")
                    viewModel.updateStats(for: session)
                }
                .onAppear {
                    viewModel.updateStats(for: session)
                }
        } else {
            NeonWelcomeView()
                .environment(viewModel)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label {
                Text("\(viewModel.currentSessionTokens)")
                    .font(.caption2.weight(.medium))
            } icon: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.caption2)
            }

            Divider().frame(height: 12)

            Label {
                Text(String(format: "%.1f%% used", viewModel.tokenPercentage))
                    .font(.caption2.weight(.medium))
            } icon: {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.caption2)
            }

            Divider().frame(height: 12)

            Label {
                Text(String(format: "$%.2f", NSDecimalNumber(decimal: viewModel.currentSessionCost).doubleValue))
                    .font(.caption2.weight(.medium))
            } icon: {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.caption2)
            }
        }
        .foregroundColor(theme.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(GlassEffect.regular, in: Capsule())
    }

    // MARK: - Helper Methods

    /// Initializes the default provider and model from ModelRegistry.
    private func initializeDefaultModel() {
        let providers = modelRegistry.availableProviders()
        guard !providers.isEmpty else {
            print("🟡 MODEL INIT: No providers available in ModelRegistry")
            return
        }

        let firstProviderID = providers[0]
        let models = modelRegistry.models(for: firstProviderID)
        guard let firstModel = models.first else {
            print("🟡 MODEL INIT: No models found for provider \(firstProviderID)")
            return
        }

        // Create UILLMProvider and UILLMModel using stable UUIDs
        let uiModels = models.map { model in
            UILLMModel(
                id: stableUUID(for: model.id),
                modelID: model.id,
                name: model.displayName,
                contextWindow: model.contextWindow
            )
        }

        viewModel.selectedProvider = UILLMProvider(
            id: stableUUID(for: firstProviderID),
            name: providerDisplayName(for: firstProviderID),
            icon: providerIcon(for: firstProviderID),
            models: uiModels,
            isActive: true
        )

        viewModel.selectedModel = UILLMModel(
            id: stableUUID(for: firstModel.id),
            modelID: firstModel.id,
            name: firstModel.displayName,
            contextWindow: firstModel.contextWindow
        )

        print(
            "🟢 MODEL INIT: Set default provider: \(firstProviderID), model: \(firstModel.displayName) (\(firstModel.id))"
        )
    }
}
