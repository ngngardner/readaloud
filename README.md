# Readaloud

Self-hosted AI audiobook reader with word-level highlighting. Import EPUB and PDF files, generate audiobooks with AI text-to-speech, and read along as each word highlights in sync with the audio — like Kindle + Audible's Whispersync, but free and self-hosted.

## Features

- **File Import** — Upload EPUB and PDF files with automatic chapter extraction
- **AI Audiobook Generation** — Convert any book to audio using LocalAI TTS (Kokoro)
- **Word-Level Highlighting** — Follow along as each word highlights in sync with playback
- **Reading Progress** — Tracks your position (scroll and audio) across sessions
- **Task Dashboard** — Monitor import and audiobook generation progress in real-time

## Quick Start

```bash
git clone https://github.com/ngngardner/readaloud.git
cd readaloud
docker compose up
```

Open [http://localhost:4000](http://localhost:4000). On first run, LocalAI will download the TTS and Whisper models.

## Requirements

- Docker with GPU support (NVIDIA)
- ~4GB disk for AI models

### CPU-Only Mode

Edit `docker-compose.yml`: change the LocalAI image to `localai/localai:latest` and remove the `deploy.resources` section.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `SECRET_KEY_BASE` | (required) | Phoenix secret — generate with `mix phx.gen.secret` |
| `PHX_HOST` | `localhost` | Hostname for the web server |
| `LOCALAI_URL` | `http://localai:8080` | LocalAI endpoint |
| `DATABASE_PATH` | `/data/readaloud.db` | SQLite database path |
| `STORAGE_PATH` | `/data/files` | Book and audio file storage |

## Development

Requires [Nix](https://nixos.org/download.html):

```bash
cd readaloud
nix develop   # or use direnv

mix deps.get
mix ecto.setup
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000).

## Architecture

Elixir umbrella project with DDD bounded contexts:

```
apps/
├── readaloud_library/    — Book and chapter management
├── readaloud_reader/     — Reading progress tracking
├── readaloud_tts/        — TTS/STT client (LocalAI)
├── readaloud_importer/   — EPUB/PDF import pipeline
├── readaloud_audiobook/  — Audiobook generation pipeline
└── readaloud_web/        — Phoenix LiveView UI
```

## License

MIT
