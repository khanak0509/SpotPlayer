# SpotPlayer

Personal Spotify-link music player. Paste a playlist, backend resolves tracks via scraping and downloads audio via yt-dlp. The Flutter app saves tracks locally — replays never hit the server again.

## Stack

- **Backend**: FastAPI, spotifyscraper, yt-dlp, ffmpeg (in-memory state, ephemeral temp files)
- **App**: Flutter (Riverpod, just_audio, Hive)
- **Deploy**: Render.com free Docker web service

## Quick start (local)

### Backend

```bash
cd backend
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Requires **ffmpeg** on PATH for audio conversion.

### Flutter app

```bash
cd app
flutter pub get
flutter run
```

Set the backend URL in **Settings** (defaults to `http://localhost:8000`).

## Deploy to Render

1. Push this repo to GitHub
2. In Render: **New → Blueprint** and connect the repo (uses `render.yaml`)
   - Or **New → Web Service**, point at `./backend/Dockerfile`
3. Copy the service URL into the app's Settings (e.g. `https://spotplayer-api.onrender.com`)

No persistent disk needed. The free tier sleeps after 15 min of inactivity — first request after idle may take 30–60 seconds (the app handles this during import).

## Architecture

| Layer | Responsibility |
|-------|----------------|
| Backend (session) | Resolve playlists, queue yt-dlp downloads, stream each track once |
| Hive (device) | Playlist library, track file paths — permanent local storage |
| Temp disk (server) | Holds audio briefly during download/stream, cleared after send |

## API

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/playlists/import` | `{ "url": "..." }` → full playlist + queue downloads |
| POST | `/api/playlists/sync` | `{ "url": "..." }` → re-sync for new tracks |
| POST | `/api/tracks/queue` | Queue tracks for download |
| POST | `/api/tracks/status` | Batch status for track IDs |
| GET | `/api/tracks/{id}/stream` | Stream audio (full download, then temp file removed) |
| POST | `/api/tracks/{id}/retry` | Retry failed download |
| GET | `/health` | Health check |

## Env vars

| Variable | Default | Description |
|----------|---------|-------------|
| `DOWNLOAD_WORKERS` | `4` | Concurrent yt-dlp workers |
| `PORT` | `8000` | Server port (Render sets this) |
| `TEMP_DIR` | system temp | Ephemeral audio scratch space |
