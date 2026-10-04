# SpotPlayer: Complete Project Guide

This document explains the whole project for a developer or AI coding agent picking it up with no prior context. It covers what the app does, how every part works, the important rules inside the code, how to build it, and the owner's working preferences.

---

## 1. What the app is

**SpotPlayer** is a personal offline music player for Android (iOS builds too).

The user pastes a public **Spotify link** (playlist, album, or single track). A small **backend on the user's computer** reads the track list from Spotify, finds each song on **YouTube**, and downloads it as an **MP3**. The phone app then copies those MP3s onto the phone. After that, all playback is **fully offline**. No streaming, no Spotify account, no login.

Key idea: **the computer is only needed while importing or syncing.** Daily listening needs nothing but the phone.

### Main user flows

1. **First launch:** there is no server URL and no music, so the app shows the server setup screen.
2. **Import:**
   - The user starts the backend on a computer with `./start.sh`, which prints a LAN URL like `http://192.168.1.42:8000/api`.
   - They paste that URL in **Settings → Server**.
   - They tap **+** and paste a Spotify link.
   - The backend queues downloads. The app polls status and pulls finished MP3s onto the phone.
3. **Daily use:** the user opens the app and plays music offline. Controls also work from the notification shade, lock screen, headphones, the Android home-screen widget, and Android Auto.

### Current feature set (kept intentionally small)

The owner explicitly asked to keep **only base features, polished and optimized**.

- Import a playlist, album, or track by link. Re-sync a playlist to pick up new songs. Retry failed downloads.
- Library of imported playlists, search across songs, **Liked songs** (favorites), **Recently played**.
- Full player:
  - play/pause, next/previous, seek
  - shuffle (turning it off restores the original order), repeat (off / all / one)
  - **Up Next** queue with drag-to-reorder
  - sleep timer (15 / 30 / 60 minutes, or "End of this track")
  - playback speed (0.8x / 1.0x / 1.25x)
  - optional smooth fade between tracks ("Smooth transitions")
- Resume the last song, queue, and position after the app is killed. It restores paused, never autoplays.
- Background playback with a media notification (via `just_audio_background` / `audio_service`).
- Local notifications: download batch finished, continue-listening reminder, sleep timer ended.
- **Listening stats** screen, based on local play/skip/listen-time counts.
- Android home-screen widget (play/pause/next/previous).
- Reclaims storage: deleting a playlist deletes MP3s that no other playlist uses.

### Features that were REMOVED (do not re-add unless asked)

- **Gemma on-device LLM** (`flutter_gemma`). It made the APK about 307 MB and needed a Hugging Face token, so it was removed completely from the app and backend. The APK is now about 61 MB.
- **Assistant** (natural-language mix builder). Removed completely, including its Settings entry.
- **Daily Mix / Smart mixes row** (Daily / Likes / On Repeat). Removed. The owner said "later we can add".
- There is no WorkManager or background job scheduling. Do not add it.

---

## 2. Repository layout

```
spotify/
├── README.md               User-facing setup guide
├── PROJECT_GUIDE.md        (this file)
├── docker-compose.yml      Runs the backend container (volume at /data)
├── start.sh / start.bat    Detects the LAN IP, prints the URL to paste in the app, runs docker compose up --build
├── host_ip.py              Helper: prints this computer's Wi-Fi IP
├── render.yaml             Optional Render.com deploy config (health check /health)
├── backend/                Python FastAPI server (import + YouTube download)
└── app/                    Flutter app (the product)
```

---

## 3. Backend (`backend/`)

**Stack:** Python, FastAPI, Uvicorn, `spotify_scraper` (reads public Spotify pages without an API key), `yt-dlp` + FFmpeg (YouTube search and MP3 extraction). It runs in Docker.

### Files

