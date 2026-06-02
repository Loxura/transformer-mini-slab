# Music fetcher (PC side)

Runs on the **main PC** (not the tablet). Builds a music library, then **Syncthing**
replicates it to the tablet's `~/Music` (P2P, no cloud). The tablet plays locally — works
with the PC off.

## Prerequisites
Docker + the compose plugin. On Windows: **Docker Desktop** (manages the WSL2 backend), or
`sudo apt install docker.io docker-compose-v2` inside WSL.

## Start
```sh
cd server
# edit TZ in docker-compose.yml first
docker compose up -d
```
Creates `./config`, `./downloads`, `./library` next to the compose file.

## Web UIs (from the PC browser)
| Service | URL | Role |
|---|---|---|
| Lidarr | http://localhost:8686 | music library manager |
| Prowlarr | http://localhost:9696 | indexer manager (feeds Lidarr) |
| qBittorrent | http://localhost:8080 | download client (default login admin/adminadmin → change it) |
| Syncthing | http://localhost:8384 | sync `./library` → tablet |

## Wiring order
1. **qBittorrent** — log in, change the password, set the save path to `/downloads`.
2. **Prowlarr** — add your indexers; under *Settings → Apps* add Lidarr (it pushes indexers to it).
3. **Lidarr** — *Settings → Download Clients* add qBittorrent; *Media Management* root folder `/music`;
   then add artists/albums to fetch.
4. **Syncthing** — share the `/library` folder; pair with the tablet (see below).

## Tablet side
- Tablet runs Syncthing too; pair the two devices and accept the shared folder into `~/Music`.
- mpd has `auto_update "yes"`, so new files appear in the library automatically.

> Indexer/content choices are yours — this repo only provides the open-source plumbing.
