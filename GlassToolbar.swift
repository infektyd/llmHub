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
        GlassEffectContainer(spacing: spacing) {
            HStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .environment(\.glassToolbarNamespace, toolbarNamespace)
    }
}

// MARK: - Toolbar Item

struct GlassToolbarItem: View {
    @Environment(\.glassToolbarNamespace) private var namespace
    
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
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .glassEffect(
                    isActive ? .regular.tint(.glassAccent).interactive() : .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(.plain)
        .glassEffectID(id, in: namespace)
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
