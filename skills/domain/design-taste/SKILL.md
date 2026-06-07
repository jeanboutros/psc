---
name: design-taste
description: "Anti-slop frontend design skill. Covers typography, color, layout, motion, accessibility, dark mode, and the full pre-flight checklist for shipping premium UI. Triggered when building landing pages, portfolios, marketing sites, or any consumer-facing UI where design quality matters. Synthesised from multiple open-source design skills."
---

# Design Taste — Premium Frontend Skill

## Purpose

Prevent AI-generated UI from looking generic, templated, or "slop." This skill provides rules for typography, color, layout, motion, accessibility, and states that produce interfaces people love without knowing why.

## When to Trigger

- Building any consumer-facing UI (landing pages, marketing sites, portfolios)
- Implementing a design brief where aesthetic quality is specified
- Reviewing UI implementation for design quality
- Any time the brief mentions a design direction (minimalist, premium, playful, editorial, etc.)

## Sources

This skill is synthesised from the following open-source skills. Check these repos for updates:

| Source | Repository | Focus |
|--------|-----------|-------|
| Taste Skill (v2) | `https://github.com/Leonxlnx/taste-skill` | Anti-slop frontend, layout, typography, motion, pre-flight |
| Emil Kowalski Design Eng | `https://github.com/emilkowalski/skill` | Animation decisions, component polish, spring physics, CSS mastery |
| Impeccable | `https://github.com/pbakaus/impeccable` | Design critique, audit, polish, color, typography, responsive |
| Anthropic Frontend Design | `https://github.com/anthropics/skills` (skills/frontend-design) | Creative direction, aesthetic differentiation, bold design choices |
| Redesign Skill | `https://github.com/Leonxlnx/taste-skill` (skills/redesign-skill) | Upgrading existing UIs, audit checklists, fix priorities |

---

## 1. Brief Inference — Read the Room Before Anything

Before touching code, infer the design direction:

1. **Page kind** — landing, portfolio, redesign, editorial, dashboard
2. **Vibe words** — minimalist, premium, playful, brutalist, editorial, etc.
3. **Audience** — who uses this and in what context
4. **Brand constraints** — existing colors, type, photography, guidelines
5. **Quiet constraints** — accessibility-first, regulated, trust-first

**Output a one-line Design Read:** "Reading this as: <page kind> for <audience>, with a <vibe> language, leaning toward <design system or aesthetic family>."

If the brief is ambiguous, ask **one** clarifying question — never a multi-question dump.

---

## 2. Design System Selection

### When to use an official design system
If the brief reads as a specific platform, use the official package:

| Brief reads as | Use |
|---------------|-----|
| Modern SaaS, own components | shadcn/ui (`npx shadcn@latest add ...`) |
| Tailwind-based modern | Tailwind v4 utilities |
| Google/Material | `@material/web` + Material 3 tokens |
| Microsoft/enterprise | `@fluentui/react-components` |
| IBM-style B2B | `@carbon/react` |
| GitHub-style | `@primer/css` or `@primer/react-brand` |
| Accessible React foundation | `@radix-ui/themes` |

**One system per project.** Never mix systems.

### When the brief is an aesthetic, not a system
Build with native CSS + Tailwind + maintained component library. Be honest in comments about what is borrowed inspiration vs. official material.

---

## 3. Typography

- **Display headlines:** `text-4xl md:text-6xl tracking-tighter leading-none`
- **Body:** `text-base text-gray-600 leading-relaxed max-w-[65ch]`
- **Default sans:** Geist, Outfit, Cabinet Grotesk, Satoshi — NOT Inter (unless explicitly requested)
- **Serif:** VERY DISCOURAGED as default. Only when brand brief explicitly names one
- **Banned defaults:** Fraunces, Instrument_Serif
- Cap body line length at 65-75ch
- Use `text-wrap: balance` on h1-h3, `text-wrap: pretty` on prose
- Hero heading ceiling: clamp() max ≤ 6rem

