# Cost-Efficient AI Development Guide

> **For Hans — Making Every Dollar Count**

---

## 💡 The Core Insight

You don't need Opus for 90% of coding work. You need Opus to **think once** so cheaper models can **execute many times**.

This document captures patterns to minimize costs while maintaining quality.

---

## 📊 Cost Reality Check (December 2025)

| Model | Input (per 1M tokens) | Output (per 1M tokens) | Best For |
|-------|----------------------|------------------------|----------|
| **Claude 3.5 Haiku** | ~$0.25 | ~$1.25 | Boilerplate, docs, simple fixes |
| **Claude 3.5/4 Sonnet** | ~$3 | ~$15 | Features, UI, most development |
| **Claude 4 Opus** | ~$15 | ~$75 | Architecture, complex debugging |

**Translation**: One Opus session ≈ 5 Sonnet sessions ≈ 25 Haiku sessions

---

## 🎯 The "Opus Investment" Pattern

### When to Use Opus (Sparingly)

1. **Project kickoff** — Set up AGENTS.md, establish patterns
2. **New subsystem design** — Create implementation docs like LIQUID_GLASS_MIGRATION.md
3. **When stuck** — Sonnet tried twice and failed
4. **Architecture reviews** — Once a month, audit the codebase
5. **Complex debugging** — Race conditions, memory issues, async bugs

### The ROI Formula

```
Good Opus Session = Implementation Doc + Code Examples + Clear Instructions
                  = 5-10 successful Sonnet sessions
                  = Weeks of productive development
```

---

## 📝 Template: Opus Handoff Document

When you use Opus, ask it to create a document like this:

```markdown
# [Feature/Migration] Implementation Guide

**FOR:** Sonnet/Haiku  
**FROM:** Opus  
**DATE:** [Date]  

## Goal
[One sentence: what are we building/fixing?]

## Files to Create
- `path/to/file.swift` — [purpose]

## Files to Modify  
- `existing/file.swift` — [what changes]

## Step-by-Step Instructions

### Step 1: [Action]
```swift
// FIND:
[exact code to find]

// REPLACE WITH:
[exact code to use]
```

### Step 2: [Action]
...

## Verification
- [ ] Check 1
- [ ] Check 2

## Do NOT Change
- file1.swift (reason)
- file2.swift (reason)
```

---

## 🔄 Daily Workflow

### Morning (Haiku - Cheap)
- "What files changed yesterday? Summarize."
- "Add documentation to this function"
- "What does this error mean?"
- Quick syntax questions

### Development (Sonnet - Balanced)
- "Implement Step 3 from LIQUID_GLASS_MIGRATION.md"
- "Add a new Tool following the pattern in CalculatorTool"
- "Write tests for ChatService"
- "Fix this bug: [paste error]"

### When Stuck (Opus - Investment)
- "Sonnet couldn't figure out why X. Here's what we tried..."
- "Design how we should implement [complex feature]"
- "Review this architecture and create implementation docs"

---

## 🚀 Maximizing Context Efficiency

### Do This ✅
```
"Look at AGENTS.md and implement the first migration in 
LIQUID_GLASS_MIGRATION.md. The file is NeonChatInput.swift."
```
- References existing docs (AI reads them, not you typing)
- Specific file target
- Clear scope

### Don't Do This ❌
```
"I have this app and it uses SwiftUI and I want to add 
Liquid Glass and here's what my files look like [pastes 
500 lines] and I want the buttons to be glass and..."
```
- Wastes tokens on context the AI already has
- Vague scope = multiple clarification rounds = more tokens

---

## 📁 Your Project's Cost-Saving Infrastructure

You now have:

| File | Purpose | Saves You |
|------|---------|-----------|
| `AGENTS.md` | Project context for any AI model | Re-explaining architecture every session |
| `LIQUID_GLASS_MIGRATION.md` | Step-by-step Liquid Glass work | Opus re-architecting each session |
| `UI_FIXES_SUMMARY.md` | Record of past decisions | Re-solving solved problems |

### Keep Adding:
- `PROVIDER_INTEGRATION.md` — When you add a new LLM provider
- `TOOL_IMPLEMENTATION.md` — Patterns for new tools
- `DEBUGGING_LOG.md` — Complex bugs and solutions (so you never pay to solve twice)

---

## 💬 Prompt Templates for Each Tier

### Haiku Prompts
```
"Add Swift documentation comments to all public methods in [file]"

"What does this error mean: [error]"

"Rename [oldName] to [newName] in [file]"

"Format this code to match the project style"
```

### Sonnet Prompts
```
"Following AGENTS.md conventions, implement [feature] in [file]"

"Look at LIQUID_GLASS_MIGRATION.md and complete Migration [N]"

"Add a new tool called [Name]Tool following the Tool protocol in ToolRegistry.swift"

"Write tests for [Component] using Swift Testing framework"

"Fix: [paste error and file context]"
```

### Opus Prompts (Investment Sessions)
```
"Review my project architecture in AGENTS.md. I want to add [major feature]. 
Create an implementation document that Sonnet can follow, similar to 
LIQUID_GLASS_MIGRATION.md. Include exact code snippets and file locations."

"Sonnet has failed twice to fix [issue]. Here's what we tried: [context]. 
Debug this and explain what's actually happening."

"Audit AGENTS.md — is it still accurate? What should be updated? 
What new patterns have emerged that should be documented?"
```

---

## 🎮 The Game: Minimize Round Trips

Every message costs money. Reduce them:

1. **Be specific first message** — Don't say "help me with X", say "do X in file Y"
2. **Include relevant context** — But reference docs, don't paste everything
3. **Batch related changes** — "Do steps 1-3" not "Do step 1" then "Do step 2"
4. **Verify locally before asking** — Don't use AI to check if code compiles

---

## 📈 Tracking Your Investment

Keep a simple log:

```
Date       | Model  | Task                           | Result
-----------|--------|--------------------------------|--------
2025-12-04 | Opus   | Create LIQUID_GLASS_MIGRATION  | ✅ Doc created
2025-12-04 | Sonnet | Implement Phase 1              | ✅ 3 files
2025-12-05 | Sonnet | Migration 1: NeonChatInput     | ✅ 
2025-12-05 | Haiku  | Add docs to GlassCard          | ✅
2025-12-05 | Sonnet | Migration 2: NeonToolbar       | ❌ Needs Opus
2025-12-06 | Opus   | Debug toolbar issue            | ✅ Fixed + updated doc
```

This helps you see patterns — what needs Opus, what doesn't.

---

## 🙏 Final Thought

The fact that you keep coming back to Claude despite budget constraints tells me you value quality. This system lets you get Opus-quality architecture with Sonnet-level costs.

**Your investment today:**
- ~$2-3 for this Opus session
- Created infrastructure worth 10-20 future sessions

**Your ongoing cost:**
- Mostly Sonnet ($0.50-1 per session)
- Occasional Haiku ($0.05-0.10 per session)
- Rare Opus (when truly needed)

You've got this. Build something amazing. 🚀

---

*Document created with appreciation for developers who code on a budget.*
