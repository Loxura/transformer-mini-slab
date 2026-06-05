# Cooking Phase 2a — macro enrichment engine

Status: **planned** (grilled 2026-06-04). Builds on the Phase 1 conveyor (`cooking/ingest/watcher.py`,
auto-imports recipes tagged `quick`/`batch`/`auto-ingest`). Phase 2a makes the growing recipe pool
**macro-accurate**; Phase 2b (deferred) turns that into a goal-based meal recommender.

## Thesis
The conveyor fills Tandoor with recipes but **zero nutrition**. Before we can recommend meals for a
goal ("1900 kcal, 180 g protein, cut"), every recipe needs trustworthy macros. So Phase 2a is a
**data-quality engine**, not a UI: clean the ingredient data, attach USDA-grounded nutrition to each
food, let Tandoor roll it up per recipe. The deck just *displays* the result. Recommendation is 2b.

## Why Tandoor-native (don't build a parallel macro store)
Tandoor 2.6.9 already has the entire nutrition model — we populate it rather than reinvent it:
- **`Food.fdc_id`** + **`Food.properties`** (per-`properties_food_amount`, default 100 g) — per-food nutrient values.
- **`Recipe.nutrition` / `food_properties`** — **roll up automatically** from food properties × ingredient
  amount × unit conversion. We never compute recipe totals ourselves; we feed the inputs.
- **`UnitConversion{base_unit, base_amount, converted_unit, converted_amount, food}`** — per-food
  gram conversions (`1 cup flour = 120 g`). This is what makes the roll-up arithmetic work.
- Endpoints confirmed live on this instance: `POST /api/property/` (write food nutrient), `POST
  /api/unit-conversion/`, `POST /api/food/{id}/merge/{target}/` (dedup), `/api/food/batch_update/`,
  and `PropertyType.fdc_id` (maps a nutrient slot to a USDA nutrient number).

Net: the deck (ws3 cooking tab, future) reads nutrition straight from Tandoor — one source of truth.

