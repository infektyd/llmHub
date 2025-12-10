# llmHub Scaffold Directory

**⚠️ FILES IN THIS DIRECTORY ARE NOT COMPILED**

This directory contains scaffolded features for future implementation.
Files are structured and documented but excluded from the Xcode build.

## Activation Instructions

To activate a feature:
1. In Xcode, select the `llmHub` target
2. Go to Build Phases → Compile Sources
3. Click + and add the relevant .swift files from `Scaffold/`
4. Remove any conflicting old implementations
5. Build and fix any integration issues

## Feature Status

| Feature | Target Date | Status | Activation Blocker |
|---------|-------------|--------|-------------------|
| models.dev API | Dec 22, 2024 | 🔴 Scaffold | Multi-select bug |
| Context Compaction | Jan 5, 2025 | 🔴 Scaffold | models.dev first |
| Tool Schema | Jan 12, 2025 | 🔴 Scaffold | Context compaction first |
| **Liquid Glass Design System** | **Jan 26, 2025** | **🔴 Scaffold** | **All bugs fixed** |

## Trajectory (Rigid)

```
Dec 8-15:  Fix current bugs (multi-select, Google duplicate)
Dec 15-22: Activate & implement models.dev
Dec 22-29: Integration testing, fallback logic
Dec 29-Jan 5: Activate & implement basic compaction
Jan 5-12:  Token estimation, UI integration
Jan 12-19: Activate tool schema types
Jan 19-26: Port existing tools
Jan 26-Feb 2: Full integration, remove scaffolds
```

## Rules

- No scaffold stays scaffolded > 4 weeks
- Each feature must have migration.md with concrete steps
- Activation requires all unit tests passing
- Old code removed within 1 week of activation
