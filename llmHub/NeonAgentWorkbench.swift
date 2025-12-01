//
//  NeonAgentWorkbench.swift
//  llmHub - Neon Agent Workbench
//
//  Complete single-file implementation of the Neon Agent Workbench UI
//  Featuring cyberpunk-inspired design with electric blue and fuchsia accents
//
//  Created for macOS 26.1+ (Tahoe) with Swift 6.2
//

import SwiftUI
import SwiftData

// MARK: - Color Palette

extension Color {
    /// Electric Blue (#00BFFF) - Active states, tool execution, success
    static let neonElectricBlue = Color(red: 0, green: 0.75, blue: 1.0)

    /// Fuchsia (#FF0066) - Critical alerts, primary selection
    static let neonFuchsia = Color(red: 1.0, green: 0, blue: 0.4)

    /// Deep Charcoal - Primary background
    static let neonCharcoal = Color(red: 0.12, green: 0.12, blue: 0.15)

    /// Midnight - Secondary background
    static let neonMidnight = Color(red: 0.08, green: 0.08, blue: 0.10)

    /// Subtle Gray - Text and borders
    static let neonGray = Color(red: 0.6, green: 0.6, blue: 0.65)
}

// MARK: - Sample Data Models

struct LLMProvider: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String
    let models: [LLMModel]
    var isActive: Bool

    static let sampleProviders: [LLMProvider] = [
        LLMProvider(
            id: UUID(),
            name: "Anthropic",
            icon: "brain.head.profile",
            models: [
                LLMModel(id: UUID(), name: "Claude 3.5 Sonnet", contextWindow: 200000),
                LLMModel(id: UUID(), name: "Claude 3 Opus", contextWindow: 200000),
                LLMModel(id: UUID(), name: "Claude 3 Haiku", contextWindow: 200000)
            ],
            isActive: true
        ),
        LLMProvider(
            id: UUID(),
            name: "OpenAI",
            icon: "sparkles",
            models: [
                LLMModel(id: UUID(), name: "GPT-4 Turbo", contextWindow: 128000),
                LLMModel(id: UUID(), name: "GPT-4", contextWindow: 8192),
                LLMModel(id: UUID(), name: "GPT-3.5 Turbo", contextWindow: 16385)
            ],
            isActive: false
        ),
        LLMProvider(
            id: UUID(),
            name: "Google",
            icon: "cloud.fill",
            models: [
                LLMModel(id: UUID(), name: "Gemini Pro", contextWindow: 32000),
                LLMModel(id: UUID(), name: "Gemini Ultra", contextWindow: 32000)
            ],
            isActive: false
        )
    ]
}

struct LLMModel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let contextWindow: Int
}

struct ConversationItem: Identifiable {
    let id: UUID
    var title: String
    let timestamp: Date
    var folderID: UUID?
    var tags: [ChatTag]
    var isPinned: Bool
    let messageCount: Int

    static let sampleConversations: [ConversationItem] = [
        ConversationItem(
            id: UUID(),
            title: "SwiftUI Animation Helpers",
            timestamp: Date().addingTimeInterval(-3600),
            tags: [ChatTag(id: UUID(), name: "Swift", color: "#FF0066")],
            isPinned: true,
            messageCount: 12
        ),
        ConversationItem(
            id: UUID(),
            title: "Database Schema Design",
            timestamp: Date().addingTimeInterval(-7200),
            tags: [ChatTag(id: UUID(), name: "SQL", color: "#00BFFF")],
            isPinned: false,
            messageCount: 8
        ),
        ConversationItem(
            id: UUID(),
            title: "API Integration Strategy",
            timestamp: Date().addingTimeInterval(-86400),
            tags: [],
            isPinned: false,
            messageCount: 15
        ),
        ConversationItem(
            id: UUID(),
            title: "Code Review: Auth Module",
            timestamp: Date().addingTimeInterval(-172800),
            tags: [ChatTag(id: UUID(), name: "Security", color: "#FFD700")],
            isPinned: false,
            messageCount: 6
        )
    ]
}

struct ToolExecution: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let status: ExecutionStatus
    let output: String
    let timestamp: Date

    enum ExecutionStatus {
        case pending
        case running
        case success
        case error

        var color: Color {
            switch self {
            case .pending: return .neonGray
            case .running: return .neonElectricBlue
            case .success: return .green
            case .error: return .neonFuchsia
            }
        }
    }
}

