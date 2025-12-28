//
//  NeonToolbar.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

#if os(macOS)
    struct NeonToolbar: View {
        let session: ChatSessionEntity
        @Binding var selectedProvider: UILLMProvider?
        @Binding var selectedModel: UILLMModel?
        let scrollOffset: CGFloat
        @Binding var toolInspectorVisible: Bool
        @Binding var columnVisibility: NavigationSplitViewVisibility
        @Binding var showingSettings: Bool
        @Binding var showingToolsDebug: Bool
        var onOpenSettings: () -> Void

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
            GlassToolbar(spacing: 16) {
                // Sidebar Toggle
                GlassToolbarItem(
                    id: "sidebar",
                    icon: "sidebar.left",
                    isActive: columnVisibility == .all || columnVisibility == .doubleColumn
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        columnVisibility = (columnVisibility == .detailOnly) ? .all : .detailOnly
                    }
                }

                // Conversation Title
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(session.messages.count) messages")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Model Picker (keep existing NeonModelPicker for now)
                NeonModelPicker(
                    selectedProvider: $selectedProvider,
                    selectedModel: $selectedModel
                )

                #if DEBUG
                    GlassToolbarItem(
                        id: "tools_debug",
                        icon: "wrench.and.screwdriver",
                        isActive: showingToolsDebug
                    ) {
                        showingToolsDebug = true
                    }
                #endif

                // Settings Button
                GlassToolbarItem(
                    id: "settings",
                    icon: "gearshape",
                    isActive: false
                ) {
                    onOpenSettings()
                }

                // Tool Inspector Toggle
                GlassToolbarItem(
                    id: "inspector",
                    icon: "sidebar.right",
                    isActive: toolInspectorVisible
                ) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        toolInspectorVisible.toggle()
                    }
                }
            }
            .opacity(toolbarOpacity)
        }
    }
#endif
// MARK: - Previews

#if os(macOS)
    #Preview("Neon Toolbar") {
        @Previewable @State var provider: UILLMProvider? = MockData.uiLLMProvider()
        @Previewable @State var model: UILLMModel? = MockData.uiLLMModel()
        @Previewable @State var inspectorVisible = false
        @Previewable @State var columnVisibility: NavigationSplitViewVisibility = .all
        @Previewable @State var showingSettings = false
        @Previewable @State var showingToolsDebug = false

        NeonToolbar(
            session: MockData.chatSession(),
            selectedProvider: $provider,
            selectedModel: $model,
            scrollOffset: 0,
            toolInspectorVisible: $inspectorVisible,
            columnVisibility: $columnVisibility,
            showingSettings: $showingSettings,
            showingToolsDebug: $showingToolsDebug,
            onOpenSettings: {}
        )
        .padding()
        .frame(width: 800)
        .previewEnvironment()
    }
#endif
