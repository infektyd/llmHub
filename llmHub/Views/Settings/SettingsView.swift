//
//  SettingsView.swift
//  llmHub
//
//  Created by AI Assistant on 12/07/25.
//

import SwiftUI

/// Settings view for managing API keys and provider configuration.
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var modelRegistry: ModelRegistry

    var body: some View {
        TabView {
            // MARK: - API Keys Tab
            APIKeysSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
                .tag(0)

            // MARK: - Appearance Tab
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
                .tag(1)

            // MARK: - General Tab
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        #if os(macOS)
            .frame(width: 700, height: 550)
        #endif
        .background(LiquidGlassTokens.surfaceBackground)
        .onAppear {
            viewModel.modelRegistry = modelRegistry
        }
    }
}

// MARK: - Appearance Settings (Redesigned)

struct AppearanceSettingsView: View {
    

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text("Customize your workspace look and feel.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Info about Canvas UI
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.inset.filled")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Canvas UI")
                            .font(.headline)
                        Text("Floating panels with minimal design")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // MARK: - Window Style (macOS only)
                #if os(macOS)
                    WindowStylePicker()
                        .padding(.top, 4)
                #endif

                Spacer(minLength: 20)
            }
        }
        .background(Color.clear)
    }
}

// MARK: - 2025 UI Components

/// A slider with a liquid glass aesthetic.
struct LiquidSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...100

    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                // Track (Glass)
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.1), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .frame(height: height * 0.6)

                // Fill (Neon)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.accent.opacity(0.6), AppColors.error.opacity(0.6),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * CGFloat(progress), height: height * 0.6)
                    .blur(radius: 4)  // Glow effect

                // Thumb (Refractive Orb)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white, .white.opacity(0.5)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: height
                        )
                    )
                    .overlay(
                        Circle().stroke(.white.opacity(0.8), lineWidth: 1)
                    )
                    .shadow(
                        color: AppColors.accent.opacity(isDragging ? 0.8 : 0.4),
                        radius: isDragging ? 10 : 5
                    )
                    .frame(width: height, height: height)
                    .offset(x: (width - height) * CGFloat(progress))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                isDragging = true
                                let newProgress = min(max(0, drag.location.x / width), 1)
                                value =
                                    range.lowerBound
                                    + (newProgress * (range.upperBound - range.lowerBound))
                            }
                            .onEnded { _ in
                                withAnimation(.spring) {
                                    isDragging = false
                                }
                            }
                    )
            }
        }
    }
}

/// A specialized card for theme selection.
struct LiquidThemeCard: View {
    let appTheme: AppTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Background Preview
                RoundedRectangle(cornerRadius: 06)
                    .fill(appTheme.backgroundPrimary)
                    .frame(width: 100, height: 70)
                    .overlay(
                        RoundedRectangle(cornerRadius: 06)
                            .strokeBorder(isSelected ? appTheme.accent : .clear, lineWidth: 2)
                    )
                    .shadow(color: isSelected ? appTheme.accent.opacity(0.5) : .clear, radius: 10)

                // UI Elements Preview
                VStack(spacing: 4) {
                    Capsule().fill(appTheme.surface).frame(width: 70, height: 8)
                    HStack(spacing: 4) {
                        Circle().fill(appTheme.accent).frame(width: 16, height: 16)
                        Capsule().fill(appTheme.textSecondary.opacity(0.3)).frame(width: 40, height: 8)
                    }
                }
            }

            Text(appTheme.name)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
    }
}

/// An animated orb that reacts to intensity.
struct OrbPreview: View {
    let intensity: Double  // 0.0 to 1.0 (ish)

    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            // Core
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            AppColors.accent, AppColors.error, AppColors.accent,
                        ],
                        center: .center,
                        startAngle: .degrees(phase),
                        endAngle: .degrees(phase + 360)
                    )
                )
                .blur(radius: 10 - (intensity * 5))
                .opacity(0.8)

            // Glint
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.8), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                phase = 360
            }
        }
        // React to intensity changes
        .scaleEffect(0.8 + (intensity * 0.2))
        .animation(.spring, value: intensity)
    }
}

