# 🟣 GLASS: UI Update - Model Picker & Sidebar

**Date**: December 11, 2025
**Status**: ✅ IMPLEMENTED

## Summary
Implemented a sleek, cross-platform model selection menu, sidebar toggle, and settings integration.

## Changes

### 1. Model Selection (`NeonModelPickerSheet.swift`)
- **Refactor**: Converted to a cross-platform (iOS/macOS) sheet.
- **UI**: Added "brain" icon for models, "crown" for premium tiers, and "star.fill" for favorites.
- **Features**: Searchable list, favorites section, pricing tier indicators.

### 2. UI Models (`UIModels.swift`)
- **Added**: `PricingTier` enum to `UILLMModel` to support premium/free tier visualization.

### 3. macOS Toolbar (`NeonToolbar.swift`)
- **Added**: "sidebar.left" toggle button for the sidebar.
- **Added**: "gearshape" button for Settings.
- **Updated**: integrated `NeonModelPicker` which now launches the sheet.

### 4. macOS Picker (`NeonModelPicker.swift`)
- **Updated**: Replaced popover with `.sheet` using `NeonModelPickerSheet`.

### 5. Chat View (`NeonChatView.swift`)
- **Shared State**: Moved `showingSettings` and `modelRegistry` to be available on all platforms.
- **Integration**: Passed bindings to `NeonToolbar` and added Settings sheet modifier.

## Verification
- **Build**: Pending verification.
- **Cross-Platform**: iOS uses `NeonModelPickerButton` (which uses the sheet), macOS uses `NeonModelPicker` (which now uses the sheet).
