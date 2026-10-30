import re
from urllib.parse import parse_qs, urlparse

import yt_dlp

MAX_TRACKS = 1000
MAX_MIX_TRACKS = 200

_JUNK = re.compile(
    r"\s*[\(\[][^\)\]]*\b(official|video|audio|lyrics?|visuali[sz]er|hd|4k|hq|mv|m/v)\b[^\)\]]*[\)\]]",
    re.IGNORECASE,
)
_CHANNEL_SUFFIX = re.compile(r"\s*(- topic|vevo|official)\s*$", re.IGNORECASE)
_DEAD_TITLES = {"[private video]", "[deleted video]"}


def is_youtube_url(url: str) -> bool:
    host = (urlparse(url.strip()).hostname or "").lower()
    return host == "youtu.be" or host == "youtube.com" or host.endswith(".youtube.com")


def _ids(url: str) -> tuple[str | None, str | None]:
    parsed = urlparse(url.strip())
    query = parse_qs(parsed.query)
    list_id = (query.get("list") or [None])[0]
    video_id = (query.get("v") or [None])[0]
    if parsed.hostname == "youtu.be":
        video_id = parsed.path.strip("/") or None
    elif not video_id:
        m = re.match(r"/(shorts|live|embed)/([\w-]+)", parsed.path)
        if m:
            video_id = m.group(2)
    return list_id, video_id


def _thumb(video_id: str) -> str:
    return f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg"


def _clean_channel(channel: str) -> str:
    return _CHANNEL_SUFFIX.sub("", channel or "").strip() or "Unknown"


def split_title(title: str, channel: str) -> tuple[str, str]:
    clean = _JUNK.sub("", title or "").split(" | ")[0].strip()
    for sep in (" - ", " – ", " — "):
        if sep in clean:
            artist, name = clean.split(sep, 1)
            if artist.strip() and name.strip():
                return artist.strip(), name.strip()
    return _clean_channel(channel), clean or title


def _track_dict(entry: dict, position: int) -> dict | None:
    video_id = entry.get("id")
    title = entry.get("title") or ""
    if not video_id or not title or title.lower() in _DEAD_TITLES:
        return None
    artist, name = split_title(title, entry.get("channel") or entry.get("uploader") or "")
    return {
        "id": f"yt_{video_id}",
        "name": name,
        "artist": artist,
        "duration_ms": int((entry.get("duration") or 0) * 1000),
        "album_art": _thumb(video_id),
        "position": position,
    }


def _extract(url: str, limit: int) -> dict:
    opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extract_flat": "in_playlist",
        "playlistend": limit,
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            return ydl.extract_info(url, download=False)
    except yt_dlp.utils.DownloadError:
        raise ValueError("YouTube link not found or private") from None


def parse_youtube_url(url: str) -> dict:
    list_id, video_id = _ids(url)
    if list_id:
        return parse_youtube_playlist(list_id, video_id)
    if video_id:
        return parse_youtube_video(video_id)
    raise ValueError("URL must be a YouTube playlist or video link")


def parse_youtube_playlist(list_id: str, video_id: str | None = None) -> dict:
    is_mix = list_id.startswith("RD")
    if is_mix and video_id:
        source = f"https://www.youtube.com/watch?v={video_id}&list={list_id}"
    else:
        source = f"https://www.youtube.com/playlist?list={list_id}"
    info = _extract(source, MAX_MIX_TRACKS if is_mix else MAX_TRACKS)

    tracks = []
    for entry in info.get("entries") or []:
        row = _track_dict(entry or {}, len(tracks))
        if row:
            tracks.append(row)
    if not tracks:
        raise ValueError("Playlist is empty or private")

    return {
        "id": f"yt_{list_id}",
        "name": info.get("title") or "YouTube Playlist",
        "cover_url": tracks[0]["album_art"],
        "spotify_url": source,
        "tracks": tracks,
        "kind": "playlist",
    }


def parse_youtube_video(video_id: str) -> dict:
    source = f"https://www.youtube.com/watch?v={video_id}"
    row = _track_dict(_extract(source, 1), 0)
    if not row:
        raise ValueError("Could not read video")
    return {
        "id": f"track_{row['id']}",
        "name": row["name"],
        "cover_url": row["album_art"],
        "spotify_url": source,
        "tracks": [row],
        "kind": "track",
    }
