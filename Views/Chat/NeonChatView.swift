//
//  NeonChatView.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftData
import SwiftUI

struct NeonChatView: View {
    let session: ChatSessionEntity
    @Environment(WorkbenchViewModel.self) private var workbenchVM
    @Environment(\.modelContext) private var modelContext
    @State private var chatVM = ChatViewModel()

    @State private var scrollOffset: CGFloat = 0
    @Namespace private var toolAnimation

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Dynamic Toolbar
            NeonToolbar(
                session: session,
                selectedProvider: Bindable(workbenchVM).selectedProvider,
                selectedModel: Bindable(workbenchVM).selectedModel,
                scrollOffset: scrollOffset,
                toolInspectorVisible: Bindable(workbenchVM).toolInspectorVisible
            )

            // MARK: - Messages Area
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(session.messages) { message in
                        NeonMessageBubble(message: message)
                    }
                }
                .padding(20)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: NeonScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(NeonScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }

            Divider()
                .background(Color.neonGray.opacity(0.2))

            // MARK: - Chat Input
            NeonChatInput(
                messageText: $chatVM.messageText,
                toolsEnabled: $chatVM.toolsEnabled,
                availableTools: chatVM.availableTools,
                toolAnimation: toolAnimation,
                onSend: {
                    chatVM.sendMessage(session: session, modelContext: modelContext)
                },
                onToolTrigger: { tool in
                    chatVM.triggerTool(tool, workbenchVM: workbenchVM)
                }
            )
        }
        .background(Color.neonMidnight)
    }
}

// MARK: - Preference Keys

struct NeonScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
