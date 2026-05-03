#!/bin/bash
# Build verification script for artifact attachment fix

set -e

echo "🔨 Building llmHub for macOS..."
xcodebuild -project llmHub.xcodeproj -scheme llmHub -destination 'platform=macOS' -quiet clean build
if [ $? -eq 0 ]; then
    echo "✅ macOS build SUCCEEDED"
else
    echo "❌ macOS build FAILED"
    exit 1
fi

echo ""
echo "🔨 Building llmHub for iOS Simulator..."
xcodebuild -project llmHub.xcodeproj -scheme llmHub -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -quiet clean build
if [ $? -eq 0 ]; then
    echo "✅ iOS build SUCCEEDED"
else
    echo "❌ iOS build FAILED"
    exit 1
fi

echo ""
echo "🎉 All builds SUCCEEDED!"
echo ""
echo "📋 Summary of Changes:"
echo "  • Added DEBUG-safe attachment metrics to LLMRequestTracer"
echo "  • Added auto-staging conversion in ChatViewModel"
echo "  • Artifacts now automatically convert to Attachments on import"
echo ""
echo "🧪 Manual Testing Checklist:"
echo "  1. Import a text file via artifact sandbox"
echo "  2. Send a message (any text)"
echo "  3. Check console for: ✅ Auto-staged artifact as attachment: <filename>"
echo "  4. Check console for: 📎 [provider] Attachments: 1 - <filename>(...)"
echo "  5. Verify provider request includes attachment content"
