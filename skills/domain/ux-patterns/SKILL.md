---
name: ux-patterns
description: "UX interaction patterns, state management, accessibility compliance, and usability heuristics for UI work. Triggered when designing user flows, reviewing UI for completeness, or verifying that all interactive states are handled. Covers forms, navigation, modals, responsive behaviour, and error handling."
---

# UX Patterns — Interaction Design & State Management

## Purpose

Ensure every UI ships with complete state coverage, proper accessibility, and coherent interaction patterns. This skill prevents the common failure mode where only the "happy path" is implemented and all edge cases, error states, loading states, and accessibility are afterthoughts.

## When to Trigger

- Designing or reviewing user flows
- Implementing interactive components (forms, modals, navigation, drag interactions)
- Verifying UI completeness in Phase C
- Any time a component handles user input or shows dynamic data

## Sources

| Source | Repository | Focus |
|--------|-----------|-------|
| Impeccable | `https://github.com/pbakaus/impeccable` | UX critique, interaction design, harden, onboard, edge cases |
| Redesign Skill | `https://github.com/Leonxlnx/taste-skill` (skills/redesign-skill) | State completeness audit, interactivity checks |
| Taste Skill | `https://github.com/Leonxlnx/taste-skill` | Interactive states, form patterns, content density |
| Emil Kowalski Design Eng | `https://github.com/emilkowalski/skill` | Gesture interactions, drag patterns, momentum, toast principles |

---

## 1. State Completeness Matrix

Every interactive element MUST implement applicable states. "It works in the happy path" is not shipping-ready.

### Component States

| State | When | Implementation |
|-------|------|---------------|
| **Default** | Initial populated render | Standard styling |
| **Empty** | No data available | Composed view with guidance on how to populate; never a blank screen |
| **Loading** | Data being fetched | Skeleton loaders matching final layout shape; no generic spinners |
| **Error** | Operation failed | Inline contextual message with actionable recovery; not just a toast |
| **Partial** | Some data loaded, some failed | Graceful degradation; show what loaded, indicate what failed |
| **Disabled** | Action not available | Reduced opacity + cursor change + tooltip explaining why |
| **Hover** | Pointer over element | Appropriate visual feedback (desktop only via `@media (hover: hover)`) |
| **Active/Pressed** | Element being clicked/tapped | Physical feedback: `scale(0.97)` or `translateY(1px)` |
| **Focused** | Keyboard focus | High-contrast visible ring; never `outline: none` without replacement |
| **Selected** | Item chosen from set | Clear differentiation from non-selected siblings |
| **Success** | Action completed | Confirmation + guidance on next action |
| **Offline** | Network unavailable | Cached data display + offline indicator |

### Page-Level States

| State | Implementation |
|-------|---------------|
| **First visit** | Onboarding guidance, feature highlights |
| **Returning user** | Remembered preferences, recent activity |
| **Logged out** | Appropriate gating, clear login path |
| **Permissions error** | Explain what's restricted and how to gain access |
| **404 / Not found** | Helpful branded page with navigation options |
| **Maintenance** | Clear timeline, alternative contact |

---

## 2. Form UX Patterns

### Rules (non-negotiable)

- **Label ABOVE input.** Always. Never inside (placeholder-as-label banned).
- **Helper text** optional but present in markup.
- **Error text BELOW input** — inline, not in a distant toast.
- **Standard gap:** `gap-2` for input blocks.
- **No placeholder-as-label.** Ever.
- **Validation:** inline as user moves focus, not only on submit.
- **Submit button:** disabled until minimum valid state, or always enabled with clear error feedback.
- **Multi-step:** progress indicator, ability to go back, don't lose entered data.

### Error Message Quality

| Bad | Good | Why |
|-----|------|-----|
| "Invalid input" | "Email must include @ and a domain (e.g. name@company.com)" | Specific fix |
| "Error" | "We couldn't save your changes. Check your connection and try again." | Actionable |
| "Oops!" | "This email is already registered. Sign in instead?" | Next step |
| "Required" | "Your name is needed to personalise your account" | Context |

---

## 3. Navigation Patterns

- **Current location** always indicated (active state on nav item)
- **No dead ends** — every page has a way back
- **Breadcrumbs** for deep hierarchies (> 2 levels)
- **Consistent structure** — same nav on every page unless justified
- **Mobile nav:** hamburger or bottom tabs; never a desktop nav crammed into mobile
- **Skip-to-content link** — essential for keyboard users
- **Focus management on route change** — move focus to main content or announce to screen reader

---

## 4. Modal & Dialog Patterns

- **Focus trap** — Tab cycles within modal; cannot escape to background
- **Focus return** — On close, return focus to the trigger element
- **Escape to close** — Always. Non-negotiable for modals.
- **Backdrop click** — Closes non-critical modals; confirmation dialogs require explicit action
- **Scroll lock** — Body scroll disabled while modal open
- **ARIA:** `role="dialog"`, `aria-modal="true"`, `aria-labelledby` pointing to heading
- **Prefer alternatives:** inline editing, slide-over panels, expandable sections for simple actions

