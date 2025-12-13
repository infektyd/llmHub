//
//  TerminalOutputView.swift
//  llmHub
//
//  Terminal-style output view with ANSI color support
//

import SwiftUI

// MARK: - ANSI Parser

/// Parses strings containing ANSI escape codes into `AttributedString`s.
struct ANSIParser {
    /// Parse ANSI escape sequences and return an AttributedString.
    /// - Parameter text: The text containing ANSI codes.
    /// - Returns: An `AttributedString` with styles applied.
    static func parse(_ text: String) -> AttributedString {
        var result = AttributedString()
        var currentAttributes = ANSIAttributes()
        
        // Regex to match ANSI escape sequences
        let pattern = "\u{001B}\\[([0-9;]*)m"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        var currentIndex = text.startIndex
        let nsText = text as NSString
        
        let matches = regex?.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []
        
        for match in matches {
            // Get text before this escape sequence
            if let range = Range(match.range, in: text), range.lowerBound > currentIndex {
                let plainText = String(text[currentIndex..<range.lowerBound])
                var attributed = AttributedString(plainText)
                currentAttributes.apply(to: &attributed)
                result.append(attributed)
            }
            
            // Parse the escape codes
            if let codeRange = Range(match.range(at: 1), in: text) {
                let codes = String(text[codeRange])
                currentAttributes.parse(codes: codes)
            }
            
            // Move past this escape sequence
            if let range = Range(match.range, in: text) {
                currentIndex = range.upperBound
            }
        }
        
        // Append remaining text
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex...])
            var attributed = AttributedString(remainingText)
            currentAttributes.apply(to: &attributed)
            result.append(attributed)
        }
        
        return result
    }
}

// MARK: - ANSI Attributes

/// Represents the current state of ANSI text attributes.
struct ANSIAttributes {
    var foregroundColor: Color = .primary
    var backgroundColor: Color = .clear
    var isBold = false
    var isItalic = false
    var isUnderline = false
    var isDim = false
    
    /// Updates attributes based on ANSI escape codes.
    /// - Parameter codes: The ANSI code string (e.g., "1;31").
    mutating func parse(codes: String) {
        let codeList = codes.split(separator: ";").compactMap { Int($0) }
        
        for code in codeList.isEmpty ? [0] : codeList {
            switch code {
            case 0:
                reset()
            case 1:
                isBold = true
            case 2:
                isDim = true
            case 3:
                isItalic = true
            case 4:
                isUnderline = true
            case 22:
                isBold = false
                isDim = false
            case 23:
                isItalic = false
            case 24:
                isUnderline = false
                
            // Standard foreground colors
            case 30: foregroundColor = .black
            case 31: foregroundColor = .red
            case 32: foregroundColor = .green
            case 33: foregroundColor = .yellow
            case 34: foregroundColor = .blue
            case 35: foregroundColor = .purple
            case 36: foregroundColor = .cyan
            case 37: foregroundColor = .white
            case 39: foregroundColor = .primary
                
            // Bright foreground colors
            case 90: foregroundColor = Color(white: 0.5)
            case 91: foregroundColor = Color.red.opacity(0.8)
            case 92: foregroundColor = Color.green.opacity(0.8)
            case 93: foregroundColor = Color.yellow.opacity(0.8)
            case 94: foregroundColor = Color.blue.opacity(0.8)
            case 95: foregroundColor = Color.purple.opacity(0.8)
            case 96: foregroundColor = Color.cyan.opacity(0.8)
            case 97: foregroundColor = .white
                
            // Standard background colors
            case 40: backgroundColor = .black
            case 41: backgroundColor = Color.red.opacity(0.3)
            case 42: backgroundColor = Color.green.opacity(0.3)
            case 43: backgroundColor = Color.yellow.opacity(0.3)
            case 44: backgroundColor = Color.blue.opacity(0.3)
            case 45: backgroundColor = Color.purple.opacity(0.3)
            case 46: backgroundColor = Color.cyan.opacity(0.3)
            case 47: backgroundColor = Color.white.opacity(0.3)
            case 49: backgroundColor = .clear
                
            default:
                break
            }
        }
    }
    
    /// Resets all attributes to default.
    mutating func reset() {
        foregroundColor = .primary
        backgroundColor = .clear
        isBold = false
        isItalic = false
        isUnderline = false
        isDim = false
    }
    
    /// Applies the current attributes to an AttributedString.
    /// - Parameter attributedString: The string to modify.
    func apply(to attributedString: inout AttributedString) {
        attributedString.foregroundColor = isDim ? foregroundColor.opacity(0.6) : foregroundColor
        
        if backgroundColor != .clear {
            attributedString.backgroundColor = backgroundColor
        }
        
        if isBold {
            attributedString.font = .system(.body, design: .monospaced).bold()
        } else if isItalic {
            attributedString.font = .system(.body, design: .monospaced).italic()
        } else {
            attributedString.font = .system(.body, design: .monospaced)
        }
        
        if isUnderline {
            attributedString.underlineStyle = .single
        }
    }
}

// MARK: - Terminal Output View