/// A card for UI mode selection (Neon vs Nordic)
struct UIModeCard: View {
    let title: String
    let icon: String
    let description: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isSelected ? .white : .secondary)

                // Title
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .primary)

                // Description
                Text(description)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Legacy Components (Preserved for compatibility)

struct APIKeysSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Keys")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text(
                        "Configure API keys for each LLM provider. Keys are securely stored in the system Keychain."
                    )
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

                Divider()
                    .background(AppColors.textSecondary.opacity(0.3))

                // Provider Key Rows
                ForEach(SettingsViewModel.ProviderInfo.allProviders, id: \.provider) { info in
                    ProviderKeyRow(
                        info: info,
                        apiKey: viewModel.binding(for: info.provider),
                        hasKey: viewModel.hasKey(for: info.provider),
                        isSaving: viewModel.savingProvider == info.provider,
                        onSave: { viewModel.saveKey(for: info.provider) },
                        onDelete: { viewModel.deleteKey(for: info.provider) }
                    )
                }

                // Status Message
                if let message = viewModel.statusMessage {
                    HStack(spacing: 8) {
                        Image(
                            systemName: viewModel.isError
                                ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .foregroundColor(viewModel.isError ? AppColors.error : .green)

                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(viewModel.isError ? AppColors.error : .green)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                viewModel.isError
                                    ? AppColors.error.opacity(0.1) : Color.green.opacity(0.1))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(24)
        }
        .background(LiquidGlassTokens.surfaceBackground)
        .onAppear {
            viewModel.loadKeys()
        }
    }
}

struct ProviderKeyRow: View {
    let info: SettingsViewModel.ProviderInfo
    @Binding var apiKey: String
    let hasKey: Bool
    let isSaving: Bool
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var isSecure: Bool = true
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider Header
            HStack(spacing: 12) {
                Image(systemName: info.icon)
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.accent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)

