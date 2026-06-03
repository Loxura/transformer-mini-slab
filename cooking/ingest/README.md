# Cooking conveyor — ingest watcher

Polls the approved food-blog feeds and auto-imports new recipes into Tandoor, role-tagged
**batch** vs **quick** so the meal planner can split them. Mirrors the *arr music stack:
monitor → grab → store, no hand-holding. Design rationale: `docs/proposals/2026-06-03-cooking-tab-plan.md`.

## Why it fetches the HTML itself (don't "fix" this)
Tandoor's `/api/recipe-from-source/` can fetch a URL itself, but several sources (Budget Bytes etc.)
**403 Tandoor's server-side fetcher** (default UA / repeated hits from one IP). So the watcher fetches
each page with a browser User-Agent, rate-limited per host, and hands the HTML to Tandoor via the
`data` field — Tandoor still does the parsing (recipe-scrapers), we just control the fetch. Passing
only a URL (letting Tandoor fetch) gets intermittently blocked.

## Pipeline (per new URL)
1. Poll feed (conditional GET — ETag/Last-Modified; `304` = nothing new). Sitemaps for `--backfill`.
2. Drop obvious roundups by slug (`/best-`, `top-N`, `-recipes/`, `/category/`) + already-seen URLs.
3. Fetch page HTML (browser UA, ≥2 s/host).
4. `POST /api/recipe-from-source/ {url, data:html}` → structured `recipe` + `duplicates`.
5. Skip if `duplicates` non-empty (already imported) or no `steps` (not a recipe — roundup/blog post).
6. Classify role: `working+waiting` time → `quick` if ≤30 min else `batch`; `bucket_default` when no time.
7. `POST /api/recipe/` with keywords `[<role>, auto-ingest]` (normalizes step/ingredient `order` first).

## Run
```sh
# needs ~/.config/eww/tandoor-url + tandoor-token (read-write). Stdlib only — no pip.
cooking/ingest/watcher.py --source "Budget Bytes" --dry-run -v   # preview, create nothing
cooking/ingest/watcher.py --source "Budget Bytes" --limit 5      # create up to 5
cooking/ingest/watcher.py                                        # poll ALL sources
cooking/ingest/watcher.py --backfill --source "Fit Men"          # walk sitemap for older posts
```
Flags: `--source <substr>`, `--limit N` (global cap/run), `--per-source N` (fair cap per source — use for cron), `--dry-run`, `--backfill`, `-v`.

Sources live in `sources.json`. State (gitignored) in `state/`: `seen.json` (url → outcome) and
`feeds.json` (per-feed ETag/Last-Modified). Delete `state/seen.json` to re-evaluate everything.

## Scheduling (always-on)
Runtime lives in the `/home` clone (matches the music stack + its cron). Cron line (every 30 min,
`--per-source` so each source gets a fair share and a sitemap source like Fit Men Cook can't hog the
run — its backlog just trickles in):
```sh
*/30 * * * * /home/ayub/transformer-mini-slab/cooking/ingest/watcher.py --per-source 6 >> /home/ayub/recipe-ingest.log 2>&1
```
Conditional GET (ETag/Last-Modified) makes idle polls cheap (`304`, no work). Needs Tandoor up
(localhost:8090) + the token files; the watcher only does HTTP, so it does NOT need the docker group.
