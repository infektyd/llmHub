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
	        
	        final class Coordinator {
	            private var pendingWorkItem: DispatchWorkItem?
	            private var lastAppliedOpacity: Double?
	            private var lastAppliedAlphaValue: Double?
	
	            func scheduleApply(opacity: Double, alphaValue: Double, to view: NSView) {
	                guard lastAppliedOpacity != opacity || lastAppliedAlphaValue != alphaValue else { return }
	
	                pendingWorkItem?.cancel()
	                let workItem = DispatchWorkItem { [weak view] in
	                    guard let view else { return }
	                    guard let window = view.window else { return }
	
	                    window.alphaValue = CGFloat(alphaValue)
	
	                    if opacity < 1.0 {
	                        window.isOpaque = false
	                        window.backgroundColor = NSColor.clear
	                    } else {
	                        window.isOpaque = true
	                        window.backgroundColor = NSColor.windowBackgroundColor
	                    }
	
	                    self.lastAppliedOpacity = opacity
	                    self.lastAppliedAlphaValue = alphaValue
	                }
	                pendingWorkItem = workItem
	                DispatchQueue.main.async(execute: workItem)
	            }
	        }
	
	        func makeCoordinator() -> Coordinator {
	            Coordinator()
	        }

	        func makeNSView(context: Context) -> NSView {
	            let view = NSView()
	            context.coordinator.scheduleApply(opacity: opacity, alphaValue: alphaValue, to: view)
	            return view
	        }

	        func updateNSView(_ nsView: NSView, context: Context) {
	            context.coordinator.scheduleApply(opacity: opacity, alphaValue: alphaValue, to: nsView)
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
