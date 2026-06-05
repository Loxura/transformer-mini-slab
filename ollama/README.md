# Ollama — local LLM runtime (containerized)

Runs on the **mainframe**, its own isolated stack like `searxng/` and `cooking/`. Serves the reconciler
model the cooking macro-enricher (`../cooking/enrich/enrich.py`) calls, and is available for any other
local LLM work. This **replaces the host-installed `ollama serve` systemd service** so everything runs
in containers.

- **GPU**: the host's registered `nvidia` Docker runtime passes the RTX 3060 (12 GB) into the container
  (`runtime: nvidia` + `NVIDIA_VISIBLE_DEVICES=all`). Models run on the GPU, not the CPU.
- **Models**: stored in the named volume `ollama_models`, isolated from the host's old `~/.ollama` /
  `/usr/share/ollama` stores.
- **Port**: published on `11434` (the canonical Ollama port) by default, so it's a drop-in for anything
  that already talks to `localhost:11434` — including the enricher. Override with `OLLAMA_HOST_PORT` in
  `ollama/.env` if you need to coexist with something else.

## First-time setup (retire the host service, then bring up the container)
The host `ollama` systemd service owns port 11434; retire it so the container can bind it:
```sh
sudo systemctl disable --now ollama        # stop + disable the host install
cd ollama
docker compose up -d                        # container binds 11434 (GPU passthrough)
docker exec ollama ollama pull gemma3n:e4b  # pull the reconciler model into the container volume
```

## Verify
```sh
docker compose ps
docker exec ollama nvidia-smi --query-gpu=name --format=csv,noheader   # GPU visible in-container
curl -s http://localhost:11434/api/tags | head -c 200                  # API up, lists models
docker exec ollama ollama ps                                           # a loaded model shows "100% GPU"
```

## Notes
- The enricher reads the Ollama endpoint from `~/.config/eww/ollama-url` (default `http://localhost:11434`)
  and the model from `~/.config/eww/ollama-model` / `$ENRICH_MODEL` (default `gemma3n:e4b`). With the
  container on 11434 nothing changes there.
- Pull more models any time: `docker exec ollama ollama pull <name>`. They persist in `ollama_models`.
- The old host model stores (`~/.ollama`, `/usr/share/ollama/.ollama`) are now unused and can be removed
  to reclaim disk once you're happy the container works.
