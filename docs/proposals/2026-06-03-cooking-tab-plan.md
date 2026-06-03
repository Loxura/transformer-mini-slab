# Cooking tab — planning doc

**Date:** 2026-06-03 (updated same day after research pass + design discussion)
**Status:** Discussion / pre-spec. Thesis and architecture now settled; ingest sources + a few
specifics still open. Nothing built.
**Context:** New feature for the Transformer Mini deck (the always-on sway/eww touch "deck" on a
2016 ASUS T102HA tablet; mpd music UI, neo-brutalist look, paginated — no touch-scroll). Repo
`/mnt/c/Users/ayub/Desktop/transformer-mini-slab`, mirrored to the tablet `minideck@192.168.0.44`.
The "mainframe" = the user's home server (same box that runs the music acquisition stack).

---

## The thesis (this is the whole point — read first)

**This is a takeout interceptor, not a "what can I make" app.**

The real failure mode: long day → already sat down, joint rolled, low energy → *deciding* what to
cook is the one thing the user can't face → UberEats wins by default. The entire design goal is to
**make the decision already-made before the low-energy moment is ever reached.** At tired-o'clock
all that's left is execute: the deck says "tonight: reheat the chili" or "tonight: cook this 25-min
thing," one tap to steps. No choosing.

Everything below follows from that. The earlier framing ("checklist of what's in the house" +
"what can I make from what I have") was the *wrong* centerpiece — see "What we deliberately cut."

---

## The loop we're actually building

1. **Plan** (on a high-energy moment — weekend/couch, NOT a tired weeknight): pick recipes from a
   **shortlist** into the week's meal plan. Shortlist is split into two buckets (see "roles").
2. **Auto shopping list** generated from the plan → user shops (user already shops from a list).
3. **Prep day**: batch recipes get cooked big; deck Cook-mode walks the steps.
4. **Weeknights**: deck shows tonight's assignment — *reheat* a batch portion, or *cook* a quick
   fresh one. One tap → steps. Zero decision. This is the moment that beats takeout.

