//
//  LiquidGlassTheme.swift
//  llmHub
//
//  Liquid Glass Design System - Core modifiers and glass effects.
//  Scaffolded for future integration; see LiquidGlassMigration.md for activation steps.
//

import SwiftUI

// MARK: - Glass Modifier

/// Applies glass morphism effect to any shape
struct GlassModifier: ViewModifier {
    let glass: Glass
    let shape: AnyShape
    
    func body(content: Content) -> some View {
        content
            .background(glass.background, in: shape)
            .overlay(shape.stroke(glass.border, lineWidth: glass.borderWidth))
            .shadow(color: glass.shadow.color, radius: glass.shadow.radius)
    }
}

extension View {
    /// Apply glass morphism effect with custom shape
    func glassEffect(_ glass: Glass, in shape: AnyShape) -> some View {
        modifier(GlassModifier(glass: glass, shape: shape))
    }
    
    /// Apply standard glass card effect
    func glassCard(_ style: Glass = .regular) -> some View {
        modifier(GlassModifier(glass: style, shape: .rect(cornerRadius: 16)))
    }
    
    /// Apply pill-shaped glass (rounded rectangle)
    func glassPill(_ style: Glass = .regular) -> some View {
        modifier(GlassModifier(glass: style, shape: .capsule))
    }
    
    /// Apply glass effect with custom corner radius
    func glassRounded(_ cornerRadius: CGFloat, style: Glass = .regular) -> some View {
        modifier(GlassModifier(glass: style, shape: .rect(cornerRadius: cornerRadius)))
    }
}

// MARK: - Glass Configuration

/// Configures appearance of glass morphism effect
struct Glass: Equatable {
    // Appearance
    let background: AnyShapeStyle
    let border: Color
    let borderWidth: CGFloat
    let shadow: GlassShadow
    
    // Tint color (optional)
    private let tintColor: Color?
    private let isInteractive: Bool
    
    // MARK: - Presets
    
    /// Standard glass effect - frosted, subtle tint
    static let regular = Glass(
        background: AnyShapeStyle(.ultraThinMaterial),
        border: Color.white.opacity(0.2),
        borderWidth: 1.0,
        shadow: GlassShadow(color: .black, radius: 10, opacity: 0.1),
        tintColor: nil,
        isInteractive: false
    )
    
    /// Elevated glass - more prominent material, stronger shadow
    static let elevated = Glass(
        background: AnyShapeStyle(.thinMaterial),
        border: Color.white.opacity(0.3),
        borderWidth: 1.5,
        shadow: GlassShadow(color: .black, radius: 20, opacity: 0.15),
        tintColor: nil,
        isInteractive: false
    )
    
    /// Interactive glass - responds to user interaction
    static let interactive = Glass(
        background: AnyShapeStyle(.thinMaterial),
        border: Color.white.opacity(0.4),
        borderWidth: 1.5,
        shadow: GlassShadow(color: .black, radius: 15, opacity: 0.12),
        tintColor: nil,
        isInteractive: true
    )
    
    /// Prominent glass - strong material, high contrast
    static let prominent = Glass(
        background: AnyShapeStyle(.thickMaterial),
        border: Color.white.opacity(0.4),
        borderWidth: 2.0,
        shadow: GlassShadow(color: .black, radius: 25, opacity: 0.2),
        tintColor: nil,
        isInteractive: false
    )
    
    /// Dark mode glass - optimized for dark backgrounds
    static let dark = Glass(
        background: AnyShapeStyle(.ultraThinMaterial),
        border: Color.white.opacity(0.15),
        borderWidth: 1.0,
        shadow: GlassShadow(color: .black, radius: 12, opacity: 0.2),
        tintColor: nil,
        isInteractive: false
    )
    
    // MARK: - Modifiers
    
    /// Apply color tint to glass
    func tint(_ color: Color) -> Glass {
        Glass(
            background: AnyShapeStyle(Color(nsColor: NSColor(cgColor: color.cgColor!)).opacity(0.1)),
            border: border,
            borderWidth: borderWidth,
            shadow: shadow,
            tintColor: color,
            isInteractive: isInteractive
        )
    }
    
    /// Make glass interactive (hover states, etc.)
    func interactive() -> Glass {
        Glass(
            background: background,
            border: Color.white.opacity(0.4),
            borderWidth: borderWidth,
            shadow: shadow,
            tintColor: tintColor,
            isInteractive: true
        )
    }
    
    /// Adjust transparency of glass
    func opacity(_ value: Double) -> Glass {
        Glass(
            background: AnyShapeStyle(Color.white.opacity(value * 0.1)),
            border: border,
            borderWidth: borderWidth,
            shadow: shadow,
            tintColor: tintColor,
            isInteractive: isInteractive
        )
    }
}

// MARK: - Shadow Configuration

struct GlassShadow: Equatable {
    let color: Color
    let radius: CGFloat
    let opacity: Double
    
    var effectiveColor: Color {
        color.opacity(opacity)
    }
}

// MARK: - Shape Wrapper

/// Type-erased shape for use in glass modifier
struct AnyShape: Shape {
    private let path: (CGRect) -> Path
    
    init<S: Shape>(_ shape: S) {
        self.path = { shape.path(in: $0) }
    }
    
    func path(in rect: CGRect) -> Path {
        path(rect)
    }
    
    // MARK: - Common Shapes
    
    static func rect(cornerRadius: CGFloat) -> AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    static var capsule: AnyShape {
        AnyShape(Capsule())
    }
    
    static var circle: AnyShape {
        AnyShape(Circle())
    }
    
    static func rounded(_ cornerRadius: CGFloat) -> AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Button Styles

/// Glass card button style - raised, interactive
struct GlassButtonStyle: ButtonStyle {
    let glass: Glass
    
    @State private var isPressed = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCard(isPressed ? glass.interactive() : glass)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .onChange(of: configuration.isPressed) { newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPressed = newValue
                }
            }
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    /// Glass morphism button style (standard)
    static var glass: GlassButtonStyle {
        GlassButtonStyle(glass: .regular)
    }
    
    /// Glass morphism button style (prominent)
    static var glassProminent: GlassButtonStyle {
        GlassButtonStyle(glass: .prominent)
    }
    
    /// Glass morphism button style with custom style
    static func glass(_ style: Glass) -> GlassButtonStyle {
        GlassButtonStyle(glass: style)
    }
}

// MARK: - Preview

#Preview("Glass Effects") {
    VStack(spacing: 20) {
        // Regular glass
        VStack {
            Text("Regular Glass")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack {
                Text("Standard effect")
                    .foregroundStyle(.white)
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .glassCard()
        }
        
        // Elevated glass
        VStack {
            Text("Elevated Glass")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack {
                Text("Stronger material & shadow")
                    .foregroundStyle(.white)
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .glassCard(.elevated)
        }
        
        // Interactive button
        VStack {
            Text("Interactive Glass Button")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button("Click Me") { }
                .buttonStyle(.glass)
        }
        
        // Tinted glass
        VStack {
            Text("Tinted Glass")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Success state")
                }
                .foregroundStyle(.green)
            }
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .glassCard(.regular.tint(.green))
        }
        
        Spacer()
    }
    .padding()
    .background(
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.1, green: 0.15, blue: 0.25),
                Color(red: 0.15, green: 0.1, blue: 0.2)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
