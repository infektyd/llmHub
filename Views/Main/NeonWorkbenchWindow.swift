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
    @Environment(\.modelContext) private var modelContext
    @Query private var sessions: [ChatSessionEntity]

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            // MARK: - Sidebar (Conversation History)
            NeonSidebar()
                .environment(viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)

        } content: {
            // MARK: - Main Content (Chat View)
            if let conversationID = viewModel.selectedConversationID,
                let session = sessions.first(where: { $0.id == conversationID })
            {
                NeonChatView(session: session)
                    .environment(viewModel)
                    .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            } else {
                NeonWelcomeView()
                    .navigationSplitViewColumnWidth(min: 400, ideal: 600)
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
        .preferredColorScheme(.dark)
        .background(Color.neonMidnight)
        .onAppear {
            // Set default selection if none
            if viewModel.selectedConversationID == nil, let first = sessions.first {
                viewModel.selectedConversationID = first.id
            }
        }
    }
}
