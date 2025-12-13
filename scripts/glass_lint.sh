#!/bin/bash
# Glass UI Lint - Prevents deprecated glass patterns from reappearing
# Add to CI or as a pre-commit hook:
#   cp scripts/glass_lint.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit

set -e

SEARCH_DIR="${1:-llmHub}"
ERRORS=0

# Deprecated patterns that should NEVER reappear
DEPRECATED_PATTERNS=(
    "GlassEffectContainer"
    "glassEffectID"
    "GlassEffectIntensity.native"
    "GlassEffectIntensity\.native"
)

echo "🔍 Glass UI Lint: Checking for deprecated patterns..."

for pattern in "${DEPRECATED_PATTERNS[@]}"; do
    # Skip definition files (LiquidGlassAPI.swift may still have the deprecated definition)
    matches=$(grep -r --include="*.swift" "$pattern" "$SEARCH_DIR" 2>/dev/null | grep -v "LiquidGlassAPI.swift" | grep -v "@available.*deprecated" || true)
    
    if [ -n "$matches" ]; then
        echo "❌ Found deprecated pattern '$pattern':"
        echo "$matches"
        ERRORS=$((ERRORS + 1))
    fi
done

if [ $ERRORS -eq 0 ]; then
    echo "✅ No deprecated glass patterns found."
    exit 0
else
    echo ""
    echo "❌ $ERRORS deprecated pattern(s) found. Please use:"
    echo "   • .glassEffect(GlassEffect.regular.tint(...)) instead of GlassEffectIntensity"
    echo "   • Remove GlassEffectContainer wrappers (they were no-ops)"
    echo "   • Remove glassEffectID calls (they were no-ops)"
    exit 1
fi
