//
//  llmHubApp.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftData
import SwiftUI

/// The main application entry point.
@main
struct llmHubApp: App {

    // MARK: - State

    /// Central registry for managing available LLM models across all providers.
    @StateObject private var modelRegistry = ModelRegistry()

    /// State for FoundationModels diagnostics
    @State private var afmDiagnostics = AFMDiagnosticsState()

    /// Settings manager for app-wide configuration
    @State private var settingsManager = SettingsManager()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(modelRegistry)
                .environment(afmDiagnostics)
                .environment(\.settingsManager, settingsManager)
                .applyUIAppearance(from: settingsManager.settings)
                .preferredColorScheme(settingsManager.settings.colorScheme.toColorScheme)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.size) { oldSize, newSize in
                                print("📐 Window resize: \(oldSize) → \(newSize)")
                            }
                    }
                )
                .task {
                    guard !PreviewMode.isRunning else { return }
                    // Log AFM availability status once on launch (debug aid for Apple Intelligence)
                    FoundationModelsDiagnostics.probe()

                    // Fetch models on app launch
                    await modelRegistry.fetchAllModels()
                }
        }
        .modelContainer(for: [
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self,
            ProjectEntity.self,
            ArtifactEntity.self,
            MemoryEntity.self,
        ])
        #if os(macOS)
            .commands {
                // Add Settings menu command
                CommandGroup(replacing: .appSettings) {
                    Button("Settings...") {
                        openSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                }
                // Keep core sidebar/menu wiring attached to the main window scene
                SidebarCommands()
            }
        #endif

        #if os(macOS)
            // Settings Window
            Settings {
                SettingsView()
                    .environmentObject(modelRegistry)
                    .environment(afmDiagnostics)
                    .environment(\.settingsManager, settingsManager)
                    .applyUIAppearance(from: settingsManager.settings)
            }
        #endif
    }

    // MARK: - Private Methods

    /// Opens the Settings window.
    private func openSettings() {
        #if os(macOS)
            if #available(macOS 14, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
        #endif
    }
}
