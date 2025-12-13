//
//  WindowAccessor.swift
//  llmHub
//
//  Provides access to the underlying NSWindow for transparency control.
//

import SwiftUI

#if os(macOS)
    import AppKit

    /// A view modifier that enables window transparency on macOS.
    struct TransparentWindowModifier: ViewModifier {
        @Binding var opacity: Double

        func body(content: Self.Content) -> some View {
            content
                .background(WindowAccessor(opacity: opacity))
        }
    }

    /// NSViewRepresentable that accesses the underlying NSWindow to enable transparency.
    struct WindowAccessor: NSViewRepresentable {
        var opacity: Double = 1.0 // Background opacity (backgroundColor alpha)
        var alphaValue: Double = 1.0 // Window alpha value (entire window transparency)

        typealias NSViewType = NSView

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            // Defer window access to ensure the view is in the hierarchy
            DispatchQueue.main.async {
                configureWindow(for: view)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            // Update window transparency when opacity changes
            configureWindow(for: nsView)
        }

        private func configureWindow(for view: NSView) {
            guard let window = view.window else { return }

            // Update entire window alpha
            window.alphaValue = CGFloat(alphaValue)

            // Update background opacity
            if opacity < 1.0 {
                // Enable transparency
                window.isOpaque = false
                window.backgroundColor = NSColor.clear // Or custom color with alpha
                // Ideally we want the background to be transparent but window has shadow?
                // window.hasShadow = false // Optional
            } else {
                // Restore opaque window for better performance
                window.isOpaque = true
                window.backgroundColor = NSColor.windowBackgroundColor
            }
        }
    }

    extension View {
        /// Makes the window background transparent on macOS.
        /// - Parameter opacity: Binding to the background opacity (0.0 = fully transparent, 1.0 = opaque)
        func transparentWindow(opacity: Binding<Double>) -> some View {
            self.background(WindowAccessor(opacity: opacity.wrappedValue))
        }
        
        /// Controls window alpha and background opacity.
        func windowAppearance(opacity: Double, alpha: Double) -> some View {
            self.background(WindowAccessor(opacity: opacity, alphaValue: alpha))
        }

        /// Makes the window background transparent with a fixed opacity.
        func transparentWindow(opacity: Double = 0.0) -> some View {
            self.background(WindowAccessor(opacity: opacity))
        }
    }
#endif