// MARK: - Main App Window

struct NeonAgentWorkbenchWindow: View {
    @State private var selectedConversation: ConversationItem.ID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var toolInspectorVisible = false
    @State private var selectedProvider: LLMProvider?
    @State private var selectedModel: LLMModel?
    @State private var conversations = ConversationItem.sampleConversations
    @State private var activeToolExecution: ToolExecution?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // MARK: - Sidebar (Conversation History)
            NeonAgentSidebar(
                conversations: $conversations,
                selectedConversation: $selectedConversation
            )
            .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 350)

        } content: {
            // MARK: - Main Content (Chat View)
            if let conversationID = selectedConversation,
               let conversation = conversations.first(where: { $0.id == conversationID }) {
                NeonChatView(
                    conversation: conversation,
                    toolInspectorVisible: $toolInspectorVisible,
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel,
                    activeToolExecution: $activeToolExecution
                )
                .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            } else {
                NeonWelcomeView()
                    .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            }

        } detail: {
            // MARK: - Tool Inspector (Adaptive Right Pane)
            if toolInspectorVisible {
                NeonToolInspector(
                    isVisible: $toolInspectorVisible,
                    toolExecution: $activeToolExecution
                )
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: 500)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .preferredColorScheme(.dark)
        .background(Color.neonMidnight)
        .onAppear {
            // Set default selection
            if selectedConversation == nil, let first = conversations.first {
                selectedConversation = first.id
            }

            // Set default provider and model
            if selectedProvider == nil {
                selectedProvider = LLMProvider.sampleProviders.first
                selectedModel = selectedProvider?.models.first
            }
        }
    }
}

// MARK: - Sidebar Component

struct NeonAgentSidebar: View {
    @Binding var conversations: [ConversationItem]
    @Binding var selectedConversation: ConversationItem.ID?
    @State private var searchText = ""
    @State private var expandedFolders: Set<UUID> = []

    var pinnedConversations: [ConversationItem] {
        conversations.filter { $0.isPinned }
    }

    var recentConversations: [ConversationItem] {
        conversations.filter { !$0.isPinned }.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with New Chat button
            HStack {
                Text("Conversations")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: { createNewConversation() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(.neonElectricBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.neonGray)
                    .font(.system(size: 14))

                TextField("Search conversations...", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.neonCharcoal.opacity(0.6))
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()
                .background(Color.neonGray.opacity(0.2))

            // Conversation List
            ScrollView {
                VStack(spacing: 0) {
                    // Pinned Section
                    if !pinnedConversations.isEmpty {
                        SectionHeader(title: "Pinned", icon: "pin.fill")

                        ForEach(pinnedConversations) { conversation in
                            ConversationRow(
                                conversation: conversation,
                                isSelected: selectedConversation == conversation.id
                            )
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedConversation = conversation.id
                                }
                            }
                        }

                        Divider()
                            .background(Color.neonGray.opacity(0.2))
                            .padding(.vertical, 8)
                    }

                    // Recent Section
                    SectionHeader(title: "Recent", icon: "clock.fill")

                    ForEach(recentConversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            isSelected: selectedConversation == conversation.id
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedConversation = conversation.id
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(
            // Blurred material background with low opacity
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay(Color.neonCharcoal.opacity(0.3))
        )
    }

    private func createNewConversation() {
        let newConversation = ConversationItem(
            id: UUID(),
            title: "New Conversation",
            timestamp: Date(),
            tags: [],
            isPinned: false,
            messageCount: 0
        )
        conversations.insert(newConversation, at: 0)
        selectedConversation = newConversation.id
    }
}

// MARK: - Sidebar Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.neonGray)

            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.neonGray)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: ConversationItem
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Conversation icon/indicator
            Circle()
                .fill(isSelected ? Color.neonFuchsia : Color.neonElectricBlue.opacity(0.3))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .neonGray)
                        .lineLimit(1)

