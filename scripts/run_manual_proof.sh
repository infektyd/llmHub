#!/bin/bash
#
# run_manual_proof.sh
# Runs manual proof test with xcresult bundle and extracts logs for evidence.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
RESULT_BUNDLE="/tmp/llmhub-manual-proof.xcresult"
DIAGNOSTICS_DIR="/tmp/llmhub-diagnostics"
EVIDENCE_FILE="/tmp/llmhub-manual-proof-evidence.txt"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔬 llmHub Manual Proof Runner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Clean up previous results
echo "🧹 Cleaning up previous results..."
rm -rf "$RESULT_BUNDLE" "$DIAGNOSTICS_DIR" "$EVIDENCE_FILE"

# Run the manual proof test
echo "🧪 Running manual proof test..."
echo "   Test: HTTPRequestToolTests/testManualProof_ATSAndHTTPS_RealNetwork"
echo "   Result bundle: $RESULT_BUNDLE"
echo ""

xcodebuild test \
    -scheme llmHub \
    -destination 'platform=macOS' \
    -only-testing:llmHubTests/HTTPRequestToolTests/testManualProof_ATSAndHTTPS_RealNetwork \
    -resultBundlePath "$RESULT_BUNDLE" \
    2>&1 | tee /tmp/llmhub-test-output.log

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Extracting diagnostics from xcresult bundle..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

mkdir -p "$DIAGNOSTICS_DIR"

xcrun xcresulttool export diagnostics \
    --path "$RESULT_BUNDLE" \
    --output-path "$DIAGNOSTICS_DIR"

echo ""
echo "✅ Diagnostics exported to: $DIAGNOSTICS_DIR"
echo ""

# Extract relevant log lines
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Extracting manual proof evidence..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Search for log files containing our evidence
cat > "$EVIDENCE_FILE" << 'EOF'
# llmHub Manual Proof Evidence Report

## Git Information
EOF

echo "" >> "$EVIDENCE_FILE"
echo "**Commit:** $(git rev-parse HEAD)" >> "$EVIDENCE_FILE"
echo "**Date:** $(date)" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

echo "## Test Execution" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo "**Command:**" >> "$EVIDENCE_FILE"
echo '```bash' >> "$EVIDENCE_FILE"
echo "xcodebuild test -scheme llmHub -destination 'platform=macOS' \\" >> "$EVIDENCE_FILE"
echo "  -only-testing:llmHubTests/HTTPRequestToolTests/testManualProof_ATSAndHTTPS_RealNetwork \\" >> "$EVIDENCE_FILE"
echo "  -resultBundlePath $RESULT_BUNDLE" >> "$EVIDENCE_FILE"
echo '```' >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

echo "## Extracted Logs" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo "Searching diagnostics directory for manual proof logs..." >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo '```' >> "$EVIDENCE_FILE"

# Find and display log files
if [ -d "$DIAGNOSTICS_DIR" ]; then
    find "$DIAGNOSTICS_DIR" -type f \( -name "*.log" -o -name "*.txt" \) -exec sh -c '
        echo "=== File: $1 ==="
        grep -i "MANUAL PROOF\|TEST 1\|TEST 2\|ATS\|HTTPS" "$1" 2>/dev/null || echo "(no matching lines)"
        echo ""
    ' _ {} \; >> "$EVIDENCE_FILE"
else
    echo "No diagnostics directory found" >> "$EVIDENCE_FILE"
fi

echo '```' >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

echo "## Raw Test Output (excerpt)" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo '```' >> "$EVIDENCE_FILE"
grep -i "manual proof\|test 1\|test 2\|ats\|https" /tmp/llmhub-test-output.log | tail -50 >> "$EVIDENCE_FILE" || echo "(no matching lines in test output)" >> "$EVIDENCE_FILE"
echo '```' >> "$EVIDENCE_FILE"

echo ""
echo "✅ Evidence report written to: $EVIDENCE_FILE"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏁 Manual Proof Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📁 Files created:"
echo "   - xcresult bundle: $RESULT_BUNDLE"
echo "   - Diagnostics:     $DIAGNOSTICS_DIR"
echo "   - Evidence report: $EVIDENCE_FILE"
echo ""
echo "📖 View evidence report:"
echo "   cat $EVIDENCE_FILE"
echo ""
