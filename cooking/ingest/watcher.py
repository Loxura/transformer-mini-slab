#!/usr/bin/env python3
"""
Cooking conveyor — recipe-ingest watcher.

Polls the approved food-blog feeds/sitemaps, and for each NEW recipe URL:
  1. fetches the page HTML ourselves (browser UA, polite per-host rate-limit) — we must fetch,
     not let Tandoor fetch, because some sites 403 Tandoor's server-side fetcher;
  2. hands {url, data: html} to Tandoor's POST /api/recipe-from-source/ (Tandoor parses it via
     recipe-scrapers and returns a structured `recipe` dict, and a `duplicates` list);
  3. skips if it's not a real recipe (no steps) or already imported (duplicates / local seen-set);
  4. role-classifies batch vs quick (working+waiting time; bucket_default as fallback);
  5. creates it via POST /api/recipe/ with keywords [<role>, auto-ingest].

Stdlib only — no pip needed. Config: ~/.config/eww/tandoor-url + tandoor-token.
State (gitignored): cooking/ingest/state/{seen.json,feeds.json}.

Usage:
  ./watcher.py                       # poll all sources' feeds
  ./watcher.py --source "Budget"     # only sources whose name contains "Budget"
  ./watcher.py --limit 5             # stop after creating 5 recipes this run
  ./watcher.py --dry-run             # scrape + classify, but DON'T create
  ./watcher.py --backfill            # walk sitemaps instead of feeds (catch older posts)
  ./watcher.py -v                    # verbose
"""
import argparse, json, os, re, subprocess, sys, tempfile, time, urllib.request, urllib.error
import xml.etree.ElementTree as ET
from urllib.parse import urlparse
from pathlib import Path

HERE = Path(__file__).resolve().parent
STATE = HERE / "state"
CFG = Path.home() / ".config" / "eww"
UA = "RecipeWatcher/1.0 (+mailto:blues@computerblues.net)"
BROWSER_UA = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
MIN_HOST_DELAY = 2.0            # seconds between requests to the same host
ROUNDUP_SLUG = re.compile(r"/(best-|top-?\d+|how-to-|guide|roundup|recipes-)|-recipes/?$|/category/", re.I)
NONHTML_EXT = re.compile(r"\.(jpe?g|png|gif|webp|svg|pdf|mp4|mov|css|js|xml|zip)(\?|$)", re.I)

BASE = open(CFG / "tandoor-url").read().strip()
TOKEN = open(CFG / "tandoor-token").read().strip()
APIH = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}

_last_hit = {}   # host -> last request monotonic time


def log(*a): print(*a, file=sys.stderr, flush=True)


def host_of(url): return urlparse(url).netloc


def normalize_url(url):
    """Strip query string + fragment so RSS tracking params (?utm_*, ?adt_ei=...) don't
    pollute the seen-set key or the stored source_url. WP recipe post URLs are canonical w/o them."""
    return urlparse(url)._replace(query="", fragment="").geturl()


def polite(url):
    h = host_of(url)
    wait = MIN_HOST_DELAY - (time.monotonic() - _last_hit.get(h, 0))
    if wait > 0: time.sleep(wait)
    _last_hit[h] = time.monotonic()


def http_get(url, ua=BROWSER_UA, extra=None, timeout=30):
    polite(url)
    headers = {"User-Agent": ua, "Accept": "*/*"}
    if extra: headers.update(extra)
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, dict(r.headers), r.read()


def api(method, path, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=data, headers=APIH, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try: body = json.loads(e.read().decode())
        except Exception: body = {"_raw": "<unparseable>"}
        return e.code, body


# ---- state -------------------------------------------------------------------
def load_state(name, default):
    p = STATE / name
    if p.exists():
        try: return json.loads(p.read_text())
        except Exception: pass
    return default


def save_state(name, obj):
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / name).write_text(json.dumps(obj, indent=1, ensure_ascii=False))


