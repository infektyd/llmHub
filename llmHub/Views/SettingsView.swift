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
    
    // Code Interpreter Settings
    @AppStorage("codeInterpreter.securityMode") private var securityMode: CodeSecurityMode = .sandbox
    @AppStorage("codeInterpreter.timeout") private var executionTimeout: Int = 30
    @State private var interpreterStatus: [InterpreterInfo] = []
    @State private var isCheckingInterpreters = false
    
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
                
                Section {
                    Button("Save Keys") {
                        saveKeys()
                    }
                    .disabled(openAIKey.isEmpty && anthropicKey.isEmpty && mistralKey.isEmpty && googleKey.isEmpty && xaiKey.isEmpty && openRouterKey.isEmpty)
                }
                
                // Code Interpreter Section
                Section("Code Interpreter") {
                    Picker("Security Mode", selection: $securityMode) {
                        ForEach(CodeSecurityMode.allCases, id: \.self) { mode in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(mode.displayName)
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: mode.systemImage)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    
                    Stepper("Timeout: \(executionTimeout)s", value: $executionTimeout, in: 5...120, step: 5)
                }
                
                Section("Available Interpreters") {
                    if isCheckingInterpreters {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Checking interpreters...")
                                .foregroundStyle(.secondary)
                        }
                    } else if interpreterStatus.isEmpty {
                        Button("Check Availability") {
                            checkInterpreters()
                        }
                    } else {
                        ForEach(interpreterStatus, id: \.language) { info in
                            HStack {
                                Image(systemName: info.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(info.isAvailable ? .green : .red)
                                
                                Text(info.language.displayName)
                                
                                Spacer()
                                
                                if info.isAvailable {
                                    Text(info.version ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("Not installed")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Button("Refresh") {
                            checkInterpreters()
                        }
                        .font(.caption)
                    }
                }
                
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
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
        .frame(width: 450, height: 650)
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
    
    private func checkInterpreters() {
        isCheckingInterpreters = true
        Task {
            let tool = CodeInterpreterTool()
            let status = await tool.checkAvailability()
            await MainActor.run {
                interpreterStatus = status
                isCheckingInterpreters = false
            }
        }
    }
}


