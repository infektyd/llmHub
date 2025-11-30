//
//  NewChatToolbar.swift
//  llmHub
//
//  Created by AI Assistant on 11/27/25.
//

import SwiftUI

struct NewChatToolbar: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var selectedProviderID = ""
    @State private var selectedModel = ""
    @State private var showConfig = false
    @State private var availableModels: [LLMModel] = []

    var body: some View {
        Button(action: { 
            showConfig = true 
            Task { await loadModels() }
        }) {
            Label("New Chat", systemImage: "plus")
        }
        .onAppear {
            if let first = viewModel.availableProviders.first {
                selectedProviderID = first.id
                Task { await loadModels() }
            }
        }
        .sheet(isPresented: $showConfig) {
            VStack(spacing: 16) {
                Text("New Session")
                    .font(.headline)
                
                Form {
                    Picker("Provider", selection: $selectedProviderID) {
                        ForEach(viewModel.availableProviders, id: \.id) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .onChange(of: selectedProviderID) {
                        Task { await loadModels() }
                    }
                    
                    if !availableModels.isEmpty {
                        Picker("Model", selection: $selectedModel) {
                            ForEach(availableModels, id: \.id) { model in
                                Text(model.displayName).tag(model.id)
                            }
                        }
                    } else {
                        HStack {
                            Text("Model")
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .formStyle(.grouped)
                
                HStack {
                    Button("Cancel") {
                        showConfig = false
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button("Start Chat") {
                        viewModel.startSession(providerID: selectedProviderID, model: selectedModel)
                        showConfig = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(availableModels.isEmpty || selectedModel.isEmpty)
                }
            }
            .padding()
            .frame(width: 350)
        }
    }
    
    private func loadModels() async {
        let models = await viewModel.fetchModels(for: selectedProviderID)
        await MainActor.run {
            availableModels = models
        }
    }
}
