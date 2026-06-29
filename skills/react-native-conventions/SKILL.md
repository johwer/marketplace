---
name: react-native-conventions
description: React Native / Expo / NativeWind best practices for the Repo mobile app (apps/mobile). Use when reviewing or writing Expo Router + NativeWind v4 code — fonts, theming, styling, navigation, SecureStore, and WebView auth.
---

# React Native Conventions (Expo + NativeWind)

Curated, stack-specific best practices for `apps/mobile` (Expo SDK 56 / RN New Architecture / React 19 / NativeWind v4 / Expo Router). This is an **independent reference** — do not assume the in-repo `docs/CODING_STYLE_MOBILE.md` is authoritative on its own (it may share an author with the code under review). Where this skill and that doc disagree, reason from first principles and flag the conflict.

## Fonts — the #1 source of confusion

**There is no global default-font mechanism in React Native.** RN has no DOM and no CSS cascade, so there is no `body { font-family }` equivalent. NativeWind compiles each `className` to a per-element style object; it does **not** emit a global `* { font-family }`. RN's built-in `<Text>`/`<TextInput>` always fall back to the OS system font (San Francisco / Roboto) unless a font family is set on that element.

Consequences when reviewing/answering font questions:

- **A `fontFamily` mapping in `tailwind.config` does NOT load a font.** The font must be loaded at runtime via `useFonts(...)` (from `expo-font` / `@expo-google-fonts/*`) and render must be gated until `loaded` is true (return `null` / keep the splash screen up). Verify both the mapping *and* a matching `useFonts` call exist.
- **The deprecated "global default" tricks do not work on this stack.** `Text.defaultProps.style = {...}` and `react-native-global-props`' `setCustomText(...)` both rely on `defaultProps`, which **React 19 removed for function components**. Monkeypatching `Text.render` is fragile. Do not recommend any of these.
- **The correct pattern is a custom `<Text>` wrapper** with the font baked into its base styles (e.g. a `cva` base of `font-sans`). Call sites then need **no** `font-sans` class. Treat the wrapper as the *only* Text anyone imports.
- **Enforce the wrapper with ESLint** so nobody writes `font-sans` by hand or silently drops to system-font RN `Text`:
  ```js
  "no-restricted-imports": ["error", {
    paths: [{
      name: "react-native",
      importNames: ["Text", "TextInput"],
      message: "Import the app's <Text>/<TextInput> wrapper — RN's defaults use the system font and bypass the brand font.",
    }],
  }]
  ```
  Apply the same wrapper treatment to `TextInput` (it has the identical system-font default).
- **Weights are family swaps, not numeric weights.** Custom fonts don't synthesize weight in RN. Map each weight to its own loaded family (`DMSans_400Regular` / `_500Medium` / `_700Bold`) and expose a `weight` prop. Writing `className="font-bold"` (Tailwind numeric weight) yields faux-bold on iOS / no-op on Android — flag it; only `weight="bold"` / `font-sans-bold` works.
- **Give web font stacks a generic fallback.** `sans: ["DMSans_400Regular"]` compiles to a fallback-less `font-family` on web (`web.output: "single"`). Add a trailing generic (`"sans-serif"`) so text degrades gracefully during font load / on failure. Native is unaffected (render is gated), but the fallback is cheap and correct.

## Styling & theming (NativeWind v4)

- **Runtime theming uses `vars()`.** A `ThemeProvider` wraps the tree in a `<View style={vars(colors)}>`; Tailwind colors map to `var(--color-*)`. CSS vars only reach descendants of that View. This is the correct v4 pattern.
- **Native navigator chrome lives outside the var scope.** `Stack`/`Drawer` `screenOptions` (`headerStyle`, `contentStyle`, tint) can't read the CSS vars — resolve them through a `useThemeColor(...)` hook that returns the raw value. Correct workaround; don't flag it.
- **Use semantic tokens, never raw colors** — *and verify the token value, not just the form.* A hardcoded `text-black` (`#000`) is wrong if the brand's `--color-primary-text` is e.g. `#192d05`; the bug is a wrong color even for a single brand, independent of any white-label argument. Flag raw `text-gray-500`, `border-gray-300`, `#hex`, `"#000"` defaults — point to the matching semantic token.
- **`global.css` is just `@tailwind base/components/utilities`** for v4 — minimal is correct.
- **`app/+html.tsx` is web-only.** Styles there (and `@layer base` element selectors) affect the web build only — they never reach native. Hardcoding a value there that equals the active brand's token is acceptable for a single-brand app; otherwise prefer the token.
- **White-label vs single-brand is a scope decision to confirm, not assume.** If the theme constants define multiple retailers but the product is one brand, the extra themes/`setRetailer` may be speculative (YAGNI) — raise it, and check whether the style doc's claims match reality.

## Security essentials (RN apps handle real tokens)

- **`SecureStore.setItemAsync` must pass `keychainAccessible`.** The default `AFTER_FIRST_UNLOCK` keeps tokens readable while locked and can land in backups. For auth/health tokens use `{ keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY }`.
- **WebView auth is a token-injection surface.** `originWhitelist={["*"]}` *plus* an `onMessage` handler that trusts any payload as a token is exploitable: RN's `onMessage` does not expose sender origin, so the trust boundary must be enforced on navigation via `onShouldStartLoadWithRequest` pinned to known IdP origins (Repo / Microsoft / BankID). Allowing those origins to *load* is fine; leaving navigation unpinned is not.
- **Validate URL scheme/host before `Linking.openURL(...)`** of WebView-supplied strings — otherwise a compromised page can trigger arbitrary schemes (`tel:`, `intent:`, …).
- **Don't commit credentials**, even `__DEV__`-gated ones — they stay in the JS bundle and trip secret scanners. Load from untracked local config / runtime entry.
- **401 handling should match web parity**: single-flight refresh + one retry before force-logout, not log-out-on-every-401.

## Components & Expo config

- **Use the app's UI primitives** (`components/ui/*`), not raw `react-native` elements, at call sites. HTML elements don't exist in RN.
- **Props type naming**: `<Component>Props` (e.g. `DevLoginModalProps`), not a bare `Props`, when the repo convention calls for it.
- **Deep-link scheme must be consistent** across `app.json` `scheme`, BankID `redirect=` URLs, and any web/native bridge — a mismatch breaks same-device return-to-app.
- **Fail loud** over silent defaulting; handle async login promises (`.catch` → error banner) rather than leaving unhandled rejections.

## Review checklist (quick pass)

1. Every mapped custom font has a matching `useFonts` + render gate?
2. Is there a `Text`/`TextInput` wrapper, and is RN's version lint-banned?
3. `weight` prop used instead of `font-bold`? Web font stack has a generic fallback?
4. Raw colors / `#hex` instead of semantic tokens — and do token *values* match intent?
5. `SecureStore` calls pass `keychainAccessible`?
6. WebView: `onShouldStartLoadWithRequest` pinned; `onMessage` token trust enforced on navigation?
7. Multi-retailer theming actually used, or speculative for a single-brand app?
8. Deep-link scheme consistent everywhere?
