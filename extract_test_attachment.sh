#!/bin/bash
#
# extract_test_attachment.sh
# Extracts the XCTAttachment text from the manual proof test result
#

set -euo pipefail

RESULT_BUNDLE="/tmp/llmhub-manual-proof.xcresult"

echo "Running manual proof test to generate fresh attachment..."
xcodebuild test \
    -scheme llmHub \
    -destination 'platform=macOS' \
    -only-testing:llmHubTests/HTTPRequestToolTests/testManualProof_ATSAndHTTPS_RealNetwork \
    -resultBundlePath "$RESULT_BUNDLE" \
    > /dev/null 2>&1

echo ""
echo "Test completed. Extracting attachment content..."
echo ""

# Find the test attachment reference in xcresult
# The attachment is stored in the xcresult bundle structure
# We need to find and extract the text attachment

# List all files in xcresult to find attachments
find "$RESULT_BUNDLE" -name "*.txt" -o -name "*Attachment*" 2>/dev/null | while read -r file; do
    if [ -f "$file" ]; then
        echo "=== Found potential attachment: $file ==="
        cat "$file"
        echo ""
    fi
done

echo ""
echo "Note: XCTAttachment content may require deeper xcresult parsing."
echo "The test itself PASSED, confirming both ATS block and HTTPS success."
