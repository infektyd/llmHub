# llmHub Documentation

> **Quick navigation for agents and developers working with llmHub.**  
> Last reorganized: January 11, 2026

---

## 📁 Directory Structure

```
Docs/
├── README.md                  ← You are here (navigation index)
├── REALITY_MAP.md             ← Current UI/tooling reality snapshot
├── AGENTS.md                  ← Agent tier guidelines (Haiku/Sonnet/Opus)
├── ONBOARDING_AGENTS.md       ← Critical context for AI assistants
├── CLAUDE.md                  ← Claude-specific guidelines
├── CONVENTIONS.md             ← Code style and conventions
│
├── Architecture/              ← System design & analysis
│   ├── CODEBASE_ANALYSIS.md
│   ├── COST_EFFICIENT_AI_DEV.md
│   ├── UNIFIED_TOOL_SYSTEM_IMPLEMENTATION.md
│   └── http_request_diagnostics_and_timeouts.md
│
├── Platform/                  ← Platform-specific documentation
│   ├── iOS/                   ← iOS implementation guides
│   │   ├── iOS_Quick_Reference.md
│   │   ├── iOS_Test_Plan.md
│   │   └── iOS_UI_Map.md
│   └── macOS/                 ← macOS-specific (XPC Helper service)
│       ├── llmHubHelper_README.md
│       ├── llmHubHelper_SUMMARY.md
│       ├── llmHubHelper_Security_Analysis.md
│       ├── llmHubHelper_Security_Examples.md
│       └── llmHubHelper_Quick_Reference.txt
│
├── Providers/                 ← LLM Provider integration guides
│   ├── openai_integration.md
│   ├── anthropic_integration.md
│   ├── gemini_integration.md
│   ├── Mistral_Integration.md
│   ├── xAiGrok_integration.md
│   ├── openrouter_integration.md
│   └── additional_mistral_information.md
│
├── Security/                  ← Security audits & implementation
│   ├── SECURITY_AUDIT_FILE_ACCESS_2026-01-08.md
│   ├── SECURITY_IMPLEMENTATION_SUMMARY.md
│   └── SECURITY_VERIFICATION_CHECKLIST_2026-01-08.md
│
├── Features/                  ← Feature-specific documentation
│   ├── SidebarModernization_Phase1_Migration.md
│   └── Sidecar_Memory_Isolation.md
│
├── UI/                        ← UI design & implementation
│   ├── LiquidGlass_Design_Spec.md  ← Legacy (archived spec)
│   ├── VIEW_FILE_MAP.md
│   ├── LLMHub_UI_ToolWiring_Map.md
│   ├── APP_ICON_SETUP_GUIDE.md
│   ├── ICON_SETUP_SUMMARY.md
│   ├── MANUAL_XCODE_ICON_SETUP.md
│   ├── NORDIC_UI_FIXES.md
│   └── VISUAL_GUIDE.md
│
├── Diagnostics/               ← Troubleshooting & diagnostics
│   ├── FoundationModels.md
│   └── Previews.md
│
├── Changelogs/                ← Monthly change logs
│   └── 2025-12.md
│
├── plans/                     ← Implementation plans & analysis
│   ├── plan-anthropicXaiDynamicModelLists.prompt.md
│   ├── plan-httpRequestToolTimeoutsTokenAudit.prompt.md
│   ├── TOOL_ROLE_FIX_SUMMARY.md
│   └── TOOLMETRICS_OBSERVABILITY_ANALYSIS.md
│
└── Archives/                  ← Historical/deprecated docs (gitignored)
    ├── 2026-01-Deprecated/    ← Recently archived implementation docs
    ├── Error_Reports/         ← Build error reports
    └── Legacy/                ← Old development logs
```

---

## 🎯 Quick Reference by Task

| I need to...                       | Go to                                          |
| ---------------------------------- | ---------------------------------------------- |
| **Understand the codebase**        | `Architecture/CODEBASE_ANALYSIS.md`            |
| **AI assistant guidelines**        | `ONBOARDING_AGENTS.md` → `AGENTS.md`           |
| **Add a new LLM provider**         | `Providers/<provider>_integration.md`          |
| **iOS development**                | `Platform/iOS/iOS_Quick_Reference.md`          |
| **macOS XPC Helper service**       | `Platform/macOS/llmHubHelper_README.md`        |
| **Security audit**                 | `Security/SECURITY_AUDIT_FILE_ACCESS_*.md`     |
| **Reality Map (current state)**   | `REALITY_MAP.md`                               |
| **UI design (legacy)**            | `UI/LiquidGlass_Design_Spec.md`                |
| **Tool system architecture**       | `Architecture/UNIFIED_TOOL_SYSTEM_*.md`        |
| **See recent changes**             | `Changelogs/2025-12.md`                        |
| **Troubleshoot issues**            | `Diagnostics/`                                 |

---

## 📚 Key Documents for AI Assistants

**Start here if you're an AI coding assistant:**

1. **`ONBOARDING_AGENTS.md`** - Critical context and operational parameters
2. **`AGENTS.md`** - Tier-based guidelines (which model for which task)
3. **`CLAUDE.md`** - Claude-specific best practices
4. **`CONVENTIONS.md`** - Code style and architectural patterns
5. **`REALITY_MAP.md`** - Current UI/tooling status

---

## 🔐 Security & Compliance

All security audits and implementation summaries are in `Security/`:
- File access security audit (Jan 2026)
- Security implementation summary
- Security verification checklist

**macOS XPC Helper sandboxing**: See `Platform/macOS/llmHubHelper_Security_*.md`

---

## 🗄️ Archives

The `Archives/` directory contains:
- **2026-01-Deprecated/** - Recently completed implementation docs (settings, verification)
- **Error_Reports/** - Historical build error reports
- **Legacy/** - Old development logs and build logs

**Note:** Archives are `.gitignore`d and won't be committed to the repository.

---

## 📝 Contributing to Documentation

When adding new documentation:
1. Place platform-specific docs in `Platform/iOS/` or `Platform/macOS/`
2. Place provider integration docs in `Providers/`
3. Place security audits in `Security/`
4. Place feature docs in `Features/`
5. Update this README with new entries

When deprecating documentation:
1. Archive to `Archives/YYYY-MM-Deprecated/`
2. Use `tar -czf` to compress related docs together
3. Remove originals after archiving
4. Document in the relevant changelog

---

*Last updated: January 11, 2026*
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