                    if conversation.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.neonElectricBlue)
                    }

                    Spacer()

                    Text(timeAgo(from: conversation.timestamp))
                        .font(.system(size: 10))
                        .foregroundColor(.neonGray.opacity(0.7))
                }

                // Tags
                if !conversation.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(conversation.tags) { tag in
                            TagPill(tag: tag)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.neonCharcoal.opacity(0.8) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.neonFuchsia.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .padding(.horizontal, 8)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: ChatTag

    var tagColor: Color {
        Color(hex: tag.color) ?? .neonElectricBlue
    }

    var body: some View {
        Text(tag.name)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(tagColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tagColor.opacity(0.2))
                    .overlay(
                        Capsule()
                            .stroke(tagColor.opacity(0.5), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - Chat View

struct NeonChatView: View {
    let conversation: ConversationItem
    @Binding var toolInspectorVisible: Bool
    @Binding var selectedProvider: LLMProvider?
    @Binding var selectedModel: LLMModel?
    @Binding var activeToolExecution: ToolExecution?

    @State private var messageText = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var toolsEnabled = true
    @State private var availableTools: [ToolDefinition] = ToolDefinition.sampleTools
    @Namespace private var toolAnimation

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Dynamic Toolbar
            NeonToolbar(
                conversation: conversation,
                selectedProvider: $selectedProvider,
                selectedModel: $selectedModel,
                scrollOffset: scrollOffset,
                toolInspectorVisible: $toolInspectorVisible
            )

            // MARK: - Messages Area
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Sample messages
                    NeonMessageBubble(
                        role: .user,
                        content: "Can you help me implement a custom SwiftUI animation for a morphing button?"
                    )

                    NeonMessageBubble(
                        role: .assistant,
                        content: "I'd be happy to help you create a morphing button animation! Let me break this down into steps and show you how to implement it using SwiftUI's animation system.\n\nFirst, let's create the basic structure with a matchedGeometryEffect..."
                    )

                    NeonMessageBubble(
                        role: .user,
                        content: "That's great! Can you also show me how to add a spring animation?"
                    )
                }
                .padding(20)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }

            Divider()
                .background(Color.neonGray.opacity(0.2))

            // MARK: - Chat Input
            NeonChatInput(
                messageText: $messageText,
                toolsEnabled: $toolsEnabled,
                availableTools: availableTools,
                toolAnimation: toolAnimation,
                onSend: { sendMessage() },
                onToolTrigger: { tool in
                    triggerTool(tool)
                }
            )
        }
        .background(Color.neonMidnight)
    }

    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        // Handle message sending
        messageText = ""
    }

    private func triggerTool(_ tool: ToolDefinition) {
        // Simulate tool execution
        let execution = ToolExecution(
            id: UUID(),
            name: tool.name,
            icon: tool.icon,
            status: .running,
            output: "Executing \(tool.name)...",
            timestamp: Date()
        )
        activeToolExecution = execution
        toolInspectorVisible = true

        // Simulate completion after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            activeToolExecution = ToolExecution(
                id: execution.id,
                name: tool.name,
                icon: tool.icon,
                status: .success,
                output: "Successfully executed \(tool.name)\n\nResult: Sample output data...",
                timestamp: execution.timestamp
            )
        }
    }
}

// MARK: - Toolbar Component

struct NeonToolbar: View {
    let conversation: ConversationItem
    @Binding var selectedProvider: LLMProvider?
    @Binding var selectedModel: LLMModel?
    let scrollOffset: CGFloat
    @Binding var toolInspectorVisible: Bool

    private var toolbarOpacity: Double {
        // Fade toolbar when scrolling down
        let threshold: CGFloat = 50
        if scrollOffset > threshold {
            return 1.0
        } else if scrollOffset < -threshold {
            return 0.7
        } else {
            return 1.0 - (abs(scrollOffset) / threshold) * 0.3
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            // Conversation Title
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("\(conversation.messageCount) messages")
                    .font(.system(size: 11))
                    .foregroundColor(.neonGray)
            }

            Spacer()

            // Model Picker
            NeonModelPicker(
                selectedProvider: $selectedProvider,
                selectedModel: $selectedModel
            )

            // Tool Inspector Toggle
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    toolInspectorVisible.toggle()
                }
            }) {
                Image(systemName: toolInspectorVisible ? "sidebar.right.fill" : "sidebar.right")
                    .font(.system(size: 16))
                    .foregroundColor(toolInspectorVisible ? .neonElectricBlue : .neonGray)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.neonCharcoal.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial
                .opacity(toolbarOpacity)
        )
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.neonGray.opacity(0.2)),
            alignment: .bottom
        )
    }
}

