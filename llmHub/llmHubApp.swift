//
//  llmHubApp.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI
import SwiftData

@main
struct llmHubApp: App {
    var body: some Scene {
        WindowGroup {
            RootContainerView()
        }
        .modelContainer(for: [ChatSessionEntity.self, ChatMessageEntity.self])
    }
}
