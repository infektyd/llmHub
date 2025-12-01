//
//  llmHubApp.swift
//  llmHub
//
//  Created by Jules (AI Assistant) for llmHub.
//  Target OS: macOS 26.1+ (Tahoe) | Swift 6.2
//  Description: Single-file implementation of the Neon Agent Workbench main window.
//

import SwiftUI

// MARK: - 1. App Entry Point

@main
struct llmHubApp: App {
    var body: some Scene {
        WindowGroup {
            LLMHubRootView()
        }
        // Modern, edge-to-edge window style appropriate for immersive apps
        .windowStyle(.hiddenTitleBar)
        // Ensure the app defaults to dark mode for the Neon aesthetic
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - 2. Design System & Theme

/// Centralized definition of the Neon Agent aesthetic colors and styles.
struct Theme {
    /// Electric Blue (#00BFFF): Used for active states, tools, and success indicators.
    static let electricBlue = Color(red: 0.0, green: 0.749, blue: 1.0) // #00BFFF

    /// Fuchsia (#FF0066): Used for alerts, primary selection, and model picker.
    static let fuchsia = Color(red: 1.0, green: 0.0, blue: 0.4) // #FF0066

    /// Deep charcoal/midnight background for high contrast.
    static let midnightBackground = Color(red: 0.05, green: 0.05, blue: 0.08)

    /// Standard glass material for translucent surfaces.
    static let glassMaterial: Material = .ultraThinMaterial
}

// MARK: - 3. Models (Sample Data)

struct Folder: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp: Date
}

struct AIModel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let provider: String
}

struct ToolLog: Identifiable {
    let id = UUID()
    let toolName: String
    let status: String
    let output: String
    let timestamp: Date
}

// MARK: - 4. Root View (Layout Architecture)

struct LLMHubRootView: View {
    // Navigation State
    @State private var selectedFolder: Folder?
    @State private var isInspectorVisible: Bool = false

    // Sample Data
    let folders = [
        Folder(name: "Active Operations", icon: "waveform.path.ecg"),
        Folder(name: "Archive: Sector 7", icon: "archivebox.fill"),
        Folder(name: "System Diag", icon: "cpu")
    ]

    var body: some View {
        // Core Layout: Adaptive NavigationSplitView
        // Maps to: Sidebar | Content (Chat) | Inspector (Right Pane)
        NavigationSplitView {
            llmHubSidebar(folders: folders, selectedFolder: $selectedFolder)
        } detail: {
            ChatView(isInspectorVisible: $isInspectorVisible)
                // The Inspector is attached to the Detail view
                .inspector(isPresented: $isInspectorVisible) {
                    ToolInspector()
                        .inspectorColumnWidth(min: 250, ideal: 320, max: 450)
                }
        }
        // Enforce dark theme
        .preferredColorScheme(.dark)
        .background(Theme.midnightBackground)
        // Device-adaptive sizing
        .frame(minWidth: 900, minHeight: 600)
    }
}

// MARK: - 5. Component: Conversation Sidebar

struct llmHubSidebar: View {
    let folders: [Folder]
    @Binding var selectedFolder: Folder?

    var body: some View {
        List(selection: $selectedFolder) {
            Section(header: Text("COMM CHANNELS").font(.caption).foregroundStyle(.secondary)) {
                ForEach(folders) { folder in
                    NavigationLink(value: folder) {
                        Label {
                            Text(folder.name)
                                .font(.system(.body, design: .monospaced))
                        } icon: {
                            Image(systemName: folder.icon)
                                .foregroundStyle(Theme.electricBlue)
                        }
                    }
                    .listRowBackground(Color.clear) // clean look
                }
            }

            Section(header: Text("RECENT INTEL").font(.caption).foregroundStyle(.secondary)) {
                Label("Project Chimera", systemImage: "bubble.left")
                Label("Network Scan results", systemImage: "bubble.left")
                Label("Encryption Keys", systemImage: "bubble.left")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.glassMaterial) // Low-opacity blurred material
        .navigationTitle("NEXUS")
    }
}

// MARK: - 6. Component: Main Chat View

struct ChatView: View {
    @Binding var isInspectorVisible: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var messageText: String = ""
    @State private var isToolTriggerActive: Bool = false
    @Namespace private var toolNamespace

    // Sample Conversation
    @State private var messages: [ChatMessage] = [
        ChatMessage(text: "System initialized. Neural link active.", isUser: false, timestamp: Date()),
        ChatMessage(text: "Run diagnostics on Sector 4.", isUser: true, timestamp: Date()),
        ChatMessage(text: "Scanning Sector 4... Anomalies detected in grid 7.", isUser: false, timestamp: Date())
    ]

