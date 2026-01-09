//
//  SettingsView.swift
//  llmHub
//
//  Unified settings interface following the flat/matte UI theme.
//  Modular section components for easy Xcode preview editing.
//

import SwiftUI

// swiftlint:disable file_length

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var modelRegistry: ModelRegistry
    @Environment(AFMDiagnosticsState.self) private var afmDiagnostics
    @StateObject private var viewModel = SettingsViewModel()

    @State private var selectedSection: SettingsSection = .providers

    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
        case providers = "Providers"
        case tools = "Tools"
        case appearance = "Appearance"
        case advanced = "Advanced"
        case about = "About"
        #if DEBUG
            case diagnostics = "Diagnostics"
        #endif

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .providers: return "key.fill"
            case .tools: return "wrench.and.screwdriver"
            case .appearance: return "paintbrush.fill"
            case .advanced: return "gearshape.2.fill"
            case .about: return "info.circle.fill"
            #if DEBUG
                case .diagnostics: return "stethoscope"
            #endif
            }
        }
    }

    var body: some View {
        Group {
            #if os(macOS)
                HSplitView {
                    // Sidebar navigation
                    sidebarContent
                        .frame(minWidth: 180, maxWidth: 220)

                    // Detail content
                    detailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            #else
                NavigationStack {
                    List(SettingsSection.allCases) { section in
                        NavigationLink(value: section) {
                            SettingsSidebarRow(
                                title: section.rawValue,
                                icon: section.icon,
                                isSelected: selectedSection == section
                            )
                        }
                    }
                    .listStyle(.insetGrouped)
                    .navigationTitle("Settings")
                    .navigationDestination(for: SettingsSection.self) { section in
                        SettingsDetailView(
                            section: section, viewModel: viewModel, afmDiagnostics: afmDiagnostics
                        )
                        .navigationTitle(section.rawValue)
                    }
                }
            #endif
        }
        .background(AppColors.backgroundPrimary)
        .onAppear {
            viewModel.modelRegistry = modelRegistry
            viewModel.loadKeys()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 3 : 4) {
            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarRow(
                    title: section.rawValue,
                    icon: section.icon,
                    isSelected: selectedSection == section
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedSection = section
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, uiCompactMode ? 12 : 16)
        .padding(.horizontal, uiCompactMode ? 10 : 12)
        .background(AppColors.backgroundSecondary)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: uiCompactMode ? 18 : 24) {
                switch selectedSection {
                case .providers:
                    ProvidersSection(viewModel: viewModel)
                case .tools:
                    ToolsSection(viewModel: viewModel)
                case .appearance:
                    AppearanceSection()
                case .advanced:
                    AdvancedSettingsView()
                case .about:
                    AboutSection()
                #if DEBUG
                    case .diagnostics:
                        DiagnosticsSection(afmDiagnostics: afmDiagnostics)
                #endif
                }
            }
            .padding(uiCompactMode ? 16 : 24)
        }
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - iOS Detail Host

private struct SettingsDetailView: View {
    let section: SettingsView.SettingsSection
    let viewModel: SettingsViewModel
    let afmDiagnostics: AFMDiagnosticsState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch section {
                case .providers:
                    ProvidersSection(viewModel: viewModel)
                case .tools:
                    ToolsSection(viewModel: viewModel)
                case .appearance:
                    AppearanceSection()
                case .advanced:
                    AdvancedSettingsView()
                case .about:
                    AboutSection()
                #if DEBUG
                    case .diagnostics:
                        DiagnosticsSection(afmDiagnostics: afmDiagnostics)
                #endif
                }
            }
            .padding(24)
        }
        .background(AppColors.backgroundPrimary)
    }
}

// MARK: - Sidebar Row

struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool

    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        HStack(spacing: uiCompactMode ? 8 : 10) {
            Image(systemName: icon)
                .font(.system(size: 14 * uiScale, weight: .medium))
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                .frame(width: 20)

            Text(title)
                .font(.system(size: 13 * uiScale, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)

            Spacer()
        }
        .padding(.horizontal, uiCompactMode ? 10 : 12)
        .padding(.vertical, uiCompactMode ? 8 : 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AppColors.accent.opacity(0.12) : Color.clear)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Section Header

struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20 * uiScale, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13 * uiScale))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

// MARK: - Settings Card

struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.textPrimary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Providers Section

