//
//  NewChatToolbar.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI

struct NewChatToolbar: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        Button(action: {
            viewModel.startSession(providerID: "openai", model: "gpt-4o")
        }) {
            Label("New Chat", systemImage: "plus")
        }
    }
}