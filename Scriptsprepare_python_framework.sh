#!/bin/bash

# prepare_python_framework.sh
# Prepares Python.xcframework for embedding in iOS app
# Fixes sandbox permission issues during build

set -e

FRAMEWORK_PATH="${SRCROOT}/Frameworks/Python.xcframework"

if [ ! -d "$FRAMEWORK_PATH" ]; then
    echo "Error: Python.xcframework not found at $FRAMEWORK_PATH"
    exit 1
fi

echo "Preparing Python.xcframework for embedding..."

# Function to process a single framework slice
process_framework_slice() {
    local SLICE_PATH="$1"
    echo "Processing slice: $(basename "$SLICE_PATH")"
    
    if [ ! -d "$SLICE_PATH" ]; then
        return
    fi
    
    # Find the actual framework directory
    local FRAMEWORK_DIR=$(find "$SLICE_PATH" -name "Python.framework" -type d -maxdepth 2 | head -n 1)
    
    if [ -z "$FRAMEWORK_DIR" ]; then
        echo "Warning: No Python.framework found in $SLICE_PATH"
        return
    fi
    
    echo "Found framework at: $FRAMEWORK_DIR"
    
    # Remove problematic files
    if [ -d "$FRAMEWORK_DIR/lib" ]; then
        echo "Cleaning lib directory..."
        
        # Remove bytecode files
        find "$FRAMEWORK_DIR/lib" -name "*.pyc" -delete 2>/dev/null || true
        find "$FRAMEWORK_DIR/lib" -name "*.pyo" -delete 2>/dev/null || true
        find "$FRAMEWORK_DIR/lib" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
        
        # Remove test directories (often cause issues)
        find "$FRAMEWORK_DIR/lib" -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
        find "$FRAMEWORK_DIR/lib" -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
        
        # Remove any broken symlinks
        find "$FRAMEWORK_DIR/lib" -type l ! -exec test -e {} \; -delete 2>/dev/null || true
    fi
    
    # Fix all permissions
    echo "Fixing permissions..."
    find "$FRAMEWORK_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    find "$FRAMEWORK_DIR" -type f -exec chmod 644 {} \; 2>/dev/null || true
    
    # Remove extended attributes
    echo "Removing extended attributes..."
    xattr -cr "$FRAMEWORK_DIR" 2>/dev/null || true
    
    # Make sure the main binary is executable
    if [ -f "$FRAMEWORK_DIR/Python" ]; then
        chmod 755 "$FRAMEWORK_DIR/Python"
    fi
    
    echo "Slice processed successfully"
}

# Process all slices in the XCFramework
for SLICE in "$FRAMEWORK_PATH"/*; do
    if [ -d "$SLICE" ] && [[ "$(basename "$SLICE")" != "Info.plist" ]]; then
        process_framework_slice "$SLICE"
    fi
done

echo "Python.xcframework preparation complete"
