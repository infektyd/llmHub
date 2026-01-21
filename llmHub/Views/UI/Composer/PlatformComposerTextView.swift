//
//  PlatformComposerTextView.swift
//  llmHub
//
//  Created by Assistant.
//

import OSLog
import SwiftUI

struct PasteMetrics: Sendable {
    let charCount: Int
    let lineCount: Int
    let isRichText: Bool
    let action: PasteAction
    let pasteboardChangeCount: Int
}

enum PasteAction: String, Sendable {
    case inline
    case attach
    case ignored
}

struct PlatformComposerTextView: View {
    @Binding var text: AttributedString
    @Binding var isFocused: Bool
    var forceInlinePaste: Bool
    var onTextChange: (String) -> Void = { _ in }
    var onSelectionChange: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}
    var onPasteEvent: (PasteMetrics) -> Void = { _ in }
    var onLargePaste: (String, @escaping (String?) -> Void) -> Void = { _, completion in
        completion(nil)
    }

    var body: some View {
        #if os(macOS)
            MacComposerTextView(
                text: $text,
                isFocused: $isFocused,
                forceInlinePaste: forceInlinePaste,
                onTextChange: onTextChange,
                onSelectionChange: onSelectionChange,
                onSubmit: onSubmit,
                onPasteEvent: onPasteEvent,
                onLargePaste: onLargePaste
            )
        #else
            IOSComposerTextView(
                text: $text,
                isFocused: $isFocused,
                forceInlinePaste: forceInlinePaste,
                onTextChange: onTextChange,
                onSelectionChange: onSelectionChange,
                onSubmit: onSubmit,
                onPasteEvent: onPasteEvent,
                onLargePaste: onLargePaste
            )
        #endif
    }
}

private let pasteLogger = Logger(subsystem: "com.llmhub", category: "ComposerPaste")

#if os(iOS)
import UIKit

private struct IOSComposerTextView: UIViewRepresentable {
    @Binding var text: AttributedString
    @Binding var isFocused: Bool
    let forceInlinePaste: Bool
    let onTextChange: (String) -> Void
    let onSelectionChange: (Bool) -> Void
    let onSubmit: () -> Void
    let onPasteEvent: (PasteMetrics) -> Void
    let onLargePaste: (String, @escaping (String?) -> Void) -> Void

