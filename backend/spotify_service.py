import re

from spotify_scraper import SpotifyClient


def _best_image_url(images) -> str | None:
    if not images:
        return None
    sorted_imgs = sorted(images, key=lambda i: getattr(i, "width", 0) or 0, reverse=True)
    return sorted_imgs[0].url


def parse_spotify_playlist(url: str) -> dict:
    with SpotifyClient() as client:
        playlist = client.get_playlist(url, max_tracks=1000)

    cover = _best_image_url(getattr(playlist, "images", None))

    tracks = []
    for idx, item in enumerate(playlist.tracks):
        song = item.track
        if not song or not getattr(song, "name", None):
            continue
        artist = song.artists[0].name if song.artists else "Unknown"
        album_art = None
        if song.album:
            album_art = _best_image_url(getattr(song.album, "images", None))
        track_id = getattr(song, "id", None) or _fallback_id(artist, song.name)
        tracks.append({
            "id": track_id,
            "name": song.name,
            "artist": artist,
            "duration_ms": getattr(song, "duration_ms", 0) or 0,
            "album_art": album_art,
            "position": idx,
        })

    playlist_id = _extract_id(url)
    return {
        "id": playlist_id,
        "name": playlist.name or "Untitled Playlist",
        "cover_url": cover,
        "spotify_url": _normalize_url(url, playlist_id),
        "tracks": tracks,
    }


def _extract_id(url: str) -> str:
    m = re.search(r"playlist/([a-zA-Z0-9]+)", url)
    if not m:
        raise ValueError("Invalid Spotify playlist URL")
    return m.group(1)


def _normalize_url(url: str, playlist_id: str) -> str:
    if "open.spotify.com" in url:
        return f"https://open.spotify.com/playlist/{playlist_id}"
    return url


def _fallback_id(artist: str, name: str) -> str:
    import hashlib
    raw = f"{artist.lower()}::{name.lower()}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]
