//
//  LiquidMarkdownTheme.swift
//  llmHub
//
//  Claude-level Markdown typography tuned for the unified Liquid Glass transcript.
//

import SwiftUI

#if canImport(MarkdownUI)
    import MarkdownUI
#endif

#if canImport(MarkdownUI)
    extension MarkdownUI.Theme {
        static func llmHubLiquid(theme appTheme: AppTheme) -> MarkdownUI.Theme {
            MarkdownUI.Theme()
                .text {
                    ForegroundColor(appTheme.textPrimary)
                    BackgroundColor(nil)
                    FontSize(16)
                }
                .code {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.92))
                    ForegroundColor(appTheme.textPrimary.opacity(0.92))
                    BackgroundColor(appTheme.textPrimary.opacity(0.08))
                }
                .strong {
                    FontWeight(.semibold)
                }
                .link {
                    ForegroundColor(appTheme.accent)
                }
                .heading1 { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.12))
                        .markdownMargin(top: 22, bottom: 12)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(1.70))
                        }
                }
                .heading2 { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.12))
                        .markdownMargin(top: 20, bottom: 10)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(1.38))
                        }
                }
                .heading3 { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.12))
                        .markdownMargin(top: 18, bottom: 10)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(1.18))
                        }
                }
                .heading4 { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.12))
                        .markdownMargin(top: 16, bottom: 8)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(1.06))
                        }
                }
                .heading5 { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.12))
                        .markdownMargin(top: 14, bottom: 8)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(0.95))
                            ForegroundColor(appTheme.textSecondary)
                        }
                }
                .heading6 { configuration in
                    configuration.label
                        .relativeLineSpacing(.em(0.12))
                        .markdownMargin(top: 14, bottom: 8)
                        .markdownTextStyle {
                            FontWeight(.semibold)
                            FontSize(.em(0.90))
                            ForegroundColor(appTheme.textTertiary)
                        }
                }
                .paragraph { configuration in
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.26))
                        .markdownMargin(top: 0, bottom: 14)
                }
                .blockquote { configuration in
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appTheme.textSecondary.opacity(0.25))
                            .relativeFrame(width: .em(0.20))
                        configuration.label
                            .markdownTextStyle {
                                ForegroundColor(appTheme.textSecondary)
                                BackgroundColor(nil)
                            }
                            .relativePadding(.horizontal, length: .em(0.95))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownMargin(top: 0, bottom: 14)
                }
                .codeBlock { configuration in
                    ScrollView(.horizontal, showsIndicators: false) {
                        configuration.label
                            .fixedSize(horizontal: false, vertical: true)
                            .relativeLineSpacing(.em(0.22))
                            .markdownTextStyle {
                                FontFamilyVariant(.monospaced)
                                FontSize(.em(0.90))
                                ForegroundColor(appTheme.textPrimary.opacity(0.92))
                            }
                            .padding(14)
                    }
                    .background(appTheme.textPrimary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .markdownMargin(top: 0, bottom: 14)
                }
                .listItem { configuration in
                    configuration.label
                        .markdownMargin(top: .em(0.22))
                }
                .table { configuration in
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .markdownTableBorderStyle(.init(color: appTheme.textPrimary.opacity(0.10)))
                        .markdownTableBackgroundStyle(
                            .alternatingRows(
                                appTheme.textPrimary.opacity(0.02),
                                appTheme.textPrimary.opacity(0.05)
                            )
                        )
                        .markdownMargin(top: 0, bottom: 14)
                }
                .tableCell { configuration in
                    configuration.label
                        .markdownTextStyle {
                            if configuration.row == 0 { FontWeight(.semibold) }
                            BackgroundColor(nil)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .relativeLineSpacing(.em(0.25))
                }
                .thematicBreak {
                    Divider()
                        .relativeFrame(height: .em(0.18))
                        .overlay(appTheme.textPrimary.opacity(0.08))
                        .markdownMargin(top: 18, bottom: 18)
                }
        }
    }
#endif
#if canImport(MarkdownUI)
    // MARK: - Previews

    #Preview("Markdown Showcase") {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Markdown {
                    """
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
                }
                .markdownTheme(.llmHubLiquid(theme: ThemeManager.shared.current))
            }
            .padding()
        }
        .frame(width: 500)
        .previewEnvironment()
    }
#endif
