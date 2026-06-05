# Cooking phase 2 — calorie-aware smart finder (grounded nutrition + recommender)

**Date:** 2026-06-04 (design discussion; decisions locked below)
**Status:** Pre-spec → ready to build. Thesis evolution, nutrition strategy, recommender shape, and
compute budget all settled in discussion. Nothing built yet for this phase.
**Builds on:** `2026-06-03-cooking-tab-plan.md` (phase 1 — the takeout-interceptor Cook tab, now
shipped: Tandoor backend, ingest watcher on cron, deck Cook-mode + photo picker + quick/batch mood
filter, deployed to the tablet at commit `818080c`/`566553f`).
**Context:** Transformer Mini deck — always-on sway/eww touch "deck" on a 2016 ASUS T102HA (Atom
x5-Z8350, 4 GB, weak GPU; neo-brutalist, paginated, no touch-scroll). Authoring repo
`/mnt/c/Users/ayub/Desktop/transformer-mini-slab`; runtime clone `/home/ayub/transformer-mini-slab`
(native ext4, where cron runs); tablet `minideck@192.168.0.44`. **Mainframe** = the home server /
daily-driver PC: **i5-12400F (6c/12t), 16 GB RAM, RTX 3060 12 GB** — also runs the music stack and
Tandoor.

---

## The thesis evolves: two doors into one pool

Phase 1's thesis is load-bearing and **stays primary**: it's a *takeout interceptor* — the meal is
decided ahead, so the tired-night deck just executes ("reheat the chili" / "cook this 25-min thing"),
one tap to steps, zero choosing. Phase 1 **deliberately cut** "what can I make."

Phase 2 adds a **second door** without overwriting the first:

- **Interceptor door (default, tired night):** unchanged. Tonight's plan → Cook mode.
- **Improviser door (new, high-energy / "I feel like deciding"):** a **calorie-aware finder** —
  set a calorie ceiling + ingredients you want/avoid → get ranked candidates from the pool. The
  later **fridge/pantry-photo VLM** ("what can I make right now") is the eventual end of this door.

So we *add* a mode; the interceptor insight is untouched. Honest framing for the write-up: *the
constraint cut in v1 came back once the hardware (local LLM + VLM) made it cheap and grounded.*

---

## What we're building in phase 2 (the genuinely-useful slice)

1. **Calories on every recipe** — grounded, not guessed (see "Nutrition" below).
2. **A finder** — calorie ceiling + include/exclude ingredients (+ quick/batch) → ranked candidates.
3. **A small onboarding/profile** — standing daily-calorie target + favorite/avoid ingredients, so
   the finder pre-filters sensibly before you touch anything.
4. **A bigger pool** — grow ~77 → several hundred, fill the South-Asian gap.

Deferred to later phases (rail-compatible, see "Roadmap"): MQTT bus, ESP32 proximity-wake,
whisper STT/TTS, conversational LLM advisor, VLM pantry scan, SearXNG-backed open-web advisor, MCPs.

---

## Architecture — one-direction dependency, two time-separated paths

The whole design hangs off one rule, same as the music stack: **each piece talks to exactly one
thing below it over HTTP; the dumb client never reaches past its neighbour.** Any piece is then
swappable without touching the others — that's the abstraction worth writing about.

```
  DECK (thin client)             MAINFRAME (brains — all Docker)
  ──────────────────             ──────────────────────────────
  finder UI  ──HTTP──▶  recommender ──▶ Tandoor (recipes + nutrition + meal-plan)
  (eww panel)            service          ▲
   reads only            (scores/ranks)   │
       │                                  │
   profile (display)                      │
                          watcher ────────┘  (writes recipes + nutrition)
                             │
                             ├──HTTP──▶ Ollama / gemma4:e4b   (parses ingredient strings)
                             └──▶ local nutrition DB + SearXNG (grounds the numbers)
```

The deck knows **only** the recommender. The recommender knows **only** Tandoor + the profile file.
The watcher is the **only** thing that ever touches the LLM. Two paths, run at different times:

**Write path — background, on the existing 30-min watcher cron (nobody waiting):**
```
feed → watcher → fetch page → Tandoor scrapes recipe
                                   │  [NEW]
                                   ▼
              ingredients[] → gemma4:e4b parse → {qty,unit,food} per line
                                   ▼
              ground each via local nutrition DB → (miss) SearXNG → sum ÷ servings
                                   ▼
              write per-serving macros + confidence + per-ingredient source into Tandoor
```

**Read path — interactive, on the deck (human waiting → must be instant):**
```
finder → recommender {kcal ceiling, include[], exclude[], mood, profile}
            → query Tandoor candidates
            → DETERMINISTIC score (calorie-fit + ingredient-match + protein density)
            → ranked recipe IDs + photos → deck renders tiles
```

