//
//  WindowBackgroundStyle.swift
//  llmHub
//
//  Native SwiftUI window background styles for macOS 26+.
//

import SwiftUI

/// Window background style options
enum WindowBackgroundStyle: String, CaseIterable, Identifiable {
    /// Airy: True transparency, desktop wallpaper shows through
    case airy = "Airy"

    /// Grounded: Frosted glass pane, app has presence but still translucent
    case grounded = "Grounded"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .airy:
            return "Floating UI elements on your desktop"
        case .grounded:
            return "Frosted glass window with presence"
        }
    }

    var iconName: String {
        switch self {
        case .airy:
            return "cloud"
        case .grounded:
            return "square.fill"
        }
    }
}

// MARK: - Native Window Background View

/// A view that applies the appropriate native background based on the selected style
struct NativeWindowBackground: View {
    let style: WindowBackgroundStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch style {
        case .airy:
            // True transparency - just clear, let the window handle it
            Color.clear
                .ignoresSafeArea()

        case .grounded:
            // Native frosted glass pane
            Color.clear
                .glassEffect(.regular, in: Rectangle())
                .ignoresSafeArea()
        }
    }
}

#Preview("Airy") {
    NativeWindowBackground(style: .airy)
}

#Preview("Grounded") {
    NativeWindowBackground(style: .grounded)
}

// MARK: - Settings Picker Component

#if os(macOS)
    /// A picker component for Settings to switch between Airy and Grounded modes
    struct WindowStylePicker: View {
        @AppStorage("windowBackgroundStyle") private var selectedStyleRaw: String =
            WindowBackgroundStyle.grounded.rawValue

        private var selectedStyle: WindowBackgroundStyle {
            WindowBackgroundStyle(rawValue: selectedStyleRaw) ?? .grounded
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("Window Style", systemImage: "macwindow")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal)

                HStack(spacing: 0) {
                    ForEach(WindowBackgroundStyle.allCases) { style in
                        let isSelected = selectedStyle == style

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedStyleRaw = style.rawValue
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: style.iconName)
                                    .font(.system(size: 12))

                                Text(style.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .semibold : .medium)
                            }
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        isSelected
                                            ? Color.neonElectricBlue.opacity(0.3) : Color.clear
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                isSelected
                                                    ? Color.neonElectricBlue.opacity(0.6) : .clear,
                                                lineWidth: 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(.white.opacity(0.05), lineWidth: 1)
                        )
                )
                .padding(.horizontal)

                // Description
                Text(selectedStyle.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
        }
    }

    #Preview("Window Style Picker") {
        WindowStylePicker()
            .padding()
            .background(Color.black)
    }
#endif
