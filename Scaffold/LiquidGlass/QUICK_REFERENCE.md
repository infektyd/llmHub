# Liquid Glass - Quick Reference Card

**For use AFTER activation (Jan 26, 2025+)**

---

## Glass Modifiers

### Basic Usage
```swift
.glassCard()                    // Standard frosted glass
.glassPill()                    // Rounded capsule glass
.glassRounded(16)               // Custom corner radius
.glassCard(.elevated)           // Stronger material
.glassCard(.prominent)          // Maximum visibility
```

### With Customization
```swift
.glassCard(.regular.tint(.green))       // Green tinted
.glassCard(.elevated.interactive())     // Responds to touch
.glassEffect(.dark, in: .circle)        // Custom shape
```

### Available Glass Presets
- `.regular` - Standard frosted (default)
- `.elevated` - Stronger material, bigger shadow
- `.interactive` - Responds to user interaction
- `.prominent` - Maximum contrast and visibility
- `.dark` - Optimized for dark backgrounds

---

## Button Styles

```swift
Button("Click") { }
    .buttonStyle(.glass)                // Standard glass button
    .buttonStyle(.glassProminent)       // Prominent glass button
    .buttonStyle(.glass(.elevated))     // Custom glass style
```

---

## Colors

### Semantic Colors (Use These!)
```swift
LiquidGlassTokens.Colors.accent         // Primary accent (cyan)
LiquidGlassTokens.Colors.textPrimary    // White text
LiquidGlassTokens.Colors.textSecondary  // Gray text
LiquidGlassTokens.Colors.success        // Green
LiquidGlassTokens.Colors.warning        // Orange
LiquidGlassTokens.Colors.error          // Red
```

### Glass Tints (For .tint() modifier)
```swift
LiquidGlassTokens.Colors.Glass.accent
LiquidGlassTokens.Colors.Glass.success
LiquidGlassTokens.Colors.Glass.warning
LiquidGlassTokens.Colors.Glass.error
```

### Backgrounds
```swift
LiquidGlassTokens.Colors.background         // Main background
LiquidGlassTokens.Colors.backgroundSecondary
LiquidGlassTokens.Colors.surface
```

### Convenient Shorthand (After Activation)
```swift
Color.liquid.accent         // Shorthand for above
Color.liquid.textPrimary
Color.liquid.success
```

---

## Typography

### Font Sizes & Weights
```swift
LiquidGlassTokens.Typography.display()              // Large headline
LiquidGlassTokens.Typography.heading()              // Medium heading
LiquidGlassTokens.Typography.heading(.headingSmall) // Small heading
LiquidGlassTokens.Typography.body()                 // Regular body
LiquidGlassTokens.Typography.body(.bodySmall)       // Small body
LiquidGlassTokens.Typography.label()                // Label text
LiquidGlassTokens.Typography.mono()                 // Code/monospace
```

### Available Sizes
```swift
.display      // 32pt (bold)
.heading      // 24pt (semibold)
.body         // 14pt (regular)
.label        // 12pt (medium)
.mono         // 14pt (monospaced)
```

### Usage Example
```swift
Text("Title")
    .font(LiquidGlassTokens.Typography.heading())

Text("Subtitle")
    .font(LiquidGlassTokens.Typography.label(.labelSmall))
```

---

## Spacing

```swift
LiquidGlassTokens.Spacing.xxs    // 4
LiquidGlassTokens.Spacing.xs     // 8
LiquidGlassTokens.Spacing.sm     // 12
LiquidGlassTokens.Spacing.md     // 16
LiquidGlassTokens.Spacing.lg     // 24
LiquidGlassTokens.Spacing.xl     // 32
LiquidGlassTokens.Spacing.xxl    // 48
LiquidGlassTokens.Spacing.xxxl   // 64
```

### Usage Example
```swift
VStack(spacing: LiquidGlassTokens.Spacing.md) {
    Text("Item 1")
    Text("Item 2")
}
.padding(LiquidGlassTokens.Spacing.lg)
```

### Shorthand (After Convenient Extension)
```swift
VStack(spacing: .spacing.md) { }
.padding(.spacing.lg)
```

---

## Corner Radius

```swift
LiquidGlassTokens.Radius.xs     // 4
LiquidGlassTokens.Radius.sm     // 8
LiquidGlassTokens.Radius.md     // 12
LiquidGlassTokens.Radius.lg     // 16
LiquidGlassTokens.Radius.xl     // 20
LiquidGlassTokens.Radius.xxl    // 24
LiquidGlassTokens.Radius.full   // ∞ (circle)
```

### Usage
```swift
.cornerRadius(LiquidGlassTokens.Radius.md)
.glassRounded(LiquidGlassTokens.Radius.lg)
```

---

## Shadows

```swift
LiquidGlassTokens.Shadows.none   // No shadow
LiquidGlassTokens.Shadows.sm     // Subtle (4pt radius)
LiquidGlassTokens.Shadows.md     // Standard (8pt radius)
LiquidGlassTokens.Shadows.lg     // Elevated (12pt radius)
LiquidGlassTokens.Shadows.xl     // Strong (20pt radius)
```