---

## 4. Color

- Max 1 accent color. Saturation < 80% by default
- **No AI-purple gradients** as default
- **No pure black (#000000)** — use off-black (zinc-950)
- **No pure white (#ffffff)** — use off-white
- One palette per project — don't fluctuate warm/cool within a page
- **Color Consistency Lock:** once an accent is chosen, it's used on the WHOLE page
- **Premium-consumer palette ban:** the warm beige + brass + espresso palette is banned as default reach
- Use OKLCH for precision; tint neutrals toward the brand hue

---

## 5. Layout

- **Hero MUST fit initial viewport** — headline max 2 lines, subtext max 20 words, CTA visible without scroll
- **Hero top padding:** max `pt-24` at desktop
- **Navigation:** single line on desktop, height max 80px
- **No 3-column equal feature cards** — this is the most generic AI layout
- **Zigzag cap:** max 2 consecutive image+text splits before breaking the pattern
- **Section repetition ban:** no two sections share the same layout family
- **Eyebrow restraint:** max 1 eyebrow per 3 sections
- **Grid over Flex-Math** — use CSS Grid, not `calc(33% - 1rem)` hacks
- **Viewport stability:** use `min-h-[100dvh]`, never `h-screen`
- Container: `max-w-[1400px] mx-auto` or `max-w-7xl`

---

## 6. Motion & Animation

### The Animation Decision Framework

1. **Should it animate at all?** High-frequency actions (100+/day) → no animation
2. **Purpose?** Spatial consistency, state indication, explanation, feedback, preventing jarring changes
3. **Easing?** Entering/exiting → ease-out; moving on screen → ease-in-out; hover → ease; constant → linear
4. **Duration?** Button press: 100-160ms; tooltips: 125-200ms; dropdowns: 150-250ms; modals: 200-500ms

### Rules

- **Custom easing curves required** — built-in CSS easings are too weak: `cubic-bezier(0.23, 1, 0.32, 1)`
- **Never `ease-in` for UI** — it starts slow, feels sluggish
- **Never animate from `scale(0)`** — start from 0.95 with opacity
- **Never `window.addEventListener('scroll')`** — use Motion `useScroll()`, ScrollTrigger, IntersectionObserver, or CSS scroll-driven animations
- **Only animate `transform` and `opacity`** — skip layout and paint
- **`prefers-reduced-motion` is mandatory** — non-negotiable for `MOTION_INTENSITY > 3`
- **Motion must be motivated** — if you can't articulate why in one sentence, drop it
- **Marquee:** max one per page
- Use springs for drag, gestures, and decorative mouse interactions (`useSpring` from motion/react)
- Make popovers origin-aware (`transform-origin` from trigger, not center)
- Skip tooltip delay on subsequent hovers

### Forbidden Patterns
- `window.addEventListener("scroll", ...)` — banned
- Custom scroll progress with `window.scrollY` in React state — banned
- `requestAnimationFrame` loops that touch React state — banned
- Wrapping static content in `layout` props "for safety" — banned

---

## 7. Interactive States (ALL MANDATORY)

Every interactive element must implement:
- **Loading:** skeleton loaders matching final layout shape
- **Empty states:** composed, indicate how to populate
- **Error states:** clear, inline, contextual
- **Tactile feedback:** `-translate-y-[1px]` or `scale-[0.98]` on `:active`
- **Button contrast:** verify text readable against background (WCAG AA 4.5:1)
- **CTA wrap ban:** button text must fit one line at desktop
- **No duplicate CTA intent:** one label per intent per page
- **Form contrast:** inputs, placeholders, focus rings all pass WCAG AA

---

## 8. Dark Mode (Mandatory for Consumer-Facing)

- Design both modes from the start
- Respect `prefers-color-scheme` unless brand insists
- No pure `#000000` or `#ffffff` — use off-values
- Hierarchy parity: if a CTA pops in light, it pops in dark
- Test in both modes before shipping

---

## 9. Performance & Accessibility

- **LCP** < 2.5s — hero image must be priority/preloaded
- **INP** < 200ms — heavy work off main thread
- **CLS** < 0.1 — reserve space for images, fonts, embeds
- Hardware acceleration: `will-change: transform` only on actually-animated elements
- Grain/noise: only on fixed, pointer-events-none pseudo-elements
- Z-index: semantic scale (dropdown → sticky → modal → toast → tooltip), never arbitrary `z-[9999]`
- ARIA labels, roles, live regions for dynamic content
- Keyboard operability: logical tab order, visible focus, trapped modals
- Touch targets: ≥ 44x44px on mobile

---

## 10. AI Tells — Forbidden Patterns

Unless the brief explicitly asks for them:

- **No Inter as default font**
- **No AI-purple/blue gradients**
- **No 3-column equal feature cards**
- **No generic names** (John Doe, Jane Smith)
- **No fake round numbers** (99.99%, $100.00)
- **No startup-slop brand names** (Acme, Nexus, SmartFlow)
- **No filler verbs** (Elevate, Seamless, Unleash, Next-Gen)
- **No em-dashes** — completely banned. Use hyphen, comma, colon, or period
- **No hand-rolled SVG icons** — use library (Phosphor, HugeIcons, Radix, Tabler)
- **No div-based fake screenshots**
- **No `lucide-react` as default** — acceptable only on explicit request
- **No custom mouse cursors**
- **No section-number eyebrows** (001 · Capabilities)
- **No scroll cues** (Scroll, ↓ scroll)

---

## 11. Pre-Flight Check (Run Before Shipping)

- [ ] Brief inference declared (one-liner)?
- [ ] Design system chosen from correct category?
- [ ] ZERO em-dashes anywhere on the page?
- [ ] Page Theme Lock: ONE theme for whole page?
- [ ] Color Consistency Lock: one accent everywhere?
- [ ] Button Contrast Check: every CTA readable (WCAG AA)?
- [ ] Hero fits viewport: headline ≤ 2 lines, CTA visible without scroll?
- [ ] Navigation on ONE line at desktop, height ≤ 80px?
- [ ] No 3+ consecutive zigzag sections?
- [ ] No duplicate CTA intent?
- [ ] Eyebrow count ≤ ceil(sectionCount / 3)?
- [ ] Real images used (gen-tool / Picsum / placeholder slots)?
- [ ] Motion motivated: every animation justified in one sentence?
- [ ] Reduced motion wrapped for MOTION_INTENSITY > 3?
- [ ] Dark mode tested in both modes?
- [ ] Mobile collapse explicit?
- [ ] `min-h-[100dvh]`, never `h-screen`?
- [ ] Empty / loading / error states provided?
- [ ] Icons from allowed library only?
- [ ] No AI Tells from the forbidden list?
- [ ] Core Web Vitals plausibly hit?

---

## 12. Component Craft (from Emil Kowalski)

- **Buttons:** `transform: scale(0.97)` on `:active`
- **Popovers:** `transform-origin` from trigger, not center (modals exempt — stay centered)
- **Tooltips:** skip delay on subsequent hovers (instant with no animation)
- **CSS transitions > keyframes** for interruptible UI
- **Blur to mask transitions:** `filter: blur(2px)` during crossfade
- **`@starting-style`** for CSS-only enter animations
- **translateY(100%)** relative to element's own size (responsive)
- **Spring physics** for drag/gesture interactions (momentum + interruptibility)

---

## Self-Reflection Clause

After fixing any design bug or resolving a visual issue:
1. **Why was this missed?** — What pre-flight check or audit step was skipped?
2. **What procedural safeguard would have caught it?** — What specific check should be added to the pre-flight?
3. **Update the knowledge base** — Add the lesson to this skill's forbidden patterns or pre-flight checklist.
