//
//  ChatHeaderBar.swift
//  llmHub
//

import SwiftUI

struct ChatHeaderBar: View {
    @Binding var title: String
    @Binding var selectedProviderID: String
    @Binding var selectedModelID: String
    @Binding var leftSidebarVisible: Bool

    @EnvironmentObject private var modelRegistry: ModelRegistry
    @State private var isEditingTitle = false
    @State private var showModelPicker = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Left section: Sidebar toggle + Title
            HStack(spacing: 8) {
                Button {
                    withAnimation {
                        leftSidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColors.surface)
                        }
                }
                .buttonStyle(.plain)
                .help(leftSidebarVisible ? "Hide Sidebar" : "Show Sidebar")

                if isEditingTitle {
                    TextField("Chat Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .focused($isTitleFocused)
                        .onSubmit {
                            isEditingTitle = false
                        }
                        .frame(maxWidth: 300)
                } else {
                    Text(title.isEmpty ? "New Chat" : title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            title.isEmpty ? AppColors.textTertiary : AppColors.textPrimary
                        )
                        .onTapGesture {
                            isEditingTitle = true
                            isTitleFocused = true
                        }
                }
            }

            Spacer()

            // Right section: Model Picker
            Button {
                showModelPicker = true
            } label: {
                HStack(spacing: 6) {
                    providerIcon(providerID: selectedProviderID)
                        .font(.system(size: 12))

                    Text(currentModelName)
                        .font(.system(size: 13, weight: .medium))

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppColors.surface)
                        .shadow(color: AppColors.shadowSmoke, radius: 4, x: 0, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(AppColors.textPrimary.opacity(0.05), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.backgroundPrimary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColors.textPrimary.opacity(0.05))
                .frame(height: 1)
        }
        .onChange(of: isTitleFocused) { _, newValue in
            if !newValue {
                isEditingTitle = false
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(
                selectedProviderID: $selectedProviderID,
                selectedModelID: $selectedModelID
            )
            .environmentObject(modelRegistry)
        }
    }

    private var currentModelName: String {
        let models = modelRegistry.models(for: selectedProviderID)
        return models.first(where: { $0.id == selectedModelID })?.displayName ?? selectedModelID
    }

    private func providerIcon(providerID: String) -> some View {
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
        return Image(systemName: icon)
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var title = "My Awesome Chat"
        @Previewable @State var provider = "openai"
        @Previewable @State var model = "gpt-4o"
        @Previewable @State var sidebar = true

        ChatHeaderBar(
            title: $title,
            selectedProviderID: $provider,
            selectedModelID: $model,
            leftSidebarVisible: $sidebar
        )
        .environmentObject(ModelRegistry())
        .padding()
        .background(AppColors.backgroundSecondary)
    }
#endif
