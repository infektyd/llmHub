// Views/Components/AdaptiveGlassBackground.swift
//
// A shape-agnostic, user-configurable glass background component.
// Integrates with LiquidGlassTokens for consistent design across the app.
//

import SwiftUI

// MARK: - AdaptiveGlassBackground

/// A reusable glass background view that adapts its intensity based on user preferences.
///
/// Each UI region (sidebar, chat area, input bar, etc.) can have its own glass intensity
/// setting, stored in `@AppStorage` and adjustable from the Settings panel.
///
/// **Usage:**
/// ```swift
/// VStack {
///     // content
/// }
/// .background {
///     AdaptiveGlassBackground(target: .chatArea)
/// }
/// ```
///
/// **Shape-Agnostic Design:**
/// By default uses a `RoundedRectangle` with semantically-appropriate corner radius.
/// For custom shapes (like capsules), use the shape parameter:
/// ```swift
/// AdaptiveGlassBackground(target: .modelPicker, shape: Capsule())
/// ```
struct AdaptiveGlassBackground<S: InsettableShape>: View {
    // MARK: - User Preferences (AppStorage)

    @AppStorage("glassIntensity.sidebar") private var sidebarIntensity: Double = 95
    @AppStorage("glassIntensity.chatArea") private var chatAreaIntensity: Double = 75
    @AppStorage("glassIntensity.inputBar") private var inputBarIntensity: Double = 65
    @AppStorage("glassIntensity.toolInspector") private var toolInspectorIntensity: Double = 65
    @AppStorage("glassIntensity.messages") private var messagesIntensity: Double = 95
    @AppStorage("glassIntensity.modelPicker") private var modelPickerIntensity: Double = 100
    @AppStorage("glassIntensity.welcomeView") private var welcomeViewIntensity: Double = 80
    @AppStorage("glassIntensity.settingsPanel") private var settingsPanelIntensity: Double = 90

    // MARK: - Environment

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Properties

    /// The target UI region this background is applied to.
    private let target: Target

    /// The shape to use for the glass effect.
    private let shape: S

    // MARK: - Types

    /// Defines the different UI regions that can have adaptive glass backgrounds.
    enum Target: String, CaseIterable {
        case sidebar
        case chatArea
        case inputBar
        case toolInspector
        case messages
        case modelPicker
        case welcomeView
        case settingsPanel

        /// Human-readable name for settings UI.
        var displayName: String {
            switch self {
            case .sidebar: return "Sidebar"
            case .chatArea: return "Chat Area"
            case .inputBar: return "Input Bar"
            case .toolInspector: return "Tool Inspector"
            case .messages: return "Messages"
            case .modelPicker: return "Model Picker"
            case .welcomeView: return "Welcome View"
            case .settingsPanel: return "Settings Panel"
            }
        }

        /// Default corner radius for this target (from LiquidGlassTokens).
        var defaultCornerRadius: CGFloat {
            switch self {
            case .sidebar:
                return LiquidGlassTokens.Radius.control
            case .chatArea:
                return LiquidGlassTokens.Radius.sheet
            case .inputBar:
                return LiquidGlassTokens.Radius.control
            case .toolInspector:
                return LiquidGlassTokens.Radius.toolCard
            case .messages:
                return LiquidGlassTokens.Radius.control
            case .modelPicker:
                return LiquidGlassTokens.Radius.control
            case .welcomeView:
                return LiquidGlassTokens.Radius.sheet
            case .settingsPanel:
                return LiquidGlassTokens.Radius.sheet
            }
        }
    }

    // MARK: - Initializer

    /// Creates an adaptive glass background with a custom shape.
    ///
    /// - Parameters:
    ///   - target: The UI region this background is for.
    ///   - shape: The shape to apply the glass effect to.
    init(target: Target, shape: S) {
        self.target = target
        self.shape = shape
    }

    // MARK: - Computed Properties

    /// The current intensity value for this target (0-100).
    private var intensity: Double {
        switch target {
        case .sidebar: return sidebarIntensity
        case .chatArea: return chatAreaIntensity
        case .inputBar: return inputBarIntensity
        case .toolInspector: return toolInspectorIntensity
        case .messages: return messagesIntensity
        case .modelPicker: return modelPickerIntensity
        case .welcomeView: return welcomeViewIntensity
        case .settingsPanel: return settingsPanelIntensity
        }
    }

    /// Whether the current theme is light mode.
    private var isLightMode: Bool {
        colorScheme == .light
    }

    // MARK: - Body

    var body: some View {
        let (glassStyle, overlayOpacity) = intensity.asGlassIntensity

        // The overlay color adapts to light/dark mode for proper contrast
        let overlayColor: Color =
            isLightMode
            ? Color.white.opacity(overlayOpacity * 0.35)
            : Color.black.opacity(overlayOpacity)

        Color.clear
            .overlay(overlayColor)
            .glassEffect(glassStyle, in: shape)
            .animation(.easeInOut(duration: 0.3), value: intensity)
            .animation(.easeInOut(duration: 0.2), value: colorScheme)
    }
}

// MARK: - Convenience Initializers

extension AdaptiveGlassBackground where S == RoundedRectangle {
    /// Creates an adaptive glass background with the default rounded rectangle shape.
    ///
    /// The corner radius is automatically determined from `LiquidGlassTokens` based on the target.
    init(target: Target) {
        self.init(
            target: target,
            shape: RoundedRectangle(
                cornerRadius: target.defaultCornerRadius,
                style: .continuous
            )
        )
    }

    /// Creates an adaptive glass background with a custom corner radius.
    init(target: Target, cornerRadius: CGFloat) {
        self.init(
            target: target,
            shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

// MARK: - View Modifier Convenience

extension View {
    /// Applies an adaptive glass background to this view.
    ///
    /// Uses the default shape for the target region.
    @ViewBuilder
    func adaptiveGlassBackground(target: AdaptiveGlassBackground<RoundedRectangle>.Target)
        -> some View
    {
        self.background {
            AdaptiveGlassBackground(target: target)
        }
    }

    /// Applies an adaptive glass background with a custom shape.
    @ViewBuilder
    func adaptiveGlassBackground<ShapeType: InsettableShape>(
        target: AdaptiveGlassBackground<ShapeType>.Target,
        shape: ShapeType
    ) -> some View {
        self.background {
            AdaptiveGlassBackground(target: target, shape: shape)
        }
    }
}

// MARK: - Preview

struct AdaptiveGlassBackground_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            // Background gradient to show glass effect
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.3), .cyan.opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Adaptive Glass Backgrounds")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)

                // Default RoundedRectangle
                Text("Chat Area (Default Shape)")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background {
                        AdaptiveGlassBackground(target: .chatArea)
                    }

                // Custom Capsule shape
                Text("Model Picker (Capsule)")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background {
                        AdaptiveGlassBackground(target: .modelPicker, shape: Capsule())
                    }

                // Sidebar style
                Text("Sidebar")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background {
                        AdaptiveGlassBackground(target: .sidebar)
                    }

                // Using the view modifier
                Text("Using View Modifier")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .adaptiveGlassBackground(target: .messages)

                Spacer()
            }
            .padding()
        }
    }
}