// MARK: - Model Picker

struct NeonModelPicker: View {
    @Binding var selectedProvider: LLMProvider?
    @Binding var selectedModel: LLMModel?
    @State private var isExpanded = false

    var body: some View {
        Menu {
            ForEach(LLMProvider.sampleProviders) { provider in
                Menu {
                    ForEach(provider.models) { model in
                        Button(action: {
                            selectedProvider = provider
                            selectedModel = model
                        }) {
                            HStack {
                                Text(model.name)
                                if selectedModel?.id == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.neonFuchsia)
                                }
                            }
                        }
                    }
                } label: {
                    Label(provider.name, systemImage: provider.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let provider = selectedProvider {
                    Image(systemName: provider.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.neonElectricBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let provider = selectedProvider {
                        Text(provider.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.neonGray)
                    }
                    if let model = selectedModel {
                        Text(model.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.neonGray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.neonFuchsia.opacity(0.5), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message Bubble

struct NeonMessageBubble: View {
    let role: MessageRole
    let content: String

    var isUser: Bool {
        role == .user
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser {
                // AI Avatar
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.neonElectricBlue, .neonFuchsia],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                Text(content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.neonCharcoal.opacity(0.6) : Color.neonCharcoal.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        isUser ? Color.neonGray.opacity(0.2) : Color.neonElectricBlue.opacity(0.3),
                                        lineWidth: 1
                                    )
                            )
                    )
            }
            .frame(maxWidth: 600, alignment: isUser ? .trailing : .leading)

            if isUser {
                // User Avatar
                Circle()
                    .fill(Color.neonGray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.neonGray)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// MARK: - Chat Input

struct NeonChatInput: View {
    @Binding var messageText: String
    @Binding var toolsEnabled: Bool
    let availableTools: [ToolDefinition]
    let toolAnimation: Namespace.ID
    let onSend: () -> Void
    let onToolTrigger: (ToolDefinition) -> Void

    @State private var showToolPicker = false
    @State private var selectedTools: Set<UUID> = []
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Tool Trigger Bubble
            if toolsEnabled {
                HStack {
                    NeonToolTriggerBubble(
                        showToolPicker: $showToolPicker,
                        selectedTools: $selectedTools,
                        availableTools: availableTools,
                        namespace: toolAnimation,
                        onToolTrigger: onToolTrigger
                    )

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            // Input Field
            HStack(alignment: .bottom, spacing: 12) {
                // Text Input
                ZStack(alignment: .topLeading) {
                    if messageText.isEmpty {
                        Text("Message...")
                            .font(.system(size: 14))
                            .foregroundColor(.neonGray.opacity(0.5))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                    }

                    TextEditor(text: $messageText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 120)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .focused($isInputFocused)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.neonCharcoal.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isInputFocused ? Color.neonElectricBlue.opacity(0.5) : Color.neonGray.opacity(0.2), lineWidth: 1)
                        )
                )

                // Send Button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(messageText.isEmpty ? .neonGray.opacity(0.3) : .neonElectricBlue)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .background(
            .ultraThinMaterial
                .overlay(Color.neonCharcoal.opacity(0.2))
        )
    }
}

// MARK: - Tool Trigger Bubble

struct NeonToolTriggerBubble: View {
    @Binding var showToolPicker: Bool
    @Binding var selectedTools: Set<UUID>
    let availableTools: [ToolDefinition]
    let namespace: Namespace.ID
    let onToolTrigger: (ToolDefinition) -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Toggle Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showToolPicker.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 12))
                        .foregroundColor(showToolPicker ? .neonElectricBlue : .neonGray)

                    if !showToolPicker {
                        Text("Tools")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.neonGray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    showToolPicker ? Color.neonElectricBlue.opacity(0.6) : Color.neonGray.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                )
            }
            .buttonStyle(.plain)
            .matchedGeometryEffect(id: "toolBubble", in: namespace)

            // Expanded Tool Icons
            if showToolPicker {
                ForEach(availableTools.prefix(5)) { tool in
                    Button(action: { onToolTrigger(tool) }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 14))
                            .foregroundColor(.neonElectricBlue)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.neonCharcoal.opacity(0.6))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.neonElectricBlue.opacity(0.4), lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
        }
    }
}

// MARK: - Tool Inspector

struct NeonToolInspector: View {
    @Binding var isVisible: Bool
    @Binding var toolExecution: ToolExecution?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.neonElectricBlue)

                    Text("Tool Inspector")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        isVisible = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundColor(.neonGray)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.neonCharcoal.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.neonCharcoal.opacity(0.4))

