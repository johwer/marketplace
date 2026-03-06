# Platform Testing Guidelines

## Platform Selection Decision Tree

### When to Use Web Testing (Puppeteer)
- Testing web applications running in browsers
- Responsive web design verification
- Desktop and mobile web layouts
- Cross-browser compatibility (Chrome/Firefox/Safari)
- Available on all platforms (Windows, macOS, Linux)

### When to Use iOS Simulator
- Testing native iOS applications
- React Native iOS app development
- iOS-specific UI components
- Touch gestures and mobile interactions
- Only available on macOS

### When to Test Both
- React Native apps with web counterparts
- Universal components used in both platforms
- Ensuring consistent UX across platforms
- Verifying platform-specific adaptations

## Platform-Specific Considerations

### Web (Puppeteer)
**Strengths:**
- Fast iteration cycle
- Easy viewport manipulation
- DevTools integration
- Network throttling
- Console log access

**Limitations:**
- Cannot test native mobile features
- Limited touch gesture simulation
- No access to device APIs

### iOS Simulator
**Strengths:**
- Native iOS behavior
- True touch interactions
- Device API access
- Realistic performance
- Multiple device sizes

**Limitations:**
- macOS only
- Slower startup time
- Limited automation compared to web
- Requires app rebuild for changes

## Best Practices by Platform

### Web Testing Best Practices
1. Test at multiple viewport sizes (mobile, tablet, desktop)
2. Verify hover states and keyboard navigation
3. Check console for errors and warnings
4. Test with network throttling for slow connections
5. Verify accessibility with screen reader simulation

### iOS Testing Best Practices
1. Test on multiple device sizes (iPhone SE, standard, Pro Max)
2. Verify touch target sizes (minimum 44x44 points)
3. Test swipe gestures and navigation
4. Check safe area insets (notch/Dynamic Island)
5. Verify dark mode appearance
6. Test rotation (portrait/landscape)

## Common Scenarios

### Scenario: Building a New Feature
1. Start with web for rapid iteration
2. Once stable, verify on iOS simulator
3. Fix platform-specific issues

### Scenario: Fixing Visual Bug
1. Reproduce on the platform where bug occurs
2. Fix and verify on that platform
3. Spot-check other platform for regressions

### Scenario: Matching Design Mock
1. Determine target platform from design
2. Test on that platform primarily
3. Verify consistent experience on other platforms
