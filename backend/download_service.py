import asyncio
import logging
import re
from difflib import SequenceMatcher
from pathlib import Path

import yt_dlp

from config import DOWNLOAD_WORKERS, TEMP_DIR
from track_store import clear_path, get_path, get_status, set_meta, set_path, set_status, get_all_statuses, get_meta

logger = logging.getLogger(__name__)

download_queue: asyncio.Queue | None = None
_workers_started = False
_pending: set[str] = set()
_retry_counts: dict[str, int] = {}


AUDIO_EXTS = (".m4a", ".mp3")


def _audio_base(track_id: str) -> Path:
    safe = re.sub(r"[^\w\-]", "_", track_id)
    return TEMP_DIR / safe


def _audio_path(track_id: str) -> Path:
    base = _audio_base(track_id)
    for ext in AUDIO_EXTS:
        candidate = base.with_suffix(ext)
        if candidate.exists():
            return candidate
    return base.with_suffix(".m4a")


def _norm(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").lower()).strip()


_NON_ORIGINAL = (
    "cover", "karaoke", "instrumental", "8d audio", "8d", "slowed", "reverb",
    "sped up", "speed up", "tribute", "reaction", "mashup", "dj mix", "nightcore",
    "lyric video", "lyrics video", "with lyrics", "whatsapp", "shorts", "1 hour",
    "loop", "bass boosted", "fan made", "fanmade", "cover by", "sung by",
    "recreated", "re-create", "female version", "male version",
)

_VARIANT = ("unplugged", "live", "remix", "redux", "acoustic", "reprise", "version", "lofi", "lo-fi")

_DUBBED_LANG_MARKERS = (
    "tamil", "telugu", "malayalam", "kannada", "bengali", "marathi", "punjabi",
    "tamil version", "telugu version", "kannada version", "malayalam version",
    "dubbed", "dubbed version",
    "en uyir",
    "em nathoni",
    "en jeevane",
    "enthi nenena",
    "nee kannu",
)

_OFFICIAL_LABELS = (
    "t-series", "sony music", "zee music", "tips", "saregama", "yrf", "wave music",
    "universal", "warner", "atlantic", "interscope", "vevo",
)


def _spotify_allows_variant(spotify_title: str) -> set[str]:
    t = _norm(spotify_title)
    return {v for v in _VARIANT if v in t}


def _official_bonus(video_title: str, channel: str, artist: str) -> float:
    vt = _norm(video_title)
    ch = _norm(channel)
    primary_artist = _norm(artist.split(",")[0])
    bonus = 0.0

    for marker in (
        "official audio", "official video", "official music video",
        "full audio", "full video", "audio song",
    ):
        if marker in vt:
            bonus += 0.12

    if " - topic" in ch or ch.endswith("topic"):
        bonus += 0.3
    if "vevo" in ch:
        bonus += 0.22
    if primary_artist and primary_artist in ch:
        bonus += 0.18
    for label in _OFFICIAL_LABELS:
        if label in ch:
            bonus += 0.1

    return min(bonus, 0.55)


def _non_original_penalty(video_title: str, channel: str, spotify_title: str) -> float:
    vt = _norm(video_title)
    ch = _norm(channel)
    st = _norm(spotify_title)
    allowed = _spotify_allows_variant(spotify_title)
    penalty = 0.0

    for kw in _NON_ORIGINAL:
        if kw in vt or kw in ch:
            penalty += 0.35

    for variant in _VARIANT:
        if variant in vt and variant not in allowed:
            penalty += 0.35 if variant in ("unplugged", "live", "remix", "acoustic", "lofi", "lo-fi") else 0.2

    if "lyrics" in vt and "official" not in vt:
        penalty += 0.25

    for lang in _DUBBED_LANG_MARKERS:
        if lang in vt and lang not in st:
            penalty += 0.6
            break

    return min(penalty, 1.0)


def _track_name(title: str) -> str:
    cleaned = re.sub(r"\(.*?\)", "", title)
    cleaned = re.sub(r'\s*-\s*from.*', "", cleaned, flags=re.I)
    return _norm(cleaned.split("-")[0])


def _score_result(entry: dict, artist: str, title: str, duration_ms: int) -> float:
    video_title = entry.get("title") or ""
    channel = entry.get("channel") or entry.get("uploader") or ""
    vt = _norm(video_title)
    target = _norm(f"{artist} - {title}")
    track_name = _track_name(title)

    if track_name and track_name not in vt:
        return 0.0

    title_sim = SequenceMatcher(None, vt, target).ratio()

    primary_artist = _norm(artist.split(",")[0])
    if primary_artist in vt and track_name in vt:
        title_sim = min(1.0, title_sim + 0.2)

    video_dur = entry.get("duration") or 0
    if video_dur and duration_ms:
        diff_sec = abs(video_dur - duration_ms / 1000)
        if diff_sec <= 3:
            dur_score = 1.0
        elif diff_sec <= 10:
            dur_score = 0.85
        elif diff_sec <= 20:
            dur_score = 0.55
        else:
            dur_score = max(0.0, 1.0 - diff_sec / 30.0)
    else:
        dur_score = 0.15

    base = title_sim * 0.4 + dur_score * 0.35
    bonus = _official_bonus(video_title, channel, artist)
    penalty = _non_original_penalty(video_title, channel, title)
    return max(0.0, base + bonus - penalty)


def _rank_results(entries: list[dict], artist: str, title: str, duration_ms: int) -> list[tuple[float, dict]]:
    ranked = [(_score_result(e, artist, title, duration_ms), e) for e in entries]
    ranked.sort(key=lambda item: item[0], reverse=True)
    return ranked


def _ydl_opts(extra: dict | None = None) -> dict:
    base = {
        "quiet": True,
        "no_warnings": True,
        "retries": 3,
        "fragment_retries": 3,
    }
    if extra:
        base.update(extra)
    return base


def _entry_url(entry: dict) -> str | None:
    url = entry.get("webpage_url") or entry.get("url")
    if url:
        return url
    vid = entry.get("id")
    if vid:
        return f"https://www.youtube.com/watch?v={vid}"
    return None


def _search_youtube(
    artist: str,
    title: str,
    duration_ms: int,
    exclude: set[str] | None = None,
) -> str | None:
    query = f"ytsearch12:{artist} {title} official audio"
    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extract_flat": True,
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(query, download=False)
    except Exception as e:
        logger.warning("yt-dlp search failed for %s - %s: %s", artist, title, e)
        return None

    entries = [e for e in (info.get("entries") or []) if e]
    if not entries:
        logger.warning("yt-dlp search returned no results for %s - %s", artist, title)
        return None

    skip = exclude or set()
    for score, entry in _rank_results(entries, artist, title, duration_ms):
        url = _entry_url(entry)
        if not url or url in skip:
            continue
        if score < 0.25:
            break
        logger.info(
            "picked %.2f %s - %s -> %s",
            score,
            artist,
            title,
            (entry.get("title") or "")[:80],
        )
        return url
    return None


def _download_from_url(url: str, base: Path) -> Path | None:
    base.parent.mkdir(parents=True, exist_ok=True)
    tmp = base.with_name(base.name + ".part")
    opts = _ydl_opts({
        "format": "bestaudio[ext=m4a]/bestaudio",
        "outtmpl": str(tmp) + ".%(ext)s",
        "postprocessors": [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "m4a>m4a/mp3",
            "preferredquality": "192",
        }],
    })
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            ydl.download([url])
    except Exception as e:
        logger.warning("download failed %s: %s", url, e)
        for f in base.parent.glob(f"{tmp.name}*"):
            f.unlink(missing_ok=True)
        return None

    result = None
    for f in base.parent.glob(f"{tmp.name}*"):
        if f.suffix in AUDIO_EXTS and result is None:
            result = base.with_suffix(f.suffix)
            f.rename(result)
        else:
            f.unlink(missing_ok=True)
    return result