struct ProvidersSection: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(
                "API Providers",
                subtitle: "Configure API keys for LLM providers"
            )

            // Status banner
            if let message = viewModel.statusMessage {
                StatusBanner(message: message, isError: viewModel.isError)
            }

            // Provider cards
            SettingsCard {
                ForEach(
                    Array(SettingsViewModel.ProviderInfo.allProviders.enumerated()),
                    id: \.element.provider
                ) { index, info in
                    ProviderRow(
                        info: info,
                        keyBinding: viewModel.binding(for: info.provider),
                        hasKey: viewModel.hasKey(for: info.provider),
                        isSaving: viewModel.savingProvider == info.provider,
                        onSave: { viewModel.saveKey(for: info.provider) },
                        onDelete: { viewModel.deleteKey(for: info.provider) }
                    )

                    if index < SettingsViewModel.ProviderInfo.allProviders.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

// MARK: - Provider Row

struct ProviderRow: View {
    let info: SettingsViewModel.ProviderInfo
    @Binding var keyBinding: String
    let hasKey: Bool
    let isSaving: Bool
    let onSave: () -> Void
    let onDelete: () -> Void

    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode

    @State private var isExpanded = false
    @State private var isKeyVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: info.icon)
                        .font(.system(size: 16 * uiScale, weight: .medium))
                        .foregroundStyle(hasKey ? AppColors.accent : AppColors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    hasKey
                                        ? AppColors.accent.opacity(0.12)
                                        : AppColors.backgroundSecondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)

                        if let desc = info.description {
                            Text(desc)
                                .font(.system(size: 11 * uiScale))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }

                    Spacer()

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(hasKey ? AppColors.success : AppColors.textTertiary.opacity(0.5))
                            .frame(width: 8, height: 8)

                        Text(hasKey ? "Configured" : "Not set")
                            .font(.system(size: 11 * uiScale, weight: .medium))
                            .foregroundStyle(hasKey ? AppColors.success : AppColors.textTertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12 * uiScale, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // API key input
                    HStack(spacing: 8) {
                        Group {
                            if isKeyVisible {
                                TextField("API Key", text: $keyBinding)
                            } else {
                                SecureField("API Key", text: $keyBinding)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(.system(size: 13 * uiScale, design: .monospaced))
                        .padding(.horizontal, uiCompactMode ? 10 : 12)
                        .padding(.vertical, uiCompactMode ? 9 : 10)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColors.backgroundPrimary)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
                        }

                        // Toggle visibility
                        Button {
                            isKeyVisible.toggle()
                        } label: {
                            Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                                .font(.system(size: 13 * uiScale))
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Actions
                    HStack(spacing: 12) {
                        Button {
                            onSave()
                        } label: {
                            HStack(spacing: 6) {
                                if isSaving {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11 * uiScale, weight: .semibold))
                                }
                                Text("Save")
                                    .font(.system(size: 12 * uiScale, weight: .medium))
                            }
                            .padding(.horizontal, uiCompactMode ? 12 : 14)
                            .padding(.vertical, uiCompactMode ? 7 : 8)
                            .background {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(AppColors.accent)
                            }
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(keyBinding.isEmpty || isSaving)
                        .opacity(keyBinding.isEmpty ? 0.5 : 1)

                        if hasKey {
                            Button {
                                onDelete()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11 * uiScale, weight: .semibold))
                                    Text("Remove")
                                        .font(.system(size: 12 * uiScale, weight: .medium))
                                }
                                .padding(.horizontal, uiCompactMode ? 12 : 14)
                                .padding(.vertical, uiCompactMode ? 7 : 8)
                                .background {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(AppColors.textTertiary.opacity(0.5), lineWidth: 1)
                                }
                                .foregroundStyle(AppColors.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Docs link
                        if let url = info.docsURL {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text("Get API Key")
                                        .font(.system(size: 12 * uiScale, weight: .medium))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 10 * uiScale, weight: .semibold))
                                }
                                .foregroundStyle(AppColors.accent)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(uiCompactMode ? 14 : 16)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }
}

// MARK: - Status Banner

struct StatusBanner: View {
    let message: String
    let isError: Bool

    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14 * uiScale))

            Text(message)
                .font(.system(size: 13 * uiScale, weight: .medium))

            Spacer()
        }
        .padding(uiCompactMode ? 10 : 12)
        .foregroundStyle(isError ? Color.red : AppColors.success)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill((isError ? Color.red : AppColors.success).opacity(0.1))
        }
    }
}

// MARK: - Tools Section

