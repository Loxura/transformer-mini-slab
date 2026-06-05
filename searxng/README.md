# SearXNG — self-hosted metasearch (standalone)

Runs on the **mainframe** (same box as `server/` and `cooking/`). Two jobs, one container:

1. **A private web search UI** for personal use — open `http://<mainframe>:8091`, no ads, no tracking.
2. **A JSON search API** that the cooking **macro-enricher** (`cooking/enrich/enrich.py`) consumes to
   cross-check nutrition facts against USDA.

It is deliberately its **own** top-level stack (not folded into `cooking/`): it goes up/down on its
own, is generally useful, and is easy to expand (add engines, plugins) later. The enricher is just one
consumer; if SearXNG is down the enricher degrades to USDA-only.

## Run
```sh
cd searxng
cp settings.yml.example settings.yml
# generate the secret_key (the real settings.yml is gitignored, mounted read-only):
sed -i "/^  secret_key:/s|\"[^\"]*\"|\"$(head -c50 /dev/urandom | base64 | tr -d '\n')\"|" settings.yml
docker compose up -d
```
Then open **http://<mainframe>:8091**.

## Verify
```sh
docker compose ps
curl -sI http://localhost:8091/ | head -1                          # expect HTTP 200
# JSON API (what the enricher uses) — should return {"results":[...], ...}:
curl -s 'http://localhost:8091/search?q=chicken+breast+nutrition+facts+per+100g&format=json' | head -c 300
```
If `format=json` returns an HTTP 403 / "Forbidden", confirm `search.formats` in `settings.yml`
includes `json` and that the container was restarted after editing it.

## Notes
- **Secret handling** mirrors the rest of the repo (`.env`/`.env.example`): only
  `settings.yml.example` is committed (placeholder secret); the real `settings.yml` is **gitignored**
  and holds the generated `secret_key`. It's mounted **read-only**, so the secret never enters git and
  the container can't rewrite it. (The image logs a harmless `chown: settings.yml: Read-only file
  system` warning because of the ro mount.)
- **Engine noise in logs is expected and non-fatal**: darknet engines (`ahmia`, `torch`) need Tor and
  go inactive; `brave`/`google` occasionally rate-limit or fail to parse. Results still aggregate from
  the healthy engines (DuckDuckGo, Wikipedia, etc.) — the nutrition queries return 20+ hits.
- **LAN-only.** `limiter: false` + `public_instance: false` keep the JSON API reachable from the
  enricher without a referer/rate-limit dance. Do **not** expose port 8091 to the internet with these
  settings.
