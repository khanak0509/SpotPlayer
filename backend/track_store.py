import asyncio
from typing import Literal

TrackStatus = Literal["queued", "downloading", "ready", "failed"]

_lock = asyncio.Lock()
_status: dict[str, TrackStatus] = {}
_paths: dict[str, str] = {}
_meta: dict[str, dict] = {}


async def get_status(track_id: str) -> TrackStatus | None:
    return _status.get(track_id)


async def set_status(track_id: str, status: TrackStatus):
    async with _lock:
        _status[track_id] = status


async def get_path(track_id: str) -> str | None:
    return _paths.get(track_id)


async def set_path(track_id: str, path: str):
    async with _lock:
        _paths[track_id] = path


def clear_path_sync(track_id: str):
    _paths.pop(track_id, None)


async def clear_path(track_id: str):
    async with _lock:
        _paths.pop(track_id, None)


async def get_meta(track_id: str) -> dict | None:
    return _meta.get(track_id)


async def set_meta(track_id: str, artist: str, title: str, duration_ms: int):
    async with _lock:
        _meta[track_id] = {
            "artist": artist,
            "title": title,
            "duration_ms": duration_ms,
        }


async def batch_status(track_ids: list[str]) -> dict[str, TrackStatus]:
    result = {}
    for tid in track_ids:
        s = _status.get(tid)
        if s:
            result[tid] = s
    return result