| File | Role |
|---|---|
| `main.py` | FastAPI app. CORS. On startup: `start_workers()`. Mounts the router at **`/api`**. `GET /health` for pings. |
| `config.py` | Env config: `DATA_DIR` (default `backend/data`, Docker `/data`), `TEMP_DIR` (MP3 folder, `/data/audio`), `DOWNLOAD_WORKERS` (default 4, compose sets 3), `HOST`, `PORT`. |
| `spotify_service.py` | `parse_spotify_url(url)` detects playlist/album/track and returns one "playlist-shaped" dict: `{id, name, cover_url, spotify_url, tracks:[{id,name,artist,duration_ms,album_art,position}], kind}`. IDs: playlist = Spotify ID, album = `album_<id>`, track = `track_<id>`. |
| `download_service.py` | The download pipeline (details below). |
| `track_store.py` | Per-track `status` / `path` / `meta`, persisted in `DATA_DIR/tracks.json` behind an asyncio lock. Statuses: `queued`, `downloading`, `ready`, `failed`. |
| `playlist_store.py` | Saves imported playlist JSON on the server. |
| `routes.py` | HTTP API (below). |
| `models.py` | Pydantic request/response models. |
| `network_util.py` | LAN IP helpers. |
| `Dockerfile`, `entrypoint.sh`, `requirements.txt` | Container setup. |

### Download pipeline (`download_service.py`)

