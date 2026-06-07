#!/usr/bin/env python3
"""
Cooking macro-enrichment engine (Phase 2a).

The conveyor (../ingest/watcher.py) fills Tandoor with recipes but ZERO nutrition. This makes the
growing pool macro-accurate so a later phase can recommend meals for a goal. It is a DATA-QUALITY
engine, not a UI: clean the ingredient data, attach USDA-grounded nutrition to each Food, and let
Tandoor roll it up per recipe automatically (Recipe.nutrition = sum of food props x amount x unit
conversion). We never compute recipe totals ourselves — we feed Tandoor the inputs.

Accuracy bar (why we don't just use Tandoor's single-source fdc/aiproperties endpoints):
    USDA FDC  ||  SearXNG web  ->  Gemma reconciles  ->  confidence + source + agreement
High-confidence agreement -> written to Tandoor. Disagreement / low confidence -> review file, never
silently written.

Two passes:
  Pass A  cleanup     review-GATED (mutates the shared recipe DB): propose merges/deletes, flag
                      mis-parsed rows -> state/cleanup-plan.json -> human approves -> --apply-cleanup.
  Pass B  match+enrich additive/reversible, so no gate: per clean Food, look up + reconcile + write
                      Food.properties, Food.fdc_id, and (food,unit)->grams UnitConversions.

Stdlib only (mirrors watcher.py — no pip). Config in ~/.config/eww/:
    tandoor-url, tandoor-token         (required; shared with the watcher)
    usda-key                           (optional; FoodData Central api.data.gov key. Absent -> USDA skipped)
    searxng-url   (default http://localhost:8091)
    ollama-url    (default http://localhost:11434)
    ollama-model  (default gemma3n:e4b)   # `ollama pull gemma3n:e4b` first
State (gitignored): cooking/enrich/state/{enriched,cleanup-plan,review-macros}.json

Usage:
  ./enrich.py --setup-properties        # create the 6 nutrient PropertyTypes (one-time)
  ./enrich.py --plan-cleanup            # write cleanup-plan.json (NO mutation) — review it
  ./enrich.py --apply-cleanup           # execute approved merges/deletes from the plan
  ./enrich.py --backfill                # Pass B over all clean foods
  ./enrich.py --food "chicken breast"   # enrich one food by name (debug)
  ./enrich.py                           # incremental: foods not in enriched.json yet (cron)
  ./enrich.py --dry-run -v              # match + reconcile, write NOTHING
  ./enrich.py --backfill --limit 5      # cap foods processed (testing)
"""
import argparse, json, os, re, sys, time, urllib.request, urllib.error, urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATE = HERE / "state"
CFG = Path.home() / ".config" / "eww"

BASE = open(CFG / "tandoor-url").read().strip()
TOKEN = open(CFG / "tandoor-token").read().strip()
APIH = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}


def _cfg(name, default=None):
    p = CFG / name
    return p.read_text().strip() if p.exists() else default


USDA_KEY = _cfg("usda-key")                                   # optional
SEARX = _cfg("searxng-url", "http://localhost:8091").rstrip("/")
OLLAMA = _cfg("ollama-url", "http://localhost:11434").rstrip("/")
MODEL = os.environ.get("ENRICH_MODEL") or _cfg("ollama-model", "gemma3n:e4b")

# The 6 nutrient slots, each mapped to its USDA FoodData Central nutrient number via PropertyType.fdc_id.
NUTRIENTS = [
    ("Calories", "kcal", 1008),
    ("Protein", "g", 1003),
    ("Carbohydrates", "g", 1005),
    ("Fat", "g", 1004),
    ("Fiber", "g", 1079),
    ("Sugar", "g", 2000),
]
# JSON key <-> property name. Gemma + USDA both speak these lowercase keys.
NKEYS = ["calories", "protein", "carbohydrates", "fat", "fiber", "sugar"]
NAME_BY_KEY = {k: n for k, (n, _u, _f) in zip(NKEYS, NUTRIENTS)}
FDC_BY_KEY = {k: f for k, (_n, _u, f) in zip(NKEYS, NUTRIENTS)}

VERBOSE = False


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def vlog(*a):
    if VERBOSE:
        print(*a, file=sys.stderr, flush=True)


