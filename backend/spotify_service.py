import re

from spotify_scraper import SpotifyClient


def _best_image_url(images) -> str | None:
    if not images:
        return None
    sorted_imgs = sorted(images, key=lambda i: getattr(i, "width", 0) or 0, reverse=True)
    return sorted_imgs[0].url


def _fallback_id(artist: str, name: str) -> str:
    import hashlib
    raw = f"{artist.lower()}::{name.lower()}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]


def _track_dict(song, position: int) -> dict | None:
    if not song or not getattr(song, "name", None):
        return None
    artist = song.artists[0].name if song.artists else "Unknown"
    album_art = None
    if song.album:
        album_art = _best_image_url(getattr(song.album, "images", None))
    track_id = getattr(song, "id", None) or _fallback_id(artist, song.name)
    return {
        "id": track_id,
        "name": song.name,
        "artist": artist,
        "duration_ms": getattr(song, "duration_ms", 0) or 0,
        "album_art": album_art,
        "position": position,
    }


def detect_spotify_kind(url: str) -> str:
    if re.search(r"(album)/([a-zA-Z0-9]+)", url) or url.startswith("spotify:album:"):
        return "album"
    if re.search(r"(track)/([a-zA-Z0-9]+)", url) or url.startswith("spotify:track:"):
        return "track"
    if re.search(r"(playlist)/([a-zA-Z0-9]+)", url) or url.startswith("spotify:playlist:"):
        return "playlist"
    raise ValueError("URL must be a Spotify playlist, album, or track link")


def _extract_id(url: str, kind: str) -> str:
    m = re.search(rf"{kind}/([a-zA-Z0-9]+)", url)
    if m:
        return m.group(1)
    m = re.search(rf"spotify:{kind}:([a-zA-Z0-9]+)", url)
    if m:
        return m.group(1)
    raise ValueError(f"Invalid Spotify {kind} URL")


def _normalize_url(kind: str, entity_id: str) -> str:
    return f"https://open.spotify.com/{kind}/{entity_id}"


def parse_spotify_url(url: str) -> dict:
    """Parse playlist, album, or track URL into the shared playlist-shaped payload."""
    kind = detect_spotify_kind(url.strip())
    if kind == "playlist":
        return parse_spotify_playlist(url)
    if kind == "album":
        return parse_spotify_album(url)
    return parse_spotify_track(url)


def parse_spotify_playlist(url: str) -> dict:
    with SpotifyClient() as client:
        playlist = client.get_playlist(url, max_tracks=1000)

    cover = _best_image_url(getattr(playlist, "images", None))
    tracks = []
    for idx, item in enumerate(playlist.tracks):
        song = item.track
        row = _track_dict(song, idx)
        if row:
            tracks.append(row)

    playlist_id = _extract_id(url, "playlist")
    return {
        "id": playlist_id,
        "name": playlist.name or "Untitled Playlist",
        "cover_url": cover,
        "spotify_url": _normalize_url("playlist", playlist_id),
        "tracks": tracks,
        "kind": "playlist",
    }


def parse_spotify_album(url: str) -> dict:
    with SpotifyClient() as client:
        album = client.get_album(url)

    cover = _best_image_url(getattr(album, "images", None))
    album_id = getattr(album, "id", None) or _extract_id(url, "album")
    tracks = []
    for idx, item in enumerate(getattr(album, "tracks", None) or []):
        song = getattr(item, "track", None) or item
        row = _track_dict(song, idx)
        if row:
            if not row.get("album_art"):
                row["album_art"] = cover
            tracks.append(row)

    return {
        "id": f"album_{album_id}",
        "name": getattr(album, "name", None) or "Untitled Album",
        "cover_url": cover,
        "spotify_url": _normalize_url("album", album_id),
        "tracks": tracks,
        "kind": "album",
    }


def parse_spotify_track(url: str) -> dict:
    with SpotifyClient() as client:
        song = client.get_track(url)

    row = _track_dict(song, 0)
    if not row:
        raise ValueError("Could not read track")

    track_id = row["id"]
    cover = row.get("album_art")
    return {
        "id": f"track_{track_id}",
        "name": row["name"],
        "cover_url": cover,
        "spotify_url": _normalize_url("track", track_id),
        "tracks": [row],
        "kind": "track",
    }