**Weeknight model = MIX** (user's call): a couple of **batch-and-reheat** anchors for tired nights
(reheat beats takeout on *effort*, not just decision) + **quick-fresh** meals for energy nights.

**Planning style = pick from a shortlist** (user's call): system surfaces good candidates, user
actively chooses each slot. Not fully hands-off, not build-from-scratch.

---

## Architecture (settled)

### Split: thin client on the deck, brains on the mainframe
Same split as the music stack. The Atom only renders + takes taps; the server stores, scrapes,
classifies, plans. Deck talks to the mainframe with `curl` against `http://mainframe:<port>/api/...`
+ an API token — same pattern as the existing `mpc` / `bt-ctl` / `cover-palette` scripts.

### Backend: Tandoor Recipes (self-hosted). Confirmed by research pass.
Chosen over Mealie/roll-your-own. The meal-prep thesis makes Tandoor the clear fit: meal planning is
a first-class feature that **auto-feeds the shopping list**, ingredients are structured data, and it
ships its own web planner UI we can reuse.

### Planning happens in Tandoor's WEB UI (phone/laptop), NOT on the deck.
Key decision. "Pick from a shortlist and assign to days" is a scroll-heavy, fiddly interaction the
deck (no-scroll, big-button, paginated) is *bad* at — and **Tandoor already has a planner that does
exactly this.** So we don't build a deck planner. The conveyor belt's job is to make Tandoor's
recipe list *good* (tagged by role, deduped); the user plans on their phone on the couch.

### The deck is a (mostly read-only) EXECUTION dashboard.
This collapses the deck client from "three interactive surfaces" to basically **"render tonight's
plan + Cook mode"** — a fraction of the original scope, and exactly what the deck is good at.
- Reads the meal plan via the Tandoor API; shows tonight's assignment (cook vs reheat).
- Cook mode: step-through one recipe, big text, swipe between steps, tick ingredients — reuse the
  proven pagination machinery (cached list + page-state files + prev/next), never touch-scroll.
- Optional later: a glanceable week view.

### The conveyor belt is where the real work now lives (mainframe watcher)
Two jobs, both at ingest time:
1. **Ingest** — poll sources (food-blog RSS / a subreddit / specific sites) → extract recipe URLs →
   dedupe against the watcher's own seen-set → **`POST /api/recipe-from-source/`** to Tandoor, which
   scrapes + creates the recipe itself. (Tandoor internally uses the `recipe-scrapers` library with
   the JSON-LD wild-mode fallback on — so we do NOT build our own scraper; the watcher just feeds
   URLs, like an *arr feeds release URLs to a downloader.)
2. **Classify role** — tag each recipe **batch** vs **quick** so the planner's shortlist can split
   into two buckets. Start with cheap heuristics: `total_time` (recipe-scrapers provides it) → quick
   if under ~30 min; high servings / keywords ("meal prep", "freezer", "batch") / the source it came
   from → batch. Write the tag into Tandoor.

---

## What we deliberately cut (and why)

- **"What can I make from what I have"** — CUT from the centerpiece. If you shop *for* a plan, you
  never ask this question; you bought exactly what the plan needs. (Tandoor *does* support it
  natively via `?makenow=` + `?foods_and/or=` if we ever want it — see API notes — but it's not core.)
- **Pantry / on-hand inventory tracking** — DEMOTED to "someday," not v1. The hard, app-killing
  problem of keeping a pantry current only exists if decisions depend on live inventory. They don't:
  decisions are pre-made and shopped-for. So the whole pantry-data-entry rabbit hole evaporates.
- **Pantry-reconcile-at-decision-time, depletion tracking, makenow tolerance** — all explored, all
  shelved. Recorded here so we don't re-derive them: they solved a problem the thesis removes.

If the thesis ever changes back toward improvisation, the cut work is recoverable from git history
of this doc.

---

## Research-pass findings (verified 2026-06-03, against Tandoor source + primary docs)

### Tandoor REST API
- **Auth:** `Authorization: Bearer <token>` (Tandoor 2.x uses Django OAuth Toolkit). NOTE: old blog
  snippets show `Token <token>` — that's pre-2.x; use **Bearer**, fall back to `Token` only if it
  401s. Generate a **read-write** scoped token in Settings → API. Everything is **space-scoped**
  (token's user must belong to a space).
- **OpenAPI/docs on the instance:** `/openapi/`, Swagger at `/docs/swagger/`, ReDoc at `/docs/api/`.
- **Recipes/steps:** `GET /api/recipe/` (list, lighter serializer) and `GET /api/recipe/{id}/`
  (detail — fetch this for full nested `steps[].ingredients[].{food,unit,amount}`).
- **Meal plan:** `GET/POST /api/meal-plan/`, `/api/meal-type/`. Plan a recipe onto multiple days for
  reheat nights. Meal plan → shopping list is a triggered action, not automatic-on-read.
- **Shopping list:** `/api/shopping-list-entry/` (granular: `food`, `unit`, `amount`, `checked`).
  Gotcha: adding a brand-new food via API can 500 (issue #4418) — prefer existing food IDs.
- **URL import:** `POST /api/recipe-from-source/` (uses recipe-scrapers under the hood). VERIFY on
  our build whether it *creates* directly or returns parsed data for a second create call (changed
  across the importer refactor).
- **Pagination:** DRF page-number style `?page=N&page_size=M`, envelope `{count,next,previous,results}`.
  Recipes default page_size 25 (max 100); foods 50 (max 200). Walk `next` until null.
- **"What can I make" (if ever wanted):** native — `?makenow=1` (uses on-hand foods), `?foods_and=`,
  `?foods_or=`, negations, `?query=` fuzzy. Pantry on-hand = `food_onhand` boolean on `/api/food/`,
  richer `/api/inventory-entry/` (amount/unit/location/expiry) also exists. Not needed for v1.

### Self-hosting (mainframe)
- **Two containers:** `vabene1111/recipes` (gunicorn + bundled nginx, port 80) + `postgres:16-alpine`.
  No separate nginx, no redis for single-household. Current stable ~v2.6.9, active project.
- **DB:** SQLite officially fine for home use BUT has a network-exposure footgun (DB can land in the
  nginx-served media dir — GHSA-g8w3-p77x-mmxh). Cleaner default = the tiny bundled Postgres.
- **Footprint:** ~300–500 MB RAM total. Coexists fine with the music stack.
- **Networking (good for our curl client):** NO reverse proxy needed. Map `ports: 8080:80`, hit
  `http://mainframe:8080` over plain LAN HTTP. `ALLOWED_HOSTS=*`; `CSRF_TRUSTED_ORIGINS` only matters
  behind a proxy (which we won't use). Direct IP:port access has no CSRF pain.
- **Setup gotchas:** set `SECRET_KEY` (≥50 chars, stable), `POSTGRES_PASSWORD`; mount `./mediafiles`
  + the Postgres data dir; first registered account becomes superuser → create a Space → then set
  `ENABLE_SIGNUP=0`. Back up media + DB before version bumps (migrations run on update).

### Ingest toolchain
- **Recommendation: feed URLs to Tandoor's `/api/recipe-from-source/`, do NOT build our own scraper.**
  Tandoor embeds `recipe-scrapers` (hhursev, healthy, v15.x, 643 sites) with the generic JSON-LD
  fallback on. Rebuilding it would just drift out of sync.
- **JSON-LD fallback** is reliable on the modern WordPress food-blog ecosystem (SEO pressure → near-
  universal Recipe markup); expect a tail of misses on hand-rolled/JS-only/paywalled sites.
- **Dedupe:** Tandoor stores `source_url` but has NO filter-by-source_url API yet (#4632) and does
  NOT auto-reject dupes. Watcher keeps its OWN seen-set keyed by normalized source URL (like an *arr
  history DB).
- **Legality:** personal-use capture of ingredient lists + instructions is low-risk (not
  copyrightable; prose/photos are, but personal capture is normal). Be a polite scraper (robots,
  rate-limit, UA). Don't republish.

### Tablet charging (confirmed — for the always-on requirement)
- T102HA charges over **micro-USB** (NOT USB-C). Stock adapter 5V/2A = 10W. No PD/QC — plain 5V only.
  Battery ~31.6 Wh. **Buy a 5V/2.4A (12W) USB-A block + a 3A-rated micro-USB cable.** Higher wattage
  is genuinely wasted (no PD to negotiate it). ~$21 shipped is fine. Order it.

---

## Ingest sources — SEED LIST (approved 2026-06-03)

User taste profile: omnivore foodie, eats everything, **high-protein / gym lean**, mild prefer-cooked-
over-raw-veg (skip salad-only blogs). So the pool is wide, batch bucket leans high-protein.

All 12 below were verified live: scrapable (no Cloudflare/CAPTCHA/paywall), emit clean Recipe JSON-LD,
and have a working feed to poll. All on `recipe-scrapers`' supported list (zero-config) EXCEPT The
Protein Chef, which still scrapes via Tandoor's generic JSON-LD fallback.

**Batch / high-protein meal-prep bucket:**
- Fit Men Cook — gym meal-prep flagship (poll the Yoast `recipes-sitemap.xml`, NOT `/feed/` — its feed
  serves full-HTML items that confuse naive sniffers)
- Meal Prep Manual — `/feed/` — purpose-built batch components (bulk chicken/rice/beans)
- Skinnytaste — `/feed/` — 30g+ protein meal plans, family-batch dinners
- Budget Bytes — `/feed/` — cheap big-batch staples (spans both buckets)
- The Protein Chef — `/feed/` — high-protein comfort + macros (off-list; clean WP Recipe Maker JSON-LD)

**Quick-weeknight bucket (global, ~30 min):**
- RecipeTin Eats — `/feed/` — global comfort + Asian takeout (flagship)
- Damn Delicious — `/feed/` — American + Asian-American, "30-minute meals"
- The Woks of Life — `/feed/` — Chinese
- Just One Cookbook — `/feed/` — Japanese
- The Mediterranean Dish — `/feed/` — Mediterranean / Middle Eastern
- Indian Healthy Recipes (Swasthi's) — `/feed/` — South Asian / Indian
- Mexican Please — `/feed/` — Mexican

Bench (vetted, on supported list — add if a bucket runs thin): evolvingtable, sweetpeasandsaffron,
eatingbirdfood, ambitiouskitchen, bowlofdelicious (meal-prep/quick); My Korean Kitchen, Red House
Spice (Asian); Eat the Gains, The Girl on Bloor (high-protein). Reddit: OUT (2023 API change; not
worth it).

---

## Ingest watcher mechanics (specified — implement from this)

Per source store: `feed_url` (or sitemap), `sitemap_index` (`/sitemap_index.xml`), ETag +
Last-Modified, last-seen high-water timestamp.

1. **Poll** `/feed/` every 30–60 min with conditional GET (send `If-None-Match`/`If-Modified-Since`;
   `304` = skip, near-zero cost). **Follow redirects** (`curl -L`) — some feeds 301 (e.g. Pinch of
   Yum) and you silently get zero items otherwise. Collect new `<item><link>` URLs.
2. **Backfill daily** by walking the Yoast `post-sitemap*.xml` (paginated: `post-sitemap.xml`,
   `post-sitemap2.xml`, …); take `<url><loc>` where `<lastmod>` > high-water mark. RSS only shows the
   newest window (count varies, NOT always 10) — sitemap is how you catch anything missed.
3. **Pre-filter cheaply** on feed `<category>`/slug — drop roundup/guide buckets (`roundup`, `news`,
   `how-to`, slugs like `/best-`, `top-NN-`, plural `-recipes/` collections).
4. **Authoritative recipe check** — fetch RAW HTML (readability strips `<script>`, so don't use a
   reader), parse every `application/ld+json` (handle top-level object OR `@graph` array; `@type` may
   be string or list). **Import iff a `Recipe` node exists; if only `ItemList` → it's a roundup →
   skip.** This one check identifies real recipes AND filters listicles.
5. **Import** surviving URLs via `POST /api/recipe-from-source/`. Response keys: `recipe_json`,
   `recipe_tree`, `recipe_html`, `recipe_images`, `duplicates`, `link`, `error`, `msg`. Use
   `duplicates` (matches existing `source_url`) to dedupe; treat non-empty `error`/`msg` or empty
   `recipe_tree` as a failed scrape to log. Also keep the watcher's OWN seen-set keyed by normalized
   source URL (Tandoor has no filter-by-source_url API).
6. **Role-classify** the imported recipe (batch vs quick) and tag it in Tandoor — heuristics:
   `total_time` < ~30 min → quick; high servings / keywords (meal prep, freezer, batch) / a per-source
   default (the batch-bucket sources default to batch) → batch.
7. **Be polite:** real identifying UA (`RecipeWatcher/1.0 (+mailto:blues@computerblues.net)`), respect
   robots.txt, 1–2 s/host delay, exponential backoff on 429/5xx.

---

## Open questions (what's left)

1. **Role-classification thresholds** — confirm exact batch-vs-quick rule (time cutoff, servings
   cutoff, keyword list) once we see real ingested data; the per-source default gets us started.
2. **Confirm planning-on-phone vs deck** — design assumes user plans in Tandoor's web UI on a phone,
   deck executes. Quick sanity-check it matches how the user wants to use it.
3. **Tandoor hosting specifics** — port, whether Postgres is already available / spin a new one,
   where volumes live on the mainframe.
4. **`/api/recipe-from-source/` behaviour on our build** — creates directly vs returns-for-confirm
   (response serializer suggests it returns parsed `recipe_tree`/`recipe_json` for a create step —
   verify on the live instance).

---

## Deck integration notes (for whoever implements)

- New mode replaces **ws3 (was Video — dropped; Atom can't sustain video)**. Touch points:
  `sway/config` (`$ws3 "3:Video"` → `"3:Cooking"`, drop `assign mpv`), `eww/ws-name.sh`,
  `deck-mode.sh` (case 3), mode rail labels (`eww.yuck` dash-foot: "VIDEO" → "COOK"), and `deck-root`
  (add a `(box :visible {ws == "3:Cooking"} ...)` branch; today ws3 is blank for mpv).
- Deck client is now **mostly read-only**: render tonight's plan + Cook mode. Reuse pagination for
  step-through. No deck-side planner, no pantry UI in v1.
- Keep the neo-brutalist language (stamped cells, hard borders/shadows, ASCII-only SCSS — see eww
  README gotcha). Big kitchen-friendly touch targets, glanceable across the counter.
- Client scripts live in `eww/*.sh` → installed to `~/.local/bin/<name>`; talk to Tandoor with
  `curl` + an API token stored OUTSIDE the repo (like `gcal-url`). Use `Authorization: Bearer`.
- Mode rail (Dash foot) + `deck-mode` + `deck-swipe` all reference 3 modes — update labels and the
  Video→Cooking rename consistently.

---

## Immediate next steps

Design phase is closed — sources approved, architecture + ingest mechanics specified. Build order:

1. ✅ **DONE — Tandoor stood up** (`cooking/` stack, port 8090, named volumes, onboarded, read-write
   token at `~/.config/eww/tandoor-token`, signup locked). Run docker via `sg docker -c '...'`.
   ⚠️ Still TODO: **LAN reachability** — WSL is NAT mode, so only localhost works on the PC; the
   tablet/phone need mirrored networking (`.wslconfig` → `networkingMode=mirrored`, restarts WSL) or a
   Windows netsh portproxy before the deck client can reach `192.168.0.30:8090`.
2. ✅ **DONE — ingest watcher built + pool seeded + scheduled.** `cooking/ingest/watcher.py` (stdlib
   Python; `sources.json`, gitignored `state/`). Watcher FETCHES HTML itself (browser UA, polite) and
   hands it to Tandoor via `{url, data:html}` — because Tandoor's own server-side fetch gets 403'd by
   sources. Pipeline: feed (conditional GET) → drop roundups/images/seen → fetch → parse via Tandoor →
   skip non-recipes/dupes → role-tag batch/quick → create. **Seeded 69 recipes (41 batch / 28 quick)**
   across 11 sources. **Dropped 2:** Damn Delicious (Cloudflare-403) → replaced by Bowl of Delicious;
   Indian Healthy Recipes (JS bot-wall) removed → **South-Asian cuisine gap to fill later**. Runtime
   lives in the **/home clone**; cron runs it every 30 min (`--per-source 6`).
3. ✅ **DONE — deck Cook-mode view built + ws3 swap.** ws3 renamed Video->Cooking everywhere
   (`sway/config` [dropped `assign mpv`, added `exec cook load`], `deck-mode.sh`, `deck-swipe.sh`,
   `eww.yuck` deck-root branch + dash-foot rail "COOK", sandbox `sway-config`). New `eww/cook.sh`
   (-> `~/.local/bin/cook`) drives it imperatively like album-grid: resolves tonight's recipe (today's
   Tandoor meal-plan -> else newest), normalizes, pushes eww vars. View = stamped title + role badge +
   ingredient checklist (tap to tick, lime when done) | step viewer (STEP n/N, wrapped instruction,
   prev / NEXT STEP pager). Neo-brutalist, no-scroll. Built + screenshot-verified in `~/deck-sandbox`
   against localhost:8090 (pager + checklist interaction confirmed). Ingredients render as a **2-column
   grid** so long lists (tested: bibimbap, 15) fit the no-scroll screen without pushing the header off.
   **Meal-plan resolution VERIFIED**: created a Tandoor meal-plan entry for today and the deck resolved
   THAT recipe (not the newest) -> the full "plan ahead -> tired-night deck shows tonight's meal" thesis
   loop works end to end. Remaining minor polish: a very long single step could still overflow
   vertically; some sources put the recipe blurb in step 1.
4. **Sort LAN reachability** (mirrored WSL networking or netsh portproxy) so tablet/phone reach :8090.
   The tablet's `cook load` will show "NO MEAL LOADED" until this is done.
5. **Deploy to the tablet** (scp eww.{yuck,scss} + cook -> tablet, full eww restart) once LAN is up.
6. **Buy the charger** (12W block + 3A micro-USB cable) for the always-on requirement.