# ---- HTTP --------------------------------------------------------------------
def _req(url, data=None, headers=None, method="GET", timeout=60):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read()


def api(method, path, payload=None, timeout=120):
    """Tandoor API call. Returns (status, parsed_json_or_error_dict)."""
    data = json.dumps(payload).encode() if payload is not None else None
    try:
        st, body = _req(BASE + path, data=data, headers=APIH, method=method, timeout=timeout)
        return st, (json.loads(body) if body else {})
    except urllib.error.HTTPError as e:
        try:
            body = json.loads(e.read().decode())
        except Exception:
            body = {"_raw": "<unparseable>"}
        return e.code, body
    except Exception as e:
        return 0, {"_err": f"{type(e).__name__}: {e}"}


def api_all(path):
    """Page through a Tandoor list endpoint, returning the flat results list."""
    out, page = [], 1
    sep = "&" if "?" in path else "?"
    while True:
        st, body = api("GET", f"{path}{sep}page={page}&page_size=100")
        if st != 200 or not isinstance(body, dict):
            break
        out.extend(body.get("results", []))
        if not body.get("next"):
            break
        page += 1
    return out


def http_json(url, timeout=60):
    """GET a URL expecting JSON. Returns parsed dict/list or None on any failure."""
    try:
        st, body = _req(url, headers={"User-Agent": "MacroEnricher/1.0"}, timeout=timeout)
        return json.loads(body) if st == 200 else None
    except Exception as e:
        vlog(f"    http_json fail {url[:80]}: {type(e).__name__}")
        return None


# ---- state -------------------------------------------------------------------
def load_state(name, default):
    p = STATE / name
    if p.exists():
        try:
            return json.loads(p.read_text())
        except Exception:
            pass
    return default


def save_state(name, obj):
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False))


# ---- one-time setup: property types + grams unit -----------------------------
def get_property_types():
    """name(lower) -> property_type dict. Used to map a nutrient key to its PropertyType id."""
    return {pt["name"].lower(): pt for pt in api_all("/api/property-type/")}


def setup_properties():
    have = get_property_types()
    created = 0
    for name, unit, fdc in NUTRIENTS:
        if name.lower() in have:
            log(f"  = {name} exists (id {have[name.lower()]['id']})")
            continue
        st, body = api("POST", "/api/property-type/",
                       {"name": name, "unit": unit, "fdc_id": fdc, "order": NKEYS.index(name.lower()) if name.lower() in NKEYS else 0})
        if st in (200, 201):
            log(f"  + created {name} (id {body['id']}, fdc {fdc})")
            created += 1
        else:
            log(f"  ! {name} failed: {st} {json.dumps(body)[:160]}")
    log(f"== property types: {created} created ==")
    return 0


_GRAMS_ID = None


def grams_unit_id():
    """id of the grams Unit (the basis for all food properties + conversions). Create if missing."""
    global _GRAMS_ID
    if _GRAMS_ID is not None:
        return _GRAMS_ID
    for u in api_all("/api/unit/"):
        if (u.get("name") or "").strip().lower() in ("g", "gram", "grams"):
            _GRAMS_ID = u["id"]
            return _GRAMS_ID
    st, body = api("POST", "/api/unit/", {"name": "g", "plural_name": "g", "description": "grams"})
    _GRAMS_ID = body["id"] if st in (200, 201) else None
    return _GRAMS_ID


# ---- Pass A: cleanup classification ------------------------------------------
JUNK_RE = re.compile(r"^\s*[^0-9A-Za-z]|[0-9]|[/+]|[(){}\[\]]")   # leading punct, any digit, separators, brackets


def normalize_name(name):
    """Dedup key: lowercase, hyphens/underscores -> space, drop punctuation, collapse whitespace."""
    s = (name or "").lower()
    s = re.sub(r"[-_]", " ", s)
    s = re.sub(r"[^a-z0-9 ]", "", s)
    return re.sub(r"\s+", " ", s).strip()


def is_junk_food(name):
    n = (name or "").strip()
    if not n:
        return "empty"
    if len(n) > 40:
        return "too long (likely a mis-split fragment)"
    if JUNK_RE.search(n):
        return "leading punctuation / embedded amount / multi-item separator"
    return None


