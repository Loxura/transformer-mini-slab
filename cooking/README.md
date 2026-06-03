# Cooking backend — Tandoor Recipes (the cooking conveyor)

Runs on the **mainframe** (this box, same one as `server/`). Backs the deck's **Cooking tab (ws3)**.
Design + rationale: `docs/proposals/2026-06-03-cooking-tab-plan.md`. Thesis: a *takeout interceptor* —
the meal is decided ahead, so the tired-night deck just says "cook / reheat this," one tap to steps.

```
recipe-ingest watcher  --POST /api/recipe-from-source/-->  Tandoor  <--curl reads meal plan + steps--  deck (ws3)
   (polls food-blog feeds)                                (this stack)                                  phone plans here too
```

Two containers only — Tandoor 2.x bundles nginx in the web image (no separate proxy/redis). Isolated
from the music stack: it does **not** touch gluetun's VPN netns; plain LAN HTTP is correct.

## Run
```sh
cd cooking
cp .env.example .env
# generate secrets and drop them into .env:
#   SECRET_KEY:        head -c50 /dev/urandom | base64
#   POSTGRES_PASSWORD: head -c24 /dev/urandom | base64
docker compose up -d
```
Then open **http://<mainframe>:8090** and:
1. **Register the first account** — it becomes the superuser.
2. **Create a Space** (Tandoor is space-scoped; the API token's user needs one).
3. Settings → **API → generate a read-write token** (the deck client + ingest watcher use it;
   store it OUTSIDE the repo, like `gcal-url`). Header: `Authorization: Bearer <token>`.
4. Set `ENABLE_SIGNUP=0` in `.env` and `docker compose up -d` again to lock signup.

Data lives in **named docker volumes** (`pgdata`, `mediafiles`, `staticfiles`), NOT `./` bind mounts:
the repo is on `/mnt/c` (DrvFs), where Postgres `initdb` can't set permissions — bind-mounting the DB
there fails. Named volumes sit on the Linux VM's ext4 instead. Back up before version bumps (migrations
run on update):
```sh
docker compose exec db_recipes pg_dump -U djangouser djangodb > tandoor-db-backup.sql
docker run --rm -v cooking_mediafiles:/m -v "$PWD":/out alpine tar czf /out/mediafiles-backup.tgz -C /m .
```

## Verify
```sh
docker compose ps
curl -sI http://localhost:8090/ | head -1          # expect HTTP 200/302
curl -s  http://localhost:8090/openapi/ | head -c 200   # OpenAPI schema (also Swagger at /docs/swagger/)
```

## LAN reachability — ALREADY WORKS (no WSL fix needed)
Docker runs under **Docker Desktop** (WSL integration), NOT native docker in NAT-mode WSL. Docker
Desktop publishes the container port straight to the **Windows host's `0.0.0.0:8090`**, bypassing
WSL's NAT, and ships an inbound-allow firewall rule ("Docker Desktop Backend"). The home LAN adapter
(192.168.0.30) is on the **Private** profile. Net result, verified 2026-06-03: the tablet/phone can
reach Tandoor at **`http://192.168.0.30:8090`** with no `.wslconfig`/mirrored-mode/portproxy change.
(An earlier note here recommended mirrored networking — that was based on a wrong NAT assumption; do
NOT do it, mirrored mode can actually disrupt Docker Desktop's networking.)

Confirm from a phone: browse to `http://192.168.0.30:8090` on the LAN. If a future Windows/Docker
update ever breaks it, the fallback is an elevated `netsh ... portproxy` to the WSL IP, but it's not
needed today.

Then on the **tablet**, point the deck client at the LAN URL:
`echo http://192.168.0.30:8090 > ~/.config/eww/tandoor-url` and copy the token to
`~/.config/eww/tandoor-token` (chmod 600). Until this is done, the tablet's Cook tab shows
"NO MEAL LOADED" (the deck only reaches Tandoor over the LAN; the sandbox uses localhost).

## Notes
- API surface, auth, pagination, the `/api/recipe-from-source/` import endpoint, and the on-hand/
  meal-plan endpoints are documented in the proposal doc's research-pass section.
- Meal-plan API (verified 2026-06-03): `POST /api/meal-plan/` requires `servings`, `from_date`,
  `meal_type` (an id from `/api/meal-type/` — create one, e.g. "Dinner", first); `recipe` is a nested
  `{id,name}`. The deck's `cook` resolves today's entry via `?from_date=&to_date=`.
- Always-on caveat: if this box sleeps, the deck can't fetch the plan — plan to cache the week's plan
  on the deck so tonight's card still renders when the mainframe is down. (Future work.)
