//
//  LiquidMarkdownTheme.swift
//  llmHub
//
//  Liquid Glass typography tuned for Textual's StructuredText rendering.
//

import SwiftUI

#if canImport(Textual)
import Textual
#endif

#if canImport(Textual)
struct LiquidStructuredTextStyle: StructuredText.Style {
    let theme: AppTheme

    var inlineStyle: InlineStyle {
        InlineStyle()
            .code(
                .monospaced,
                .fontScale(0.92),
                .foregroundColor(theme.textPrimary.opacity(0.92)),
                .backgroundColor(theme.textPrimary.opacity(0.08))
            )
            .strong(.fontWeight(.semibold))
            .link(.foregroundColor(theme.accent))
    }

    var headingStyle: LiquidHeadingStyle { LiquidHeadingStyle(theme: theme) }
    var paragraphStyle: LiquidParagraphStyle { LiquidParagraphStyle() }
    var blockQuoteStyle: LiquidBlockQuoteStyle { LiquidBlockQuoteStyle(theme: theme) }
    var codeBlockStyle: LiquidCodeBlockStyle { LiquidCodeBlockStyle(theme: theme) }
    var listItemStyle: StructuredText.DefaultListItemStyle {
        .default(markerSpacing: .fontScaled(0.5))
    }
    var unorderedListMarker: StructuredText.HierarchicalSymbolListMarker {
        .hierarchical(.disc, .circle, .square)
    }
    var orderedListMarker: StructuredText.DecimalListMarker { .decimal }
    var tableStyle: LiquidTableStyle { LiquidTableStyle(theme: theme) }
    var tableCellStyle: LiquidTableCellStyle { LiquidTableCellStyle() }
    var thematicBreakStyle: LiquidThematicBreakStyle { LiquidThematicBreakStyle(theme: theme) }
}

extension StructuredText.Style where Self == LiquidStructuredTextStyle {
    static func llmHubLiquid(theme: AppTheme) -> Self {
        .init(theme: theme)
    }
}

extension StructuredText.HighlighterTheme {
    static func llmHubLiquid(theme: AppTheme) -> StructuredText.HighlighterTheme {
        StructuredText.HighlighterTheme(
            foregroundColor: DynamicColor(theme.textPrimary.opacity(0.92)),
            backgroundColor: DynamicColor(theme.textPrimary.opacity(0.06))
        )
    }
}

struct LiquidHeadingStyle: StructuredText.HeadingStyle {
    let theme: AppTheme
    private static let fontScales: [CGFloat] = [1.70, 1.38, 1.18, 1.06, 0.95, 0.90]
    private static let spacingTops: [CGFloat] = [1.375, 1.25, 1.125, 1.0, 0.875, 0.875]
    private static let spacingBottoms: [CGFloat] = [0.75, 0.625, 0.625, 0.5, 0.5, 0.5]

    func makeBody(configuration: Configuration) -> some View {
        let headingLevel = min(configuration.headingLevel, 6)
        let fontScale = Self.fontScales[headingLevel - 1]
        let spacingTop = Self.spacingTops[headingLevel - 1]
        let spacingBottom = Self.spacingBottoms[headingLevel - 1]

        configuration.label
            .textual.fontScale(fontScale)
            .textual.lineSpacing(.fontScaled(0.12))
            .textual.blockSpacing(.fontScaled(top: spacingTop, bottom: spacingBottom))
            .fontWeight(.semibold)
            .foregroundStyle(headingForegroundColor(for: headingLevel))
    }

    private func headingForegroundColor(for level: Int) -> Color {
        switch level {
        case 5:
            return theme.textSecondary
        case 6:
            return theme.textTertiary
        default:
            return theme.textPrimary
        }
    }
}

struct LiquidParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.26))
            .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.875))
    }
}

