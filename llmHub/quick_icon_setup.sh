#!/bin/bash

# Quick Icon Setup Script
# This script automates the entire icon setup process

echo "🎨 llmHub App Icon Setup"
echo "========================"
echo ""

# Find icon files in the root directory
echo "Looking for icon files in the current directory..."
ICON_FILES=($(ls *.png *.jpg *.jpeg 2>/dev/null | head -5))

if [ ${#ICON_FILES[@]} -eq 0 ]; then
    echo "❌ No icon files found in the current directory."
    echo "Please place your source icon (1024x1024 PNG) in this directory."
    exit 1
fi

echo "Found the following image files:"
for i in "${!ICON_FILES[@]}"; do
    echo "  $((i+1)). ${ICON_FILES[$i]}"
done
echo ""

# If only one icon, use it automatically
if [ ${#ICON_FILES[@]} -eq 1 ]; then
    SELECTED_ICON="${ICON_FILES[0]}"
    echo "Using: $SELECTED_ICON"
else
    # Ask user to select
    echo -n "Select icon file (1-${#ICON_FILES[@]}): "
    read selection
    SELECTED_ICON="${ICON_FILES[$((selection-1))]}"
fi

echo ""
echo "📱 Select target platforms:"
echo "  1. Universal (macOS + iOS) - Recommended"
echo "  2. macOS only"
echo "  3. iOS only"
echo -n "Choice (1-3): "
read platform_choice

case $platform_choice in
    1)
        CONTENTS_FILE="AppIcon-Universal-Contents.json"
        echo "✅ Universal (macOS + iOS)"
        ;;
    2)
        CONTENTS_FILE="AppIcon-macOS-Contents.json"
        echo "✅ macOS only"
        ;;
    3)
        CONTENTS_FILE="AppIcon-iOS-Contents.json"
        echo "✅ iOS only"
        ;;
    *)
        echo "Invalid choice. Using Universal."
        CONTENTS_FILE="AppIcon-Universal-Contents.json"
        ;;
esac

echo ""

# Determine output directory
OUTPUT_DIR="./llmHub/Assets.xcassets/AppIcon.appiconset"

if [ ! -d "./llmHub/Assets.xcassets" ]; then
    echo "⚠️  Assets.xcassets not found in expected location."
    echo -n "Enter path to Assets.xcassets directory: "
    read assets_path
    OUTPUT_DIR="$assets_path/AppIcon.appiconset"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo "🔧 Generating icon sizes..."
echo ""

# Check if sips is available (macOS)
if command -v sips &> /dev/null; then
    ./generate_icons.sh "$SELECTED_ICON" "$OUTPUT_DIR"
elif command -v python3 &> /dev/null; then
    # Check if Pillow is installed
    if python3 -c "import PIL" 2>/dev/null; then
        python3 generate_icons.py "$SELECTED_ICON" "$OUTPUT_DIR"
    else
        echo "⚠️  Pillow not installed. Installing..."
        pip3 install Pillow
        python3 generate_icons.py "$SELECTED_ICON" "$OUTPUT_DIR"
    fi
else
    echo "❌ Neither sips nor Python 3 found. Cannot generate icons."
    exit 1
fi

# Copy Contents.json
echo ""
echo "📝 Setting up Contents.json..."
cp "$CONTENTS_FILE" "$OUTPUT_DIR/Contents.json"

echo ""
echo "✅ Setup complete!"
echo ""
echo "📋 Next steps:"
echo "  1. Open your project in Xcode"
echo "  2. Check Assets.xcassets → AppIcon"
echo "  3. Clean build folder (Cmd+Shift+K)"
echo "  4. Build and run!"
echo ""
echo "🎉 Your app icon warnings should now be resolved!"