---

## Animations

```swift
LiquidGlassTokens.Animation.fast        // 0.15s (UI interactions)
LiquidGlassTokens.Animation.normal      // 0.3s (standard)
LiquidGlassTokens.Animation.slow        // 0.5s (emphatic)
LiquidGlassTokens.Animation.spring      // Bouncy spring
```

### Usage
```swift
withAnimation(LiquidGlassTokens.Animation.normal) {
    // Change state
}
```

---

## Common Patterns

### Status Card
```swift
VStack(spacing: 8) {
    HStack {
        Image(systemName: "checkmark.circle.fill")
        Text("Success!")
    }
    .foregroundStyle(.green)
    
    Text("Operation completed")
        .font(.caption)
}
.padding(LiquidGlassTokens.Spacing.md)
.glassCard(.regular.tint(.green))
```

### Input Field
```swift
TextField("Enter text", text: $text)
    .padding(LiquidGlassTokens.Spacing.md)
    .glassCard()
```

### Button Group
```swift
HStack(spacing: LiquidGlassTokens.Spacing.md) {
    Button("Cancel") { }
        .buttonStyle(.glass)
    
    Button("Save") { }
        .buttonStyle(.glass(.prominent))
}
```

### Message Bubble
```swift
VStack(alignment: .leading, spacing: 4) {
    Text("From: AI")
        .font(LiquidGlassTokens.Typography.label())
    
    Text("Response text")
        .font(LiquidGlassTokens.Typography.body())
}
.padding(LiquidGlassTokens.Spacing.md)
.glassCard(.regular.tint(LiquidGlassTokens.Colors.Glass.accent))
```

### Section Header
```swift
VStack(alignment: .leading, spacing: 12) {
    Text("Settings")
        .font(LiquidGlassTokens.Typography.heading(.headingMedium))
    
    Divider()
        .opacity(0.3)
}
.padding(LiquidGlassTokens.Spacing.md)
```

---

## Migration Checklist

When migrating existing code:

- [ ] Replace `.background(.ultraThinMaterial)` with `.glassCard()`
- [ ] Replace `GlassCard { }` with `.glassCard()` modifier
- [ ] Replace hardcoded colors with `LiquidGlassTokens.Colors.*`
- [ ] Replace hardcoded font sizes with `LiquidGlassTokens.Typography.*`
- [ ] Replace hardcoded spacing with `LiquidGlassTokens.Spacing.*`
- [ ] Replace `.cornerRadius(16)` with `.cornerRadius(LiquidGlassTokens.Radius.lg)`
- [ ] Test visual appearance (should be identical or better)

---

## What NOT to Do

❌ Don't use hardcoded colors:
```swift
// Wrong
Color(red: 0.7, green: 0.7, blue: 0.8)

// Right
LiquidGlassTokens.Colors.textSecondary
```

❌ Don't use inline materials:
```swift
// Wrong
.background(.ultraThinMaterial).cornerRadius(16)

// Right
.glassCard()
```

❌ Don't nest GlassCard components:
```swift
// Wrong
GlassCard {
    GlassCard {
        Text("Content")
    }
}

// Right
Text("Content")
    .glassCard()
    .padding()
    .glassCard(.elevated)
```

❌ Don't use magic numbers for spacing:
```swift
// Wrong
.padding(16)

// Right
.padding(LiquidGlassTokens.Spacing.md)
```

---

## Need More Info?

| Topic | Document |
|-------|----------|
| Overview & Examples | `README.md` |
| Activation Steps | `LiquidGlassMigration.md` |
| Architecture Details | `INTEGRATION_GUIDE.md` |
| Complete Implementation | `LiquidGlassTheme.swift` |
| All Token Definitions | `LiquidGlassTokens.swift` |
| Project Timeline | `Scaffold/README.md` |

---

## Cheat Sheet Preview

### Before (Current Code)
```swift
VStack {
    Text("Status")
        .font(.system(size: 20, weight: .semibold))
        .foregroundStyle(.white)
    
    HStack {
        Image(systemName: "checkmark.circle")
        Text("Complete")
            .foregroundStyle(.green)
    }
    .font(.system(size: 14))
}
.padding(16)
.background(.ultraThinMaterial)
.cornerRadius(12)
```

### After (Liquid Glass)
```swift
VStack {
    Text("Status")
        .font(LiquidGlassTokens.Typography.heading(.headingSmall))
        .foregroundStyle(LiquidGlassTokens.Colors.textPrimary)
    
    HStack {
        Image(systemName: "checkmark.circle")
        Text("Complete")
            .foregroundStyle(.green)
    }
    .font(LiquidGlassTokens.Typography.body())
}
.padding(LiquidGlassTokens.Spacing.md)
.glassCard(.regular.tint(.green))
```

✅ Clearer intent  
✅ Consistent appearance  
✅ Single source of truth  
✅ Easier to maintain  

---

**Print this card and keep it nearby during migration!**

For full details, see the comprehensive guides in `Scaffold/LiquidGlass/`
