import os
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request
from fastapi.responses import StreamingResponse

from download_service import delete_temp_file, enqueue_tracks, retry_track, _audio_path
from models import (
    BatchStatusRequest,
    BatchStatusResponse,
    ImportRequest,
    ImportResponse,
    PlaylistDetail,
    QueueTracksRequest,
    SearchResult,
    SyncRequest,
    TrackInfo,
    TrackStatus,
)
from playlist_store import delete_playlist, list_playlists, load_playlist, save_playlist
from spotify_service import parse_spotify_url
from track_store import batch_status, clear_path_sync, get_path, get_status

router = APIRouter()


async def _track_with_status(track: dict) -> TrackInfo:
    status = await get_status(track["id"])
    if not status:
        status = TrackStatus.queued
    return TrackInfo(
        id=track["id"],
        name=track["name"],
        artist=track["artist"],
        duration_ms=track["duration_ms"],
        album_art=track.get("album_art"),
        status=TrackStatus(status),
        position=track.get("position", 0),
    )


async def _build_detail(data: dict) -> PlaylistDetail:
    tracks = []
    ready = 0
    syncing = False
    for t in sorted(data.get("tracks", []), key=lambda x: x.get("position", 0)):
        info = await _track_with_status(t)
        tracks.append(info)
        if info.status == TrackStatus.ready:
            ready += 1
        elif info.status in (TrackStatus.queued, TrackStatus.downloading):
            syncing = True
    return PlaylistDetail(
        id=data["id"],
        name=data["name"],
        cover_url=data.get("cover_url"),
        spotify_url=data.get("spotify_url", ""),
        tracks=tracks,
        ready_count=ready,
        syncing=syncing,
    )


async def _merge_playlist(existing: dict | None, parsed: dict) -> dict:
    if not existing:
        parsed["imported_at"] = datetime.now(timezone.utc).isoformat()
        return parsed

    existing_ids = {t["id"] for t in existing.get("tracks", [])}
    new_tracks = [t for t in parsed["tracks"] if t["id"] not in existing_ids]
    merged = existing["tracks"] + new_tracks
    for i, t in enumerate(merged):
        t["position"] = i
    existing["tracks"] = merged
    existing["name"] = parsed["name"]
    existing["cover_url"] = parsed.get("cover_url") or existing.get("cover_url")
    existing["spotify_url"] = parsed["spotify_url"]
    existing["updated_at"] = datetime.now(timezone.utc).isoformat()
    return existing


@router.post("/playlists/import", response_model=ImportResponse)
async def import_playlist(body: ImportRequest):
    try:
        parsed = parse_spotify_url(body.url.strip())
    except Exception as e:
        raise HTTPException(400, f"Could not resolve Spotify link: {e}")

    existing = await load_playlist(parsed["id"])
    data = await _merge_playlist(existing, parsed)
    await save_playlist(data)
    await enqueue_tracks(data["tracks"])
    detail = await _build_detail(data)

    return ImportResponse(
        playlist_id=data["id"],
        name=data["name"],
        track_count=len(data["tracks"]),
        playlist=detail,
    )


@router.post("/playlists/sync", response_model=ImportResponse)
async def sync_playlist(body: SyncRequest):
    try:
        parsed = parse_spotify_url(body.url.strip())
    except Exception as e:
        raise HTTPException(400, f"Could not re-sync: {e}")

    existing = await load_playlist(parsed["id"])
    before_ids = {t["id"] for t in (existing or {}).get("tracks", [])}
    data = await _merge_playlist(existing, parsed)
    await save_playlist(data)

    new_tracks = [t for t in data["tracks"] if t["id"] not in before_ids]
    await enqueue_tracks(new_tracks)
    detail = await _build_detail(data)

    return ImportResponse(
        playlist_id=data["id"],
        name=data["name"],
        track_count=len(data["tracks"]),
        playlist=detail,
    )


@router.get("/playlists/{playlist_id}", response_model=PlaylistDetail)
async def get_playlist(playlist_id: str):
    data = await load_playlist(playlist_id)
    if not data:
        raise HTTPException(404, "Playlist not in active session")
    return await _build_detail(data)


@router.post("/tracks/queue")
async def queue_tracks(body: QueueTracksRequest):
    await enqueue_tracks([t.model_dump() for t in body.tracks])
    return {"queued": len(body.tracks)}


@router.post("/tracks/status", response_model=BatchStatusResponse)
async def tracks_status(body: BatchStatusRequest):
    raw = await batch_status(body.track_ids)
    statuses = {tid: TrackStatus(s) for tid, s in raw.items()}
    return BatchStatusResponse(statuses=statuses)


@router.get("/tracks/{track_id}/status")
async def track_status_endpoint(track_id: str):
    status = await get_status(track_id)
    return {"track_id": track_id, "status": status or "unknown"}


@router.post("/tracks/{track_id}/retry")
async def retry_download(track_id: str, body: QueueTracksRequest):
    for t in body.tracks:
        if t.id == track_id:
            await retry_track(track_id, t.artist, t.name, t.duration_ms)
            return {"ok": True}
    for p in await list_playlists():
        for t in p.get("tracks", []):
            if t["id"] == track_id:
                await retry_track(track_id, t["artist"], t["name"], t["duration_ms"])
                return {"ok": True}
    raise HTTPException(404, "Track not found")


@router.get("/tracks/{track_id}/stream")
async def stream_track(track_id: str, request: Request):
    path = await get_path(track_id)
    if not path or not os.path.exists(path):
        fallback = _audio_path(track_id)
        if fallback.exists():
            path = str(fallback)
        else:
            raise HTTPException(404, "Track not ready")

    file_size = os.path.getsize(path)
    range_header = request.headers.get("range")

    if range_header:
        range_match = range_header.replace("bytes=", "").split("-")
        start = int(range_match[0]) if range_match[0] else 0
        end = int(range_match[1]) if len(range_match) > 1 and range_match[1] else file_size - 1
        end = min(end, file_size - 1)
        length = end - start + 1

        def iter_range():
            with open(path, "rb") as f:
                f.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = f.read(min(65536, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                    yield chunk

        return StreamingResponse(
            iter_range(),
            status_code=206,
            media_type="audio/mpeg",
            headers={
                "Content-Range": f"bytes {start}-{end}/{file_size}",
                "Accept-Ranges": "bytes",
                "Content-Length": str(length),
            },
        )

    def iter_full():
        with open(path, "rb") as f:
            while chunk := f.read(65536):
                yield chunk

    return StreamingResponse(
        iter_full(),
        media_type="audio/mpeg",
        headers={
            "Accept-Ranges": "bytes",
            "Content-Length": str(file_size),
        },
    )


@router.get("/playlists/{playlist_id}/search", response_model=SearchResult)
async def search_playlist(playlist_id: str, q: str = Query("")):
    data = await load_playlist(playlist_id)
    if not data:
        raise HTTPException(404, "Playlist not in active session")

    query = q.lower().strip()
    tracks = []
    for t in data.get("tracks", []):
        if query and query not in t["name"].lower() and query not in t["artist"].lower():
            continue
        tracks.append(await _track_with_status(t))
    return SearchResult(tracks=tracks)


@router.delete("/playlists/{playlist_id}")
async def remove_playlist(playlist_id: str):
    await delete_playlist(playlist_id)
    return {"ok": True}
