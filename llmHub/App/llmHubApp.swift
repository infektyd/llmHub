//
//  llmHubApp.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import Foundation
import SwiftData
import SwiftUI

/// The main application entry point.
@main
struct llmHubApp: App {

    // MARK: - State

    /// Central registry for managing available LLM models across all providers.
    @StateObject private var modelRegistry: ModelRegistry

    /// State for FoundationModels diagnostics
    @State private var afmDiagnostics: AFMDiagnosticsState

    /// Settings manager for app-wide configuration
    @State private var settingsManager: SettingsManager

    private let modelContainer: ModelContainer

    // MARK: - Body

    init() {
        if PreviewMode.isRunning {
            _modelRegistry = StateObject(wrappedValue: ModelRegistry())
            _afmDiagnostics = State(initialValue: AFMDiagnosticsState())
            _settingsManager = State(
                initialValue: SettingsManager(
                    userDefaults: UserDefaults(suiteName: "llmHub.preview") ?? .standard
                )
            )
        } else {
            _modelRegistry = StateObject(wrappedValue: ModelRegistry())
            _afmDiagnostics = State(initialValue: AFMDiagnosticsState())
            _settingsManager = State(initialValue: SettingsManager())
        }

        let schema = Schema([
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self,
            ProjectEntity.self,
            ArtifactEntity.self,
            MemoryEntity.self
        ])

        if PreviewMode.isRunning {
            print("SwiftData: initializing ModelContainer (Preview in-memory)")

            do {
                let configuration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                modelContainer = try ModelContainer(for: schema, configurations: [configuration])
                print("SwiftData: ModelContainer initialized successfully")
            } catch {
                print("Unresolved error loading container", error)
                let fallbackConfiguration = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true
                )
                modelContainer = try! ModelContainer(for: schema, configurations: [fallbackConfiguration])
                print("SwiftData: using in-memory fallback container")
            }
            return
        }

        Self.ensureDataDirectoriesExist()
        
        #if DEBUG
        ArtifactImportDiagnostics.isEnabled = true
        print("🔍 Artifact import diagnostics enabled (DEBUG build)")
        #endif

        print("SwiftData: initializing ModelContainer (CloudKit disabled)")

        do {
            let configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .none
            )
            modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            print("SwiftData: ModelContainer initialized successfully")
        } catch {
            print("Unresolved error loading container", error)
            let fallbackConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )
            modelContainer = try! ModelContainer(for: schema, configurations: [fallbackConfiguration])
            print("SwiftData: using in-memory fallback container")
        }
    }

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
                    
                    // Bootstrap iCloud workspace
                    await bootstrapCloudWorkspace()
                }
        }
        .modelContainer(modelContainer)
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
            .modelContainer(modelContainer)
        #endif
    }

    // MARK: - Private Methods

    private static func ensureDataDirectoriesExist() {
        let fileManager = FileManager.default
        guard
            let appSupportURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            print("Could not locate Application Support directory.")
            return
        }

        do {
            try fileManager.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            print("Could not create Application Support directory: \(error)")
        }
    }

    /// Bootstraps the iCloud workspace, logging availability and ensuring the default workspace exists.
    private func bootstrapCloudWorkspace() async {
        let manager = CloudWorkspaceManager.shared
        
        // 1. Log iCloud container availability
        let containerURL = await manager.containerURL()
        if let url = containerURL {
            print("🌥️ iCloud container available: \(url.path)")
        } else {
            print("⚠️ iCloud container unavailable — using local fallback")
        }
        
        // 2. Ensure default workspace exists
        let defaultID = manager.defaultWorkspaceID()
        do {
            let workspaceURL = try await manager.getOrCreateWorkspace(id: defaultID)
            print("📁 Default workspace ready: \(workspaceURL.path)")
        } catch {
            print("❌ Failed to create default workspace: \(error.localizedDescription)")
        }
    }
    
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
