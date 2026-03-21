---
name: frontend-performance
description: Frontend performance optimization — Core Web Vitals, bundle analysis, React rendering, image optimization, caching strategies
---

## Core Web Vitals Targets

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| **LCP** (Largest Contentful Paint) | < 2.5s | 2.5s – 4.0s | > 4.0s |
| **INP** (Interaction to Next Paint) | < 200ms | 200ms – 500ms | > 500ms |
| **CLS** (Cumulative Layout Shift) | < 0.1 | 0.1 – 0.25 | > 0.25 |

## Performance Checklist

### Critical (fix immediately)

**CSS**
- [ ] Minify all CSS files
- [ ] Non-blocking CSS — critical CSS inlined in `<head>`, rest loaded async
- [ ] Remove unused CSS (PurgeCSS / Tailwind's built-in purge)
- [ ] Avoid inline `style` attributes for reusable styles

**JavaScript**
- [ ] Minify all JS (Vite handles this in production builds)
- [ ] Non-blocking scripts — use `async` or `defer` on all `<script>` tags
- [ ] No render-blocking JS in `<head>`
- [ ] Eliminate async waterfalls — don't `await` sequentially when requests are independent

**Images**
- [ ] Use modern formats (WebP/AVIF) with fallbacks
- [ ] Compress images (Squoosh, Sharp)
- [ ] Set explicit `width` and `height` to prevent CLS
- [ ] Lazy load offscreen images (`loading="lazy"`)
- [ ] Serve exact-size images (don't resize in CSS)

**Network**
- [ ] HTTPS everywhere
- [ ] GZIP/Brotli compression enabled
- [ ] HTTP cache headers set (Cache-Control, ETag)
- [ ] Page weight < 1500KB (target < 500KB)
- [ ] TTFB < 1.3s
- [ ] Minimize HTTP requests

### High Priority

**Bundle Optimization**
- [ ] Code splitting — route-based (`React.lazy` + `Suspense`)
- [ ] Tree-shaking enabled (Vite default with ESM)
- [ ] Direct imports, not barrel files (`import { Button } from './Button'`, not `from './index'`)
- [ ] Dynamic imports for heavy libraries (`import('chart-library')`)
- [ ] Analyze bundle: `npx vite-bundle-visualizer`
- [ ] Monitor dependency sizes: check with Bundlephobia before adding

**React Rendering**
- [ ] Avoid unnecessary re-renders — `React.memo` for pure components
- [ ] `useMemo` for expensive computations
- [ ] `useCallback` for callbacks passed as props
- [ ] Virtualize long lists (`react-window` or `@tanstack/virtual`)
- [ ] Don't create objects/arrays inline in JSX props
- [ ] Key prop — use stable IDs, never array index (unless static list)

**Fonts**
- [ ] Use WOFF2 format
- [ ] `font-display: swap` to prevent invisible text
- [ ] Preconnect to font origins: `<link rel="preconnect" href="...">`
- [ ] Total web fonts < 300KB
- [ ] Subset fonts to used characters only

### Medium Priority

**Caching**
- [ ] Service Worker for offline caching (if applicable)
- [ ] Use CDN for static assets
- [ ] Preload critical resources: `<link rel="preload">`
- [ ] Prefetch likely next navigations: `<link rel="prefetch">`
- [ ] Cookie size < 4096 bytes per domain

**RTK Query Specific**
- [ ] Use `keepUnusedDataFor` to control cache lifetime
- [ ] Avoid over-fetching — request only needed fields via query params
- [ ] Use `selectFromResult` to minimize re-renders
- [ ] Tag-based invalidation — don't refetch everything on one mutation

## React Performance Antipatterns

```tsx
// BAD: Creates new object every render → child re-renders
<Child style={{ color: 'red' }} />

// GOOD: Stable reference
const style = useMemo(() => ({ color: 'red' }), []);
<Child style={style} />
```

```tsx
// BAD: Async waterfall — sequential requests
const user = await fetchUser(id);
const posts = await fetchPosts(id);  // waits for user!

// GOOD: Parallel requests
const [user, posts] = await Promise.all([
  fetchUser(id),
  fetchPosts(id)
]);
```

```tsx
// BAD: Barrel file imports pull in everything
import { Button } from '@/ui';

// GOOD: Direct import — tree-shakeable
import { Button } from '@/ui/Button';
```

## Tools

| Tool | Purpose | Command |
|------|---------|---------|
| **Lighthouse** | Full performance audit | Chrome DevTools → Lighthouse tab |
| **vite-bundle-visualizer** | Bundle composition | `npx vite-bundle-visualizer` |
| **Bundlephobia** | Dependency size check | bundlephobia.com |
| **WebPageTest** | Real-world load testing | webpagetest.org |
| **React DevTools Profiler** | Component render analysis | React DevTools → Profiler tab |

## Recommended External Skills

```bash
# Vercel React Best Practices — 45 rules, 21k+ stars
npx skills add vercel-labs/agent-skills

# Addy Osmani Web Quality — Lighthouse audits, Core Web Vitals, 1.2k stars
npx skills add addyosmani/web-quality-skills

# Image optimization + Web performance skills
npx skills add secondsky/claude-skills
```
