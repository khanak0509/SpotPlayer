<div align="center">
  <h1>🎶 SpotPlayer</h1>
  <p><b>If you are a developer and still paying to listen to music, then this is for you. Thank me later... 🚀</b></p>
  
  <p>
    <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter"></a>
    <a href="https://fastapi.tiangolo.com/"><img src="https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"></a>
    <a href="https://www.docker.com/"><img src="https://img.shields.io/badge/Docker-2CA5E0?style=for-the-badge&logo=docker&logoColor=white" alt="Docker"></a>
    <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"></a>
    <img src="https://img.shields.io/badge/Offline-100%25-brightgreen?style=for-the-badge" alt="Offline">
  </p>
</div>

---

## ✨ Why SpotPlayer?
Stop paying for subscriptions just to listen to your music offline. **SpotPlayer** is a sleek, completely offline music player built for power users. 

Paste a Spotify link. The app talks to a self-hosted local backend, fetches the absolute best quality audio, syncs it to your phone, and boom—your music lives on your device forever. No ads, no streaming buffers, no monthly fees. 

Your computer is only needed **while importing or syncing**. After that, take your phone anywhere and enjoy your completely offline library.

## 🚀 Features That Wow

- 📥 **One-Click Imports:** Just paste a playlist, album, or track link. SpotPlayer handles the rest.
- 🎧 **True Offline Experience:** Music stays on your phone. No internet? No problem.
- ⚡ **Lightning Fast Downloads:** Powered by parallel Python workers in a Docker container.

- 📱 **Native Integration:** Full background play, Android Auto support, lock-screen media controls, AirPods support, and an interactive Android home widget.
- 🧠 **Smart Memory:** Remembers your exact position and queue after closing the app.

---

## 🛠️ Tech Stack

SpotPlayer is a beautiful marriage of modern technologies:
- **Frontend App:** [Flutter](https://flutter.dev/) (Dart) using Riverpod for robust state management.
- **Local Backend Engine:** [FastAPI](https://fastapi.tiangolo.com/) (Python) running seamlessly in a [Docker](https://www.docker.com/) container.
- **Audio Processing:** Under the hood, it uses advanced matching logic to get you the pristine audio you expect.

---

## ⚙️ Quick Setup Guide

We’ve made setup as painless as possible. You only need your computer for the initial sync.

### Step 1: Install the App
Get the app running on your Android device:
```bash
cd app
flutter pub get
flutter build apk --release --split-per-abi --tree-shake-icons
```
*Install the generated APK (`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`) on your phone.*

### Step 2: Spin Up the Engine
Ensure your phone and computer are on the **same Wi-Fi network**. From the root directory, launch the backend:
```bash
# Mac / Linux
./start.sh        

# Windows
start.bat         
```
*The terminal will print a shiny API URL (e.g., `http://192.168.1.42:8000/api`). Keep this handy!*

### Step 3: Sync & Play
1. Open SpotPlayer on your phone.
2. Go to **Settings → Server** and paste your API URL.
3. Tap the **+** button and paste any Spotify link.
4. Watch the magic happen, then hit **Play**! 🎉

*Once your songs are downloaded, press `Ctrl+C` on your computer. Your music is now safely in your pocket.*

---

## 💡 Pro Tips

- **Reclaim Space:** Deleting a playlist automatically cleans up orphaned MP3 files, keeping your storage optimized.
- **Listen Stats:** Tap the insights icon in your library to see your listening stats and history.
- **Auto-Retry:** SpotPlayer automatically handles failed downloads, but you can always manually retry an entire batch with one tap.

<div align="center">
  <br/>
  <i>Built with ❤️ for developers who love music.</i>
</div>
