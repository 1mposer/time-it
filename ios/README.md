# ⚠️ VISUAL MOCKUP — REFERENCE ONLY. DO NOT IMPLEMENT FROM THIS CODE.

This directory (`ios/`) currently holds a **Figma Make export** — a **React / Vite / Tailwind / shadcn web prototype** of the dashboard. It exists **only** as a pixel/layout reference for the visual design.

**It is NOT the app.** The app is a **native SwiftUI** iPhone app. This TypeScript/React bundle will never ship and will be deleted once the SwiftUI app exists.

## If you are the implementing agent — build the SwiftUI app, not this

- **Target:** a new SwiftUI Xcode project at **`ios/TimeIt/`** (does not exist yet — create it).
- **Build from the specs, in this order — they are authoritative, this code is not:**
  1. [`docs/issues/current/implement-spec-issue-5a-ios-core.md`](../docs/issues/current/implement-spec-issue-5a-ios-core.md) — the build shape (models, networking, views, tests).
  2. [`docs/issues/current/design-decisions-issue-5.md`](../docs/issues/current/design-decisions-issue-5.md) — shared nav/UX + the **"Mockup vs. API contract"** table you must obey.
  3. [`ios/guidelines/Guidelines.md`](guidelines/Guidelines.md) — canonical colour / typography / layout tokens.
  4. [`CLAUDE.md`](../CLAUDE.md) "API response contract" — the wire shape.

## Do NOT

- ❌ **Do NOT** run `npm install` / `pnpm install` / `vite` — this bundle is not part of the build.
- ❌ **Do NOT** port the `.tsx` files 1:1 into Swift. The layout is a guide; the structure is SwiftUI/MVVM per the specs.
- ❌ **Do NOT** trust the TypeScript types (`ActivityCard.tsx` etc.). They **predate** the current backend contract — single `condition`/`bestTime` instead of per-activity `days[]`, `"none"` instead of JSON `null`, clock hours instead of global `hours[]` indices, no `timezone`. See the "Mockup vs. API contract" table in `design-decisions-issue-5.md` for every mismatch you must **not** replicate.

## Why it's kept

It is the only *runnable* rendering of the target design — a visual fallback while the SwiftUI dashboard is built. `Guidelines.md` is the text distillation; this is the picture. Delete after the SwiftUI card + timeline exist, if at all.

---

_Original Figma export notes (historical): "Activity Dashboard Mockup", from https://www.figma.com/design/Q1wHA3hPLE7i3g6xBqEtRk/Activity-Dashboard-Mockup — `npm i` / `npm run dev` would run the web prototype. Do not do this for the app build._