def is_junk_unit(name):
    """Units should be measures. A unit that's punctuation or carries a food name means the
    ingredient ROW was mis-parsed (food leaked into the unit slot) — flag, don't auto-fix."""
    n = (name or "").strip()
    if not n or n in ("-", "—", "/"):
        return "empty / punctuation"
    if JUNK_RE.search(n):
        return "punctuation / amount in unit slot"
    # Known legit measures pass; anything multi-word or long is suspect (food leaked in).
    if len(n) > 18 or " " in n.strip().rstrip("s"):
        return "looks like a food name, not a measure"
    return None


def plan_cleanup():
    foods = api_all("/api/food/")
    ings = api_all("/api/ingredient/")
    # usage counts
    food_use = {}
    unit_rows = {}     # unit_id -> [ingredient ids]
    for ing in ings:
        f = ing.get("food") or {}
        u = ing.get("unit") or {}
        if f.get("id"):
            food_use[f["id"]] = food_use.get(f["id"], 0) + 1
        if u.get("id"):
            unit_rows.setdefault(u["id"], []).append(ing["id"])

    # --- dedupe clean foods by normalized name ---
    by_key = {}
    junk_foods = []
    for f in foods:
        reason = is_junk_food(f["name"])
        if reason:
            junk_foods.append({
                "id": f["id"], "name": f["name"], "reason": reason,
                "used_in_ingredients": food_use.get(f["id"], 0),
                # only safe to delete if it's used nowhere; otherwise it's a mis-parsed row -> manual.
                "action": "delete" if food_use.get(f["id"], 0) == 0 else "flag (used in a recipe row — manual edit)",
            })
            continue
        by_key.setdefault(normalize_name(f["name"]), []).append(f)

    merges = []
    for key, group in by_key.items():
        if len(group) < 2:
            continue
        # canonical = most-used, then shortest name (prefer the tidy variant).
        group.sort(key=lambda f: (-food_use.get(f["id"], 0), len(f["name"])))
        target = group[0]
        for f in group[1:]:
            merges.append({
                "from_id": f["id"], "from_name": f["name"],
                "to_id": target["id"], "to_name": target["name"],
                "key": key, "from_uses": food_use.get(f["id"], 0),
            })

    # --- junk units (food leaked into unit slot -> mis-parsed rows) ---
    units = api_all("/api/unit/")
    junk_units = []
    for u in units:
        reason = is_junk_unit(u["name"])
        if reason:
            rows = unit_rows.get(u["id"], [])
            junk_units.append({
                "id": u["id"], "name": u["name"], "reason": reason,
                "affected_ingredient_ids": rows,
                "note": "rows mis-parsed — fix the recipe by hand; not auto-fixable",
            })

    plan = {
        "generated": int(time.time()),
        "stats": {
            "foods_total": len(foods),
            "junk_foods": len(junk_foods),
            "duplicate_merges": len(merges),
            "junk_units": len(junk_units),
        },
        "merges": merges,
        "junk_foods": junk_foods,
        "junk_units": junk_units,
    }
    save_state("cleanup-plan.json", plan)
    log(f"== cleanup plan written -> {STATE/'cleanup-plan.json'} ==")
    log(f"   {plan['stats']}")
    log("   REVIEW the plan, then: ./enrich.py --apply-cleanup")
    log("   (merges rewrite recipes — pg_dump first: see ../README.md backup section)")
    return 0


def apply_cleanup():
    plan = load_state("cleanup-plan.json", None)
    if not plan:
        log("! no cleanup-plan.json — run --plan-cleanup first"); return 1
    merges = plan.get("merges", [])
    deletes = [j for j in plan.get("junk_foods", []) if j.get("action") == "delete"]
    log(f"applying: {len(merges)} merges, {len(deletes)} junk deletes "
        f"({sum(1 for j in plan.get('junk_foods', []) if j.get('action') != 'delete')} junk flagged for manual fix)")
    done = {"merge": 0, "delete": 0, "fail": 0}
    for m in merges:
        st, body = api("PUT", f"/api/food/{m['from_id']}/merge/{m['to_id']}/")
        if st in (200, 201, 204):
            done["merge"] += 1
            vlog(f"  merged {m['from_name']!r} -> {m['to_name']!r}")
        else:
            done["fail"] += 1
            log(f"  ! merge {m['from_id']}->{m['to_id']} failed: {st} {json.dumps(body)[:120]}")
    for j in deletes:
        st, body = api("DELETE", f"/api/food/{j['id']}/")
        if st in (200, 204):
            done["delete"] += 1
            vlog(f"  deleted junk {j['name']!r}")
        else:
            done["fail"] += 1
            log(f"  ! delete {j['id']} failed: {st}")
    log(f"== cleanup applied: {done} ==")
    return 0


