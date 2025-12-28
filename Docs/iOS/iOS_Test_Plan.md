# iOS Testing Plan - Settings & Keyboard

**Feature**: iOS Settings Access + Keyboard Dismiss  
**Date**: December 10, 2025  
**Tester**: _______________

---

## Pre-Test Setup

- [ ] Build app for iOS simulator or device
- [ ] Clear any existing API keys in Keychain (fresh state)
- [ ] Note device/simulator version: iOS _______

---

## Test 1: Settings Access

### Test 1.1: Settings Button Visibility
**Steps**:
1. Launch llmHub on iOS
2. Navigate to any chat session

**Expected**:
- [ ] Gear icon visible in top-left corner of navigation bar
- [ ] Gear icon colored in neon electric blue
- [ ] Icon is tappable (shows touch feedback)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.2: Open Settings Modal
**Steps**:
1. Tap the gear icon in top-left

**Expected**:
- [ ] Settings modal slides up from bottom
- [ ] Modal shows drag indicator at top
- [ ] "Settings" title appears in navigation bar
- [ ] "Done" button visible in top-right
- [ ] Three tabs visible at bottom: "API Keys", "Appearance", "General"

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.3: Enter API Key
**Steps**:
1. In Settings, ensure "API Keys" tab is selected
2. Find "OpenAI" provider row
3. Tap the API key text field
4. Enter test key: `sk-test-1234567890`
5. Tap "Save" button

**Expected**:
- [ ] Text field accepts input
- [ ] Keyboard appears when field is tapped
- [ ] Characters are masked (secure entry)
- [ ] Eye icon toggles visibility
- [ ] "Save" button enabled when text is present
- [ ] Success message appears: "OpenAI API key saved successfully"
- [ ] Green "Configured" badge appears next to provider name
- [ ] Green checkmark icon appears

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.4: Test All Providers
**Steps**:
Repeat Test 1.3 for each provider:

- [ ] OpenAI
- [ ] Anthropic
- [ ] Google AI
- [ ] Mistral AI
- [ ] xAI
- [ ] OpenRouter

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.5: Delete API Key
**Steps**:
1. Find a provider with a saved key (green checkmark)
2. Tap the red trash icon

**Expected**:
- [ ] Confirmation or immediate deletion
- [ ] Text field clears
- [ ] Green "Configured" badge disappears
- [ ] Success message: "[Provider] API key deleted"
- [ ] Trash icon disappears (no key to delete)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.6: Documentation Links
**Steps**:
1. In API Keys tab, find any provider
2. Tap "Get API key from [Provider]" link

**Expected**:
- [ ] Safari/browser opens
- [ ] Correct provider documentation page loads
- [ ] Link colored in neon electric blue

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.7: Appearance Tab
**Steps**:
1. Tap "Appearance" tab at bottom
2. Tap theme picker dropdown
3. Select different theme (e.g., "Liquid Glass")
4. Adjust glass effect sliders

**Expected**:
- [ ] Tab switches to Appearance settings
- [ ] Theme preview cards visible
- [ ] Theme picker shows available themes
- [ ] Selecting theme updates preview in real-time
- [ ] Sliders adjust opacity (0-100%)
- [ ] Changes apply immediately (if visible in background)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 1.8: Close Settings
**Steps**:
1. Tap "Done" button in top-right
2. Alternative: Swipe down on modal

**Expected**:
- [ ] Modal dismisses
- [ ] Returns to chat view
- [ ] Settings changes persist (API keys saved)
- [ ] Swipe-to-dismiss works smoothly

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

## Test 2: Keyboard Dismiss - Interactive Swipe

### Test 2.1: Keyboard Appears
**Steps**:
1. In chat view, tap the message input field at bottom
2. Keyboard should appear

**Expected**:
- [ ] Keyboard slides up from bottom
- [ ] Input field gains focus
- [ ] Blue border/glow appears on input field
- [ ] Keyboard dismiss button appears (small circle with chevron icon)

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 2.2: Swipe to Dismiss
**Steps**:
1. With keyboard visible, swipe down on the message list (scroll area)
2. Use a gentle downward swipe gesture

**Expected**:
- [ ] Keyboard slides down and dismisses
- [ ] Input field loses focus (blue border disappears)
- [ ] Keyboard dismiss button disappears
- [ ] Message list remains scrollable

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 2.3: Swipe While Typing
**Steps**:
1. Tap input field to show keyboard
2. Type some text: "Hello, this is a test message"
3. Swipe down on message list to dismiss keyboard
4. Tap input field again

**Expected**:
- [ ] Keyboard dismisses even with text present
- [ ] Text remains in input field (not cleared)
- [ ] Re-tapping input field shows keyboard again
- [ ] Previously typed text still visible

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

## Test 3: Keyboard Dismiss - Explicit Button

### Test 3.1: Button Appears on Focus
**Steps**:
1. Tap input field to show keyboard
2. Observe the input bar (bottom of screen)

**Expected**:
- [ ] Small circular button appears between input field and send button
- [ ] Button shows keyboard chevron down icon (`keyboard.chevron.compact.down`)
- [ ] Button matches Liquid Glass theme (translucent circle)
- [ ] Button animates in with scale + fade transition

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 3.2: Button Dismisses Keyboard
**Steps**:
1. With keyboard visible, tap the keyboard dismiss button

**Expected**:
- [ ] Keyboard immediately dismisses
- [ ] Input field loses focus
- [ ] Keyboard dismiss button animates out (scale + fade)
- [ ] Any typed text remains in input field

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 3.3: Button Hidden When Not Focused
**Steps**:
1. Start with keyboard hidden
2. Observe input bar

