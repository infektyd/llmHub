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
    
    var body: some View {
        TabView {
            // MARK: - API Keys Tab
            APIKeysSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("API Keys", systemImage: "key.fill")
                }
                .tag(0)
            
            // MARK: - General Tab (Future)
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(1)
        }
        .frame(width: 600, height: 500)
        .background(Color.neonMidnight)
    }
}

// MARK: - API Keys Settings

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
                    
                    Text("Configure API keys for each LLM provider. Keys are securely stored in the system Keychain.")
                        .font(.system(size: 13))
                        .foregroundColor(.neonGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
                
                Divider()
                    .background(Color.neonGray.opacity(0.3))
                
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
                        Image(systemName: viewModel.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundColor(viewModel.isError ? .neonFuchsia : .green)
                        
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(viewModel.isError ? .neonFuchsia : .green)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(viewModel.isError ? Color.neonFuchsia.opacity(0.1) : Color.green.opacity(0.1))
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(24)
        }
        .background(Color.neonMidnight)
        .onAppear {
            viewModel.loadKeys()
        }
    }
}

// MARK: - Provider Key Row

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
                    .foregroundColor(.neonElectricBlue)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    
                    if let description = info.description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(.neonGray)
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
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isFocused ? Color.neonElectricBlue : Color.neonGray.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Toggle Visibility
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.neonGray)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
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
                        RoundedRectangle(cornerRadius: 6)
                            .fill(apiKey.isEmpty ? Color.neonGray.opacity(0.3) : Color.neonElectricBlue)
                    )
                }
                .buttonStyle(.plain)
                .disabled(apiKey.isEmpty || isSaving)
                
                // Delete Button
                if hasKey {
                    Button(action: onDelete) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.neonFuchsia)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.neonFuchsia.opacity(0.1))
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
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.neonElectricBlue)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(hasKey ? Color.green.opacity(0.3) : Color.neonGray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - General Settings (Placeholder)

struct GeneralSettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("General Settings")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            
            Text("More settings coming soon...")
                .font(.system(size: 13))
                .foregroundColor(.neonGray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.neonMidnight)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .preferredColorScheme(.dark)
}
