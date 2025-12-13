# llmHub Documentation

> Quick navigation for agents and developers working with llmHub.

---

## 📁 Directory Structure

```
Docs/
├── README.md              ← You are here (navigation index)
├── Agents.md              ← Agent tier guidelines (Haiku/Sonnet/Opus)
│
├── Architecture/          ← System design & analysis
│   ├── CODEBASE_ANALYSIS.md
│   └── COST_EFFICIENT_AI_DEV.md
│
├── Providers/             ← LLM Provider integration guides
│   ├── openai_integration.md
│   ├── anthropic_integration.md
│   ├── gemini_integration.md
│   ├── Mistral_Integration.md
│   ├── xAiGrok_integration.md
│   ├── openrouter_integration.md
│   └── additional_mistral_information.md
│
├── Changelogs/            ← Monthly change logs
│   └── 2025-12.md
│
├── Legacy/                ← Historical docs (archived)
│   ├── DevLogs/           ← Past fix/migration logs
│   └── BuildLogs/         ← Old build error reports
│
└── (Root files)           ← iOS-specific docs
    ├── iOS_Quick_Reference.md
    ├── iOS_Test_Plan.md
    ├── iOS_UI_Map.md
    └── LLMHub_UI_ToolWiring_Map.md
```

---

## 🎯 Quick Reference by Task

| I need to...                 | Go to                                 |
| ---------------------------- | ------------------------------------- |
| Understand the codebase      | `Architecture/CODEBASE_ANALYSIS.md`   |
| Add a new LLM provider       | `Providers/<provider>_integration.md` |
| Know which agent tier to use | `Agents.md`                           |
| See recent changes           | `Changelogs/2025-12.md`               |
| Understand iOS specifics     | `iOS_Quick_Reference.md`              |
| Map UI → Tool wiring         | `LLMHub_UI_ToolWiring_Map.md`         |
| Review old fixes             | `Legacy/DevLogs/`                     |

---

## 🔧 Key Entry Points

| Area                  | Primary File                                 | Notes                        |
| --------------------- | -------------------------------------------- | ---------------------------- |
| **App Entry**         | `llmHub/App/llmHubApp.swift`                 | SwiftUI @main                |
| **Chat Loop**         | `llmHub/Services/ChatService.swift`          | Brain/Hand/Loop orchestrator |
| **Tool System**       | `llmHub/Services/ToolRegistry.swift`         | Actor-based tool management  |
| **Provider Protocol** | `llmHub/Providers/LLMProviderProtocol.swift` | `LLMProvider` protocol       |
| **Models**            | `llmHub/Models/ChatModels.swift`             | Domain models                |

---

## ⚠️ Legacy Documentation

Files in `Legacy/` are historical and may describe outdated patterns. They are kept for reference but should not be used for new development.

**Last reorganization:** 2025-12-13
