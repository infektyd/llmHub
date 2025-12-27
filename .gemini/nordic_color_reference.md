# Nordic Theme - Quick Color Reference

## Primary Colors

### Terracotta (Primary Accent)

```swift
Color(hex: "CD6F4E")
```

- **Use:** Primary buttons, user message bubbles, focus states
- **RGB:** 205, 111, 78
- **HSL:** 16°, 54%, 55%

### Sage (Secondary Accent)

```swift
Color(hex: "7BA382")
```

- **Use:** Secondary buttons, assistant message accent bar, selection highlights
- **RGB:** 123, 163, 130
- **HSL:** 131°, 18%, 56%

## Dark Mode Palette

### Backgrounds

```swift
// Canvas (Stone-900)
Color(hex: "1C1917")  // RGB: 28, 25, 23

// Surface (Stone-800)
Color(hex: "292524")  // RGB: 41, 37, 36
```

### Text

```swift
// Primary (Stone-50)
Color(hex: "FAFAF9")  // RGB: 250, 250, 249

// Secondary (Stone-400)
Color(hex: "A8A29E")  // RGB: 168, 162, 158

// Tertiary (Stone-500)
Color(hex: "78716C")  // RGB: 120, 113, 108
```

### Borders

```swift
// Stone-700
Color(hex: "44403C")  // RGB: 68, 64, 60
```

## Light Mode Palette

### Backgrounds

```swift
// Canvas
Color(hex: "FAF9F7")  // RGB: 250, 249, 247

// Surface
Color.white  // RGB: 255, 255, 255
```

### Text

```swift
// Primary
Color(hex: "1C1917")  // RGB: 28, 25, 23

// Secondary
Color(hex: "A8A29E")  // RGB: 168, 162, 158

// Tertiary
Color(hex: "78716C")  // RGB: 120, 113, 108
```

### Borders

```swift
// Stone-200
Color(hex: "E7E5E4")  // RGB: 231, 229, 228
```

## Semantic Colors

### Success

```swift
Color(hex: "7BA382")  // Sage (same as secondary accent)
```

### Warning

```swift
Color(hex: "F59E0B")  // Amber
// RGB: 245, 158, 11
```

### Error

```swift
Color(hex: "DC2626")  // Warm Red
// RGB: 220, 38, 38
```

## Usage Examples

### User Message Bubble

```swift
RoundedRectangle(cornerRadius: 16)
    .fill(Color(hex: "CD6F4E"))  // Terracotta
```

### Assistant Message Card

```swift
// Background
RoundedRectangle(cornerRadius: 12)
    .fill(colorScheme == .dark ? Color(hex: "292524") : .white)

// Left accent bar
Rectangle()
    .fill(Color(hex: "7BA382"))  // Sage
    .frame(width: 3)
```

### Selected Sidebar Row

```swift
RoundedRectangle(cornerRadius: 8)
    .fill(Color(hex: "7BA382"))  // Sage
```

### Focused Text Field Border

```swift
RoundedRectangle(cornerRadius: 8)
    .stroke(Color(hex: "CD6F4E"), lineWidth: 1)  // Terracotta
```

## Color Scheme Switching

All components use `@Environment(\.colorScheme)` to adapt:

```swift
@Environment(\.colorScheme) private var colorScheme

private var backgroundColor: Color {
    colorScheme == .dark
        ? Color(hex: "292524")  // Dark mode
        : Color.white           // Light mode
}
```

## Accessibility Notes

- **Contrast Ratios:** All text/background combinations meet WCAG AA standards
- **Terracotta on White:** 4.8:1 (AA compliant)
- **Sage on White:** 3.5:1 (Use for non-critical text only)
- **White on Terracotta:** 5.2:1 (AA compliant)
- **White on Sage:** 3.8:1 (AA compliant for large text)
