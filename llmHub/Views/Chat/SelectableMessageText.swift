//
//  SelectableMessageText.swift
//  llmHub
//
//  Created by Hans Axelsson on 12/12/25.
//

import Combine
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// A specialized text view that renders Markdown and supports specific chat interactions
/// like "Add as Reference" menu items and auto-copy logic.
struct SelectableMessageText: View {
    let content: String
    let messageID: UUID
    let role: MessageRole
    @ObservedObject var interactionController: ChatInteractionController
    @Environment(\.theme) private var theme

    var body: some View {
        #if os(macOS)
            MacSelectableTextView(
                text: content,
                messageID: messageID,
                role: role,
                interactionController: interactionController,
                theme: theme
            )
        #else
            IOSSelectableTextView(
                text: content,
                messageID: messageID,
                role: role,
                interactionController: interactionController,
                theme: theme
            )
        #endif
    }
}

// MARK: - macOS Implementation

#if os(macOS)
    private struct MacSelectableTextView: NSViewRepresentable {
        let text: String
        let messageID: UUID
        let role: MessageRole
        let interactionController: ChatInteractionController
        let theme: AppTheme

        func makeNSView(context: Context) -> InternalTextView {
            let scrollView = InternalTextView.scrollableTextView()
            let textView = scrollView.documentView as! InternalTextView

            textView.textContainerInset = NSSize(width: 0, height: 0)
            textView.drawsBackground = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.allowsUndo = false

            // Remove standard styling to let us control it
            textView.textContainer?.lineFragmentPadding = 0

            textView.delegate = context.coordinator
            textView.interactionController = interactionController
            textView.messageID = messageID
            textView.messageRole = role

            return textView
        }

        func updateNSView(_ nsView: InternalTextView, context: Context) {
            // Only update if content changed to avoid losing selection
            if nsView.string != text {
                // Simple Parse Logic
                // In a real app, we'd use a better parser or cache.
                // For now, use AttributedString with markdown options

                let attributed = parseMarkdown(text, theme: theme)
                nsView.textStorage?.setAttributedString(attributed)
                nsView.font = NSFont.systemFont(ofSize: 14)  // Fallback
                nsView.textColor = NSColor(theme.textPrimary)
            }

            // Update context refs just in case
            nsView.interactionController = interactionController
            nsView.messageID = messageID
            nsView.messageRole = role
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, NSTextViewDelegate {
            var parent: MacSelectableTextView

            init(_ parent: MacSelectableTextView) {
                self.parent = parent
            }

            func textViewDidChangeSelection(_ notification: Notification) {
                guard let textView = notification.object as? InternalTextView else { return }

                let range = textView.selectedRange()
                if range.length > 0,
                    let text = (textView.string as NSString).substring(with: range) as String?
                {
                    parent.interactionController.handleSelectionChange(
                        text: text,
                        messageID: parent.messageID,
                        role: parent.role
                    )
                } else {
                    parent.interactionController.handleSelectionChange(
                        text: nil,
                        messageID: nil,
                        role: nil
                    )
                }
            }
        }

        // Internal subclass to override menu
        class InternalTextView: NSTextView {
            var interactionController: ChatInteractionController?
            var messageID: UUID?
            var messageRole: MessageRole?

            override func menu(for event: NSEvent) -> NSMenu? {
                let menu = super.menu(for: event) ?? NSMenu()

                // Add custom reference item if there is a selection
                if selectedRange().length > 0 {
                    menu.insertItem(NSMenuItem.separator(), at: 0)

                    let refItem = NSMenuItem(
                        title: "Add as Reference",
                        action: #selector(addAsReference),
                        keyEquivalent: ""
                    )
                    refItem.target = self
                    refItem.image = NSImage(
                        systemSymbolName: "quote.bubble",
                        accessibilityDescription: "Add as Reference")

                    menu.insertItem(refItem, at: 0)
                }

                return menu
            }

            @objc func addAsReference() {
                guard let range = Range(selectedRange(), in: string) else { return }
                let selectedText = String(string[range])

                interactionController?.handleSelectionChange(
                    text: selectedText,
                    messageID: messageID,
                    role: messageRole
                )
                interactionController?.addSelectionAsReference()
            }

            // Disable intrinsic size to allow height usage in SwiftUI properly?
            // Actually for chat bubbles we typically want it to fit content.
            // NSTextView is scrollable by default, but we wrap it in a plain view usually.
            // Here we use the standard scrollable constructor but might need to invalidate intrinsic content size.
        }

        private func parseMarkdown(_ text: String, theme: AppTheme) -> NSAttributedString {
            // Fallback or basic markdown parsing
            // Since we claimed "Core Markdown Only", we can use `try? AttributedString(markdown: ...)`
            // and convert to NSAttributedString.

            do {
                var options = AttributedString.MarkdownParsingOptions()
                options.interpretedSyntax = .inlineOnlyPreservingWhitespace  // Keep it simple first

                // Actually let's try standard parsing
                let attributed = try AttributedString(markdown: text)
                return NSAttributedString(attributed)
            } catch {
                return NSAttributedString(
                    string: text,
                    attributes: [
                        .foregroundColor: NSColor(theme.textPrimary),
                        .font: NSFont.systemFont(ofSize: 14),  // Check theme font
                    ])
            }
        }
    }
#endif

// MARK: - iOS Implementation

#if os(iOS)
    private struct IOSSelectableTextView: UIViewRepresentable {
        let text: String
        let messageID: UUID
        let role: MessageRole
        let interactionController: ChatInteractionController
        let theme: AppTheme

        func makeUIView(context: Context) -> InternalTextView {
            let textView = InternalTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false  // Let SwiftUI handle scrolling container
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0

            textView.delegate = context.coordinator
            textView.interactionController = interactionController
            textView.messageID = messageID
            textView.messageRole = role

            return textView
        }

        func updateUIView(_ uiView: InternalTextView, context: Context) {
            if uiView.text != text {
                // Apply markdown
                uiView.attributedText = parseMarkdown(text, theme: theme)
            }
            uiView.interactionController = interactionController
            uiView.messageID = messageID
            uiView.messageRole = role
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UITextViewDelegate {
            var parent: IOSSelectableTextView

            init(_ parent: IOSSelectableTextView) {
                self.parent = parent
            }

            func textViewDidChangeSelection(_ textView: UITextView) {
                guard let range = textView.selectedTextRange,
                    let text = textView.text(in: range),
                    !text.isEmpty
                else {
                    return
                }

                parent.interactionController.handleSelectionChange(
                    text: text,
                    messageID: parent.messageID,
                    role: parent.role
                )
            }
        }

        class InternalTextView: UITextView {
            var interactionController: ChatInteractionController?
            var messageID: UUID?
            var messageRole: MessageRole?

            override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
                if action == #selector(addAsReference) {
                    return true
                }
                return super.canPerformAction(action, withSender: sender)
            }

            // For iOS 16+, ideally override `editMenu(for:)` but to keep compat we can add menu item to UIMenuController?
            // Wait, UIMenuController is deprecated in iOS 16. We should use `editMenu(for:)`.

            override func editMenu(for textRange: UITextRange, suggestedActions: [UIMenuElement])
                -> UIMenu?
            {
                let refAction = UIAction(
                    title: "Add as Reference", image: UIImage(systemName: "quote.bubble")
                ) { [weak self] _ in
                    self?.addAsReference()
                }

                // Insert at the beginning
                var newActions = suggestedActions
                newActions.insert(refAction, at: 0)

                return UIMenu(children: newActions)
            }

            @objc func addAsReference() {
                interactionController?.addSelectionAsReference()
            }
        }

        private func parseMarkdown(_ text: String, theme: AppTheme) -> NSAttributedString {
            do {
                let attributed = try AttributedString(markdown: text)
                let nsAttr = NSAttributedString(attributed)

                let mutable = NSMutableAttributedString(attributedString: nsAttr)
                mutable.addAttribute(
                    .foregroundColor, value: UIColor(theme.textPrimary),
                    range: NSRange(location: 0, length: mutable.length))
                // Apply font if needed
                return mutable
            } catch {
                return NSAttributedString(
                    string: text,
                    attributes: [
                        .foregroundColor: UIColor(theme.textPrimary)
                    ])
            }
        }
    }
#endif
