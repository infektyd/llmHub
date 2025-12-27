//
//  NordicButton.swift
//  llmHub
//
//  Primary (terracotta) and secondary (sage) button variants.
//

import SwiftUI

/// Button style variants for Nordic theme
enum NordicButtonStyle {
    case primary  // Terracotta fill
    case secondary  // Sage fill
    case ghost  // No fill, just text
}

/// A clean, minimalist button with hover states
struct NordicButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let style: NordicButtonStyle
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, style: NordicButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(textColor)
                .padding(.horizontal, 08)
                .padding(.vertical, 05)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(backgroundColor)
            .opacity(isHovered ? 0.9 : 1.0)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return Color(red: 0.804, green: 0.435, blue: 0.306)  // CD6F4E - Terracotta
        case .secondary:
            return Color(red: 0.482, green: 0.639, blue: 0.51)  // 7BA382 - Sage
        case .ghost:
            return Color.clear
        }
    }

    private var textColor: Color {
        switch style {
        case .primary, .secondary:
            return .white
        case .ghost:
            return NordicColors.textPrimary(colorScheme)
        }
    }
}

// MARK: - Previews

#Preview("All Variants - Light") {
    VStack(spacing: 20) {
        Text("Nordic Buttons - Light Mode")
            .font(.title2.bold())
        
        VStack(spacing: 16) {
            NordicButton("Primary Button", style: .primary) {
                print("Primary tapped")
            }
            
            NordicButton("Secondary Button", style: .secondary) {
                print("Secondary tapped")
            }
            
            NordicButton("Ghost Button", style: .ghost) {
                print("Ghost tapped")
            }
        }
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("All Variants - Dark") {
    VStack(spacing: 20) {
        Text("Nordic Buttons - Dark Mode")
            .font(.title2.bold())
            .foregroundColor(.white)
        
        VStack(spacing: 16) {
            NordicButton("Primary Button", style: .primary) {
                print("Primary tapped")
            }
            
            NordicButton("Secondary Button", style: .secondary) {
                print("Secondary tapped")
            }
            
            NordicButton("Ghost Button", style: .ghost) {
                print("Ghost tapped")
            }
        }
    }
    .padding()
    .background(Color(red: 0.11, green: 0.098, blue: 0.09))
    .preferredColorScheme(.dark)
}

#Preview("Primary Only") {
    NordicButton("Click Me", style: .primary) {}
        .padding()
}