# ---- Pass B: lookups ---------------------------------------------------------
def usda_lookup(name):
    """Return {'macros': {key: per100g}, 'fdc_id': int, 'desc': str, 'portions': [...]} or None."""
    if not USDA_KEY:
        return None
    q = urllib.parse.urlencode({
        "query": name, "api_key": USDA_KEY, "pageSize": 5,
        "dataType": "Foundation,SR Legacy",          # analytical reference foods (full per-100g macros)
    })
    data = http_json(f"https://api.nal.usda.gov/fdc/v1/foods/search?{q}")
    if not data or not data.get("foods"):
        return None
    # Match on nutrientId (1008, 1003, ...), NOT nutrientNumber ("208","203", ...). Calories and
    # sugar have alternate ids on some foods, so fall back. Pick the first result with real macros.
    CAL = (1008, 2048, 2047)        # Energy; else Atwater specific / general
    SUGAR = (2000, 1063)            # Total Sugars; else Sugars (NLEA)
    direct = {1003: "protein", 1005: "carbohydrates", 1004: "fat", 1079: "fiber"}
    qwords = [w for w in re.findall(r"[a-z]+", name.lower()) if len(w) > 2]
    cands = []                                               # (-overlap, idx, food, macros) for stable best
    for idx, food in enumerate(data["foods"]):
        by_id = {n["nutrientId"]: float(n["value"]) for n in food.get("foodNutrients", [])
                 if n.get("nutrientId") is not None and n.get("value") is not None}
        macros = {key: round(by_id[nid], 2) for nid, key in direct.items() if nid in by_id}
        for nid in CAL:
            if nid in by_id: macros["calories"] = round(by_id[nid], 2); break
        for nid in SUGAR:
            if nid in by_id: macros["sugar"] = round(by_id[nid], 2); break
        if "calories" not in macros or len(macros) < 4:      # skip nutrient-less / partial entries
            continue
        desc = (food.get("description") or "").lower()
        overlap = sum(1 for w in qwords if w in desc)        # how many query words the desc actually contains
        cands.append((-overlap, idx, food, macros))
    if not cands:
        return None
    cands.sort()                                             # best query-overlap first; ties keep USDA order
    _, _, food, macros = cands[0]
    return {"macros": macros, "fdc_id": food.get("fdcId"),
            "desc": food.get("description", ""), "portions": food.get("foodPortions", [])}


def searx_snippets(name, n=5):
    """Web nutrition snippets from the standalone SearXNG JSON API. [] on failure (degrade to USDA-only)."""
    q = urllib.parse.urlencode({"q": f"{name} nutrition facts per 100g", "format": "json"})
    data = http_json(f"{SEARX}/search?{q}", timeout=30)
    if not data:
        return []
    out = []
    for r in data.get("results", [])[:n]:
        snip = (r.get("content") or "").strip()
        if snip:
            out.append({"title": r.get("title", "")[:120], "url": r.get("url", ""), "snippet": snip[:400]})
    return out


GEMMA_SCHEMA = {
    "type": "object",
    "properties": {
        **{k: {"type": "number"} for k in NKEYS},
        "confidence": {"type": "number"},
        "source": {"type": "string", "enum": ["usda", "web", "estimate"]},
        "agreement": {"type": "boolean"},
        "notes": {"type": "string"},
    },
    "required": NKEYS + ["confidence", "source", "agreement"],
}