struct ToolsSection: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    @Environment(\.uiScale) private var uiScale

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(
                "Tools",
                subtitle: "Enable or disable assistant capabilities"
            )

            SettingsCard {
                if viewModel.toolToggles.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading tools…")
                                .font(.system(size: 12 * uiScale))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        .padding(24)
                        Spacer()
                    }
                } else {
                    ForEach(Array(viewModel.toolToggles.enumerated()), id: \.element.id) { index, tool in
                        ToolToggleRow(
                            tool: tool,
                            onToggle: { enabled in
                                viewModel.toggleTool(tool.id, enabled: enabled)
                            }
                        )

                        if index < viewModel.toolToggles.count - 1 {
                            Divider()
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Tool Toggle Row

struct ToolToggleRow: View {
    let tool: UIToolToggleItem
    let onToggle: (Bool) -> Void

    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 14 * uiScale, weight: .medium))
                .foregroundStyle(tool.isAvailable ? AppColors.accent : AppColors.textTertiary)
                .frame(width: 28, height: 28)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            tool.isAvailable
                                ? AppColors.accent.opacity(0.12) : AppColors.backgroundSecondary)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 14 * uiScale, weight: .medium))
                    .foregroundStyle(
                        tool.isAvailable ? AppColors.textPrimary : AppColors.textTertiary)

                Text(tool.description)
                    .font(.system(size: 11 * uiScale))
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)
            }

            Spacer()

            if tool.isAvailable {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { tool.isEnabled },
                        set: { onToggle($0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.small)
            } else if let reason = tool.unavailableReason {
                Text(reason)
                    .font(.system(size: 10 * uiScale, weight: .medium))
                    .foregroundStyle(AppColors.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(AppColors.backgroundSecondary)
                    }
            }
        }
        .padding(uiCompactMode ? 14 : 16)
        .opacity(tool.isAvailable ? 1 : 0.6)
    }
}

// MARK: - Appearance Section

struct AppearanceSection: View {
    @Environment(\.settingsManager) private var settingsManager
    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(
                "Appearance",
                subtitle: "Customize the look and feel"
            )

            SettingsCard {
                // Color scheme
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color Scheme")
                        .font(.system(size: 13 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)

                    Picker(
                        "",
                        selection: Binding(
                            get: { settingsManager.settings.colorScheme },
                            set: { settingsManager.settings.colorScheme = $0 }
                        )
                    ) {
                        ForEach(ColorSchemeChoice.allCases, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(uiCompactMode ? 14 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 14 : 16)

                // Font size slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Font Size")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(Int(settingsManager.settings.fontSize * 100))%")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Adjust the base font size throughout the application")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { settingsManager.settings.fontSize },
                            set: { settingsManager.settings.fontSize = $0 }
                        ),
                        in: 0.8...1.5,
                        step: 0.05
                    )
                    .tint(AppColors.accent)
                }
                .padding(uiCompactMode ? 14 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 14 : 16)

                // Compact mode toggle
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.settings.compactMode },
                        set: { settingsManager.settings.compactMode = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Compact Mode")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Reduce spacing and padding throughout the UI")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(uiCompactMode ? 14 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 14 : 16)

                // Token counts toggle
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.settings.showTokenCounts },
                        set: { settingsManager.settings.showTokenCounts = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Token Counts")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Display token usage in message headers")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(uiCompactMode ? 14 : 16)
            }
        }
    }
}

// MARK: - About Section

struct AboutSection: View {
    @Environment(\.uiScale) private var uiScale
    @Environment(\.uiCompactMode) private var uiCompactMode

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(
                "About",
                subtitle: "llmHub version and information"
            )

            SettingsCard {
                VStack(alignment: .leading, spacing: 16) {
                    // App icon + name
                    HStack(spacing: 16) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppColors.accent, AppColors.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                            .overlay {
                                Image(systemName: "brain.head.profile")
                                    .font(.system(size: 28 * uiScale, weight: .medium))
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("llmHub")
                                .font(.system(size: 18 * uiScale, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)

                            Text("Version 2.0 (Canvas)")
                                .font(.system(size: 13 * uiScale))
                                .foregroundStyle(AppColors.textSecondary)

                            Text("AI Workbench for macOS & iOS")
                                .font(.system(size: 12 * uiScale))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                    }
                }
                .padding(uiCompactMode ? 14 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 14 : 16)

                // Build info
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(label: "Build", value: Bundle.main.buildNumber ?? "–")
                    InfoRow(label: "Platform", value: platformName)
                    InfoRow(label: "Architecture", value: architectureName)
                }
                .padding(uiCompactMode ? 14 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 14 : 16)

                // Links
                VStack(alignment: .leading, spacing: 8) {
                    LinkRow(title: "GitHub Repository", icon: "link", url: "https://github.com")
                    LinkRow(
                        title: "Report an Issue", icon: "exclamationmark.bubble",
                        url: "https://github.com")
                }
                .padding(uiCompactMode ? 14 : 16)
            }
        }
    }

    private var platformName: String {
        #if os(macOS)
            return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #elseif os(iOS)
            return "iOS \(UIDevice.current.systemVersion)"
        #else
            return "Unknown"
        #endif
    }

    private var architectureName: String {
        #if arch(arm64)
            return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
            return "Intel (x86_64)"
        #else
            return "Unknown"
        #endif
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13 * uiScale))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13 * uiScale, design: .monospaced))
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}

