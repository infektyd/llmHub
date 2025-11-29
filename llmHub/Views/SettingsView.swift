//
//  SettingsView.swift
//  llmHub
//
//  Created by AI Assistant on 11/29/25.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.keychainStore) private var keychainStore
    
    @State private var openAIKey = ""
    @State private var anthropicKey = ""
    @State private var mistralKey = ""
    @State private var googleKey = ""
    @State private var xaiKey = ""
    @State private var openRouterKey = ""
    
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("API Keys") {
                    SecureField("OpenAI API Key", text: $openAIKey)
                    SecureField("Anthropic API Key", text: $anthropicKey)
                    SecureField("Mistral API Key", text: $mistralKey)
                    SecureField("Google AI API Key", text: $googleKey)
                    SecureField("xAI API Key", text: $xaiKey)
                    SecureField("OpenRouter API Key", text: $openRouterKey)
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                
                Section {
                    Button("Save Keys") {
                        saveKeys()
                    }
                    .disabled(openAIKey.isEmpty && anthropicKey.isEmpty && mistralKey.isEmpty && googleKey.isEmpty && xaiKey.isEmpty && openRouterKey.isEmpty)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear(perform: loadKeys)
        }
        .frame(width: 400, height: 500)
    }
    
    private func loadKeys() {
        openAIKey = keychainStore.apiKey(for: .openAI) ?? ""
        anthropicKey = keychainStore.apiKey(for: .anthropic) ?? ""
        mistralKey = keychainStore.apiKey(for: .mistral) ?? ""
        googleKey = keychainStore.apiKey(for: .google) ?? ""
        xaiKey = keychainStore.apiKey(for: .xai) ?? ""
        openRouterKey = keychainStore.apiKey(for: .openRouter) ?? ""
    }
    
    private func saveKeys() {
        do {
            if !openAIKey.isEmpty { try keychainStore.updateKey(openAIKey, for: .openAI) }
            if !anthropicKey.isEmpty { try keychainStore.updateKey(anthropicKey, for: .anthropic) }
            if !mistralKey.isEmpty { try keychainStore.updateKey(mistralKey, for: .mistral) }
            if !googleKey.isEmpty { try keychainStore.updateKey(googleKey, for: .google) }
            if !xaiKey.isEmpty { try keychainStore.updateKey(xaiKey, for: .xai) }
            if !openRouterKey.isEmpty { try keychainStore.updateKey(openRouterKey, for: .openRouter) }
            dismiss()
        } catch {
            errorMessage = "Failed to save keys: \(error.localizedDescription)"
        }
    }
}

