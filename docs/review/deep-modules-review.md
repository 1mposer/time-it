# Deep-Modules Architecture Review — Charter & Report Format

A reusable brief for an architecture review of this repo. It hunts **depth**, not bugs: where a shallow module can become a deep one, where complexity leaks across a seam, where the interface is as wide as the implementation. Run it before/after each phase — the green test suite proves correctness, this proves design.

Self-contained: no external skills required. The vocabulary it grades against is in §5.

---

## 1. Stance

- **Design, not correctness.** The suite is green; do **not** re-audit tests, report bugs, flag lint/style, or propose features. Look only at module shape.
- **Aim:** depth, in service of two things —
  - **testability** — a module testable through one narrow interface, not through the way N callers happen to wire it.
  - **AI-navigability** — a cold agent (or human) can find the right module from its name + interface alone; boundaries are discoverable; names match `docs/CONTEXT.md`.
- **Read first:** `CLAUDE.md` → `docs/CONTEXT.md` → `docs/adr/`. Use the project's domain terms (Window, bucket, night-stitch, …) and the architectural terms in §5. Don't invent vocabulary.
- **Scope:** the whole repo is fair game, but weight the recently-changed surface (the modules a phase touched). **Independent discovery first** — find friction on your own *before* reading the author's priors in §3, then reconcile.

## 2. How to assess — a lens, not a checklist

Explore organically; note where you feel friction. These questions orient, they don't constrain:

- Where was a **pure function extracted for testability**, but the real bugs live in *how it's called* — the logic and its callers sit far apart (no **locality**)?
- Where do **tightly-coupled modules leak across their seam** — one module reaching into another's internals, or an implicit contract that fails silently?
- Which parts are **untested or hard to test through their current interface** — where a test must reconstruct caller wiring, or reach for a **mock** because there's no seam to substitute a local fake?
- Where is a module **shallow** — its interface nearly as wide as its implementation (thin wrappers, pass-through layers)?

**The deletion test** (apply to anything you suspect is shallow): *would deleting/inlining it concentrate complexity, or just move it?* "Concentrates" is the signal — that's a deepening candidate. "Just moves it" is not.

**Volume:** the **3–6 highest-leverage** candidates. Not an exhaustive list of every theoretical refactor.

**ADR conflicts:** if a candidate contradicts an [ADR](../adr/), surface it **only** when the friction is real enough to warrant reopening the ADR. Mark it in the card (amber callout: "contradicts ADR-000X — worth reopening because…"). Don't enumerate everything the ADRs forbid.

## 3. Current run — VOLATILE (overwrite each phase)

> Replace this whole section per run. Everything above and below is durable.