def gemma_reconcile(name, usda, snippets):
    """Reconcile USDA + web into per-100 g macros via Ollama (JSON mode). None if model unavailable."""
    sys_p = (
        "You are a nutrition data reconciler. Given a food name plus a USDA candidate and web search "
        "snippets, output per-100-gram values for exactly these nutrients: calories (kcal), protein, "
        "carbohydrates, fat, fiber, sugar (grams). Rules: prefer USDA when present and consistent with "
        "the web; NEVER average a real value with a number you are unsure about; if USDA and web "
        "disagree by more than ~25% on the macros, set agreement=false and lower confidence. Set "
        "source to 'usda', 'web', or 'estimate'. confidence is 0..1. Respond with JSON only."
    )
    usda_txt = json.dumps(usda["macros"]) + f" (USDA: {usda['desc']})" if usda else "none"
    web_txt = "\n".join(f"- {s['snippet']}" for s in snippets) or "none"
    user_p = f"Food: {name}\nUSDA per-100g candidate: {usda_txt}\nWeb snippets:\n{web_txt}"
    payload = {
        "model": MODEL, "stream": False, "format": GEMMA_SCHEMA,
        "options": {"temperature": 0},
        "messages": [{"role": "system", "content": sys_p}, {"role": "user", "content": user_p}],
    }
    try:
        st, body = _req(f"{OLLAMA}/api/chat", data=json.dumps(payload).encode(),
                        headers={"Content-Type": "application/json"}, method="POST", timeout=180)
        msg = json.loads(body)["message"]["content"]
        return json.loads(msg)
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read().decode()[:160]
        except Exception:
            pass
        log(f"    ! ollama {e.code} (model {MODEL!r} pulled?) {detail}")
        return None
    except Exception as e:
        vlog(f"    ! reconcile fail: {type(e).__name__}: {e}")
        return None


# ---- Pass B: write to Tandoor ------------------------------------------------
def write_food_macros(food, macros, fdc_id, pt_by_key):
    """PATCH the Food's nested properties (basis 100 g) + fdc_id. Merges with existing props by type."""
    g = grams_unit_id()
    existing = {p["property_type"]["id"]: p for p in food.get("properties", []) if p.get("property_type")}
    for key in NKEYS:
        if key not in macros:
            continue
        pt = pt_by_key.get(key)
        if not pt:
            continue
        existing[pt["id"]] = {"property_amount": round(float(macros[key]), 2),
                             "property_type": {"id": pt["id"], "name": pt["name"]}}
    payload = {
        "properties": list(existing.values()),
        "properties_food_amount": 100,
        "properties_food_unit": {"id": g, "name": "g"},
    }
    if fdc_id:
        payload["fdc_id"] = int(fdc_id)
    st, body = api("PATCH", f"/api/food/{food['id']}/", payload)
    return st in (200, 201), body


def ensure_conversions(food, used_units, usda):
    """For each non-gram unit actually used with this food, ensure a UnitConversion to grams exists.
    USDA foodPortions first, then a Gemma density estimate; only units neither can resolve are returned
    as missing — a missing conversion silently undercounts the roll-up, so callers log these. Returns
    list of unit names left without a conversion."""
    g = grams_unit_id()
    # NOTE: Tandoor's ?food= filter is ignored by this endpoint (returns ALL conversions), so we
    # MUST filter by food client-side. A global `have` set would skip a food's needed conversion
    # whenever an earlier food already used the same unit id — silently breaking its roll-up.
    existing = [c for c in api_all("/api/unit-conversion/") if (c.get("food") or {}).get("id") == food["id"]]
    have = {(c.get("base_unit") or {}).get("id") for c in existing}
    portions = (usda or {}).get("portions") or []
    missing = []
    for u in used_units:
        uid, uname = u["id"], (u["name"] or "").strip()
        if uid == g or uname.lower() in ("g", "gram", "grams") or uid in have:
            continue
        grams, src = _portion_grams(uname, portions), "usda"
        if grams is None:
            grams, src = gemma_grams(food["name"], uname), "estimate"
        if grams is None:
            missing.append(uname)
            continue
        api("POST", "/api/unit-conversion/", {
            "base_amount": 1, "base_unit": {"id": uid, "name": uname},
            "converted_amount": round(grams, 2), "converted_unit": {"id": g, "name": "g"},
            "food": {"id": food["id"], "name": food["name"]},
        })
        vlog(f"    conv 1 {uname} = {round(grams,2)} g ({src})")
    return missing


_GRAMS_SCHEMA = {"type": "object",
                 "properties": {"grams": {"type": "number"}, "confidence": {"type": "number"}},
                 "required": ["grams"]}


