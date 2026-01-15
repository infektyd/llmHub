//
//  AdvancedSettingsView.swift
//  llmHub
//
//  Advanced settings section for power users.
//  Includes auto-scroll, streaming throttle, context limits, timeouts, etc.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(\.settingsManager) private var settingsManager

    @Environment(\.uiCompactMode) private var uiCompactMode
    @Environment(\.uiScale) private var uiScale

    @AppStorage(AgentSettings.maxIterationsKey) private var agentMaxIterations: Int = AgentSettings.defaultMaxIterations

    var body: some View {
        VStack(alignment: .leading, spacing: uiCompactMode ? 16 : 20) {
            SettingsSectionHeader(
                "Advanced",
                subtitle: "Fine-tune performance and behavior"
            )

            SettingsCard {
                // Auto-scroll toggle
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.settings.autoScroll },
                        set: { settingsManager.settings.autoScroll = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-scroll")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Automatically scroll to the newest message during streaming")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Streaming throttle slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Streaming Throttle")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(settingsManager.settings.streamingThrottle) updates/sec")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Limit how frequently the UI updates during streaming to reduce CPU usage")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { Double(settingsManager.settings.streamingThrottle) },
                            set: { settingsManager.settings.streamingThrottle = Int($0) }
                        ),
                        in: 5...20,
                        step: 1
                    )
                    .tint(AppColors.accent)
                }
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Context compaction toggle
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.settings.contextCompactionEnabled },
                        set: { settingsManager.settings.contextCompactionEnabled = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Context Compaction")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Automatically compress older messages to stay within token limits")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Max context tokens slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Max Context Tokens")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(settingsManager.settings.maxContextTokens.formatted())")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Maximum number of tokens to include in conversation context")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { Double(settingsManager.settings.maxContextTokens) },
                            set: { settingsManager.settings.maxContextTokens = Int($0) }
                        ),
                        in: 1000...200000,
                        step: 1000
                    )
                    .tint(AppColors.accent)
                }
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Agent max iterations stepper
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Agent Max Iterations")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(agentMaxIterations)")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Maximum number of tool-step loops per run (guardrails: 1–200)")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Stepper(
                        value: Binding(
                            get: { AgentSettings.clampMaxIterations(agentMaxIterations) },
                            set: { agentMaxIterations = AgentSettings.clampMaxIterations($0) }
                        ),
                        in: AgentSettings.minMaxIterations...AgentSettings.maxMaxIterations
                    ) {
                        Text("")
                    }
                    .labelsHidden()
                }
                .padding(uiCompactMode ? 12 : 16)
            }

            // Second card for workspace settings
            SettingsCard {
                // Recent session limit slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Recent Sessions Limit")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(settingsManager.settings.recentSessionLimit)")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Maximum number of sessions to display in the sidebar")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { Double(settingsManager.settings.recentSessionLimit) },
                            set: { settingsManager.settings.recentSessionLimit = Int($0) }
                        ),
                        in: 10...50,
                        step: 5
                    )
                    .tint(AppColors.accent)
                }
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Auto-save interval slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Auto-save Interval")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(Int(settingsManager.settings.autoSaveInterval))s")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("How often to automatically save conversation state")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { settingsManager.settings.autoSaveInterval },
                            set: { settingsManager.settings.autoSaveInterval = $0 }
                        ),
                        in: 10...300,
                        step: 10
                    )
                    .tint(AppColors.accent)
                }
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Network timeout slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Network Timeout")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(Int(settingsManager.settings.networkTimeout))s")
                            .font(.system(size: 12 * uiScale, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    Text("Maximum time to wait for API responses before timing out")
                        .font(.system(size: 11 * uiScale))
                        .foregroundStyle(AppColors.textTertiary)

                    Slider(
                        value: Binding(
                            get: { settingsManager.settings.networkTimeout },
                            set: { settingsManager.settings.networkTimeout = $0 }
                        ),
                        in: 10...120,
                        step: 5
                    )
                    .tint(AppColors.accent)
                }
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                // Summary generation toggle
                Toggle(
                    isOn: Binding(
                        get: { settingsManager.settings.summaryGenerationEnabled },
                        set: { settingsManager.settings.summaryGenerationEnabled = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatic Summaries")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Generate conversation summaries using Apple Foundation Models")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(uiCompactMode ? 12 : 16)

                Divider()
                    .padding(.horizontal, uiCompactMode ? 12 : 16)

                Toggle(
                    isOn: Binding(
                        get: { settingsManager.settings.developerModeManualToolTriggering },
                        set: { settingsManager.settings.developerModeManualToolTriggering = $0 }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Developer Mode (Manual Tool Triggering)")
                            .font(.system(size: 14 * uiScale, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)
                        Text("Show developer-only controls to run tools manually")
                            .font(.system(size: 11 * uiScale))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .padding(uiCompactMode ? 12 : 16)
            }

            // Reset button
            HStack {
                Spacer()
                Button {
                    settingsManager.resetToDefaults()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11 * uiScale, weight: .semibold))
                        Text("Reset to Defaults")
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
        }
    }
}

// MARK: - Preview

#if DEBUG
    #Preview("Advanced Settings") {
        AdvancedSettingsView()
            .frame(width: 600, height: 800)
            .background(AppColors.backgroundPrimary)
            .environment(\.settingsManager, SettingsManager())
    }
#endif
