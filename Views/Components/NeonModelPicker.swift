//
//  NeonModelPicker.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/01/25.
//

import SwiftUI

struct NeonModelPicker: View {
    @Binding var selectedProvider: UILLMProvider?
    @Binding var selectedModel: UILLMModel?
    @State private var isExpanded = false

    var body: some View {
        Menu {
            ForEach(UILLMProvider.sampleProviders) { provider in
                Menu {
                    ForEach(provider.models) { model in
                        Button(action: {
                            selectedProvider = provider
                            selectedModel = model
                        }) {
                            HStack {
                                Text(model.name)
                                if selectedModel?.id == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.neonFuchsia)
                                }
                            }
                        }
                    }
                } label: {
                    Label(provider.name, systemImage: provider.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let provider = selectedProvider {
                    Image(systemName: provider.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.neonElectricBlue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let provider = selectedProvider {
                        Text(provider.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.neonGray)
                    }
                    if let model = selectedModel {
                        Text(model.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.neonGray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.neonFuchsia.opacity(0.5), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