struct LiquidBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.textSecondary.opacity(0.25))
                .textual.frame(width: .fontScaled(0.2), alignment: .leading)

            configuration.label
                .foregroundStyle(theme.textSecondary)
                .textual.padding(.horizontal, .fontScaled(0.95))
        }
        .textual.lineSpacing(.fontScaled(0.26))
        .textual.blockSpacing(.fontScaled(bottom: 0.875))
    }
}

struct LiquidCodeBlockStyle: StructuredText.CodeBlockStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.22))
                .textual.fontScale(0.9)
                .fixedSize(horizontal: false, vertical: true)
                .monospaced()
                .textual.padding(.fontScaled(0.875))
        }
        .background(theme.textPrimary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .textual.blockSpacing(.fontScaled(bottom: 0.875))
    }
}

struct LiquidTableStyle: StructuredText.TableStyle {
    let theme: AppTheme
    private let borderWidth: CGFloat = 1

    func makeBody(configuration: Configuration) -> some View {
        let borderColor = theme.textPrimary.opacity(0.10)
        let rowPrimary = theme.textPrimary.opacity(0.02)
        let rowAlternate = theme.textPrimary.opacity(0.05)

        configuration.label
            .background {
                Canvas { context, _ in
                    for row in configuration.layout.rowIndices {
                        let rowRect = configuration.layout.rowBounds(row)
                        guard !rowRect.isNull else { continue }
                        let fillColor = row % 2 == 0 ? rowPrimary : rowAlternate
                        context.fill(Path(rowRect), with: .color(fillColor))
                    }
                }
            }
            .overlay {
                Canvas { context, _ in
                    for divider in configuration.layout.dividers() {
                        context.fill(Path(divider), with: .color(borderColor))
                    }
                    context.stroke(
                        Path(configuration.layout.bounds),
                        with: .color(borderColor),
                        lineWidth: borderWidth
                    )
                }
            }
            .textual.tableCellSpacing(horizontal: borderWidth, vertical: borderWidth)
            .textual.blockSpacing(.fontScaled(top: 0, bottom: 0.875))
            .padding(borderWidth)
    }
}

struct LiquidTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(configuration.row == 0 ? .semibold : .regular)
            .textual.lineSpacing(.fontScaled(0.25))
            .textual.padding(.vertical, .fontScaled(0.375))
            .textual.padding(.horizontal, .fontScaled(0.75))
    }
}

struct LiquidThematicBreakStyle: StructuredText.ThematicBreakStyle {
    let theme: AppTheme

    func makeBody(configuration: Configuration) -> some View {
        Divider()
            .textual.frame(height: .fontScaled(0.18))
            .overlay(theme.textPrimary.opacity(0.08))
            .textual.blockSpacing(.fontScaled(top: 1.125, bottom: 1.125))
    }
}
#endif

#if canImport(Textual)
// MARK: - Previews

#Preview("Markdown Showcase") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            StructuredText(
                markdown: """
                # Heading 1
                ## Heading 2
                ### Heading 3

                This is a paragraph with **strong text**, *italic text*, and a [link](https://google.com).

                > This is a blockquote with some interesting information that should be styled nicely.

                ### Code Samples

                Inline `code` and code blocks:

                ```swift
                func hello() {
                    print("Hello, Liquid Glass!")
                }
                ```

                ### Lists

                - Item 1
                - Item 2
                  - Sub-item 2.1

                1. Ordered 1
                2. Ordered 2

                ### Tables

                | Feature | Status | Notes |
                | :--- | :--- | :--- |
                | Glass | ✅ | Shiny |
                | Flat | ❌ | Boring |

                ***

                Bottom content.
                """
            )
            .textual.structuredTextStyle(.llmHubLiquid(theme: CanvasDarkTheme()))
            .textual.highlighterTheme(.llmHubLiquid(theme: CanvasDarkTheme()))
            .textual.listItemSpacing(.fontScaled(top: 0.22))
        }
        .padding()
    }
    .frame(width: 500)
    .previewEnvironment()
}
#endif