---

## 5. Loading & Transitions

- **Skeleton loaders** over spinners — match the shape of the content that will appear
- **Optimistic updates** — show the result immediately, revert on failure
- **Progress indicators** for operations > 2 seconds
- **Stagger entry** — items cascade in with slight delays (30-80ms between items)
- **No content flash** — use `@starting-style` or mount-state pattern to animate entry
- **Perceived performance:** fast-spinning indicators > slow ones; `ease-out` at 200ms feels faster than `ease-in`

---

## 6. Responsive Behaviour

### Breakpoint Strategy

| Breakpoint | Strategy |
|-----------|----------|
| < 640px (mobile) | Single column, full-width inputs, bottom-sheet instead of modals, touch-friendly |
| 640-768px (tablet portrait) | 2-column where appropriate, collapsible sidebar |
| 768-1024px (tablet landscape) | Adapted grid, consider showing more context |
| > 1024px (desktop) | Full layout, hover states active, keyboard shortcuts |

### Rules

- **Mobile-first** — start with mobile, enhance upward
- **No horizontal scroll** at any breakpoint (carousels and galleries are exceptions)
- **Touch targets** ≥ 44x44px on mobile
- **No hover-dependent functionality** on mobile — everything accessible via tap
- **Explicit collapse rules** per section — "Tailwind handles it" is not a collapse strategy

---

## 7. Accessibility (Non-Negotiable)

### WCAG AA Compliance

| Requirement | Implementation |
|------------|---------------|
| Colour contrast | 4.5:1 for body text, 3:1 for large text (≥18px or bold ≥14px) |
| Keyboard operability | All interactive elements reachable and operable via keyboard |
| Focus visibility | Clear, high-contrast focus indicator on all focusable elements |
| Screen reader | Meaningful labels, roles, states communicated via ARIA |
| Motion sensitivity | `prefers-reduced-motion` respected; no seizure-inducing content |
| Touch targets | ≥ 44x44px (WCAG 2.2 Target Size) |
| Text resize | Content usable at 200% zoom |
| Language | `lang` attribute on `<html>`; `lang` changes marked on inline foreign text |

### Common ARIA Patterns

| Component | ARIA Pattern |
|-----------|-------------|
| Modal | `role="dialog"`, `aria-modal="true"`, `aria-labelledby` |
| Tab panel | `role="tablist"` / `role="tab"` / `role="tabpanel"`, `aria-selected` |
| Accordion | `aria-expanded`, `aria-controls` |
| Live content | `aria-live="polite"` for non-urgent, `"assertive"` for errors |
| Toggle | `aria-pressed` or `aria-checked` |
| Navigation | `<nav>` with `aria-label` if multiple navs on page |

---

## 8. Gesture & Drag Interactions

- **Momentum-based dismissal:** velocity > 0.11 = dismiss, regardless of distance
- **Damping at boundaries:** the more dragged past boundary, the less it moves
- **Pointer capture:** set once dragging starts to maintain even if pointer leaves element
- **Multi-touch protection:** ignore additional touch points after drag begins
- **Friction instead of hard stops:** allow dragging past limits with increasing resistance
- **Spring physics for release:** elements settle naturally, don't snap

---

## 9. Content Strategy for UI

- **No generic placeholder names** — use diverse, realistic names
- **No fake round numbers** — use organic data (47.2%, not 50%)
- **No Lorem Ipsum** — write real draft copy
- **No "Oops!" error messages** — be direct and helpful
- **No passive voice in UI copy** — active verbs ("We couldn't save" not "Changes were not saved")
- **Button labels:** verb + object ("Save changes" not "OK", "Delete project" not "Yes")
- **Link text:** standalone meaning ("View pricing plans" not "Click here")
- **One copy register per page** — don't mix technical and marketing voice

---

## 10. Redesign Protocol

When upgrading an existing UI:

1. **Audit first** — document current state (brand tokens, IA, patterns to preserve/retire)
2. **Preservation rules** — don't change IA unless asked; preserve copy voice; honour accessibility wins
3. **Priority order:** font swap → colour cleanup → hover/active states → layout → components → states → polish
4. **Never break existing analytics** — don't rename tracked elements
5. **SEO migration** — preserve URLs, meta, structured data

---

## Self-Reflection Clause

After any UX bug or state-completeness failure:
1. **Which state was missing from the spec?** — Was it not considered in Phase A, or dropped during implementation?
2. **What checklist item would have caught it?** — Update the State Completeness Matrix if a new state type is discovered.
3. **Update the knowledge base** — Add the pattern to this skill or flag it for the UX Engineer's Phase C checklist.