**No LLM on the read path.** The model did its work hours ago at import; ranking is plain, fast,
debuggable code. The tired-night tap stays instant and works even while Ollama is unloaded / you're
gaming.

---

## Nutrition — grounded, never guessed

**Principle (this is the design's spine):** we do **not** trust a 4B model's *memory* for calorie
numbers. We shrink the model's job to the one thing it's reliably good at — **turning messy
ingredient text into structured `{qty, unit, food}`** — and let **authoritative data** supply every
number. The model is a *translator between human text and real data*, never an oracle.

### Data sources — keyless, no geo-block, self-hosted

USDA's *API* needs a key and is geo-blocked here, so we don't use it. Instead we **host the data**:

| Source | Strong at | Key? | How we get it |
|---|---|---|---|
| **USDA SR Legacy** (~7,800 generic foods, few MB) | raw cooking staples ("chicken breast", "brown rice", "olive oil") | none — public domain | redistributed copy from a **mirror** (HuggingFace/GitHub/Kaggle) → dodges the geo-blocked usda.gov entirely |
| **Open Food Facts** (4M+ products; CSV/JSONL/Parquet nightly dumps) | branded / regional / packaged items | none — public API + open dumps | EU-hosted, not geo-blocked; add **only if** branded gaps appear |
| **SearXNG** (self-hosted) | the rare unresolved item | none | our own instance; **only network call, only on a miss** |

Recipe ingredients are mostly generic, so **USDA SR Legacy in a local SQLite is the spine** — tiny,
instant, offline. OFF is optional breadth; SearXNG is the last-resort gap-filler. **No API keys
anywhere; the only thing that ever hits the open web is our own SearXNG, only when both local
datasets miss.**

### The harness (code drives; model does only the fuzzy bits)

```
for each recipe (batch, at import):
  for each ingredient line:
     gemma4:e4b → {qty, unit, food}              # model's ONLY job
     local nutrition DB(food)  --hit-->  macros × qty
        │ miss → Open Food Facts (if loaded)
        │ miss → SearXNG(food + "nutrition") → extract
        │ miss → mark ingredient UNRESOLVED
  sum × qty ÷ servings → per-serving {kcal, protein, carbs, fat}
  store in Tandoor nutrition; tag per-ingredient source = usda | off | web | unresolved
  confidence = fraction of recipe mass resolved against real data
```

Control flow lives in our code and is fully inspectable: every recipe records *which* source backed
*which* ingredient, so any number is auditable. **Prefer published** macros when a blog ships them
(free ground truth); only run the harness on the gaps. The model is called with `format=json` + a
fixed schema, `temperature=0` — a *function returning JSON*, not a chat.

**Open decision (lean: flag, don't fake):** if too much of a recipe's mass is `unresolved`, mark the
recipe **"macros incomplete"** rather than silently summing partial data and presenting a confident
wrong total.

### Earning trust — the calibration set

Recipes that already carry *published* macros are our **truth set**. Run the harness on them, compare
the grounded sum to the published number, measure error, tune the prompt/matching until it's tight.
We validate the pipeline *before* relying on it — and the UI shows a `~` + confidence on estimated
recipes, so the tool tells you when it's unsure instead of confidently lying.

---

## The recommender (deterministic read path)

Service on the mainframe. Input: `{kcal_ceiling, include[], exclude[], mood, profile}`. Output:
ranked recipe IDs + image refs.

- **Hard filters:** calorie ceiling, excluded ingredients, "macros incomplete" hidden unless asked.
- **Soft boosts (ranking, not gates):** included ingredients rank up (toggle for "must contain");
  favourites from profile.
- **Tiebreak:** protein-per-calorie (user taste = lean, high-protein).
- **Profile:** standing daily-calorie target + favourite/avoid lists, in a small JSON on the
  mainframe (mirrors how `cook` mood/state already persist). Stateless one-off queries layer on top.

Deterministic on purpose: fast, debuggable, works with the GPU asleep. The *conversational* advisor
that reasons over your goals + what you've eaten is a later phase that intentionally puts an LLM on
the read path, with its own latency budget.

---

## Compute budget — AI that gets out of your way

Mainframe is also the daily driver / gaming PC. Verified idle under normal load: **GPU 7% util,
~9.6 GB VRAM free of 12; CPU load 0.26/12 threads; 11 GB RAM free.** Ollama already installed.

- **Model: `gemma4:e4b`** (Gemma 4, shipped Apr 2026; 4.5B effective, **natively multimodal**).
  Fits the free VRAM; the *same* model handles ingredient-parsing now **and** the future
  fridge-photo VLM — one model spine for the whole helper. `gemma4:e2b` is the lighter fallback;
  `26b`/`31b` won't fit resident in 12 GB.
- **Dockerized Ollama** (its own container, GPU passthrough — the one real setup risk to verify
  under Docker Desktop/WSL2). Pull `gemma4:e4b`.
- **Idle-unload + batch-at-import:** the model is invoked only by the watcher's batch job, runs with
  `keep_alive=0` so it unloads the instant the batch finishes. "Cooking ≠ gaming" is the natural
  mutex; when you're not importing recipes, the 3060 is fully yours. Warm-up latency is irrelevant
  because no human ever waits on it.

Blog point: *self-hosted AI that politely vacates the GPU when you want to play a game.*

---

## Deck UI — thin finder + onboarding (eww)

Reuse the existing photo-tile picker grid. Add:

- **Finder/filter screen:** tap a calorie ceiling; tap **ingredient chips** to include/exclude
  (chips sourced from Tandoor's real food list — curated, no typing) → fires the recommender →
  ranked photo tiles. Each tile shows kcal + protein, with `~` for estimated.
- **Onboarding:** set standing daily-calorie target + favourite/avoid (rare action; deck sliders +
  chips, or phone — TBD). Stored in the profile JSON.
- No new typing burden; everything is taps. Verify in the deck-sandbox via grim, same as Cook mode.

---

## Dataset growth

- Target **~77 → ~300** recipes; politeness-capped (`--per-source`, ≥2 s/host, conditional GET).
- **Fill the South-Asian gap** left when Indian Healthy Recipes was dropped (find a scrapable
  replacement that doesn't bot-wall).
- Use existing `--backfill` (sitemap walk) to deepen the pool; nutrition harness runs over new +
  backfilled recipes automatically.

---

## Build order (each slice independently useful & verifiable)

0. **Ollama container + `gemma4:e4b`.** Stand up, **verify GPU passthrough works under Docker
   Desktop/WSL2** (main risk), run one test parse+estimate. *Verify:* sane macros for a known recipe.
1. **Local nutrition DB.** Load USDA SR Legacy into SQLite under `cooking/`. *Verify:* lookups for
   common foods return correct per-100 g macros.
2. **Nutrition harness + backfill the 77.** Parse → ground → sum → write to Tandoor. *Verify against
   the calibration set:* grounded sums vs published macros within tolerance; tune.
3. **Recommender service.** Filters + scoring + profile. *Verify:* curl with filters, eyeball ranking.
4. **Deck finder + onboarding UI.** *Verify:* grim screenshots in sandbox.
5. **Profile persistence + dataset growth** (+ optional OFF dump if branded gaps surfaced).

---

## Roadmap — deferred phases (all on the same thin-client / owned-brain rail)

1. **LLM nutrition estimate → DB-grounded harness** ← *this doc* (first LLM-in-the-loop milestone).
2. **Conversational advisor** — LLM on the read path: "I had a big lunch, light high-protein dinner
   from my pool?" Reasons over goals + intake. Own latency budget.
3. **Full diet/fitness helper** — goal model (cut/maintain/bulk), weight trend, intake logging
   (logging via "talk to it" STT, since the deck is bad at typing).
4. **VLM pantry/fridge scan** — photograph contents → gemma4 vision → "what can I make right now."
   The improviser door's endgame; the *return* of the cut "what can I make" constraint.
5. **Ambient layer** — **MQTT** bus; **ESP32 proximity sensor** wakes the screen on approach;
   **whisper STT/TTS** for hands-free; **SearXNG**-backed open-web answers; **MCPs** to wire tools.

Each clips onto the same rail: thin eww panel on the deck → service on the i5/3060 over LAN. Nothing
in phase 2 blocks any of these.

---

## Open questions

- **Unresolved-ingredient policy:** flag recipe "macros incomplete" (lean) vs. sum partial anyway.
- **Calorie filter:** hard ceiling (lean — every recipe now has a number) vs. soft "prefer under X".
- **Onboarding surface:** deck (sliders + chips) vs. phone web.
- **South-Asian source:** which scrapable blog replaces Indian Healthy Recipes.
- **GPU passthrough** under Docker Desktop/WSL2 — confirm before committing to the container path.

---

## The blog case study (why this project matters)

This is the write-up's thesis in miniature: **a regular consumer using AI to assemble a custom
internal tool from self-hosted parts** — where the cheap thin client is deliberately dumb and every
"brain" (Tandoor, the recommender, Ollama/Gemma, the nutrition data, SearXNG) lives on one box you
own, behind clean HTTP contracts. The honest-AI details are the heart of it: the model translates
rather than recalls; numbers come from authoritative data; the system *tells you when it's guessing*;
and the AI vacates the GPU when you'd rather game. A new abstraction layer for DIY tech — AI as the
glue that finally lets individuals build software shaped exactly to their own life.

---

## Immediate next steps

1. Dockerize Ollama, pull `gemma4:e4b`, verify GPU passthrough + a test parse.
2. Load USDA SR Legacy into a local SQLite.
3. Build the nutrition harness; backfill the 77; calibrate against published-macro recipes.
4. (then) recommender service → deck finder UI → profile → dataset growth.
</content>
</invoke>