def download_track_sync(track_id: str, artist: str, title: str, duration_ms: int) -> str | None:
    out_path = _audio_path(track_id)
    if out_path.exists():
        return str(out_path)
    base = _audio_base(track_id)

    tried: set[str] = set()
    if track_id.startswith("yt_"):
        url = f"https://www.youtube.com/watch?v={track_id[3:]}"
        path = _download_from_url(url, base)
        if path:
            return str(path)
        tried.add(url)

    url = _search_youtube(artist, title, duration_ms, exclude=tried)
    if not url:
        return None

    for attempt in range(3):
        path = _download_from_url(url, base)
        if path:
            return str(path)
        tried.add(url)
        url = _search_youtube(artist, title, duration_ms, exclude=tried)
        if not url:
            break
    return None


def delete_temp_file(track_id: str):
    base = _audio_base(track_id)
    for ext in AUDIO_EXTS:
        base.with_suffix(ext).unlink(missing_ok=True)


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
    if status == "failed":
        delete_temp_file(track_id)
        await clear_path(track_id)
        _pending.discard(track_id)

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
                _retry_counts.pop(track_id, None)
                logger.info("ready %s", track_id)
            else:
                retries_done = _retry_counts.get(track_id, 0)
                if retries_done < 1:
                    _retry_counts[track_id] = retries_done + 1
                    delete_temp_file(track_id)
                    await clear_path(track_id)
                    await set_status(track_id, "queued")
                    _pending.add(track_id)
                    await download_queue.put(job)
                    logger.warning("auto-retry %s (attempt %d)", track_id, retries_done + 1)
                else:
                    _retry_counts.pop(track_id, None)
                    await set_status(track_id, "failed")
                    _pending.discard(track_id)
                    logger.warning("failed %s (no more retries)", track_id)
        except Exception as e:
            logger.exception("worker %d failed on %s: %s", worker_id, track_id, e)
            await set_status(track_id, "failed")
            _retry_counts.pop(track_id, None)
            _pending.discard(track_id)
        finally:
            download_queue.task_done()


async def start_workers():
    global download_queue, _workers_started
    if _workers_started:
        return
    download_queue = asyncio.Queue()
    _workers_started = True

    statuses = await get_all_statuses()
    for track_id, status in statuses.items():
        if status in ("downloading", "queued"):
            meta = await get_meta(track_id)
            if meta:
                _pending.add(track_id)
                await set_status(track_id, "queued")
                await download_queue.put({
                    "track_id": track_id,
                    "artist": meta.get("artist", ""),
                    "title": meta.get("title", ""),
                    "duration_ms": meta.get("duration_ms", 0),
                })
                logger.info("recovered stuck track: %s", track_id)

    for i in range(DOWNLOAD_WORKERS):
        asyncio.create_task(_worker(i))


async def retry_track(track_id: str, artist: str, title: str, duration_ms: int):
    _retry_counts.pop(track_id, None)
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
