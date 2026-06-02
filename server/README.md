# Music fetcher (PC side) — transient conveyor

Runs on the **main PC**. The PC does the heavy lifting and only holds files **in-flight**;
finished albums are shipped to the tablet and the local staging is **flushed**. The tablet
holds the permanent library and plays it (PC off).

```
Lidarr (want-list) + Prowlarr + qBittorrent
  download -> Lidarr imports/organises -> ./library (staging)
        sync-to-tablet.sh:  rsync --remove-source-files  (copy, then delete source)
  -> tablet ~/Music (permanent) -> mpd auto-update -> play ;  PC staging flushed
```

## Prerequisites
Docker + compose. Windows: **Docker Desktop** (enable WSL integration), or
`sudo apt install docker.io docker-compose-v2` in WSL. Plus `rsync` + `ssh` (for the ship step;
the WSL→tablet SSH key is already set up).

## VPN — qBittorrent behind Mullvad (gluetun, kill-switched)
qBittorrent runs inside gluetun's network namespace, so torrent traffic exits **only** through
Mullvad WireGuard; if the tunnel drops, qBit is cut off (no IP leak). Prowlarr/Lidarr use the
normal connection (just searches/metadata).
1. Mullvad → **Account → WireGuard configuration** → generate a key; note the **PrivateKey** + **Address**.
2. `cp .env.example .env`, paste them in. **`.env` is gitignored — never commit it.**

## Run
```sh
cd server
cp .env.example .env        # then edit .env with your Mullvad key + address
docker compose up -d
```
Folders `config/ downloads/ library/` are created next to the compose file. Configure the UIs
from a browser: **Lidarr** :8686 · **Prowlarr** :9696 · **qBittorrent** :8080.

Confirm the VPN is actually up before downloading:
```sh
docker compose exec gluetun wget -qO- https://am.i.mullvad.net/connected
```

Wiring: qBittorrent save path `/downloads`; Prowlarr → add indexers + add Lidarr under
Settings→Apps; Lidarr → **Download Clients → qBittorrent, host `gluetun`, port `8080`**
(not `localhost` — qBit lives in gluetun's network), root folder `/music`.

## Ship + flush
```sh
./sync-to-tablet.sh            # copies ./library -> tablet:~/Music, deletes shipped files
```
Automate it on a timer (every 10 min):
```sh
*/10 * * * * /full/path/server/sync-to-tablet.sh >> ~/sync-tablet.log 2>&1
```
Override the target if needed: `TABLET=minideck@192.168.0.43 ./sync-to-tablet.sh`.

## The one Lidarr gotcha
Lidarr expects its library files to *stay put*; we flush them after shipping, so Lidarr will
mark those albums "missing." To stop it re-downloading:
- **Don't enable** automatic missing-album search / RSS sync, **or**
- unmonitor albums after they're fetched.

Treat Lidarr here as a **fetch-and-forward** engine (add to want-list → it grabs + organises
once → conveyor ships it → done), not a permanent library manager. The permanent library is
the tablet.
