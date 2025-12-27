#!/usr/bin/env python3
"""
Icon Generator Script for macOS and iOS
Generates all required icon sizes from a source icon file
Requires: Pillow (pip install Pillow)
Usage: python generate_icons.py <source_icon.png> <output_directory>
"""

import sys
import os
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Error: Pillow library not found.")
    print("Install it with: pip install Pillow")
    sys.exit(1)

def generate_icon(source_image, output_path, size, filename):
    """Generate a resized icon and save it."""
    print(f"  Creating {filename} ({size}x{size})")
    resized = source_image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(output_path / filename, "PNG")

def main():
    if len(sys.argv) != 3:
        print("Usage: python generate_icons.py <source_icon.png> <output_directory>")
        print("Example: python generate_icons.py icon.png ./llmHub/Assets.xcassets/AppIcon.appiconset")
        sys.exit(1)
    
    source_icon_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    
    if not source_icon_path.exists():
        print(f"Error: Source icon file not found: {source_icon_path}")
        sys.exit(1)
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Generating icon sizes from {source_icon_path}...")
    
    # Open source image
    try:
        source_image = Image.open(source_icon_path)
        # Convert to RGBA if needed
        if source_image.mode != 'RGBA':
            source_image = source_image.convert('RGBA')
    except Exception as e:
        print(f"Error opening source image: {e}")
        sys.exit(1)
    
    # macOS Icons
    print("Generating macOS icons...")
    macos_icons = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    for size, filename in macos_icons:
        generate_icon(source_image, output_dir, size, filename)
    
    # iOS Icons
    print("Generating iOS icons...")
    ios_icons = [
        # iPhone
        (40, "icon_20x20@2x-iphone.png"),
        (60, "icon_20x20@3x.png"),
        (58, "icon_29x29@2x-iphone.png"),
        (87, "icon_29x29@3x.png"),
        (80, "icon_40x40@2x-iphone.png"),
        (120, "icon_40x40@3x.png"),
        (120, "icon_60x60@2x.png"),
        (180, "icon_60x60@3x.png"),
        # iPad
        (20, "icon_20x20.png"),
        (40, "icon_20x20@2x-ipad.png"),
        (29, "icon_29x29.png"),
        (58, "icon_29x29@2x-ipad.png"),
        (40, "icon_40x40.png"),
        (80, "icon_40x40@2x-ipad.png"),
        (76, "icon_76x76.png"),
        (152, "icon_76x76@2x.png"),
        (167, "icon_83.5x83.5@2x.png"),
        # Marketing
        (1024, "icon_1024x1024.png"),
    ]
    
    for size, filename in ios_icons:
        generate_icon(source_image, output_dir, size, filename)
    
    print("\n✅ Icon generation complete!")
    print(f"Icons saved to: {output_dir}")
    print("\nNext steps:")
    print(f"1. Copy the appropriate Contents.json file to {output_dir}/")
    print("   - For universal (macOS + iOS): cp AppIcon-Universal-Contents.json {output_dir}/Contents.json")
    print("   - For macOS only: cp AppIcon-macOS-Contents.json {output_dir}/Contents.json")
    print("   - For iOS only: cp AppIcon-iOS-Contents.json {output_dir}/Contents.json")
    print("2. Open your project in Xcode")
    print("3. Build and run!")

if __name__ == "__main__":
    main()
