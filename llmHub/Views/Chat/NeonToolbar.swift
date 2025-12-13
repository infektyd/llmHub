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
            
            // Settings Button
            GlassToolbarItem(
                id: "settings",
                icon: "gearshape",
                isActive: showingSettings
            ) {
                showingSettings = true
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