// MARK: - Link Row

struct LinkRow: View {
    let title: String
    let icon: String
    let url: String

    @Environment(\.uiScale) private var uiScale

    var body: some View {
        if let linkURL = URL(string: url) {
            Link(destination: linkURL) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 13 * uiScale))
                        .foregroundStyle(AppColors.accent)
                        .frame(width: 20)

                    Text(title)
                        .font(.system(size: 13 * uiScale, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11 * uiScale, weight: .semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
        }
    }
}

// MARK: - Diagnostics Section (DEBUG only)

#if DEBUG
    struct DiagnosticsSection: View {
        let afmDiagnostics: AFMDiagnosticsState

        @Environment(\.uiScale) private var uiScale
        @Environment(\.uiCompactMode) private var uiCompactMode

        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                SettingsSectionHeader(
                    "Diagnostics",
                    subtitle: "Debug tools and Apple Foundation Models testing"
                )

                SettingsCard {
                    // AFM Status
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Apple Foundation Models")
                                .font(.system(size: 14 * uiScale, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            if afmDiagnostics.availability != nil {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(afmDiagnostics.statusColor)
                                        .frame(width: 8, height: 8)
                                    Text(afmDiagnostics.reasonText)
                                        .font(.system(size: 11 * uiScale, weight: .medium))
                                        .foregroundStyle(afmDiagnostics.statusColor)
                                }
                            }
                        }

                        Toggle(
                            "Verbose AFM Logs",
                            isOn: Bindable(afmDiagnostics).foundationModelsDiagnosticsEnabled
                        )
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        HStack(spacing: 12) {
                            Button("Run Probe") {
                                afmDiagnostics.runProbe()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Test Generate") {
                                afmDiagnostics.runSmallGenerate()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if afmDiagnostics.lastCheckTime != nil {
                                Spacer()
                                Text("Last: \(afmDiagnostics.timeSinceCheck)")
                                    .font(.system(size: 11 * uiScale))
                                    .foregroundStyle(AppColors.textTertiary)
                            }
                        }
                    }
                    .padding(uiCompactMode ? 14 : 16)
                }
            }
        }
    }
#endif

// MARK: - Previews