            Divider()
                .background(Color.neonElectricBlue.opacity(0.3))

            // Content
            ScrollView {
                if let execution = toolExecution {
                    VStack(alignment: .leading, spacing: 16) {
                        // Tool Info
                        HStack(spacing: 12) {
                            Image(systemName: execution.icon)
                                .font(.system(size: 20))
                                .foregroundColor(.neonElectricBlue)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(Color.neonCharcoal.opacity(0.6))
                                )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(execution.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)

                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(execution.status.color)
                                        .frame(width: 6, height: 6)

                                    Text(statusText(execution.status))
                                        .font(.system(size: 11))
                                        .foregroundColor(.neonGray)
                                }
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.neonCharcoal.opacity(0.4))
                        )

                        // Output
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Output")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.neonGray)

                            Text(execution.output)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.neonMidnight.opacity(0.8))
                                )
                        }
                    }
                    .padding(16)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.neonGray.opacity(0.3))

                        Text("No Active Tool")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.neonGray)

                        Text("Tool execution results will appear here")
                            .font(.system(size: 12))
                            .foregroundColor(.neonGray.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(40)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(.ultraThinMaterial)
                .overlay(Color.neonMidnight.opacity(0.5))
                .overlay(
                    // Electric Blue perimeter glow
                    Rectangle()
                        .stroke(
                            LinearGradient(
                                colors: [.neonElectricBlue.opacity(0.6), .neonElectricBlue.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 2
                        ),
                    alignment: .leading
                )
        )
    }

    private func statusText(_ status: ToolExecution.ExecutionStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .running: return "Running..."
        case .success: return "Completed"
        case .error: return "Error"
        }
    }
}

// MARK: - Welcome View

struct NeonWelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Neon Logo/Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .neonElectricBlue.opacity(0.3),
                                .neonFuchsia.opacity(0.2),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "sparkles")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.neonElectricBlue, .neonFuchsia],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Neon Agent Workbench")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .neonGray],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("Select a conversation or create a new one to begin")
                    .font(.system(size: 14))
                    .foregroundColor(.neonGray)
            }

            // Quick Actions
            HStack(spacing: 16) {
                QuickActionButton(
                    icon: "plus.bubble.fill",
                    title: "New Chat",
                    color: .neonElectricBlue
                )

                QuickActionButton(
                    icon: "folder.fill",
                    title: "Browse",
                    color: .neonFuchsia
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.neonMidnight)
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    @State private var isHovered = false

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 140, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(color.opacity(isHovered ? 0.6 : 0.3), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Tool Definition

struct ToolDefinition: Identifiable {
    let id: UUID
    let name: String
    let icon: String
    let description: String

    static let sampleTools: [ToolDefinition] = [
        ToolDefinition(
            id: UUID(),
            name: "Code Interpreter",
            icon: "curlybraces",
            description: "Execute code snippets"
        ),
        ToolDefinition(
            id: UUID(),
            name: "Web Search",
            icon: "magnifyingglass.circle.fill",
            description: "Search the web"
        ),
        ToolDefinition(
            id: UUID(),
            name: "File Reader",
            icon: "doc.text.fill",
            description: "Read file contents"
        ),
        ToolDefinition(
            id: UUID(),
            name: "File Editor",
            icon: "pencil.circle.fill",
            description: "Edit files"
        ),
        ToolDefinition(
            id: UUID(),
            name: "Terminal",
            icon: "terminal.fill",
            description: "Execute shell commands"
        )
    ]
}

// MARK: - Preference Keys

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Color Extension for Hex Support

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        guard Scanner(string: hex).scanHexInt64(&int) else {
            return nil
        }

        let a, r, g, b: UInt64
        switch hex.count {
        case 6: // RGB
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview Provider

#Preview("Neon Agent Workbench") {
    NeonAgentWorkbenchWindow()
        .frame(minWidth: 1200, minHeight: 800)
}