                    if let description = info.description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }

                Spacer()

                // Status Indicator
                if hasKey {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text("Configured")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.green)
                }
            }

            // API Key Input
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if isSecure && !apiKey.isEmpty {
                        SecureField("Enter API key", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .focused($isFocused)
                    } else {
                        TextField("Enter API key", text: $apiKey)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .focused($isFocused)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control / 2)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control / 2)
                                .stroke(
                                    isFocused
                                        ? AppColors.accent
                                        : AppColors.textPrimary.opacity(
                                            LiquidGlassTokens.Stroke.border),
                                    lineWidth: 1)
                        )
                )

                // Toggle Visibility
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control / 2)
                                .fill(Color.black.opacity(0.3))
                        )
                }
                .buttonStyle(.plain)

                // Save Button
                Button(action: onSave) {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12))
                        }
                        Text("Save")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control / 2)
                            .fill(
                                apiKey.isEmpty
                                    ? AppColors.textSecondary.opacity(0.3) : AppColors.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty || isSaving)

                // Delete Button
                if hasKey {
                    Button(action: onDelete) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.error)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control / 2)
                                    .fill(AppColors.error.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Documentation Link
            if let docsURL = info.docsURL {
                Link(destination: docsURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                        Text("Get API key from \(info.name)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(AppColors.accent)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(AppColors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    // Native Link doesn't support easy hover transforms without a wrapper,
                    // but we can rely on standard button style behavior if needed.
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control)
                        .stroke(
                            hasKey
                                ? AppColors.success.opacity(0.3)
                                : AppColors.textPrimary.opacity(0.1),
                            lineWidth: 1)
                )
        )
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var contextConfig = UserDefaults.standard.loadContextConfig()
    @State private var showSaveConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("General Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)

                    Text("Configure app behavior, tools, and performance optimizations.")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

                Divider()
                    .background(AppColors.textSecondary.opacity(0.3))

                // Tool Selection Section
                toolSelectionSection

                // Text Selection Section (Auto-Copy)
                textSelectionSection

                // Context Management Section
                contextManagementSection

                // Save Confirmation
                if showSaveConfirmation {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)

                        Text("Settings saved successfully")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(24)
        }
        .background(LiquidGlassTokens.surfaceBackground)
        .onAppear {
            Task {
                await viewModel.loadTools()
            }
        }
    }

    @ViewBuilder
    private var toolSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.accent)

                Text("Available Tools")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.toolToggles.enumerated()), id: \.element.id) {
                    index, tool in
                    SettingsToolToggleRow(tool: tool) { isEnabled in
                        viewModel.toggleTool(tool.id, enabled: isEnabled)
                    }

                    if index < viewModel.toolToggles.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control)
                    .fill(Color.black.opacity(0.2))
                    .glassEffect(
                        GlassEffect.regular,
                        in: .rect(cornerRadius: LiquidGlassTokens.Radius.control))
            )
        }
    }

    @ViewBuilder
    private var textSelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.system(size: 18))
                        .foregroundColor(AppColors.accent)

                Text("Text Selection")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            #if os(macOS)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        "Auto-copy selected text",
                        isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "chatAutoCopyEnabled") },
                            set: { UserDefaults.standard.set($0, forKey: "chatAutoCopyEnabled") }
                        )
                    )
                    .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))

                    Text(
                        "Automatically copy text to clipboard when selecting (Assistant/Tool messages only)."
                    )
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control)
                        .fill(Color.black.opacity(0.2))
                        .glassEffect(
                            GlassEffect.regular,
                            in: .rect(cornerRadius: LiquidGlassTokens.Radius.control))
                )
            #else
                Text("Text selection settings are available on macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            #endif
        }
    }

    @ViewBuilder
    private var contextManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.accent)

                Text("Context Management")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }

            Text("Automatically optimize conversation history to reduce token usage and costs.")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            // Enable/Disable Toggle
            Toggle(
                isOn: Binding(
                    get: { contextConfig.enabled },
                    set: { newValue in
                        contextConfig = ContextConfig(
                            enabled: newValue,
                            summarizationEnabled: contextConfig.summarizationEnabled,
                            summarizeAtTurnCount: contextConfig.summarizeAtTurnCount,
                            preserveLastTurns: contextConfig.preserveLastTurns,
                            summaryMaxTokens: contextConfig.summaryMaxTokens,
                            defaultMaxTokens: contextConfig.defaultMaxTokens,
                            preserveSystemPrompt: contextConfig.preserveSystemPrompt,
                            preserveRecentMessages: contextConfig.preserveRecentMessages,
                            providerOverrides: contextConfig.providerOverrides
                        )
                        saveConfig()
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable Context Compaction")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text("Automatically removes old messages when context limit is reached")
                        .font(.system(size: 11))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control)
                    .fill(Color.black.opacity(0.2))
                    .overlay(
                        RoundedRectangle(cornerRadius: LiquidGlassTokens.Radius.control)
                            .stroke(AppColors.textPrimary.opacity(0.1), lineWidth: 1)
                    )
            )

            if contextConfig.enabled {
                // Configuration Options
                VStack(spacing: 16) {
                    // Max Tokens Slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Default Token Limit")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(contextConfig.defaultMaxTokens.formatted()) tokens")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppColors.accent)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(contextConfig.defaultMaxTokens) },
                                set: { newValue in
                                    contextConfig = ContextConfig(
                                        enabled: contextConfig.enabled,
                                        summarizationEnabled: contextConfig.summarizationEnabled,
                                        summarizeAtTurnCount: contextConfig.summarizeAtTurnCount,
                                        preserveLastTurns: contextConfig.preserveLastTurns,
                                        summaryMaxTokens: contextConfig.summaryMaxTokens,
                                        defaultMaxTokens: Int(newValue),
                                        preserveSystemPrompt: contextConfig.preserveSystemPrompt,
                                        preserveRecentMessages: contextConfig
                                            .preserveRecentMessages,
                                        providerOverrides: contextConfig.providerOverrides
                                    )
                                }
                            ),
                            in: 50_000...200_000,
                            step: 10_000,
                            onEditingChanged: { editing in
                                if !editing {
                                    saveConfig()
                                }
                            }
                        )
                        .tint(AppColors.accent)

                        Text("Conversations exceeding this limit will be automatically compacted")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Recent Messages Slider
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent Messages to Preserve")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(contextConfig.preserveRecentMessages) messages")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(AppColors.accent)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(contextConfig.preserveRecentMessages) },
                                set: { newValue in
                                    contextConfig = ContextConfig(
                                        enabled: contextConfig.enabled,
                                        summarizationEnabled: contextConfig.summarizationEnabled,
                                        summarizeAtTurnCount: contextConfig.summarizeAtTurnCount,
                                        preserveLastTurns: contextConfig.preserveLastTurns,
                                        summaryMaxTokens: contextConfig.summaryMaxTokens,
                                        defaultMaxTokens: contextConfig.defaultMaxTokens,
                                        preserveSystemPrompt: contextConfig.preserveSystemPrompt,
                                        preserveRecentMessages: Int(newValue),
                                        providerOverrides: contextConfig.providerOverrides
                                    )
                                }
                            ),
                            in: 5...50,
                            step: 1,
                            onEditingChanged: { editing in
                                if !editing {
                                    saveConfig()
                                }
                            }
                        )
                        .tint(AppColors.accent)

                        Text("The most recent messages will always be kept in the context")
                            .font(.system(size: 10))
                            .foregroundColor(AppColors.textSecondary)
                    }

                    // Preserve System Prompt Toggle
                    Toggle(
                        isOn: Binding(
                            get: { contextConfig.preserveSystemPrompt },
                            set: { newValue in
                                contextConfig = ContextConfig(
                                    enabled: contextConfig.enabled,
                                    summarizationEnabled: contextConfig.summarizationEnabled,
                                    summarizeAtTurnCount: contextConfig.summarizeAtTurnCount,
                                    preserveLastTurns: contextConfig.preserveLastTurns,
                                    summaryMaxTokens: contextConfig.summaryMaxTokens,
                                    defaultMaxTokens: contextConfig.defaultMaxTokens,
                                    preserveSystemPrompt: newValue,
                                    preserveRecentMessages: contextConfig.preserveRecentMessages,
                                    providerOverrides: contextConfig.providerOverrides
                                )
                                saveConfig()
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Always Preserve System Prompt")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)

                            Text("Keep the system instructions even when compacting context")
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: AppColors.accent))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(AppColors.textSecondary.opacity(0.2), lineWidth: 1)
                        )
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Info Box
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.accent.opacity(0.8))
                    .frame(width: 20, height: 20)

                Text(
                    "Context compaction can reduce token costs by 40-70% in long conversations by intelligently removing older messages while preserving important context."
                )
                .font(.system(size: 11))
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.accent.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    private func saveConfig() {
        UserDefaults.standard.saveContextConfig(contextConfig)

        withAnimation {
            showSaveConfirmation = true
        }

        // Auto-hide confirmation after 2 seconds
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                withAnimation {
                    showSaveConfirmation = false
                }
            }
        }
    }
}

struct SettingsToolToggleRow: View {
    let tool: UIToolToggleItem
    let onToggle: (Bool) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: tool.icon)
                .font(.system(size: 16))
                .foregroundStyle(tool.isEnabled ? Color.cyan : Color.secondary)
                .frame(width: 24, height: 24)

            // Name
            Text(tool.name)
                .font(.system(size: 13, weight: tool.isEnabled ? .bold : .regular))
                .foregroundStyle(.white)

            Spacer()

            // Toggle
            Toggle(
                "",
                isOn: Binding(
                    get: { tool.isEnabled },
                    set: { onToggle($0) }
                )
            )
            .toggleStyle(.switch)
            .tint(.blue)
            .glassEffect()
            .disabled(!tool.isAvailable)
        }
        .padding(12)
        .contentShape(Rectangle())
        .onHover { hover in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isHovering = hover
            }
        }
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .background(
            isHovering ? Color.white.opacity(0.05) : Color.clear
        )
        .help("\(tool.name)\n\(tool.description)")
    }
}

// MARK: - Previews

#Preview("Settings View") {
    SettingsView()
        .previewEnvironment()
}