**Expected**:
- [ ] Keyboard dismiss button NOT visible
- [ ] Only input field and send button visible
- [ ] Layout clean and uncluttered

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 3.4: Button Appearance in Both Themes
**Steps**:
1. Go to Settings → Appearance
2. Switch to "Liquid Glass" theme
3. Return to chat, focus input field, observe dismiss button
4. Go to Settings → Appearance
5. Switch to "Classic" theme
6. Return to chat, focus input field, observe dismiss button

**Expected**:
- [ ] **Liquid Glass**: Translucent glass circle with blur effect
- [ ] **Classic**: Semi-transparent gray circle
- [ ] Both themes: Button is clearly visible and tappable
- [ ] Styling matches send button nearby

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

## Test 4: Integration & Edge Cases

### Test 4.1: Send Message with Keyboard Visible
**Steps**:
1. Tap input field to show keyboard
2. Type a message
3. Tap send button (arrow up)

**Expected**:
- [ ] Message sends successfully
- [ ] Input field clears
- [ ] Keyboard remains visible (iOS behavior)
- [ ] Can immediately type next message

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 4.2: Rotate Device/Orientation Change
**Steps**:
1. Focus input field (keyboard visible)
2. Rotate device to landscape
3. Rotate back to portrait

**Expected**:
- [ ] Keyboard adapts to new orientation
- [ ] Keyboard dismiss button remains visible
- [ ] Settings modal (if open) adapts to rotation
- [ ] No layout breaks or overlaps

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 4.3: Settings While Keyboard Visible
**Steps**:
1. Focus input field (keyboard visible)
2. Tap gear icon to open Settings

**Expected**:
- [ ] Keyboard dismisses automatically
- [ ] Settings modal opens smoothly
- [ ] No keyboard visible behind settings
- [ ] Can type in API key fields in Settings

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 4.4: Background/Foreground with Keyboard
**Steps**:
1. Focus input field (keyboard visible)
2. Press Home button or swipe to app switcher
3. Return to app

**Expected**:
- [ ] Keyboard state handled gracefully
- [ ] No crash or layout issues
- [ ] Input field state preserved

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 4.5: VoiceOver Accessibility
**Steps** (if VoiceOver available):
1. Enable VoiceOver in iOS Settings
2. Navigate to llmHub chat view
3. Focus input field with VoiceOver
4. Locate keyboard dismiss button

**Expected**:
- [ ] Gear icon has accessibility label: "Settings"
- [ ] Keyboard dismiss button has clear label: "Dismiss keyboard" or similar
- [ ] Input field properly labeled
- [ ] All controls navigable with VoiceOver

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

## Test 5: Settings Persistence

### Test 5.1: API Keys Persist
**Steps**:
1. Enter API keys for 2-3 providers
2. Close Settings (Done button)
3. Completely quit app (swipe up in app switcher)
4. Relaunch app
5. Open Settings

**Expected**:
- [ ] All saved API keys still present
- [ ] "Configured" badges visible for saved providers
- [ ] No need to re-enter keys

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

### Test 5.2: Appearance Settings Persist
**Steps**:
1. Change theme to "Liquid Glass"
2. Adjust several glass opacity sliders
3. Close Settings
4. Quit and relaunch app
5. Open Settings → Appearance

**Expected**:
- [ ] Selected theme still active
- [ ] All opacity values preserved
- [ ] Theme visually applied throughout app

**Result**: ☐ Pass ☐ Fail  
**Notes**: _____________________________________________

---

## Performance & Polish

### Smoothness
- [ ] Settings modal opens/closes smoothly (60fps)
- [ ] Keyboard dismiss animations smooth
- [ ] No lag when typing in input field
- [ ] Theme switches apply instantly

### Visual Polish
- [ ] Neon theme colors used consistently
- [ ] Glass effects render correctly
- [ ] No visual glitches or artifacts
- [ ] Dark mode support correct
- [ ] Safe area insets respected (notch/Dynamic Island)

### Haptics (if device supports)
- [ ] Subtle haptic on settings save?
- [ ] Haptic on settings delete?
- [ ] Haptic on keyboard dismiss? (Optional)

---

## Bug Tracking

### Issues Found

**Issue #1**:
- **Description**: _____________________________________________
- **Steps to Reproduce**: _____________________________________________
- **Expected**: _____________________________________________
- **Actual**: _____________________________________________
- **Severity**: ☐ Critical ☐ High ☐ Medium ☐ Low
- **Screenshot/Video**: _____________________________________________

**Issue #2**:
- **Description**: _____________________________________________
- **Steps to Reproduce**: _____________________________________________
- **Expected**: _____________________________________________
- **Actual**: _____________________________________________
- **Severity**: ☐ Critical ☐ High ☐ Medium ☐ Low
- **Screenshot/Video**: _____________________________________________

---

## Sign-Off

**Overall Result**: ☐ Pass ☐ Fail ☐ Pass with Issues

**Summary**:
_____________________________________________
_____________________________________________
_____________________________________________

**Tested By**: _______________  
**Date**: _______________  
**iOS Version**: _______________  
**Device**: _______________

**Ready for Production**: ☐ Yes ☐ No ☐ With Fixes

---

## Notes for Developers

- If any tests fail, attach logs from Xcode console
- Check for warnings in Xcode build output
- Verify Keychain access works correctly in simulator vs device
- Test on multiple iOS versions if possible (iOS 15+, iOS 16+, iOS 17+)