def gemma_grams(food_name, unit_name):
    """Estimate grams for 1 <unit_name> of <food_name> via Ollama (density fallback). None if unavailable
    or implausible. Cheap one-shot; conservative — rejects non-positive / absurd values."""
    payload = {
        "model": MODEL, "stream": False, "format": _GRAMS_SCHEMA, "options": {"temperature": 0},
        "messages": [
            {"role": "system", "content": "Estimate the mass in grams of ONE given unit of a food "
             "(e.g. 1 cup of flour ~= 120 g, 1 teaspoon of active dry yeast ~= 3 g). Respond JSON only "
             "with grams (number) and confidence 0..1. If the unit is not a real measure, set grams to 0."},
            {"role": "user", "content": f"1 {unit_name} of {food_name}"},
        ],
    }
    try:
        st, body = _req(f"{OLLAMA}/api/chat", data=json.dumps(payload).encode(),
                        headers={"Content-Type": "application/json"}, method="POST", timeout=120)
        out = json.loads(json.loads(body)["message"]["content"])
        grams = float(out.get("grams", 0))
        return grams if 0 < grams < 5000 else None
    except Exception as e:
        vlog(f"    ! gemma_grams fail: {type(e).__name__}")
        return None


def _portion_grams(unit_name, portions):
    """Grams for 1 <unit_name> from USDA foodPortions, matching the measure/modifier by name. None if absent."""
    un = unit_name.lower().rstrip("s")
    for p in portions:
        amt = p.get("amount") or 1
        gw = p.get("gramWeight")
        label = (p.get("modifier") or "") + " " + ((p.get("measureUnit") or {}).get("name") or "")
        if gw and amt and un and un in label.lower():
            return float(gw) / float(amt)
    return None


# ---- Pass B: per-food orchestration ------------------------------------------
def enrich_food(food, used_units, pt_by_key, tau, dry_run, enriched, review):
    name = food["name"]
    usda = usda_lookup(name)
    snippets = searx_snippets(name)
    vlog(f"  · {name}: usda={'y' if usda else 'n'} web={len(snippets)}")
    rec = gemma_reconcile(name, usda, snippets)

    if not rec:
        review[str(food["id"])] = {"name": name, "reason": "reconcile-unavailable",
                                   "usda": bool(usda), "web": len(snippets), "ts": int(time.time())}
        return "review"

    macros = {k: rec[k] for k in NKEYS if isinstance(rec.get(k), (int, float))}
    conf = float(rec.get("confidence", 0))
    agree = bool(rec.get("agreement", False))
    source = rec.get("source", "estimate")
    if source == "usda" and not usda:
        source = "web" if snippets else "estimate"   # honesty: can't claim USDA if we never consulted it

    # Atwater sanity: kcal must roughly equal 4*protein + 4*carb + 9*fat. Catches internally
    # inconsistent macro sets a model can emit confidently (e.g. 20 kcal but 48 g carb) — the
    # deterministic honesty rail that works even web-only, with no USDA to cross-check against.
    atwater = ""
    if "calories" in macros:
        implied = 4 * macros.get("protein", 0) + 4 * macros.get("carbohydrates", 0) + 9 * macros.get("fat", 0)
        cal = macros["calories"]
        if max(cal, implied) > 20 and abs(implied - cal) > 0.4 * max(cal, implied):
            agree = False                              # force to review with a clear reason
            atwater = f" atwater:{cal:.0f}vs{implied:.0f}"

    ok = conf >= tau and agree and len(macros) >= 4    # need the core macros, agreeing, confident

    if dry_run:
        log(f"  DRY {name}: conf={conf:.2f} agree={agree} src={source}{atwater} {macros}")
        return "dry"

    if not ok:
        review[str(food["id"])] = {"name": name, "reason": f"conf={conf:.2f} agree={agree}{atwater}",
                                   "macros": macros, "source": source, "ts": int(time.time())}
        vlog(f"  ~ review {name} (conf {conf:.2f}, agree {agree}{atwater})")
        return "review"

    fdc_id = usda["fdc_id"] if (source == "usda" and usda) else None
    wrote, body = write_food_macros(food, macros, fdc_id, pt_by_key)
    if not wrote:
        log(f"  ! write failed {name}: {json.dumps(body)[:140]}")
        return "error"
    missing = ensure_conversions(food, used_units, usda)
    enriched[str(food["id"])] = {"name": name, "macros": macros, "source": source,
                                 "confidence": conf, "fdc_id": fdc_id,
                                 "missing_conversions": missing, "ts": int(time.time())}
    flag = f"  (missing conv: {', '.join(missing)})" if missing else ""
    log(f"  + {name}: {source} conf {conf:.2f}{flag}")
    return "written"


