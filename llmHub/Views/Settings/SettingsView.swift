//
//  SettingsView.swift
//  llmHub
//
//  Simple Settings View (Canvas Style)
//  Replaces the old Glass/Neon SettingsView
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var modelRegistry: ModelRegistry
    @Environment(AFMDiagnosticsState.self) private var afmDiagnostics

    var body: some View {
        List {
            Section("Providers") {
                ForEach(modelRegistry.availableProviders(), id: \.self) { provider in
                    LabeledContent(provider) {
                        Text("Configured")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Appearance") {
                Text("Canvas Theme Active")
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: "2.0 (Canvas)")
            }

            #if DEBUG
                Section("Diagnostics") {
                    Toggle(
                        "Verbose AFM Logs",
                        isOn: Bindable(afmDiagnostics).foundationModelsDiagnosticsEnabled)

                    Button("Run AFM Probe") {
                        afmDiagnostics.runProbe()
                    }

                    Button("Run AFM Generate (small)") {
                        afmDiagnostics.runSmallGenerate()
                    }

                    if let availability = afmDiagnostics.availability {
                        LabeledContent("AFM Status", value: afmDiagnostics.reasonText)
                            .foregroundStyle(afmDiagnostics.statusColor)
                    }
                }
            #endif
        }
    }
}