/// A view that displays code execution results with syntax highlighting and ANSI color support.
struct TerminalOutputView: View {
    /// The result of the code execution.
    let result: CodeExecutionResult
    @State private var showRawOutput = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "terminal")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("Execution Result")
                    .font(.headline)
                
                Spacer()
                
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(result.isSuccess ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    
                    Text(result.isSuccess ? "Success" : "Failed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Execution time
                Text("\(result.executionTimeMs)ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            
            // Language and exit code
            HStack(spacing: 16) {
                Label(result.language.displayName, systemImage: languageIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("Exit: \(result.exitCode)")
                    .font(.caption.monospaced())
                    .foregroundStyle(result.isSuccess ? Color.secondary : Color.red)
            }
            
            Divider()
            
            // Output content
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // STDOUT
                    if !result.stdout.isEmpty {
                        outputSection(title: "stdout", content: result.stdout, isError: false)
                    }
                    
                    // STDERR
                    if !result.stderr.isEmpty {
                        outputSection(title: "stderr", content: result.stderr, isError: true)
                    }
                    
                    // Empty output message
                    if result.stdout.isEmpty && result.stderr.isEmpty {
                        Text("(No output)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            
            // Toggle for raw view
            Toggle("Show raw output", isOn: $showRawOutput)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(macOS)
                .fill(Color(nsColor: .textBackgroundColor))
                #else
                .fill(Color(uiColor: .tertiarySystemBackground))
                #endif
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var languageIcon: String {
        switch result.language {
        case .swift: return "swift"
        case .python: return "ladybug"
        case .typescript, .javascript: return "curlybraces"
        case .dart: return "arrow.trianglehead.branch"
        }
    }
    
    @ViewBuilder
    private func outputSection(title: String, content: String, isError: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(isError ? .red : .green)
            
            if showRawOutput {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                Text(ANSIParser.parse(content))
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isError ? Color.red.opacity(0.1) : Color.green.opacity(0.1))
        )
    }
}

// MARK: - Compact Terminal View

/// A compact version of the terminal output view, expandable on click.
struct CompactTerminalView: View {
    /// The result of the code execution.
    let result: CodeExecutionResult
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "terminal.fill")
                        .foregroundStyle(result.isSuccess ? .green : .red)
                    
                    Text(result.language.displayName)
                        .font(.caption.bold())
                    
                    Spacer()
                    
                    if result.isSuccess {
                        Text("✓")
                            .foregroundStyle(.green)
                    } else {
                        Text("Exit \(result.exitCode)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                    
                    Text("\(result.executionTimeMs)ms")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            
            // Expanded content
            if isExpanded {
                Divider()
                
                ScrollView {
                    Text(ANSIParser.parse(result.combinedOutput))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                #if os(macOS)
                .fill(Color(nsColor: .controlBackgroundColor))
                #else
                .fill(Color(uiColor: .secondarySystemBackground))
                #endif
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    result.isSuccess ? Color.green.opacity(0.3) : Color.red.opacity(0.3),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Code Preview with Execution Button

/// A view showing code with an option to execute it.
struct CodeExecutionPreview: View {
    /// The code content.
    let code: String
    /// The programming language.
    let language: SupportedLanguage
    /// Action to trigger execution.
    let onExecute: () -> Void
    /// Action to cancel execution.
    let onCancel: () -> Void
    
    @State private var showFullCode = false
    
    private var previewLines: String {
        let lines = code.components(separatedBy: .newlines)
        if lines.count <= 10 {
            return code
        }
        return lines.prefix(10).joined(separator: "\n") + "\n... (\(lines.count - 10) more lines)"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                
                Text("Code Execution Request")
                    .font(.headline)
                
                Spacer()
                
                Text(language.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            
            // Code preview
            VStack(alignment: .leading, spacing: 4) {
                ScrollView {
                    Text(showFullCode ? code : previewLines)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        #if os(macOS)
                .fill(Color(nsColor: .textBackgroundColor))
                #else
                .fill(Color(uiColor: .tertiarySystemBackground))
                #endif
                )
                
                if code.components(separatedBy: .newlines).count > 10 {
                    Button(showFullCode ? "Show less" : "Show full code") {
                        withAnimation {
                            showFullCode.toggle()
                        }
                    }
                    .font(.caption)
                }
            }
            
            // Action buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button {
                    onExecute()
                } label: {
                    Label("Execute", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(macOS)
                .fill(Color(nsColor: .controlBackgroundColor))
                #else
                .fill(Color(uiColor: .secondarySystemBackground))
                #endif
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 2)
        )
    }
}

// MARK: - Interpreter Status View

/// A view showing the availability status of code interpreters.
struct InterpreterStatusView: View {
    /// List of interpreter information.
    let interpreters: [InterpreterInfo]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available Interpreters")
                .font(.headline)
            
            ForEach(SupportedLanguage.allCases, id: \.self) { language in
                let info = interpreters.first { $0.language == language }
                
                HStack {
                    Image(systemName: info?.isAvailable == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(info?.isAvailable == true ? .green : .red)
                    
                    Text(language.displayName)
                        .font(.body)
                    
                    Spacer()
                    
                    if let version = info?.version {
                        Text(version)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if info?.isAvailable == false {
                        Text("Not installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    VStack {
        TerminalOutputView(result: CodeExecutionResult(
            id: UUID(),
            language: .python,
            code: "print('Hello, World!')",
            stdout: "Hello, World!\n\u{001B}[32mGreen text\u{001B}[0m\n\u{001B}[1;31mBold red\u{001B}[0m",
            stderr: "",
            exitCode: 0,
            executionTimeMs: 42,
            timestamp: Date(),
            sandboxPath: nil
        ))
        
        CompactTerminalView(result: CodeExecutionResult(
            id: UUID(),
            language: .swift,
            code: "print(\"Test\")",
            stdout: "Test",
            stderr: "warning: something",
            exitCode: 0,
            executionTimeMs: 156,
            timestamp: Date(),
            sandboxPath: nil
        ))
    }
    .padding()
    .frame(width: 500)
}
