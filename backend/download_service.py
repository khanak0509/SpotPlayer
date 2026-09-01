import asyncio
import logging
import re
from difflib import SequenceMatcher
from pathlib import Path

import yt_dlp

from config import DOWNLOAD_WORKERS, TEMP_DIR
from track_store import clear_path, get_path, get_status, set_meta, set_path, set_status

logger = logging.getLogger(__name__)

download_queue: asyncio.Queue | None = None
_workers_started = False
_pending: set[str] = set()


def _audio_path(track_id: str) -> Path:
    safe = re.sub(r"[^\w\-]", "_", track_id)
    return TEMP_DIR / f"{safe}.mp3"


def _score_result(entry: dict, artist: str, title: str, duration_ms: int) -> float:
    video_title = (entry.get("title") or "").lower()
    target = f"{artist} - {title}".lower()
    title_sim = SequenceMatcher(None, video_title, target).ratio()
    if artist.lower() in video_title and title.lower() in video_title:
        title_sim = min(1.0, title_sim + 0.25)
    video_dur = entry.get("duration") or 0
    if video_dur and duration_ms:
        diff_sec = abs(video_dur - duration_ms / 1000)
        dur_score = max(0.0, 1.0 - diff_sec / 45.0)
    else:
        dur_score = 0.3
    return title_sim * 0.55 + dur_score * 0.45


def _ydl_opts(extra: dict | None = None) -> dict:
    base = {
        "quiet": True,
        "no_warnings": True,
        "retries": 3,
        "fragment_retries": 3,
        "extractor_args": {"youtube": {"player_client": ["android", "web"]}},
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
                "(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
            ),
        },
    }
    if extra:
        base.update(extra)
    return base


def _search_youtube(artist: str, title: str, duration_ms: int) -> str | None:
    query = f"ytsearch5:{artist} - {title}"
    opts = _ydl_opts({"skip_download": True, "extract_flat": False})
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(query, download=False)
    except Exception as e:
        logger.warning("yt-dlp search failed for %s - %s: %s", artist, title, e)
        return None

    entries = info.get("entries") or []
    if not entries:
        return None

    best = max(entries, key=lambda e: _score_result(e, artist, title, duration_ms))
    return best.get("webpage_url") or best.get("url")


def _download_from_url(url: str, out_path: Path) -> bool:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = out_path.with_suffix(".part")
    opts = _ydl_opts({
        "format": "bestaudio/best",
        "outtmpl": str(tmp.with_suffix("")),
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }],
    })
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])
    except Exception as e:
        logger.warning("download failed %s: %s", url, e)
        for f in tmp.parent.glob(f"{tmp.stem}*"):
            f.unlink(missing_ok=True)
        return False

    for c in out_path.parent.glob(f"{tmp.stem}*"):
        if c.suffix == ".mp3":
            if c != out_path:
                c.rename(out_path)
            return True
    return out_path.exists()


def download_track_sync(track_id: str, artist: str, title: str, duration_ms: int) -> str | None:
    out_path = _audio_path(track_id)
    if out_path.exists():
        return str(out_path)

    url = _search_youtube(artist, title, duration_ms)
    if not url:
        return None

    for attempt in range(2):
        if _download_from_url(url, out_path):
            return str(out_path)
        if attempt == 0:
            url = _search_youtube(artist, title, duration_ms)
            if not url:
                break
    return None


def delete_temp_file(track_id: str):
    path = _audio_path(track_id)
    if path.exists():
        path.unlink(missing_ok=True)


async def enqueue_track(track_id: str, artist: str, title: str, duration_ms: int):
    global download_queue
    if download_queue is None:
        return

    await set_meta(track_id, artist, title, duration_ms)
    status = await get_status(track_id)
    path = await get_path(track_id)

    if status == "ready" and path and Path(path).exists():
        return
    if status == "downloading" or track_id in _pending:
        return

    _pending.add(track_id)
    await set_status(track_id, "queued")
    await download_queue.put({
        "track_id": track_id,
        "artist": artist,
        "title": title,
        "duration_ms": duration_ms,
    })
    logger.info("queued %s - %s", artist, title)


async def enqueue_tracks(tracks: list[dict]):
    for t in tracks:
        await enqueue_track(t["id"], t["artist"], t["name"], t["duration_ms"])


async def _worker(worker_id: int):
    global download_queue
    loop = asyncio.get_event_loop()
    while True:
        job = await download_queue.get()
        track_id = job["track_id"]
        try:
            status = await get_status(track_id)
            out_path = _audio_path(track_id)
            if status == "ready" and out_path.exists():
                await set_path(track_id, str(out_path))
                continue

            await set_status(track_id, "downloading")
            path = await loop.run_in_executor(
                None,
                download_track_sync,
                track_id,
                job["artist"],
                job["title"],
                job["duration_ms"],
            )
            if path:
                await set_status(track_id, "ready")
                await set_path(track_id, path)
                logger.info("ready %s", track_id)
            else:
                await set_status(track_id, "failed")
                logger.warning("failed %s", track_id)
        except Exception as e:
            logger.exception("worker %d failed on %s: %s", worker_id, track_id, e)
            await set_status(track_id, "failed")
        finally:
            _pending.discard(track_id)
            download_queue.task_done()


async def start_workers():
    global download_queue, _workers_started
    if _workers_started:
        return
    download_queue = asyncio.Queue()
    _workers_started = True
    for i in range(DOWNLOAD_WORKERS):
        asyncio.create_task(_worker(i))


async def retry_track(track_id: str, artist: str, title: str, duration_ms: int):
    delete_temp_file(track_id)
    await clear_path(track_id)
    _pending.discard(track_id)
    await set_status(track_id, "queued")
    _pending.add(track_id)
    await download_queue.put({
        "track_id": track_id,
        "artist": artist,
        "title": title,
        "duration_ms": duration_ms,
    })
