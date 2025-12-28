import SwiftUI

struct ToolsAvailableDebugSheet: View {
    let providerID: String
    let modelID: String
    let toolToggles: [UIToolToggleItem]

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var canonicalProviderID: String {
        ProviderID.canonicalID(from: providerID)
    }

    private var toolCallingAvailable: Bool {
        switch canonicalProviderID {
        case "openai", "anthropic", "google", "mistral", "xai", "openrouter":
            return true
        default:
            return false
        }
    }

    private var enabledToolDefinitions: [ToolDefinition] {
        toolToggles
            .filter { $0.isEnabled }
            .map { toggle in
                ToolDefinition(name: toggle.name, description: toggle.description, inputSchema: [:])
            }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tools Available (Debug)")
                        .font(.system(size: 18, weight: .semibold))
                    Text("\(canonicalProviderID) / \(modelID)")
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Tool calling: \(toolCallingAvailable ? "available" : "not available")")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.textSecondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enabled tools")
                            .font(.system(size: 14, weight: .semibold))

                        if enabledToolDefinitions.isEmpty {
                            Text("None enabled (authorize tools in Settings → General).")
                                .font(.caption)
                                .foregroundStyle(theme.textTertiary)
                        } else {
                            ForEach(enabledToolDefinitions, id: \.name) { tool in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tool.name)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.textPrimary)
                                    Text(tool.description)
                                        .font(.caption)
                                        .foregroundStyle(theme.textTertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 06)
                                        .fill(theme.surface.opacity(0.25))
                                        .glassEffect(
                                            GlassEffect.regular, in: .rect(cornerRadius: 12))
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("System tool manifest (as sent)")
                            .font(.system(size: 14, weight: .semibold))

                        Text(
                            ToolManifest.systemPrompt(
                                tools: enabledToolDefinitions,
                                toolCallingAvailable: toolCallingAvailable
                            )
                        )
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 06)
                                .fill(theme.surface.opacity(0.20))
                                .glassEffect(GlassEffect.regular, in: .rect(cornerRadius: 12))
                        )
                    }
                }
                .padding(4)
            }
        }
        .padding(16)
        .background(theme.backgroundPrimary)
    }
}
// MARK: - Previews

#Preview("Tools Available Debug") {
    ToolsAvailableDebugSheet(
        providerID: "openai",
        modelID: "gpt-4o",
        toolToggles: [
            UIToolToggleItem(
                id: "calculator",
                name: "Calculator",
                icon: "function",
                description: "Perform math calculations",
                isEnabled: true,
                isAvailable: true
            ),
            UIToolToggleItem(
                id: "read_file",
                name: "Read File",
                icon: "doc.text",
                description: "Read file contents",
                isEnabled: false,
                isAvailable: true
            ),
        ]
    )
    .frame(width: 500, height: 600)
    .previewEnvironment()
}
