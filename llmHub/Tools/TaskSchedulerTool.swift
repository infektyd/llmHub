//
//  TaskSchedulerTool.swift
//  llmHub
//
//  Task scheduling and automation tool
//

import Foundation
import OSLog

/// Task Scheduler Tool conforming to the Tool protocol.
/// Schedules tasks and automated operations.
/// Task Scheduler Tool conforming to the Tool protocol.
/// Schedules tasks and automated operations.
struct TaskSchedulerTool: Tool {
    let name = "task_scheduler"
    let description = """
        Schedule tasks to run at specific times or intervals. \
        Create recurring jobs, reminders, and automated workflows. \
        Use this tool when you need to automate repetitive tasks or schedule future operations.
        """

    nonisolated var parameters: ToolParametersSchema {
        ToolParametersSchema(
            properties: [
                "action": ToolProperty(
                    type: .string,
                    description: "Scheduling action to perform",
                    enumValues: ["create", "list", "cancel", "status"]
                ),
                "task_id": ToolProperty(
                    type: .string,
                    description: "Task identifier (for list, cancel, status actions)"
                ),
                "command": ToolProperty(
                    type: .string,
                    description: "Command or operation to schedule (for create action)"
                ),
                "schedule": ToolProperty(
                    type: .string,
                    description: "Cron-style schedule or ISO 8601 datetime (for create action)"
                ),
                "repeat": ToolProperty(
                    type: .boolean,
                    description: "Whether task should repeat (default: false)"
                ),
            ],
            required: ["action"]
        )
    }

    nonisolated var permissionLevel: ToolPermissionLevel { .dangerous }
    nonisolated var requiredCapabilities: [ToolCapability] { [.scheduleTasks] }
    nonisolated var weight: ToolWeight { .standard }
    nonisolated var isCacheable: Bool { false }

    private let logger = Logger(subsystem: "com.llmhub", category: "TaskSchedulerTool")

    nonisolated func execute(arguments: ToolArguments, context: ToolContext) async throws -> ToolResult {
        throw ToolError.unavailable(
            reason:
                "Task scheduling not configured. Set up task scheduler backend in Settings > Tools > Scheduler."
        )
    }
}
