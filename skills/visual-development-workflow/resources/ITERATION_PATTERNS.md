# Common Iteration Patterns

## Pattern 1: Layout Mismatch

**Symptom:** Elements don't align with design mock

**Iteration Strategy:**
1. First pass: Fix major structural issues (flexbox/grid)
2. Second pass: Adjust spacing and padding
3. Third pass: Fine-tune alignment and margins

**Example:**
```
Iteration 1: Changed layout from block to flexbox
Screenshot shows: Better but spacing too tight

Iteration 2: Adjusted gap and padding values
Screenshot shows: Spacing correct, but alignment off

Iteration 3: Added align-items: center
Screenshot shows: Perfect match
```

## Pattern 2: Color/Typography Mismatch

**Symptom:** Colors or fonts don't match design

**Iteration Strategy:**
1. First pass: Update primary colors and font families
2. Second pass: Adjust font sizes and weights
3. Third pass: Fine-tune opacity, shadows, and details

**Example:**
```
Iteration 1: Changed button color from blue to brand coral
Screenshot shows: Color closer but still slightly off

Iteration 2: Updated hex value to exact brand color
Screenshot shows: Color perfect, font weight too light

Iteration 3: Changed font-weight to 600
Screenshot shows: Perfect match
```

## Pattern 3: Responsive Issues

**Symptom:** Layout breaks at certain viewports

**Iteration Strategy:**
1. First pass: Identify breakpoint where it breaks
2. Second pass: Add/adjust media queries
3. Third pass: Test all breakpoints (mobile, tablet, desktop)

**Example:**
```
Iteration 1: Take screenshot at 375px width
Screenshot shows: Menu overlapping content

Iteration 2: Add mobile menu breakpoint at 768px
Screenshot shows: Menu fixed but logo too large

Iteration 3: Adjust logo size for mobile
Screenshot shows: All viewports working correctly
```

## Pattern 4: Interactive State Issues

**Symptom:** Hover, focus, or active states incorrect

**Iteration Strategy:**
1. First pass: Implement base interactive states
2. Second pass: Test and screenshot each state
3. Third pass: Adjust timing, colors, transitions

**Example:**
```
Iteration 1: Add hover state styles
Screenshot shows: Hover works but too abrupt

Iteration 2: Add transition property
Screenshot shows: Transition smooth but wrong color

Iteration 3: Adjust hover background color
Screenshot shows: Perfect interaction
```

## Pattern 5: Cross-Platform Differences

**Symptom:** Looks different on web vs iOS

**Iteration Strategy:**
1. First pass: Make it work on primary platform
2. Second pass: Test on secondary platform, identify differences
3. Third pass: Add platform-specific adjustments

**Example:**
```
Iteration 1: Implement feature for web
Screenshot shows: Web looks perfect

Iteration 2: Test on iOS simulator
Screenshot shows: Safe area insets causing issues

Iteration 3: Add SafeAreaView wrapper for iOS
Screenshot shows: Both platforms working correctly
```

## When to Stop Iterating

### Good Stopping Points:
- Visual output matches design within reasonable tolerance
- All interactive elements function correctly
- Responsive behavior works across target breakpoints
- No console errors or warnings
- User approves the result

### Red Flags to Continue:
- Obvious layout breaks or overlapping elements
- Colors significantly different from brand guidelines
- Interactive elements not responding
- Console showing errors
- User points out issues

## Efficiency Tips

### Avoid Over-Iteration:
- Don't chase pixel-perfection on first pass
- Focus on major issues before minor details
- Use design tokens/variables to avoid repeated color/spacing adjustments
- Ask user if "close enough" is acceptable

### Batch Related Changes:
- Fix all spacing issues together
- Update all colors in one iteration
- Adjust all font sizes at once

### Learn from Patterns:
- If buttons consistently need more padding, update base styles
- If colors are always slightly off, verify design system values
- If breakpoints always need adjustment, review media query strategy
