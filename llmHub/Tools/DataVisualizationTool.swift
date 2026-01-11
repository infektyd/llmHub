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
    nonisolated var requiredCapabilities: [ToolCapability] { [] }
    nonisolated var weight: ToolWeight { .heavy }
    nonisolated var isCacheable: Bool { true }

    private let logger = Logger(subsystem: "com.llmhub", category: "DataVisualizationTool")

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        guard let chartType = arguments.string("chart_type") else {
            throw ToolError.invalidArguments("chart_type is required")
        }

        let title = arguments.string("title") ?? "Chart"
        let xLabel = arguments.string("x_label") ?? "x"
        let yLabel = arguments.string("y_label") ?? "y"
        let theme = arguments.string("theme") ?? "light"
        let export = arguments.string("export_format") ?? "markdown"

        let series = await MainActor.run { extractNumericSeries(from: arguments) }
        guard !series.isEmpty else {
            throw ToolError.invalidArguments(
                "No numeric data found. Provide data using any of these keys: " +
                "'data', 'y', 'values', 'series', or 'dataset'.")
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

private func extractNumericSeries(from arguments: ToolArguments) -> [[Double]] {
    if let dataValue = arguments["data"] {
        let series = extractSeries(from: dataValue)
        if !series.isEmpty {
            return series
        }
    }

    return extractSeries(from: .object(arguments.jsonValuesByKey))
}

private func extractSeries(from value: JSONValue) -> [[Double]] {
    switch value {
    case .array(let array):
        if let numbers = extractNumberArray(from: array), !numbers.isEmpty {
            return [numbers]
        }
        var series: [[Double]] = []
        for element in array {
            if case .array(let nested) = element,
               let numbers = extractNumberArray(from: nested),
               !numbers.isEmpty {
                series.append(numbers)
            }
        }
        return series
    case .object(let dictionary):
        if let seriesValue = dictionary["series"] {
            let series = extractSeries(from: seriesValue)
            if !series.isEmpty {
                return series
            }
        }

        for key in ["y", "values", "data"] {
            if let value = dictionary[key] {
                let series = extractSeries(from: value)
                if !series.isEmpty {
                    return series
                }
            }
        }

        if let dataset = dictionary["dataset"] {
            let series = extractSeries(from: dataset)
            if !series.isEmpty {
                return series
            }
        }

        var series: [[Double]] = []
        for value in dictionary.values {
            if case .array(let array) = value,
               let numbers = extractNumberArray(from: array),
               !numbers.isEmpty {
                series.append(numbers)
            }
        }
        return series
    default:
        return []
    }
}

private func extractNumberArray(from values: [JSONValue]) -> [Double]? {
    let numbers = values.compactMap { extractNumber(from: $0) }
    return numbers.isEmpty ? nil : numbers
}

private func extractNumber(from value: JSONValue) -> Double? {
    switch value {
    case .number(let number):
        return number
    case .string(let string):
        return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
    default:
        return nil
    }
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
