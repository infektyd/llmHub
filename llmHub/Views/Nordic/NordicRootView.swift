//
//  NordicRootView.swift
//  llmHub
//
//  Main entry point for Nordic UI mode.
//  ZERO .glassEffect() calls - fully compatible with View Hierarchy Debugger.
//

import SwiftData
import SwiftUI

/// Root view for Nordic UI mode - completely separate from Neon/Glass UI
struct NordicRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var modelRegistry: ModelRegistry

    @Query(sort: \ChatSessionEntity.updatedAt, order: .reverse)
    private var sessions: [ChatSessionEntity]

    @State private var selectedSession: ChatSessionEntity?
    @State private var sidebarViewModel = SidebarViewModel()
    @State private var workbenchViewModel: WorkbenchViewModel?

    var body: some View {
        ZStack(alignment: .leading) {
            // Z-0: Continuous background (edge-to-edge)
            NordicColors.canvas(colorScheme)
                .ignoresSafeArea()

            // Content layers on top
            HStack(spacing: 0) {
                // Z-2: Sidebar as raised panel with shadow
                NordicSidebarView(
                    sessions: sessions,
                    selectedSession: $selectedSession,
                    viewModel: sidebarViewModel
                )
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                .background(
                    Rectangle()
                        .fill(NordicColors.surface(colorScheme))
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.16 : 0.08),
                            radius: 8,
                            x: 2,
                            y: 0
                        )
                )

                // Z-1: Chat area - NO background, content sits on canvas
                Group {
                    if let session = selectedSession {
                        NordicChatContainerView(
                            session: session,
                            workbenchViewModel: workbenchViewModel
                                ?? createWorkbenchViewModel(for: session)
                        )
                    } else {
                        NordicWelcomeView()
                    }
                }
            }
        }
        .onChange(of: selectedSession) { _, newSession in
            if let session = newSession {
                workbenchViewModel = createWorkbenchViewModel(for: session)
            }
        }
    }

    private func createWorkbenchViewModel(for session: ChatSessionEntity) -> WorkbenchViewModel {
        let viewModel = WorkbenchViewModel()
        viewModel.selectedConversationID = session.id
        return viewModel
    }
}

// MARK: - Nordic Sidebar View

/// Sidebar for Nordic theme showing conversation list
struct NordicSidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext

    let sessions: [ChatSessionEntity]
    @Binding var selectedSession: ChatSessionEntity?
    @State var viewModel: SidebarViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader

            // Divider
            Rectangle()
                .fill(NordicColors.border(colorScheme))
                .frame(height: 1)

            // Session list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(sessions.filter { !$0.isArchived }) { session in
                        NordicSessionRow(
                            session: session,
                            isSelected: selectedSession?.id == session.id
                        ) {
                            selectedSession = session
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
            }
        }
        // NO .background() - applied in NordicRootView as raised panel
    }

    private var sidebarHeader: some View {
        VStack(spacing: 12) {
            // Title
            HStack {
                Text("Conversations")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(NordicColors.textPrimary(colorScheme))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // New Chat button
            Button(action: createNewChat) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .medium))
                    Text("New Chat")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(NordicColors.accentSecondary(colorScheme))
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func createNewChat() {
        let newSession = ChatSessionEntity(
            session: ChatSession(
                id: UUID(),
                title: "New Chat",
                providerID: "openai",
                model: "gpt-4",
                createdAt: Date(),
                updatedAt: Date(),
                messages: [],
                metadata: ChatSessionMetadata(
                    lastTokenUsage: nil,
                    totalCostUSD: 0,
                    referenceID: UUID().uuidString
                )
            )
        )
        modelContext.insert(newSession)
        try? modelContext.save()
        selectedSession = newSession
    }
}

// MARK: - Nordic Session Row

/// Individual session row in the sidebar
struct NordicSessionRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: ChatSessionEntity
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(session.displayTitle)
                    .font(.system(size: 14, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : NordicColors.textPrimary(colorScheme))
                    .lineLimit(1)

                // Metadata
                if let category = session.afmCategory {
                    Text(category.capitalized)
                        .font(.system(size: 11))
                        .foregroundColor(
                            isSelected ? .white.opacity(0.8) : NordicColors.textMuted(colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected {
            return NordicColors.accentSecondary(colorScheme)
        }
        if isHovered {
            return colorScheme == .dark ? Color(hex: "292524") : Color(hex: "E7E5E4")
        }
        return .clear
    }
}

// MARK: - Nordic Chat Container

/// Container for the chat view with a specific session
struct NordicChatContainerView: View {
    @Environment(\.colorScheme) private var colorScheme

    let session: ChatSessionEntity
    var workbenchViewModel: WorkbenchViewModel

    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Divider
            Rectangle()
                .fill(NordicColors.border(colorScheme))
                .frame(height: 1)

            // Messages
            messagesArea

            // Input bar
            NordicInputBar(
                text: $inputText,
                onSend: {
                    Task {
                        await sendMessage()
                    }
                }
            )
        }
        // NO .background() - transparent, shows canvas
    }

    private func sendMessage() async {
        // TODO: Implement actual message sending logic
        print("Sending message: \(inputText)")
        inputText = ""
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(NordicColors.textPrimary(colorScheme))

                if let model = workbenchViewModel.selectedModel {
                    Text(model.name)
                        .font(.system(size: 12))
                        .foregroundColor(NordicColors.textSecondary(colorScheme))
                }
            }

            Spacer()

            // Settings button
            #if os(macOS)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(NordicColors.textSecondary(colorScheme))
            }
            .buttonStyle(.plain)
            .help("Settings")
            #endif

            // Nordic theme indicator
            Text("Nordic")
                .font(.system(size: 11))
                .foregroundColor(NordicColors.textMuted(colorScheme))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(NordicColors.surface(colorScheme))
                        .overlay(
                            Capsule()
                                .stroke(NordicColors.border(colorScheme), lineWidth: 1)
                        )
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        // NO .background() - transparent, shows canvas
    }

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(session.messages) { message in
                        NordicMessageRow(
                            message: message.asDomain()
                        )
                        .id(message.id)
                    }

                    // TODO: Add streaming message support
                    // if !streamingText.isEmpty {
                    //     NordicStreamingMessage(text: streamingText)
                    // }
                }
                .padding(.vertical, 16)
            }
        }
    }
}

// MARK: - Nordic Streaming Message

/// Displays a streaming assistant message
struct NordicStreamingMessage: View {
    @Environment(\.colorScheme) private var colorScheme

    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(NordicColors.accentSecondary(colorScheme))
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    // Content with cursor - NO background
                    HStack(spacing: 4) {
                        Text(text)
                            .font(.system(size: 15))
                            .foregroundColor(NordicColors.textPrimary(colorScheme))
                            .textSelection(.enabled)

                        // Blinking cursor
                        Text("▊")
                            .font(.system(size: 15))
                            .foregroundColor(NordicColors.accentSecondary(colorScheme))
                            .opacity(0.7)
                    }
                }
            }
            // NO .background() — text floats on canvas

            Spacer(minLength: 80)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}