#if DEBUG

    // MARK: Preview Fixtures

    @MainActor
    enum SettingsPreviewFixtures {
        static func mockToolToggles() -> [UIToolToggleItem] {
            [
                UIToolToggleItem(
                    id: "calculator",
                    name: "Calculator",
                    icon: "function",
                    description: "Perform mathematical calculations",
                    isEnabled: true,
                    isAvailable: true,
                    unavailableReason: nil
                ),
                UIToolToggleItem(
                    id: "code_interpreter",
                    name: "Code Interpreter",
                    icon: "curlybraces",
                    description: "Execute Python code in a sandboxed environment",
                    isEnabled: true,
                    isAvailable: true,
                    unavailableReason: nil
                ),
                UIToolToggleItem(
                    id: "web_search",
                    name: "Web Search",
                    icon: "globe",
                    description: "Search the web for current information",
                    isEnabled: false,
                    isAvailable: true,
                    unavailableReason: nil
                ),
                UIToolToggleItem(
                    id: "shell",
                    name: "Shell",
                    icon: "terminal",
                    description: "Execute shell commands",
                    isEnabled: false,
                    isAvailable: false,
                    unavailableReason: "Requires macOS"
                )
            ]
        }

        static func mockSettingsViewModel(withKeys: Bool = false, withTools: Bool = true)
            -> SettingsViewModel {
            let viewModel = SettingsViewModel()
            if withKeys {
                viewModel.openAIKey = "sk-mock-key-12345"
                viewModel.anthropicKey = "sk-ant-mock-67890"
            }
            if withTools {
                viewModel.toolToggles = mockToolToggles()
            }
            return viewModel
        }
    }

    // MARK: Full Settings Preview

    #Preview("Settings • Full") {
        SettingsView()
            .environmentObject(ModelRegistry())
            .environment(AFMDiagnosticsState())
            .frame(width: 800, height: 600)
    }

    // MARK: Section Previews (Selectable Components)

    #Preview("Section • Providers (Empty)") {
        ScrollView {
            ProvidersSection(viewModel: SettingsPreviewFixtures.mockSettingsViewModel())
                .padding(24)
        }
        .background(AppColors.backgroundPrimary)
        .frame(width: 600, height: 500)
    }

    #Preview("Section • Providers (Configured)") {
        ScrollView {
            ProvidersSection(
                viewModel: SettingsPreviewFixtures.mockSettingsViewModel(withKeys: true)
            )
            .padding(24)
        }
        .background(AppColors.backgroundPrimary)
        .frame(width: 600, height: 500)
    }

    #Preview("Section • Tools") {
        ScrollView {
            ToolsSection(viewModel: SettingsPreviewFixtures.mockSettingsViewModel())
                .padding(24)
        }
        .background(AppColors.backgroundPrimary)
        .frame(width: 600, height: 400)
    }

    #Preview("Section • Appearance") {
        ScrollView {
            AppearanceSection()
                .padding(24)
        }
        .background(AppColors.backgroundPrimary)
        .frame(width: 600, height: 400)
    }

    #Preview("Section • About") {
        ScrollView {
            AboutSection()
                .padding(24)
        }
        .background(AppColors.backgroundPrimary)
        .frame(width: 600, height: 500)
    }

    #Preview("Section • Diagnostics") {
        ScrollView {
            DiagnosticsSection(afmDiagnostics: AFMDiagnosticsState())
                .padding(24)
        }
        .background(AppColors.backgroundPrimary)
        .frame(width: 600, height: 300)
    }

    // MARK: Component Previews (Granular Selection)

    #Preview("Component • Sidebar Row") {
        VStack(spacing: 4) {
            SettingsSidebarRow(title: "Providers", icon: "key.fill", isSelected: true)
            SettingsSidebarRow(title: "Tools", icon: "wrench.and.screwdriver", isSelected: false)
            SettingsSidebarRow(title: "Appearance", icon: "paintbrush.fill", isSelected: false)
        }
        .padding()
        .background(AppColors.backgroundSecondary)
        .frame(width: 200)
    }

    #Preview("Component • Provider Row (Collapsed)") {
        SettingsCard {
            ProviderRow(
                info: SettingsViewModel.ProviderInfo.allProviders[0],
                keyBinding: .constant(""),
                hasKey: false,
                isSaving: false,
                onSave: {},
                onDelete: {}
            )
        }
        .padding(24)
        .background(AppColors.backgroundPrimary)
        .frame(width: 500)
    }

    #Preview("Component • Provider Row (Configured)") {
        SettingsCard {
            ProviderRow(
                info: SettingsViewModel.ProviderInfo.allProviders[1],
                keyBinding: .constant("sk-ant-api03-xxxxx"),
                hasKey: true,
                isSaving: false,
                onSave: {},
                onDelete: {}
            )
        }
        .padding(24)
        .background(AppColors.backgroundPrimary)
        .frame(width: 500)
    }

    #Preview("Component • Tool Toggle Row") {
        SettingsCard {
            VStack(spacing: 0) {
                ToolToggleRow(
                    tool: SettingsPreviewFixtures.mockToolToggles()[0],
                    onToggle: { _ in }
                )
                Divider().padding(.horizontal, 16)
                ToolToggleRow(
                    tool: SettingsPreviewFixtures.mockToolToggles()[3],
                    onToggle: { _ in }
                )
            }
        }
        .padding(24)
        .background(AppColors.backgroundPrimary)
        .frame(width: 500)
    }

    #Preview("Component • Status Banner (Success)") {
        VStack(spacing: 12) {
            StatusBanner(message: "API key saved successfully", isError: false)
            StatusBanner(message: "Failed to save key: Invalid format", isError: true)
        }
        .padding(24)
        .background(AppColors.backgroundPrimary)
        .frame(width: 500)
    }

    #Preview("Component • Settings Card") {
        SettingsCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Card Title")
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Card content goes here with proper styling.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(16)
        }
        .padding(24)
        .background(AppColors.backgroundPrimary)
        .frame(width: 400)
    }

    #Preview("Component • Section Header") {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionHeader("Simple Header")
            SettingsSectionHeader(
                "Header with Subtitle", subtitle: "A helpful description of this section")
        }
        .padding(24)
        .background(AppColors.backgroundPrimary)
        .frame(width: 400)
    }

#endif
