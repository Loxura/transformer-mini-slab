# Macro-enrichment engine (Cooking Phase 2a)

Makes the auto-ingested recipe pool **macro-accurate**. The conveyor (`../ingest/watcher.py`) fills
Tandoor with recipes but **zero nutrition**; this engine attaches USDA-grounded macros to each *Food*
and lets Tandoor roll them up per recipe automatically. It's a **data-quality engine, not a UI** — the
deck just displays the result later.

Plan + rationale: `../../docs/proposals/2026-06-04-cooking-phase2-smart-finder-plan.md`.

```
 SearXNG (../searxng)  ─web snippets─┐
 USDA FoodData Central ─per-100g─────┤→  Ollama/Gemma reconciles → confidence/source/agreement
                                     │        │ high-conf + agree              │ else
                                     │        ▼                                ▼
                                     │   PATCH Food.properties (basis 100 g)   state/review-macros.json
                                     │   + Food.fdc_id + UnitConversion→g      (optional later human fix)
                                     └→  Tandoor rolls up → Recipe.food_properties
```

## Why Tandoor-native
We populate Tandoor's existing nutrition model instead of building a parallel store: per-food
`Property` values (basis 100 g), `Food.fdc_id` for provenance, and per-food `UnitConversion`s to grams
so the roll-up arithmetic works. Tandoor then computes the per-recipe roll-up itself — we never sum
macros ourselves. We also don't drive macros through Tandoor's single-source `fdc`/`aiproperties`
endpoints: our bar is **USDA ∥ web → Gemma reconciles → confidence**, which those can't express.

> **Where the roll-up shows up:** read `Recipe.food_properties` (in the recipe detail), NOT
> `Recipe.nutrition`. `nutrition` is Tandoor's slot for a *manually entered* nutrition label and stays
> `null`. `food_properties` is the **computed** roll-up: per nutrient, a `food_values` map giving each
> ingredient food's contribution (or a `missing_conversion` marker when a `(food,unit)→g` conversion is
> absent — that food then contributes nothing, silently undercounting). The deck reads `food_properties`.

## Prerequisites (one-time)
1. **SearXNG up** — `cd ../../searxng && docker compose up -d` (the JSON API; see its README).
2. **Ollama + model** — Ollama already serves on `:11434`; pull the reconciler model:
   ```sh
   ollama pull gemma3n:e4b
   ```
   Override the model with `ENRICH_MODEL=<name>` or `~/.config/eww/ollama-model` if you prefer another.
3. **USDA key** *(optional but recommended)* — free key from <https://fdc.nal.usda.gov/api-key-signup.html>,
   then `printf '%s' '<key>' > ~/.config/eww/usda-key` (gitignored, same pattern as `tandoor-token`).
   Without it, USDA is skipped and reconciliation runs **web-only** (lower confidence → more review items).
4. **Nutrient slots** — create the 6 `PropertyType`s mapped to USDA nutrient numbers:
   ```sh
   ./enrich.py --setup-properties
   ```

Config read from `~/.config/eww/`: `tandoor-url`, `tandoor-token` (required, shared with the watcher),
plus optional `usda-key`, `searxng-url` (default `http://localhost:8091`), `ollama-url`
(default `http://localhost:11434`), `ollama-model` (default `gemma3n:e4b`).

## Pass A — cleanup (review-GATED — it mutates the shared recipe DB)
The scraper mis-split many ingredient lines (`(155g,`, `+ 1 tbsp plain flour / all-purpose flour`) and
leaked food names into the unit slot (`g/14oz`, `beef`). Matching can't run on garbage, so cleanup is a
prerequisite — and because merges **rewrite recipes**, it is propose → human approves → apply.

```sh
./enrich.py --plan-cleanup     # writes state/cleanup-plan.json — NO mutation. Open and review it.
# back up first (merges rewrite recipes): see ../README.md "Back up before version bumps"
./enrich.py --apply-cleanup    # executes ONLY: dedupe merges + deletes of UNUSED junk foods
```
What the plan contains:
- **`merges`** — duplicate foods normalized to one canonical (`all purpose flour` → `all-purpose flour`).
  Auto-applied.
- **`junk_foods`** — fragments. `action: delete` only when the food is used in **zero** ingredient rows;
  otherwise `action: flag` — the row is mis-parsed and needs a manual recipe edit (we never silently
  break a recipe). On the current DB **every junk food is in-use**, so apply deletes none — all are flagged.
- **`junk_units`** — food/amount text leaked into the unit slot. Always flagged (lists the affected
  ingredient ids); fix those recipes by hand.

## Pass B — match + enrich (additive/reversible → no gate)
For each clean, unmatched Food: USDA lookup **and** SearXNG snippets → Gemma reconciles to per-100 g
macros + `confidence`/`source`/`agreement` → if `confidence ≥ τ` **and** sources agree, write
`Food.properties` (basis 100 g), set `Food.fdc_id` when USDA won, and ensure `(food,unit)→g`
conversions. Otherwise the food goes to `review-macros.json` (non-blocking).

```sh
./enrich.py --backfill              # all clean foods (after cleanup approval)
./enrich.py                         # incremental: foods not in enriched.json yet (cron)
./enrich.py --food "chicken breast" # one food, debug
./enrich.py --dry-run -v            # reconcile + print, write nothing
./enrich.py --backfill --tau 0.8    # stricter write threshold (default 0.7)
./enrich.py --backfill --limit 5    # cap foods processed (testing)
```

**Conversion coverage matters:** a missing `(food, unit)→g` conversion makes Tandoor silently
*undercount*. The engine enumerates every `(food, unit)` pair actually used across recipes and fills
grams from USDA `foodPortions` first, then a **Gemma density estimate** (`1 cup flour ≈ 120 g`); only
units neither can resolve are recorded per food in `enriched.json` (`missing_conversions`) and logged —
fix those by adding a `UnitConversion` by hand. Junk units are already flagged in Pass A.

After a backfill, **spot-check** a few recipes' computed `Recipe.food_properties` against the source
pages' stated nutrition as a sanity gate.

## Cadence
- **Backfill** once over all foods after the cleanup approval.
- **Incremental** via cron, after the watcher's `*/30` run — Pass B over foods new since last run.
  Cleanup (Pass A) stays on-demand because it's gated. Low-confidence items accumulate in
  `review-macros.json` for whenever you feel like triaging.

## State (gitignored, mirrors the watcher)
- `state/enriched.json` — `food_id → {macros, source, confidence, fdc_id, missing_conversions, ts}`
  (skip-set + provenance).
- `state/cleanup-plan.json` — proposed cleanup actions awaiting approval.
- `state/review-macros.json` — low-confidence / disagreement foods for optional human fix.

## Notes / honesty rails
- **Reconcile is schema-forced** (`source` + `confidence` + `agreement` required); disagreement routes
  to review, never silently written. Gemma is told not to average a real value with an uncertain one.
- **Reversible:** Pass B only adds properties/conversions/`fdc_id`. To undo a food, clear its
  `properties` (`PATCH /api/food/{id}/ {"properties": []}`) and delete its `UnitConversion`s.
- Stdlib-only, like the watcher — no `pip install`.