    var body: some View {
        ZStack(alignment: .top) {
            // Background
            Theme.midnightBackground.ignoresSafeArea()

            // Chat Content
            ScrollView {
                // Scroll Tracker
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                VStack(spacing: 20) {
                    Spacer().frame(height: 80) // Spacing for toolbar

                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                    }
                }
                .padding()
                .padding(.bottom, 100) // Spacing for input
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                self.scrollOffset = value
            }

            // 2. Dynamic Toolbar
            llmHubToolbar(scrollOffset: scrollOffset, isInspectorVisible: $isInspectorVisible)

            // Input Area
            VStack {
                Spacer()
                HStack(alignment: .bottom, spacing: 12) {
                    // 4. Tool Trigger System
                    ToolTriggerBubble(isActive: $isToolTriggerActive, namespace: toolNamespace)

                    TextField("Enter command...", text: $messageText)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .font(.system(.body, design: .monospaced))

                    Button {
                        // Send action
                        if !messageText.isEmpty {
                            messages.append(ChatMessage(text: messageText, isUser: true, timestamp: Date()))
                            messageText = ""
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.electricBlue)
                            .shadow(color: Theme.electricBlue.opacity(0.5), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(
                    Theme.glassMaterial
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                )
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            Text(message.text)
                .padding()
                .background(message.isUser ? Theme.electricBlue.opacity(0.2) : Color.white.opacity(0.1))
                .background(.ultraThinMaterial)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(message.isUser ? Theme.electricBlue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: message.isUser ? Theme.electricBlue.opacity(0.3) : .clear, radius: 5)

            if !message.isUser { Spacer() }
        }
    }
}

// MARK: - 7. Component: Dynamic Toolbar

struct llmHubToolbar: View {
    var scrollOffset: CGFloat
    @Binding var isInspectorVisible: Bool

    // Calculate appearance based on scroll
    // If scrolled down (offset < 0), background becomes more opaque/blurred
    var isScrolled: Bool {
        scrollOffset < -10
    }

    var body: some View {
        HStack {
            Text("SESSION: ALPHA")
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(Theme.electricBlue)
                .shadow(color: Theme.electricBlue.opacity(0.6), radius: 4)

            Spacer()

            // 3. Model Picker
            ModelPickerView()

            Spacer()

            // Inspector Toggle
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isInspectorVisible.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.title3)
                    .foregroundStyle(isInspectorVisible ? Theme.electricBlue : .white)
                    .shadow(color: isInspectorVisible ? Theme.electricBlue : .clear, radius: 5)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            Theme.glassMaterial
                .opacity(isScrolled ? 1.0 : 0.6)
                .ignoresSafeArea()
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(LinearGradient(colors: [.clear, Theme.electricBlue.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))
                .opacity(isScrolled ? 1.0 : 0.0),
            alignment: .bottom
        )
        .animation(.easeInOut(duration: 0.2), value: isScrolled)
    }
}

// MARK: - 8. Component: Model Picker

struct ModelPickerView: View {
    @State private var selectedModelID: UUID?

    let models = [
        AIModel(name: "GPT-4o (Omni)", provider: "OpenAI"),
        AIModel(name: "Claude 3.5 Sonnet", provider: "Anthropic"),
        AIModel(name: "Gemini 1.5 Pro", provider: "Google")
    ]

    init() {
        _selectedModelID = State(initialValue: models.first?.id)
    }

    var body: some View {
        Menu {
            ForEach(models) { model in
                Button {
                    selectedModelID = model.id
                } label: {
                    HStack {
                        Text(model.name)
                        if selectedModelID == model.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.caption)
                Text(models.first(where: { $0.id == selectedModelID })?.name ?? "Select Model")
                    .font(.system(.subheadline, design: .monospaced))
                    .fontWeight(.bold)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.3))
            )
            .overlay(
                Capsule()
                    .stroke(Theme.fuchsia.opacity(0.7), lineWidth: 1.5)
                    .shadow(color: Theme.fuchsia.opacity(0.5), radius: 4)
            )
            .foregroundStyle(.white)
        }
        .menuStyle(.button)
    }
}

// MARK: - 9. Component: Tool Trigger System

struct ToolTriggerBubble: View {
    @Binding var isActive: Bool
    var namespace: Namespace.ID

    var body: some View {
        ZStack {
            if isActive {
                // Expanded State
                HStack(spacing: 15) {
                    Button { isActive.toggle() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Divider().frame(height: 20).background(.white.opacity(0.3))

                    ToolIcon(icon: "terminal", label: "Shell")
                    ToolIcon(icon: "globe", label: "Web")
                    ToolIcon(icon: "doc.text.magnifyingglass", label: "Search")
                    ToolIcon(icon: "photo", label: "Vision")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .matchedGeometryEffect(id: "toolBubble", in: namespace)
                .overlay(
                    Capsule()
                        .stroke(Theme.electricBlue.opacity(0.5), lineWidth: 1)
                        .shadow(color: Theme.electricBlue.opacity(0.3), radius: 5)
                )
            } else {
                // Collapsed State
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isActive.toggle()
                    }
                } label: {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.electricBlue)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .matchedGeometryEffect(id: "toolBubble", in: namespace)
                        .overlay(
                            Circle()
                                .stroke(Theme.electricBlue.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ToolIcon: View {
    let icon: String
    let label: String

    var body: some View {
        Button {} label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))

            }
            .foregroundStyle(Theme.electricBlue)
            .padding(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 10. Component: Adaptive Tool Inspector

struct ToolInspector: View {
    // Sample Output Data
    @State private var logs: [ToolLog] = [
        ToolLog(toolName: "WebSearch", status: "Success", output: "Found 14 references for 'Project Neon'.", timestamp: Date()),
        ToolLog(toolName: "CodeInterpreter", status: "Running", output: "Calculating vectors...", timestamp: Date())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "server.rack")
                    .foregroundStyle(Theme.electricBlue)
                Text("TOOL_OUTPUT")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: .green, radius: 4)
            }
            .padding()
            .background(Color.black.opacity(0.4))

            Divider().background(Theme.electricBlue.opacity(0.3))

            // Output Content
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(log.toolName.uppercased())
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.fuchsia)
                                Spacer()
                                Text(log.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.gray)
                            }

                            Text(log.output)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding()
            }
        }
        .background(Theme.glassMaterial) // Darker blurred material
        .background(Color.black.opacity(0.6)) // Tinting
        .overlay(
            // Electric Blue perimeter glow on the left edge
            Rectangle()
                .frame(width: 1)
                .foregroundStyle(Theme.electricBlue)
                .shadow(color: Theme.electricBlue, radius: 8),
            alignment: .leading
        )
    }
}

// MARK: - Helpers

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
