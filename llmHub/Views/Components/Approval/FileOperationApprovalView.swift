//
//  FileOperationApprovalView.swift
//  llmHub
//
//  Approval dialog for file operations with diff preview
//

import SwiftUI

/// View for approving file operations with a diff preview.
struct FileOperationApprovalView: View {
    /// The preview of the file operation to approve.
    let preview: FileOperationPreview
    /// Action to perform when approved.
    let onApprove: () -> Void
    /// Action to perform when rejected.
    let onReject: () -> Void

    @State private var showFullDiff = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Diff content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Operation summary
                    operationSummary

                    Divider()

                    // Diff preview
                    if showFullDiff {
                        diffPreview
                    }
                }
                .padding()
            }

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(minWidth: 500, idealWidth: 700, minHeight: 400, idealHeight: 600)
        #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
        #else
            .background(Color(uiColor: .systemBackground))
        #endif
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: preview.request.operation.systemImage)
                .font(.title2)
                .foregroundColor(operationColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(preview.request.operation.displayName) File")
                    .font(.headline)

                Text(preview.request.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Toggle("Show Diff", isOn: $showFullDiff)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding()
        #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
        #else
            .background(Color(uiColor: .secondarySystemBackground))
        #endif
    }

    // MARK: - Operation Summary

    private var operationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operation Details")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Operation:")
                        .foregroundColor(.secondary)
                    Text(preview.request.operation.displayName)
                        .fontWeight(.medium)
                }

                GridRow {
                    Text("Path:")
                        .foregroundColor(.secondary)
                    Text(preview.request.path)
                        .font(.system(.body, design: .monospaced))
                }

                if let destination = preview.request.destination {
                    GridRow {
                        Text("Destination:")
                            .foregroundColor(.secondary)
                        Text(destination)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                if preview.request.operation == .edit,
                    let oldString = preview.request.oldString,
                    let newString = preview.request.newString
                {
                    GridRow {
                        Text("Find:")
                            .foregroundColor(.secondary)
                        Text(oldString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 4)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(2)
                    }

                    GridRow {
                        Text("Replace:")
                            .foregroundColor(.secondary)
                        Text(newString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(2)
                    }
                }

                if let content = preview.request.content {
                    GridRow {
                        Text("Content:")
                            .foregroundColor(.secondary)
                        Text("\(content.count) characters")
                    }
                }
            }
        }
        .padding()
        #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
        #else
            .background(Color(uiColor: .secondarySystemBackground))
        #endif
        .cornerRadius(8)
    }

    // MARK: - Diff Preview

    private var diffPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Changes Preview")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(addedLinesCount) additions, \(removedLinesCount) deletions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(preview.diffLines.enumerated()), id: \.offset) { index, line in
                        DiffLineView(line: line)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(.body, design: .monospaced))
            #if os(macOS)
                .background(Color(nsColor: .textBackgroundColor))
            #else
                .background(Color(uiColor: .tertiarySystemBackground))
            #endif
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var addedLinesCount: Int {
        preview.diffLines.filter { $0.type == .added }.count
    }

    private var removedLinesCount: Int {
        preview.diffLines.filter { $0.type == .removed }.count
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Button(action: onReject) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Reject")
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .buttonStyle(.bordered)

            Spacer()

            Text("This will modify files on your system")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onApprove) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Approve")
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .tint(operationColor)
        }
        .padding()
    }

    // MARK: - Helpers

    private var operationColor: Color {
        switch preview.request.operation {
        case .create, .copy:
            return .green
        case .edit, .append:
            return .blue
        case .rename, .move:
            return .orange
        case .delete:
            return .red
        }
    }
}

// MARK: - Diff Line View

/// View for displaying a single line in a diff.
struct DiffLineView: View {
    /// The diff line data.
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            // Line number
            if let lineNum = line.lineNumber {
                Text(String(format: "%4d", lineNum))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
                    .padding(.trailing, 8)
            } else {
                Spacer()
                    .frame(width: 48)
            }

            // Prefix
            Text(linePrefix)
                .foregroundColor(lineColor)
                .frame(width: 20, alignment: .center)

            // Content
            Text(line.content)
                .foregroundColor(lineColor)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(backgroundColor)
    }

    private var linePrefix: String {
        switch line.type {
        case .unchanged: return " "
        case .removed: return "-"
        case .added: return "+"
        }
    }

    private var lineColor: Color {
        switch line.type {
        case .unchanged: return .primary
        case .removed: return .red
        case .added: return .green
        }
    }

    private var backgroundColor: Color {
        switch line.type {
        case .unchanged: return .clear
        case .removed: return Color.red.opacity(0.1)
        case .added: return Color.green.opacity(0.1)
        }
    }
}

// MARK: - Approval Sheet Presenter

extension View {
    /// Present file operation approval as a sheet.
    /// - Parameters:
    ///   - preview: Binding to the operation preview.
    ///   - onApprove: Action on approval.
    ///   - onReject: Action on rejection.
    /// - Returns: A view modified with the sheet.
    func fileOperationApproval(
        preview: Binding<FileOperationPreview?>,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) -> some View {
        self.sheet(
            isPresented: Binding(
                get: { preview.wrappedValue != nil },
                set: { if !$0 { preview.wrappedValue = nil } }
            )
        ) {
            if let currentPreview = preview.wrappedValue {
                FileOperationApprovalView(
                    preview: currentPreview,
                    onApprove: {
                        preview.wrappedValue = nil
                        onApprove()
                    },
                    onReject: {
                        preview.wrappedValue = nil
                        onReject()
                    }
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Create File") {
    FileOperationApprovalView(
        preview: FileOperationPreview(
            request: FileOperationRequest(
                operation: .create,
                path: "~/Documents/test.swift",
                content: "import Foundation\n\nprint(\"Hello, World!\")\n"
            ),
            originalContent: nil,
            proposedContent: "import Foundation\n\nprint(\"Hello, World!\")\n",
            diffLines: [
                DiffLine(type: .added, content: "import Foundation", lineNumber: 1),
                DiffLine(type: .added, content: "", lineNumber: 2),
                DiffLine(type: .added, content: "print(\"Hello, World!\")", lineNumber: 3),
            ]
        ),
        onApprove: {},
        onReject: {}
    )
    .previewEnvironment()
}

#Preview("Edit File") {
    FileOperationApprovalView(
        preview: FileOperationPreview(
            request: FileOperationRequest(
                operation: .edit,
                path: "~/Documents/test.swift",
                oldString: "Hello",
                newString: "Goodbye"
            ),
            originalContent: "print(\"Hello, World!\")",
            proposedContent: "print(\"Goodbye, World!\")",
            diffLines: [
                DiffLine(type: .removed, content: "print(\"Hello, World!\")", lineNumber: 1),
                DiffLine(type: .added, content: "print(\"Goodbye, World!\")", lineNumber: 1),
            ]
        ),
        onApprove: {},
        onReject: {}
    )
    .previewEnvironment()
}
