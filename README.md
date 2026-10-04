# SpotPlayer

**Paste a Spotify link. Keep the music on your phone. Play offline.**

SpotPlayer turns public Spotify playlists, albums, and tracks into your own offline library. Import once, and audio lives on your phone — no streaming when you hit play.

Your computer is only needed **while importing or syncing**. After that, the app runs on its own.

---

## Features

- Import **playlist / album / track** links (Liked Songs needs a public playlist — no Spotify login)
- Offline MP3 library with search, favorites, recents
- Local **reminders** (download finished, continue listening)
- Full player: shuffle (restores order when off), repeat, queue, sleep timer (incl. end of track), speed
- Gapless + optional smooth fade between tracks
- Resume last song and position after app kill (starts paused)
- Background play, notification shade, AirPods next/prev
- Interactive Android home widget (play / pause / next / previous)
- Android Auto media source support
- Faster parallel downloads + Retry all failed
- Deleting a playlist reclaims orphaned audio files
- Durable backend store (Docker volume survives restart)
- Teal-on-black brand UI

---

## Setup

### 1 · Install the app on your phone

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons
```

APK:

```
app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Allow notifications when prompted (media controls / shade).

### 2 · Start the backend

Phone and computer on the **same Wi-Fi**. From the **project root**:

```bash
./start.sh        # Mac / Linux
start.bat         # Windows
```

Copy the printed LAN URL, e.g. `http://192.168.1.42:8000/api`.

Docker mounts a volume at `/data` so queue status and server audio survive `docker compose restart`.

### 3 · Import

1. **Settings → Server** → paste the API URL  
2. Tap **+** → paste a Spotify **playlist, album, or track** link  
3. Wait for downloads → **Play**

Press `Ctrl+C` to stop the backend when done. Music stays on your phone.

### 4 · Daily use

Open the app and play offline. Home widget and notification controls work while a track is loaded.

---

## Requirements

- [Docker](https://docs.docker.com/get-docker/)
- [Python 3](https://www.python.org/downloads/) — start script finds your Wi-Fi IP
- Same Wi-Fi for phone + computer during import

---

## Limits

- Private Spotify **Liked Songs** are not scraped (no OAuth). Make a public playlist of likes if you need them.
- Album art may need network until cached by the image library.
- Matching uses YouTube search — occasional wrong matches; retry failed downloads from the playlist screen.