# ---- feed / sitemap parsing --------------------------------------------------
def links_from_feed(xml_bytes):
    """RSS <item><link> and Atom <entry><link href>."""
    out = []
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        return re.findall(r"<link>(https?://[^<]+)</link>", xml_bytes.decode("utf-8", "replace"))
    for item in root.iter():
        tag = item.tag.split("}")[-1]
        if tag in ("item", "entry"):
            for child in item:
                ct = child.tag.split("}")[-1]
                if ct == "link":
                    href = (child.text or "").strip() or child.attrib.get("href", "").strip()
                    if href: out.append(href); break
    return out


def links_from_sitemap(xml_bytes):
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        return re.findall(r"<loc>(https?://[^<]+)</loc>", xml_bytes.decode("utf-8", "replace"))
    return [el.text.strip() for el in root.iter() if el.tag.split("}")[-1] == "loc" and el.text]


# ---- core per-URL pipeline ---------------------------------------------------
def classify(rec, bucket_default):
    total = (rec.get("working_time") or 0) + (rec.get("waiting_time") or 0)
    if total > 0:
        return "quick" if total <= 30 else "batch", total
    return (bucket_default or "batch"), total


def normalize_orders(steps):
    for si, step in enumerate(steps):
        step["order"] = si
        for ii, ing in enumerate(step.get("ingredients", [])):
            ing["order"] = ii


def set_image(rid, html):
    """Give the new recipe a photo from the page's og:image (we already have the HTML).
    Uploads via curl multipart (Tandoor's PUT /api/recipe/<id>/image/)."""
    m = re.search(rb'<meta[^>]+property="og:image"[^>]*content="([^"]+)"', html)
    if not m:
        return
    try:
        st, _, img = http_get(m.group(1).decode("utf-8", "replace"))
    except Exception:
        return
    if st != 200 or not img:
        return
    f = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
    try:
        f.write(img); f.close()
        subprocess.run(["curl", "-s", "-o", "/dev/null", "-X", "PUT",
                        "-H", f"Authorization: Bearer {TOKEN}", "-F", f"image=@{f.name}",
                        f"{BASE}/api/recipe/{rid}/image/"], timeout=30)
    except Exception:
        pass
    finally:
        os.unlink(f.name)


def import_url(url, bucket_default, dry_run):
    """Returns ('created', id) | ('dup', None) | ('skip', reason) | ('error', msg)."""
    try:
        st, _, html = http_get(url)
    except urllib.error.HTTPError as e:
        return "skip", f"fetch {e.code}"
    except Exception as e:
        return "skip", f"fetch {type(e).__name__}"
    if st != 200 or not html:
        return "skip", f"fetch status {st}"

    st, scr = api("POST", "/api/recipe-from-source/", {"url": url, "data": html.decode("utf-8", "replace")})
    if scr.get("duplicates"):
        return "dup", None
    rec = scr.get("recipe")
    if scr.get("error") or not rec or not rec.get("steps"):
        return "skip", (scr.get("msg") or "no recipe/steps")
    if not sum(len(s.get("ingredients", [])) for s in rec.get("steps", [])):
        return "skip", "no ingredients"   # unusable for cooking; don't pollute the pool

    role, total = classify(rec, bucket_default)
    if dry_run:
        return "created", f"DRY {rec.get('name')!r} [{role}, {total}min]"

    normalize_orders(rec["steps"])
    payload = {
        "name": rec["name"][:128],
        "description": (rec.get("description") or "")[:512],
        "servings": int(rec.get("servings") or 1),
        "working_time": int(rec.get("working_time") or 0),
        "waiting_time": int(rec.get("waiting_time") or 0),
        "source_url": rec.get("source_url") or url,
        "internal": True,
        "keywords": [{"name": role}, {"name": "auto-ingest"}],
        "steps": rec["steps"],
    }
    st, created = api("POST", "/api/recipe/", payload)
    if st in (200, 201):
        try: set_image(created["id"], html)   # give it a photo from the page's og:image
        except Exception: pass
        return "created", created["id"]
    return "error", json.dumps(created)[:200]


