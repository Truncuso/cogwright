---
title: "Prototype — UI branch discipline"
---

# UI branch

1. **State the question and pick N** — default **3** variations, cap 5.
2. **Prefer embedding in a real page** when a host app exists: render the
   variations on the existing route behind a `?variant=` search param with a
   small floating switcher (arrows cycle, URL-stable, hidden outside dev). A
   variant judged against the real header, data, and density answers the
   question; a variant in a vacuum always looks fine. Fall back to a clearly
   named standalone route or static mock only when no host page exists.
3. **Variations must be structurally different** — different layout,
   information hierarchy, primary affordance. Three re-colored card grids are
   one variation. If two drafts converge, redo one with an explicit "do not
   use <the shared structure>" constraint.
4. **Read-only** — variants never wire to real mutations; stub them.
5. **Write UI.md**: the question; per-variation one-liner + snippet or
   screenshot; the recommended variation and why (often "header from B,
   sidebar from C" — record the recombination); what to carry into the real
   implementation.
