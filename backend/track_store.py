import asyncio
import json
import os
from pathlib import Path
from typing import Literal

TrackStatus = Literal["queued", "downloading", "ready", "failed"]

_lock = asyncio.Lock()
_status: dict[str, TrackStatus] = {}
_paths: dict[str, str] = {}
_meta: dict[str, dict] = {}
_loaded = False


def _state_path() -> Path:
    base = Path(os.getenv("DATA_DIR", Path(__file__).resolve().parent / "data"))
    base.mkdir(parents=True, exist_ok=True)
    return base / "tracks.json"


def _load_sync():
    global _status, _paths, _meta, _loaded
    if _loaded:
        return
    path = _state_path()
    if path.exists():
        try:
            raw = json.loads(path.read_text())
            _status = raw.get("status", {}) or {}
            _paths = raw.get("paths", {}) or {}
            _meta = raw.get("meta", {}) or {}
        except Exception:
            _status, _paths, _meta = {}, {}, {}
    _loaded = True


def _save_sync():
    path = _state_path()
    path.write_text(json.dumps({
        "status": _status,
        "paths": _paths,
        "meta": _meta,
    }, indent=2))


async def init_store():
    async with _lock:
        _load_sync()


async def get_status(track_id: str) -> TrackStatus | None:
    async with _lock:
        _load_sync()
        return _status.get(track_id)


async def set_status(track_id: str, status: TrackStatus):
    async with _lock:
        _load_sync()
        _status[track_id] = status
        _save_sync()


async def get_path(track_id: str) -> str | None:
    async with _lock:
        _load_sync()
        return _paths.get(track_id)


async def set_path(track_id: str, path: str):
    async with _lock:
        _load_sync()
        _paths[track_id] = path
        _save_sync()


def clear_path_sync(track_id: str):
    _load_sync()
    _paths.pop(track_id, None)
    _save_sync()


async def clear_path(track_id: str):
    async with _lock:
        _load_sync()
        _paths.pop(track_id, None)
        _save_sync()


async def get_meta(track_id: str) -> dict | None:
    async with _lock:
        _load_sync()
        return _meta.get(track_id)


async def set_meta(track_id: str, artist: str, title: str, duration_ms: int):
    async with _lock:
        _load_sync()
        _meta[track_id] = {
            "artist": artist,
            "title": title,
            "duration_ms": duration_ms,
        }
        _save_sync()


async def batch_status(track_ids: list[str]) -> dict[str, TrackStatus]:
    async with _lock:
        _load_sync()
        result = {}
        for tid in track_ids:
            s = _status.get(tid)
            if s:
                result[tid] = s
        return result
