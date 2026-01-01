#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./make_review_bundle.sh 7248b2ebe5f18553b156d2d0f547c64f510dc6c2
# If no arg provided, defaults to HEAD.

COMMIT="${1:-HEAD}"
OUTDIR="llmhub_review_bundle"
ZIPNAME="llmhub_review_bundle.zip"

# Key files we care about for review
KEY_FILES=(
  "llmHub/Models/Core/ContextConfig.swift"
  "llmHub/Services/ContextManagement/ContextManagementService.swift"
  "llmHub/Services/ContextManagement/ContextCompactor.swift"
  "llmHub/Services/Chat/ChatService.swift"
  "llmHub/ViewModels/ChatViewModel.swift"
  "llmHub/Providers/Anthropic/AnthropicProvider.swift"
  "llmHub/Providers/Anthropic/AnthropicManager.swift"
)

# Artifacts to exclude from diffs
EXCLUDES=(
  "Docs/Archives/**"
  "handoff_context_compaction_streaming.jsonl"
)

rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

echo "==> Writing metadata..."
{
  echo "Commit: $COMMIT"
  echo
  echo "## git rev-parse"
  git rev-parse HEAD
  echo
  echo "## branch"
  git branch --show-current || true
  echo
  echo "## remotes"
  git remote -v
  echo
  echo "## status"
  git status --porcelain=v1 || true
  echo
  echo "## show (header only)"
  git show --no-patch --pretty=fuller "$COMMIT"
} > "$OUTDIR/00_meta.txt"

echo "==> Writing recent commits..."
git log -20 --oneline > "$OUTDIR/01_commits.txt"

echo "==> Writing changed file list for commit..."
git show --name-status --oneline "$COMMIT" > "$OUTDIR/02_changed_files.txt"

echo "==> Writing code-only patch for commit (excluding large artifacts)..."
# Build pathspec excludes for git
# shellcheck disable=SC2086
git show --no-pager "$COMMIT" -- . \
  $(printf " ':(exclude)%s'" "${EXCLUDES[@]}") \
  > "$OUTDIR/03_diff_code_only.patch" || true

echo "==> Writing diff for key files only..."
# shellcheck disable=SC2086
git show --no-pager "$COMMIT" -- "${KEY_FILES[@]}" > "$OUTDIR/04_key_files_combined.diff" || true

echo "==> Writing full contents of key files at HEAD..."
{
  for f in "${KEY_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      echo "===== FILE: $f ====="
      sed -n '1,260p' "$f"
      echo
      echo "===== END FILE: $f ====="
      echo
    else
      echo "MISSING: $f"
      echo
    fi
  done
} > "$OUTDIR/05_key_files_full.txt"

echo "==> Writing focused searches (summary/cancel/system/tool manifest)..."
{
  echo "## rolling summary / summarize"
  rg -n "rolling_summary|summariz|summaryMaxTokens|summarizeAtTurnCount|preserveLastTurns|summarizationEnabled" llmHub || true
  echo
  echo "## cancellation / termination"
  rg -n "onTermination|CancellationError|Task\\.isCancelled|task\\.cancel\\(|cancel\\(" llmHub || true
  echo
  echo "## system messages / tool manifest"
  rg -n "ToolManifest|systemPrompt|\\.system\\b|system:" llmHub || true
} > "$OUTDIR/06_context_search.txt"

echo "==> Zipping bundle..."
rm -f "$ZIPNAME"
zip -r "$ZIPNAME" "$OUTDIR" >/dev/null

echo
echo "Done."
echo "Upload this file in chat:"
echo "  $ZIPNAME"
