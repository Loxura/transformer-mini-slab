# transformer-mini-slab 🎵📖🍳

Reviving a **2016 ASUS Transformer Mini (T102HA, Intel Cherry Trail)** as a calm,
always-on **touch "deck"** running Debian Linux — styled **"e-ink with a heartbeat."**

> Old hardware, great battery, lovely screen. Give it a few jobs and make them beautiful.

**Status:** 🛠️ Actively built. The deck UI (sway + eww) and the mainframe backends run today;
deployment to the physical tablet follows the LAN/charger steps in the [roadmap](docs/roadmap.md).

---

## The shape of it — a deck and a mainframe

The project is a **thin client + owned brains** split, the same on every feature:

- **The deck** — the tablet itself. An always-on, neo-brutalist, **swipe-between-fullscreen-modes**
  touch UI (sway + a single eww layer-shell window). It only renders and takes taps; it talks to the
  mainframe over the LAN with `curl` + a token. See [docs/deck.md](docs/deck.md).
- **The mainframe** — the home server (same box as the music-acquisition stack). It stores, scrapes,
  classifies, and computes; the deck just displays the result.

### Deck modes (swipe order)
1. **Dash** — clock, weather, now-playing mini, system vitals, toggles (eww widgets).
2. **Music** — a touch *Now Playing* card: big album art, large transport, "UP NEXT", and a palette
   pulled **live from the cover** (the one colour-adaptive exception to the e-ink look). Album-grid
   browser + Bluetooth panel from the corner. This is the "heartbeat."
3. **Cooking** — a **takeout interceptor**: the meal is decided ahead (planned in Tandoor's web UI on
   a phone), so the tired-night deck just says "cook / reheat *this*," one tap to step-through.

## The aesthetic

Mostly paper-and-ink minimalism — static, monochrome, neo-brutalist (stamped cells, hard borders).
The single living element is the album-art palette on the Music card. Calm, but alive.
See [docs/aesthetic.md](docs/aesthetic.md).

## Hardware target

| | |
|---|---|
| Device | ASUS Transformer Mini **T102HA** (detachable 2-in-1) |
| SoC | Intel Atom **x5-Z8350** (Cherry Trail) |
| RAM | 4 GB |
| Storage | 64/128 GB eMMC **+ microSD** (music library) |
| Display | 10.1" 1280×800 touch |

Cherry Trail Linux support is real but has a checklist — see [docs/hardware.md](docs/hardware.md).

## Stack

**On the deck:** `sway` (compositor) · `eww` (widgets/cards, layer-shell) · `lisgd` (touch gestures) ·
`mpd` + `mpc` (playback) · PipeWire · `wvkbd` (on-screen keyboard).

**On the mainframe:** a music-acquisition stack (`server/`) · **Tandoor Recipes** + a recipe-ingest
conveyor + a macro-enrichment engine (`cooking/`) · **SearXNG** metasearch (`searxng/`) ·
**Ollama** GPU LLM runtime (`ollama/`).

Architecture & data flow: [docs/architecture.md](docs/architecture.md).

## The cooking backend (the conveyor)

A self-feeding recipe pipeline that makes the Cooking tab worth having:

1. **Ingest** — `cooking/ingest/` polls food-blog feeds and imports new recipes into Tandoor
   (role-tagged `quick`/`batch`), deduped against its own seen-set.
2. **Enrich** — `cooking/enrich/` makes the pool **macro-accurate**: it cleans the ingredient data
   (review-gated), then cross-checks USDA ∥ SearXNG, has Ollama/Gemma reconcile per-100 g macros
   (with a deterministic Atwater sanity guard), and writes them into Tandoor — which rolls them up
   into per-recipe nutrition automatically.

Each piece has its own README. Design docs live in [docs/proposals/](docs/proposals/).

## Repo layout

```
transformer-mini-slab/
├── docs/              # design language, hardware checklist, deck spec, architecture, proposals
├── sway/              # compositor config (the swipe deck)
├── eww/               # Dash widgets + deck scripts (clock, weather, vitals, ws routing)
├── music-card/        # the Now Playing card (art + cover-derived palette, transport)
├── mpd/               # mpd configuration
├── waybar/ themes/    # bar + colourschemes (kitty/cava e-ink palette)
├── server/            # mainframe music-acquisition stack + sync-to-tablet
├── cooking/           # Tandoor stack + ingest conveyor (ingest/) + macro enricher (enrich/)
├── searxng/           # self-hosted metasearch (LAN search UI + JSON API for the enricher)
└── ollama/            # containerized GPU LLM runtime (recipe macro reconciliation)
```

## License

MIT — see [LICENSE](LICENSE).
