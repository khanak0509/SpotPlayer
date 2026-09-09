# SpotPlayer

**Paste a Spotify playlist. Keep it on your phone. Play offline.**

SpotPlayer turns any Spotify playlist into your own offline library. Import once, and every track lives on your phone — no streaming, no re-downloading when you hit play.

---

## What you get

- Import from a Spotify link
- Songs saved as MP3 on your phone
- Full player — shuffle, queue, background play
- Works offline after import

Your computer is only needed **while adding a new playlist**. After that, the app runs on its own.

---

## Setup

### 1 · Install the app on your phone

Build a small release APK (share the `arm64-v8a` file — works on most phones):

```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons
```

APK path:

```
app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Upload that file and share your download link.

### 2 · Import a playlist

**On your computer** (same Wi-Fi as your phone). From the **project root** (not the `app` folder):

```bash
cd /path/to/spotify
./start.sh        # Mac / Linux
```

```bat
start.bat         # Windows
```

That starts the backend and prints a link — copy it:

```
http://192.168.1.42:8000/api
```

**On your phone:**

1. **Settings → Server** → paste that link
2. Tap **+** → paste a Spotify playlist link
3. Wait for downloads → **Play**

Press `Ctrl+C` to stop the backend when done. Music stays on your phone.

### 3 · Daily use

Open the app and play. No computer, no Wi-Fi required.

---

## Requirements

- [Docker](https://docs.docker.com/get-docker/)
- [Python 3](https://www.python.org/downloads/) — used by the start script to find your Wi-Fi IP
- Phone and computer on the **same Wi-Fi** during import

---