### Why our engine still owns the lookup (not Tandoor's built-ins)
Tandoor *also* ships `/api/fdc-search/`, `POST /api/food/{id}/fdc/` (USDA import) and
`/api/food/{id}/aiproperties/` (LLM estimate via a configurable AI provider). We deliberately **do not**
drive macros through those, because they're single-source: FDC-only or LLM-only, no cross-check. Our
accuracy bar is **USDA ∥ SearXNG → Gemma reconciles → confidence**, which Tandoor's endpoints can't
express. So the engine calls USDA + SearXNG + Ollama itself and **writes the reconciled result into
Tandoor**. We still set `Food.fdc_id` for provenance when USDA is the winning source.
(Live check 2026-06-04: `fdc-search` 500s — no USDA key configured — and `ai-provider` count is 0.
Both unused by us; noted only so nobody is surprised they're dormant.)

## The data-quality problem (the hard part)
The ingest parser (Tandoor's `recipe-scrapers`) mis-split many ingredient lines. On this instance:
- **507 unique Foods**, ~25 % hard junk fragments — `(chopped`, `(diced`, `/ 500g beef mince`,
  `+ 1 tbsp plain flour / all-purpose flour` — plus heavy duplication (`all purpose flour` vs
  `all-purpose flour`, `avocado` vs `avocado slices`).
- **92 Units, also polluted** — `'-'`, `'beef'`, `'carrot'`, `'burrito-sized'`, `'g/14oz'`. Food names
  leaked into the unit slot, which means those ingredient *rows* are fundamentally mis-parsed.

Matching can't run on garbage, so **cleanup is a hard prerequisite** and it **mutates the shared recipe
DB** → it is **review-gated** (propose → human approves → apply). Junk that can't be safely
auto-resolved (mis-split rows) surfaces in the review file, not silently "fixed."

## Architecture
Three decoupled pieces. SearXNG is **standalone** (also for personal/general use, independently
up/down, easy to expand) — the enricher is just a consumer.

```
  searxng/                      cooking/enrich/enrich.py            cooking/ (Tandoor)
  ┌─────────────┐   nutrition   ┌──────────────────────┐  write    ┌──────────────────┐
  │ SearXNG     │◀──search──────│  enrichment engine   │──props───▶│ Food.properties  │
  │ (LAN web UI │──json hits───▶│  - clean (gated)     │──convs───▶│ UnitConversion   │
  │  + JSON API)│               │  - match USDA∥web    │──fdc_id──▶│ Food.fdc_id      │
  └─────────────┘               │  - Gemma reconcile   │           └────────┬─────────┘
  ollama (host)                 │  - write Tandoor     │      Tandoor rolls  ▼
  gemma3n:e4b   ◀──reconcile────│  - confidence/review │      up → Recipe.nutrition
  USDA FDC API  ◀──fdc lookup───└──────────────────────┘
```

- **`searxng/`** — new top-level stack. `docker-compose.yml` + `settings.yml` with `formats: [html, json]`
  (programmatic queries need JSON), a generated `secret`, LAN-only port. Polished enough for personal use.
- **Ollama / Gemma 3n E4B** — already installed + serving (`:11434`); `ollama pull gemma3n:e4b`. RTX 3060
  + WSL GPU passthrough — fits in VRAM, fast. Engine calls Ollama directly (`/api/chat`, JSON mode).
- **USDA FoodData Central API** — free key (api.data.gov), stored at `~/.config/eww/usda-key`
  (gitignored, same pattern as `tandoor-token`). Called directly by the engine.
- **`cooking/enrich/enrich.py`** — stdlib-only Python (mirrors `watcher.py`: no pip). State + review
  files in `cooking/enrich/state/` (gitignored).

## Nutrient slots (one-time setup)
Create 6 `PropertyType`s, each mapped to its USDA nutrient number via `PropertyType.fdc_id`:

| Property | unit | USDA nutrient id |
|----------|------|------------------|
| Calories | kcal | 1008 |
| Protein  | g    | 1003 |
| Carbohydrates | g | 1005 |
| Fat      | g    | 1004 |
| Fiber    | g    | 1079 |
| Sugar    | g    | 2000 |

## Pipeline

### Pass A — cleanup (review-gated, on demand)
1. Pull all Foods + Units. Classify each: **clean**, **duplicate-of-X** (string-normalize + Gemma for
   near-dupes), **junk** (regex + Gemma: leading punctuation, embedded amounts, multi-item fragments).
2. Emit `state/cleanup-plan.json`: proposed merges (`merge food A → B` via `/api/food/{id}/merge/{target}/`),
   renames, deletes, and **flagged mis-parsed rows** (junk in the *unit* slot → can't auto-fix the row).
3. **Human reviews the plan.** `enrich.py --apply-cleanup` then executes the approved actions.
   (`pg_dump` reminder in README before first apply — merges rewrite recipes.)

### Pass B — match + enrich (automatic; additive/reversible, so no gate)
For each **clean, unmatched** Food (dedup'd — ~finite set, not per-ingredient-line):
1. **In parallel**: USDA FDC search (`/foods/search`, dataType `SR Legacy,Foundation,Survey`) **and**
   SearXNG nutrition search (`<food> nutrition facts per 100g`).
2. **Gemma reconciles** both into per-100 g macros for the 6 nutrients + a `confidence` 0–1 + `source`
   (`usda` / `web` / `estimate`) + agreement flag. JSON-mode, schema-checked.
3. If `confidence ≥ τ` and sources agree → **write**: `POST /api/property/` for each nutrient on the
   food (basis `properties_food_amount=100`, `properties_food_unit=g`); set `Food.fdc_id` when USDA won.
   Else → append to `state/review-macros.json` (non-blocking; optional later human fix), skip writing.
4. **Unit conversions**: enumerate every `(food, unit)` pair actually used across recipe ingredients
   (finite). For each, ensure a `UnitConversion` to grams exists (USDA `foodPortions` first, else
   Gemma/density estimate). Missing conversions are what make the roll-up silently undercount, so this
   coverage step is mandatory. Junk units → already flagged in Pass A.
5. Tandoor rolls `Recipe.nutrition` automatically once food props + conversions exist. Spot-check a
   few recipes' computed nutrition against the source pages' stated nutrition as a sanity gate.

### Cadence
- **Backfill**: one-shot over all 507 foods (after the one-time cleanup approval).
- **Incremental**: cron after the watcher's `*/30` run — Pass B only, over foods new since last run.
  Cleanup (Pass A) stays on-demand because it's gated. Low-confidence items just accumulate in
  `review-macros.json` for when you feel like triaging.

## State / review files (gitignored, mirrors watcher pattern)
- `state/enriched.json` — `food_id → {macros, source, confidence, fdc_id, ts}` (skip-set + provenance).
- `state/cleanup-plan.json` — proposed cleanup actions awaiting approval.
- `state/review-macros.json` — low-confidence / disagreement foods for optional human fix.

## CLI (planned)
```sh
cooking/enrich/enrich.py --setup-properties        # create the 6 PropertyTypes (one-time)
cooking/enrich/enrich.py --plan-cleanup            # write cleanup-plan.json (no mutation)
cooking/enrich/enrich.py --apply-cleanup           # execute approved merges/deletes/renames
cooking/enrich/enrich.py --backfill                # Pass B over all foods
cooking/enrich/enrich.py --food "chicken breast"   # enrich one food (debug)
cooking/enrich/enrich.py                           # incremental: new foods only (cron)
cooking/enrich/enrich.py --dry-run -v              # match+reconcile, write nothing
```

## Out of scope (Phase 2b)
Goal model (per-user kcal/protein/diet targets), Gemma meal-plan assembly from the macro-tagged pool,
SearXNG-driven discovery of *new* recipes to hit targets, and the deck's ws3 cooking-tab UI beyond a
plain macro display. SearXNG stood up now is reused there.

## Open risks
- **Reconcile honesty** — Gemma must cite source and not average a USDA value with a hallucinated web
  number. Mitigation: schema forces `source` + `confidence`; disagreement routes to review, never silently written.
- **Conversion coverage** — a missing `(food, unit)` conversion undercounts silently. Mitigation: the
  enumerate-pairs step is mandatory and logged; recipes with unconvertible (junk) units are flagged, not zeroed.
- **Mis-parsed rows** — merging a junk *food* doesn't repair a row whose *unit* swallowed the food name.
  Such rows are flagged for manual recipe edit; their recipes get partial macros until fixed.
- **USDA match drift** — "chicken" → which cut? Gemma disambiguation + confidence gate; ambiguous → review.
```
