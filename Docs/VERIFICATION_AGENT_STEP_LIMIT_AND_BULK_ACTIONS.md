# Manual Verification: Agent Step Limit + Sidebar Bulk Actions

Date: 2026-01-08

## 1) Agent step-limit popup

### Goal (Agent popup)

Verify that hitting the tool-step cap does **not** silently end as "complete", and instead shows a user-facing prompt with Continue / Change default / Stop.

### Setup (Agent popup)

- In Settings (or via the popup), set **Agent Max Iterations** to a small value (e.g. `1` or `2`) to reproduce quickly.
- Use a prompt that reliably triggers repeated tool calls (e.g. a request that causes read/write/search loops).

### Steps (Agent popup)

1. Start a run that triggers tool use.
1. Wait until the agent hits the cap.

### Expected (Agent popup)

- A modal prompt appears:
  - Title: "Agent reached its step limit"
  - Body: "This run hit the limit of X tool steps. What would you like to do?"
  - Actions:
    - Continue… (lets you pick additional steps; default +10)
    - Change default… (lets you set a persisted default; applies immediately)
    - Stop
- Logs include:
  - cap hit with `limit` and `used`
  - the last tool attempted
  - the user’s choice

### Continue Semantics (Agent popup)

1. Click **Continue…**
1. Choose `+10` additional steps
1. Click **Apply**

Expected:

- The run resumes from current persisted state (no new user message inserted).
- Previously completed tool results are not duplicated.

### Change-Default Semantics (Agent popup)

1. Hit the step limit again.
1. Click **Change default…**
1. Set default to a larger value (e.g. 20)
1. Click **Apply**

Expected:

- Default is persisted and used for subsequent runs.
- The currently stopped run resumes immediately with extra budget.

### Stop Semantics (Agent popup)

1. Hit the step limit.
1. Click **Stop**

Expected:

- The run ends and the partial transcript remains as-is.
- No additional tool calls are executed.

## 2) Sidebar multi-select bulk Archive/Delete

### Goal (Sidebar)

Verify Finder-style selection and context menu targeting.

### Steps (Sidebar)

1. In the left sidebar, select a conversation.
1. Hold **Shift** and click another conversation.

Expected:

- The entire contiguous range between the two rows becomes selected.

1. **Right-click** on a row **inside** the current selection.
1. Choose **Archive**.

Expected:

- All selected conversations are archived.

1. Undo/restore as needed, then multi-select again.
1. **Right-click** on a row **outside** the selection.
1. Choose **Delete**.

Expected:

- Only the clicked conversation is deleted (selection does not cause bulk delete).

## 3) Tool/file access transparency

### Goal (Tool/file transparency)

Verify that users can see the workspace root and file paths touched by tools.

### Steps (Tool/file transparency)

1. Open the Tools panel.
1. Verify that it shows the current workspace root path.
1. Run an action that calls a file tool (read/write/patch).
1. Check logs.

Expected:

- Tool logs include file path metadata (e.g. `resolvedPath=...`) for file tools.
- Users can infer whether Swift source files were read/written by inspecting the logged paths.
