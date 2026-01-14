# Workspace Files Panel - Quick Start Guide

## What Was Added

A new **"Workspace"** section in the right sidebar that displays code execution outputs from the iCloud-synced workspace.

## Where to Find It

1. Open llmHub
2. Open right sidebar (Inspector)
3. Scroll to find the **"Workspace"** section (below "Files" section)

## What It Shows

The Workspace section displays files automatically saved during code execution:

- **output_*.txt** — stdout from code execution (green icon)
- **error_*.txt** — stderr from code execution (red icon)  
- **code_*.{ext}** — executed code files (accent blue icon)
- **Generated files** — charts, images, JSON outputs (purple/blue icons)

## How to Use

### 1. Run Code
```swift
// In chat, ask the AI to run code:
"Write and execute a Python script that prints hello world"
```

The AI will use the Code Interpreter tool, which saves outputs to the workspace.

### 2. View Outputs
Within ~1 second, files appear in the **Workspace** section:
- `output.txt` — "hello world"
- `code.py` — the executed Python script

### 3. Actions

**Hover over a file** to reveal:
- 📋 **Copy** — copies file contents to clipboard
- 🗑️ **Delete** — removes file from workspace

**Click the menu** (••• icon) for:
- 🔍 **Show in Finder** (macOS only) — opens workspace folder
- 🗑️ **Clear All Files** — removes all workspace files

**Click refresh** (↻ icon) to manually reload the file list.

### 4. iCloud Sync Status

Look for the cloud icon next to the refresh button:
- ☁️ **Green cloud** — syncing to iCloud, files available on all devices
- ☁️ **Slashed cloud** — using local storage (iCloud unavailable)

## File Types & Colors

| Icon | Type | Color | Examples |
|------|------|-------|----------|
| `</>` | Code | Blue (accent) | `.swift`, `.py`, `.js` |
| 📄 | Output | Green | `output_*.txt` |
| ⚠️ | Error | Red | `error_*.txt` |
| 🖼️ | Image | Purple | `.png`, `.jpg`, `.svg` |
| 📊 | Data | Blue | `.json`, `.csv` |
| 📄 | Other | Gray | Everything else |

## Example Workflow

1. **User:** "Generate a scatter plot of random data in Python"
2. **AI:** Executes Python code with matplotlib
3. **Workspace Files:**
   - `output.txt` — "Plot saved to scatter_plot.png"
   - `code.py` — Python script
   - `scatter_plot.png` — Generated chart image

All three files appear automatically in the Workspace section.

## Empty State

If no code has been executed yet, you'll see:

```
📄
No execution outputs
Run code to see outputs here
```

## Troubleshooting

### Files Not Appearing
- Wait 1-2 seconds for iCloud sync
- Click the refresh (↻) button
- Check that code execution succeeded (no errors in chat)

### iCloud Not Available
- Files are saved locally instead
- Look for slashed cloud icon
- Files won't sync across devices until iCloud is available

### Too Many Files
- Use "Clear All Files" to start fresh
- Individual delete for selective cleanup
- Workspace files don't affect artifact files (separate systems)

## Technical Details

- **Storage:** iCloud Drive → llmHub → Workspaces → `<workspace-id>`
- **Fallback:** `~/Documents/Workspaces` when iCloud unavailable
- **Updates:** Real-time via `NSMetadataQuery` (1-second throttle)
- **Persistence:** Section expand/collapse state saved in UserDefaults

## Related Features

- **Files Section** — User-imported files (drag-drop)
- **Tools Section** — Enable/disable tools (including Code Interpreter)
- **Code Interpreter Tool** — Executes code and saves outputs to workspace

---

**Implementation Status:** ✅ Complete  
**Build Status:** ✅ Verified  
**Ready to Test:** Yes
