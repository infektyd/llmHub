//
//  llmHubApp.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftData
import SwiftUI

@main
struct llmHubApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            ChatSessionEntity.self,
            ChatMessageEntity.self,
            ChatFolderEntity.self,
            ChatTagEntity.self,
        ])
    }
}
