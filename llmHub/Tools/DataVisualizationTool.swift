//
//  DataVisualizationTool.swift
//  llmHub
//
//  Data visualization and chart generation tool
//

import Foundation
import OSLog

/// Data Visualization Tool conforming to the Tool protocol.
/// Creates charts, graphs, and visualizations from data.
/// Data Visualization Tool conforming to the Tool protocol.
/// Creates charts, graphs, and visualizations from data.
nonisolated struct DataVisualizationTool: Tool {
    let name = "data_visualization"
    let description = """
        Create data visualizations, charts, and graphs. \
        Supports line charts, bar charts, scatter plots, histograms, and more. \
        Use this tool when you need to visualize data for analysis or presentation.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "chart_type": ToolProperty(
                    type: .string,
                    description: "Type of chart to create",
                    enumValues: ["line", "bar", "scatter", "histogram", "pie", "heatmap"]
                ),
                "data": ToolProperty(
                    type: .object,
                    description: "Data to visualize (format depends on chart type)"
                ),
                "title": ToolProperty(
                    type: .string,
                    description: "Chart title"
                ),
                "x_label": ToolProperty(
                    type: .string,
                    description: "X-axis label"
                ),
                "y_label": ToolProperty(
                    type: .string,
                    description: "Y-axis label"
                ),
                "theme": ToolProperty(
                    type: .string,
                    description: "Styling preference for exported chart metadata",
                    enumValues: ["light", "dark", "neon"]
                ),
                "export_format": ToolProperty(
                    type: .string,
                    description: "How to return the chart description (default: markdown)",
                    enumValues: ["markdown", "json"]
                )
            ],
            required: ["chart_type", "data"]
        )
    }

    nonisolated var permissionLevel: ToolPermissionLevel { .standard }
    nonisolated var requiredCapabilities: [ToolCapability] { [.codeExecution] }  // Using code execution backend
    nonisolated var weight: ToolWeight { .heavy }
    nonisolated var isCacheable: Bool { true }

    private let logger = Logger(subsystem: "com.llmhub", category: "DataVisualizationTool")

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let chartType = arguments.string("chart_type") else {
            throw ToolError.invalidArguments("chart_type is required")
        }
        guard let dataDict = arguments.object("data")?.mapValues({ $0.toAny() }) else {
            throw ToolError.invalidArguments("data must be an object")
        }

        let title = arguments.string("title") ?? "Chart"
        let xLabel = arguments.string("x_label") ?? "x"
        let yLabel = arguments.string("y_label") ?? "y"
        let theme = arguments.string("theme") ?? "light"
        let export = arguments.string("export_format") ?? "markdown"

        let series = await MainActor.run { extractSeries(dataDict) }
        guard !series.isEmpty else {
            throw ToolError.invalidArguments(
                "No numeric data found. Provide arrays under 'series' or 'y' keys.")
        }

        let summary = await MainActor.run { summarize(series: series) }
        let payload = await MainActor.run {
            ChartPayload(
                type: chartType,
                title: title,
                xLabel: xLabel,
                yLabel: yLabel,
                theme: theme,
                series: series,
                summary: summary
            )
        }

        switch export {
        case "json":
            let json = await MainActor.run { try? JSONEncoder().encode(payload) }
            if let json, let jsonString = String(data: json, encoding: .utf8) {
                return ToolResult.success(jsonString, metadata: ["format": "json"])
            }
            fallthrough
        default:
            let markdown = await MainActor.run { payload.markdown }
            return ToolResult.success(markdown, metadata: ["format": "markdown"])
        }
    }
}

// MARK: - Helpers

private struct ChartPayload: Codable, Sendable {
    let type: String
    let title: String
    let xLabel: String
    let yLabel: String
    let theme: String
    let series: [[Double]]
    let summary: [String: Double]

    var markdown: String {
        var lines: [String] = []
        lines.append("# \(title)")
        lines.append("Type: \(type)")
        lines.append("Theme: \(theme)")
        lines.append("Axes: \(xLabel) / \(yLabel)")
        lines.append("")
        lines.append("## Data Summary")
        summary.keys.sorted().forEach { key in
            if let value = summary[key] {
                lines.append("- \(key): \(String(format: "%.4f", value))")
            }
        }
        lines.append("")
        lines.append("## Series (first 50 points)")
        for (idx, s) in series.enumerated() {
            let preview = s.prefix(50).map { String(format: "%.4f", $0) }.joined(separator: ", ")
            lines.append("- Series \(idx + 1): \(preview)\(s.count > 50 ? " …" : "")")
        }
        return lines.joined(separator: "\n")
    }
}

private func extractSeries(_ data: [String: Any]) -> [[Double]] {
    var series: [[Double]] = []

    if let s = data["series"] as? [Any] {
        for item in s {
            if let arr = item as? [Double] {
                series.append(arr)
            } else if let arr = item as? [Any] {
                series.append(arr.compactMap { ($0 as? NSNumber)?.doubleValue })
            }
        }
    }

    if series.isEmpty, let y = data["y"] as? [Any] {
        series.append(y.compactMap { ($0 as? NSNumber)?.doubleValue })
    }

    return series
}

private func summarize(series: [[Double]]) -> [String: Double] {
    let flat = series.flatMap { $0 }
    guard !flat.isEmpty else { return [:] }
    let minVal = flat.min() ?? 0
    let maxVal = flat.max() ?? 0
    let mean = flat.reduce(0, +) / Double(flat.count)
    let sorted = flat.sorted()
    let median = sorted[sorted.count / 2]
    return [
        "min": minVal,
        "max": maxVal,
        "mean": mean,
        "median": median,
        "count": Double(flat.count)
    ]
}