def run_passB(args):
    pt_by_key = {}
    pts = get_property_types()
    for key in NKEYS:
        pt = pts.get(NAME_BY_KEY[key].lower())
        if pt:
            pt_by_key[key] = pt
    if len(pt_by_key) < len(NKEYS):
        log("! property types missing — run --setup-properties first"); return 1
    if not USDA_KEY:
        log("! note: no ~/.config/eww/usda-key — USDA skipped, reconcile uses web only")
    if MODEL == "gemma3n:e4b":
        vlog(f"  model: {MODEL} (override with ENRICH_MODEL or ~/.config/eww/ollama-model)")

    foods = api_all("/api/food/")
    ings = api_all("/api/ingredient/")
    # (food_id -> {unit_id: unit}) for the conversion-coverage step
    units_by_food = {}
    for ing in ings:
        f, u = ing.get("food") or {}, ing.get("unit") or {}
        if f.get("id") and u.get("id"):
            units_by_food.setdefault(f["id"], {})[u["id"]] = u

    enriched = load_state("enriched.json", {})
    review = load_state("review-macros.json", {})

    id_filter = {int(x) for x in args.food_id.split(",")} if args.food_id else None
    todo = []
    for f in foods:
        if id_filter is not None:
            if f["id"] in id_filter:
                todo.append(f)                         # explicit ids: enrich exactly these (debug)
            continue
        if is_junk_food(f["name"]):
            continue                                   # cleanup handles junk; never enrich it
        if args.food and args.food.lower() not in f["name"].lower():
            continue
        if not args.food and not args.backfill and str(f["id"]) in enriched:
            continue                                   # incremental: skip already-enriched
        todo.append(f)
    if args.limit:
        todo = todo[:args.limit]
    mode = "by-id" if args.food_id else ("backfill" if args.backfill else ("one" if args.food else "incremental"))
    log(f"== Pass B: {len(todo)} foods to enrich ({mode}) ==")

    totals = {"written": 0, "review": 0, "error": 0, "dry": 0}
    for i, f in enumerate(todo, 1):
        used = list(units_by_food.get(f["id"], {}).values())
        status = enrich_food(f, used, pt_by_key, args.tau, args.dry_run, enriched, review)
        totals[status] = totals.get(status, 0) + 1
        if not args.dry_run and i % 10 == 0:
            save_state("enriched.json", enriched); save_state("review-macros.json", review)
    if not args.dry_run:
        save_state("enriched.json", enriched); save_state("review-macros.json", review)
    log(f"== done: {totals} ==")
    return 0


# ---- main --------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Cooking macro-enrichment engine (Phase 2a)")
    ap.add_argument("--setup-properties", action="store_true", help="create the 6 nutrient PropertyTypes (one-time)")
    ap.add_argument("--plan-cleanup", action="store_true", help="write cleanup-plan.json (no mutation)")
    ap.add_argument("--apply-cleanup", action="store_true", help="execute approved merges/deletes from the plan")
    ap.add_argument("--backfill", action="store_true", help="Pass B over ALL clean foods")
    ap.add_argument("--food", help="enrich only foods whose name contains this (debug)")
    ap.add_argument("--food-id", help="enrich exactly these food ids, comma-separated (debug)")
    ap.add_argument("--tau", type=float, default=0.7, help="confidence threshold to write (default 0.7)")
    ap.add_argument("--limit", type=int, default=0, help="cap foods processed in Pass B (testing)")
    ap.add_argument("--dry-run", action="store_true", help="match + reconcile, write nothing")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    global VERBOSE
    VERBOSE = args.verbose

    if args.setup_properties:
        return setup_properties()
    if args.plan_cleanup:
        return plan_cleanup()
    if args.apply_cleanup:
        return apply_cleanup()
    return run_passB(args)


if __name__ == "__main__":
    sys.exit(main())