- There is an `asyncio.Queue` plus N worker tasks. Each job runs `download_track_sync` in a thread executor.
- **YouTube matching:** searches `ytsearch12:"{artist} {title} official audio"`, then scores every result:
  - title similarity and a check that the track name appears in the video title
  - duration closeness to Spotify's duration
  - bonuses for official channels ("- Topic", VEVO, the artist's name in the channel, labels like T-Series/Saregama, "official audio")
  - penalties for covers, karaoke, slowed/reverb, 8D, lyric videos, live/remix/unplugged (unless the Spotify title itself says so)
  - results below a score of 0.25 are rejected
- It downloads the best audio and converts it to MP3 at 192 kbps via FFmpeg. If a download fails, it tries up to 3 other candidates.
- Files are saved as `TEMP_DIR/<safe_track_id>.mp3`.
- `enqueue_track` skips tracks that are already ready or downloading. A failed track is cleaned up and re-queued.

### API (all under `/api`)

| Method & path | Purpose |
|---|---|
| `POST /playlists/import` `{url}` | Parse the Spotify link, merge with any existing server copy, save, queue all tracks. Returns `{playlist_id, name, track_count, playlist: PlaylistDetail}`. |
| `POST /playlists/sync` `{url}` | Re-parse and queue only the new tracks. |
| `GET /playlists/{id}` | Playlist with live track statuses. |
| `GET /playlists/{id}/search?q=` | Server-side search (the app mostly searches locally). |
| `DELETE /playlists/{id}` | Remove from the server. |
| `POST /tracks/queue` `{tracks:[{id,name,artist,duration_ms}]}` | Queue downloads. |
| `POST /tracks/status` `{track_ids:[...]}` | Batch statuses `{statuses:{id:status}}`. |
| `GET /tracks/{id}/status` | Single status. |
| `POST /tracks/{id}/retry` | Re-download one track. |
| `GET /tracks/{id}/stream` | Serves the MP3, with HTTP Range support. **The app downloads the file from here onto the phone.** |
| `GET /health` (no `/api` prefix) | Reachability ping. |

### Running the backend

```bash
./start.sh          # macOS/Linux (Windows: start.bat)
# prints: http://<LAN-IP>:8000/api  -> paste into the app's Settings → Server
```

Docker volume `spotplayer_data` keeps `/data` (statuses + MP3s) across restarts. The phone and computer must be on the **same Wi-Fi**.

---

## 4. Flutter app (`app/`)

**Stack:**

| Area | Packages |
|---|---|
| State | Riverpod 2 (`StateNotifier`) |
| Local storage | Hive (all values stored as JSON strings) |
| Playback | `just_audio` 0.9.x + `just_audio_background` (wraps `audio_service`) + `audio_session` |
| HTTP | Dio |
| Images | `cached_network_image` |
| Background colours | `palette_generator` |
| Other | `home_widget` (Android widget), `flutter_local_notifications` + `timezone`, `permission_handler`, `google_fonts` |

Android package: `com.spotplayer.spotplayer`.

### 4.1 Startup (`lib/main.dart`)

1. `JustAudioBackground.init(...)` with `androidNotificationOngoing: false` and `androidStopForegroundOnPause: false`. The plugin asserts that "ongoing" requires stop-on-pause, so this combination keeps the service alive when paused.
2. Sets system UI colours, locks the screen to portrait, runs `Hive.initFlutter()`, and reads `server_url` from the `settings` box.
3. `SpotPlayerApp._bootstrap()` runs **in this order**:
   1. `localStore.init`
   2. `userPrefs.init`
   3. `playbackSession.init`
   4. `playStats.init`
   5. `settingsStore.init` (then sets `serverUrlProvider`)
   6. `widgetService.init`
   7. `notificationService.init`
   8. server reachability refresh
   9. `library.load()`
   10. `player.restoreSession()`
   11. continue-listening reminder check
   12. auto-sync if enabled
   13. a 20-second periodic server ping
4. Lifecycle:
   - On **resume:** reminder check, ping the server, and if it's up, auto-sync and reload the library.
   - On **pause:** save the session end time.

### 4.2 Screens (`lib/screens/`)

| File | What it shows |
|---|---|
| `shell.dart` | Root router. Shows a spinner while loading. If any playlists exist, it shows **LibraryScreen + MiniPlayerBar** (offline-first). Otherwise it shows `ServerSetupScreen` when there's no server, or `ImportEmptyScreen` when there's a server but no music. |
| `library_screen.dart` | Home screen. The app bar has search, Listening stats (`Icons.insights_rounded`), and Settings. Below that: Liked songs entry, **Recently played** row, and the playlist grid. The **+** button opens the import sheet. |
| `playlist_detail_screen.dart` | Playlist header, play/shuffle, track list with a download status per row, search filter, retry failed. **Hold a track to reorder** (a `SliverReorderableList` using `onReorderItem`). Swipe to remove. Reordering also calls `player.syncPlaylistOrder` (see 4.5). |
| `now_playing_screen.dart` | Full player: blurred art background, album art (Hero `now-playing-art`), title/artist, like, speed, sleep timer, **seek bar**, transport controls, **Up Next** sheet (`ReorderableListView`, `onReorderItem` → `reorderQueue`; tapping a row → `skipToIndex`). Swipe down to dismiss. Swipe the art left/right for next/previous. |
| `favorites_screen.dart` | Liked songs (from `userPrefs.favoriteIds`), with a heart per row. Tapping a row plays the list as `playlistId: 'liked'`. |
| `search_screen.dart` | Local search across all playlists. |
| `listening_stats_screen.dart` | Top tracks by plays and listen time, from `PlayStatsService`. |
| `settings_screen.dart` | Server URL (with test), toggles (Auto-sync, Smooth transitions, Reminders, Show onboarding tips), Storage (usage, clear downloads), About. **No Assistant section.** |
| `server_setup_screen.dart`, `import_empty_screen.dart`, `onboarding_screen.dart` | Setup and empty states. |

### 4.3 Widgets (`lib/widgets/`)

| File | What it does |
|---|---|
| `mini_player.dart` | Bottom bar: art, title, shuffle/prev/play/next, thin progress bar (`_MiniProgress`, the only part that rebuilds on position ticks). Horizontal swipe = next/previous. Tap opens the full player via `openNowPlaying(context)`, a `PageRouteBuilder` with a **slide-up** transition (no fade). |
| `art_background.dart` | `ArtBackground`: blurred cover inside a **RepaintBoundary** (blur sigma 30, decoded at `memCacheWidth: 120`) plus a gradient from the palette colours. The palette is extracted about 350 ms after open, on a 64-px `ResizeImage`. `ArtGradientHeader` is a lightweight non-blurred header for the playlist page. |
| `track_row.dart` | Track row plus `FavoriteHeartButton` (calls `userPrefs.toggleFavorite`) and a status indicator. |
| `import_sheet.dart` | Paste-link bottom sheet that calls `library.importPlaylist`. |
| Others | `playlist_card.dart`, `playlist_sync_progress.dart`, `offline_banner.dart`, `equalizer_bars.dart`, `scale_button.dart` (press animation). |

### 4.4 Services and state (`lib/services/`, `lib/providers/`)

| File | Role |
|---|---|
| `models/models.dart` | `Track` (id, name, artist, durationMs, albumArt, status, position), `TrackStatus {queued, downloading, ready, failed, resolving}`, `PlaylistSummary`, `PlaylistDetail`, `PlayerRepeatMode {off, one, all}`. JSON uses snake_case keys matching the backend. |
| `services/api.dart` | `ApiService` (Dio). `baseUrl` comes from `serverUrlProvider` and **includes `/api`**. `ping()` strips `/api` and calls `/health`. Import and sync use a 90-second timeout. |
| `services/local_store.dart` | `LocalStore`, with Hive boxes `playlists` (id → PlaylistDetail JSON plus `imported_at`) and `track_paths` (trackId → local MP3 path). MP3s live in `<app documents>/tracks/<trackId>.mp3`. `hasTrack` checks that the file actually exists. It also provides `reclaimOrphanTracks`, `getLikedTracks`, and `mergeStatuses`. `TrackSyncService` (`trackSyncProvider`) queues tracks, fetches statuses, and downloads ready tracks from `/tracks/{id}/stream` (4 in parallel, `.part` then rename). `libraryTickProvider` bumps to refresh progress UI. |
| `providers/library_provider.dart` | `LibraryNotifier`: loads summaries, polls every 3 s while syncing, fires the "download finished" notification when a sync wave ends. Also handles import, sync, retry-failed, remove playlist, reorder tracks (persists positions), and remove track from playlist (also removes it from the player queue). `playlistDetailProvider(id)` exposes one playlist. |
| `providers/player_provider.dart` | `PlayerNotifier` / `PlayerState`: all playback. See 4.5. |
| `services/user_prefs_store.dart` | `UserPrefsNotifier` (Hive box `user_prefs`): favourites as `{trackId: likedAtMs}` (migrates an old list format), recent tracks (max 20), onboarding flag, autoSync, crossfade, remindersEnabled, playbackSpeed, lastContinueNotifMs. **`init()` loads from disk only once** (a memoised future). Do not make it reload, or likes will flip back (a real bug that was fixed). |
| `services/playback_session_store.dart` | Saves the queue, source order, index, position, shuffle, repeat, and playlist info for resume. Also stores the session end time for the reminder. |
| `services/play_stats_store.dart` | `PlayStatsService` (box `play_stats`): per-track `playCount`, `skipCount`, `totalListenMs`, `lastPlayedMs`. A play = completed or at least 15 s listened. A skip = under 10 s. `onTrackLeft` snapshots listen time *before* any await. |
| `services/settings_store.dart` | Box `settings`: server URL. `serverUrlProvider`, `bootstrapServerUrl`. |
| `services/server_connectivity.dart` | `serverReachableProvider` (a bool notifier with `refresh()`), `ensureServerConfigured` / `ensureServerReachable` helpers. |
| `services/notification_service.dart` | Local notifications: download batch finished, continue listening, sleep timer ended. |
| `services/widget_service.dart` | Pushes the title, artist, and is_playing to the Android home widget. |

### 4.5 Player internals (`player_provider.dart`): READ BEFORE CHANGING

This file was carefully debugged. These rules fix real bugs the owner hit:

1. **Never `await _player.play()`.** In just_audio, the Future returned by `play()` completes only when playback stops or pauses. Awaiting it froze the load path, which left the volume at 0 with crossfade on ("timer runs but no sound") and left the loading flag stuck. Always use `unawaited(_player.play())`.
2. **One `ConcatenatingAudioSource` per queue** (`_playlist`, `useLazyPreparation: true`). The player's shuffle mode is always **disabled**. Shuffle is done by reordering `state.queue` ourselves, so **`state.queue[i]` always equals player index `i`**. `_sourceOrder` stores the unshuffled order for when shuffle is turned off.
3. **`_loadPlaylist`** (the only function that replaces the source):
   - A generation counter `_loadGen` makes overlapping loads safe: only the newest applies state and starts playback.
   - `_loadingPlaylist` is true during a load, and index events are ignored meanwhile.
   - `_pauseSerial`: if the user taps pause while a load is running, the load does not autoplay afterwards.
   - It awaits `_ready` (the `_init` future) first.
4. **Queue edits must not reload the source.**
   - `reorderQueue(old, new)` / `_moveInQueue` update `state.queue` **first**, then call `_playlist.move(old, new)`. `new` is the **final index** (from `onReorderItem`, already adjusted).
   - Removing a non-current track uses `_playlist.removeAt`. Removing the current track reloads at the same index.
   - It falls back to a reload only if the native call throws.
   - A probe on an Android emulator confirmed that `move()` correctly changes what plays next, even when done near the end of the current track.
5. **`syncPlaylistOrder(playlistId, orderedTracks)`:** when the user reorders the *playlist page* of the playlist that's currently playing, the same order is applied to the live queue. When shuffled, only `_sourceOrder` is updated. Without this, the next song followed the old order, a real bug that was fixed.
6. **Track changes** are handled in `_onIndexChanged`. It maps the index to `state.queue[index]` and updates stats: `onTrackLeft` counts "completed" if the previous track was within 4 s of its end. It also handles the "End of this track" sleep, the crossfade fade-in, recents, and the widget.
7. **Completion:** at the end of the whole queue (`ProcessingState.completed`), just_audio keeps `playing == true`, so the code pauses and seeks to 0. `isPlaying` is `playing && !completed`.
8. **Crossfade** (`_maybeCrossfadeOut` and `_fadeVolume`):
   - Volume ramps down in the last 2.8 s and ramps up on the next track.
   - `_fadeToken` cancels older fades.
   - `_fadedOut` restores full volume if the user seeks back out of the fade window. Otherwise the volume stayed low.
9. **Interruptions** (calls, other apps, headphone unplug) are handled by just_audio itself (`handleInterruptions` default). **Do not add custom `interruptionEventStream` / `becomingNoisyEventStream` handlers.** An old custom handler paused on duck and never resumed.
10. **Navigation:** `next()` / `previous()` compute indices themselves and use `skipToIndex` (`seek(Duration.zero, index: i)`). They do not use `seekToNext`, which with `LoopMode.one` just restarts the same song. `previous()` restarts the track if more than 3 s in or at index 0.
11. **`resume()`:** reloads if there's no source or the player is idle (e.g. after an error), and seeks if completed.
12. **Sleep timer:** either a duration or `afterCurrentTrack`. `_finishSleep` pauses and sends a notification.
13. **Persistence:** the session is saved with an 800 ms debounce (`_schedulePersist`), skipped while loading or restoring.

### 4.6 UI performance rules (keep these)

- **Do not `ref.watch(playerProvider)` for whole screens.** Position ticks many times per second. Use `ref.watch(playerProvider.select(...))` for exactly the fields you need.
  - `NowPlayingScreen` watches the track, isPlaying, shuffle, repeat, speed, and playlistName.
  - Only `_SeekBar`, `_SleepLabel`, and `_MiniProgress` watch position.
- **Seek bar:** while dragging, keep a local `_dragValue` and seek **once** in `onChangeEnd`. Seeking on every `onChanged` made the thumb jitter.
- **Open full player:** slide transition only. No `Opacity` or fade over the blurred background: fading a full-screen blur caused lag and half-transparent "blurry buttons".
- Keep expensive blur inside a `RepaintBoundary` with a small image decode.

### 4.7 Android native (`app/android/`)

- `MainActivity.kt` extends **`AudioServiceActivity`** (required by just_audio_background).
- `SpotPlayerWidget.kt`: a `HomeWidgetProvider`. The buttons send `ACTION_MEDIA_BUTTON` key events to the media session.
- The manifest declares the audio service (`MediaBrowserService`, which also enables Android Auto via `automotive_app_desc`), the widget receiver, and permissions: INTERNET, WAKE_LOCK, FOREGROUND_SERVICE(+_MEDIA_PLAYBACK), POST_NOTIFICATIONS.
- `build.gradle.kts`:
  - `minSdk = maxOf(24, flutter.minSdkVersion)`
  - **core library desugaring** enabled (`desugar_jdk_libs:2.1.4`), required by flutter_local_notifications
  - the release build uses R8 with `proguard-rules.pro` (Flutter keep rules plus `-dontwarn com.google.android.play.core.**`)
- iOS: deployment target 14.0 (Podfile and pbxproj). Run `pod install` in `app/ios` after dependency changes.

---

## 5. Building and running

### Flutter SDK location (important)

- The project uses stable Flutter at **`~/development/flutter`** (currently 3.47.5, Dart 3.13). `~/.zshrc` adds `~/development/flutter/bin` to PATH. Open a new terminal or run `source ~/.zshrc` if `flutter` is "not found".
- `~/Desktop/flutter/flutter` is the owner's **Flutter fork** (a framework-contributor checkout without version tags). **Do not use it for this app.** `pub get` fails with "0.0.0-unknown", and it contains unrelated framework changes.

### Commands

```bash
cd app
flutter pub get
flutter analyze lib          # should show 0 errors/warnings (a few style infos are fine)
flutter build apk --release  # → app/build/app/outputs/flutter-apk/app-release.apk (~61 MB)
flutter run                  # debug on a connected device/emulator
```

- If a sandboxed or agent shell sets a temporary `GRADLE_USER_HOME`, Gradle tries to re-download itself and times out. Fix: `export GRADLE_USER_HOME=$HOME/.gradle` (Gradle 8.14 is cached there).
- Emulator: AVD `flutter_emulator` (`~/Library/Android/sdk/emulator/emulator -avd flutter_emulator`).

### End-to-end test

1. Run `./start.sh` on the computer.
2. On the phone, same Wi-Fi: Settings → Server → paste the URL, then test.
3. Tap **+**, paste a Spotify playlist link, wait for the downloads, and play.

---

## 6. Owner's working preferences (follow these)

- **Keep it simple.** Polish and optimize the base features. Don't add big new features or scope creep unless asked.
- **Commits:** only when the owner asks. One logical change per commit, **short messages**, and **no AI co-author trailer** (no "Co-authored-by: Cursor/AI"). Git hooks were disabled for this via `git config core.hooksPath /tmp/empty-git-hooks`. Push to `origin` (GitHub `khanak0509/SpotPlayer`) when asked.
- Users must never need tokens or keys on the phone. No server is needed for daily playback.
- The owner reports bugs in casual, spoken-style English (sometimes mixed with Hindi). Read carefully for the actual scenario (e.g. "moved 5th song to 2nd place, but old 2nd song played").
- After fixes, build the release APK so the owner can install and test on their phone.

---

## 7. Current state (at handoff)

- All fixes below are done, analyzed clean, and built into the release APK. **They are NOT committed yet.** Check `git status`, and commit in small pieces only when the owner asks.
- Recent fixes, so you know what's intentional:
  1. Removed Gemma, the Assistant, and Mixes (code, settings, README).
  2. Likes flipping back on the Liked page: `UserPrefsNotifier.init()` now loads once.
  3. Silent playback (timer running, no sound): `play()` is never awaited, and crossfade volume is restored on seek-back.
  4. Pause sometimes ignored: a pause during loading now wins, custom interruption handling was removed, and the end of the queue stops cleanly.
  5. Up Next reorder: live `move()` instead of a reload. Tapping Up Next jumps within the queue (it used to replace the queue with one song).
  6. **Playlist-page reorder now updates the live queue** (`syncPlaylistOrder`).
  7. Sleep "End of this track" works mid-queue. Next/previous work with Repeat One. Stats no longer count every change as a skip.
  8. Smooth full-player open (slide, cached blur, no full-screen rebuilds) and a smooth seek bar (seek on release).
- Known limits:
  - Private Spotify "Liked Songs" can't be imported. Use a public playlist.
  - YouTube matching can occasionally pick the wrong video (use retry).
  - Album art needs network until cached.
- Ideas the owner mentioned for **later** (not now): bring back mixes; an on-device LLM only if it can stay small.