**No active run.** (Last run: pre-#5a, June 2026 — its priors are resolved history; report in `docs/review/out/` if kept. The 2026-06-30 run's three internal-seam deepening candidates remain advisory, not blockers.) Write a fresh leverage-moment + priors block here when starting a run.

## 4. Output — a self-contained HTML report

Write one HTML file to `docs/review/out/<YYYY-MM-DD>-deep-modules.html` (durable, **not** a temp dir — this is a deliverable kept across phases). Styling via **Tailwind CDN**, graph diagrams via **Mermaid CDN**. ("Self-contained" = single file; it still needs network to render the CDNs.)

**Substance over polish.** A candidate with a sharp problem/solution beats a pretty diagram. Never let visualization eat the analysis. **No animations** — static before/after carries the point.

### Scaffold

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Architecture review — time-it</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
      mermaid.initialize({ startOnLoad: true, theme: "neutral", securityLevel: "loose" });
    </script>
    <style>
      .seam { stroke-dasharray: 4 4; }     /* dashed seam lines */
      .leak { stroke: #dc2626; }           /* red leakage edges */
      .deep { background: linear-gradient(135deg, #0f172a, #1e293b); } /* deep module */
    </style>
  </head>
  <body class="bg-stone-50 text-slate-900 font-sans">
    <main class="max-w-5xl mx-auto px-6 py-12 space-y-12">
      <header>...</header>
      <section id="candidates" class="space-y-10">...</section>
      <section id="top-recommendation">...</section>
    </main>
  </body>
</html>
```

### Header

Repo name, date, and a compact legend: solid box = module, dashed line = seam, red arrow = leakage, thick dark box = deep module. No intro paragraph — straight into the candidates.

### Candidate card

The diagram carries the weight. Prose is sparse and uses §5 terms without ceremony. **No paragraphs of explanation — if a diagram needs a paragraph to be understood, redraw the diagram.** One `<article>` per candidate:

- **Title** — short, names the deepening ("Make `evaluateAll` own its tagging").
- **Strength badge** — `Strong` (emerald) · `Worth exploring` (amber) · `Speculative` (slate).
  - *Strong* = passes the deletion test, clear locality or leverage win, bounded blast radius.
  - *Worth exploring* = real friction, but the fix or its payoff is uncertain.
  - *Speculative* = a hunch worth recording, not yet justified.
- **Files** — monospaced list (`font-mono text-sm`).
- **Before / After diagram** — the centrepiece, two columns side by side. Patterns below.
- **Problem** — one sentence. What hurts.
- **Solution** — one sentence. What changes.
- **Wins** — bullets, ≤6 words, named in §5 terms: "locality: bugs concentrate in one module", "leverage: one interface, N call sites", "interface shrinks; implementation absorbs the wrappers". One bullet states the **deletion-test** result ("delete: concentrates complexity").
- **ADR callout** (if applicable) — one line, amber-tinted box.

### Diagram patterns

Pick the one that fits; mix them — variety is signal, not decoration.

- **Mermaid graph** (workhorse for dependencies / call flow). "X calls Y calls Z, look at the mess." `classDef` to colour leakage edges red and the deep module dark. Sequence diagrams for "before: 6 round-trips; after: 1." Wrap in a Tailwind card so it doesn't feel parachuted in.

  ```html
  <div class="rounded-lg border border-slate-200 bg-white p-4">
    <pre class="mermaid">
      flowchart LR
        GW[getWeather] -- tags localDay/localHour --> H[(hours)]
        H --> EA[evaluateAll]
        EA -.silent precondition.-> H
        classDef leak stroke:#dc2626,stroke-width:2px;
        class EA,H leak
    </pre>
  </div>
  ```

- **Hand-built boxes-and-arrows** (when Mermaid's layout fights you). Modules as bordered `<div>`s; arrows as inline SVG `<line>`/`<path>` over a relative container. Reach for this when the "after" should read as one thick-bordered deep module with greyed-out internals — Mermaid won't carry that weight.
- **Cross-section** (layered shallowness). Stacked horizontal bands (`h-12 border-l-4`): before — 6 thin layers each doing nothing; after — 1 thick band with the consolidated responsibility.
- **Mass diagram** (interface-as-wide-as-implementation — *the* depth visual). Two rectangles per module: interface surface vs implementation. Before — interface nearly as tall as implementation (shallow). After — short interface, tall implementation (deep).
- **Call-graph collapse** (static). Before — a tree of nested call boxes; after — the same tree collapsed into one box with the now-internal calls faded inside.

### Style

- Editorial, not corporate-dashboard. Generous whitespace; `font-serif` headings work with stone/slate.
- Colour sparingly: one accent (emerald or indigo) + red for leakage + amber for warnings.
- Diagrams ~320px tall so before/after sits side by side without scrolling.
- Module labels inside diagrams: `text-xs uppercase tracking-wider` — schematic, not UI.
- Only scripts are the two CDNs. Otherwise static — no app code, no interactivity beyond Mermaid's own rendering.

### Top recommendation

One larger card: candidate name, one sentence on why-first, anchor link to its card. That's it.

## 5. Vocabulary (self-contained — use exactly these)

Architectural nouns/verbs — **use exactly:** module, interface, implementation, depth, deep, shallow, seam, adapter, leverage, locality.

**Never substitute:** component / service / unit (for module) · API / signature (for interface) · boundary (for seam) · layer / wrapper (for module, when you mean module).

Domain nouns — from `docs/CONTEXT.md`, used as defined there: Pursuit, Activity, Threshold, Rating, Window, Index, Forecast, night-stitch, bucket, Lite/Pro, Display metrics. A card names the architectural shape **and** the domain thing: "the **night-stitch** branch makes `evaluateAll` **shallow** — the tagging **seam** leaks."

**Phrasings that fit:**

- "`evaluateAll` is shallow — interface nearly matches the implementation."
- "Tagging leaks across the seam."
- "Deepen: one interface, one place to test."
- "Two adapters justify the seam: Meteosource in prod, in-memory in tests."

**Wins bullets** name the gain in the terms above: *"locality: bugs concentrate in one module"*, *"leverage: one interface, N call sites"*, *"interface shrinks; implementation absorbs the wrappers"*. Don't write *"easier to maintain"* or *"cleaner code"* — those don't earn their place.

No hedging, no throat-clearing, no "it's worth noting that…". If a sentence could be a bullet, make it a bullet. If a bullet could be cut, cut it.