# ---- main --------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", help="only sources whose name contains this (case-insensitive)")
    ap.add_argument("--limit", type=int, default=0, help="max recipes to CREATE this run, total (0 = no cap)")
    ap.add_argument("--per-source", type=int, default=0, help="max recipes to CREATE per source (fair share; good for cron)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--backfill", action="store_true", help="walk sitemaps instead of feeds")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    cfg = json.loads((HERE / "sources.json").read_text())["sources"]
    if args.source:
        cfg = [s for s in cfg if args.source.lower() in s["name"].lower()]
    if not cfg:
        log("no matching sources"); return 1

    seen = load_state("seen.json", {})       # url -> {status, id, role, name, ts}
    feeds = load_state("feeds.json", {})      # feed_url -> {etag, last_modified}
    created_count = 0
    totals = {"created": 0, "dup": 0, "skip": 0, "error": 0}

    for s in cfg:
        feed_url = s["url"]
        log(f"\n# {s['name']}  ({'sitemap' if args.backfill or s['type']=='sitemap' else 'feed'})")
        # conditional GET on the feed itself
        cond = {}
        meta = feeds.get(feed_url, {})
        if not args.backfill:
            if meta.get("etag"): cond["If-None-Match"] = meta["etag"]
            if meta.get("last_modified"): cond["If-Modified-Since"] = meta["last_modified"]
        try:
            st, hdrs, body = http_get(feed_url, extra=cond)   # browser UA — some feeds 403/JS-wall a plain UA
        except urllib.error.HTTPError as e:
            if e.code == 304:
                log("  304 not modified — nothing new"); continue
            log(f"  feed fetch failed: HTTP {e.code}"); continue
        except Exception as e:
            log(f"  feed fetch error: {type(e).__name__}: {e}"); continue

        if not args.backfill:
            feeds[feed_url] = {"etag": hdrs.get("ETag", ""), "last_modified": hdrs.get("Last-Modified", "")}

        urls = links_from_sitemap(body) if (args.backfill or s["type"] == "sitemap") else links_from_feed(body)
        # keep only same-site recipe-ish post URLs, newest first, drop obvious roundups & already-seen
        site = host_of(feed_url)
        cands = []
        for u in urls:
            u = normalize_url(u)
            if host_of(u) != site: continue
            if u.rstrip("/") == f"https://{site}" or "/feed" in u: continue
            if NONHTML_EXT.search(u): continue          # skip image/asset URLs (sitemaps list them)
            if ROUNDUP_SLUG.search(u): continue
            if u in seen: continue
            cands.append(u)
        # de-dup preserve order
        cands = list(dict.fromkeys(cands))
        log(f"  {len(urls)} links, {len(cands)} new candidates")

        src_created = 0
        for u in cands:
            if args.limit and created_count >= args.limit:
                log("  hit --limit, stopping"); save_state("seen.json", seen); save_state("feeds.json", feeds); _summary(totals); return 0
            if args.per_source and src_created >= args.per_source:
                log("  hit --per-source, next source"); break
            status, info = import_url(u, s.get("bucket_default"), args.dry_run)
            totals[status] = totals.get(status, 0) + 1
            rec = {"status": status, "ts": int(time.time()), "source": s["name"]}
            if status == "created":
                created_count += 1; src_created += 1
                if args.dry_run:
                    log(f"  + {info}")
                    rec["info"] = info
                else:
                    rec["id"] = info; log(f"  + created #{info}  {u}")
            elif status == "dup":
                if args.verbose: log(f"  = dup        {u}")
            elif status == "skip":
                if args.verbose: log(f"  - skip ({info})  {u}")
            else:
                log(f"  ! ERROR ({info})  {u}")
            if not (args.dry_run and status == "created"):
                seen[u] = rec   # don't poison seen-set on dry-run "would-create"

        save_state("seen.json", seen)
        save_state("feeds.json", feeds)

    _summary(totals)
    return 0


def _summary(t):
    log(f"\n== done: {t.get('created',0)} created, {t.get('dup',0)} dup, {t.get('skip',0)} skip, {t.get('error',0)} error ==")


if __name__ == "__main__":
    sys.exit(main())
