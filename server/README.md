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

## Run
```sh
cd server
docker compose up -d            # only busy while fetching
```
Folders `config/ downloads/ library/` are created next to the compose file. Configure the UIs
from a browser: **Lidarr** :8686 · **Prowlarr** :9696 · **qBittorrent** :8080.

Wiring: qBittorrent save path `/downloads`; Prowlarr → add indexers + add Lidarr under
Settings→Apps; Lidarr → add qBittorrent as download client, root folder `/music`.

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
