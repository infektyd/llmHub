#!/bin/bash

# Icon Generator Script for macOS and iOS
# This script generates all required icon sizes from a source icon file
# Usage: ./generate_icons.sh <source_icon.png> <output_directory>

SOURCE_ICON="$1"
OUTPUT_DIR="$2"

if [ -z "$SOURCE_ICON" ] || [ -z "$OUTPUT_DIR" ]; then
    echo "Usage: $0 <source_icon.png> <output_directory>"
    echo "Example: $0 icon.png ./llmHub/Assets.xcassets/AppIcon.appiconset"
    exit 1
fi

if [ ! -f "$SOURCE_ICON" ]; then
    echo "Error: Source icon file not found: $SOURCE_ICON"
    exit 1
fi

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "Generating icon sizes from $SOURCE_ICON..."

# Function to generate icon
generate_icon() {
    local size=$1
    local filename=$2
    echo "  Creating $filename (${size}x${size})"
    sips -z $size $size "$SOURCE_ICON" --out "$OUTPUT_DIR/$filename" > /dev/null 2>&1
}

# macOS Icons
echo "Generating macOS icons..."
generate_icon 16 "icon_16x16.png"
generate_icon 32 "icon_16x16@2x.png"
generate_icon 32 "icon_32x32.png"
generate_icon 64 "icon_32x32@2x.png"
generate_icon 128 "icon_128x128.png"
generate_icon 256 "icon_128x128@2x.png"
generate_icon 256 "icon_256x256.png"
generate_icon 512 "icon_256x256@2x.png"
generate_icon 512 "icon_512x512.png"
generate_icon 1024 "icon_512x512@2x.png"

# iOS Icons - iPhone
echo "Generating iOS icons..."
generate_icon 40 "icon_20x20@2x-iphone.png"
generate_icon 60 "icon_20x20@3x.png"
generate_icon 58 "icon_29x29@2x-iphone.png"
generate_icon 87 "icon_29x29@3x.png"
generate_icon 80 "icon_40x40@2x-iphone.png"
generate_icon 120 "icon_40x40@3x.png"
generate_icon 120 "icon_60x60@2x.png"
generate_icon 180 "icon_60x60@3x.png"

# iOS Icons - iPad
generate_icon 20 "icon_20x20.png"
generate_icon 40 "icon_20x20@2x-ipad.png"
generate_icon 29 "icon_29x29.png"
generate_icon 58 "icon_29x29@2x-ipad.png"
generate_icon 40 "icon_40x40.png"
generate_icon 80 "icon_40x40@2x-ipad.png"
generate_icon 76 "icon_76x76.png"
generate_icon 152 "icon_76x76@2x.png"
generate_icon 167 "icon_83.5x83.5@2x.png"

# iOS Marketing Icon
generate_icon 1024 "icon_1024x1024.png"

echo ""
echo "✅ Icon generation complete!"
echo "Icons saved to: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Copy the appropriate Contents.json file to $OUTPUT_DIR/"
echo "   - For universal (macOS + iOS): cp AppIcon-Universal-Contents.json $OUTPUT_DIR/Contents.json"
echo "   - For macOS only: cp AppIcon-macOS-Contents.json $OUTPUT_DIR/Contents.json"
echo "   - For iOS only: cp AppIcon-iOS-Contents.json $OUTPUT_DIR/Contents.json"
echo "2. Open your project in Xcode"
echo "3. Build and run!"