    func makeUIView(context: Context) -> ComposerUITextView {
        let textView = ComposerUITextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.delegate = context.coordinator
        textView.attributedText = NSAttributedString(text)
        textView.onPaste = { [weak textView] in
            guard let textView else { return }
            context.coordinator.handlePaste(in: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: ComposerUITextView, context: Context) {
        context.coordinator.parent = self
        let updatedText = NSAttributedString(text)
        if !uiView.attributedText.isEqual(to: updatedText) {
            context.coordinator.isProgrammaticUpdate = true
            uiView.attributedText = updatedText
            context.coordinator.isProgrammaticUpdate = false
        }

        if isFocused && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSComposerTextView
        var isProgrammaticUpdate = false
        private var lastPasteboardChangeCount: Int?
        private var lastPasteTimestamp: TimeInterval = 0

        init(parent: IOSComposerTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let selection = textView.selectedRange
            let textLength = textView.textStorage.length
            let isAtEnd = selection.length == 0 && selection.location == textLength
            parent.onSelectionChange(isAtEnd)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isProgrammaticUpdate else { return }
            parent.text = AttributedString(textView.attributedText)
            parent.onTextChange(textView.text ?? "")
        }

        func handlePaste(in textView: ComposerUITextView) {
            let payload = PastePayload.read()
            guard !payload.plainText.isEmpty else {
                textView.performDefaultPaste()
                return
            }

            if let last = lastPasteboardChangeCount,
                last == payload.pasteboardChangeCount,
                Date().timeIntervalSince1970 - lastPasteTimestamp < 0.2
            {
                notifyPasteEvent(
                    charCount: payload.plainText.count,
                    lineCount: payload.plainText.lineCount,
                    isRichText: payload.isRichText,
                    action: .ignored,
                    changeCount: payload.pasteboardChangeCount
                )
                return
            }

            lastPasteboardChangeCount = payload.pasteboardChangeCount
            lastPasteTimestamp = Date().timeIntervalSince1970

            let result = PasteConversionEngine.evaluate(
                text: payload.plainText,
                forceInline: parent.forceInlinePaste
            )
            let action: PasteAction = result.action == .attach ? .attach : .inline
            notifyPasteEvent(
                charCount: result.charCount,
                lineCount: result.lineCount,
                isRichText: payload.isRichText,
                action: action,
                changeCount: payload.pasteboardChangeCount
            )

            if action == .attach {
                let selection = textView.selectedRange
                parent.onLargePaste(payload.plainText) { [weak self, weak textView] stub in
                    guard let textView, let stub else { return }
                    DispatchQueue.main.async {
                        self?.insertStub(stub, in: textView, range: selection)
                    }
                }
            } else if let attributed = payload.attributedText {
                insertAttributed(attributed, in: textView)
            } else {
                textView.performDefaultPaste()
            }
        }

        private func insertAttributed(_ attributed: NSAttributedString, in textView: UITextView) {
            let range = textView.selectedRange
            isProgrammaticUpdate = true
            textView.textStorage.replaceCharacters(in: range, with: attributed)
            textView.selectedRange = NSRange(location: range.location + attributed.length, length: 0)
            isProgrammaticUpdate = false
            textView.delegate?.textViewDidChange?(textView)
        }

        private func insertStub(_ stub: String, in textView: UITextView, range: NSRange) {
            let attributes = textView.typingAttributes
            let stubAttributed = NSAttributedString(string: stub, attributes: attributes)
            isProgrammaticUpdate = true
            textView.textStorage.replaceCharacters(in: range, with: stubAttributed)
            textView.selectedRange = NSRange(location: range.location + stubAttributed.length, length: 0)
            isProgrammaticUpdate = false
            textView.delegate?.textViewDidChange?(textView)
        }

        private func notifyPasteEvent(
            charCount: Int,
            lineCount: Int,
            isRichText: Bool,
            action: PasteAction,
            changeCount: Int
        ) {
            let metrics = PasteMetrics(
                charCount: charCount,
                lineCount: lineCount,
                isRichText: isRichText,
                action: action,
                pasteboardChangeCount: changeCount
            )
            parent.onPasteEvent(metrics)
            #if DEBUG
                let typeLabel = metrics.isRichText ? "rich" : "plain"
                pasteLogger.info(
                    "[PASTE_EVENT] chars=\(metrics.charCount), lines=\(metrics.lineCount), type=\(typeLabel), action=\(metrics.action.rawValue), changeCount=\(metrics.pasteboardChangeCount)"
                )
            #endif
        }
    }
}

private final class ComposerUITextView: UITextView {
    var onPaste: (() -> Void)?

    override func paste(_ sender: Any?) {
        if let onPaste {
            onPaste()
        } else {
            super.paste(sender)
        }
    }

    func performDefaultPaste() {
        super.paste(nil)
    }
}

private struct PastePayload {
    let attributedText: NSAttributedString?
    let plainText: String
    let isRichText: Bool
    let pasteboardChangeCount: Int

    static func read(from pasteboard: UIPasteboard = .general) -> PastePayload {
        let changeCount = pasteboard.changeCount
        var attributed: NSAttributedString?

        if let rtfData = pasteboard.data(forPasteboardType: "public.rtf") {
            attributed = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else if let htmlData = pasteboard.data(forPasteboardType: "public.html") {
            attributed = try? NSAttributedString(
                data: htmlData,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            )
        }

        let plain = attributed?.string ?? pasteboard.string ?? ""
        return PastePayload(
            attributedText: attributed,
            plainText: plain,
            isRichText: attributed != nil,
            pasteboardChangeCount: changeCount
        )
    }
}
#endif

#if os(macOS)
import AppKit

private struct MacComposerTextView: NSViewRepresentable {
    @Binding var text: AttributedString
    @Binding var isFocused: Bool
    let forceInlinePaste: Bool
    let onTextChange: (String) -> Void
    let onSelectionChange: (Bool) -> Void
    let onSubmit: () -> Void
    let onPasteEvent: (PasteMetrics) -> Void
    let onLargePaste: (String, @escaping (String?) -> Void) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = ComposerNSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.onPaste = { [weak textView] in
            guard let textView else { return }
            context.coordinator.handlePaste(in: textView)
        }
        textView.onSubmit = { context.coordinator.handleSubmit() }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true

        textView.textStorage?.setAttributedString(NSAttributedString(text))
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? ComposerNSTextView else { return }

        let updatedText = NSAttributedString(text)
        if !(textView.attributedString().isEqual(to: updatedText)) {
            context.coordinator.isProgrammaticUpdate = true
            textView.textStorage?.setAttributedString(updatedText)
            context.coordinator.isProgrammaticUpdate = false
        }

        if isFocused, nsView.window?.firstResponder != textView {
            nsView.window?.makeFirstResponder(textView)
        } else if !isFocused, nsView.window?.firstResponder == textView {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacComposerTextView
        var isProgrammaticUpdate = false
        private var lastPasteboardChangeCount: Int?
        private var lastPasteTimestamp: TimeInterval = 0

        init(parent: MacComposerTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused = false
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate,
                let textView = notification.object as? NSTextView
            else { return }
            parent.text = AttributedString(textView.attributedString())
            parent.onTextChange(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selection = textView.selectedRange()
            let textLength = textView.string.utf16.count
            let isAtEnd = selection.length == 0 && selection.location == textLength
            parent.onSelectionChange(isAtEnd)
        }

        func handleSubmit() {
            parent.onSubmit()
        }

        func handlePaste(in textView: ComposerNSTextView) {
            let payload = PastePayload.read()
            guard !payload.plainText.isEmpty else {
                textView.performDefaultPaste()
                return
            }

            if let last = lastPasteboardChangeCount,
                last == payload.pasteboardChangeCount,
                Date().timeIntervalSince1970 - lastPasteTimestamp < 0.2
            {
                notifyPasteEvent(
                    charCount: payload.plainText.count,
                    lineCount: payload.plainText.lineCount,
                    isRichText: payload.isRichText,
                    action: .ignored,
                    changeCount: payload.pasteboardChangeCount
                )
                return
            }

            lastPasteboardChangeCount = payload.pasteboardChangeCount
            lastPasteTimestamp = Date().timeIntervalSince1970

            let result = PasteConversionEngine.evaluate(
                text: payload.plainText,
                forceInline: parent.forceInlinePaste
            )
            let action: PasteAction = result.action == .attach ? .attach : .inline
            notifyPasteEvent(
                charCount: result.charCount,
                lineCount: result.lineCount,
                isRichText: payload.isRichText,
                action: action,
                changeCount: payload.pasteboardChangeCount
            )

            if action == .attach {
                let range = textView.selectedRange()
                parent.onLargePaste(payload.plainText) { [weak self, weak textView] stub in
                    guard let textView, let stub else { return }
                    DispatchQueue.main.async {
                        self?.insertStub(stub, in: textView, range: range)
                    }
                }
            } else if let attributed = payload.attributedText {
                insertAttributed(attributed, in: textView)
            } else {
                textView.performDefaultPaste()
            }
        }

        private func insertAttributed(_ attributed: NSAttributedString, in textView: NSTextView) {
            let range = textView.selectedRange()
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: range, with: attributed)
            textView.setSelectedRange(
                NSRange(location: range.location + attributed.length, length: 0))
            textView.didChangeText()
            isProgrammaticUpdate = false
        }

        private func insertStub(_ stub: String, in textView: NSTextView, range: NSRange) {
            let attributes = textView.typingAttributes
            let stubAttributed = NSAttributedString(string: stub, attributes: attributes)
            isProgrammaticUpdate = true
            textView.textStorage?.replaceCharacters(in: range, with: stubAttributed)
            textView.setSelectedRange(
                NSRange(location: range.location + stubAttributed.length, length: 0))
            textView.didChangeText()
            isProgrammaticUpdate = false
        }

        private func notifyPasteEvent(
            charCount: Int,
            lineCount: Int,
            isRichText: Bool,
            action: PasteAction,
            changeCount: Int
        ) {
            let metrics = PasteMetrics(
                charCount: charCount,
                lineCount: lineCount,
                isRichText: isRichText,
                action: action,
                pasteboardChangeCount: changeCount
            )
            parent.onPasteEvent(metrics)
            #if DEBUG
                let typeLabel = metrics.isRichText ? "rich" : "plain"
                pasteLogger.info(
                    "[PASTE_EVENT] chars=\(metrics.charCount), lines=\(metrics.lineCount), type=\(typeLabel), action=\(metrics.action.rawValue), changeCount=\(metrics.pasteboardChangeCount)"
                )
            #endif
        }
    }
}

private final class ComposerNSTextView: NSTextView {
    var onPaste: (() -> Void)?
    var onSubmit: (() -> Void)?

    override func paste(_ sender: Any?) {
        if let onPaste {
            onPaste()
        } else {
            super.paste(sender)
        }
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            if !NSEvent.modifierFlags.contains(.shift) {
                onSubmit?()
                return
            }
        }
        super.doCommand(by: selector)
    }

    func performDefaultPaste() {
        super.paste(nil)
    }
}

private struct PastePayload {
    let attributedText: NSAttributedString?
    let plainText: String
    let isRichText: Bool
    let pasteboardChangeCount: Int

    static func read(from pasteboard: NSPasteboard = .general) -> PastePayload {
        let changeCount = pasteboard.changeCount
        var attributed: NSAttributedString?

        if let data = pasteboard.data(forType: .rtf) {
            attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else if let data = pasteboard.data(forType: .html) {
            attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            )
        }

        let plain = attributed?.string ?? pasteboard.string(forType: .string) ?? ""
        return PastePayload(
            attributedText: attributed,
            plainText: plain,
            isRichText: attributed != nil,
            pasteboardChangeCount: changeCount
        )
    }
}
#endif

private extension String {
    var lineCount: Int {
        components(separatedBy: .newlines).count
    }
}
