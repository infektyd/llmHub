//
//  GlassToolbar.swift
//  llmHub
//
//  Liquid Glass toolbar with automatic morphing support.
//

import SwiftUI

struct GlassToolbar<Content: View>: View {
    @Namespace private var toolbarNamespace
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .environment(\.glassToolbarNamespace, toolbarNamespace)
        }
    }
}

// MARK: - Toolbar Item

struct GlassToolbarItem: View {
    @Environment(\.glassToolbarNamespace) private var namespace
    @Environment(\.theme) private var theme

    let id: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    init(id: String, icon: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        if let ns = namespace {
            baseButton
                .glassEffectID(id, in: ns)
        } else {
            baseButton
        }
    }

    @ViewBuilder
    private var baseButton: some View {
        Button(action: action) {
            if theme.usesGlassEffect {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .glassEffect(
                        isActive
                            ? .regular.tint(Color.accentColor.opacity(0.25)).interactive()
                            : .regular.interactive(),
                        in: .circle
                    )
            } else {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .background(isActive ? theme.accent.opacity(0.2) : theme.surface)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                isActive
                                    ? theme.accent.opacity(0.4)
                                    : theme.textTertiary.opacity(0.15),
                                lineWidth: theme.borderWidth
                            )
                    )
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toolbar Divider

struct GlassToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 1, height: 24)
    }
}

// MARK: - Environment Key

private struct GlassToolbarNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var glassToolbarNamespace: Namespace.ID? {
        get { self[GlassToolbarNamespaceKey.self] }
        set { self[GlassToolbarNamespaceKey.self] = newValue }
    }
}

// MARK: - View Extension for Conditional Modifiers

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("Glass Toolbar") {
    VStack {
        GlassToolbar {
            GlassToolbarItem(id: "home", icon: "house.fill", isActive: true) {}
            GlassToolbarItem(id: "search", icon: "magnifyingglass") {}
            GlassToolbarDivider()
            GlassToolbarItem(id: "settings", icon: "gearshape.fill") {}
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}
