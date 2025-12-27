# Nordic UI - Quick Testing Guide

## How to Test the Nordic UI

### 1. Switch to Nordic Mode

1. **Open Settings:**
   - macOS: Press `Cmd+,` or go to `llmHub > Settings...`
2. **Navigate to Appearance:**
   - Click the "Appearance" tab
3. **Select Nordic UI:**
   - Under "UI Style", click the "Nordic" card
   - You should see a blue info box appear
4. **Restart the App:**
   - Quit llmHub (`Cmd+Q`)
   - Relaunch llmHub
5. **Verify Nordic UI:**
   - You should see a clean, minimal interface
   - Warm earth tones (terracotta, sage green)
   - No glass effects
   - "Nordic" badge in the top-right of the chat area

### 2. Test Core Features

#### Sidebar

- [ ] See list of conversations
- [ ] Click "New Chat" button creates a new session
- [ ] Click on a conversation selects it
- [ ] Selected conversation has sage green background
- [ ] Hover states work (light gray on hover)
- [ ] AFM categories show below conversation titles

#### Chat Area

- [ ] Empty state shows "Start a conversation" message
- [ ] Selected conversation shows in main area
- [ ] Conversation title displays in header
- [ ] Model name shows below title

#### Messages

- [ ] User messages appear as terracotta bubbles (right-aligned)
- [ ] Assistant messages appear as white/dark cards with sage left border (left-aligned)
- [ ] Timestamps show below each message
- [ ] Messages are readable in both light and dark mode

#### Input Bar

- [ ] Text field accepts input
- [ ] Send button is disabled when empty
- [ ] Send button is enabled when text is entered
- [ ] Pressing Enter sends the message
- [ ] Clicking send button sends the message
- [ ] Input clears after sending

### 3. Test Light/Dark Mode

1. **Switch to Dark Mode:**
   - macOS: System Settings > Appearance > Dark
2. **Verify Colors:**

   - Background: Warm charcoal (`#1C1917`)
   - Cards: Stone (`#292524`)
   - Text: Warm off-white (`#FAFAF9`)
   - Accents: Lighter terracotta and sage

3. **Switch to Light Mode:**
   - macOS: System Settings > Appearance > Light
4. **Verify Colors:**
   - Background: Warm cream (`#FAF9F7`)
   - Cards: White
   - Text: Dark stone (`#1C1917`)
   - Accents: Terracotta and sage

### 4. Test View Hierarchy Debugger

**This is the critical test - Nordic UI should NOT crash the debugger!**

1. **Run the app in Xcode**
2. **Switch to Nordic mode** (if not already)
3. **Open Debug menu** > **View Debugging** > **Capture View Hierarchy**
4. **Verify:** The view hierarchy should load successfully
5. **Inspect:** You should see all Nordic views in the hierarchy
6. **No crashes:** The debugger should not crash or show errors

### 5. Switch Back to Neon Mode

1. **Open Settings** (`Cmd+,`)
2. **Go to Appearance tab**
3. **Select "Neon Glass"** card
4. **Restart the app**
5. **Verify:** You're back to the Neon/Glass UI

### 6. Compare Nordic vs Neon

| Feature                 | Nordic           | Neon/Glass      |
| ----------------------- | ---------------- | --------------- |
| Glass effects           | ❌ None          | ✅ Everywhere   |
| Color palette           | Warm earth tones | Vibrant neon    |
| Design style            | Minimal, clean   | Modern, dynamic |
| View Hierarchy Debugger | ✅ Works         | ❌ Crashes      |
| Performance             | ✅ Fast          | ✅ Fast         |
| Animations              | Subtle           | Prominent       |

## Troubleshooting

### Nordic mode doesn't activate

- **Solution:** Make sure you restarted the app after selecting Nordic in Settings

### Colors look wrong

- **Check:** System appearance (light/dark mode)
- **Verify:** `@Environment(\.colorScheme)` is working correctly

### Messages not showing

- **Check:** Session has messages in the database
- **Verify:** `ChatSessionEntity` is being queried correctly

### Input bar not working

- **Check:** `WorkbenchViewModel.chatViewModel.inputText` binding
- **Verify:** `send()` function is being called

### Build errors

- **Solution:** Clean build folder (`Cmd+Shift+K`) and rebuild
- **Check:** All Nordic files are included in the target

## Expected Behavior

### On First Launch (Nordic Mode)

1. Sidebar shows "Conversations" header
2. "New Chat" button is visible
3. Main area shows "Start a conversation" welcome message
4. Everything uses Nordic colors
5. No glass effects anywhere

### After Creating a Chat

1. New session appears in sidebar
2. Session is automatically selected (sage green background)
3. Chat area shows the session
4. Input bar is ready for text
5. Sending a message creates a user message bubble (terracotta)

### After Receiving a Response

1. Assistant message appears below user message
2. Message has sage green left border
3. Message content is readable
4. Timestamp is visible

## Performance Benchmarks

Nordic UI should be:

- **Faster to render** (no glass effects)
- **Lower memory usage** (simpler views)
- **Smoother scrolling** (no blur effects)
- **Instant UI updates** (no complex animations)

## Accessibility

Nordic UI should support:

- **VoiceOver:** All elements have labels
- **Keyboard navigation:** Tab through elements
- **High contrast:** Works in both light and dark mode
- **Text scaling:** Respects system text size

---

**Last Updated:** December 26, 2025
**Status:** Ready for Testing
